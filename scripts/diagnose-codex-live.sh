#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library \
  -framework AppKit -framework QuartzCore -framework CoreGraphics -lsqlite3 \
  Sources/Shared/*.swift Sources/Diagnostics/CodexLiveProbe.swift -o build/CodexLiveProbe
WORKPLACE_PROBE_OUTPUT_ROOT="$PROJECT_DIR/build" build/CodexLiveProbe "$@"
