import SwiftUI

/// The app's one icon primitive: Hugeicons ("stroke rounded"), drawn from the
/// generated paths in `HugeIconPaths`, coloured by the current foreground style.
/// Call sites keep passing the familiar SF Symbol name; `Icon.map` translates it.
/// Anything unmapped falls back to the SF Symbol so nothing ever renders blank.
struct Icon: View {
    let name: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular

    init(_ name: String, size: CGFloat = 16, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    var body: some View {
        if let key = Icon.map[name] ?? (HugeIconPaths.names.contains(name) ? name : nil),
           let p = HugeIconPaths.paths(key) {
            ZStack {
                IconShape(path: p.stroke)
                    .stroke(style: StrokeStyle(lineWidth: stroke * size * 1.1 / 24,
                                               lineCap: .round, lineJoin: .round))
                IconShape(path: p.fill).fill()
            }
            .frame(width: size * 1.1, height: size * 1.1)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Image(systemName: name)
                .font(.system(size: size * 0.78, weight: weight))
                .frame(width: size, height: size)
        }
    }

    /// Bolder than Hugeicons' native 1.5 so glyphs read solid on pure black;
    /// heavier text gets a heavier line.
    private var stroke: CGFloat {
        switch weight {
        case .bold, .heavy, .black: return 2.5
        case .semibold:             return 2.25
        default:                    return 2.0
        }
    }

    /// SF Symbol name → Hugeicon. Filled/outline SF variants share one icon; the
    /// selected state is carried by colour and the accent marker, not a fill.
    static let map: [String: String] = [
        // Tabs
        "house": "home-01", "ellipsis.bubble": "bubble-chat", "ellipsis.bubble.fill": "bubble-chat",
        "wifi": "wifi-01", "stethoscope": "stethoscope", "hammer": "source-code",
        "shippingbox": "package", "shippingbox.fill": "package", "doc.on.clipboard": "clipboard",
        "bookmark": "bookmark-02", "camera": "camera-01", "camera.fill": "camera-01",
        "bell": "notification-03", "bell.slash": "notification-off-03",
        "rectangle.topthird.inset.filled": "notification-03",
        // Navigation + actions
        "chevron.left": "arrow-left-01", "chevron.right": "arrow-right-01",
        "arrow.up.right": "arrow-up-right-01", "arrow.up.circle.fill": "arrow-up-02",
        "plus.circle.fill": "add-circle", "xmark.circle.fill": "cancel-circle", "xmark": "cancel-01",
        "arrow.clockwise": "refresh", "arrow.counterclockwise": "arrow-reload-horizontal",
        "gearshape": "settings-02", "gearshape.fill": "settings-02", "pin": "pin", "pin.fill": "pin",
        "terminal": "computer-terminal-01", "link": "link-01", "globe": "globe-02",
        "tray.and.arrow.down": "inbox-download", "doc.on.doc": "copy-01", "checkmark": "tick-02",
        "text.bubble": "message-01", "speedometer": "dashboard-speed-01", "sparkles": "sparkles",
        // Media
        "play.fill": "play", "pause.fill": "pause", "forward.fill": "next", "backward.fill": "previous",
        "music.note": "music-note-01",
        "speaker.slash.fill": "volume-mute-02", "speaker.wave.1.fill": "volume-low",
        "speaker.wave.2.fill": "volume-high", "speaker.wave.3.fill": "volume-high",
        // Status
        "checkmark.circle.fill": "checkmark-circle-02", "exclamationmark.triangle": "alert-02",
        "exclamationmark.triangle.fill": "alert-02", "exclamationmark": "alert-circle",
        "xmark.octagon.fill": "cancel-circle", "hand.raised.fill": "alert-02",
        "bolt.fill": "flash", "battery.100": "battery-full", "battery.25percent": "battery-low",
        "chart.bar.fill": "analytics-01",
        // Dev
        "arrow.triangle.branch": "git-branch", "arrow.triangle.pull": "git-pull-request",
        // Health checks
        "network": "global-search", "cpu": "cpu", "memorychip": "ram-memory",
        "arrow.triangle.swap": "arrow-data-transfer-vertical", "internaldrive": "hard-drive",
        "thermometer.medium": "temperature", "clock.arrow.circlepath": "clock-01",
        "lock.shield": "security-check",
    ]
}

/// A 24×24 Hugeicons path scaled into whatever frame it's given.
private struct IconShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
