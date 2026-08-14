import AVFoundation
import AVKit
import SwiftUI

// AVKit is linked explicitly in the target's Frameworks phase, not left to
// autolinking. Without it the binary picks up only the _AVKit_SwiftUI overlay,
// AVPlayerView has no class at runtime, and VideoPlayer dies building its
// metadata — audio keeps playing while nothing is drawn. Don't remove the link.

/// One video. Plays only while it is the page on screen.
///
/// Loops on its own normally; during a slideshow it plays through once and
/// hands over to the next page.
struct VideoPageView: View {
    let item: MediaItem
    let isCurrent: Bool

    @Environment(MediaLibrary.self) private var library
    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var failure: String?
    @State private var conversion: ConversionState = .idle

    /// Where a file that won't play is in the process of becoming one that will.
    private enum ConversionState: Equatable {
        case idle
        case running(Double)
        case failed(String)

        var isRunning: Bool { if case .running = self { return true }; return false }
    }

    var body: some View {
        ZStack {
            if failure != nil {
                unplayable
            } else {
                VideoPlayer(player: player)
            }
        }
        // No padding or background of its own: the carousel card supplies the
        // surface and the rounded shape, and the video fills it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.url) { await prepare() }
        .task(id: playerItem) { await watch() }
        // A clip that can't play has no end to wait for, so give it the same
        // dwell as a still rather than stalling the slideshow on it. A
        // conversion in progress holds the page instead — skipping away from
        // something the viewer just asked for would be rude.
        .task(id: "\(failure != nil)-\(isCurrent)-\(library.isSlideshowRunning)-\(conversion.isRunning)") {
            guard failure != nil, !conversion.isRunning else { return }
            guard library.currentID == item.id, library.isSlideshowRunning else { return }
            try? await Task.sleep(for: Duration.seconds(MediaLibrary.stillSeconds))
            guard !Task.isCancelled else { return }
            library.advanceSlideshow()
        }
        .onDisappear { player.pause() }
        .onChange(of: isCurrent) { syncPlayback() }
    }

    // MARK: - Can't play

    /// The failure page, with the offer to convert.
    private var unplayable: some View {
        VStack(spacing: 20) {
            UnreadableMediaView(name: item.displayName, detail: failure)

            switch conversion {
            case .running(let fraction):
                VStack(spacing: 10) {
                    ProgressView(value: fraction > 0 ? fraction : nil, total: 1)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                    Text(fraction > 0 ? "Converting… \(Int(fraction * 100))%" : "Converting…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            case .failed(let reason):
                VStack(spacing: 10) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    convertButton(title: "Try Again")
                }
            case .idle:
                convertButton(title: "Convert to MP4")
            }
        }
        .tint(.white)
    }

    private func convertButton(title: String) -> some View {
        Button(title) { Task { await runConversion() } }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Re-encode a copy that this device can play. The original isn't touched.")
    }

    /// Converts the file and shows the result in place.
    ///
    /// The conversion is written to Slidy's own container, so the original —
    /// which we only ever have read access to — is left exactly as it was.
    private func runConversion() async {
        guard !conversion.isRunning else { return }
        conversion = .running(0)

        let source = item.url
        // Report progress through the binding rather than capturing the view:
        // the encoder calls back from its own queue, and this way nothing but
        // the state box crosses over.
        let state = $conversion
        do {
            let converted = try await VideoConverter.convert(source: source) { fraction in
                Task { @MainActor in
                    // A late callback must not reopen the panel after the
                    // conversion has finished and been swapped in.
                    if case .running = state.wrappedValue { state.wrappedValue = .running(fraction) }
                }
            }
            conversion = .idle
            library.useConverted(converted, for: item.id)
        } catch is CancellationError {
            conversion = .idle
        } catch {
            conversion = .failed(error.localizedDescription)
        }
    }

    // MARK: - Playback

    /// Loads the asset before handing it to the player.
    ///
    /// The tracks and duration have to be loaded first: building a player item
    /// straight from a URL and playing it immediately leaves AVFoundation
    /// working with an asset it hasn't parsed, which some files survive and
    /// others don't. Loading up front also lets us say *why* a file won't play
    /// instead of showing a black page.
    private func prepare() async {
        failure = nil
        do {
            let asset = AVURLAsset(url: item.url)
            let (isPlayable, tracks) = try await asset.load(.isPlayable, .tracks)

            guard isPlayable else {
                await reportUnplayable("This file isn't playable on this device.")
                return
            }
            guard tracks.contains(where: { $0.mediaType == .video }) else {
                failure = "This file has no video track."
                return
            }

            let newItem = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: newItem)
            player.actionAtItemEnd = .none
            playerItem = newItem
            syncPlayback()

            // Started playing already, so a normal clip never waits on this.
            // The check matters for files that open and play their audio while
            // the picture stays black — nothing before this point notices.
            let url = item.url
            if await !VideoConverter.canDecodePicture(at: url) {
                guard url == item.url else { return }
                player.pause()
                await reportUnplayable("This device has no decoder for this video's format.")
            }
        } catch {
            await reportUnplayable(error.localizedDescription)
        }
    }

    /// Shows the failure — unless this file has been converted before, in which
    /// case the conversion is swapped in silently. Converting is only asked
    /// about once per file; every time after that it just plays.
    private func reportUnplayable(_ reason: String) async {
        if let existing = VideoConverter.existingConversion(of: item.url) {
            library.useConverted(existing, for: item.id)
            return
        }
        failure = reason
    }

    /// Loops at the end of the clip, and reports decode failures, which surface
    /// during playback rather than at load time.
    private func watch() async {
        guard let playerItem else { return }
        let center = NotificationCenter.default

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                let ended = center.notifications(named: .AVPlayerItemDidPlayToEndTime, object: playerItem)
                for await _ in ended {
                    // Ask the library, don't trust the captured `isCurrent`:
                    // this closure holds the view value from whenever the task
                    // started, and the pager builds neighbouring pages while
                    // they are not current, so that snapshot can be stale.
                    guard library.currentID == item.id else { continue }
                    if library.isSlideshowRunning {
                        // The clip has had its turn — the whole clip is its
                        // dwell time, however long that is.
                        library.advanceSlideshow()
                    } else {
                        await player.seek(to: .zero)
                        player.play()
                    }
                }
            }
            group.addTask { @MainActor in
                let failed = center.notifications(named: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
                for await note in failed {
                    let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    await reportUnplayable(error?.localizedDescription ?? "This video stopped playing.")
                }
            }
        }
    }

    private func syncPlayback() {
        guard failure == nil else { return }
        if isCurrent {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
        }
    }
}
