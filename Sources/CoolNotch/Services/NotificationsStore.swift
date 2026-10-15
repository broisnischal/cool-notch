import SwiftUI

/// In-memory history of everything shown as a notch notification pill, so the user
/// has a notification center to scroll back through.
@MainActor
final class NotificationsStore: ObservableObject {
    static let shared = NotificationsStore()
    @Published private(set) var history: [RecordedNotification] = []
    private let maxItems = 60

    private init() {}

    func record(_ n: NotchNotification) {
        history.insert(RecordedNotification(notification: n, date: Date()), at: 0)
        if history.count > maxItems { history.removeLast(history.count - maxItems) }
    }

    func clear() { history.removeAll() }
}
