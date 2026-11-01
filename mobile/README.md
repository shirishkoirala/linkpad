# Linkpad Flutter apps

This project contains the Android/iOS controllers and the macOS, Windows and Linux desktop apps. The standalone Kotlin Android client has been retired. The `android/` folder here is Flutter's required Android platform target, not a second app.

See the [main README](../README.md) for downloads and setup, [desktop packaging](../PACKAGING.md) for installers, and [current validation](../VALIDATION.md) for verification records.

## Development

Use Flutter 3.47.7, matching CI, and the Go version in `../go.mod` for desktop helper builds. Install the native build tools for your target platform.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run
```

Android requires API 29 or later. iOS development requires full Xcode and an appropriate signing team. The iOS deployment target is configured in the Xcode project; do not infer compatibility from older validation logs.

## Mobile connection flow

The app opens the Computers chooser. Pair a nearby computer with its QR code, or enter pairing details manually. Saved computers reconnect without another secret; only one computer is controlled at a time. Local discovery can find new servers and recover a saved server after its IP address changes, while preserving certificate verification. See [saved computers](COMPUTERS.md).

Control sessions are foreground-only. Backgrounding or disconnecting clears pending input. Automatic recovery retries transient failures with bounded backoff; manual disconnect stops recovery. Changed certificates and rejected trust require attention rather than silently accepting a new identity.

The input pipeline allows up to four plain movements in flight; clicks, keyboard, volume and dragging respect ordered acknowledgement barriers. Stale input expires, and adaptive stall detection pauses controls before reconnecting. See [input timing and diagnostics](INPUT-LATENCY.md) for the current limits rather than duplicating them here.

## Identity and storage

The client creates an EC certificate and stores private credentials using platform secure storage. It requires TLS 1.3, verifies the exact desktop certificate SHA-256 fingerprint and checks certificate dates. This is a software private key loaded into Dart memory; it is not a hardware-backed signing key.

Pairing secrets are single-use, expire after two minutes and are not saved. Both device clocks must be correct. Loss of a private identity requires pairing again; secure-storage and backup retention varies by platform. Automatic certificate renewal is not implemented.

## Builds

```sh
flutter build apk --release
flutter build appbundle --release
flutter build ipa --release
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Build on the target's supported host. Android release signing is managed manually by the maintainer. iOS distribution requires Apple signing. Desktop builds bundle the Go helper automatically; packaging/signing instructions are in [PACKAGING.md](../PACKAGING.md). No release build alone establishes store or signing readiness.
