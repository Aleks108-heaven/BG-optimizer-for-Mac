# BG Optimizer: security and performance review

Date: 2026-10-13. Reviewer: the assistant that wrote the app (so this is a self-review, not independent). Machine: M1 MacBook, macOS 27.
Method: the project's own `security-checklist.md` (items 1 to 12) applied to a local app, reading the source, inspecting the built app with `codesign`, `otool`, `lsof`, and measuring CPU with `ps` and `sample`.
Automated checks you can rerun: `./BGOptimizer/tests/run.sh` (translations, log, row menu, startup items, changing jobs by hand).

## What the app can and cannot do (the attack surface)

| Question | Answer | Evidence |
|---|---|---|
| Does it listen on or use the network? | No | `lsof -i` for the running app: 0 connections. No network framework is linked (`otool -L`). No update channel. |
| Does it accept input from other programs? | No | Info.plist declares no URL scheme, no Apple events, no helper tool, no XPC service. The only input is the user's clicks. |
| Does it run as administrator, or ask for a password? | No | Runs as the logged-in user. No entitlements, no privileged helper. It never calls `sudo`. |
| What can it change on other programs? | Only processes owned by the same user: put them in background mode (reversible), and switch your own LaunchAgents on or off for the next login (reversible) | `setpriority` on same-user processes; `launchctl disable|enable gui/<uid>/<label>` |
| What can it never touch? | System processes, security tools, local AI hosts, this app, the app in front, anything on your protected list; macOS (`com.apple.`) startup items, security tools' startup items | Covered by the automated checks in `BGOptimizer/tests/` (changing jobs by hand and startup items). |
| Third-party code? | None. Only Apple frameworks. | `otool -L` |
| External programs it launches? | `system_profiler` (battery health), `launchctl`, `sfltool` (read the startup list), by full path with fixed arguments, never through a shell | `grep Process()` in Sources |

## Findings

| ID | Severity | Finding | Status |
|---|---|---|---|
| S-01 | Low | The log folder, the log file and the crash-recovery file were readable by other users of this Mac (755/644). They contain the names of the programs you run. | **Fixed**: folder 700, files 600. Tested. |
| S-02 | Low | A process name or path containing a newline or escape codes could forge extra lines in the log. | **Fixed**: control characters become spaces, one entry is one line. Tested. |
| S-03 | Low | The environment variable `BGOPT_LOG_DIR` redirects where the log is written (used by the tests). | **Accepted.** Whoever can set a program's environment can already run code as you. It only changes the log location. |
| S-04 | Medium (for sharing) | The app is ad-hoc signed: no Developer ID, not notarized, no hardened runtime. On another Mac, Gatekeeper warns. | **Open.** Needs a paid Apple Developer account. Required for a warning-free download by other people; it makes no difference when the app is built on the Mac that runs it. |
| S-05 | Info | The app is not sandboxed. | **By design.** Reading other processes and setting their priority is not possible from the sandbox. |
| S-06 | Low | After checking a process, there is a tiny window before changing it in which the PID could be reused by another process. | **Mitigated**: the process identity (PID plus start time) is checked again immediately before the change. Worst case: another process of yours is put in reversible background mode. |
| S-07 | Low | Startup control: a crafted label, a file outside your LaunchAgents folder, a symbolic link, or a mismatched file could redirect a change. | **Controls in place and tested**: plain-text label only, folder check after resolving symbolic links, the file must name that exact label, macOS items, security tools and this app refused, the result is read back from launchd. |
| S-08 | Low | The text of `sfltool` and `system_profiler` is parsed. Their format is not documented and can change. | **Accepted.** Parsing is defensive: if it fails, fewer rows are shown, nothing is changed. Changes never depend on this text, they rely on `launchctl`. |
| S-09 | Medium (usability/safety) | The app was menu-bar-only with no menu bar of its own, so copy and paste did not work in its text fields and a minimized window had no app icon. | **Fixed**: a normal Dock icon and menus while a window is open (Edit, Window, View menus). Verified with the built-in window self-test. |
| S-10 | Medium (performance) | The Activity window kept refreshing while minimized or covered. | **Fixed**: refresh and row-building stop when the window is minimized, covered or closed. Verified. |

Not covered: fuzzing of the parsers, a review by someone other than the author, hostile local users beyond file permissions, and the behaviour of macOS itself.

## Performance (the app's own cost, M1, 489 of the user's processes)

Measured as the process's cumulative CPU time over 20 seconds (`ps`), Observe-only mode, 12 seconds after start. 100% would be one full core. Resolution is 0.01 s, so values near 0.1% are "very small", not exact.

| State | Before the speed-up | After |
|---|---|---|
| Menu bar only (window closed) | 0.10% | 0.10% |
| Activity window open | 5.05% | 0.10% |
| Activity window minimized | 0.05% to 0.40% | 0.10% |
| Memory | | about 77 MB closed, about 101 MB with the window |

What changed: the decision for each program (is it protected? a browser?) is now remembered instead of recomputed for all processes every 5 seconds, and the disk size is read every 30 s instead of every 5 s. A profile before and after confirmed the work is still done (row building 92 ms to 21 ms, classification 71 ms to 14 ms in a 12 s sample), so the saving is real and not a stalled window. A first measurement of the minimized window with `top` read 5.3%; direct CPU-time measurement showed that was a measurement artifact.
