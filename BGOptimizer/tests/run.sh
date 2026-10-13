#!/bin/bash
# Runs every automated check. Needs only the Xcode command-line tools. Takes about a minute.
# It starts harmless sleeper processes and uses your real Finder only to confirm it is refused. It never touches your real log.
set -uo pipefail
cd "$(dirname "$0")/.."
W="$(mktemp -d)"; trap 'pkill -f "$W/" 2>/dev/null; rm -rf "$W"' EXIT
FAIL=0
step() { echo; echo "== $1"; }

step "translations"; python3 tools/check_strings.py || FAIL=1

# The tests run inside a tiny app bundle so Bundle.main finds the language files.
mkbundle() { mkdir -p "$W/$1.app/Contents/MacOS" "$W/$1.app/Contents/Resources"; cp -R Resources/en.lproj Resources/uk.lproj "$W/$1.app/Contents/Resources/"
  cp Info.plist "$W/$1.app/Contents/Info.plist"; /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable t" -c "Set :CFBundleIdentifier com.example.bgopt.$1" "$W/$1.app/Contents/Info.plist"; }
build() { # name, test file, sources...   (Swift only allows top-level code in a file called main.swift)
  local n="$1" t="$2"; shift 2; mkbundle "$n"; mkdir -p "$W/$n.src"; cp "$t" "$W/$n.src/main.swift"
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" "$@" "$W/$n.src/main.swift" -o "$W/$n.app/Contents/MacOS/t" 2>&1 | grep error; return "${PIPESTATUS[0]}"; }
CORE=(Sources/Engine.swift Sources/ActionLog.swift Sources/ProcTable.swift Sources/Policy.swift Sources/L10n.swift Sources/Format.swift)

step "log: permissions, one line per entry, clear"
build log tests/log_test.swift "${CORE[@]}" && BGOPT_LOG_DIR="$W/logdir" "$W/log.app/Contents/MacOS/t" || FAIL=1

step "row menu: contents for every kind of row, both languages"
build menu tests/row_menu_test.swift "${CORE[@]}" Sources/RowMenu.swift && "$W/menu.app/Contents/MacOS/t" || FAIL=1

step "startup items: parsing, rules for changing, real read"
build startup tests/startup_test.swift "${CORE[@]}" Sources/StartupItems.swift && "$W/startup.app/Contents/MacOS/t" || FAIL=1

step "changing jobs by hand: rules enforced by the engine"
swiftc -O tests/sleeper.swift -o "$W/bgsleeper" 2>&1 | grep error
mkdir -p "$W/fake/Google Chrome.app/Contents/MacOS"; cp "$W/bgsleeper" "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper"
codesign --force --sign - "$W/bgsleeper" "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper" 2>/dev/null
( "$W/bgsleeper" >/dev/null 2>&1 & ); ( "$W/fake/Google Chrome.app/Contents/MacOS/bgsleeper" >/dev/null 2>&1 & ); sleep 1   # detached: not "in front"
SL=$(pgrep -f "$W/bgsleeper" | head -1); CH=$(pgrep -f "Google Chrome.app/Contents/MacOS/bgsleeper" | head -1); FI=$(pgrep -x Finder | head -1)
if [ -z "$SL" ] || [ -z "$CH" ] || [ -z "$FI" ]; then echo "  could not start the test processes (sleeper=$SL fake-browser=$CH Finder=$FI)"; FAIL=1
else build manual tests/manual_control_test.swift "${CORE[@]}" && BGOPT_LOG_DIR="$W/logdir2" "$W/manual.app/Contents/MacOS/t" "$SL" "$CH" "$FI" || FAIL=1; fi

echo; [ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
