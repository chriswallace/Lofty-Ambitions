#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bootstrap-desktop.sh
export LOFTY_DESKTOP=1
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lofty-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/lofty-swift-cache"
exec swift run --disable-sandbox LoftyDesktop "$@"
