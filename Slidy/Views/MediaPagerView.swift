import SwiftUI

/// The horizontal strip of pages. One media item per screen, snapping into place.
struct MediaPagerView: View {
    @Environment(MediaLibrary.self) private var library

    var body: some View {
        @Bindable var library = library

        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(library.items) { item in
                    page(for: item)
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $library.currentID)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        #if !os(macOS)
        // On macOS the arrow keys are menu commands, which would double up with these.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        #endif
    }

    @ViewBuilder
    private func page(for item: MediaItem) -> some View {
        switch item.kind {
        case .image:
            ImagePageView(item: item)
        case .video:
            VideoPageView(item: item, isCurrent: item.id == library.currentID)
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        withAnimation(.easeInOut(duration: 0.25)) {
            library.step(delta)
        }
        return .handled
    }
}

#Preview {
    MediaPagerView()
        .environment(MediaLibrary())
}
