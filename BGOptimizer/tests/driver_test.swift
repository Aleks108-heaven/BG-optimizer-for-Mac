// Drivers tab: reading `systemextensionsctl list`, the decision for every kind of row, a scan of stand-in folders, and a real read.
// Read only: the real part only lists what is there.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

// --- reading the list (text copied from a real Mac, tab separated) ----------------------------------------------------
let header = "enabled\tactive\tteamID\tbundleID (version)\tname\t[state]\n"
let sample = "5 extension(s)\n"
    + "--- com.apple.system_extension.network_extension (Go to 'System Settings' to modify these system extension(s))\n" + header
    + "*\t*\tJ6S6Q257EK\tch.protonvpn.mac.WireGuard-Extension (5.1.0/2464805.2506251706)\tProtonVPN WireGuard\t[activated enabled]\n"
    + "--- com.apple.system_extension.endpoint_security (Go to 'System Settings' to modify these system extension(s))\n" + header
    + "\t*\tGVZRY6KDKR\tcom.malwarebytes.mbam.engine.sys.ext (5.26.1/5.26.1.4152)\tMalwarebytes Engine\t[activated disabled]\n"
    + "\t*\t4HMJQ7V3SX\tcom.swiftlydetecting.agent.securityextension (2.1.0/1)\tMac Monitor Security Extension\t[activated disabled]\n"
    + "--- com.apple.system_extension.driver_extension (Go to 'System Settings' to modify these system extension(s))\n" + header
    + "\t\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.0.0/1)\tKarabiner VirtualHID\t[activated waiting for user]\n"
    + "\t\tABCDE12345\tcom.acme.old (1.0/1)\tAcme Old\t[terminated waiting to uninstall on reboot]\n"
    + "*\t*\tUBF8T346G9\tcom.microsoft.wdav.epsext (101.26072.0017/101.26072.0017)\tMicrosoft Defender Endpoint Security Extension\t[activated enabled]\n"
    + "*\t*\t0000000000\tcom.apple.something (1.0/1)\tApple's own\t[activated enabled]\n"

let recs = DriverParsers.parseSystemExtensions(sample)
check(recs.count == 7, "list: seven rows read; the count line, headers and --- lines are skipped (got \(recs.count))")
check(recs.first == SystemExtensionRecord(category: "network_extension", team: "J6S6Q257EK", identifier: "ch.protonvpn.mac.WireGuard-Extension",
                                         version: "5.1.0", name: "ProtonVPN WireGuard", state: .enabled), "list: every field of a row, version without the build number")
check(recs.first { $0.identifier.contains("malwarebytes") }?.state == .disabled, "list: a row with an empty first column still reads (disabled)")
check(recs.first { $0.identifier.contains("pqrs") }?.state == .waitingForUser && recs.first { $0.identifier.contains("pqrs") }?.category == "driver_extension", "list: waiting for approval, and the kind from the --- line")
check(recs.first { $0.identifier == "com.acme.old" }?.state == .removing, "list: 'terminated waiting to uninstall on reboot' is being removed")
check(DriverParsers.parseSystemExtensions("").isEmpty && DriverParsers.parseSystemExtensions("0 extension(s)\n").isEmpty, "list: empty text and a zero count give nothing")
check(DriverParsers.parseSystemExtensions("garbage\nwith no tabs\n").isEmpty, "list: lines that are not rows are ignored")
check(DriverParsers.parseState("[activated enabled]") == .enabled && DriverParsers.parseState("[activated disabled]") == .disabled, "state: enabled and disabled are not confused")
check(DriverParsers.parseState("[something new]") == .unknown, "state: an unknown wording is unknown, not guessed")

// --- the decision (a table: state x maker's app) ------------------------------------------------------------------------
func v(_ kind: DriverKind, _ state: ExtensionState?, _ present: Bool?) -> DriverStatus {
    DriverScanner.classify(kind: kind, state: state, maker: present == nil ? nil : "acme", makerPresent: present).status
}
check(v(.systemExtension, .disabled, false) == .probablyUnused, "decide: switched off and no app from the maker -> probably not in use")
check(v(.systemExtension, .disabled, true) == .switchedOff, "decide: switched off but the maker's app is installed -> only switched off")
check(v(.systemExtension, .enabled, false) == .makerAppMissing, "decide: on, but no app from the maker -> maker's app not found (not 'unused')")
check(v(.systemExtension, .enabled, true) == .enabled, "decide: on, and the maker's app is installed -> enabled")
check(v(.systemExtension, .waitingForUser, false) == .pending && v(.systemExtension, .removing, true) == .pending, "decide: waiting for approval and being removed are pending whatever the maker")
check(v(.systemExtension, .unknown, true) == .installed, "decide: an unknown state is not called enabled")
check(v(.kernelExtension, nil, true) == .legacy && v(.kernelExtension, nil, false) == .makerAppMissing, "decide: a kernel extension is legacy, and worse when its app is gone")
check(v(.helperTool, nil, true) == .installed && v(.helperTool, nil, false) == .makerAppMissing, "decide: a helper tool is only 'installed' when its app is there; use cannot be known")
check(v(.helperTool, nil, nil) == .installed, "decide: a name that says nothing about a maker is never flagged")
check(DriverStatus.probablyUnused.rawValue < DriverStatus.makerAppMissing.rawValue && DriverStatus.makerAppMissing.rawValue < DriverStatus.enabled.rawValue, "order: the most interesting come first")

// --- a scan of stand-in folders ---------------------------------------------------------------------------------------
let fm = FileManager.default
let W = fm.temporaryDirectory.appendingPathComponent("bgopt-driver-\(getpid())")
try? fm.removeItem(at: W)
let kexts = W.appendingPathComponent("Extensions").path, helpers = W.appendingPathComponent("Helpers").path
try? fm.createDirectory(atPath: kexts, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: helpers, withIntermediateDirectories: true)
func kext(_ file: String, _ id: String, _ version: String) {
    let dir = kexts + "/" + file + "/Contents"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleName": file.replacingOccurrences(of: ".kext", with: "")]
    try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: dir + "/Info.plist"), options: .atomic)
}
kext("Gone.kext", "com.gone.driver", "3.0")
kext("Here.kext", "com.adobe.driver", "1.2")
kext("Apple.kext", "com.apple.driver.x", "1")
kext("Evil.kext", "com.evil.k", "9.\u{202E}0\u{200B}.1 " + String(repeating: "A", count: 500))
for h in ["com.acme.helper", "com.adobe.thing", "LegacyTool", "com.apple.foo", ".hidden", "com.evil.\u{202E}gpj"] { fm.createFile(atPath: helpers + "/" + h, contents: Data("x".utf8)) }

let installed: Set<String> = ["com.adobe.reader", "org.pqrs.karabiner-elements.settings", "com.microsoft.word"]
var asked: [String] = []
let items = DriverScanner.scan(extensionList: sample, kextDir: kexts, helperDir: helpers, installedIDs: installed,
                               appExists: { asked.append($0); return $0 == "ch.protonvpn.mac" })
func item(_ id: String) -> DriverItem? { items.first { $0.identifier == id } }

check(item("com.malwarebytes.mbam.engine.sys.ext")?.status == .probablyUnused, "scan: Malwarebytes Engine (off, no Malwarebytes app) -> probably not in use")
check(item("com.swiftlydetecting.agent.securityextension")?.status == .probablyUnused, "scan: Mac Monitor extension (off, no app) -> probably not in use")
check(item("org.pqrs.Karabiner-DriverKit-VirtualHIDDevice")?.status == .pending, "scan: a driver waiting for approval is pending, not 'unused'")
check(item("com.acme.old")?.status == .pending, "scan: an extension waiting to be removed is pending")
check(item("com.microsoft.wdav.epsext")?.status == .enabled, "scan: Defender extension, another Microsoft app installed -> enabled (a maker-level match: it cannot miss an owner, it may miss an orphan)")
check(item("ch.protonvpn.mac.WireGuard-Extension")?.status == .enabled && asked.contains("ch.protonvpn.mac"), "scan: an app outside the usual folders is found by asking macOS for the shorter identifier")
check(item("com.apple.something") == nil && item("com.apple.driver.x") == nil && item("com.apple.foo") == nil, "scan: Apple's own items are never listed")
check(item("com.gone.driver")?.status == .makerAppMissing && item("com.gone.driver")?.info == "3.0", "scan: a legacy kernel extension whose app is gone, with its version")
check({ let i = item("com.evil.k")?.info ?? ""; return !i.isEmpty && i.count <= 40 && plainText(i) == i }(), "scan: a hostile version (direction-changing and zero-width characters, 500 letters) is shown as short plain text")
check(item("com.adobe.driver")?.status == .legacy, "scan: a legacy kernel extension whose maker's app is installed -> legacy")
check(item("com.acme.helper")?.status == .makerAppMissing && item("com.acme.helper")?.kind == .helperTool, "scan: a root helper whose maker has no app -> maker's app not found")
check(item("com.adobe.thing")?.status == .installed, "scan: a root helper whose maker has an app -> only installed (not flagged)")
check(item("LegacyTool")?.status == .installed && item("LegacyTool")?.detailArg == nil, "scan: a helper with no maker in its name is never flagged")
check(item(".hidden") == nil && !items.contains { $0.identifier.unicodeScalars.contains { $0.value == 0x202E } }, "scan: hidden files and names with direction-changing characters are not listed")
check(item("com.acme.helper")?.info?.count == 10 && item("com.acme.helper")?.info?.contains("-") == true, "scan: a helper shows the day it was installed")
check(items.first?.status == .probablyUnused, "scan: the list starts with what is most likely unused")
check(Set(items.map { $0.id }).count == items.count, "scan: every row has its own id")
check(DriverScanner.scan(extensionList: "", kextDir: W.path + "/nope", helperDir: W.path + "/nope2", installedIDs: [], appExists: { _ in false }).isEmpty, "scan: nothing found and missing folders are fine")
try? fm.removeItem(at: W)

// --- the real Mac (read only) -----------------------------------------------------------------------------------------
let real = DriverScanner.read()
print("  info extensionsRead=\(real.extensionsRead), rows=\(real.items.count), probably unused=\(real.items.filter { $0.status == .probablyUnused }.count)")
check(real.items.allSatisfy { !$0.identifier.isEmpty && !$0.identifier.lowercased().hasPrefix("com.apple.") && plainText($0.name) == $0.name }, "real: no empty id, no com.apple. item, plain names")
check(Set(real.items.map { $0.id }).count == real.items.count, "real: every row has its own id")
check(real.items == real.items.sorted { ($0.statusRank, $0.name.lowercased()) < ($1.statusRank, $1.name.lowercased()) }, "real: sorted most interesting first")
if real.extensionsRead {
    let listed = DriverParsers.parseSystemExtensions(ToolRunner.run("/usr/bin/systemextensionsctl", ["list"], timeout: 15).output)
        .filter { !$0.identifier.lowercased().hasPrefix("com.apple.") }
    check(real.items.filter { $0.kind == .systemExtension }.count == listed.count, "real: as many system extensions as macOS lists (\(listed.count))")
}
print(failures == 0 ? "DRIVERS: ALL PASSED" : "DRIVERS: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
