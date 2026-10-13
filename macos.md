# macOS inspection commands (read-only)

Everything here only reads, except the "Changes" section at the end. Run on macOS 27 / Apple silicon (M1): `top`, `ps`, `pmset -g therm`, `memory_pressure`, `launchctl print gui/$(id -u)`, `sfltool dumpbtm`, `csrutil`, `spctl --status`, `fdesetup`, `socketfilterfw` all worked without sudo. The rest follow standard usage but were not run here.

- Identity: `sw_vers; uname -m; id` (`uname -m` prints `arm64` on Apple silicon)
- Hardware: `sysctl -n machdep.cpu.brand_string; sysctl -n hw.memsize hw.ncpu; system_profiler SPHardwareDataType`
- Processes, current load: `top -l 2 -s 1 -o cpu -n 15 -stats pid,command,cpu | tail -17`. Use the second sample: `top -l 1` reports averages since each process started and shows near 0% for everything.
- Processes, lifetime view: `ps -Ao pid,pri,state,%cpu,comm -r | head -25` (`%cpu` here is an average over the process's life, not current load)
- Process priority: `ps -o pid,pri,state,comm -p <pid>` (a normal process shows `pri` 31; one in background mode shows a much lower value, for example 4)
- Memory, thermal, battery: `memory_pressure | tail -3; vm_stat | head -8; pmset -g therm; pmset -g batt` ("No thermal warning level has been recorded" means macOS has not throttled the chip)
- Disk: `df -h /; diskutil info / | grep -E "Volume Free|Container Total"`
- Services: `launchctl list | awk '$2 != 0'` (column 2 is the last exit status; non-zero or negative means failed or killed by a signal); user domain: `launchctl print gui/$(id -u) | head -40`; system domain: `launchctl print system | head`
- Persistence: `ls /Library/LaunchAgents /Library/LaunchDaemons ~/Library/LaunchAgents`; login and background items: `sfltool dumpbtm` (may ask for sudo on other macOS versions)
- Logs: `log show --last 1h --style compact --predicate 'messageType == error' | tail -200` (a 24 h window can take minutes and produce huge output); crashes: `ls ~/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports`
- Ports: `lsof -iTCP -sTCP:LISTEN -n -P`
- Security: `csrutil status; spctl --status; fdesetup status; /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`
- Signatures: `codesign -dv --verbose=2 <app>`; `codesign --verify --deep --strict <app>`; `spctl -a -vv <app>`
- Updates: `softwareupdate -l` (needs network, can take a minute)
- Apps: `ls /Applications ~/Applications`; `system_profiler SPApplicationsDataType | head -200` (slow); `brew outdated`
- Runtimes: `python3 --version; node -v; java -version; ruby -v; which -a python3`

## Changes (not read-only: ask first, and note what you changed)

- Put a process in background mode (low priority, efficiency cores): `taskpolicy -b -p <pid>`
- Put it back to normal: `taskpolicy -B -p <pid>`. `renice` does not undo background mode.
- Only your own user's processes can be changed without sudo. Never do this to system, audio, security or foreground apps.
