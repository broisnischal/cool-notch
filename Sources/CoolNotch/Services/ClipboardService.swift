import SwiftUI
import AppKit
import Combine

/// Clipboard history — polls the general pasteboard and keeps recent text entries.
/// Tapping one copies it back. Text only (no images) to stay light.
@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private var timer: AnyCancellable?
    private var lastChange = NSPasteboard.general.changeCount
    private var suppressNext = false     // ignore the change we cause by copying

    private let maxItems = 40
    private let storeKey = "clipboardItems"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = saved
        }
        timer = Timer.publish(every: 0.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if suppressNext { suppressNext = false; return }

        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard items.first?.text != s else { return }

        items.removeAll { $0.text == s }
        items.insert(ClipItem(text: s, date: Date()), at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
        save()
    }

    func copy(_ item: ClipItem) {
        suppressNext = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChange = pb.changeCount
        // Move it to the top.
        items.removeAll { $0.id == item.id }
        items.insert(ClipItem(text: item.text, date: Date()), at: 0)
        save()
    }

    func clear() { items.removeAll(); save() }
}
