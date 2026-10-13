// Drives the engine directly with harmless sleeper processes and checks the rules for changing jobs by hand.
// Priorities are read back with ps, independently of the engine. Run through tests/run.sh.
import AppKit

func pri(_ pid: Int32) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "pri=", "-p", "\(pid)"]
    let o = Pipe(); p.standardOutput = o; try? p.run(); p.waitUntilExit()
    return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
}
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

let a = CommandLine.arguments
let sleeper = Int32(a[1])!, chrome = Int32(a[2])!, finder = Int32(a[3]) ?? 0   // 0 = no system process available to test against (e.g. a CI machine)
let startOf = { (p: Int32) in ProcTable.sample(p, wantCPU: false)!.start }
let finderBefore = finder == 0 ? "" : pri(finder)
var cfg = Config(); cfg.interval = 1; cfg.sustain = 3; cfg.threshold = 90
let engine = Engine(cfg, ActionLog(echo: false))
var rows: [Int32: ActivityRow] = [:]
var notices: [(String, Bool)] = []
engine.onActivity = { r, _ in rows = Dictionary(uniqueKeysWithValues: r.map { ($0.pid, $0) }) }
engine.onNotice = { t, err in notices.append((t, err)) }
engine.start(); engine.setActivity(true)

func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
func lastNotice() -> (String, Bool)? { notices.last }
func isOK(_ r: ActivityRow?) -> Bool { if case .ok? = r.map({ $0.access }) { return true }; return false }
func isConfirm(_ r: ActivityRow?) -> Bool { if case .confirm? = r.map({ $0.access }) { return true }; return false }
func isLocked(_ r: ActivityRow?) -> Bool { if case .locked? = r.map({ $0.access }) { return true }; return false }

at(3)   { print("rows offered before any action")
          check(isOK(rows[sleeper]), "normal job may be slowed directly")
          check(isConfirm(rows[chrome]), "browser-like job needs a confirmation")
          if finder != 0 { check(isLocked(rows[finder]) && rows[finder]?.canProtect == false, "a system process is locked and cannot even be added to the list") } else { print("  skipped: no system process to test against") } }
at(3.2) { print("[A] slow a normal job"); engine.slowManually(pid: sleeper, start: startOf(sleeper), confirmedInteractive: false) }
at(4.5) { check(pri(sleeper) == "4", "priority 31 -> 4 (read with ps)"); check(rows[sleeper]?.canRestore == true, "table now offers Restore")
          check(lastNotice()?.1 == false, "success banner") }
at(4.6) { if finder != 0 { print("[B] try to slow a system process, even with confirmation"); engine.slowManually(pid: finder, start: startOf(finder), confirmedInteractive: true) } }
at(5.2) { if finder != 0 { check(pri(finder) == finderBefore, "system process priority unchanged"); check(lastNotice()?.1 == true, "refusal banner") } }
at(5.3) { print("[C] wrong identity (start time + 1)"); engine.slowManually(pid: chrome, start: startOf(chrome) + 1, confirmedInteractive: true) }
at(5.9) { check(pri(chrome) == "31", "browser-like job untouched"); check(lastNotice()?.1 == true, "refusal banner") }
at(6.0) { print("[D] browser-like job without confirmation"); engine.slowManually(pid: chrome, start: startOf(chrome), confirmedInteractive: false) }
at(6.6) { check(pri(chrome) == "31", "still untouched"); check(lastNotice()?.1 == true, "refusal banner") }
at(6.7) { print("[E] browser-like job with confirmation"); engine.slowManually(pid: chrome, start: startOf(chrome), confirmedInteractive: true) }
at(7.7) { check(pri(chrome) == "4", "slowed after confirmation") }
at(12)  { print("[F] 8 s later (an automatic slow-down would have been released after 3 s of quiet)")
          check(pri(sleeper) == "4" && pri(chrome) == "4", "manual slow-downs are still in place") }
at(12.2){ print("[G] restore"); engine.release(sleeper) }
at(13.5){ check(pri(sleeper) == "31", "restored to 31") }
at(13.6){ print("[H] slow again, then put the app on the protected list"); engine.slowManually(pid: sleeper, start: startOf(sleeper), confirmedInteractive: false) }
at(14.8){ check(pri(sleeper) == "4", "slowed again"); engine.update(cfg, protectedApps: ["bgsleeper"]) }
at(16.2){ check(pri(sleeper) == "31" && pri(chrome) == "31", "protecting released every process of that app")
          check(rows[sleeper]?.userEntry == "bgsleeper" && isLocked(rows[sleeper]), "row says it is on your list and is locked") }
at(16.3){ print("[I] try to slow a protected app"); engine.slowManually(pid: sleeper, start: startOf(sleeper), confirmedInteractive: true) }
at(17.2){ check(pri(sleeper) == "31", "refused"); check(lastNotice()?.1 == true, "refusal banner") }
at(17.5){ engine.shutdownSync()
          check(pri(sleeper) == "31" && pri(chrome) == "31", "everything is back to normal after quitting")
          print(failures == 0 ? "MANUAL CONTROL: ALL PASSED" : "MANUAL CONTROL: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
RunLoop.main.run()
