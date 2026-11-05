#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework AppKit -framework CoreGraphics \
  Sources/Shared/Model.swift Sources/Shared/PendingWeather.swift Sources/Shared/PendingNote.swift Sources/Shared/WorldViewport.swift Sources/Shared/DisplaySceneRouting.swift \
  Tests/DisplaySceneRoutingTests.swift -o build/DisplaySceneRoutingTests
build/DisplaySceneRoutingTests
