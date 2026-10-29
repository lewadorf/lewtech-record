# Contributing to Lewtech Record

Thank you for helping improve a small, local-first Mac recording app.

## Start here

For a bug, include macOS version, processor, recording mode, devices, reproduction steps, expected behavior and what happened. Check existing issues first. For a larger feature or design change, open an issue to agree on scope before implementing it.

## Make a change

1. Fork the repository and create a focused branch.
2. Build with `./scripts/build.sh` on macOS 15 or newer.
3. Run `./scripts/verify.sh` for changes to recording, media timing or persistence.
4. Test affected UI and real devices manually. Describe what you could and could not test.
5. Open a pull request with the problem, resulting behavior and validation performed.

Keep the app local-first. Preserve the warm Lewtech palette, accessibility labels and readable contrast. Avoid adding runtime dependencies or network services without discussing the need first.

For documentation-only changes, check links, commands and image rendering; a full media test run is unnecessary. For bug fixes, add a regression test when it can meaningfully reproduce the failure.

## Respect privacy and ownership

Do not commit personal recordings, library metadata, credentials, crash reports containing private paths or signing certificates. Use synthetic examples. Only contribute work you have the right to share, retain applicable copyright notices, and include licenses for any new dependencies or assets.

Be constructive and respectful in issues and reviews. See [SUPPORT.md](SUPPORT.md) for support and [SECURITY.md](SECURITY.md) for sensitive reports.

## License

Contributions intentionally submitted for inclusion in this project are provided under Apache-2.0, unless explicitly stated otherwise, as described in Section 5 of [LICENSE](LICENSE). Preserve applicable attribution and third-party notices.
