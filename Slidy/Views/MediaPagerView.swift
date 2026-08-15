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

    private let metrics = CarouselMetrics.current

    /// How many cards make up a half turn of the arc. Fixed rather than taken
    /// from the number of open files, so the stack looks the same whether you
    /// opened five photos or five hundred.
    private let spread = 15.0

    /// How far a card shrinks and darkens per place from the middle.
    private let scalePerStep = 0.16
    private let dimPerStep = 0.18

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.size.width * metrics.radiusRatio(spread: spread)
            let cardWidth = proxy.size.width * metrics.cardWidthRatio
            let cardHeight = proxy.size.height * metrics.cardHeightRatio

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

    /// How far you have to drag to move one card along. Scaled to the card, not
    /// the screen: a near-full-width card that jumps on a 50pt flick feels like
    /// it's slipping out from under your thumb.
    private func dragLength(_ width: CGFloat) -> CGFloat {
        max(1, width * metrics.dragRatio)
    }

    // MARK: - Contents

    private var lastIndex: Double { Double(max(0, library.items.count - 1)) }

    /// Only the cards near the middle, paired with their real indices.
    private func visibleItems() -> [(offset: Int, element: MediaItem)] {
        guard !library.items.isEmpty else { return [] }
        let middle = Int(draggingItem.rounded())
        let lower = max(0, middle - metrics.reach)
        let upper = min(library.items.count - 1, middle + metrics.reach)
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

/// How the stack is proportioned, which can't be the same on both platforms: a
/// Mac window is wide enough to show a real stack of cards behind the current
/// one, a phone held in the hand is not. There the current photo is the view,
/// and its neighbours are slivers at the edges that say which way to swipe.
struct CarouselMetrics {

    /// How much of the view the middle card takes up.
    var cardWidthRatio: CGFloat
    var cardHeightRatio: CGFloat

    /// Centre-to-centre distance between neighbouring cards, as a fraction of
    /// the view's width. This is the number that decides how much of the next
    /// card you see, so it's set directly rather than dialled in through the
    /// radius of the arc the cards sit on.
    var neighbourStep: CGFloat

    /// How far you drag to move one card along, as a fraction of the width.
    var dragRatio: CGFloat

    /// How many cards either side get built. Anything further out is off screen,
    /// and each one costs a decoded image.
    var reach: Int

    static var current: CarouselMetrics {
        #if os(macOS)
        // The stack as it was: a wide card with its neighbours fanned out behind.
        CarouselMetrics(
            cardWidthRatio: 0.62,
            cardHeightRatio: 0.72,
            neighbourStep: 0.138,
            dragRatio: 0.14,
            reach: 3
        )
        #else
        // 0.90 wide, with the neighbour pushed just far enough out that only its
        // near edge clears the current card:
        //   half of this card (0.45) + half of the next, shrunk one step
        //   (0.45 × 0.84 = 0.378) ≈ 0.83, less a little so it isn't flush.
        CarouselMetrics(
            cardWidthRatio: 0.90,
            // Tall enough to fill the gap between the bars, which overlay the
            // card's corners rather than sitting above and below it.
            cardHeightRatio: 0.74,
            neighbourStep: 0.80,
            dragRatio: 0.32,
            reach: 2
        )
        #endif
    }

    /// The arc's radius, solved backwards from where the neighbouring card is
    /// wanted: the card one place out sits at `sin(2π / spread) × radius`.
    func radiusRatio(spread: Double) -> CGFloat {
        neighbourStep / CGFloat(sin(.pi * 2 / spread))
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
