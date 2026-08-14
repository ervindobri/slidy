import SwiftUI

/// The carousel: the current item sits in the middle at full size, with the
/// pages either side tucked in behind it, scaled down and dimmed.
///
/// Built on ChrisR's answer to "Carousel view SwiftUI":
/// https://stackoverflow.com/a/72352181 (CC BY-SA 4.0). Cards are placed around
/// an arc — the offset is the sine of the distance from the middle — so they
/// bunch up as they go back, which is what gives the stack its depth.
///
/// Position is computed from the index rather than read back from a scroll
/// view. A `ScrollView` with a two-way `scrollPosition` binding fights itself
/// here: moving the position programmatically makes the binding report the
/// items it passes over, which moves the position again, and the stack settles
/// somewhere other than where it was sent.
struct MediaPagerView: View {
    @Environment(MediaLibrary.self) private var library

    @State private var snappedItem = 0.0
    @State private var draggingItem = 0.0

    /// How much of the screen the middle card takes up.
    private let cardWidthRatio: CGFloat = 0.62
    private let cardHeightRatio: CGFloat = 0.72

    /// Radius of the arc the cards are placed around.
    private let radiusRatio = 0.34

    /// How many cards make up a half turn of the arc. Fixed rather than taken
    /// from the number of open files, so the stack looks the same whether you
    /// opened five photos or five hundred.
    private let spread = 15.0

    /// How far a card shrinks and darkens per place from the middle.
    private let scalePerStep = 0.16
    private let dimPerStep = 0.18

    /// Cards beyond this are behind the stack and off screen. They aren't built
    /// at all — each one would hold a decoded image.
    private let reach = 3

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.size.width * radiusRatio
            let cardWidth = proxy.size.width * cardWidthRatio
            let cardHeight = proxy.size.height * cardHeightRatio

            ZStack {
                ForEach(visibleItems(), id: \.element.id) { index, item in
                    let offset = abs(distance(index))

                    card(for: item, width: cardWidth, height: cardHeight)
                        .scaleEffect(1.0 - offset * scalePerStep)
                        // Darkened rather than faded, which is the one place
                        // this departs from the original: photos overlap far
                        // more than flat colour tiles, and anything translucent
                        // shows the rest of the stack straight through itself.
                        .brightness(-offset * dimPerStep)
                        .offset(x: xOffset(index, radius: radius), y: 0)
                        .zIndex(1.0 - offset * 0.1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        draggingItem = snappedItem - value.translation.width / dragLength(proxy.size.width)
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            // Carried by the flick rather than where the finger
                            // stopped, then snapped to whole cards.
                            draggingItem = snappedItem - value.predictedEndTranslation.width / dragLength(proxy.size.width)
                            draggingItem = (round(draggingItem)).clamped(to: 0...lastIndex)
                            snappedItem = draggingItem
                            commit()
                        }
                    }
            )
            #if !os(macOS)
            // On macOS the arrow keys are menu commands, which would double up with these.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.rightArrow) { move(1) }
            #endif
        }
        .onAppear { sync(to: library.currentIndex) }
        // Arrow keys, the menu and the slideshow all move the library rather
        // than the carousel, so the carousel follows it.
        .onChange(of: library.currentIndex) { _, index in
            guard Int(snappedItem.rounded()) != index else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { sync(to: index) }
        }
    }

    // MARK: - Arc

    /// How many places `index` is from the middle. Fractional during a drag, so
    /// the stack follows the finger rather than jumping card to card.
    private func distance(_ index: Int) -> Double {
        Double(index) - draggingItem
    }

    private func xOffset(_ index: Int, radius: CGFloat) -> CGFloat {
        let angle = .pi * 2 / spread * distance(index)
        return sin(angle) * radius
    }

    /// How far you have to drag to move one card along.
    private func dragLength(_ width: CGFloat) -> CGFloat {
        max(1, width * 0.14)
    }

    // MARK: - Contents

    private var lastIndex: Double { Double(max(0, library.items.count - 1)) }

    /// Only the cards near the middle, paired with their real indices.
    private func visibleItems() -> [(offset: Int, element: MediaItem)] {
        guard !library.items.isEmpty else { return [] }
        let middle = Int(draggingItem.rounded())
        let lower = max(0, middle - reach)
        let upper = min(library.items.count - 1, middle + reach)
        guard lower <= upper else { return [] }
        return (lower...upper).map { ($0, library.items[$0]) }
    }

    private func card(for item: MediaItem, width: CGFloat, height: CGFloat) -> some View {
        page(for: item)
            .frame(width: width, height: height)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 22, y: 14)
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

    // MARK: - Keeping the library in step

    private func sync(to index: Int) {
        snappedItem = Double(index)
        draggingItem = snappedItem
    }

    /// Hands the settled position back to the library, which is what the title,
    /// the indicator, the slideshow and video playback all read.
    private func commit() {
        let index = Int(snappedItem)
        guard library.items.indices.contains(index) else { return }
        library.currentID = library.items[index].id
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            library.step(delta)
        }
        return .handled
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    MediaPagerView()
        .environment(MediaLibrary())
}
