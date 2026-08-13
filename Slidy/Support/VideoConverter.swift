import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import MediaToolSwift

/// Turns a video this device can't play into an H.264 MP4 it can.
///
/// Two paths, tried in order:
///
/// 1. **MediaToolSwift**, which drives `AVAssetReader`/`AVAssetWriter` with
///    VideoToolbox. This is the path for anything the system can decode but
///    won't play well — odd containers, exotic profiles, unusual pixel formats.
/// 2. **Frame-by-frame**, for files the system has no decoder for at all.
///    See ``transcodeFrameByFrame(source:destination:onProgress:)``.
///
/// Results are cached, so a file is only ever converted once.
enum VideoConverter {

    // MARK: - Cache

    /// Where converted files live: Application Support, not Caches, because
    /// re-encoding a clip is expensive enough that we don't want the system
    /// throwing the result away between launches.
    private static func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Slidy/Converted", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A stable name for `source`'s conversion.
    ///
    /// Keyed on the path, size and modification date, so replacing a file with
    /// a different one of the same name doesn't serve up the old conversion.
    private static func destination(for source: URL) throws -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        let fingerprint = "\(source.standardizedFileURL.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()

        let stem = source.deletingPathExtension().lastPathComponent
        return try cacheDirectory().appendingPathComponent("\(stem)-\(hash).mp4")
    }

    /// The finished conversion of `source`, if it has already been made.
    static func existingConversion(of source: URL) -> URL? {
        guard let destination = try? destination(for: source),
              FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

    // MARK: - Converting

    /// Converts `source`, reporting progress from 0 to 1.
    ///
    /// Returns immediately with the existing file if it has been converted
    /// before. `onProgress` is called from whichever queue the encoder happens
    /// to be on — hop to the main actor yourself if you're driving UI with it.
    @discardableResult
    static func convert(
        source: URL,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let destination = try destination(for: source)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        // Write to a scratch file and move it into place at the end, so an
        // interrupted conversion can't leave a truncated file behind that later
        // looks like a finished one.
        let scratch = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial.mp4")
        try? FileManager.default.removeItem(at: scratch)

        var primaryFailure: Error?
        do {
            try await runMediaTool(source: source, destination: scratch, onProgress: onProgress)
            try commit(scratch, to: destination, matching: source)
            return destination
        } catch {
            primaryFailure = error
        }

        try? FileManager.default.removeItem(at: scratch)
        try Task.checkCancellation()

        do {
            try await transcodeFrameByFrame(source: source, destination: scratch, onProgress: onProgress)
            try commit(scratch, to: destination, matching: source)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: scratch)
            throw VideoConversionError.bothPathsFailed(primary: primaryFailure, fallback: error)
        }
    }

    /// Moves the finished scratch file into place, carrying the original's
    /// timestamps so the clip keeps its position among the photos around it.
    private static func commit(_ scratch: URL, to destination: URL, matching source: URL) throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: source.path) {
            var keep: [FileAttributeKey: Any] = [:]
            if let created = attributes[.creationDate] { keep[.creationDate] = created }
            if let modified = attributes[.modificationDate] { keep[.modificationDate] = modified }
            try? FileManager.default.setAttributes(keep, ofItemAtPath: scratch.path)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: scratch, to: destination)
    }

    // MARK: - Path 1: MediaToolSwift

    private static func runMediaTool(
        source: URL,
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // The callback can fire before we get around to reading from it — an
        // unstarted conversion reports `.failed` synchronously — so states go
        // into a buffered stream rather than a continuation we might miss.
        var sink: AsyncStream<CompressionState>.Continuation!
        let states = AsyncStream<CompressionState>(bufferingPolicy: .unbounded) { sink = $0 }
        let states_ = sink!

        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            fileType: .mp4,
            videoSettings: CompressionVideoSettings(codec: .h264, quality: 0.85),
            optimizeForNetworkUse: true,
            skipAudio: false,
            audioSettings: CompressionAudioSettings(codec: .aac),
            overwrite: true,
            callback: { states_.yield($0) }
        )

        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            onProgress(progress.fractionCompleted)
        }
        defer {
            observation.invalidate()
            states_.finish()
        }

        for await state in states {
            switch state {
            case .started:
                continue
            case .completed:
                return
            case .failed(let error):
                throw error
            case .cancelled:
                throw CancellationError()
            }
        }
        throw VideoConversionError.stoppedEarly
    }

    // MARK: - Path 2: frame by frame

    /// Transcodes by pulling compressed frames out and decoding them ourselves.
    ///
    /// macOS and iOS dropped their Motion JPEG decoders, so `AVAssetReader`
    /// refuses to decompress these files — which is what MediaToolSwift and
    /// every other AVFoundation-based converter needs it to do. AVFoundation
    /// can still *demux* the file though, and Motion JPEG frames are ordinary
    /// JPEGs, so we ask the reader for the samples untouched (`outputSettings:
    /// nil`), decode each one with ImageIO, and hand the pixels to VideoToolbox
    /// to re-encode. Audio goes the normal way — µ-Law is still supported.
    private static func transcodeFrameByFrame(
        source: URL,
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConversionError.noVideoTrack
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        let (naturalSize, transform, frameRate) = try await videoTrack.load(
            .naturalSize, .preferredTransform, .nominalFrameRate
        )
        let size = CGSize(
            width: abs(naturalSize.width.rounded()),
            height: abs(naturalSize.height.rounded())
        )
        guard size.width >= 1, size.height >= 1 else {
            throw VideoConversionError.noVideoTrack
        }

        let duration = try await asset.load(.duration).seconds
        let expectedFrames = frameRate > 0 && duration.isFinite
            ? Int((duration * Double(frameRate)).rounded())
            : 0

        // One reader per track. Sharing a reader between the two outputs
        // deadlocks: it won't advance past its internal buffer while an output
        // is being read at a different rate.
        let videoReader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard videoReader.canAdd(videoOutput) else {
            throw VideoConversionError.unreadable("The video track can't be read.")
        }
        videoReader.add(videoOutput)

        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            if reader.canAdd(output) {
                reader.add(output)
                audioReader = reader
                audioOutput = output
            }
        }

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate(for: size, frameRate: frameRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(videoInput) else {
            throw VideoConversionError.unreadable("The video track can't be written.")
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: audioBitRate
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard videoReader.startReading() else {
            throw videoReader.error ?? VideoConversionError.unreadable("The file couldn't be read.")
        }
        audioReader?.startReading()
        guard writer.startWriting() else {
            throw writer.error ?? VideoConversionError.unreadable("The file couldn't be written.")
        }
        writer.startSession(atSourceTime: .zero)

        // Both inputs have to be pumped at the same time. The writer interleaves
        // the tracks as it goes and stops marking one input ready while the
        // other lags, so draining video first and audio afterwards deadlocks.
        let tally = FrameTally()
        async let video: Void = drain(output: videoOutput, into: videoInput, label: "video") { sample in
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard let image = decodeJPEGFrame(sample),
                  let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool, size: size) else {
                tally.countSkipped()
                return
            }
            adaptor.append(buffer, withPresentationTime: time)
            let written = tally.countWritten()
            if expectedFrames > 0 {
                onProgress(min(1, Double(written) / Double(expectedFrames)))
            }
        }

        async let audio: Void = {
            guard let audioOutput, let audioInput else { return }
            await drain(output: audioOutput, into: audioInput, label: "audio", handle: nil)
        }()

        _ = await (video, audio)

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? VideoConversionError.unreadable("The conversion didn't finish.")
        }
        guard tally.written > 0 else {
            throw VideoConversionError.noDecodableFrames
        }
        onProgress(1)
    }

    /// Pumps every sample of one reader output into one writer input.
    ///
    /// This has to go through `requestMediaDataWhenReady`. Polling
    /// `isReadyForMoreMediaData` in a plain loop spins forever, because the
    /// writer only starts driving that flag once the callback is installed.
    private static func drain(
        output: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        label: String,
        handle: ((CMSampleBuffer) -> Void)?
    ) async {
        let queue = DispatchQueue(label: "com.ervindobri.Slidy.convert.\(label)")
        let resumed = OneShot()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        // The callback can fire once more after we finish; only
                        // the first one gets to resume the continuation.
                        if resumed.claim() { continuation.resume() }
                        return
                    }
                    if let handle {
                        handle(sample)
                    } else {
                        input.append(sample)
                    }
                }
            }
        }
    }

    // MARK: - Frame plumbing

    private static let audioSampleRate = 44_100.0
    private static let audioBitRate = 96_000

    /// Generous but bounded: these are short clips off old cameras, and a
    /// visible re-encode artefact is worse than a few extra megabytes.
    private static func bitRate(for size: CGSize, frameRate: Float) -> Int {
        let fps = frameRate > 0 ? Double(frameRate) : 30
        let estimate = size.width * size.height * fps * 0.7
        return Int(min(max(estimate, 4_000_000), 40_000_000))
    }

    private static func decodeJPEGFrame(_ sample: CMSampleBuffer) -> CGImage? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { return nil }

        guard let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Errors

enum VideoConversionError: LocalizedError {
    case noVideoTrack
    case noDecodableFrames
    case stoppedEarly
    case unreadable(String)
    case bothPathsFailed(primary: Error?, fallback: Error?)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "This file has no video track to convert."
        case .noDecodableFrames:
            return "None of this file's frames could be decoded."
        case .stoppedEarly:
            return "The converter stopped without finishing."
        case .unreadable(let detail):
            return detail
        case .bothPathsFailed(let primary, let fallback):
            let reason = (fallback ?? primary)?.localizedDescription
            return reason ?? "This file couldn't be converted."
        }
    }
}

// MARK: - Small shared state

/// Frame counts, written from the encoder queue and read once draining ends.
private final class FrameTally: @unchecked Sendable {
    private let lock = NSLock()
    private var _written = 0
    private var _skipped = 0

    var written: Int { lock.withLock { _written } }

    @discardableResult
    func countWritten() -> Int { lock.withLock { _written += 1; return _written } }
    func countSkipped() { lock.withLock { _skipped += 1 } }
}

/// Lets exactly one caller through, whichever gets there first.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
