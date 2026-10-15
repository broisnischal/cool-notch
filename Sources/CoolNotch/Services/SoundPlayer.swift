import AppKit

/// Tiny sound layer for the notch. A soft system tick on open, gated by the
/// `openSound` preference. Kept deliberately quiet — a cue, not an alert.
@MainActor
enum NotchSound {
    // Retained so a fast re-open can restart cleanly instead of overlapping.
    private static var current: NSSound?

    /// Subtle click as the panel unfurls.
    static func open() {
        guard AppSettings.shared.openSound else { return }
        play("Pop", volume: 0.16)
    }

    /// Soft chime when a Claude Code session goes quiet.
    static func agentDone() {
        guard AppSettings.shared.agentAlerts else { return }
        play("Glass", volume: 0.12)
    }

    private static func play(_ name: String, volume: Float) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        current?.stop()
        sound.volume = volume
        current = sound
        sound.play()
    }
}
