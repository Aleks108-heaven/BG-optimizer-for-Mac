import Darwin
import Foundation

struct ProcSample {
    let ppid: Int32
    let uid: UInt32
    let start: UInt64          // process start time (seconds); pid + start identifies a process
    let cpuNs: UInt64?         // cumulative CPU time; nil when unreadable
    let isBackground: Bool     // already in macOS background mode (set by itself or by another process)
}

/// Thin wrapper over libproc. No subprocesses, so sampling is cheap enough to run every few seconds.
enum ProcTable {
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    /// Apple Silicon reports CPU time in mach ticks (not ns), so convert.
    private static func ns(_ ticks: UInt64) -> UInt64 {
        UInt64(Double(ticks) * Double(timebase.numer) / Double(timebase.denom))
    }

    static func pids() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var buf = [Int32](repeating: 0, count: Int(count) + 128)
        let n = proc_listallpids(&buf, Int32(buf.count * MemoryLayout<Int32>.stride))
        guard n > 0 else { return [] }
        return buf.prefix(Int(n)).filter { $0 > 0 }
    }

    static func sample(_ pid: Int32, wantCPU: Bool) -> ProcSample? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        var cpu: UInt64?
        if wantCPU {
            var ti = proc_taskinfo()
            let tsize = Int32(MemoryLayout<proc_taskinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, tsize) == tsize {
                cpu = ns(ti.pti_total_user &+ ti.pti_total_system)
            }
        }
        return ProcSample(ppid: Int32(bitPattern: bsd.pbi_ppid), uid: bsd.pbi_uid, start: bsd.pbi_start_tvsec,
                          cpuNs: cpu, isBackground: bsd.pbi_flags & UInt32(PROC_FLAG_DARWINBG | PROC_FLAG_EXT_DARWINBG) != 0)
    }

    /// Everything running. CPU time is only read for our own user's processes (others are unreadable and never touched).
    static func snapshot() -> [Int32: ProcSample] {
        let me = getuid()
        var out: [Int32: ProcSample] = [:]
        for pid in pids() {
            guard let first = sample(pid, wantCPU: false) else { continue }
            out[pid] = first.uid == me ? (sample(pid, wantCPU: true) ?? first) : first
        }
        return out
    }

    /// The memory a process is responsible for, in bytes: the same "Memory" figure Activity Monitor shows (physical footprint).
    /// Read only. nil when macOS does not let us read it (other users' processes).
    static func memoryFootprint(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    static func path(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    /// macOS "background" mode: low CPU/IO priority and efficiency cores on Apple Silicon. Fully reversible.
    @discardableResult
    static func setBackground(_ pid: Int32, _ on: Bool) -> Bool {
        setpriority(PRIO_DARWIN_PROCESS, id_t(pid), on ? PRIO_DARWIN_BG : 0) == 0
    }
}
