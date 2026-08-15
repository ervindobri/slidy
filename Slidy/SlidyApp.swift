import SwiftUI
#if os(iOS)
import AVFoundation
#endif

@main
struct SlidyApp: App {
    @State private var library = MediaLibrary()
    @State private var recents = RecentSources()

    init() {
        #if os(iOS)
        // Media apps play through the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(recents)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Previous") {
                    withAnimation(.easeInOut(duration: 0.25)) { library.step(-1) }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!library.canStepBackward)

                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.25)) { library.step(1) }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!library.canStepForward)

                Divider()

                Button(library.isSlideshowRunning ? "Stop Slideshow" : "Play Slideshow") {
                    withAnimation(.easeInOut(duration: 0.2)) { library.toggleSlideshow() }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(library.items.count < 2)

                Divider()

                // Escape rather than ⌘W, which belongs to Close Window.
                Button("Close Media") { library.clear() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(library.isEmpty)
            }
        }
        #endif
    }

}
