import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turning a still a quarter turn, the way Preview and Finder do it.
enum ImageRotation {

    enum Failure: LocalizedError {
        case unreadable
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "This file couldn't be read."
            case .unsupported(let ext):
                let name = ext.isEmpty ? "This format" : ".\(ext) files"
                return "\(name) can't be rotated."
            }
        }
    }

    /// Rotates the picture at `url` 90° clockwise, in place.
    ///
    /// For anything carrying an orientation tag — JPEG, HEIC, TIFF — only that
    /// tag changes and the pixels are copied across untouched. That's what
    /// makes it lossless: rotate a JPEG four times and you have the picture you
    /// started with, not four rounds of re-compression. `ImageDecoder` already
    /// asks ImageIO to apply the tag while decoding, so the page shows the new
    /// orientation as soon as it reloads.
    ///
    /// Formats with nowhere to record a tag, PNG chief among them, are redrawn
    /// rotated instead — otherwise writing the tag would succeed and the
    /// picture would come back the same way up.
    static func rotateClockwise(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              CGImageSourceGetCount(source) > 0 else {
            throw Failure.unreadable
        }

        let data = carriesOrientation(type)
            ? try retagged(source: source, type: type, extension: url.pathExtension)
            : try redrawn(source: source, type: type, extension: url.pathExtension)

        try write(data, to: url)
    }

    // MARK: - Lossless path

    private static func retagged(source: CGImageSource, type: CFString, extension ext: String) throws -> Data {
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let current = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let turned = quarterTurn(from: current)

        if let copied = copyingImageData(source: source, type: type, orientation: turned) {
            return copied
        }
        return try reencoded(source: source, type: type, orientation: turned, extension: ext)
    }

    /// Replaces the orientation and copies the encoded image across untouched.
    ///
    /// `CGImageDestinationCopyImageSource` is the only route that leaves the
    /// compressed data alone — adding the image back frame by frame decodes and
    /// re-encodes it, so four turns of a JPEG come back visibly softer than
    /// they went in.
    private static func copyingImageData(
        source: CGImageSource,
        type: CFString,
        orientation: UInt32
    ) -> Data? {
        let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let metadata = existing.flatMap { CGImageMetadataCreateMutableCopy($0) }
            ?? CGImageMetadataCreateMutable()

        guard CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyTIFFOrientation,
            orientation as CFNumber
        ) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            error?.release()
            return nil
        }
        return output as Data
    }

    /// Fallback for anything `CGImageDestinationCopyImageSource` refuses.
    private static func reencoded(
        source: CGImageSource,
        type: CFString,
        orientation: UInt32,
        extension ext: String
    ) throws -> Data {
        let count = CGImageSourceGetCount(source)
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyOrientation] = orientation
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else {
            throw Failure.unsupported(ext)
        }
        // Every frame is carried over, so an animation doesn't get flattened.
        for index in 0..<count {
            CGImageDestinationAddImageFromSource(
                destination,
                source,
                index,
                index == 0 ? properties as CFDictionary : nil
            )
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure.unsupported(ext) }
        return output as Data
    }

    /// The EXIF orientation you land on after a quarter turn clockwise.
    ///
    /// Eight values rather than four because half of them are mirrored, and a
    /// mirrored picture turns the other way round the cycle.
    private static func quarterTurn(from orientation: UInt32) -> UInt32 {
        switch orientation {
        case 1: return 6
        case 2: return 7
        case 3: return 8
        case 4: return 5
        case 5: return 2
        case 6: return 3
        case 7: return 4
        case 8: return 1
        default: return 6
        }
    }

    private static func carriesOrientation(_ type: CFString) -> Bool {
        guard let type = UTType(type as String) else { return false }
        return type.conforms(to: .jpeg)
            || type.conforms(to: .tiff)
            || type.conforms(to: .heic)
            || type.conforms(to: .heif)
    }

    // MARK: - Redraw path

    private static func redrawn(source: CGImageSource, type: CFString, extension ext: String) throws -> Data {
        // Applies whatever orientation the file claims first, so the rotation
        // is a quarter turn from what's on screen rather than from the raw
        // pixels behind it.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }

        // Turning a quarter turn swaps the sides.
        let width = image.height
        let height = image.width
        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.unsupported(ext)
        }

        // Core Graphics counts anticlockwise from the bottom-left, so a
        // clockwise turn is a negative angle, and the canvas has to be pushed
        // up by its own height first to bring the result back into view.
        context.translateBy(x: 0, y: CGFloat(height))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))

        guard let rotated = context.makeImage() else { throw Failure.unsupported(ext) }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            throw Failure.unsupported(ext)
        }
        CGImageDestinationAddImage(destination, rotated, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unsupported(ext) }
        return output as Data
    }

    /// Ceiling for the redraw path, matching `ImageDecoder`'s.
    private static let maximumEdge: CGFloat = 4096

    // MARK: - Writing

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // An atomic write puts a temporary file next to the original, which
            // needs write access to the enclosing folder. Opening single files
            // rather than a folder only gets the sandbox those files, so fall
            // back to writing over the original.
            try data.write(to: url)
        }
    }
}
