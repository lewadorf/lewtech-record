#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${LEWTECH_BUILD_ROOT:-$PWD/.build}"
mkdir -p "$build_root/verification-cache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_root/verification-cache" \
  Sources/LewtechRecord/CaptureTypes.swift \
  Sources/LewtechRecord/Localization.swift \
  Sources/LewtechRecord/RecordingPipeline.swift \
  Sources/LewtechRecord/LivePreview.swift \
  Sources/LewtechRecord/LibraryStore.swift \
  scripts/tests/*.swift -o "$build_root/verify-recording"
LEWTECH_LOCALIZATION_DIRECTORY="$PWD/Sources/LewtechRecord/Resources" "$build_root/verify-recording"
