#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lofty-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/lofty-swift-cache"
APP="$PWD/dist/Lofty Ambitions.app"
GAME_VERSION="$(tr -d '\r\n' < VERSION)"
if [ ! -f dist/AppIcon.icns ]; then scripts/make-icon.sh; fi
swift build -c release --disable-sandbox --arch arm64 --arch x86_64
BUILD_PRODUCTS="$(swift build -c release --disable-sandbox --arch arm64 --arch x86_64 --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
rm -rf "$APP/Contents/Resources/LoftyAmbitions_TowerArt.bundle"
ditto "$BUILD_PRODUCTS/LoftyAmbitions_TowerArt.bundle" "$APP/Contents/Resources/LoftyAmbitions_TowerArt.bundle"
# SwiftPM derives this identifier from the checkout folder; use the game's stable identity.
plutil -replace CFBundleIdentifier -string local.loftyambitions.art \
    "$APP/Contents/Resources/LoftyAmbitions_TowerArt.bundle/Contents/Info.plist"
cp "$BUILD_PRODUCTS/LoftyAmbitions" "$APP/Contents/MacOS/LoftyAmbitions"
# Keep local workspace paths and debug symbols out of the distributed executable.
xcrun strip -S "$APP/Contents/MacOS/LoftyAmbitions"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lofty Ambitions</string>
<key>CFBundleDisplayName</key><string>Lofty Ambitions</string>
<key>CFBundleExecutable</key><string>LoftyAmbitions</string>
<key>CFBundleIdentifier</key><string>local.loftyambitions.game</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$GAME_VERSION</string>
<key>CFBundleVersion</key><string>27</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
if [ -f dist/AppIcon.icns ]; then cp dist/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Lofty-Ambitions-macOS.zip"
echo "Built $APP"
