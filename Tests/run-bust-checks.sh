#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/airposture-bust-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
cd "$ROOT"
CLANG_MODULE_CACHE_PATH="$CHECK_ROOT/module-cache" swiftc \
  Sources/AirPostureCore/PostureGaugeMapping.swift \
  Sources/AirPostureCore/BustAnimation.swift \
  Tests/AirPostureBustCheck/main.swift \
  -o "$CHECK_ROOT/AirPostureBustCheck"
"$CHECK_ROOT/AirPostureBustCheck"
