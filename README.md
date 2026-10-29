<p align="center">
  <img src="docs/assets/lewtech-record-hero.png" alt="Lewtech Record — Your screen. Your story. Your Mac. Warm cream, forest green and terracotta illustration of a screen, camera and recording controls." width="100%">
</p>

<h1 align="center">Lewtech Record</h1>
<p align="center"><strong>A little less friction. A lot more showing.</strong><br>Native screen, camera and microphone recording. Everything stays on your Mac.</p>
<p align="center">
  <a href="https://github.com/lewadorf/lewtech-record/releases">Downloads</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="docs/BRUKERVEILEDNING.md">Norsk brukerveiledning</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>
<p align="center"><code>macOS 15+</code> &nbsp; <code>Swift + SwiftUI</code> &nbsp; <code>Local MP4</code> &nbsp; <code>No account required</code></p>

---

Record a walkthrough, explain an idea or show someone how something works. Lewtech Record brings your screen, facecam and voice into one local video, with a calm interface in Lewtech's warm paper and forest-green palette.

Built by **[Leander Wachendorf](https://github.com/lewadorf)**. The app interface is currently in Norwegian; this guide is in English so more people can get started.

> **Early release:** core recording and export are implemented. Automated media checks are available, but the full physical camera/microphone and long-session test matrix is not complete. Try a short recording with your own devices before relying on it for a long session. The artwork above is a brand illustration, not a screenshot.

## Made for showing

| Capture | Make it yours | Keep control |
| :--- | :--- | :--- |
| Full screen or a selected window | Round or square facecam | Pause and resume |
| Screen + camera, screen only or camera only | Drag and resize before recording | Floating controls and menu bar |
| Optional microphone audio | Live preview and audio level meter | Local library and MP4 export |

<img src="docs/assets/recording-flow.svg" alt="Choose your source, record with pause and resume, then keep your MP4 on your Mac." width="100%">

**No account. No subscription. No built-in upload.** The app bundles its fonts and visual assets and does not need an internet connection to record. There is no system-audio recording, video editor, transcription or cloud-sharing service in this version.

## Get started

### Download an app build

Check **[GitHub Releases](https://github.com/lewadorf/lewtech-record/releases)** for packaged builds and their compatibility notes. If no app archive is listed, use the source installation below. GitHub's automatically generated “Source code” ZIP is the source project, not an installable app.

For a published app ZIP:

1. Download the archive matching your Mac's processor and extract it.
2. Move **Lewtech Record.app** to your **Applications** folder. Quit an older running copy first.
3. Open the app from Finder and grant the permissions needed for your chosen recording mode.

Local builds use an **ad-hoc signature**. They are not Apple Developer ID signed or notarized, and macOS may block downloaded builds. Only for a build you trust, follow Apple's **[opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)** guidance. Building from source is also supported. Do not disable Gatekeeper globally.

### Install from source

You need **macOS 15 or newer**, Git and a compatible Apple Swift toolchain. The project uses Swift tools version 5.9 and a macOS 15 SDK or newer; development builds have used Swift 6.3.3 in Swift 5 language mode. Full Xcode is optional if your Command Line Tools include the required SDK.

Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

Then clone and install:

```sh
git clone https://github.com/lewadorf/lewtech-record.git
cd lewtech-record
./scripts/install.sh
open "$HOME/Applications/Lewtech Record.app"
```

The installer builds the app, verifies its signature and installs it to `~/Applications/Lewtech Record.app`. An existing installation is backed up to `~/Applications/.Lewtech Record backups/`. **Your recordings are not changed.** Quit Lewtech Record, including its menu-bar instance, before installing an update.

The build uses the current Mac's architecture. A build made on Apple Silicon is not automatically an Intel or universal build.

## Your first recording

1. Select **Nytt opptak** (New recording).
2. Choose screen + camera, screen only or camera only, then select your screen/window and devices.
3. Check the live preview and microphone meter. Disable the microphone if you want silent video.
4. For facecam, choose a circle or square. Drag it into position and use a corner handle to resize it.
5. Select **Start opptak**. Recording starts after a three-second countdown.
6. Pause, resume or stop using the floating panel or menu-bar controls. The facecam can move during a screen + camera recording.
7. Select **Stopp og lagre** (Stop and save). Your finished video appears in the library.

The controls are excluded from the recording, while the facecam is composited into the video itself. Paused time is removed from both the audio and video timeline. Live preview does not save a recording.

| Shortcut | Action |
| :--- | :--- |
| `⌘N` | New recording setup |
| `⇧⌘R` | Start recording |
| `⇧⌘P` | Pause / resume |
| `⇧⌘S` | Stop and save |

Shortcuts work while Lewtech Record is active. Use the floating panel or menu bar when working in another app.

## Permissions & privacy

macOS requests **Screen Recording**, **Camera** and **Microphone** access when the corresponding features are used. Manage these in **System Settings → Privacy & Security**. The app's settings also link to these panels.

- Recordings stay in `~/Movies/Lewtech Record/` by default.
- Library metadata and unfinished recording fragments also stay on your Mac.
- The app has no built-in account system, analytics service or automatic upload.
- Exporting saves a copy to a location you choose. Sharing that file is up to you.

A permission change may require quitting and reopening the app. Open it through Finder so macOS attributes permission requests to Lewtech Record.

## Library & files

Search, sort, rename and play recordings in the library. **Vis i Finder** reveals a video; **Eksporter MP4** saves a copy elsewhere. Deleting a recording moves it to the macOS Trash.

| Property | Output |
| :--- | :--- |
| Container | MP4 |
| Video | H.264, targeting 30 fps |
| Audio | AAC when microphone recording is enabled |
| Size | Source-scaled, capped at 1920 × 1080 |
| Duration | No built-in time limit; disk space and hardware are practical limits |

Small windows and different source aspect ratios can produce smaller dimensions. Interrupted recordings are inspected on startup: playable files may be recovered, while other fragments remain in the library's `.incomplete` directory. Recovery after a crash or interruption is not guaranteed.

**Uninstall:** quit the app and remove the app bundle. Your videos remain in `~/Movies/Lewtech Record/`; remove that folder only if you also want to delete your library. Installer backups can be removed separately.

## Troubleshooting

<details>
<summary><strong>Screen permission is enabled, but capture is denied</strong></summary>

An ad-hoc signed rebuild can have a new code signature while macOS retains the old permission. First quit and reopen the app and check its Screen Recording permission. If the problem persists, quit Lewtech Record and reset only its screen permission:

```sh
tccutil reset ScreenCapture no.lewtech.record
```

Open the installed app from Finder and grant access again. This does not delete recordings. Stable Developer ID signing is needed for a smoother distributed-update experience.

</details>

<details>
<summary><strong>A camera, microphone or window is missing</strong></summary>

Use **Oppdater enheter** (Refresh devices), reconnect the device and check the relevant macOS permission. Window discovery requires screen access. If a selected window closes, choose a new source explicitly.

</details>

<details>
<summary><strong>A recording was interrupted or will not save</strong></summary>

Check free disk space and whether the selected devices are still connected. Reopen the app to let it inspect interrupted recordings. Preserve the `.incomplete` folder if you need to investigate a failed recording; some fragments may not be recoverable. See [SUPPORT.md](SUPPORT.md) for a useful, privacy-conscious bug report.

</details>

<details>
<summary><strong>The build cannot find an SDK or compiler</strong></summary>

Check `xcode-select -p`, `swift --version` and `xcrun --sdk macosx --show-sdk-version`. Install or update Apple's Command Line Tools / Xcode to include the macOS 15 SDK or newer. `swift build` alone creates an executable; use the supplied build script to create the complete `.app` bundle with its resources and permission descriptions.

</details>

## Build, verify & package

```sh
./scripts/build.sh     # dist/Lewtech Record.app
./scripts/verify.sh    # timeline, library and synthetic media checks
./scripts/package.sh   # app ZIP and SHA-256 checksum in dist/
```

The verification script compiles its own test harness and exits with an error when a check fails; `swift test` is not the test entry point. Run media checks in a normal macOS environment with access to Apple's codec services. A restricted process sandbox can prevent codec tests from running.

See **[development and release notes](docs/DEVELOPMENT.md)** for architecture, manual checks and publishing steps. Automated tests do not replace testing real cameras, microphones, permissions or long recordings.

## Contributing & support

Issues and pull requests are welcome. Read **[CONTRIBUTING.md](CONTRIBUTING.md)** before starting a change. Use **[SUPPORT.md](SUPPORT.md)** for troubleshooting and bug reports, and **[SECURITY.md](SECURITY.md)** for sensitive reports.

## Credits

Created by **Leander Wachendorf** · [GitHub](https://github.com/lewadorf) · [Lewtech](https://lewtech.no/)

The interface uses Lewtech's visual identity and the **Manrope** typeface. Manrope is distributed under the SIL Open Font License 1.1; its [copyright and license](Sources/LewtechRecord/Resources/Manrope-LICENSE.txt) are included. [Asset provenance](docs/ASSETS.md) documents the illustrations and brand resources.

## License & attribution

**[Apache License 2.0](LICENSE)** · Copyright © 2026 **Leander Wachendorf**.

You may use, modify and redistribute this project, including commercially and in closed-source products, subject to the license. When redistributing, include the license, preserve applicable copyright and attribution notices, mark modified files, and carry forward the relevant notices in **[NOTICE](NOTICE)** as required by Section 4.

Suggested credit:

> Lewtech Record — created by Leander Wachendorf. Licensed under Apache-2.0.

The license does not require a permanent on-screen credit or attribution in videos you create with the app. It does not grant rights to use Lewtech trademarks to imply endorsement. Manrope remains under its separate SIL Open Font License; see [third-party notices](THIRD_PARTY_NOTICES.md). The full license text governs.
