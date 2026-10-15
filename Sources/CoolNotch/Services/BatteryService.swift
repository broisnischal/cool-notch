import Foundation
import IOKit.ps
import Combine

struct BatteryInfo: Equatable {
    var level: Int          // 0...100
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool
    var timeToFull: Int?    // minutes, if known
    var timeToEmpty: Int?   // minutes, if known

    static let unknown = BatteryInfo(level: 100, isCharging: false, isPluggedIn: true,
                                     hasBattery: false, timeToFull: nil, timeToEmpty: nil)
}

/// Polls IOKit power sources. All public API — no entitlements required.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var info: BatteryInfo = .unknown
    var onNotify: ((NotchNotification) -> Void)?
    private var timer: AnyCancellable?
    private var seeded = false

    init() {
        refresh()
        // 20s cadence is plenty; battery % moves slowly.
        timer = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { info = .unknown; return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : 0

            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int

            let newInfo = BatteryInfo(
                level: level,
                isCharging: charging,
                isPluggedIn: plugged,
                hasBattery: true,
                timeToFull: (toFull ?? -1) > 0 ? toFull : nil,
                timeToEmpty: (toEmpty ?? -1) > 0 ? toEmpty : nil
            )
            diffNotify(old: info, new: newInfo)
            info = newInfo
            return
        }
        info = .unknown
    }

    /// Fire a live-activity pill on plug/unplug or low battery.
    private func diffNotify(old: BatteryInfo, new: BatteryInfo) {
        defer { seeded = true }
        guard seeded, new.hasBattery else { return }
        if old.isPluggedIn != new.isPluggedIn {
            if new.isPluggedIn {
                onNotify?(NotchNotification(icon: "bolt.fill", title: "Charging",
                                           subtitle: "\(new.level)%", tint: DS.good))
            } else {
                onNotify?(NotchNotification(icon: "battery.100", title: "On battery",
                                           subtitle: "\(new.level)% left", tint: DS.accent))
            }
        } else if !new.isCharging, new.level <= 20, old.level > 20 {
            onNotify?(NotchNotification(icon: "battery.25percent", title: "Low battery",
                                       subtitle: "\(new.level)% remaining", tint: DS.danger))
        }
    }
}
