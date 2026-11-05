#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework AppKit -framework Carbon \
  Sources/App/QuickNoteHotKey.swift Tests/QuickNoteHotKeyTests.swift -o build/QuickNoteHotKeyTests
build/QuickNoteHotKeyTests
