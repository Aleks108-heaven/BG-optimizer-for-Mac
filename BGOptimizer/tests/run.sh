#!/bin/bash
# Runs every automated check. Needs only the Xcode command-line tools. Takes about a minute.
# It starts harmless sleeper processes and uses a system process of the current user (Finder, Dock) only to confirm it
# is refused. It never touches the real log.
#
# Every section has a time limit, so a stuck test fails with a message instead of hanging. On GitHub Actions each
# section's result is also copied into an "annotation", which can be read on the run page without opening the raw log.
set -uo pipefail
cd "$(dirname "$0")/.."
W="$(mktemp -d)"
trap 'pkill -f "$W/" 2>/dev/null; rm -rf "$W"' EXIT
FAIL=0

# --- helpers -----------------------------------------------------------------------------------------------------
annotate() { # level title file   (only on GitHub Actions)
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  local msg
  msg="$(tail -n 80 "$3" | tail -c 3500 | python3 -c 'import sys; print(sys.stdin.read().replace("%","%25").replace("\r","%0D").replace("\n","%0A"))')"
  echo "::$1 title=$2::$msg"
}

section() { # title seconds function...   runs the function with a time limit and records pass or fail
  local title="$1" secs="$2"; shift 2
  local out="$W/section.$RANDOM.txt"
  echo; echo "== $title"
  ( "$@" ) >"$out" 2>&1 &
  local pid=$!
  ( sleep "$secs"; pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; sleep 2; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid"; local rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  cat "$out"
  if [ $rc -eq 0 ]; then
    annotate notice "$title: passed" "$out"
  else
    FAIL=1
    [ $rc -ge 128 ] && echo "  STOPPED: no result within ${secs} s (exit $rc)"
    annotate error "$title: FAILED (exit $rc)" "$out"
  fi
}

# The tests run inside a tiny app bundle so Bundle.main finds the language files.
mkbundle() { mkdir -p "$W/$1.app/Contents/MacOS" "$W/$1.app/Contents/Resources"; cp -R Resources/en.lproj Resources/uk.lproj "$W/$1.app/Contents/Resources/"
  cp Info.plist "$W/$1.app/Contents/Info.plist"; /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable t" -c "Set :CFBundleIdentifier com.example.bgopt.$1" "$W/$1.app/Contents/Info.plist"; }
build() { # name, test file, sources...   (Swift only allows top-level code in a file called main.swift)
  local n="$1" t="$2"; shift 2; mkbundle "$n"; mkdir -p "$W/$n.src"; cp "$t" "$W/$n.src/main.swift"
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" "$@" "$W/$n.src/main.swift" -o "$W/$n.app/Contents/MacOS/t" 2>&1 | grep error
  return "${PIPESTATUS[0]}"; }
CORE=(Sources/Engine.swift Sources/ActionLog.swift Sources/ProcTable.swift Sources/Policy.swift Sources/L10n.swift Sources/Format.swift)

# --- the sections ------------------------------------------------------------------------------------------------
machine() { # what kind of machine is this? (decides which tests can run)
  echo "macOS $(sw_vers -productVersion) ($(uname -m)), user $(id -un) uid $(id -u)"
  echo "window server running: $(pgrep -x WindowServer >/dev/null && echo yes || echo no)"
  echo "Finder running: $(pgrep -x Finder >/dev/null && echo yes || echo no), Dock running: $(pgrep -x Dock >/dev/null && echo yes || echo no)"
  echo "per-user launchd domain: $(launchctl print-disabled "gui/$(id -u)" 2>&1 | head -1 | cut -c1-80)"
  local t0=$SECONDS; perl -e 'alarm 15; exec @ARGV' /usr/bin/sfltool dumpbtm </dev/null 2>&1 | head -2 | cut -c1-100
  echo "sfltool dumpbtm took $((SECONDS - t0)) s (stopped at 15 s)"
  echo "swift: $(swift --version 2>&1 | head -1)"
}
translations() { python3 tools/check_strings.py; }
log_test() { build log tests/log_test.swift "${CORE[@]}" && BGOPT_LOG_DIR="$W/logdir" "$W/log.app/Contents/MacOS/t"; }
menu_test() { build menu tests/row_menu_test.swift "${CORE[@]}" Sources/RowMenu.swift && "$W/menu.app/Contents/MacOS/t"; }
startup_test() { build startup tests/startup_test.swift "${CORE[@]}" Sources/StartupItems.swift Sources/ToolRunner.swift && "$W/startup.app/Contents/MacOS/t"; }
storage_test() { build storage tests/storage_test.swift "${CORE[@]}" Sources/Storage.swift && "$W/storage.app/Contents/MacOS/t"; }
policy_test() { build policy tests/policy_test.swift "${CORE[@]}" && "$W/policy.app/Contents/MacOS/t"; }
driver_test() { build driver tests/driver_test.swift "${CORE[@]}" Sources/Storage.swift Sources/ToolRunner.swift Sources/DriverItems.swift && "$W/driver.app/Contents/MacOS/t"; }
manual_test() {
  swiftc -O tests/sleeper.swift -o "$W/bgsleeper" 2>&1 | grep error
  mkdir -p "$W/fake/Google Chrome.app/Contents/MacOS"; cp "$W/bgsleeper" "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper"
  codesign --force --sign - "$W/bgsleeper" "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper" 2>/dev/null
  ( "$W/bgsleeper" </dev/null >/dev/null 2>&1 & ); ( "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper" </dev/null >/dev/null 2>&1 & ); sleep 1   # detached: not "in front"
  local SL CH FI=0 name p
  SL=$(pgrep -f "$W/bgsleeper" | head -1); CH=$(pgrep -f "Google Chrome.app/Contents/MacOS/bgsleeper" | head -1)
  for name in Finder Dock SystemUIServer; do p=$(pgrep -x -u "$(id -u)" "$name" | head -1); if [ -n "$p" ]; then FI=$p; break; fi; done   # a system process of the user, to confirm it is refused
  if [ -z "$SL" ] || [ -z "$CH" ]; then echo "  could not start the test processes (sleeper=$SL fake-browser=$CH)"; return 1; fi
  build manual tests/manual_control_test.swift "${CORE[@]}" && BGOPT_LOG_DIR="$W/logdir2" "$W/manual.app/Contents/MacOS/t" "$SL" "$CH" "$FI"
}
app_test() { ./tests/startup_selftest.sh "build/BG Optimizer.app"; }

[ -n "${GITHUB_ACTIONS:-}" ] && section "machine report (information only)" 60 machine
section "translations" 60 translations
section "log: permissions, one line per entry, clear" 300 log_test
section "row menu: contents for every kind of row, both languages" 300 menu_test
section "startup items: parsing, rules for changing, real read" 300 startup_test
section "storage: what is offered, what is never offered, the rules for Move to Trash" 300 storage_test
section "policy: a security tool's name must start a word (no false 'Security tool')" 300 policy_test
section "drivers: reading, the decision for every kind of row, a real read" 300 driver_test
section "changing jobs by hand: rules enforced by the engine" 360 manual_test
[ -d "build/BG Optimizer.app" ] && section "finished app: start-up test (windows, Dock icon, minimize)" 120 app_test

echo; [ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
