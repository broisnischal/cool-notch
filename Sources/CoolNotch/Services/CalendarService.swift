import SwiftUI
import EventKit
import Combine

/// Upcoming calendar events via EventKit. Read-only; requests access lazily.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var authorized = false

    private let store = EKEventStore()
    private var timer: AnyCancellable?

    func start() {
        requestAccess()
        timer = Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.authorized = granted
                if granted { self?.refresh() }
            }
        }
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        let end = now.addingTimeInterval(60 * 60 * 18)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let mapped = store.events(matching: predicate)
            .filter { !$0.isAllDay && ($0.endDate ?? now) > now }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
            .prefix(4)
            .map { e in
                CalEvent(id: e.eventIdentifier ?? UUID().uuidString,
                         title: e.title ?? "Event",
                         start: e.startDate ?? now,
                         end: e.endDate ?? now,
                         isAllDay: e.isAllDay)
            }
        events = Array(mapped)
    }
}
