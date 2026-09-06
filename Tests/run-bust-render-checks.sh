#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}airposture-bust-render.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/airposture-clang-module-cache}" swiftc -O -parse-as-library \
  Sources/AirPostureCore/*.swift \
  Sources/AirPostureMac/BustSceneRig.swift \
  Tests/AirPostureBustRenderCheck/main.swift -o "$CHECK_DIR/BustRenderCheck"
"$CHECK_DIR/BustRenderCheck"
