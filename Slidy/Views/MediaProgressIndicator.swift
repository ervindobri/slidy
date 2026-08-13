import SwiftUI

/// Bottom-of-screen position indicator.
///
/// Short sets get one segment per item; longer sets collapse to a continuous
/// track so the segments never turn into slivers.
struct MediaProgressIndicator: View {
    let index: Int
    let count: Int

    private static let segmentLimit = 12
    
    @Namespace private var namespace

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer{
                VStack(spacing: 9) {
                    if count <= Self.segmentLimit {
                        segments
                    } else {
                        track
                    }
                    
                    Text("\(index + 1) / \(count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .glassEffect()
                .glassEffectUnion(id: "id", namespace: namespace)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
                .animation(.easeInOut(duration: 0.2), value: count)
            }
        }
        else {
            VStack(spacing: 9) {
                if count <= Self.segmentLimit {
                    segments
                } else {
                    track
                }
                
                Text("\(index + 1) / \(count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
            .animation(.easeInOut(duration: 0.2), value: count)
        }
    }

    private var segments: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: position == index ? 22 : 7, height: 4)
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(index + 1) / CGFloat(max(count, 1))
            ZStack(alignment: .leading) {
                unfilledTrack
                Capsule()
                    .fill(.white)
                    .frame(width: max(14, proxy.size.width * fraction))
            }
        }
        .frame(width: 200, height: 4)
    }

    /// The unfilled part of the track, with Liquid Glass where it exists.
    /// The availability check has to name every platform — `macOS 26.0, *`
    /// alone still lets the call through on iOS 17 and fails to build there.
    @ViewBuilder
    private var unfilledTrack: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(.white.opacity(0.22))
                .glassEffect()
        } else {
            Capsule()
                .fill(.white.opacity(0.22))
        }
    }
}

#Preview("Segments") {
    MediaProgressIndicator(index: 2, count: 6)
        .padding(40)
        .background(.black)
}

#Preview("Track") {
    MediaProgressIndicator(index: 17, count: 42)
        .padding(40)
        .background(.black)
}
