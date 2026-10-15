import SwiftUI

/// Horizontal wobble used to "vibrate" the notch when a notification lands.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakes), y: 0))
    }
}

/// Three dots that pulse in sequence — a "typing/working" indicator.
struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.accent)
                    .frame(width: 5, height: 5)
                    .opacity(reduceMotion ? 0.7 : (phase == i ? 1 : 0.3))
                    .scaleEffect(reduceMotion ? 1 : (phase == i ? 1.15 : 0.85))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: false)) { }
            Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

/// Collapsed "Claude is working" live activity — icon on one shoulder, dots on the other.
struct TypingActivity: View {
    let notchWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            StatusDot(color: DS.accent, pulsing: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            Color.clear.frame(width: notchWidth)
            TypingDots()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
