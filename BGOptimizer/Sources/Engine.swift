import AppKit
import IOKit.pwr_mgt

struct Config {
    var threshold = 50.0     // % of one core that counts as busy
    var sustain = 12         // consecutive busy samples before acting (12 x 5 s = 1 min)
    var interval = 5.0       // seconds between samples
    var calmFactor = 0.25    // below threshold * calmFactor counts as calm
    var dryRun = false
}

struct Slowed: Codable {
    let pid: Int32
    let start: UInt64
    let name: String
    var since: Date? = nil      // when it was slowed (for the panel)
    var cpu: Int? = nil         // % of one core when it was slowed
    var manual: Bool? = nil     // slowed by you from the Activity window: not released just because it went quiet
}

enum JobStatus {
    case slowed       // in low-priority mode by this app
    case watching     // busy, but not for long enough yet
    case wouldSlow    // observe-only: it would be slowed
    case leftAlone    // interactive/media app, in front, or keeping the Mac awake
    case protected_   // system, security, local AI, or on your list
    case normal       // below the busy threshold
}

/// What "Slow down now" may do for one job.
enum ManualAccess {
    case ok          // allowed
    case confirm     // allowed after you confirm a warning (interactive or media apps, anything keeping the Mac awake)
    case locked      // refused (system, security, local AI, protected, in front, already in background mode)
}

/// One line of the Activity window.
struct ActivityRow: Identifiable {
    let pid: Int32
    let start: UInt64          // with pid, identifies the process (a pid can be reused)
    let name: String
    let protectName: String    // what "Never slow this app" adds to your list
    let userEntry: String?     // the entry on your list that protects it, if any
    let cpu: Double            // % of one core
    let status: JobStatus
    let detail: String
    let access: ManualAccess
    let confirmText: String?   // the warning shown before a confirmed slow-down
    let lockReason: String?    // why it cannot be changed (already translated)
    let canRestore: Bool
    let canProtect: Bool
    var memBytes: UInt64 = 0   // memory the process is responsible for (read only, shown in the Processes tab)
    var id: Int32 { pid }

    /// For sorting the Status column.
    var statusRank: Int {
        switch status {
        case .slowed: return 0
        case .watching: return 1
        case .wouldSlow: return 2
        case .leftAlone: return 3
        case .protected_: return 4
        case .normal: return 5
        }
    }
}

/// Finds user processes that stay busy in the background and puts them in macOS background mode.
/// Gives them back as soon as they come to the foreground, calm down, or the app stops.
/// All state lives on `q`; never call `q.sync` from code that `q` could be waiting on.
final class Engine {
    private var cfg: Config
    private var extraProtected: [String] = []
    private let log: ActionLog
    private let q = DispatchQueue(label: "bgopt.engine")
    private var timer: DispatchSourceTimer?
    private var prev: [Int32: (start: UInt64, cpu: UInt64)] = [:]
    private var prevAt: UInt64 = 0
    private var busy: [Int32: Int] = [:]
    private var calm: [Int32: Int] = [:]
    private var slowed: [Int32: Slowed] = [:]
    private var ignored: [Int32: UInt64] = [:]  // pid -> start time of jobs you restored; not slowed again until they calm down or exit
    private var announced: Set<Int32> = []      // left-alone processes already logged once
    private let stateURL: URL
    private var wantActivity = false
    private var classifyCache: [String: (verdict: Verdict, reason: String)] = [:]   // decision per program; cleared when your list changes
    private var lastSnap: [Int32: ProcSample]?       // the latest sample, so the table can refresh right after an action
    private var lastPct: [Int32: Double] = [:]

    /// Called on the main queue after each sample while the Activity window is open: busiest jobs, and how many of your jobs exist.
    var onActivity: (([ActivityRow], Int) -> Void)?

    /// Called on the main queue with a short message after something you asked for (text, isError).
    var onNotice: ((String, Bool) -> Void)?

    /// Called on the main queue whenever the set of slowed processes changes.
    var onChange: (([Slowed]) -> Void)?

    init(_ cfg: Config, _ log: ActionLog) {
        self.cfg = cfg
        self.log = log
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BGOptimizer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        stateURL = dir.appendingPathComponent("slowed.json")
    }

    // MARK: control

    /// Apply new settings while running. Takes effect from the next sample.
    func update(_ cfg: Config, protectedApps: [String]) {
        q.async {
            self.cfg = cfg
            self.extraProtected = protectedApps.map { $0.lowercased() }
            self.classifyCache.removeAll()
            // Anything slowed that your list now protects goes back to normal.
            var changed = false
            for (pid, info) in self.slowed {
                let path = ProcTable.path(pid)
                guard !path.isEmpty, Policy.classify(path: path, extra: self.extraProtected).verdict == .never else { continue }
                if ProcTable.sample(pid, wantCPU: false)?.start == info.start { ProcTable.setBackground(pid, false) }
                self.slowed[pid] = nil; self.calm[pid] = nil; self.busy[pid] = nil
                self.log.write("NORMAL", "\(info.name) (pid \(pid)) is now on your protected list")
                changed = true
            }
            if changed { self.persistAndPublish() }
            self.republishActivity()
        }
    }

    /// Whether Activity rows are being built (used by the self-test).
    var activityEnabled: Bool { q.sync { wantActivity } }

    /// Turn Activity rows on while the window is open (they are built only then).
    func setActivity(_ on: Bool) {
        q.async { self.wantActivity = on }
    }

    func start() {
        q.async {
            guard self.timer == nil else { return }
            let chip = ProcTable.chipName()
            self.log.write("START", "\(chip), threshold \(Int(self.cfg.threshold))% for \(self.cfg.sustain)x\(Int(self.cfg.interval))s\(self.cfg.dryRun ? ", DRY-RUN" : "")")
            let t = DispatchSource.makeTimerSource(queue: self.q)
            t.schedule(deadline: .now() + self.cfg.interval, repeating: self.cfg.interval, leeway: .seconds(1))
            t.setEventHandler { self.tick() }
            t.resume()
            self.timer = t
        }
    }

    /// Turn off and give everything back.
    func stop() {
        q.async { self.halt("turned off") }
    }

    /// Blocking version for app quit / signals.
    func shutdownSync() {
        q.sync { self.halt("app quitting") }
        log.flush()
    }

    func releaseAll() {
        q.async {
            for (pid, info) in self.slowed { self.ignored[pid] = info.start }
            self.releaseAllLocked("released by you")
        }
    }

    /// Give one job back. It is not slowed again until it calms down or exits.
    func release(_ pid: Int32) {
        q.async {
            guard let info = self.slowed[pid] else { return }
            if ProcTable.sample(pid, wantCPU: false)?.start == info.start { ProcTable.setBackground(pid, false) }
            self.slowed[pid] = nil; self.calm[pid] = nil; self.busy[pid] = nil
            self.ignored[pid] = info.start
            self.log.write("NORMAL", "\(info.name) (pid \(pid)) restored by you")
            self.persistAndPublish()
            self.notify(tr("Restored: %@", info.name), error: false)
            self.republishActivity()
        }
    }

    /// Slow one job down because you asked. The engine decides again, whatever the window showed:
    /// system, security, local AI, protected and in-front jobs are refused; interactive or media jobs
    /// and anything keeping the Mac awake need `confirmedInteractive`; the pid must still be the same process.
    func slowManually(pid: Int32, start: UInt64, confirmedInteractive: Bool) {
        q.async {
            func refuse(_ name: String, _ why: String, _ logWhy: String) {
                self.log.write("REFUSED", "slow \(name) (pid \(pid)): \(logWhy)")
                self.notify(tr("Could not slow %@: %@", name, why), error: true)
            }
            guard self.timer != nil else { refuse("pid \(pid)", tr("Switch the app on to change jobs"), "app is off"); return }
            guard !self.cfg.dryRun else { refuse("pid \(pid)", tr("Turn off Observe only to change jobs"), "observe-only mode"); return }
            let snap = ProcTable.snapshot()
            guard let s = snap[pid], s.start == start, s.uid == getuid(), pid != getpid() else {
                refuse("pid \(pid)", tr("That job is no longer running."), "process changed or gone"); return
            }
            guard self.slowed[pid] == nil else { return }
            let path = ProcTable.path(pid)
            let name = path.isEmpty ? "pid \(pid)" : (path as NSString).lastPathComponent
            let (verdict, reason) = self.classify(path)
            if verdict == .never { refuse(name, tr(reason), "protected (\(reason))"); return }
            if self.frontChecker(snap)(pid) { refuse(name, tr("You are using it"), "in front"); return }
            if s.isBackground { refuse(name, tr("Already in background mode"), "already in background mode"); return }
            let held = Self.sleepAssertionHolders().contains(pid)
            if (verdict == .leaveAlone || held) && !confirmedInteractive {
                refuse(name, tr("Needs your confirmation first."), "needs confirmation"); return
            }
            guard ProcTable.setBackground(pid, true) else { refuse(name, tr("macOS did not allow it."), "macOS refused"); return }
            self.slowed[pid] = Slowed(pid: pid, start: start, name: name, since: Date(), cpu: nil, manual: true)
            self.ignored[pid] = nil; self.busy[pid] = nil; self.calm[pid] = nil
            self.log.write("SLOWED", "\(name) (pid \(pid)) slowed by you")
            self.persistAndPublish()
            self.notify(tr("Slowed down: %@", name), error: false)
            self.republishActivity()
        }
    }

    private func notify(_ text: String, error: Bool) {
        DispatchQueue.main.async { self.onNotice?(text, error) }
    }

    /// Rebuild the table from the latest sample (after an action or a settings change).
    private func republishActivity() {
        guard wantActivity, let snap = lastSnap else { return }
        publishActivity(snap, lastPct, frontChecker(snap), Self.sleepAssertionHolders())
    }

    /// After a crash, anything we slowed is still in background mode. Release the ones that are still the same process.
    func recoverFromCrash() {
        q.sync {
            guard let data = try? Data(contentsOf: stateURL),
                  let list = try? JSONDecoder().decode([Slowed].self, from: data) else { return }
            var n = 0
            for s in list {
                if let cur = ProcTable.sample(s.pid, wantCPU: false), cur.start == s.start, cur.isBackground,
                   ProcTable.setBackground(s.pid, false) { n += 1 }
            }
            try? FileManager.default.removeItem(at: stateURL)
            if n > 0 { log.write("RECOVER", "released \(n) process(es) left slowed by a previous run") }
        }
    }

    private func halt(_ why: String) {
        timer?.cancel()
        timer = nil
        releaseAllLocked(why)
        prev = [:]; prevAt = 0; busy = [:]; calm = [:]
        log.write("STOP", why)
    }

    // MARK: sampling

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let snap = ProcTable.snapshot()

        var pct: [Int32: Double] = [:]
        if prevAt != 0 {
            let dt = Double(now - prevAt)
            for (pid, s) in snap {
                if let c = s.cpuNs, let p = prev[pid], p.start == s.start, c >= p.cpu {
                    pct[pid] = Double(c - p.cpu) / dt * 100
                }
            }
        }
        prev = snap.reduce(into: [:]) { if let c = $1.value.cpuNs { $0[$1.key] = ($1.value.start, c) } }
        prevAt = now
        guard !pct.isEmpty else { return }       // first tick only primes the counters

        lastSnap = snap; lastPct = pct
        let inFront = frontChecker(snap)

        let held = Self.sleepAssertionHolders()
        var changed = releasePass(snap, pct, inFront)
        changed = slowPass(snap, pct, inFront, held) || changed
        if changed { persistAndPublish() }
        if wantActivity { publishActivity(snap, pct, inFront, held) }
    }

    /// The decision for a program. The same program is asked about every 5 seconds, so remember the answer.
    private func classify(_ path: String) -> (verdict: Verdict, reason: String) {
        if let hit = classifyCache[path] { return hit }
        let result = Policy.classify(path: path, extra: extraProtected)
        if classifyCache.count > 5000 { classifyCache.removeAll() }
        classifyCache[path] = result
        return result
    }

    /// "Is this process the app you are using, or inside it?" for the given sample.
    private func frontChecker(_ snap: [Int32: ProcSample]) -> (Int32) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        let frontPid = front?.processIdentifier ?? -1
        let frontBundle = front?.bundleURL?.path ?? ""
        var kids: [Int32: [Int32]] = [:]
        for (pid, s) in snap { kids[s.ppid, default: []].append(pid) }
        var frontTree: Set<Int32> = [frontPid]
        var stack = [frontPid]
        while let p = stack.popLast() { for k in kids[p] ?? [] where frontTree.insert(k).inserted { stack.append(k) } }
        return { pid in
            frontTree.contains(pid) || (!frontBundle.isEmpty && ProcTable.path(pid).hasPrefix(frontBundle + "/"))
        }
    }

    /// All of your own jobs, busiest first, each with what this app is doing, why, and what you may change.
    private func publishActivity(_ snap: [Int32: ProcSample], _ pct: [Int32: Double], _ inFront: (Int32) -> Bool, _ held: Set<Int32>) {
        let me = getuid(), mine = getpid()
        let own = snap.filter { $0.value.uid == me && $0.key != mine }
        let changeBlocked: String? = cfg.dryRun ? tr("Turn off Observe only to change jobs") : nil

        var rows: [ActivityRow] = []
        for (pid, s) in own {
            let p = pct[pid] ?? 0
            let path = ProcTable.path(pid)
            let name = path.isEmpty ? tr("pid %d", Int(pid)) : (path as NSString).lastPathComponent
            let (verdict, reason) = classify(path)
            let userEntry = extraProtected.isEmpty ? nil : Policy.matchedUserEntry(path: path, extra: extraProtected)
            let front = inFront(pid)
            let awake = held.contains(pid)

            let status: JobStatus, detail: String
            if let info = slowed[pid] {
                status = .slowed
                detail = info.since.map { tr("Slowed %@", ago($0)) } ?? tr("Low priority")
            } else if front {
                (status, detail) = (.leftAlone, tr("In front, never slowed"))
            } else if verdict == .never {
                (status, detail) = (.protected_, tr(reason))
            } else if verdict == .leaveAlone {
                (status, detail) = (.leftAlone, tr("Never slowed: %@", tr(reason)))
            } else if awake {
                (status, detail) = (.leftAlone, tr("Keeping the Mac awake (playback, call or download)"))
            } else if s.isBackground {
                (status, detail) = (.leftAlone, tr("Already in background mode"))
            } else if p >= cfg.threshold {
                let b = busy[pid] ?? 0
                if ignored[pid] == s.start { (status, detail) = (.normal, tr("You restored it")) }
                else if cfg.dryRun && b >= cfg.sustain { (status, detail) = (.wouldSlow, tr("Would be slowed")) }
                else { (status, detail) = (.watching, tr("Busy for %d of %d seconds", b * Int(cfg.interval), cfg.sustain * Int(cfg.interval))) }
            } else {
                (status, detail) = (.normal, tr("Below the busy threshold"))
            }

            // What you may change. The engine re-checks all of this when you act.
            var access = ManualAccess.ok
            var lock: String?
            var confirm: String?
            if slowed[pid] != nil { access = .locked }
            else if let blocked = changeBlocked { (access, lock) = (.locked, blocked) }
            else if front { (access, lock) = (.locked, tr("You are using it")) }
            else if verdict == .never { (access, lock) = (.locked, tr(reason)) }
            else if s.isBackground { (access, lock) = (.locked, tr("Already in background mode")) }
            else if verdict == .leaveAlone {
                access = .confirm
                confirm = tr("Slowing a browser, call, media app or editor can make it lag, stutter or drop out of a call. You can restore it at any time.")
            } else if awake {
                access = .confirm
                confirm = tr("It is keeping the Mac awake (playback, a call or a download). Slowing it can interrupt that. You can restore it at any time.")
            }
            rows.append(ActivityRow(pid: pid, start: s.start, name: name, protectName: Policy.appName(path: path), userEntry: userEntry,
                                    cpu: p, status: status, detail: detail, access: access, confirmText: confirm, lockReason: lock,
                                    canRestore: slowed[pid] != nil, canProtect: userEntry == nil && verdict != .never && !path.isEmpty,
                                    memBytes: ProcTable.memoryFootprint(pid) ?? 0))
        }
        rows.sort { $0.cpu > $1.cpu }
        let total = own.count
        DispatchQueue.main.async { self.onActivity?(rows, total) }
    }

    /// Give back processes that are in use again, calm, or gone.
    private func releasePass(_ snap: [Int32: ProcSample], _ pct: [Int32: Double], _ inFront: (Int32) -> Bool) -> Bool {
        var changed = false
        for (pid, info) in slowed {
            var why: String?
            if snap[pid]?.start != info.start {
                slowed[pid] = nil; calm[pid] = nil; changed = true
                log.write("GONE", "\(info.name) (pid \(pid)) exited")
                continue
            }
            calm[pid] = (pct[pid] ?? 0) < cfg.threshold * cfg.calmFactor ? (calm[pid] ?? 0) + 1 : 0
            if inFront(pid) { why = "now in the foreground" }
            else if info.manual != true, (calm[pid] ?? 0) >= cfg.sustain { why = "calmed down" }
            if let why = why {
                ProcTable.setBackground(pid, false)
                slowed[pid] = nil; calm[pid] = nil; busy[pid] = nil; changed = true
                log.write("NORMAL", "\(info.name) (pid \(pid)) \(why)")
            }
        }
        return changed
    }

    /// Find sustained hogs among our own user's background processes and slow them.
    private func slowPass(_ snap: [Int32: ProcSample], _ pct: [Int32: Double], _ inFront: (Int32) -> Bool, _ held: Set<Int32>) -> Bool {
        var changed = false
        let me = getuid(), mine = getpid()
        var hot: Set<Int32> = []
        for (pid, s) in snap where s.uid == me && pid != mine && slowed[pid] == nil {
            guard let p = pct[pid], p >= cfg.threshold, !s.isBackground, !inFront(pid) else { ignored[pid] = nil; continue }
            if ignored[pid] == s.start { continue }
            hot.insert(pid)
            busy[pid, default: 0] += 1
            guard busy[pid]! >= cfg.sustain else { continue }

            let path = ProcTable.path(pid)
            let name = (path as NSString).lastPathComponent
            let tag = "\(name) (pid \(pid)) \(Int(p))%"
            switch classify(path).verdict {
            case .never: continue
            case .leaveAlone:
                if announced.insert(pid).inserted { log.write("SKIP", "\(tag) busy, but it is an interactive/media app") }
            case .ok:
                if held.contains(pid) {
                    if announced.insert(pid).inserted { log.write("SKIP", "\(tag) busy, but it is keeping the Mac awake (playback/call/download)") }
                } else if cfg.dryRun {
                    if announced.insert(pid).inserted { log.write("WOULD", "slow \(tag)") }
                } else if ProcTable.sample(pid, wantCPU: false)?.start == s.start, ProcTable.setBackground(pid, true) {
                    slowed[pid] = Slowed(pid: pid, start: s.start, name: name, since: Date(), cpu: Int(p))
                    changed = true
                    log.write("SLOWED", "\(tag) busy for \(busy[pid]! * Int(cfg.interval))s")
                } else {
                    log.write("FAILED", "could not slow \(tag)")
                }
            }
        }
        busy = busy.filter { hot.contains($0.key) }
        announced = announced.filter { snap[$0] != nil }
        ignored = ignored.filter { snap[$0.key]?.start == $0.value }
        return changed
    }

    private func releaseAllLocked(_ why: String) {
        guard !slowed.isEmpty else { return }
        for (pid, info) in slowed {
            if ProcTable.sample(pid, wantCPU: false)?.start == info.start { ProcTable.setBackground(pid, false) }
            log.write("NORMAL", "\(info.name) (pid \(pid)) \(why)")
        }
        slowed = [:]; calm = [:]; busy = [:]
        persistAndPublish()
    }

    private func persistAndPublish() {
        let list = Array(slowed.values)
        if list.isEmpty { try? FileManager.default.removeItem(at: stateURL) }
        else if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: stateURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
        DispatchQueue.main.async { self.onChange?(list) }
    }

    /// Processes holding a "keep the Mac awake" assertion: media playback, calls, downloads, caffeinate.
    private static func sleepAssertionHolders() -> Set<Int32> {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess, let dict = raw?.takeRetainedValue() as NSDictionary? else { return [] }
        let types: Set<String> = ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "PreventSystemSleep",
                                  "NoIdleSleepAssertion", "NoDisplaySleepAssertion"]
        var out: Set<Int32> = []
        for (k, v) in dict {
            guard let pid = (k as? NSNumber)?.int32Value, let list = v as? [[String: Any]] else { continue }
            if list.contains(where: { types.contains(($0["AssertType"] as? String) ?? "") }) { out.insert(pid) }
        }
        return out
    }
}

extension ProcTable {
    static func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
