# Linkpad (placeholder name)

An MIT-licensed, local-first device connectivity experiment inspired by KDE Connect and Unified Remote. No accounts or cloud service. This is a first working vertical slice, not a production-ready replacement.

## Implemented

- Go peer identity persisted as an ECDSA P-256 self-signed certificate; TLS 1.3 WebSocket connections and explicit addresses.
- Mutual TLS proof of identity, mandatory controller-side server fingerprint verification, a single-use 256-bit pairing secret with a two-minute window, persistent desktop trust, reconnect and capability negotiation.
- An in-process plugin interface and registry. Pointer plugin available only when opted in and supported by the host.
- Native macOS cursor movement and left/right click through CoreGraphics, gated by Accessibility permission. Linux X11 input uses a pure-Go authenticated XTEST connection for relative movement, clicks, wheel scrolling and arrow keys. Windows input uses SendInput in an interactive desktop session; see [Windows input](docs/windows-input.md). macOS builds without cgo remain unavailable stubs.
- Flutter Android/iOS controller in `mobile/`, with shared pairing, certificate pinning, touchpad and foreground-only sessions. Flutter uses a software EC identity protected by platform secure storage.
- Go integration/security tests, Flutter controller tests, protocol JSON Schema, CI and build instructions.

## Pair by scanning a QR code

Start the desktop agent with a reachable LAN listener and a new pairing window:

```sh
# macOS
./bin/linkpad -listen 0.0.0.0:4747 -pair -allow-pointer
# Linux X11: run from a terminal in your desktop session
./linkpad-linux-x86_64 -listen 0.0.0.0:4747 -pair -allow-pointer
```

In the Flutter phone app, tap **Scan QR to pair**, allow camera access, and scan the code shown directly on your computer. The app fills the connection details and pairs automatically. The QR is single-use and expires in two minutes. To show the scanner when already connected, tap **Disconnect** first. After pairing, reconnects use the saved identity without scanning again.

Use `-pair-qr /path/to/new-pairing.png` to also create a private PNG if your terminal cannot display the code cleanly; the path must not already exist. Use `-advertise wss://YOUR-LAN-IP:4747/ws` if the server selects the wrong network interface. Both devices must be able to reach the advertised address. Manual pairing remains available. See [protocol/pairing.md](protocol/pairing.md) for the payload and trust model.

## Desktop: build and run

For the Flutter desktop server app (QR pairing, live phone list, tray controls,
and start at login), see [DESKTOP.md](DESKTOP.md). The terminal server below
remains available. Run one of them at a time on port 4747.

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

## Mobile: build and run

The `mobile/` Flutter project is the maintained Android and iOS controller. See [mobile/README.md](mobile/README.md) for setup, platform requirements and secure-storage details. The original standalone Kotlin Android client has been retired; `mobile/android/` remains required for Flutter Android builds.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

For an Android APK, run `flutter build apk --release` from `mobile/`. iOS builds require full Xcode and appropriate signing. Pair with the desktop on the same reachable LAN using the app's QR scanner or manual pairing details.

## Linux X11 desktop control

The Linux x86_64 executable supports mouse movement, left/right click, two-finger wheel scrolling, D-pad arrow keys, and keyboard text/shortcuts through the XTEST extension. It is statically linked and does not require `xdotool`, root, `/dev/uinput`, or disabling X server access control. Keyboard characters must be available in the active X11 keyboard layout.

The mobile Control deck keeps a full touchpad above click and arrow controls. Tap **Keyboard** to open the QWERTY keyboard beneath a smaller touchpad. Shift, Ctrl, Alt, and Super apply to the next key only; Super maps to Command on macOS. **Gestures** shows the touch controls. The app follows the phone's light/dark appearance, and manual pairing details are under **Enter pairing details**. Update the desktop server as well as the phone app to enable the negotiated `keyboard.v1` capability; older servers still support the existing pointer and arrow controls.

Run from a terminal inside the logged-in X11 desktop session, as that same user:

```sh
echo "$XDG_SESSION_TYPE"  # should say x11
./linkpad-linux-x86_64 -listen 0.0.0.0:4747 -allow-pointer
```

For first-time enrollment, also add `-pair`. `DISPLAY` and, when required by the desktop, `XAUTHORITY` are inherited from that session. A headless SSH shell without those credentials cannot control the desktop. The startup log explains missing DISPLAY, X11 authorization failures or a missing XTEST extension. Correct the environment and restart the server if input is unavailable. Pairing still works without input support.

X11 core wheel events use discrete notches: small touch deltas accumulate until 40 pixels, then emit a complete wheel press/release. Leftover scroll is discarded after 150 ms of inactivity. This provides natural-direction scrolling, but not macOS-style pixel scrolling or momentum. Wayland and headless console control remain unsupported.

## Repository map

- `cmd/linkpad`: executable, listen/connect modes and permissions.
- `internal/identity`: identity creation and exact TLS pinning.
- `internal/node`: WebSocket sessions, pairing and trust persistence.
- `internal/protocol`, `protocol/`: wire types, schema and specification.
- `internal/plugins`, `internal/pointer`: modular capability interface and native/stub backend.
- `mobile/`: shared Flutter Android/iOS controller and TLS integration tests.
- `.github/workflows/ci.yml`: Go race tests/vet, cross-platform stub builds, and macOS native build. Flutter Android/iOS checks live in `.github/workflows/flutter.yml`.

## Locally built artifacts

Desktop installers are built under `bin/releases/`. Flutter Android APKs are built under `mobile/build/app/outputs/flutter-apk/`. Build outputs are ignored by Git; use the platform build instructions above.

## Incomplete / limits

Explicit address only: no mDNS/discovery, background mobile service, file sharing, clipboard, notification sync, remote screen or internet relay. Android currently only controls, not receives. The Go process can act as either peer but does not provide a tray UI or multiplex bidirectional plugin families. Pointer authorization is global for all paired peers; per-device permissions, live revocation, audit UI, handshake admission limits and global event quotas remain work. Plugin modules are compiled into the agent; no third-party package loader or sandbox exists. A compromised paired device can operate the pointer while that capability is enabled. Local key storage uses OS file permissions on desktop, not a hardware keystore. Run a single agent process per state directory; trust files are not multi-process coordinated. This is not security audited.

See [VALIDATION.md](VALIDATION.md) for checks actually run and hardware verification still needed. Do not treat configured CI as a completed remote run.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [protocol/README.md](protocol/README.md). Branding and hosting are undecided; Linkpad and the module/application IDs are provisional.
