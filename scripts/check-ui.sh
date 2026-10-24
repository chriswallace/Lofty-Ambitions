#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lofty-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/lofty-swift-cache"
swift build --disable-sandbox
products="$(swift build --disable-sandbox --show-bin-path)"
view_sources=()
for source in Sources/TowerApp/*.swift; do
    if [[ "$source" != Sources/TowerApp/main.swift ]]; then view_sources+=("$source"); fi
done
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/lofty-ui-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$products" \
    "$products/TowerCore.o" "$products/TowerArt.o" "$products/TowerSession.o" "$products/TowerPresentation.o" \
    "${view_sources[@]}" scripts/check-ui.swift -o "$check_dir/check-ui"
PACKAGE_RESOURCE_BUNDLE_PATH="$products" "$check_dir/check-ui"
