import SwiftUI
import AppKit
import Combine

/// A file parked on the shelf. We hold a security-scoped-ish reference by URL
/// and precompute the Finder icon so chips render instantly.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.id == b.id }
}

/// Observable UI state shared between AppKit (window/hit-testing) and SwiftUI.
@MainActor
final class NotchState: ObservableObject {
    let geo: NotchGeometry

    @Published var isExpanded = false
    @Published var peeking = false           // cursor is on the notch, about to open
    @Published var isPinned = false          // click the cap to keep it open
    @Published var shelfItems: [ShelfItem] = []
    @Published var isDropTargeted = false
    @Published var selectedTab: NotchTab = .home
    @Published var tabDirection: CGFloat = 1          // +1 → content enters from trailing
    @Published var route: NotchRoute?                 // pushed detail page
    @Published var refreshTick: Int = 0               // manual-refresh signal for pages
    @Published var notification: NotchNotification?   // Dynamic-Island pill
    @Published var hud: HUDInfo?                       // volume/brightness HUD

    private var notifyWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?

    /// Show a transient level HUD (volume) in the notch.
    func showHUD(_ h: HUDInfo) {
        guard !isExpanded else { return }
        hudWork?.cancel()
        withAnimation(.easeOut(duration: 0.16)) { hud = h }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.collapseAnim) { self.hud = nil }
        }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    /// While a detail page is open, don't auto-collapse.
    var shouldStayOpen: Bool { isPinned || route != nil }

    init(geo: NotchGeometry) {
        self.geo = geo
        // Restore shelf.
        if let paths = UserDefaults.standard.array(forKey: "shelfPaths") as? [String] {
            shelfItems = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        }
        // Restore last tab (if still enabled).
        if let raw = UserDefaults.standard.string(forKey: "lastTab"),
           let tab = NotchTab(rawValue: raw) {
            selectedTab = tab
        }
    }

    private func saveShelf() {
        UserDefaults.standard.set(shelfItems.map(\.url.path), forKey: "shelfPaths")
    }

    /// Present a transient notification pill (unless the panel is open — then it
    /// would just flicker behind the content, so we skip it).
    func notify(_ n: NotchNotification) {
        NotificationsStore.shared.record(n)   // always logged to the center
        guard !isExpanded else { return }
        notifyWork?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : DS.expand) {
            notification = n
        }
        let work = DispatchWorkItem { [weak self] in self?.dismissNotification() }
        notifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: work)
    }

    func dismissNotification() {
        notifyWork?.cancel()
        withAnimation(collapseAnim) { notification = nil }
    }

    func select(_ tab: NotchTab) {
        guard tab != selectedTab || route != nil else { return }
        let order = AppSettings.shared.enabledTabs
        if let from = order.firstIndex(of: selectedTab), let to = order.firstIndex(of: tab) {
            tabDirection = to >= from ? 1 : -1
        }
        withAnimation(DS.content) {
            route = nil          // switching tabs returns to that tab's root
            selectedTab = tab
        }
        UserDefaults.standard.set(tab.rawValue, forKey: "lastTab")
    }

    /// Global-hotkey toggle: minimize (keeping the current page + background work),
    /// or bring it back exactly where it was.
    func toggleFromHotkey() {
        if isExpanded {
            isPinned = false
            withAnimation(collapseAnim) { isExpanded = false }   // keep route + content
        } else {
            isPinned = true
            NotchSound.open()
            withAnimation(expandAnim) { notification = nil; isExpanded = true }
        }
    }

    func push(_ r: NotchRoute) { withAnimation(DS.content) { route = r } }
    func pop() { withAnimation(DS.content) { route = nil } }
    func bumpRefresh() { refreshTick &+= 1 }

    /// Reduced motion → gentle non-vestibular cross-fades instead of springs.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private var expandAnim: Animation { reduceMotion ? .easeOut(duration: 0.18) : DS.expand }
    private var collapseAnim: Animation { reduceMotion ? .easeOut(duration: 0.14) : DS.collapse }

    func expand() {
        guard !isExpanded else { return }
        notifyWork?.cancel()
        NotchSound.open()
        withAnimation(expandAnim) {
            notification = nil
            peeking = false
            isExpanded = true
        }
    }

    /// Collapse unless pinned / on a detail page / using the terminal. Keeps the
    /// route + content mounted so background work (streams, terminal) continues.
    func collapseIfUnpinned() {
        guard isExpanded, !shouldStayOpen else { return }
        withAnimation(collapseAnim) { isExpanded = false }
    }

    func togglePin() {
        withAnimation(DS.press) { isPinned.toggle() }
        if !isPinned { collapseIfUnpinned() }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(shelfItems.map(\.url))
        let fresh = urls.filter { !existing.contains($0) }.map(ShelfItem.init(url:))
        guard !fresh.isEmpty else { return }
        withAnimation(DS.content) { shelfItems.append(contentsOf: fresh) }
        saveShelf()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(DS.collapse) { shelfItems.removeAll { $0.id == item.id } }
        saveShelf()
    }

    func clearShelf() {
        withAnimation(DS.collapse) { shelfItems.removeAll() }
        saveShelf()
    }
}
