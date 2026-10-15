# Linkpad (placeholder name)

An MIT-licensed, local-first device connectivity experiment inspired by KDE Connect and Unified Remote. No accounts or cloud service. This is a first working vertical slice, not a production-ready replacement.

## Implemented

- Go peer identity persisted as an ECDSA P-256 self-signed certificate; TLS 1.3 WebSocket connections and explicit addresses.
- Mutual TLS proof of identity, mandatory controller-side server fingerprint verification, a single-use 256-bit pairing secret with a two-minute window, persistent desktop trust, reconnect and capability negotiation.
- An in-process plugin interface and registry. Pointer plugin available only when opted in and supported by the host.
- Native macOS cursor movement and left/right click through CoreGraphics, gated by Accessibility permission. Windows/Linux and builds without cgo are explicit unavailable stubs and do not advertise pointer support.
- Kotlin/Compose Android touchpad, first-time pairing and reconnect, Android Keystore EC identity, exact desktop certificate pin, connection status and foreground-only sessions.
- Flutter Android/iOS controller in `mobile/`, with shared pairing, certificate pinning, touchpad and foreground-only sessions. Flutter uses a software EC identity protected by platform secure storage; physical iPhone validation remains pending.
- Go integration/security tests, Android protocol unit tests, protocol JSON Schema, CI and build instructions.

## Desktop: build and run

Requirements: Go 1.26+, macOS Xcode Command Line Tools for the native backend. Module path `example.org/linkpad` is a placeholder; no repository or release has been published. Initial dependency downloads need internet; runtime requires only a reachable local network.

```sh
go test -race ./...
go vet ./...
go build -o bin/linkpad ./cmd/linkpad
./bin/linkpad -listen 192.168.1.10:4747 -pair -allow-pointer
```

Use your desktop LAN address; the default listen address is loopback. Allow inbound TCP 4747 in your firewall. Grant the executable/launching terminal Accessibility access in **System Settings → Privacy & Security → Accessibility**, then restart. The startup message reports if the backend is unavailable. Pairing still works without pointer permission.

The terminal prints a device fingerprint and one pairing secret. Verify the fingerprint directly on the desktop, then enter both in Android. Do not obtain the fingerprint from the same untrusted network connection you are trying to authenticate. Keep the terminal secret private; whoever possesses it and a matching server pin during the window can enroll a device.

The state directory defaults to the user configuration folder (`~/Library/Application Support/linkpad` on macOS). Override it with `-state`. Keep it private: `identity.pem` contains the private key, `peers.json` lists trusted certificate fingerprints. Stop the node before editing trust; remove a peer fingerprint from `peers.json` and restart to revoke it. Revocation is not live. Losing/deleting a client identity requires pairing again. Deleting the desktop identity changes its pin and requires all clients to verify and pair again. Certificates expire after ten years; rotation is not implemented.

### Two desktop peers / smoke test

No mouse movement is performed by pairing alone. The second peer uses a separate persistent state directory:

```sh
# Terminal 1 (use -allow-pointer only when testing actual input)
./bin/linkpad -state .state-server -listen 127.0.0.1:4747 -pair
# Terminal 2: copy the fingerprint and secret from terminal 1
read -r LINKPAD_PAIR_TOKEN
export LINKPAD_PAIR_TOKEN
./bin/linkpad -state .state-controller -connect wss://127.0.0.1:4747/ws -pin <desktop-fingerprint>
unset LINKPAD_PAIR_TOKEN
# Reconnect after enrollment; no pairing secret needed
./bin/linkpad -state .state-controller -connect wss://127.0.0.1:4747/ws -pin <desktop-fingerprint>
```

For a receiver started with an available `-allow-pointer` backend, add `-dx 20 -dy 10` or `-click left` to the controller command. The CLI exits after negotiating/sending one action. Each invocation is a new authenticated connection.

## Android: build and run

### Shared Flutter client (Android and iOS)

The new `mobile/` Flutter project shares the controller UI, pairing and touchpad code across Android and iOS. See [mobile/README.md](mobile/README.md) for setup, platform requirements and the secure-storage tradeoff. Run `flutter pub get` and `flutter run` from `mobile/`. The existing Kotlin Android client below remains available during migration. The Flutter iOS target requires a full Xcode installation and hardware verification.

Requirements: JDK 17, Android SDK platform 35, network access for Gradle dependencies. A real device or emulator running **Android 10/API 29+** is required by this slice's TLS 1.3 connection code (minSdk 29).

```sh
cd android
# Set ANDROID_HOME to your installed SDK, or create ignored local.properties with sdk.dir=...
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

On the same reachable LAN, enter `wss://DESKTOP-LAN-IP:4747/ws`, the verified 64-character fingerprint, and the first-time secret. Tap **Connect / pair**. A successful handshake saves address/pin in app-private preferences and clears the secret. The non-exportable identity remains in Android Keystore. Subsequent connections use no secret. For the Android emulator, `10.0.2.2` routes to the host; ensure the node listens on a reachable interface. No cleartext transport is supported. Drag the pad to move; click buttons emit complete clicks. Movement is approximate and intentionally drops samples under backpressure.

## Repository map

- `cmd/linkpad`: executable, listen/connect modes and permissions.
- `internal/identity`: identity creation and exact TLS pinning.
- `internal/node`: WebSocket sessions, pairing and trust persistence.
- `internal/protocol`, `protocol/`: wire types, schema and specification.
- `internal/plugins`, `internal/pointer`: modular capability interface and native/stub backend.
- `android/`: native Kotlin/Compose controller.
- `mobile/`: shared Flutter Android/iOS controller and TLS integration tests.
- `.github/workflows/ci.yml`: Go race tests/vet, cross-platform stub builds, macOS native build and Android build/tests/lint.

## Locally built artifacts

`bin/linkpad` is the macOS arm64 executable; `bin/linkpad-debug.apk` is the installable Android development APK. These are ignored by Git. To install the included APK from the project root, run `adb install -r bin/linkpad-debug.apk`. Rebuild for your platform using the commands above.

## Incomplete / limits

Explicit address only: no mDNS/discovery, QR enrollment, background mobile service, file sharing, clipboard, notification sync, remote screen or internet relay. Android currently only controls, not receives. The Go process can act as either peer but does not provide a tray UI or multiplex bidirectional plugin families. Pointer authorization is global for all paired peers; per-device permissions, live revocation, audit UI, handshake admission limits and global event quotas remain work. Plugin modules are compiled into the agent; no third-party package loader or sandbox exists. A compromised paired device can operate the pointer while that capability is enabled. Local key storage uses OS file permissions on desktop, not a hardware keystore. Run a single agent process per state directory; trust files are not multi-process coordinated. This is not security audited.

See [VALIDATION.md](VALIDATION.md) for checks actually run and hardware verification still needed. Do not treat configured CI as a completed remote run.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [protocol/README.md](protocol/README.md). Branding and hosting are undecided; Linkpad and the module/application IDs are provisional.
