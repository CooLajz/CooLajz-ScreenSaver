#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -module-cache-path "$PWD/.build/IntegrationModuleCache" \
    -import-objc-header Sources/Extension/ScreenSaverPrivate.h \
    Sources/Core/*.swift Sources/Saver/AtlasSaverView.swift Sources/Extension/AtlasExtension.swift \
    Tests/Integration/main.swift -o .build/AtlasIntegrationChecks
.build/AtlasIntegrationChecks
