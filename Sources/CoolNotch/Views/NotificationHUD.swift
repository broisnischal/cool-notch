import SwiftUI

/// Dynamic-Island-style content: an icon on the left shoulder, the message on the
/// right, split around the notch gap in the middle.
struct NotificationHUD: View {
    let notification: NotchNotification
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Icon(notification.icon, size: 19.5, weight: .semibold)
                .foregroundStyle(notification.tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)

            Color.clear.frame(width: notchWidth)   // the notch gap

            // One line only — the pill must stay menu-bar height.
            HStack(spacing: 6) {
                Text(notification.title)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let subtitle = notification.subtitle {
                    Text(subtitle)
                        .font(.ui(11, .regular))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}
