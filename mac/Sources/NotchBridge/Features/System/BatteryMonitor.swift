import Foundation
import IOKit.ps

/// The Mac's internal battery, via IOKit power-source notifications (no polling).
/// Emits island activities on transitions: plugged in -> charging, and crossing 20% / 10% on battery.
final class BatteryMonitor {
    struct State: Equatable {
        var level: Int
        var charging: Bool
        var pluggedIn: Bool
    }

    /// Main thread.
    var onActivity: (SystemActivity) -> Void = { _ in }
    private(set) var state: State?
    private var source: CFRunLoopSource?

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().update()
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        source = src
        state = Self.read()     // baseline; no activity for the state we launch in
        DebugLog.write("battery: \(state.map { "\($0.level)% pluggedIn=\($0.pluggedIn) charging=\($0.charging)" } ?? "none (desktop Mac)")")
    }

    private func update() {
        guard let new = Self.read() else { return }
        let old = state
        state = new
        guard let old, old != new else { return }
        for a in Self.transitions(from: old, to: new) { onActivity(a) }
    }

    /// Pure transition rules (also used by --selftest).
    static func transitions(from old: State, to new: State) -> [SystemActivity] {
        var out: [SystemActivity] = []
        if !old.pluggedIn && new.pluggedIn {
            out.append(.charging(level: new.level, charging: new.charging))
        }
        if !new.pluggedIn {
            for threshold in [20, 10] where old.level > threshold && new.level <= threshold {
                out.append(.lowBattery(level: new.level))
                break
            }
        }
        return out
    }

    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return State(
                level: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                pluggedIn: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil   // desktop Mac: no battery
    }
}
