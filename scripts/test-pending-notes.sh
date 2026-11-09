#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library \
  Sources/Shared/AgentPuppet.swift Sources/Shared/Model.swift Sources/Shared/PendingWeather.swift Sources/Shared/StateStore.swift \
  Sources/Shared/PendingNote.swift Sources/Shared/PendingNoteStore.swift \
  Tests/PendingNoteTests.swift -o build/PendingNoteTests
build/PendingNoteTests
