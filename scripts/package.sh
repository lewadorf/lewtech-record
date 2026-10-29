#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Always build first so packages cannot silently contain a stale app.
./scripts/build.sh
app="$PWD/dist/Lewtech Record.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
arch="$(uname -m)"
case "$version" in
    ''|*[!0-9A-Za-z.-]*) printf '%s\n' 'Invalid bundle version for archive name' >&2; exit 1 ;;
esac
archive="Lewtech-Record-${version}-macOS-${arch}.zip"
staging_dir="$(mktemp -d "$PWD/dist/.package-stage.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$staging_dir/$archive"
(cd "$staging_dir" && shasum -a 256 "$archive" > "$archive.sha256")
mv "$staging_dir/$archive" "$PWD/dist/$archive"
mv "$staging_dir/$archive.sha256" "$PWD/dist/$archive.sha256"
printf '%s\n' "Package: $PWD/dist/$archive" "Checksum: $PWD/dist/$archive.sha256"
printf '%s\n' 'Ad-hoc signed; not Developer ID signed or notarized. Test before publishing.'
