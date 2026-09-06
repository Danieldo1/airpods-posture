#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_BASE="${TMPDIR:-/tmp}"
CHECK_ROOT="$(mktemp -d "${TEMP_BASE%/}/airposture-native-checks.XXXXXX")"
CLANG_CACHE="${CLANG_MODULE_CACHE_PATH:-$CHECK_ROOT/clang-module-cache}"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$CLANG_CACHE"
cd "$ROOT"

CORE_SOURCES=(Sources/AirPostureCore/*.swift)
SETTINGS_SOURCES=(
  Sources/AirPostureCore/WarningIntensity.swift
  Sources/AirPostureMac/AirPostureSettings.swift
)
SOUND_SOURCES=(
  "${SETTINGS_SOURCES[@]}"
  Sources/AirPostureMac/AlertService.swift
)
STORE_SOURCES=(
  "${CORE_SOURCES[@]}"
  Sources/AirPostureMac/AirPostureSettings.swift
  Sources/AirPostureMac/SoundPlayback.swift
  Sources/AirPostureMac/AlertService.swift
  Sources/AirPostureMac/WeeklyAnalyticsStore.swift
)

compile_and_run() {
  local name="$1"
  local test_source="$2"
  shift 2
  local executable="$CHECK_ROOT/$name"
  echo "› Compiling $name"
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" swiftc -parse-as-library "$@" "$test_source" -o "$executable"
  echo "› Running $name"
  "$executable"
}

run_sound_check() {
  echo "EXPECTED DIAGNOSTICS: the sound policy harness forces preparation, start, decode, and completion failures to verify same-sound fallback and error reporting."
  # Same-file compilation lets native checks inspect private backend ownership
  # without exposing test-only interfaces in the application.
  cat Sources/AirPostureMac/SoundPlayback.swift Tests/AirPostureSoundCheck/main.swift > "$CHECK_ROOT/SoundPlaybackCheck.swift"
  compile_and_run AirPostureSoundCheck "$CHECK_ROOT/SoundPlaybackCheck.swift" "${SOUND_SOURCES[@]}"
  echo "END EXPECTED DIAGNOSTICS"
}

run_store_check() {
  cat Sources/AirPostureMac/PostureTrackingManager.swift Tests/AirPostureAnalyticsStoreCheck/main.swift > "$CHECK_ROOT/PostureTrackingCheck.swift"
  compile_and_run AirPostureAnalyticsStoreCheck "$CHECK_ROOT/PostureTrackingCheck.swift" "${STORE_SOURCES[@]}"
}

case "${1:-checks}" in
  checks)
    compile_and_run AirPostureSettingsCheck Tests/AirPostureSettingsCheck/main.swift "${SETTINGS_SOURCES[@]}"
    run_sound_check
    run_store_check
    ;;
  sound-check)
    run_sound_check
    ;;
  store-check)
    run_store_check
    ;;
  sound-probe)
    echo "This opt-in probe plays Pop, Tink, Purr, Bottle, and Morse through the real system audio output."
    compile_and_run AirPostureSoundProbe Tests/AirPostureSoundProbe/main.swift "${SOUND_SOURCES[@]}" Sources/AirPostureMac/SoundPlayback.swift
    ;;
  *)
    echo "usage: $0 [checks|sound-check|store-check|sound-probe]" >&2
    exit 2
    ;;
esac
