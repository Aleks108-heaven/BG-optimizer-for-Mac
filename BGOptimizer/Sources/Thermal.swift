import Foundation
import IOKit

// Fans and temperatures, READ ONLY.
//
// Fan speeds come from the SMC (the Mac's system management controller) and temperatures from the named HID thermal sensors that
// Apple Silicon exposes. Both can be read by an ordinary user: no password, no helper. Neither is documented by Apple (see
// SECURITY-REVIEW.md S-24), so every reading is checked before it is shown, and a Mac that does not answer simply shows nothing.
// Nothing here writes to the SMC: setting a fan speed is refused for an ordinary user (kIOReturnNotPrivileged, checked on the
// development Mac) and this app has no privileged helper on purpose.

// MARK: what is shown

struct FanReading: Identifiable, Equatable {
    var index: Int
    var rpm: Double
    var minRPM: Double
    var maxRPM: Double
    var targetRPM: Double?
    var manual: Bool            // the SMC says the fan is not in automatic mode (something other than macOS may be setting it)
    var id: Int { index }
}

/// Where a sensor sits, in words a person can use. The order is the order of the list.
enum SensorGroup: Int, CaseIterable {
    case chipDie, cpuPerformance, cpuEfficiency, gpu, neural, soc, battery, storage, other

    var title: String {
        switch self {
        case .chipDie: return trkey("Chip (die sensors)")
        case .cpuPerformance: return trkey("CPU performance cores")
        case .cpuEfficiency: return trkey("CPU efficiency cores")
        case .gpu: return trkey("GPU")
        case .neural: return trkey("Neural Engine")
        case .soc: return trkey("System chip (SoC)")
        case .battery: return trkey("Battery")
        case .storage: return trkey("Storage (SSD)")
        case .other: return trkey("Other sensors")
        }
    }

    /// Rough guides, not limits: Apple publishes none. Chips start to slow themselves near 100 °C; a battery and an SSD dislike heat sooner.
    var warm: Double {
        switch self {
        case .battery: return 45
        case .storage: return 70
        default: return 85
        }
    }
    var hot: Double {
        switch self {
        case .battery: return 55
        case .storage: return 80
        default: return 100
        }
    }
}

enum TempLevel { case ok, warm, hot }

struct TempSensor: Identifiable, Equatable {
    var id: Int
    var name: String            // as the sensor calls itself, e.g. "pACC MTR Temp Sensor2"
    var celsius: Double
    var group: SensorGroup
}

struct SensorGroupSummary: Identifiable, Equatable {
    var group: SensorGroup
    var sensors: [TempSensor]   // sorted by name
    var hottest: Double
    var average: Double
    var id: Int { group.rawValue }
    var level: TempLevel { hottest >= group.hot ? .hot : (hottest >= group.warm ? .warm : .ok) }
}

struct ThermalReadout: Equatable {
    var fans: [FanReading] = []
    var sensors: [TempSensor] = []
    var fanCount: Int?                  // what the SMC says (FNum); nil if it could not be read
    var smcAvailable = false
    var sensorsAvailable = false
    var summaries: [SensorGroupSummary] { ThermalAnalysis.summaries(sensors) }
}

// MARK: decisions (no hardware: tested without a Mac that has fans)

enum ThermalAnalysis {
    /// A temperature a sensor can really have. Some sensors report a fixed or missing value (-21.7 was seen on an M1 MacBook Pro),
    /// and an unplugged one can report NaN.
    static func isPlausible(_ c: Double) -> Bool { c.isFinite && c > 0 && c < 150 }

    /// Which group a sensor belongs to by its name; nil for a sensor that is not a temperature reading (a calibration value).
    static func group(forName name: String) -> SensorGroup? {
        let n = name.lowercased()
        if n.contains("tcal") { return nil }                                  // "PMU tcal": a calibration value, the same on every read
        if n.hasPrefix("pacc") { return .cpuPerformance }
        if n.hasPrefix("eacc") { return .cpuEfficiency }
        if n.hasPrefix("gpu") { return .gpu }
        if n.hasPrefix("ane") { return .neural }
        if n.hasPrefix("soc mtr") || n.hasPrefix("pmgr soc") { return .soc }
        if n.contains("tdie") { return .chipDie }                            // "PMU tdie1", "PMU2 tdie1"
        if n.contains("battery") { return .battery }                         // "gas gauge battery"
        if n.hasPrefix("nand") { return .storage }
        return .other
    }

    /// Turns a raw (name, value) pair into a sensor, or nothing if it is not a usable temperature.
    static func sensor(id: Int, name: String, celsius: Double) -> TempSensor? {
        guard isPlausible(celsius), let g = group(forName: name) else { return nil }
        return TempSensor(id: id, name: plainText(name), celsius: celsius, group: g)
    }

    static func summaries(_ sensors: [TempSensor]) -> [SensorGroupSummary] {
        SensorGroup.allCases.compactMap { g in
            let list = sensors.filter { $0.group == g }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !list.isEmpty else { return nil }
            let values = list.map { $0.celsius }
            return SensorGroupSummary(group: g, sensors: list, hottest: values.max() ?? 0, average: values.reduce(0, +) / Double(values.count))
        }
    }

    /// One fan from its SMC keys (`number` reads a key as a number). A fan whose values make no sense is left out instead of shown wrong.
    static func fan(index: Int, number: (String) -> Double?) -> FanReading? {
        guard let rpm = number("F\(index)Ac"), let lo = number("F\(index)Mn"), let hi = number("F\(index)Mx") else { return nil }
        guard (0...20_000).contains(rpm), lo >= 0, hi > 0, hi <= 20_000, lo <= hi else { return nil }
        let manual = (number("F\(index)Md") ?? 0) != 0
        let target = number("F\(index)Tg").flatMap { (0...20_000).contains($0) ? $0 : nil }
        return FanReading(index: index, rpm: rpm, minRPM: lo, maxRPM: hi, targetRPM: target, manual: manual)
    }

    static let maxFans = 8
}

// MARK: the SMC (read only)

/// What the SMC hands back for a key, as raw bytes plus its four-letter type.
enum SMCDecode {
    /// A number out of the SMC's bytes. Apple Silicon sends floats ("flt ") in the Mac's own byte order and integers big-endian.
    /// Anything else (or a wrong length, or NaN) is nil.
    static func number(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : nil
        case "ui8 " where bytes.count == 1, "ui16" where bytes.count == 2, "ui32" where bytes.count == 4:
            return Double(bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        default:
            return nil
        }
    }
}

// The structure the AppleSMC user client expects: 80 bytes, laid out as in C. `SMCKeyInfo` is padded by hand, because Swift would
// otherwise place the next field inside its trailing padding and the call would fail with "bad argument" (tests check the size).
struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct SMCPLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct SMCKeyInfo { var size: UInt32 = 0, type: UInt32 = 0; var attributes: UInt8 = 0; var pad1: UInt8 = 0, pad2: UInt8 = 0, pad3: UInt8 = 0 }
typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
struct SMCParam {
    var key: UInt32 = 0
    var version = SMCVersion()
    var limits = SMCPLimit()
    var info = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// A read-only connection to the SMC. Use it from one queue at a time. It only ever sends the two read commands.
final class SMCConnection {
    private static let readKeyInfo: UInt8 = 9
    private static let readBytes: UInt8 = 5
    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: SMCKeyInfo] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private func call(_ input: SMCParam) -> SMCParam? {
        var input = input
        var output = SMCParam()
        var size = MemoryLayout<SMCParam>.stride
        guard IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParam>.stride, &output, &size) == KERN_SUCCESS,
              output.result == 0 else { return nil }
        return output
    }

    private static func code(_ key: String) -> UInt32? {
        let u = Array(key.utf8)
        return u.count == 4 ? u.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } : nil
    }

    private static func name(_ type: UInt32) -> String {
        String(decoding: [UInt8(type >> 24), UInt8((type >> 16) & 255), UInt8((type >> 8) & 255), UInt8(type & 255)], as: UTF8.self)
    }

    /// The key as a number, or nil if the Mac has no such key or its type is one we do not decode.
    func number(_ key: String) -> Double? {
        guard let code = Self.code(key) else { return nil }
        var info = infoCache[code]
        if info == nil {
            var q = SMCParam(); q.key = code; q.command = Self.readKeyInfo
            info = call(q)?.info
            infoCache[code] = info
        }
        guard let known = info, known.size > 0, known.size <= 32 else { return nil }
        var q = SMCParam(); q.key = code; q.info = known; q.command = Self.readBytes
        guard var out = call(q) else { return nil }
        let raw = withUnsafeBytes(of: &out.bytes) { Array($0.prefix(Int(known.size))) }
        return SMCDecode.number(type: Self.name(known.type), bytes: raw)
    }
}

// MARK: the named thermal sensors (read only)

// These four functions are in IOKit but not in its public headers. They are the way System Information's own sensors and every
// Apple Silicon monitor read temperatures without a password. If a future macOS drops them the app fails to start, which the
// start-up test in CI would show, and the tab shows "no sensors" when they exist but return nothing.
@_silgen_name("IOHIDEventSystemClientCreate") private func hidClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func hidClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func hidClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func hidServiceCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func hidServiceCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue") private func hidEventFloatValue(_ event: AnyObject, _ field: Int32) -> Double

final class HIDThermalSensors {
    private static let temperatureEvent: Int64 = 15        // kIOHIDEventTypeTemperature
    private let client: AnyObject?

    init() {
        client = hidClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let c = client { _ = hidClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) }   // Apple vendor page, temperature sensors
    }

    /// Every sensor that answers, with the name it gives itself.
    func read() -> [(name: String, celsius: Double)] {
        guard let c = client, let services = hidClientCopyServices(c)?.takeRetainedValue() else { return [] }
        var out: [(String, Double)] = []
        for i in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: AnyObject.self)
            guard let name = hidServiceCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = hidServiceCopyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            out.append((name, hidEventFloatValue(event, Int32(Self.temperatureEvent << 16))))
        }
        return out
    }
}

// MARK: reading everything

/// Reads fans and temperatures. Use it from one queue at a time (the Activity window uses its own).
final class ThermalReader {
    private let smc = SMCConnection()
    private let hid = HIDThermalSensors()

    func read() -> ThermalReadout {
        var out = ThermalReadout()
        if let smc = smc {
            out.smcAvailable = true
            if let n = smc.number("FNum"), (0...Double(ThermalAnalysis.maxFans)).contains(n) {
                out.fanCount = Int(n)
                out.fans = (0..<Int(n)).compactMap { ThermalAnalysis.fan(index: $0, number: smc.number) }
            }
        }
        let raw = hid.read()
        out.sensorsAvailable = !raw.isEmpty
        out.sensors = raw.enumerated().compactMap { ThermalAnalysis.sensor(id: $0.offset, name: $0.element.name, celsius: $0.element.celsius) }
        return out
    }
}
