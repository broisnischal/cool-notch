import SwiftUI
import AppKit

/// Persisted website bookmarks; open in the default browser.
@MainActor
final class BookmarksService: ObservableObject {
    static let shared = BookmarksService()
    @Published private(set) var items: [Bookmark] = []
    private let key = "bookmarks"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            items = saved
        }
    }

    func add(name: String, url: String) {
        var normalized = url.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return }
        if !normalized.contains("://") { normalized = "https://" + normalized }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (URL(string: normalized)?.host ?? normalized) : name
        items.insert(Bookmark(name: title, url: normalized), at: 0)
        save()
    }

    func remove(_ item: Bookmark) { items.removeAll { $0.id == item.id }; save() }

    func open(_ item: Bookmark) {
        if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
