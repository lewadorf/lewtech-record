#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
install_root="$HOME/Applications"
installed_app="$install_root/Lewtech Record.app"
built_app="$project_dir/dist/Lewtech Record.app"
staging_dir=""

require_closed_app() {
    if pgrep -x LewtechRecord >/dev/null 2>&1; then
        printf '%s\n' 'Avslutt Lewtech Record fra appmenyen eller menylinjeikonet, og kjør installeringen på nytt.' >&2
        exit 1
    fi
}

cleanup() {
    # Only remove the temporary directory created by this invocation.
    # User recordings and previous app installations are never removed.
    if [ -n "$staging_dir" ] && [ -d "$staging_dir" ]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup EXIT

require_closed_app
"$project_dir/scripts/build.sh"
mkdir -p "$install_root"

if [ -L "$installed_app" ]; then
    printf '%s\n' "Installasjonsmålet er en symbolsk lenke. Flytt den først: $installed_app" >&2
    exit 1
fi
if [ -e "$installed_app" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$installed_app/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$existing_id" != 'no.lewtech.record' ]; then
        printf '%s\n' "En annen fil eller app bruker installasjonsnavnet. Flytt den først: $installed_app" >&2
        exit 1
    fi
fi

staging_dir="$(mktemp -d "$install_root/.lewtech-record-install.XXXXXX")"
staged_app="$staging_dir/Lewtech Record.app"
ditto --norsrc --noextattr "$built_app" "$staged_app"
xattr -cr "$staged_app"
codesign --verify --deep --strict "$staged_app"

# Recheck after building, in case the app was opened in the meantime.
require_closed_app
backup_app=""
if [ -e "$installed_app" ]; then
    backup_root="$install_root/.Lewtech Record backups"
    mkdir -p "$backup_root"
    backup_app="$backup_root/Lewtech Record-$(date '+%Y%m%d-%H%M%S')-$$.app"
    mv "$installed_app" "$backup_app"
fi

if ! mv "$staged_app" "$installed_app"; then
    if [ -n "$backup_app" ]; then mv "$backup_app" "$installed_app"; fi
    printf '%s\n' 'Kunne ikke plassere den nye appen. Forrige installasjon er beholdt.' >&2
    exit 1
fi

if ! codesign --verify --deep --strict "$installed_app"; then
    # Move the failed new build back into temporary staging, then restore the prior app.
    mv "$installed_app" "$staged_app"
    if [ -n "$backup_app" ]; then mv "$backup_app" "$installed_app"; fi
    printf '%s\n' 'Signaturkontrollen feilet. Forrige installasjon er gjenopprettet hvis den fantes.' >&2
    exit 1
fi

printf '%s\n' "Installert: $installed_app"
if [ -n "$backup_app" ]; then printf '%s\n' "Forrige app er beholdt: $backup_app"; fi
printf '%s\n' 'Opptakene dine er ikke endret. Åpne appen fra Finder for å begynne.'
