import Carbon.HIToolbox
import Foundation

/// A single global hotkey (⌘⌃N) to toggle the notch. Carbon `RegisterEventHotKey`
/// needs no Accessibility permission. The event fires on the main run loop.
final class HotKeyCenter: @unchecked Sendable {
    static let shared = HotKeyCenter()
    private var ref: EventHotKeyRef?
    var onFire: (@Sendable () -> Void)?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData!).takeUnretainedValue()
            center.onFire?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x434E4F54), id: 1) // 'CNOT'
        RegisterEventHotKey(UInt32(kVK_ANSI_N),
                            UInt32(cmdKey | controlKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}
