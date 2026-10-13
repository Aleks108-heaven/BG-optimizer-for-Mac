#!/bin/bash
# Builds "BG Optimizer.app". The app is built and signed in a temp folder (Desktop/iCloud folders add
# file attributes that break code signing), then copied out.
#   ./build.sh            -> build/BG Optimizer.app
#   ./build.sh --install  -> also ~/Applications/BG Optimizer.app (use this one: "Launch at login"
#                            remembers the app's location, so it must live somewhere stable)
#   ./build.sh --dmg      -> also dist/BG-Optimizer-<version>.dmg (drag-to-Applications installer)
set -euo pipefail
cd "$(dirname "$0")"
python3 tools/check_strings.py          # stop here if a translation is missing or broken
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/BG Optimizer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o "$APP/Contents/MacOS/BGOptimizer"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/uk.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

copy_to() {
    rm -rf "$1/BG Optimizer.app"
    mkdir -p "$1"
    ditto --noextattr --noqtn "$APP" "$1/BG Optimizer.app"
    echo "Built: $1/BG Optimizer.app"
}
copy_to "$PWD/build"

for arg in "$@"; do
    case "$arg" in
    --install) copy_to "$HOME/Applications" ;;
    --dmg)
        VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
        OUT="dist/BG-Optimizer-$VERSION.dmg"
        DMG="$STAGE/dmg"
        mkdir -p "$DMG" dist
        ditto --noextattr --noqtn "$APP" "$DMG/BG Optimizer.app"
        xattr -cr "$DMG/BG Optimizer.app"
        ln -s /Applications "$DMG/Applications"
        rm -f "$OUT"
        hdiutil create -volname "BG Optimizer" -srcfolder "$DMG" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null 2>&1
        echo "Built: $PWD/$OUT"
        ;;
    esac
done
