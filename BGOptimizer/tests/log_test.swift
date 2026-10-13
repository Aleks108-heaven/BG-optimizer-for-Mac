// The log: private permissions, one line per entry, Clear log. Uses BGOPT_LOG_DIR so the real log is never touched.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }
func mode(_ p: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: p)[.posixPermissions]) as? NSNumber)?.intValue ?? -1 }
let log = ActionLog()
log.write("TEST", "line one\nFAKE   forged second line\r\u{1B}[31m injected")
log.flush()
let text = (try? String(contentsOf: ActionLog.fileURL)) ?? ""
check(mode(ActionLog.dir.path) == 0o700, "log folder is private (700)")
check(mode(ActionLog.fileURL.path) == 0o600, "log file is private (600)")
check(text.split(separator: "\n").count == 1, "a multi-line message stays one line")
check(!text.unicodeScalars.contains { $0.value == 0x1B }, "escape characters are removed")
log.clear(); log.flush()
check(log.tail(10).split(separator: "\n").count == 1 && log.tail(10).contains("log cleared"), "Clear log leaves only the 'log cleared' line")
print(failures == 0 ? "LOG: ALL PASSED" : "LOG: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
