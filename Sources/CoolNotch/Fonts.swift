import CoreText
import Foundation

/// Registers the bundled Geist / Geist Mono faces (Contents/Resources/Fonts) for
/// this process before any UI is built. Missing files fall back to the system font.
enum AppFonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
