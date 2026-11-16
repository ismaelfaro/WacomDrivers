#!/bin/bash
# Builds a universal (Apple Silicon + Intel) "Wacom Bamboo.app" and a zip of it in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/wacom-bamboo"

APP="dist/Wacom Bamboo.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wacom Bamboo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Ad-hoc signature: runs on this Mac and on others after the Gatekeeper step in the README.
codesign --force --deep --sign - "$APP"

(cd dist && ditto -c -k --sequesterRsrc --keepParent "Wacom Bamboo.app" "Wacom Bamboo.zip")
echo "Built dist/Wacom Bamboo.zip"
