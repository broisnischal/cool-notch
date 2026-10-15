import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// An sRGB colour that can cross actor boundaries and persist as a hex string.
struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    var hex: String {
        String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// Solid menu-bar presets — the same set Boring Old Menu Bar ships.
enum SolidBarStyle: String, CaseIterable, Identifiable {
    case black, darkGrey, lightGrey, white, catalinaDark, catalinaLight, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black:         return "Black"
        case .darkGrey:      return "Dark grey"
        case .lightGrey:     return "Light grey"
        case .white:         return "White"
        case .catalinaDark:  return "Catalina dark"
        case .catalinaLight: return "Catalina light"
        case .custom:        return "Custom"
        }
    }
    /// Colour to paint; `custom` resolves to the light- or dark-mode custom colour.
    func rgb(dark: Bool, light customLight: RGB, dark customDark: RGB) -> RGB {
        switch self {
        case .black:         return RGB(0, 0, 0)
        case .darkGrey:      return RGB(0.20, 0.20, 0.21)
        case .lightGrey:     return RGB(0.82, 0.82, 0.83)
        case .white:         return RGB(1, 1, 1)
        case .catalinaDark:  return RGB(0.17, 0.17, 0.18)
        case .catalinaLight: return RGB(0.93, 0.93, 0.94)
        case .custom:        return dark ? customDark : customLight
        }
    }
}

/// Line under the bar.
enum SolidBarDivider: String, CaseIterable, Identifiable {
    case none, hairline, pixel
    var id: String { rawValue }
    var title: String { self == .none ? "None" : (self == .hairline ? "Hairline" : "1 pixel") }
}

struct SolidBarConfig: Equatable, Sendable {
    var enabled = false
    var style = SolidBarStyle.black
    var customLight = RGB(0.93, 0.93, 0.94)
    var customDark = RGB(0, 0, 0)
    var divider = SolidBarDivider.none
    var heightAdjust = 0          // device pixels, −1…+1
    var cornerRadius = 0          // points, 0 = square screen corners
}

// MARK: - Painter

/// Solid menu bar, the Boring Old Menu Bar way: no overlay window, no hidden menu
/// bar, no screen recording. For each display we render a copy of the current
/// wallpaper *file* with a solid strip exactly where the menu bar sits (plus an
/// optional divider and rounded screen corners) and set that copy as the desktop
/// picture. macOS keeps drawing its real, fully working menu bar on top.
///
/// Idempotent: every check compares the wallpaper on screen with what *should* be
/// there (a signature of colour, size, divider, corners, appearance). New wallpaper,
/// new Space, resolution or light/dark change → repaint; turning it off → the
/// original wallpaper comes back (also lazily for other Spaces as you visit them).
@MainActor
final class SolidMenuBar: ObservableObject {
    static let shared = SolidMenuBar()

    @Published private(set) var status = ""

    private var config = SolidBarConfig()
    private let d = UserDefaults.standard
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var inFlight: Set<CGDirectDisplayID> = []

    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CoolNotch/MenuBar", isDirectory: true)

    /// painted file path → the user's original wallpaper path.
    private var originals: [String: String] {
        get { d.dictionary(forKey: "solidBar.originals") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "solidBar.originals") }
    }
    /// painted file path → signature of the settings it was rendered with.
    private var signatures: [String: String] {
        get { d.dictionary(forKey: "solidBar.signatures") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "solidBar.signatures") }
    }

    private init() {}

    func apply(_ c: SolidBarConfig) {
        config = c
        if observers.isEmpty { observe() }
        pruneOrphans()
        refreshAll()
    }

    func refreshAll() {
        for screen in NSScreen.screens { refresh(screen) }
        // Keep watching while enabled, or while any painted wallpaper still needs
        // restoring on a Space we haven't visited since turning it off.
        let needsWatch = config.enabled || !originals.isEmpty
        if needsWatch, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
                MainActor.assumeIsolated { SolidMenuBar.shared.refreshAll() }
            }
        } else if !needsWatch {
            timer?.invalidate(); timer = nil
        }
    }

    private func refresh(_ screen: NSScreen) {
        guard let id = screen.displayID, !inFlight.contains(id),
              let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        let path = current.path
        let ours = originals[path]

        guard config.enabled else {
            // Off: put the original back wherever one of our copies is showing.
            if let original = ours {
                try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: original), for: screen,
                                                           options: Self.fillOptions)
                forget(path)
            }
            status = "Off"
            return
        }

        let source = URL(fileURLWithPath: ours ?? path)
        let job = Job(screen: screen, config: config, dark: Self.isDark)
        if ours != nil, signatures[path] == job.signature { status = "On"; return }   // already right

        inFlight.insert(id)
        let dest = Self.dir.appendingPathComponent("bar-\(id)-\(UUID().uuidString.prefix(8)).png")
        Task.detached(priority: .utility) {
            let ok = Self.render(source: source, job: job, to: dest)
            await MainActor.run {
                let me = SolidMenuBar.shared
                me.inFlight.remove(id)
                guard ok else {
                    me.status = "Can't read this wallpaper — pick a picture (not a live/aerial one)."
                    return
                }
                // Only swap if the display is still there and still showing the
                // wallpaper we rendered from.
                guard let screen = NSScreen.screens.first(where: { $0.displayID == id }),
                      let now = NSWorkspace.shared.desktopImageURL(for: screen)?.path,
                      now == path else { try? FileManager.default.removeItem(at: dest); return }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(dest, for: screen, options: Self.fillOptions)
                    var o = me.originals; o[dest.path] = source.path; me.originals = o
                    var s = me.signatures; s[dest.path] = job.signature; me.signatures = s
                    if ours != nil { me.forget(path) }           // replaced an older copy of ours
                    me.status = "On"
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    me.status = "macOS refused the wallpaper change."
                }
            }
        }
    }

    private func forget(_ painted: String) {
        var o = originals; o[painted] = nil; originals = o
        var s = signatures; s[painted] = nil; signatures = s
        try? FileManager.default.removeItem(atPath: painted)
    }

    /// Delete rendered files nothing points at any more (crash leftovers, old renders).
    private func pruneOrphans() {
        let keep = Set(originals.keys)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where !keep.contains(f.path) { try? FileManager.default.removeItem(at: f) }
    }

    private func observe() {
        let ws = NSWorkspace.shared.notificationCenter
        let refresh: (Notification) -> Void = { _ in
            MainActor.assumeIsolated { SolidMenuBar.shared.refreshAll() }
        }
        observers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                        object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
            using: refresh))
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
            queue: .main, using: refresh))
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static let fillOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true,
    ]

    // MARK: Rendering (off-main, pure Core Graphics)

    /// Everything a render needs, captured on the main actor.
    struct Job: Sendable {
        let pixelW: Int, pixelH: Int, barPx: Int, cornerPx: Int
        let color: RGB
        let divider: SolidBarDivider

        init(screen: NSScreen, config c: SolidBarConfig, dark: Bool) {
            let scale = screen.backingScaleFactor
            pixelW = Int((screen.frame.width * scale).rounded())
            pixelH = Int((screen.frame.height * scale).rounded())
            // Menu-bar height: the notch inset on notched displays, otherwise the gap
            // above the visible frame; 24pt as a last resort.
            let notch = screen.safeAreaInsets.top
            let gap = screen.frame.maxY - screen.visibleFrame.maxY
            let pt = notch > 0 ? notch : (gap > 0 ? gap : 24)
            barPx = max(1, Int((pt * scale).rounded()) + c.heightAdjust)
            cornerPx = Int((CGFloat(c.cornerRadius) * scale).rounded())
            color = c.style.rgb(dark: dark, light: c.customLight, dark: c.customDark)
            divider = c.divider
        }

        var signature: String {
            "\(pixelW)x\(pixelH)|\(barPx)|\(color.hex)|\(divider.rawValue)|\(cornerPx)"
        }
    }

    nonisolated static func render(source: URL, job: Job, to dest: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), nil),
              let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: job.pixelW, height: job.pixelH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return false }

        let W = CGFloat(job.pixelW), H = CGFloat(job.pixelH)
        ctx.interpolationQuality = .high

        // Wallpaper, aspect-filled exactly as macOS's "Fill Screen" would.
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let s = max(W / iw, H / ih)
        ctx.draw(img, in: CGRect(x: (W - iw * s) / 2, y: (H - ih * s) / 2, width: iw * s, height: ih * s))

        // The bar (CG origin is bottom-left, so the strip is at the top of the bitmap).
        let bar = CGFloat(job.barPx)
        let c = job.color
        ctx.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: H - bar, width: W, height: bar))

        // Divider: a 1px line just under the bar, contrasting with the bar colour.
        if job.divider != .none {
            let alpha = job.divider == .pixel ? 0.35 : 0.16
            let line: CGColor = c.luminance > 0.5
                ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
                : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
            ctx.setFillColor(line)
            ctx.fill(CGRect(x: 0, y: H - bar - 1, width: W, height: 1))
        }

        // Rounded screen corners: black outside a rounded rect (even-odd fill).
        if job.cornerPx > 0 {
            let r = CGFloat(job.cornerPx)
            let path = CGMutablePath()
            path.addRect(CGRect(x: 0, y: 0, width: W, height: H))
            path.addRoundedRect(in: CGRect(x: 0, y: 0, width: W, height: H), cornerWidth: r, cornerHeight: r)
            ctx.addPath(path)
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fillPath(using: .evenOdd)
        }

        guard let out = ctx.makeImage() else { return false }
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let file = CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(file, out, nil)
        return CGImageDestinationFinalize(file)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
