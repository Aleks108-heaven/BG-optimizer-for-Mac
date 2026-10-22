// Fans and temperatures (read only): decoding the SMC's bytes, grouping the named sensors, refusing nonsense values, and a real read.
// The real read must pass on a Mac without fans or sensors too (a virtual machine, for example): it checks consistency, not presence.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

// --- the structure handed to the SMC must be 80 bytes (a Swift layout slip made every call fail with "bad argument") ---------------
check(MemoryLayout<SMCParam>.size == 80 && MemoryLayout<SMCParam>.stride == 80, "SMC call structure is 80 bytes (size \(MemoryLayout<SMCParam>.size))")
check(MemoryLayout<SMCKeyInfo>.size == 12 && MemoryLayout<SMCPLimit>.size == 16 && MemoryLayout<SMCVersion>.size == 6, "its parts are 12, 16 and 6 bytes")
check(MemoryLayout<SMCParam>.offset(of: \SMCParam.result) == 40 && MemoryLayout<SMCParam>.offset(of: \SMCParam.bytes) == 48, "result is at byte 40 and the data at byte 48, as in C")

// --- decoding ---------------------------------------------------------------------------------------------------------------------
check(SMCDecode.number(type: "flt ", bytes: [0, 224, 149, 68]) == 1199, "float: bytes seen on a real fan minimum decode to 1199")
check(SMCDecode.number(type: "flt ", bytes: [0, 248, 224, 69]) == 7199, "float: the real fan maximum decodes to 7199")
check(SMCDecode.number(type: "flt ", bytes: [0, 0, 0, 0]) == 0, "float: zero is zero (a stopped fan)")
check(SMCDecode.number(type: "flt ", bytes: [0, 0, 192, 127]) == nil, "float: NaN is refused")
check(SMCDecode.number(type: "flt ", bytes: [0, 0, 128, 127]) == nil, "float: infinity is refused")
check(SMCDecode.number(type: "flt ", bytes: [1, 2, 3]) == nil, "float: a wrong length is refused")
check(SMCDecode.number(type: "ui8 ", bytes: [3]) == 3, "ui8")
check(SMCDecode.number(type: "ui16", bytes: [1, 2]) == 258, "ui16 is big-endian")
check(SMCDecode.number(type: "ui32", bytes: [0, 0, 6, 226]) == 1762, "ui32 is big-endian (the real key count)")
check(SMCDecode.number(type: "ui8 ", bytes: [1, 2]) == nil, "ui8 with two bytes is refused")
check(SMCDecode.number(type: "ioft", bytes: [1, 2, 3, 4, 5, 6, 7, 8]) == nil, "a type we do not decode is refused, not guessed")
check(SMCDecode.number(type: "", bytes: []) == nil, "empty type and bytes")

// --- one fan ----------------------------------------------------------------------------------------------------------------------
func keys(_ d: [String: Double]) -> (String) -> Double? { { d[$0] } }
let real: [String: Double] = ["F0Ac": 0, "F0Mn": 1199, "F0Mx": 7199, "F0Tg": 0, "F0Md": 0]
let stopped = ThermalAnalysis.fan(index: 0, number: keys(real))
check(stopped == FanReading(index: 0, rpm: 0, minRPM: 1199, maxRPM: 7199, targetRPM: 0, manual: false), "the real fan: stopped, automatic, 1199 to 7199 rpm")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Ac": 3200]) { $1 }))?.rpm == 3200, "a spinning fan")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Md": 1]) { $1 }))?.manual == true, "mode 1 is shown as not automatic")
check(ThermalAnalysis.fan(index: 0, number: keys(real.filter { $0.key != "F0Md" }))?.manual == false, "no mode key: treated as automatic")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Tg": 99999]) { $1 }))?.targetRPM == nil, "a nonsense target is dropped, the fan is still shown")
check(ThermalAnalysis.fan(index: 1, number: keys(real)) == nil, "fan 2 does not exist on a one-fan Mac")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Mn": 8000]) { $1 })) == nil, "minimum above maximum: left out")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Ac": -5]) { $1 })) == nil, "negative speed: left out")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Mx": 0]) { $1 })) == nil, "maximum 0: left out")
check(ThermalAnalysis.fan(index: 0, number: keys(real.merging(["F0Ac": 50_000]) { $1 })) == nil, "50,000 rpm: left out")
check(ThermalAnalysis.fan(index: 0, number: keys(["F0Ac": 0, "F0Mn": 1199])) == nil, "a missing maximum: left out")

// --- sensors, using the names and values read from a real M1 MacBook Pro ----------------------------------------------------------
let real57 = """
PMU tdev7|34.9
pACC MTR Temp Sensor2|32.2
NAND CH0 temp|32.0
PMU2 tdev4|32.9
gas gauge battery|30.1
PMU tdev8|38.0
eACC MTR Temp Sensor0|30.2
pACC MTR Temp Sensor8|34.8
PMU2 tdie7|37.2
PMU2 tdev1|34.7
pACC MTR Temp Sensor5|32.0
PMU2 tdie5|40.4
pACC MTR Temp Sensor9|33.0
PMU TP3w|40.4
gas gauge battery|30.6
GPU MTR Temp Sensor1|30.0
PMU tcal|51.9
PMU2 tdie4|40.3
gas gauge battery|30.0
ANE MTR Temp Sensor1|30.0
pACC MTR Temp Sensor4|33.5
PMU2 tdev5|32.3
PMU tdie7|40.8
PMGR SOC Die Temp Sensor0|33.8
PMGR SOC Die Temp Sensor2|33.8
ISP MTR Temp Sensor5|30.0
PMU2 tdev3|34.0
gas gauge battery|30.6
PMU2 tdie3|39.4
SOC MTR Temp Sensor2|31.0
PMU tdev2|34.5
PMU tdie5|39.5
PMU2 tdie2|39.4
PMU tdev1|35.0
PMU2 tcal|51.9
pACC MTR Temp Sensor3|29.6
GPU MTR Temp Sensor4|30.0
PMU tdie4|39.0
PMU2 tdie1|40.2
SOC MTR Temp Sensor0|31.9
PMU tdie8|37.6
eACC MTR Temp Sensor3|32.4
SOC MTR Temp Sensor1|34.6
PMU tdev5|-21.7
gas gauge battery|30.0
PMU tdev4|-21.6
PMU2 tdie6|40.3
PMU tdie2|40.4
PMU tdie6|40.1
PMU tdev6|34.7
PMU tdev3|34.7
gas gauge battery|30.6
PMU2 tdie8|40.0
pACC MTR Temp Sensor7|31.9
PMU2 tdev2|34.1
PMGR SOC Die Temp Sensor1|33.9
PMU tdie1|40.7
"""
let raw: [(String, Double)] = real57.split(separator: "\n").compactMap { line in
    let p = line.split(separator: "|"); return p.count == 2 ? (String(p[0]), Double(p[1]) ?? .nan) : nil
}
let sensors = raw.enumerated().compactMap { ThermalAnalysis.sensor(id: $0.offset, name: $0.element.0, celsius: $0.element.1) }
check(raw.count == 57, "fixture: 57 sensors from a real Mac")
check(sensors.count == 53, "53 usable: 57 minus 2 calibration values (tcal) and 2 impossible readings (-21.7, -21.6); got \(sensors.count)")
check(!sensors.contains { $0.name.contains("tcal") }, "calibration values are never shown as temperatures")
check(!sensors.contains { $0.celsius < 0 }, "a negative reading is never shown")
let sum = ThermalAnalysis.summaries(sensors)
func count(_ g: SensorGroup) -> Int { sum.first { $0.group == g }?.sensors.count ?? 0 }
check(count(.chipDie) == 15 && count(.cpuPerformance) == 7 && count(.cpuEfficiency) == 2 && count(.gpu) == 2 && count(.neural) == 1,
      "groups: 15 die, 7 performance cores, 2 efficiency cores, 2 GPU, 1 Neural Engine")
check(count(.soc) == 6 && count(.battery) == 6 && count(.storage) == 1 && count(.other) == 13, "groups: 6 SoC, 6 battery, 1 SSD, 13 other")
check(sum.map { $0.group } == SensorGroup.allCases, "every group is present, in the documented order")
check(sum.allSatisfy { s in s.hottest == s.sensors.map { $0.celsius }.max() && s.average <= s.hottest && s.average >= (s.sensors.map { $0.celsius }.min() ?? 0) }, "hottest is the maximum, the average lies between the minimum and the maximum")
check(sum.allSatisfy { s in s.sensors.map { $0.name } == s.sensors.map { $0.name }.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }, "sensors inside a group are sorted by name, 'Sensor2' before 'Sensor10'")
check(Set(sensors.map { $0.id }).count == sensors.count, "ids are unique even when names repeat (six 'gas gauge battery')")

// each name rule on its own
func g(_ n: String) -> SensorGroup? { ThermalAnalysis.group(forName: n) }
check(g("pACC MTR Temp Sensor2") == .cpuPerformance && g("eACC MTR Temp Sensor0") == .cpuEfficiency && g("GPU MTR Temp Sensor1") == .gpu && g("ANE MTR Temp Sensor1") == .neural, "name rules: cores, GPU, Neural Engine")
check(g("PMU tdie1") == .chipDie && g("PMU2 tdie7") == .chipDie && g("PMGR SOC Die Temp Sensor0") == .soc && g("SOC MTR Temp Sensor2") == .soc, "name rules: die sensors, SoC (a 'Die' inside an SoC name is not a die sensor)")
check(g("gas gauge battery") == .battery && g("NAND CH0 temp") == .storage && g("PMU tdev1") == .other && g("PMU TP3w") == .other && g("something new") == .other, "name rules: battery, SSD, anything unknown is Other")
check(g("PMU tcal") == nil && g("PMU2 TCAL") == nil, "name rules: calibration values are not sensors")
check(g("") == .other, "an empty name is Other, not a crash")

// refusing nonsense
check(ThermalAnalysis.sensor(id: 0, name: "PMU tdie1", celsius: .nan) == nil && ThermalAnalysis.sensor(id: 0, name: "PMU tdie1", celsius: .infinity) == nil, "NaN and infinity are refused")
check(ThermalAnalysis.sensor(id: 0, name: "PMU tdie1", celsius: 0) == nil && ThermalAnalysis.sensor(id: 0, name: "PMU tdie1", celsius: 150) == nil && ThermalAnalysis.sensor(id: 0, name: "PMU tdie1", celsius: 149.9) != nil, "0 and 150 are refused, 149.9 is shown")
check(ThermalAnalysis.sensor(id: 0, name: "gpu\n\u{202E}x", celsius: 40)?.name.contains("\n") == false, "a name with a newline or a right-to-left override is cleaned")

// colors: thresholds differ by what is measured
func level(_ group: SensorGroup, _ c: Double) -> TempLevel { SensorGroupSummary(group: group, sensors: [], hottest: c, average: c).level }
check(level(.cpuPerformance, 84.9) == .ok && level(.cpuPerformance, 85) == .warm && level(.cpuPerformance, 99.9) == .warm && level(.cpuPerformance, 100) == .hot, "chip: warm from 85, hot from 100")
check(level(.battery, 44.9) == .ok && level(.battery, 45) == .warm && level(.battery, 55) == .hot, "battery: warm from 45, hot from 55")
check(level(.storage, 69.9) == .ok && level(.storage, 70) == .warm && level(.storage, 80) == .hot, "SSD: warm from 70, hot from 80")
check(ThermalAnalysis.summaries([]).isEmpty, "no sensors: no groups")

// --- every title has a Ukrainian text (the build also checks this) ----------------------------------------------------------------
L10n.apply(.ukrainian)
check(SensorGroup.allCases.allSatisfy { L10n.string($0.title) != $0.title || [.gpu, .neural].contains($0) }, "every group title is translated (GPU and Neural Engine stay as Apple's product names)")
L10n.apply(.english)

// --- a real read: it must be consistent whether or not this Mac has fans -------------------------------------------------------------
let reader = ThermalReader()
let now = reader.read()
print("  info smc=\(now.smcAvailable) fanCount=\(now.fanCount.map(String.init) ?? "nil") fans=\(now.fans.count) sensors=\(now.sensors.count) hidAnswered=\(now.sensorsAvailable)")
for f in now.fans { print("  info fan \(f.index): \(Int(f.rpm)) rpm, \(Int(f.minRPM))-\(Int(f.maxRPM)), manual=\(f.manual)") }
check(now.fans.count <= (now.fanCount ?? 0), "never more fans than the SMC says")
check(now.fans.allSatisfy { $0.rpm <= $0.maxRPM * 1.5 && $0.minRPM <= $0.maxRPM }, "every fan read is sane")
check(now.sensors.allSatisfy { ThermalAnalysis.isPlausible($0.celsius) }, "every temperature read is plausible")
check(now.fanCount == nil || now.smcAvailable, "a fan count only comes from a working SMC connection")
check(now.sensors.isEmpty || now.sensorsAvailable, "sensors only come from a sensor service that answered")
let again = reader.read()
check(again.fanCount == now.fanCount && again.fans.count == now.fans.count, "a second read finds the same fans")

// the reader is meant to live for the whole session: 300 reads must not grow memory (a missing release would)
func footprint() -> Int {
    var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? Int(info.resident_size) : 0
}
for _ in 0..<20 { _ = reader.read() }                      // warm up
let before = footprint()
for _ in 0..<300 { _ = reader.read() }
let grown = Double(footprint() - before) / 1_048_576
check(grown < 8, String(format: "300 reads grow memory by %.1f MB (limit 8)", grown))

// opening and dropping readers must not leak the connection either
let beforeOpen = footprint()
for _ in 0..<100 { _ = ThermalReader().read() }
let grownOpen = Double(footprint() - beforeOpen) / 1_048_576
check(grownOpen < 20, String(format: "100 readers opened, used and dropped grow memory by %.1f MB (limit 20)", grownOpen))

print(failures == 0 ? "THERMAL: ALL PASSED" : "THERMAL: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
