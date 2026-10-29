#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox
mkdir -p "$PWD/dist"
staging_dir="$(mktemp -d "$PWD/dist/.build-stage.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
APP="$staging_dir/Lewtech Record.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LewtechRecord "$APP/Contents/MacOS/LewtechRecord"
cp -R .build/release/LewtechRecord_LewtechRecord.bundle "$APP/Contents/Resources/"
cp packaging/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/Licenses/"
cp Sources/LewtechRecord/Resources/Manrope-LICENSE.txt "$APP/Contents/Resources/Licenses/"
if [ -f packaging/AppIcon.icns ]; then cp packaging/AppIcon.icns "$APP/Contents/Resources/"; fi
xattr -cr "$APP"
codesign --force --sign - --identifier no.lewtech.record "$APP"
codesign --verify --deep --strict "$APP"
# Never overwrite an executable that a test instance may still have mapped.
# Rename the old bundle, then move the complete signed build into place.
target_app="$PWD/dist/Lewtech Record.app"
if [ -d "$target_app" ]; then
    mv "$target_app" "$staging_dir/previous.app"
fi
mv "$APP" "$target_app"
printf '%s\n' "App klar: $target_app"
