// Administrator actions: only the rules are tested (what may be removed, how a name gets into a command). Nothing here asks for a
// password or changes the Mac: the command that would be run as root is built and read, never run.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

let fm = FileManager.default
let root = NSTemporaryDirectory() + "bgopt-admin-\(getpid())"
let kexts = root + "/Extensions", helpers = root + "/Helpers", daemons = root + "/Daemons", backup = root + "/Backup"
for d in [kexts, helpers, daemons] { try! fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
defer { try? fm.removeItem(atPath: root) }
func touch(_ p: String) { fm.createFile(atPath: p, contents: Data("x".utf8)) }

func item(_ name: String, _ kind: DriverKind, _ status: DriverStatus, path: String?) -> DriverItem {
    DriverItem(name: name, identifier: name, kind: kind, info: nil, status: status, detail: "", detailArg: nil, path: path)
}
func plan(_ i: DriverItem, stamp: String = "20261027-201500") throws -> (command: String, path: String, backup: String) {
    try AdminActions.removalCommand(for: i, stamp: stamp, kextDir: kexts, helperDir: helpers, daemonDir: daemons, backupRoot: backup)
}
func refused(_ i: DriverItem, stamp: String = "20261027-201500") -> Bool { (try? plan(i, stamp: stamp)) == nil }

// --- quoting -------------------------------------------------------------------------------------------------------------------------
check(AdminActions.shellQuote("a b") == "'a b'" && AdminActions.shellQuote("it's") == "'it'\\''s'", "shell: single quotes, and a quote inside is closed, escaped and reopened")
check(AdminActions.appleScriptQuote("say \"hi\" \\ now") == "\"say \\\"hi\\\" \\\\ now\"", "AppleScript: quotes and backslashes escaped")
check(AdminActions.isPlainName("com.acme.helper") && AdminActions.isPlainName("Acme Driver.kext") && AdminActions.isPlainName("a_b-c@1+2"), "names: ordinary names are plain")
check(!AdminActions.isPlainName("") && !AdminActions.isPlainName(".hidden") && !AdminActions.isPlainName("a/b") && !AdminActions.isPlainName("../x") && !AdminActions.isPlainName("a;rm -rf") && !AdminActions.isPlainName("a$(x)") && !AdminActions.isPlainName("a\nb") && !AdminActions.isPlainName("a'b") && !AdminActions.isPlainName("a\"b"), "names: empty, hidden, with / ; $ ( newline or quotes are refused")
check(!AdminActions.isPlainName(String(repeating: "a", count: 201)), "names: too long is refused")
check(!AdminActions.isPlainName("com.acme.helper\n") && !AdminActions.isPlainName("com.acme.helper\r\n") && !AdminActions.isPlainName("a\u{2028}b"), "names: a trailing newline (which $ would let through) or a line separator is refused")
check(URL(fileURLWithPath: AdminActions.backupRoot).deletingLastPathComponent().path == "/Library", "backup: directly under /Library (root only), not under Application Support (the admin group can write there)")

// --- a helper tool ---------------------------------------------------------------------------------------------------------------------
touch(helpers + "/com.acme.helper"); touch(daemons + "/com.acme.helper.plist")
let h = item("com.acme.helper", .helperTool, .makerAppMissing, path: helpers + "/com.acme.helper")
let hp = try? plan(h)
check(hp != nil && hp!.path == helpers + "/com.acme.helper" && hp!.backup == backup + "/20261027-201500", "helper: allowed; it names the file and the backup folder with the time stamp")
check(hp?.command.contains("/bin/mkdir -p '\(backup)/20261027-201500'") == true && hp?.command.contains("/bin/launchctl bootout 'system/com.acme.helper'") == true
      && hp?.command.contains("/bin/mv '\(daemons)/com.acme.helper.plist'") == true && hp?.command.hasSuffix("/bin/mv '\(helpers)/com.acme.helper' '\(backup)/20261027-201500/'") == true, "helper: makes the folder, stops the job, takes its plist, moves the tool last (so the exit status is the move's)")
check(hp?.command.contains("rm ") == false && hp?.command.contains(" -rf") == false, "helper: nothing is deleted, only moved")

// --- a kernel extension ----------------------------------------------------------------------------------------------------------------
fm.createFile(atPath: kexts + "/Acme.kext", contents: nil)
let k = item("Acme", .kernelExtension, .probablyUnused, path: kexts + "/Acme.kext")
let kp = try? plan(k)
check(kp != nil && kp!.command == "/bin/mkdir -p '\(backup)/20261027-201500' && /bin/mv '\(kexts)/Acme.kext' '\(backup)/20261027-201500/'", "kext: made the folder and moved it, no launchd step")
check(refused(item("Acme", .kernelExtension, .probablyUnused, path: helpers + "/com.acme.helper")), "kext: a path in the other folder is refused")
touch(kexts + "/NotAKext"); check(refused(item("NotAKext", .kernelExtension, .probablyUnused, path: kexts + "/NotAKext")), "kext: a file that does not end in .kext is refused")

// --- what is never offered ---------------------------------------------------------------------------------------------------------------
for s in [DriverStatus.enabled, .switchedOff, .pending, .legacy, .installed] {
    check(!AdminActions.canRemove(item("com.acme.helper", .helperTool, s, path: helpers + "/com.acme.helper")) && refused(item("com.acme.helper", .helperTool, s, path: helpers + "/com.acme.helper")), "status \(s): not offered, and refused if asked anyway")
}
check(!AdminActions.canRemove(item("com.acme.ext", .systemExtension, .probablyUnused, path: nil)) && refused(item("com.acme.ext", .systemExtension, .probablyUnused, path: helpers + "/com.acme.helper")), "a system extension is never removable by the app")
check(!AdminActions.canRemove(item("x", .helperTool, .probablyUnused, path: nil)), "no path: not offered")
touch(helpers + "/com.apple.thing")
check(refused(item("com.apple.thing", .helperTool, .makerAppMissing, path: helpers + "/com.apple.thing")), "macOS's own (com.apple.) is refused")
touch(helpers + "/com.malwarebytes.mbam.helper")
check(refused(item("com.malwarebytes.mbam.helper", .helperTool, .makerAppMissing, path: helpers + "/com.malwarebytes.mbam.helper")), "a security tool is refused")
check(refused(item("x", .helperTool, .makerAppMissing, path: helpers + "/../Helpers/com.acme.helper")), "a path with .. is refused (not exactly one level inside the folder)")
check(refused(item("x", .helperTool, .makerAppMissing, path: helpers + "/missing")), "a file that is not there is refused")
try? fm.createSymbolicLink(atPath: helpers + "/com.acme.link", withDestinationPath: "/etc/hosts")
check(refused(item("com.acme.link", .helperTool, .makerAppMissing, path: helpers + "/com.acme.link")), "a symbolic link is refused (it could point anywhere)")
check(refused(h, stamp: "20261027-201500\n"), "a time stamp with a trailing newline is refused")
check(refused(h, stamp: "x; rm -rf /") && refused(h, stamp: "2026-10-27") && refused(h, stamp: ""), "a time stamp that is not exactly 8 digits, a dash, 6 digits is refused")
check(AdminActions.stampNow(Date(timeIntervalSince1970: 0)).range(of: #"^[0-9]{8}-[0-9]{6}$"#, options: .regularExpression) != nil, "the real time stamp has the accepted shape")

// --- the list is read again before anything is moved ---------------------------------------------------------------------------------------
do { _ = try AdminActions.removeDriver(h, rescan: { [] }); check(false, "rescan: a driver that is no longer listed is refused") }
catch { check((error as? AdminError).map { if case .notAllowed = $0 { return true } else { return false } } ?? false, "rescan: a driver that is no longer listed is refused (before any password is asked)") }
let nowInstalled = item("com.acme.helper", .helperTool, .installed, path: helpers + "/com.acme.helper")
do { _ = try AdminActions.removeDriver(h, rescan: { [nowInstalled] }); check(false, "rescan: a driver whose maker app is now installed is refused") }
catch { check(error is AdminError, "rescan: a driver whose maker app is now installed is refused (before any password is asked)") }
do { _ = try AdminActions.removeDriver(h, rescan: { [item("com.acme.helper", .helperTool, .makerAppMissing, path: "/elsewhere/com.acme.helper")] }); check(false, "rescan: the same name at another path is refused") }
catch { check(error is AdminError, "rescan: the same name at another path is refused") }

// --- a launch daemon -------------------------------------------------------------------------------------------------------------------
check((try? AdminActions.daemonCommand(label: "com.acme.daemon", enable: false)) == "/bin/launchctl disable 'system/com.acme.daemon'", "daemon: disable system/<label>")
check((try? AdminActions.daemonCommand(label: "com.acme.daemon", enable: true)) == "/bin/launchctl enable 'system/com.acme.daemon'", "daemon: enable system/<label>")
for bad in ["com.apple.x", "com.malwarebytes.mbam", "a b", "a;b", "../x", "", "a/b", "$(id)"] {
    check((try? AdminActions.daemonCommand(label: bad, enable: false)) == nil, "daemon: '\(bad)' is refused")
}
let plistOK = daemons + "/com.acme.daemon.plist"
try! (PropertyListSerialization.data(fromPropertyList: ["Label": "com.acme.daemon", "Program": "/usr/local/bin/acme"], format: .xml, options: 0)).write(to: URL(fileURLWithPath: plistOK))
do { try AdminActions.setDaemonEnabled(label: "com.other.daemon", plistPath: plistOK, enable: false, daemonDir: daemons); check(false, "daemon: a plist that names another label is refused") }
catch { check((error as? AdminError).map { if case .notAllowed = $0 { return true } else { return false } } ?? false, "daemon: a plist that names another label is refused (before any password is asked)") }
do { try AdminActions.setDaemonEnabled(label: "com.acme.daemon", plistPath: root + "/elsewhere.plist", enable: false, daemonDir: daemons); check(false, "daemon: a plist outside the daemons folder is refused") }
catch { check(error is AdminError, "daemon: a plist outside the daemons folder is refused (before any password is asked)") }

print(failures == 0 ? "ADMIN ACTIONS: ALL PASSED" : "ADMIN ACTIONS: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
