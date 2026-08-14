# Slidy

A media viewer with one job: open images and videos and swipe through them
horizontally. Offline, no library, no editing, no accounts.

One SwiftUI target, running on iOS, iPadOS and macOS.

## Using it

Open media with **Open Files** (individual files or a whole folder), the
**Photo Library** picker on iOS/iPadOS, or by dragging files onto the window on
macOS and iPadOS. Anything in the selection that isn't an image or a video is
ignored — files are classified by their actual content type, not their
extension, so a mislabelled file can't sneak through.

- Swipe horizontally to page through. Arrow keys work on macOS (also under
  View ▸ Previous/Next) and on iPadOS with a keyboard.
- The bottom indicator shows position: one segment per item up to 12, a
  continuous track beyond that, with a `4 / 27` readout underneath.
- **Slideshow** — the play button runs through everything hands-off. Stills are
  held 3 seconds; a video plays to its own end however long it is, then hands
  over. It wraps around at the last item, and skipping manually mid-slideshow
  gives the new page a full turn. Space toggles it on macOS.
- Videos loop on their own when the slideshow isn't running, and play only
  while they're the page on screen.
- A video this device can't play offers **Convert to MP4** on its page. See
  [Old camcorder and digicam footage](#old-camcorder-and-digicam-footage).
- Escape closes the current set on macOS.

## Building

```sh
open Slidy.xcodeproj
```

Or from the command line:

```sh
xcodebuild -scheme Slidy -destination 'platform=macOS' build
xcodebuild -scheme Slidy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Deployment targets are iOS 17 and macOS 14. Liquid Glass styling is used where
the OS provides it (macOS 26 / iOS 26) and falls back cleanly below that. Set
your own team and bundle identifier under Signing & Capabilities before running
on a device.

## Layout

| Path | What's in it |
| --- | --- |
| [SlidyApp.swift](Slidy/SlidyApp.swift) | Entry point, macOS window and menu commands |
| [Models/MediaItem.swift](Slidy/Models/MediaItem.swift) | The item type, and the check that decides what counts as media |
| [Support/MediaLibrary.swift](Slidy/Support/MediaLibrary.swift) | Open set, current page, slideshow clock, security-scoped URL lifetimes |
| [Support/ImageDecoder.swift](Slidy/Support/ImageDecoder.swift) | Decodes stills at display size, one at a time |
| [Support/VideoConverter.swift](Slidy/Support/VideoConverter.swift) | Re-encodes videos this device can't play, and caches the result |
| [Support/PhotoImport.swift](Slidy/Support/PhotoImport.swift) | Copies Photos picks to temporary files (iOS/iPadOS) |
| [Views/ContentView.swift](Slidy/Views/ContentView.swift) | Screen layout, importers, drag and drop |
| [Views/MediaPagerView.swift](Slidy/Views/MediaPagerView.swift) | The paging horizontal scroll view |
| [Views/ImagePageView.swift](Slidy/Views/ImagePageView.swift) | One still |
| [Views/VideoPageView.swift](Slidy/Views/VideoPageView.swift) | One video |
| [Views/MediaProgressIndicator.swift](Slidy/Views/MediaProgressIndicator.swift) | The bottom indicator |
| [Views/EmptyStateView.swift](Slidy/Views/EmptyStateView.swift) | What you see before anything is open |
| [Views/AnimatedGradientBackground.swift](Slidy/Views/AnimatedGradientBackground.swift) | Drifting colour wash behind the empty state |

The Xcode project uses a file-system-synchronized group, so new files under
`Slidy/` are picked up without editing the project file.

One dependency, resolved by Swift Package Manager:
[MediaToolSwift](https://github.com/starkdmi/MediaToolSwift), which drives the
video conversion described below.

## Things worth knowing before changing this

A few decisions here look arbitrary but aren't. Each one cost a bug.

**AVKit is linked explicitly** in the target's Frameworks phase rather than left
to autolinking. Without it the binary picks up only the `_AVKit_SwiftUI`
overlay, `AVPlayerView` has no class at runtime, and `VideoPlayer` dies building
its metadata — audio keeps playing while nothing is drawn.

**The slideshow's clock lives in `MediaLibrary`, not in a view.** A view's
`.task(id:)` only restarts when its id changes, so if SwiftUI tears it down for
its own reasons the slideshow stops silently and never comes back.

**The dwell is a deadline, not a per-page timer.** The pager writes `currentID`
back as it settles, so anything keyed on that identity gets restarted at
unpredictable moments and can miss its turn entirely.

**`isCurrent` read inside a `.task` closure is stale.** The closure holds the
view value from whenever the task started, and the pager builds neighbouring
pages while they are not current — so the video's end-of-clip handler asks the
library which page is showing instead of trusting that snapshot.

**Stills decode through one actor.** Skipping quickly through a folder starts a
decode per page touched, each holding a display-sized bitmap; a dozen at once is
hundreds of megabytes for images nobody is looking at any more.

**The Mac icon is an `.icns`, the iOS icon is an asset catalog entry.** They
can't be the same file. macOS 26 takes an app icon from an asset catalog,
insets it into its own tile and paints a light plate behind it — which reads as
a pale ring around a dark icon, and gets worse, not better, if you pre-inset the
artwork yourself. An `.icns` referenced by `CFBundleIconFile` is used exactly as
authored, so [AppIcon.icns](Slidy/AppIcon.icns) contains the shaped artwork
(824pt body centred in a 1024pt canvas, with the shadow in the margin) and
`ASSETCATALOG_COMPILER_APPICON_NAME` is scoped to the iOS SDKs only. iOS wants
the opposite — full-bleed, no rounding — and masks it itself, which is what
`1024.png` in the asset catalog is for. Run `iconutil -c iconset
Slidy/AppIcon.icns` to get the individual Mac sizes back.

**The frame-by-frame converter deadlocks if you drain it wrong.** Three ways,
all of which look like a hang with no error: sharing one `AVAssetReader` between
the video and audio outputs; polling `isReadyForMoreMediaData` instead of going
through `requestMediaDataWhenReady`, which is what actually drives that flag;
and finishing the video track before starting the audio, when the writer
interleaves them and stops marking either input ready while the other lags.

## Old camcorder and digicam footage

macOS dropped its Motion JPEG and other legacy QuickTime decoders in Catalina.
Files from mid-2000s digital cameras are often Motion JPEG A video with µ-Law
audio: AVFoundation still parses the container and plays the audio, but there is
no decoder for the picture.

Slidy offers to convert these. The page shows **Convert to MP4**; press it and
the clip is re-encoded to H.264/AAC and starts playing in place. Your original
file is never touched — Slidy only ever has read access to it, and the
conversion is written to the app's own storage:

```
~/Library/Containers/com.ervindobri.Slidy/Data/Library/Application Support/Slidy/Converted
```

Conversions are keyed by path, size and modification date, so a file is only
converted once: reopen it later and it plays straight away, with no prompt.
Delete that folder to reclaim the space — anything in it can be made again.

Two conversion paths, tried in order:

**1. [MediaToolSwift](https://github.com/starkdmi/MediaToolSwift)**, which
handles anything the system can decode — odd containers, unusual profiles,
formats that play badly rather than not at all.

**2. Frame by frame**, for files the system has *no* decoder for. This is the
Motion JPEG case, and it's why path 1 isn't enough on its own: MediaToolSwift —
like every AVFoundation-based converter — needs `AVAssetReader` to decompress
the source, and on these files that fails outright:

```
AVFoundationErrorDomain -11833 "Cannot Decode"
The decoder required for this media cannot be found.
```

AVFoundation can still *demux* the file, though, and Motion JPEG frames are
ordinary JPEGs. So Slidy asks the reader for the samples untouched
(`outputSettings: nil`), decodes each one with ImageIO, and hands the pixels to
VideoToolbox to re-encode. Audio goes the normal way — µ-Law is still supported.

Detecting the problem needs care too. `isPlayable` doesn't answer the question:
it reports on the container, which these files pass. The only reliable test is
to ask for an actual frame, so Slidy decodes one — after playback has already
started, so a normal clip never waits on it.
