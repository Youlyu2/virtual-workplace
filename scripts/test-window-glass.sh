#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library -framework CoreGraphics \
  Sources/Shared/WindowGlassMask.swift Tests/WindowGlassMaskTests.swift -o build/WindowGlassMaskTests
build/WindowGlassMaskTests
