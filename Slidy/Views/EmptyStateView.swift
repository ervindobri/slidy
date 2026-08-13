import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What you see before anything is open.
struct EmptyStateView<Actions: View>: View {
    let isDropTargeted: Bool
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: isDropTargeted ? "square.and.arrow.down" : "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .ultraLight))
                .foregroundStyle(.white.opacity(isDropTargeted ? 0.95 : 0.55))
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 7) {
                Text("Slidy")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            // Side by side when there's room, stacked when there isn't. Without
            // this the two pills overflow iPhone width and SwiftUI compresses
            // their labels until the text wraps one letter per line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    actions()
                }
                VStack(spacing: 12) {
                    actions()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(isDropTargeted ? 0.5 : 0), lineWidth: 2)
                .padding(22)
        }
        .background {
            AnimatedGradientBackground()
                .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.18), value: isDropTargeted)
    }

    /// Dropping is only worth mentioning where there's something to drop from.
    private var prompt: String {
        #if os(macOS)
        "Drop photos/videos here, or open a folder."
        #else
        UIDevice.current.userInterfaceIdiom == .pad
            ? "Drop photos or videos here, or open a folder."
            : "Open photos or videos to start."
        #endif
    }
}

/// The pill-shaped buttons used on the empty screen.
struct CapsuleActionLabel: View {
    let title: String
    let systemImage: String
    // Optional closure variable (defaults to nil)
    var onPressed: ((() -> Void))? = nil
    @Namespace private var namespace

    var body: some View {
        // Every platform has to be named here: `macOS 26.0, *` alone still lets
        // the glass calls through on iOS 17 and fails to build there.
        if #available(macOS 26.0, iOS 26.0, *) {
            pill.padding(16.0).buttonStyle(.liquidGlass)
        } else {
            pill
        }
    }

    private var pill: some View {
        
                        Button(action: {
                        
                            withAnimation {
                                onPressed?()
                            }
                          }, label: {
                              HStack(spacing: 12.0) {
                                  
                              
                              Image(systemName: systemImage)
                                  .frame(width: 24, height: 24)
                              Text(title)
                                  .lineLimit(1)
                                  .fixedSize(horizontal: true, vertical: false)
                              }
                              
                          })
                        .focusable(false)
                        .border(FillShapeStyle(), width: 0.0)
                        .padding(12.0)
                        .cornerRadius(99.0)
                    
    }
}

#Preview {
    EmptyStateView(isDropTargeted: false) {
        if #available(macOS 26.0, iOS 26.0, *) {
            CapsuleActionLabel(title: "Open Files", systemImage: "folder", onPressed: {})
        } else {
            CapsuleActionLabel(title: "Open Files", systemImage: "folder", onPressed: {})
        }
    }
    .background(.black)
}
