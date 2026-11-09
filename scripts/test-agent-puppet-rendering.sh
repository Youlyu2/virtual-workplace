#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework AppKit -framework CoreGraphics \
  Sources/Shared/AgentPuppet.swift Sources/Shared/PixelAgentPuppet.swift \
  Tests/AgentPuppetRenderingTests.swift -o build/AgentPuppetRenderingTests
python3 scripts/guard-memory.py --limit-mib 384 --timeout 60 --interval 0.25 -- build/AgentPuppetRenderingTests
