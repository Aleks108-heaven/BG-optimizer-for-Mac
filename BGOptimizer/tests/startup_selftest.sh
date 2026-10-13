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
trap 'kill "$PID" 2>/dev/null; defaults delete "$ID" 2>/dev/null; rm -rf "$W"' EXIT
ditto --noextattr "$APP" "$W/T.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$W/T.app/Contents/Info.plist"
codesign --force --sign - "$W/T.app" 2>/dev/null
HEX=$(python3 -c "print(b'{\"threshold\":50,\"sustainSeconds\":60,\"protectedApps\":[],\"observeOnly\":true,\"language\":\"en\"}'.hex())")
defaults write "$ID" settings -data "$HEX"; defaults write "$ID" enabled -bool true; defaults write "$ID" didOnboard -bool true
BGOPT_LOG_DIR="$W/log" "$W/T.app/Contents/MacOS/BGOptimizer" --selftest-window >"$W/out.txt" 2>&1 &
PID=$!
for _ in $(seq 1 40); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$PID" 2>/dev/null; then echo "FAIL: the app did not finish the test in 40 s"; exit 1; fi
LOG="$W/log/actions.log"; FAIL=0
expect() { if grep -E "SELFTEST $1" "$LOG" | grep -qE "$2"; then echo "  pass $3"; else echo "  FAIL $3"; grep "SELFTEST $1" "$LOG" | cut -c1-200; FAIL=1; fi; }
expect "start" "accessory" "starts as a menu-bar-only app"
expect "Startup tab loaded" "regular.*refreshTimer=true, engineBuildsRows=true" "window open: Dock icon, refreshing, rows being built"
expect "window minimized" "regular.*minimized=true.*refreshTimer=false, engineBuildsRows=false" "minimized: keeps its Dock icon, stops all work"
expect "window restored" "regular.*minimized=false.*refreshTimer=true, engineBuildsRows=true" "restored: work resumes"
expect "window closed" "accessory.*refreshTimer=false, engineBuildsRows=false" "closed: back to menu-bar-only"
grep -E "SELFTEST Startup tab loaded" "$LOG" | grep -oE "startupItems=[0-9]+" | sed 's/^/  info /'
[ $FAIL -eq 0 ] && echo "START-UP TEST: ALL PASSED" || { echo "START-UP TEST: FAILED"; exit 1; }
