#!/bin/bash
set -euo pipefail
remove_own_bundle() {
    local destination="$1" expected_id="$2"
    [ -e "$destination" ] || return 0
    local actual_id
    actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$actual_id" != "$expected_id" ]; then
        echo "Refusing to remove a different application: $destination ($actual_id)" >&2
        return 1
    fi
    rm -rf "$destination"
    echo "Removed $destination"
}
remove_own_bundle "$HOME/Applications/虚拟工位.app" com.virtualworkplace.prototype
remove_own_bundle "$HOME/Library/Screen Savers/VirtualWorkplace.saver" com.virtualworkplace.screensaver
echo "Preserved VirtualWorkplace state and backups in Application Support."
echo "Choose another screen saver in System Settings if this one was selected."
