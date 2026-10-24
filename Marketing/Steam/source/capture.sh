#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lofty-promo-clang-cache"
products="$PWD/.build/out/Products/Debug"
sources=()
for source in Sources/TowerApp/*.swift; do
  if [[ "$source" != Sources/TowerApp/main.swift ]]; then sources+=("$source"); fi
done
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$products" \
 "$products/TowerCore.o" "$products/TowerArt.o" "$products/TowerSession.o" "$products/TowerPresentation.o" \
 "${sources[@]}" Marketing/Steam/source/capture.swift -o /tmp/lofty-promo-capture
PACKAGE_RESOURCE_BUNDLE_PATH="$products" /tmp/lofty-promo-capture "$PWD/Marketing/Steam" "$@"
