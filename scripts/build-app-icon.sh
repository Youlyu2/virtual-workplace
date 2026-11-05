#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$PROJECT_DIR/scripts/build-app-icon.sh"
SOURCE="$PROJECT_DIR/Resources/AppIcon/icon-source.png"
ICON="$PROJECT_DIR/Resources/AppIcon/VirtualWorkplace.icns"
BUILD_DIR="$PROJECT_DIR/build"
CACHE="$BUILD_DIR/app-icon.sha256"

if [ ! -s "$SOURCE" ]; then
    echo "Missing app icon source: $SOURCE" >&2
    exit 1
fi
mkdir -p "$BUILD_DIR"
FINGERPRINT="$(shasum -a 256 "$SOURCE" "$SCRIPT_PATH" | shasum -a 256 | awk '{print $1}')"
if [ -s "$ICON" ] && [ -f "$CACHE" ] && [ "$(cat "$CACHE")" = "$FINGERPRINT" ]; then
    exit 0
fi

WIDTH="$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth:/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight:/ {print $2}')"
if ! [[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] || [ "$WIDTH" -ne "$HEIGHT" ] || [ "$WIDTH" -lt 1024 ]; then
    echo "App icon source must be a square PNG of at least 1024×1024 pixels." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "$BUILD_DIR/app-icon.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/VirtualWorkplace.iconset"
mkdir -p "$ICONSET"
for POINTS in 16 32 128 256 512; do
    sips -s format png -z "$POINTS" "$POINTS" "$SOURCE" \
        --out "$ICONSET/icon_${POINTS}x${POINTS}.png" >/dev/null
    PIXELS=$((POINTS * 2))
    sips -s format png -z "$PIXELS" "$PIXELS" "$SOURCE" \
        --out "$ICONSET/icon_${POINTS}x${POINTS}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK_DIR/VirtualWorkplace.icns"
mv "$WORK_DIR/VirtualWorkplace.icns" "$ICON"
printf '%s\n' "$FINGERPRINT" > "$CACHE"
echo "Built app icon: $ICON"
