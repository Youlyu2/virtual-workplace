#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
MODEL_SOURCES=()
while IFS= read -r source; do MODEL_SOURCES+=("$source"); done < <(rg --files Sources/Shared -g '*.swift' | sort | rg '/(Model|StateStore|PendingNote|PendingWeather)\.swift$')
if [ "${#MODEL_SOURCES[@]}" -eq 0 ]; then
    echo "Expected shared Model.swift and StateStore.swift." >&2
    exit 1
fi
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library \
    "${MODEL_SOURCES[@]}" Tests/ModelTests.swift -o build/ModelTests
build/ModelTests
