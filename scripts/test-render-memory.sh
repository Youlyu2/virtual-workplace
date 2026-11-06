#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
RENDER_SOURCES=()
for source in Sources/Shared/*.swift; do
  case "$source" in Sources/Shared/Codex*) continue ;; esac
  RENDER_SOURCES+=("$source")
done
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework AppKit -framework CoreGraphics \
  "${RENDER_SOURCES[@]}" Tests/RenderMemoryTests.swift -o build/RenderMemoryTests
python3 scripts/guard-memory.py --limit-mib 1024 --timeout 300 --interval 5 -- build/RenderMemoryTests "$@"
