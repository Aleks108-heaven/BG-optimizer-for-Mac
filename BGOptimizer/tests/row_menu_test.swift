// The contents of the "…" menu for each kind of row, in both languages. Run through tests/run.sh.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }
func row(access: ManualAccess, lock: String? = nil, restore: Bool = false, protect: Bool = true, entry: String? = nil) -> ActivityRow {
    ActivityRow(pid: 1, start: 1, name: "x", protectName: "x", userEntry: entry, cpu: 1, status: .normal, detail: "", access: access,
                confirmText: nil, lockReason: lock, canRestore: restore, canProtect: protect)
}
func titles(_ e: [RowMenuEntry]) -> [String] { e.compactMap { if case let .item(t, _, _) = $0 { return t } else { return nil } } }
func has(_ e: [RowMenuEntry], enabled: Bool = true, _ f: (RowMenuAction) -> Bool) -> Bool {
    e.contains { if case let .item(_, en, a) = $0 { return en == enabled && f(a) } else { return false } }
}
for lang in [AppLanguage.english, .ukrainian] {
    L10n.apply(lang); print(lang.rawValue)
    let normal = rowMenuEntries(row(access: .ok)), edge = rowMenuEntries(row(access: .confirm)), slowed = rowMenuEntries(row(access: .locked, restore: true))
    let system = rowMenuEntries(row(access: .locked, lock: "System process", protect: false))
    let listed = rowMenuEntries(row(access: .locked, lock: "On your protected list", protect: false, entry: "blender"))
    let observe = rowMenuEntries(row(access: .locked, lock: tr("Turn off Observe only to change jobs")))
    check(has(normal) { if case .slow = $0 { return true }; return false }, "normal job: slow directly")
    check(has(edge) { if case .askToSlow = $0 { return true }; return false } && !has(edge) { if case .slow = $0 { return true }; return false }, "browser-like job: asks first, no direct item")
    check(has(slowed) { if case .restore = $0 { return true }; return false }, "slowed job: restore")
    check(!has(system) { if case .slow = $0 { return true }; return false } && !has(system) { if case .protect = $0 { return true }; return false }, "system process: nothing to do")
    check(has(system, enabled: false) { if case .none = $0 { return true }; return false }, "system process: disabled explanation")
    check(has(listed) { if case .unprotect = $0 { return true }; return false } && !has(listed) { if case .protect = $0 { return true }; return false }, "listed app: only 'remove from list'")
    check(titles(observe).first == tr("Turn off Observe only to change jobs"), "observe-only: the first line is the short instruction, with no 'Cannot change:' prefix")
    check(has(observe, enabled: false) { if case .none = $0 { return true }; return false }, "observe-only: that line is disabled")
}
print(failures == 0 ? "ROW MENU: ALL PASSED" : "ROW MENU: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
