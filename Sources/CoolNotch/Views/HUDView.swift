import SwiftUI

/// Volume/brightness HUD content — icon on one shoulder, a level bar on the other,
/// split around the notch (Dynamic-Island style).
struct HUDView: View {
    let hud: HUDInfo
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Icon(hud.icon, size: 18.2, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 20)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)

            Color.clear.frame(width: notchWidth)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(DS.accent)
                        .frame(width: max(3, geo.size.width * hud.level))
                }
            }
            .frame(height: 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 16)
            .padding(.leading, 12)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
