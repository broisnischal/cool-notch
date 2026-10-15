import Foundation
import CoreAudio
import AudioToolbox

/// Polls the default output device's master volume and reports changes so the
/// notch can show a volume HUD. Polling (10 Hz) is cheap and avoids CoreAudio
/// listener/C-callback concurrency headaches.
@MainActor
final class VolumeMonitor: ObservableObject {
    var onChange: ((Double, Bool) -> Void)?   // level 0…1, muted
    private var timer: Timer?
    private var last: Double = -1
    private var lastMuted = false
    private var seeded = false

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let device = Self.defaultOutputDevice() else { return }
        let muted = Self.muted(device)
        let level = Double(Self.volume(device) ?? 0)
        defer { seeded = true; last = level; lastMuted = muted }
        guard seeded else { return }
        if abs(level - last) > 0.001 || muted != lastMuted {
            onChange?(level, muted)
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size, &id)
        return err == noErr ? id : nil
    }

    private static func volume(_ device: AudioObjectID) -> Float? {
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        let err = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol)
        return err == noErr ? vol : nil
    }

    private static func muted(_ device: AudioObjectID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        let err = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted)
        return err == noErr && muted != 0
    }
}
