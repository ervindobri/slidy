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

    var body: some View {
        
        ZStack {
            if let failure {
                UnreadableMediaView(name: item.displayName, detail: failure)
            } else {
                VideoPlayer(player: player)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 48.0, bottom: 48.0, trailing: 48.0))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: item.url) { await prepare() }
        .task(id: playerItem) { await watch() }
        // A clip that can't play has no end to wait for, so give it the same
        // dwell as a still rather than stalling the slideshow on it.
        .task(id: "\(failure != nil)-\(isCurrent)-\(library.isSlideshowRunning)") {
            guard failure != nil, library.currentID == item.id, library.isSlideshowRunning else { return }
            try? await Task.sleep(for: Duration.seconds(MediaLibrary.stillSeconds))
            guard !Task.isCancelled else { return }
            library.advanceSlideshow()
        }
        .onDisappear { player.pause() }
        .onChange(of: isCurrent) { syncPlayback() }
    }

    /// Loads the asset before handing it to the player.
    ///
    /// The tracks and duration have to be loaded first: building a player item
    /// straight from a URL and playing it immediately leaves AVFoundation
    /// working with an asset it hasn't parsed, which some files survive and
    /// others don't. Loading up front also lets us say *why* a file won't play
    /// instead of showing a black page.
    private func prepare() async {
        do {
            let asset = AVURLAsset(url: item.url)
            let (isPlayable, tracks) = try await asset.load(.isPlayable, .tracks)

            guard isPlayable else {
                failure = "This file isn't playable on this Mac."
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
        } catch {
            failure = error.localizedDescription
        }
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
                    failure = error?.localizedDescription ?? "This video stopped playing."
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
