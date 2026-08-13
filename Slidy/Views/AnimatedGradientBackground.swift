import SwiftUI

/// A slow wash of coloured light drifting behind the empty state.
///
/// Big soft circles on separate orbits, blurred together into one moving
/// gradient. Each blob gets its own speed and phase so the arrangement never
/// visibly repeats, and the whole thing is rendered offscreen in one pass —
/// blurring at this radius is much cheaper composited once than per layer.
struct AnimatedGradientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    
    private struct Blob {
        let color: Color
        /// Diameter, as a fraction of the view's smaller edge.
        let size: CGFloat
        /// Where it sits when the drift is at zero.
        let anchor: UnitPoint
        /// How far it wanders, as a fraction of the view's size.
        let travel: CGSize
        /// Radians per second.
        let speed: Double
        /// Keeps the blobs off each other's rhythm.
        let phase: Double
        
    }

    private static let blobs: [Blob] = [
        Blob(color: Color(red: 0.85, green: 0.15, blue: 0.55), size: 1.05,
             anchor: UnitPoint(x: 0.22, y: 0.28), travel: CGSize(width: 0.18, height: 0.14),
             speed: 3*0.140, phase: 0.0),
        Blob(color: Color(red: 0.30, green: 0.25, blue: 0.95), size: 1.20,
             anchor: UnitPoint(x: 0.78, y: 0.32), travel: CGSize(width: 0.16, height: 0.18),
             speed: 3*0.105, phase: 1.7),
        Blob(color: Color(red: 0.00, green: 0.70, blue: 0.85), size: 0.95,
             anchor: UnitPoint(x: 0.68, y: 0.76), travel: CGSize(width: 0.20, height: 0.12),
             speed: 3*0.170, phase: 3.1),
        Blob(color: Color(red: 0.95, green: 0.45, blue: 0.10), size: 0.80,
             anchor: UnitPoint(x: 0.28, y: 0.80), travel: CGSize(width: 0.15, height: 0.16),
             speed: 3*0.125, phase: 4.6),
        Blob(color: Color(red: 0.55, green: 0.10, blue: 0.90), size: 0.70,
             anchor: UnitPoint(x: 0.50, y: 0.50), travel: CGSize(width: 0.22, height: 0.20),
             speed: 3*0.195, phase: 2.3)
    ]

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                // Still colourful, just not moving.
                wash(in: proxy.size, time: 0)
            } else {
                // 30fps is indistinguishable at this speed and halves the GPU
                // cost of re-blurring the whole screen every frame.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    wash(in: proxy.size, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .background(.black)
        .clipped()
        .allowsHitTesting(false)
    }

    private func wash(in size: CGSize, time: TimeInterval) -> some View {
        let shortEdge = min(size.width, size.height)

        return ZStack {
            ForEach(Self.blobs.indices, id: \.self) { index in
                let blob = Self.blobs[index]
                let diameter = shortEdge * blob.size
                // Two different frequencies per axis trace a lazy figure-eight
                // rather than a circle, which reads as less mechanical.
                let dx = cos(time * blob.speed + blob.phase) * size.width * blob.travel.width
                let dy = sin(time * blob.speed * 1.31 + blob.phase * 0.7) * size.height * blob.travel.height

                Circle()
                    .fill(blob.color)
                    .frame(width: diameter, height: diameter)
                    .position(
                        x: size.width * blob.anchor.x + dx,
                        y: size.height * blob.anchor.y + dy
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: shortEdge * 0.22)
        // One offscreen pass for the whole stack instead of blurring each blob.
        .drawingGroup(opaque: false)
        .opacity(0.55)
    }
}

#Preview {
    AnimatedGradientBackground()
        .frame(width: 700, height: 500)
}
