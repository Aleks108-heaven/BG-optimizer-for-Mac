#!/usr/bin/env python3
"""bgcalm - gently lower the priority of runaway background processes on macOS.

Safe by design:
  * dry-run unless --apply is given
  * only touches processes owned by the current user
  * never touches the frontmost app, protected apps, or its own process tree
  * browsers are report-only (a busy helper may be a tab you are using)
  * lowers priority (taskpolicy -b); never kills
  * gives priority back when the app comes to the foreground, calms down, or on exit
"""
import argparse, os, signal, subprocess, sys, time
from collections import defaultdict

# Matched against the FULL executable path (top truncates names, so never use those).
PROTECTED = {
    "WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer", "kernel_task",
    "launchd", "Terminal", "iTerm", "Claude", "sshd", "coreaudiod", "bluetoothd",
    "backupd", "cloudd", "bird", "fileproviderd",
}
REPORT_ONLY = {
    "Microsoft Edge", "Google Chrome", "Safari", "Firefox", "Brave Browser", "Arc",
    "zoom.us", "Slack", "Microsoft Teams", "FaceTime",
}
ME = os.getuid()


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def frontmost_pid():
    out = run(["lsappinfo", "front"]).strip()          # e.g. ASN:0x0-0x1234:
    if not out:
        return None
    info = run(["lsappinfo", "info", "-only", "pid", out])
    digits = "".join(c for c in info.split("=")[-1] if c.isdigit())
    return int(digits) if digits else None


def descendants(root):
    rows = run(["ps", "-Ao", "pid=,ppid="]).split()
    kids = defaultdict(list)
    for p, pp in zip(rows[::2], rows[1::2]):
        kids[int(pp)].append(int(p))
    seen, stack = {root}, [root]
    while stack:
        for k in kids[stack.pop()]:
            if k not in seen:
                seen.add(k); stack.append(k)
    return seen


def full_path(pid):
    return run(["ps", "-o", "comm=", "-p", str(pid)]).strip()


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def unthrottle(pid):
    subprocess.run(["taskpolicy", "-B", "-p", str(pid)], capture_output=True)


def matches(path, names):
    parts = path.replace(".app", "").split("/")
    return any(n in parts or any(p.startswith(n) for p in parts) for n in names)


def sample(n):
    """Current CPU% per process (delta over the second top sample)."""
    out = run(["top", "-l", "2", "-n", str(n), "-o", "cpu", "-stats", "pid,uid,cpu"])
    block = out.split("PID")[-1].splitlines()[1:]       # last sample only
    procs = []
    for line in block:
        parts = line.split()
        if len(parts) == 3:
            try:
                procs.append((int(parts[0]), int(parts[1]), float(parts[2])))
            except ValueError:
                pass
    return procs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="actually lower priority (default: report only)")
    ap.add_argument("--threshold", type=float, default=50.0, help="CPU%% counted as busy (default 50)")
    ap.add_argument("--sustain", type=int, default=5, help="consecutive busy samples before acting (default 5)")
    ap.add_argument("--interval", type=int, default=30, help="seconds between samples (default 30)")
    ap.add_argument("--once", type=int, metavar="N", help="stop after N samples")
    a = ap.parse_args()

    mine = descendants(os.getpid())
    busy, calm, throttled = defaultdict(int), defaultdict(int), {}   # throttled: pid -> name

    def restore(*_):
        for pid in list(throttled):
            unthrottle(pid)
        if throttled:
            print(f"restored {len(throttled)} process(es)")
        sys.exit(0)
    signal.signal(signal.SIGINT, restore); signal.signal(signal.SIGTERM, restore)

    mode = "APPLY" if a.apply else "DRY-RUN"
    chip = run(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
    print(f"bgcalm [{mode}] on {chip}: threshold={a.threshold}% sustain={a.sustain}x{a.interval}s  (Ctrl+C to stop)")
    n = 0
    while True:
        front = frontmost_pid()
        front_tree = descendants(front) if front else set()
        protected_pids = front_tree | mine
        sampled = sample(15)
        cpu_of = {pid: cpu for pid, _, cpu in sampled}
        for pid, name in list(throttled.items()):          # back to normal when in use again
            calm[pid] = calm[pid] + 1 if cpu_of.get(pid, 0) < a.threshold / 4 else 0
            if not alive(pid):
                reason = None
            elif pid in front_tree:
                reason = "now in foreground"
            elif calm[pid] >= a.sustain:
                reason = "calmed down"
            else:
                continue
            if reason:
                unthrottle(pid)
                print(f"NORMAL  {name} (pid {pid}) {reason}")
            del throttled[pid]; calm.pop(pid, None)
        now = {}
        for pid, uid, cpu in sampled:
            if cpu < a.threshold or uid != ME or pid in protected_pids:
                continue
            path = full_path(pid)
            if not path or matches(path, PROTECTED):
                continue
            now[pid] = (cpu, os.path.basename(path), path)
        for pid in list(busy):
            if pid not in now:
                del busy[pid]
        for pid, (cpu, name, path) in now.items():
            busy[pid] += 1
            tag = f"{name} (pid {pid}) {cpu:.0f}% busy {busy[pid]}/{a.sustain}"
            if busy[pid] < a.sustain or pid in throttled:
                print("watch  ", tag)
            elif matches(path, REPORT_ONLY):
                print("REPORT ", tag, "- browser/call app, left alone")
            elif a.apply:
                r = subprocess.run(["taskpolicy", "-b", "-p", str(pid)], capture_output=True, text=True)
                if r.returncode == 0:
                    throttled[pid] = name
                    print("LOWERED", tag)
                else:
                    print("failed ", tag, r.stderr.strip())
            else:
                print("WOULD LOWER", tag)
        n += 1
        if a.once and n >= a.once:
            restore()
        time.sleep(a.interval)


if __name__ == "__main__":
    main()
