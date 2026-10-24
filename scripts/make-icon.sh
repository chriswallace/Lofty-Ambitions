#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lofty-clang-cache"
mkdir -p dist/AppIcon.iconset
swift scripts/make-icon.swift "${TMPDIR:-/tmp}/lofty-icon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "${TMPDIR:-/tmp}/lofty-icon.png" --out "dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size*2))
  sips -z "$double" "$double" "${TMPDIR:-/tmp}/lofty-icon.png" --out "dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns dist/AppIcon.iconset
