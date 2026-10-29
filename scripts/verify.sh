#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/verification-cache
swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/verification-cache" \
  Sources/LewtechRecord/CaptureTypes.swift \
  Sources/LewtechRecord/RecordingPipeline.swift \
  Sources/LewtechRecord/LivePreview.swift \
  Sources/LewtechRecord/LibraryStore.swift \
  scripts/tests/*.swift -o .build/verify-recording
.build/verify-recording
