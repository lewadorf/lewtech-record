# Development & releases

Lewtech Record is a native macOS app, built with Swift Package Manager. The app targets macOS 15+. There are no third-party Swift package dependencies.

## Project map

| Location | Responsibility |
| --- | --- |
| `Sources/LewtechRecord/` | SwiftUI/AppKit UI, capture and persistence |
| `CaptureController.swift` | Devices, capture lifecycle and permissions |
| `RecordingPipeline.swift` | Media timing, composition and MP4 writing |
| `LibraryStore.swift` | Local files, library metadata and recovery |
| `Resources/` | Bundled branding, fonts and font license |
| `packaging/` | App metadata and icon |
| `scripts/build.sh` | Release executable, app bundle and ad-hoc signing |
| `scripts/install.sh` | Local installation with backup and rollback |
| `scripts/verify.sh` | Standalone Swift verification harness |
| `scripts/tests/` | Timeline, library, preview and media checks |
| `scripts/package.sh` | ZIP distribution and checksum |

ScreenCaptureKit supplies screen/window frames. AVFoundation handles cameras, microphones and media writing; Core Image composites the facecam. Library metadata is written atomically. Recordings are written incrementally, with interrupted files retained for recovery where possible.

## Local development

```sh
./scripts/build.sh
open "dist/Lewtech Record.app"
./scripts/verify.sh
```

Use Finder or `open` to launch the bundle. Launching the executable directly from an agent terminal can cause permission prompts to be attributed to the host app. Do not run permission resets as part of automated tests.

## Manual release checks

Before promoting a release as stable, check on the target hardware:

- Screen only, window only, camera only and screen + camera.
- Real camera and microphone, including any supported external devices.
- Preview, facecam dragging/resizing, microphone levels and countdown.
- Several pause/resume cycles and at least ten active minutes of recording.
- Normal stop, playback in QuickTime, audible speech and audio/video sync.
- Export, rename, search, app restart and library persistence.
- Permission denial, source disconnection and interrupted-file recovery.

For the longer fragmented-MP4 regression test, run `LEWTECH_STRESS_SECONDS=130 ./scripts/verify.sh`. Synthetic codec tests validate file writing and timing but do not establish physical device compatibility. Record known limitations in release notes.

## Package a release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `packaging/Info.plist`.
2. Run `./scripts/verify.sh` and complete the relevant manual checks.
3. Run `./scripts/package.sh` on the architecture you intend to distribute.
4. Inspect the ZIP contents, launch the resulting app, and verify its license files.
5. Publish the ZIP and matching `.sha256` file on GitHub Releases, naming the tested macOS version, processor and known limitations.

The script builds for the host architecture and uses an ad-hoc signature. It does not create a universal binary, obtain certificates or notarize a build. A public binary intended for frictionless installation needs a separate Developer ID signing and Apple notarization process. Never commit certificates, signing credentials or API tokens.

GitHub Actions builds, packages and verifies the app on Apple Silicon for pushes and pull requests. Successful runs retain the app ZIP and checksum as a workflow artifact for 14 days. Release publication remains explicit so an untested binary is not automatically presented as a stable release.
