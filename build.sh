#!/usr/bin/env bash
# Builds AirPosture into a runnable, signed .app bundle.
#
# Usage:
#   ./build.sh [debug|release]
#
# Signing:
#   Ad-hoc by default (local use). Do not attach the restricted
#   com.apple.developer.headphone-motion entitlement to an ad-hoc signature —
#   AMFI will SIGKILL the app on launch. NSMotionUsageDescription + the
#   Motion & Fitness TCC prompt is enough for local Core Motion access.
#
#   For Developer ID distribution:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="AirPosture"
DISPLAY_NAME="AirPosture"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SWIFT_FLAGS=(-c "$CONFIG" --disable-sandbox)

echo "› Compiling ($CONFIG)…"
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

APP_BUNDLE="$BIN_DIR/$DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
echo "› Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "› Code signing with: $SIGN_IDENTITY"
  codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/AirPostureMac.entitlements" \
    "$APP_BUNDLE"
else
  echo "› Code signing (ad-hoc, no restricted entitlements)"
  codesign --force --sign - "$APP_BUNDLE"
fi

echo "✓ Built $APP_BUNDLE"
echo "  Run it with: open \"$APP_BUNDLE\""
