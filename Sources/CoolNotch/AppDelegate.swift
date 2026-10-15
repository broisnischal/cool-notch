import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controllers: [NotchWindowController] = []
    private var statusItem: NSStatusItem?
    private let menuPets = MenuBarPetsController()

    /// Point the menu-bar pets at the (re)built notch window + services.
    private func wirePets() {
        if let c = controllers.first {
            menuPets.notchWindowNumber = c.panel.windowNumber
            menuPets.bind(claude: c.claude, ai: c.ai)
        }
        menuPets.refresh()
    }

    /// Only one Cool Notch may run. A newer launch replaces any older copy (asks it
    /// to quit, then force-quits it if it hasn't gone within 1.5s), so a relaunch
    /// can never show two notch panels at once.
    private func replaceOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(1.5)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOtherInstances()   // exactly one notch, ever
        AppFonts.register()   // before any SwiftUI view resolves a Geist font
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        buildMainMenu()                         // enables text-editing shortcuts
        buildStatusItem()
        buildNotchWindows()
        registerHotKey()
        wirePets()
        SolidMenuBar.shared.apply(AppSettings.shared.solidBarConfig)

        // Re-place windows when the screen arrangement changes (dock a laptop, etc.).
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            forName: .coolNotchOpenPrefs, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.showPreferences() } }
        NotificationCenter.default.addObserver(
            forName: .coolNotchMenuBarChanged, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { SolidMenuBar.shared.apply(AppSettings.shared.solidBarConfig) } }
        NotificationCenter.default.addObserver(
            forName: .coolNotchPetsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.menuPets.refresh() } }
        NotificationCenter.default.addObserver(
            forName: .coolNotchNeedsKey, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.activateForInput() } }
    }

    /// Activate the app + make the notch key so text fields/terminal receive keys
    /// and the Edit-menu shortcuts (⌘A/⌘Z/⌘C/V/X, word-delete) route correctly.
    private func activateForInput() {
        NSApp.activate(ignoringOtherApps: true)
        controllers.first?.panel.makeKey()
    }

    /// A minimal main menu. The Edit menu's standard selectors travel the responder
    /// chain to the focused text field / terminal, enabling copy/paste/undo/select-all.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Cool Notch",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    private func buildNotchWindows() {
        // Prefer the screen that actually has a notch, regardless of which display
        // is set as "main"; fall back to the menu-bar screen.
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        // Screen-parameter notifications also fire for things like a wallpaper
        // change — only rebuild when the display geometry really changed.
        if let screen, controllers.count == 1,
           controllers[0].screenKey == NotchWindowController.key(for: screen) { return }
        controllers.forEach { $0.tearDown() }
        controllers = []
        if let screen {
            controllers.append(NotchWindowController(screen: screen))
        }
    }

    @objc private func screensChanged() {
        buildNotchWindows()
        wirePets()
    }

    private func registerHotKey() {
        HotKeyCenter.shared.onFire = { [weak self] in
            Task { @MainActor in self?.controllers.first?.state.toggleFromHotkey() }
        }
        HotKeyCenter.shared.register()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Cool Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Cool Notch", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",
                     action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cool Notch",
                     action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    private var prefsWindow: NSWindow?
    @objc private func showPreferences() {
        if prefsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Cool Notch Settings"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: PreferencesView())
            prefsWindow = w
        }
        // Accessory apps need a temporary regular policy for the window to focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.center()
        prefsWindow?.makeKeyAndOrderFront(nil)
        prefsWindow?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === prefsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
