#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}airposture-bust-lifecycle.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
APP="$CHECK_DIR/AvatarCheck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/airposture-clang-module-cache}" swiftc -D DEBUG -parse-as-library \
  Sources/AirPostureCore/*.swift \
  Sources/AirPostureMac/AirPostureSettings.swift Sources/AirPostureMac/SoundPlayback.swift \
  Sources/AirPostureMac/AlertService.swift Sources/AirPostureMac/PostureTrackingManager.swift \
  Sources/AirPostureMac/BustSceneRig.swift Sources/AirPostureMac/BustDebugView.swift \
  Sources/AirPostureMac/InstrumentBustView.swift Tests/AirPostureBustLifecycleCheck/main.swift \
  -o "$APP/Contents/MacOS/AvatarCheck"
cp Sources/AirPostureMac/Resources/AirPostureBust.usdz "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>AvatarCheck</string><key>CFBundleIdentifier</key><string>com.macposture.avatar-lifecycle-check</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
"$APP/Contents/MacOS/AvatarCheck" "$@"
