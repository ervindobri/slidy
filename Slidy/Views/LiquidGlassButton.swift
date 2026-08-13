import SwiftUI

// 1. Custom Glass Button Style with Scale Animation
@available(macOS 26.0,iOS 26.0,  *)
struct AnimatedLiquidGlassStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
var verticalPadding: CGFloat = 14
    var horizontalPadding: CGFloat = 28
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            // Native Apple Liquid Glass effect
            .glassEffect(
                .regular
                    .tint(.white.opacity(0.1))
                    .interactive(), // Enables real-time lighting/touch reaction
                in: .rect(cornerRadius: cornerRadius)
            )
            .glassEffectTransition(GlassEffectTransition.identity)
            // Dynamic scale-up when pressed
            .scaleEffect(configuration.isPressed ? 1.15 : 1.0)
            // Smooth bouncy interaction animation
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// 2. View Extension Convenience
@available(macOS 26.0, iOS 26.0,*)
extension ButtonStyle where Self == AnimatedLiquidGlassStyle {
    static var liquidGlass: AnimatedLiquidGlassStyle { AnimatedLiquidGlassStyle() }
    static var smallLiquidGlass: AnimatedLiquidGlassStyle { AnimatedLiquidGlassStyle(verticalPadding: 4.0, horizontalPadding: 4.0) }
}
