# Validation record — 14 October 2026

1 November 2026 update: the maintainer reported successful physical Windows testing of the command-line server's controls. An incorrect system clock initially caused pairing-code expiry; correcting the clock fixed pairing. Windows GUI and installer validation are separate work.

Historical results below describe their original test dates. For current Windows backend verification, see [Windows input](docs/windows-input.md). As of 1 November 2026, portable Go race tests and Windows cross-builds pass; Linux Docker also passes the Go suite. Wine-native execution on the Apple Silicon host is blocked by a Rosetta GDT error before tests run. The new Windows CI smoke test is configured but has not been run remotely yet. Physical Windows validation and GUI/installer packaging remain pending.

Local environment: macOS arm64, Go 1.26.5, JDK 17, Android SDK 35.

## Passed

- `go test -race ./...`: persistent identity, private key permissions, wrong server pin rejection, mutual TLS client-certificate requirement, unpaired-device denial, bad/expired/single-use pairing tokens, concurrent token consumption, failed persistence, persisted trust, negotiated capability dispatch, malformed/version-mismatched messages, oversized frames, denied browser Origin and pointer bounds. Pointer integration uses a fake backend; it does not inject input into the developer machine.
- `go vet ./...`.
- Native macOS/cgo executable build: `go build -o bin/linkpad ./cmd/linkpad`.
- No-cgo cross-builds for linux/amd64, windows/amd64 and darwin/amd64. These use the explicitly unavailable pointer stub.
- Built executable smoke test: first enrollment, a second invocation reconnecting from the same persisted identity and wrong-pin rejection over real localhost TLS/WebSocket. No mouse input performed.

## Original native Android client (historical)

The standalone `android/` project was retired on 30 October 2026. The following records describe that original implementation, not the maintained Flutter app in `mobile/`.

### Android passed

- Official Gradle 8.13 wrapper distribution with official SHA-256 checksum pinned.
- A single clean build completed successfully: `./gradlew clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`, using JDK 17 and SDK 35.
- Three Android protocol unit tests passed with zero failures/errors.
- Lint completed with zero errors and eight warnings: custom pinning trust manager (intentional, validates exact certificate fingerprint and expiry), data extraction rules, dependency upgrades, placeholder app icon, redundant SDK guard, target SDK upgrade and SharedPreferences KTX convenience. These warnings are not suppressed. Target SDK 35 is chosen for this development slice; publishing requirements and branding will be addressed before a release.
- Debug APK generated and copied to `bin/linkpad-debug.apk`. Install from the project root with `adb install -r bin/linkpad-debug.apk`. Desktop executable is `bin/linkpad` (built locally for macOS arm64).

The first two overlapping Android build attempts conflicted over generated resource files. They were discarded; the final clean build above ran alone and passed.

## Not verified / incomplete

- Physical Android-to-macOS pairing and pointer interaction; Android Keystore/TLS interoperability on a real device.
- Actual macOS Accessibility permission flow, cursor movement and click behavior on hardware. Native code compiles, but input injection has not been performed.
- Windows/Linux runtime input support: stubs only, not implemented.
- GitHub Actions execution: workflow is provided, no remote repository has been published.
- Independent security review, multi-peer load/denial-of-service behavior or certificate renewal.

See README for the full feature limits.

## Linux X11 backend — 15 October 2026

Added pure-Go XTEST input support for Linux, including static/no-cgo builds. Portable race tests cover relative-motion mode, movement bounds, ordered complete clicks, natural wheel directions, accumulation/expiry, arrow key lookup, release attempts after errors, and concurrent input serialization. A Linux-only opt-in integration test verifies actual cursor coordinates, button/wheel delivery and balanced arrow keys under Xvfb; ordinary test runs do not inject input into a real desktop. CI includes an isolated Xvfb job. Physical Linux hardware verification remains pending.

The Linux amd64 test executable ran successfully in a disposable Debian container under Xvfb. The integration test confirmed two relative moves ended at the expected cursor coordinates, left/right clicks and both wheel axes reached an X11 window, arrow press/release pairs were balanced, and no mouse buttons remained held. Portable event tests also passed there. `go test -race ./...` and `go vet ./...` passed on macOS. Linux, Windows and macOS no-cgo cross-builds succeeded.
