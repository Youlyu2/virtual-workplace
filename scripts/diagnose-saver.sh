#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
SAVER_BUNDLE="$PROJECT_DIR/build/VirtualWorkplace.saver"
if [ ! -d "$SAVER_BUNDLE" ]; then
    echo "Run ./scripts/build.sh first." >&2
    exit 1
fi
plutil -lint "$SAVER_BUNDLE/Contents/Info.plist"
codesign --verify --strict "$SAVER_BUNDLE"
file "$SAVER_BUNDLE/Contents/MacOS/VirtualWorkplace"
xcrun clang -fobjc-arc -target arm64-apple-macos26.0 -isysroot "$(xcrun --show-sdk-path)" \
    -framework AppKit -framework ScreenSaver -framework CoreGraphics Sources/Diagnostics/SaverHost.m -o build/SaverHost
build/SaverHost "$SAVER_BUNDLE" "$PROJECT_DIR/build/saver-diagnostic.png" "$@"
echo "This host verifies the bundle and renderer. System sandbox, lock screen, and multiple displays still require the manual checks in docs/SCREENSAVER.md."
