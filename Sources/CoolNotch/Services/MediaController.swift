import AppKit

/// Sends system media keys (play/pause, next, previous) so the notch can drive
/// whatever app owns "Now Playing" — Music, Spotify, browsers, etc.
///
/// Posting keys to other apps may require Accessibility permission the first time
/// (System Settings ▸ Privacy & Security ▸ Accessibility). If it's not granted the
/// call is a silent no-op rather than a crash.
enum MediaController {
    // From <IOKit/hidsystem/ev_keymap.h>
    private static let NX_KEYTYPE_PLAY: Int32 = 16
    private static let NX_KEYTYPE_NEXT: Int32 = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32 = 18

    static func playPause() { post(NX_KEYTYPE_PLAY) }
    static func next()      { post(NX_KEYTYPE_NEXT) }
    static func previous()  { post(NX_KEYTYPE_PREVIOUS) }

    private static func post(_ key: Int32) {
        send(key, down: true)
        send(key, down: false)
    }

    private static func send(_ key: Int32, down: Bool) {
        let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xA00)
                                                 : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
