import SwiftUI

/// In-app notification center — the history of everything the notch has surfaced.
struct NotificationsView: View {
    @StateObject private var store = NotificationsStore.shared

    var body: some View {
        VStack(spacing: DS.gap) {
            if !store.history.isEmpty {
                SectionLabel(text: "\(store.history.count) recent") {
                    PillButton(title: "Clear") { store.clear() }
                }
                .padding(.leading, DS.inset)
            }
            if store.history.isEmpty {
                FeedStatus(icon: "bell.slash", text: "No notifications yet")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SeparatedList(items: store.history) { item in NotificationRow(item: item) }
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

struct NotificationRow: View {
    let item: RecordedNotification
    var body: some View {
        HStack(spacing: 8) {
            Icon(item.notification.icon, size: 14.3, weight: .semibold)
                .foregroundStyle(item.notification.tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.notification.title).font(.title).foregroundStyle(DS.textPrimary).lineLimit(1)
                if let sub = item.notification.subtitle {
                    Text(sub).font(.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(relativeLabel(item.date))
                .font(.caption).foregroundStyle(DS.textTertiary).lineLimit(1)
        }
        .rowSurface()
    }

    /// "now" under a minute (the system formatter prints "in 0 seconds" there),
    /// then a clean abbreviated relative time.
    private func relativeLabel(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        if elapsed < 60 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}
