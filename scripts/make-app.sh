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

# Sign with the local certificate when it exists (scripts/make-signing-cert.sh): the identity then
# stays the same on every build, so macOS keeps the app's permissions. Otherwise fall back to an
# ad-hoc signature, which changes on every build. Either runs on other Macs after the Gatekeeper
# step in the README.
IDENTITY="${SIGN_IDENTITY:-Wacom Bamboo Local Signing}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    if codesign --force --deep --sign "$IDENTITY" "$APP"; then
        echo "Signed with \"$IDENTITY\""
    else
        echo "Could not use \"$IDENTITY\" (keychain access not approved?); signing ad-hoc instead." >&2
        codesign --force --deep --sign - "$APP"
    fi
else
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc (run scripts/make-signing-cert.sh for a stable signature)"
fi

(cd dist && ditto -c -k --sequesterRsrc --keepParent "Wacom Bamboo.app" "Wacom Bamboo.zip")
echo "Built dist/Wacom Bamboo.zip"
