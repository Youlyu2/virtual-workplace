#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library -lsqlite3 \
  Sources/Shared/AgentPuppet.swift Sources/Shared/Model.swift Sources/Shared/PendingWeather.swift Sources/Shared/PendingNote.swift \
  Sources/Shared/CodexRolloutDetails.swift Sources/Shared/CodexRemoteIndex.swift \
  Sources/Shared/CodexStreamDetails.swift Sources/Shared/CodexDesktopObserver.swift \
  Tests/CodexObserverMemoryTests.swift -o build/CodexObserverMemoryTests
python3 scripts/guard-memory.py --limit-mib 768 --timeout 60 --interval 1 \
  --jsonl build/codex-memory.jsonl -- build/CodexObserverMemoryTests "$@"
