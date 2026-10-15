import SwiftUI

/// Collapsed-notch now-playing "live activity" — album art on one shoulder of the
/// notch, an animated equalizer on the other, split around the camera. iOS
/// Dynamic-Island style. Shown only while something is actually playing.
struct MediaLiveActivity: View {
    let info: NowPlaying
    let artwork: NSImage?
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            artView.frame(maxWidth: .infinity)          // centred in the left shoulder
            Color.clear.frame(width: notchWidth)        // notch gap
            EqualizerBars().frame(maxWidth: .infinity)  // centred in the right shoulder
        }
        .frame(maxHeight: .infinity)
    }

    private var artView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.10))
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                Icon("music.note", size: 13, weight: .semibold)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }
}

/// Four bars breathing like an audio meter, driven by a continuous timeline so the
/// pulse is always visibly animating while music plays. Reduced-motion aware.
struct EqualizerBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let phases: [Double] = [0, 1.3, 2.4, 3.6]

    var body: some View {
        if reduceMotion {
            bars { _ in 0.6 }
        } else {
            // .periodic (timer-based) keeps animating in the non-key notch panel,
            // where .animation (display-link) gets throttled/paused.
            TimelineView(.periodic(from: .now, by: 0.09)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                bars { i in 0.28 + 0.72 * (0.5 + 0.5 * sin(t * 8 + phases[i])) }
            }
        }
    }

    private func bars(_ height: @escaping (Int) -> Double) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(DS.accent)
                    .frame(width: 2.5, height: 13)
                    .scaleEffect(y: CGFloat(height(i)), anchor: .center)
            }
        }
        .frame(height: 14)
    }
}
