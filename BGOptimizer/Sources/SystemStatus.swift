import Darwin
import Foundation
import IOKit.ps

enum MemoryPressure {
    case normal, elevated, critical

    var label: String {
        switch self {
        case .normal: return trkey("Normal")
        case .elevated: return trkey("Elevated")
        case .critical: return trkey("Critical")
        }
    }
}

struct BatteryStatus {
    var percent: Int
    var charging: Bool
    var onAC: Bool
    var minutesRemaining: Int?       // to empty on battery, to full when charging
    var health: String?              // "Good" ... from System Information
    var maxCapacity: String?         // "85%"
    var cycles: Int?
}

/// A snapshot of how the Mac itself is doing. Everything here is public API or the same source System Information uses.
struct SystemStatus {
    var cpuLoad: Double              // 0...100 across all cores
    var cores: Int
    var memoryUsedGB: Double
    var memoryTotalGB: Double
    var pressure: MemoryPressure
    var thermal: ProcessInfo.ThermalState
    var lowPowerMode: Bool
    var battery: BatteryStatus?      // nil on a Mac without a battery
    var storageFreeGB: Double
    var storageTotalGB: Double
}

/// Reads SystemStatus. Call `read()` from a background queue; it keeps the previous CPU counters between calls.
final class SystemReader {
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var storageAt = Date.distantPast
    private var storage: (free: Double, total: Double) = (0, 0)
    private var healthAt = Date.distantPast
    private var health: (String?, String?, Int?) = (nil, nil, nil)

    func read() -> SystemStatus {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        var st = SystemStatus(cpuLoad: cpuLoad(), cores: ProcessInfo.processInfo.processorCount,
                              memoryUsedGB: memoryUsedBytes() / 1_073_741_824, memoryTotalGB: totalBytes / 1_073_741_824,
                              pressure: memoryPressure(), thermal: ProcessInfo.processInfo.thermalState,
                              lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, battery: battery(),
                              storageFreeGB: 0, storageTotalGB: 0)
        if Date().timeIntervalSince(storageAt) > 30,      // free space changes slowly and costs a file-system query
           let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            storageAt = Date()
            storage = (Double(v.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000, Double(v.volumeTotalCapacity ?? 0) / 1_000_000_000)
        }
        st.storageFreeGB = storage.free
        st.storageTotalGB = storage.total
        return st
    }

    // MARK: CPU

    private func cpuLoad() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let now = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = now }
        guard let last = lastTicks else { return 0 }
        let busy = Double(now.user &- last.user) + Double(now.system &- last.system) + Double(now.nice &- last.nice)
        let total = busy + Double(now.idle &- last.idle)
        return total > 0 ? busy / total * 100 : 0
    }

    // MARK: memory

    /// Same idea as Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func memoryUsedBytes() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pages = Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return pages * Double(vm_kernel_page_size)
    }

    private func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return level >= 4 ? .critical : (level == 2 ? .elevated : .normal)
    }

    // MARK: battery

    private func battery() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = (d[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            refreshHealth()
            return BatteryStatus(percent: d[kIOPSCurrentCapacityKey] as? Int ?? 0, charging: charging, onAC: onAC,
                                 minutesRemaining: minutes, health: health.0, maxCapacity: health.1, cycles: health.2)
        }
        return nil
    }

    /// Battery health is not in the public power API; System Information shows it, so ask it (about 0.1 s), at most every 2 minutes.
    private func refreshHealth() {
        guard Date().timeIntervalSince(healthAt) > 120 else { return }
        healthAt = Date()
        let data = Data(ToolRunner.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"], timeout: 10).output.utf8)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return }
        for item in items {
            if let h = item["sppower_battery_health_info"] as? [String: Any] {
                health = (h["sppower_battery_health"] as? String, h["sppower_battery_health_maximum_capacity"] as? String,
                          h["sppower_battery_cycle_count"] as? Int)
            }
        }
    }
}
