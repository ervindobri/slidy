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

## Old camcorder and digicam footage

macOS dropped its Motion JPEG and other legacy QuickTime decoders in Catalina.
Files from mid-2000s digital cameras are often Motion JPEG A video with µ-Law
audio: AVFoundation still parses the container and plays the audio, but there is
no decoder for the picture. Slidy reports this on the page rather than showing a
black screen, but the file genuinely cannot be played and has to be transcoded.
