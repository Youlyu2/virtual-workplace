#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$PROJECT_DIR/build/虚拟工位.app"
SAVER_SOURCE="$PROJECT_DIR/build/VirtualWorkplace.saver"
if [ ! -d "$APP_SOURCE" ] || [ ! -d "$SAVER_SOURCE" ]; then
    echo "Run ./scripts/build.sh first." >&2
    exit 1
fi
BACKUP_DIR="$HOME/Library/Application Support/VirtualWorkplace/Backups/$(date +%Y%m%d-%H%M%S)-$$"
install_own_bundle() {
    local source="$1" destination="$2" expected_id="$3"
    if [ -e "$destination" ]; then
        local actual_id
        actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
        if [ "$actual_id" != "$expected_id" ]; then
            echo "Refusing to replace a different application: $destination ($actual_id)" >&2
            exit 1
        fi
        mkdir -p "$BACKUP_DIR"
        ditto "$destination" "$BACKUP_DIR/$(basename "$destination")"
        rm -rf "$destination"
    fi
    mkdir -p "$(dirname "$destination")"
    ditto "$source" "$destination"
    codesign --verify --strict "$destination"
    echo "Installed $destination"
}
install_own_bundle "$APP_SOURCE" "$HOME/Applications/虚拟工位.app" com.virtualworkplace.prototype
install_own_bundle "$SAVER_SOURCE" "$HOME/Library/Screen Savers/VirtualWorkplace.saver" com.virtualworkplace.screensaver
echo "Select 虚拟工位 in System Settings > Wallpaper > Screen Saver."
echo "Existing bundles were backed up to $BACKUP_DIR if replacements were needed."
echo "System screen saver selection, password policy, and sleep settings were not changed."
