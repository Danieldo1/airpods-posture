#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_TEMP="${TMPDIR:-/tmp}"
TASK_BUILD="${AIRPOSTURE_FIXTURE_BUILD:-${TASK_TEMP%/}/airposture-ui-fixture-build}"
TASK_APP="${AIRPOSTURE_FIXTURE_APP:-${TASK_TEMP%/}/AirPostureUIFixture.app}"
TASK_SWIFTPM="${AIRPOSTURE_SWIFTPM_CACHE_ROOT:-${TASK_TEMP%/}/airposture-swiftpm}"
TASK_CLANG_CACHE="${CLANG_MODULE_CACHE_PATH:-${TASK_TEMP%/}/airposture-ui-fixture-clang-cache}"
SWIFT_FLAGS=(
  -c debug
  --disable-sandbox
  --cache-path "$TASK_SWIFTPM/cache"
  --scratch-path "$TASK_BUILD"
  --config-path "$TASK_SWIFTPM/config"
  --security-path "$TASK_SWIFTPM/security"
)
mkdir -p "$TASK_CLANG_CACHE"
CLANG_MODULE_CACHE_PATH="$TASK_CLANG_CACHE" swift build "${SWIFT_FLAGS[@]}"
TASK_BIN="$(CLANG_MODULE_CACHE_PATH="$TASK_CLANG_CACHE" swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
COLOR_OBJECTS=("$TASK_BIN"/ColorSelector.build/*.swift.o)
if [[ ! -e "${COLOR_OBJECTS[0]}" ]]; then
  echo "error: ColorSelector build objects not found under $TASK_BIN" >&2
  exit 1
fi
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
TASK_SOURCES=()
for source in "$TASK_ROOT"/Sources/AirPostureMac/*.swift; do
  [[ "$source" == */AirPostureMacApp.swift ]] || TASK_SOURCES+=("$source")
done
CLANG_MODULE_CACHE_PATH="$TASK_CLANG_CACHE" swiftc -parse-as-library \
  -I "$TASK_BIN/Modules" "$TASK_ROOT"/Sources/AirPostureCore/*.swift \
  "${TASK_SOURCES[@]}" "$TASK_ROOT/Tests/AirPostureUIFixture/main.swift" \
  "${COLOR_OBJECTS[@]}" -o "$TASK_APP/Contents/MacOS/AirPostureUIFixture"
cp "$TASK_ROOT/Sources/AirPostureMac/Resources/AirPostureBust.usdz" "$TASK_APP/Contents/Resources/"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AirPostureUIFixture</string>
<key>CFBundleIdentifier</key><string>com.macposture.fixture.ui20260906</string>
<key>CFBundleName</key><string>AirPosture UI Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMotionUsageDescription</key><string>This isolated AirPosture UI fixture uses the production tracker to display headphone connection status. Monitoring starts paused.</string>
</dict></plist>
PLIST
codesign --force --sign - "$TASK_APP"
"$TASK_APP/Contents/MacOS/AirPostureUIFixture" --validate-fixtures
printf '%s\n' "$TASK_APP"
