#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/虚拟工位.app"
SAVER_BUNDLE="$BUILD_DIR/VirtualWorkplace.saver"
SDK_PATH="$(xcrun --show-sdk-path)"
./scripts/build-app-icon.sh
SHARED_SOURCES=()
APP_SOURCES=()
SAVER_SOURCES=()
while IFS= read -r source; do SHARED_SOURCES+=("$source"); done < <(rg --files Sources/Shared -g '*.swift' | sort)
while IFS= read -r source; do APP_SOURCES+=("$source"); done < <(rg --files Sources/App -g '*.swift' | sort)
while IFS= read -r source; do SAVER_SOURCES+=("$source"); done < <(rg --files Sources/ScreenSaver -g '*.swift' | sort)
if [ "${#SHARED_SOURCES[@]}" -eq 0 ] || [ "${#APP_SOURCES[@]}" -eq 0 ] || [ "${#SAVER_SOURCES[@]}" -eq 0 ]; then
    echo "Missing Swift sources in Sources/Shared, Sources/App, or Sources/ScreenSaver." >&2
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" \
    "$SAVER_BUNDLE/Contents/MacOS" "$SAVER_BUNDLE/Contents/Resources" "$BUILD_DIR/module-cache"
COMMON=(-swift-version 5 -target arm64-apple-macos26.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/module-cache" -O -parse-as-library)

xcrun swiftc "${COMMON[@]}" -module-name VirtualWorkplaceApp \
    -framework AppKit -framework QuartzCore -framework CoreGraphics -framework Carbon \
    "${SHARED_SOURCES[@]}" "${APP_SOURCES[@]}" \
    -o "$APP_BUNDLE/Contents/MacOS/VirtualWorkplace"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleDisplayName</key><string>虚拟工位</string>
<key>CFBundleExecutable</key><string>VirtualWorkplace</string>
<key>CFBundleIdentifier</key><string>com.virtualworkplace.prototype</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>虚拟工位</string>
<key>CFBundleIconFile</key><string>VirtualWorkplace.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9.2</string>
<key>CFBundleVersion</key><string>23</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

xcrun swiftc "${COMMON[@]}" -module-name VirtualWorkplaceSaver -emit-library \
    -framework AppKit -framework ScreenSaver -framework QuartzCore -framework CoreGraphics \
    "${SHARED_SOURCES[@]}" "${SAVER_SOURCES[@]}" \
    -o "$SAVER_BUNDLE/Contents/MacOS/VirtualWorkplace"
cp Resources/ScreenSaver-Info.plist "$SAVER_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon/VirtualWorkplace.icns "$APP_BUNDLE/Contents/Resources/VirtualWorkplace.icns"
if [ -d Resources/Characters ]; then
    ditto Resources/Characters "$APP_BUNDLE/Contents/Resources/Characters"
    ditto Resources/Characters "$SAVER_BUNDLE/Contents/Resources/Characters"
fi
if [ -d Resources/Room ]; then
    ditto Resources/Room "$APP_BUNDLE/Contents/Resources/Room"
    ditto Resources/Room "$SAVER_BUNDLE/Contents/Resources/Room"
fi
plutil -lint "$APP_BUNDLE/Contents/Info.plist" "$SAVER_BUNDLE/Contents/Info.plist"
# Sign the nested plugin before sealing the application that carries it. The
# installed app is self-contained: its Install Screen Saver button can repair or
# update a missing/older user plugin without requiring the source checkout.
codesign --force --sign - --timestamp=none "$SAVER_BUNDLE"
rm -rf "$APP_BUNDLE/Contents/Resources/VirtualWorkplace.saver"
ditto "$SAVER_BUNDLE" "$APP_BUNDLE/Contents/Resources/VirtualWorkplace.saver"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
codesign --verify --strict "$SAVER_BUNDLE"
codesign --verify --strict "$APP_BUNDLE/Contents/Resources/VirtualWorkplace.saver"
echo "Built arm64 local prototypes:"
echo "$APP_BUNDLE"
echo "$SAVER_BUNDLE"
