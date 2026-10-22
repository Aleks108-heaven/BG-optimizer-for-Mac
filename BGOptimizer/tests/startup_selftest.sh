#!/bin/bash
# Start-up test of a FINISHED app: opens the Activity window and the Startup tab, minimizes, restores and closes it,
# and checks what the app did at each step (Dock icon on/off, refresh stopped while minimized, ...).
# Works on a throwaway copy with another identity, in Observe only mode, with its own log folder:
# it never touches your settings, your log or any job.
#   usage: tests/startup_selftest.sh "path/to/BG Optimizer.app"
set -uo pipefail
APP="${1:?usage: startup_selftest.sh <path to BG Optimizer.app>}"
if ! pgrep -x WindowServer >/dev/null; then echo "SKIPPED: no window server on this machine, so windows cannot be opened"; exit 0; fi
W="$(mktemp -d)"; ID="com.example.bgopt.selftest.$$"
trap 'kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; defaults delete "$ID" 2>/dev/null; rm -f "$HOME/Library/Preferences/$ID.plist"; rm -rf "$W"' EXIT
ditto --noextattr "$APP" "$W/T.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$W/T.app/Contents/Info.plist"
codesign --force --sign - "$W/T.app" 2>/dev/null
HEX=$(python3 -c "print(b'{\"threshold\":50,\"sustainSeconds\":60,\"protectedApps\":[],\"observeOnly\":true,\"language\":\"en\"}'.hex())")
defaults write "$ID" settings -data "$HEX"; defaults write "$ID" enabled -bool true; defaults write "$ID" didOnboard -bool true
attempt() {
rm -rf "$W/log"
BGOPT_LOG_DIR="$W/log" "$W/T.app/Contents/MacOS/BGOptimizer" --selftest-window >"$W/out.txt" 2>&1 &
PID=$!
for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done      # the app waits for each step, so a slow machine takes longer
if kill -0 "$PID" 2>/dev/null; then echo "FAIL: the app did not finish the test in 150 s"; return 1; fi
LOG="$W/log/actions.log"; FAIL=0
expect() { if grep -E "SELFTEST $1" "$LOG" | grep -qE "$2"; then echo "  pass $3"; else echo "  FAIL $3"; grep "SELFTEST $1" "$LOG" | cut -c1-200; FAIL=1; fi; }
expect "start" "accessory" "starts as a menu-bar-only app"
expect "Startup tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true" "window open: Dock icon, refreshing, rows being built"
expect "Storage tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true" "Storage tab opens and reads the Library (read only)"
expect "Drivers tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true" "Drivers tab opens and lists the extensions (read only)"
expect "Fans tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true, .*thermalRead=true" "Fans tab opens and reads the fans and sensors (read only)"
expect "Battery tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true, .*powerRead=true" "Battery tab opens and reads the power log (read only)"
expect "window minimized" "regular.*minimized=true.*refreshTimer=false, engineBuildsRows=false" "minimized: keeps its Dock icon, stops all work"
expect "window restored" "regular.*minimized=false.*refreshTimer=true, engineBuildsRows=true" "restored: work resumes"
expect "window closed" "accessory.*refreshTimer=false, engineBuildsRows=false" "closed: back to menu-bar-only"
grep -E "SELFTEST Startup tab loaded" "$LOG" | grep -oE "startupItems=[0-9]+" | sed 's/^/  info /'
grep -E "SELFTEST Storage tab loaded" "$LOG" | grep -oE "storageItems=[0-9]+" | sed 's/^/  info /'
grep -E "SELFTEST Drivers tab loaded" "$LOG" | grep -oE "driverItems=[0-9]+" | sed 's/^/  info /'
grep -E "SELFTEST Fans tab loaded" "$LOG" | grep -oE "thermal(Sensors|Fans)=-?[0-9]+" | sed 's/^/  info /'
grep -E "SELFTEST Battery tab loaded" "$LOG" | grep -oE "power(LogRead|Sessions)=[a-z0-9-]+" | sed 's/^/  info /'
[ $FAIL -eq 0 ]

}
# The app deliberately stops work while its window is covered by other windows or on another desktop space. On a Mac that is
# being used, the test window can be hidden for a moment, so a failure gets one more try, and says so.
if attempt; then echo "START-UP TEST: ALL PASSED"
else
  echo "  (first attempt failed; trying once more: on a desktop in use the window may have been covered for a moment)"
  if attempt; then echo "START-UP TEST: PASSED ON THE SECOND ATTEMPT"; else echo "START-UP TEST: FAILED"; exit 1; fi
fi
