import SwiftUI
import ServiceManagement

/// User-selectable accent, persisted in UserDefaults so `DS.accent` can read it
/// synchronously from any context (no main-actor hop).
enum AccentPreset: String, CaseIterable, Identifiable {
    case indigo, teal, pink, green, orange, graphite
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo:   return Color(red: 0.46, green: 0.51, blue: 0.97)   // oklch(0.64 0.17 266)
        case .teal:     return Color(red: 0.30, green: 0.80, blue: 0.80)
        case .pink:     return Color(red: 0.96, green: 0.44, blue: 0.72)
        case .green:    return Color(red: 0.30, green: 0.85, blue: 0.55)
        case .orange:   return Color(red: 1.00, green: 0.62, blue: 0.30)
        case .graphite: return Color(red: 0.70, green: 0.72, blue: 0.78)
        }
    }

    static let key = "accentPreset"
    static var current: AccentPreset {
        AccentPreset(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .indigo
    }
    static func set(_ preset: AccentPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: key)
    }
}

/// What plays in the background while Claude is working.
enum AIEffectStyle: String, CaseIterable, Identifiable {
    case pets, matrix
    var id: String { rawValue }
    var title: String { self == .pets ? "Pixel pets" : "Matrix" }
}

/// When the pixel pets stroll across the macOS menu bar.
enum MenuBarPetsMode: String, CaseIterable, Identifiable {
    case off, working, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .working: return "While working"
        case .always: return "Always"
        }
    }
}

/// App-wide preferences.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var accent: AccentPreset {
        didSet { AccentPreset.set(accent); objectWillChange.send() }
    }
    @Published var enabledTabs: [NotchTab] {
        didSet { d.set(enabledTabs.map(\.rawValue), forKey: "enabledTabs") }
    }
    @Published var mediaLiveActivity: Bool {
        didSet { d.set(mediaLiveActivity, forKey: "mediaLiveActivity") }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }
    @Published var hideSystemHUD: Bool {
        didSet {
            d.set(hideSystemHUD, forKey: "hideSystemHUD")
            SystemHUD.setSuppressed(hideSystemHUD)
        }
    }
    /// Subtle sound cue when the panel opens.
    @Published var openSound: Bool {
        didSet { d.set(openSound, forKey: "openSound") }
    }
    /// Matrix / pixel effect while Claude is working or responding.
    @Published var aiEffect: Bool {
        didSet { d.set(aiEffect, forKey: "aiEffect") }
    }
    /// Which background effect plays while Claude works.
    @Published var aiEffectStyle: AIEffectStyle {
        didSet { d.set(aiEffectStyle.rawValue, forKey: "aiEffectStyle") }
    }
    /// Pixel pets strolling across the macOS menu bar.
    @Published var menuBarPets: MenuBarPetsMode {
        didSet {
            d.set(menuBarPets.rawValue, forKey: "menuBarPets")
            NotificationCenter.default.post(name: .coolNotchPetsChanged, object: nil)
        }
    }
    // Solid menu bar (Boring Old Menu Bar technique — see SolidMenuBar).
    @Published var solidBarEnabled: Bool { didSet { d.set(solidBarEnabled, forKey: "solidBar.enabled"); solidBarChanged() } }
    @Published var solidBarStyle: SolidBarStyle { didSet { d.set(solidBarStyle.rawValue, forKey: "solidBar.style"); solidBarChanged() } }
    @Published var solidBarCustomLight: Color { didSet { d.set(RGB(solidBarCustomLight).hex, forKey: "solidBar.light"); solidBarChanged() } }
    @Published var solidBarCustomDark: Color { didSet { d.set(RGB(solidBarCustomDark).hex, forKey: "solidBar.dark"); solidBarChanged() } }
    @Published var solidBarDivider: SolidBarDivider { didSet { d.set(solidBarDivider.rawValue, forKey: "solidBar.divider"); solidBarChanged() } }
    @Published var solidBarHeightAdjust: Int { didSet { d.set(solidBarHeightAdjust, forKey: "solidBar.height"); solidBarChanged() } }
    @Published var solidBarCornerRadius: Int { didSet { d.set(solidBarCornerRadius, forKey: "solidBar.corners"); solidBarChanged() } }

    var solidBarConfig: SolidBarConfig {
        SolidBarConfig(enabled: solidBarEnabled, style: solidBarStyle,
                       customLight: RGB(solidBarCustomLight), customDark: RGB(solidBarCustomDark),
                       divider: solidBarDivider, heightAdjust: solidBarHeightAdjust,
                       cornerRadius: solidBarCornerRadius)
    }
    private func solidBarChanged() {
        NotificationCenter.default.post(name: .coolNotchMenuBarChanged, object: nil)
    }

    /// Soft chime + pill when a Claude Code session goes quiet (finishes).
    @Published var agentAlerts: Bool {
        didSet { d.set(agentAlerts, forKey: "agentAlerts") }
    }

    private init() {
        accent = AccentPreset.current
        if let raw = d.array(forKey: "enabledTabs") as? [String] {
            // Keep the user's choices; switch on tabs added since they last saved.
            let saved = Set(raw)
            let known = Set(d.stringArray(forKey: "knownTabs") ?? NotchTab.legacyRaw)
            let tabs = NotchTab.allCases.filter { saved.contains($0.rawValue) || !known.contains($0.rawValue) }
            enabledTabs = tabs.isEmpty ? NotchTab.allCases : tabs
        } else {
            enabledTabs = NotchTab.allCases
        }
        d.set(NotchTab.allCases.map(\.rawValue), forKey: "knownTabs")
        mediaLiveActivity = (d.object(forKey: "mediaLiveActivity") as? Bool) ?? true
        hideSystemHUD = (d.object(forKey: "hideSystemHUD") as? Bool) ?? false
        openSound = (d.object(forKey: "openSound") as? Bool) ?? true
        aiEffect = (d.object(forKey: "aiEffect") as? Bool) ?? true
        aiEffectStyle = AIEffectStyle(rawValue: d.string(forKey: "aiEffectStyle") ?? "") ?? .pets
        menuBarPets = MenuBarPetsMode(rawValue: d.string(forKey: "menuBarPets") ?? "") ?? .always
        solidBarEnabled = d.bool(forKey: "solidBar.enabled")
        solidBarStyle = SolidBarStyle(rawValue: d.string(forKey: "solidBar.style") ?? "") ?? .black
        solidBarCustomLight = (RGB(hex: d.string(forKey: "solidBar.light") ?? "") ?? RGB(0.93, 0.93, 0.94)).color
        solidBarCustomDark = (RGB(hex: d.string(forKey: "solidBar.dark") ?? "") ?? RGB(0, 0, 0)).color
        solidBarDivider = SolidBarDivider(rawValue: d.string(forKey: "solidBar.divider") ?? "") ?? .none
        solidBarHeightAdjust = d.integer(forKey: "solidBar.height")
        solidBarCornerRadius = d.integer(forKey: "solidBar.corners")
        agentAlerts = (d.object(forKey: "agentAlerts") as? Bool) ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if hideSystemHUD { SystemHUD.setSuppressed(true) }
    }

    func isEnabled(_ tab: NotchTab) -> Bool { enabledTabs.contains(tab) }
    func toggle(_ tab: NotchTab) {
        if enabledTabs.contains(tab) {
            guard enabledTabs.count > 1 else { return }   // keep at least one
            enabledTabs.removeAll { $0 == tab }
        } else {
            // preserve canonical order
            enabledTabs = NotchTab.allCases.filter { enabledTabs.contains($0) || $0 == tab }
        }
    }

    private func applyLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("CoolNotch login item error: \(error)")
        }
    }
}
