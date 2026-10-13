// Startup items: parsing (with fixed sample text), scanning, the rules for changing, and a real read of this Mac.
// The change tests use a temporary folder and a unique test label; launchd keeps a tiny "enabled" note for that label afterwards.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

// ---- parsing
let btmSample = """
========================
 Records for UID 501 : AAAA
========================
   #1:
        Name: Microsoft OneDrive
        Developer Name: Microsoft OneDrive
        Type: developer (0x20)
        Disposition: [disabled, allowed, not notified] (0x2)
        Identifier: Microsoft OneDrive
        URL: (null)
   #2:
        Name: OneDrive
        Developer Name: Microsoft OneDrive
        Type: legacy daemon (0x10010)
        Disposition: [enabled, disallowed, notified] (0x9)
        Identifier: 16.com.microsoft.OneDriveUpdaterDaemon
        URL: /Library/LaunchDaemons/com.microsoft.OneDriveUpdaterDaemon.plist
        Executable Path: /Applications/OneDrive.app/Contents/MacOS/OneDriveUpdaterDaemon
   #3:
        Name: ollama
        Developer Name: (null)
        Type: legacy agent (0x10008)
        Disposition: [enabled, allowed, notified] (0xb)
        Identifier: 8.homebrew.mxcl.ollama
        URL: /Users/501/Library/LaunchAgents/homebrew.mxcl.ollama.plist
   #4:
        Name: BG Optimizer
        Type: app (0x2)
        Disposition: [enabled, allowed, notified] (0xb)
        Identifier: 2.com.alexxxela.bgoptimizer
"""
let recs = StartupParsers.parseBTM(btmSample)
check(recs.count == 4, "BTM: four records found")
check(recs[1].allowed == false, "BTM: 'disallowed' is read as switched off (not confused with 'allowed')")
check(recs[2].allowed == true && recs[2].developer == nil, "BTM: allowed agent, '(null)' developer becomes nil")
check(recs[1].type == "legacy daemon" && recs[3].type == "app", "BTM: types are read without the hex code")
check(StartupParsers.labelFromBTMIdentifier("16.com.microsoft.OneDriveUpdaterDaemon") == "com.microsoft.OneDriveUpdaterDaemon", "BTM: identifier prefix removed")
check(StartupParsers.labelFromBTMIdentifier("homebrew.mxcl.ollama") == "homebrew.mxcl.ollama", "BTM: a label that does not start with a number is left alone")

let disabledSample = "\n\tdisabled services = {\n\t\t\"com.a.one\" => disabled\n\t\t\"com.b.two\" => enabled\n\t\t\"com.c.three\" => true\n\t}\n"
let dis = StartupParsers.parsePrintDisabled(disabledSample)
check(dis["com.a.one"] == true && dis["com.b.two"] == false && dis["com.c.three"] == true && dis.count == 3, "print-disabled parsed")

let listSample = "PID\tStatus\tLabel\n942\t0\tcom.microsoft.wdav.tray\n-\t0\tcom.openssh.ssh-agent\n-\t78\tcom.openai.atlas.update-helper\n"
let lst = StartupParsers.parseLaunchList(listSample)
check(lst["com.microsoft.wdav.tray"] == .some(942), "launchctl list: running agent has a pid")
check(lst["com.openssh.ssh-agent"] != nil && lst["com.openssh.ssh-agent"]! == nil, "launchctl list: loaded but not running")

// ---- scanning plists
let tmp = NSTemporaryDirectory() + "bgopt-startup-\(UUID().uuidString)"
let agents = tmp + "/LaunchAgents"
try! FileManager.default.createDirectory(atPath: agents, withIntermediateDirectories: true)
func writePlist(_ name: String, _ dict: [String: Any]) {
    (dict as NSDictionary).write(toFile: agents + "/" + name, atomically: true)
}
let testLabel = "com.example.bgopt.selftest.\(UUID().uuidString.prefix(8))"
writePlist("a.plist", ["Label": testLabel, "ProgramArguments": ["/usr/bin/true"], "RunAtLoad": true, "KeepAlive": true])
writePlist("b.plist", ["Label": "com.example.sched", "Program": "/Applications/Foo.app/Contents/MacOS/foo", "StartInterval": 3600])
writePlist("c.plist", ["Label": "com.example.demand", "ProgramArguments": ["/usr/bin/true"]])
writePlist("d.plist", ["Label": "com.apple.fake", "ProgramArguments": ["/usr/bin/true"], "RunAtLoad": true])
writePlist("e.plist", ["Label": "com.eset.fake", "ProgramArguments": ["/usr/bin/true"], "RunAtLoad": true])
writePlist("f.plist", ["Label": "com.example.off", "ProgramArguments": ["/usr/bin/true"], "RunAtLoad": true, "Disabled": true])
let scanned = StartupReader.scan(agents)
func when(_ l: String) -> String { scanned.first { $0.label == l }?.startsWhen ?? "?" }
check(scanned.count == 6, "scan: all six plists read")
check(when(testLabel) == "At login, kept running", "scan: RunAtLoad + KeepAlive")
check(when("com.example.sched") == "On a schedule", "scan: StartInterval")
check(when("com.example.demand") == "On demand", "scan: none of the start keys")
check(scanned.first { $0.label == "com.example.off" }?.plistDisabled == true, "scan: Disabled key read")
check(StartupReader.displayName(btmName: nil, program: "/Applications/Foo.app/Contents/MacOS/foo", label: "com.example.sched") == "Foo", "display name from the app the program lives in")
check(StartupReader.displayName(btmName: "OneDrive", program: nil, label: "com.microsoft.x") == "OneDrive", "display name from System Settings when it is a real name")
check(StartupReader.displayName(btmName: "com.adobe.thing", program: "/usr/bin/true", label: "com.adobe.thing") == "true", "a label-like name is not used")

// ---- the rules for changing
func state(_ label: String) -> Bool? { StartupParsers.parsePrintDisabled(StartupReaderShell.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]))[label] }
func refused(_ label: String, _ file: String, dir: String = agents) -> Bool {
    do { try StartupControlAction.setEnabled(label: label, plistPath: file, enable: false, agentsDir: dir); return false } catch { return true }
}
let hasGUIDomain = !StartupReaderShell.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).isEmpty
if !hasGUIDomain { print("  skipped: this machine has no per-user launchd domain, so switching cannot be tested here") }
check(!hasGUIDomain || state(testLabel) == nil, "before: no override recorded for the test label")
if hasGUIDomain { do { try StartupControlAction.setEnabled(label: testLabel, plistPath: agents + "/a.plist", enable: false, agentsDir: agents); check(state(testLabel) == true, "switch OFF: launchd now lists it as disabled (read back)") }
catch { check(false, "switch OFF should work, got \(error)") }
do { try StartupControlAction.setEnabled(label: testLabel, plistPath: agents + "/a.plist", enable: true, agentsDir: agents); check(state(testLabel) == false, "switch ON: launchd lists it as enabled again (read back)") }
catch { check(false, "switch ON should work, got \(error)") } }
check(refused("com.apple.fake", agents + "/d.plist"), "refused: a macOS (com.apple.) item")
check(state("com.apple.fake") == nil, "  ... and nothing was recorded for it")
check(refused("com.eset.fake", agents + "/e.plist"), "refused: a security tool")
check(refused("com.alexxxela.bgoptimizer", agents + "/a.plist"), "refused: this app itself")
check(refused(testLabel, agents + "/b.plist"), "refused: the plist names a different label")
check(refused("com.example.demand", "/Library/LaunchAgents/com.microsoft.update.agent.plist"), "refused: a plist outside your own LaunchAgents folder")
check(refused("com.example.demand", agents + "/../LaunchAgents/../../etc/hosts"), "refused: path tricks")
check(refused("bad label; rm -rf /", agents + "/c.plist"), "refused: a label with spaces or shell characters")
let link = tmp + "/LaunchAgents/link.plist"
try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Library/LaunchAgents/com.microsoft.update.agent.plist")
check(refused("com.microsoft.update.agent", link), "refused: a symbolic link pointing out of your folder")

// ---- reading this Mac for real
let items = StartupReader.read()
print("  (this Mac: \(items.count) startup items; \(items.filter { if case .toggle = $0.control { return true }; return false }.count) can be switched here)")
let onCI = ProcessInfo.processInfo.environment["CI"] != nil
check(!items.isEmpty || onCI, "real read: finds startup items (a CI machine may have none)")
check(!items.contains { $0.label.hasPrefix("com.apple.") }, "real read: no macOS items listed")
check(items.allSatisfy { i in if case .toggle = i.control { return i.kind == .userAgent } else { return true } }, "real read: only your own agents can be toggled")
check(items.allSatisfy { i in if case .toggle = i.control { return !StartupReader.isSecurityTool(i.label + i.name) } else { return true } }, "real read: no security tool is toggleable")

try? FileManager.default.removeItem(atPath: tmp)
print(failures == 0 ? "STARTUP: ALL PASSED" : "STARTUP: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
