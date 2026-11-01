# Linkpad

Use your phone as a touchpad, keyboard and remote for your computer.

Linkpad connects an Android phone or iPhone to a Mac, Windows or Linux computer over your local network. No account or cloud service is required. The mobile controller and desktop app share a Flutter codebase; a bundled Go server handles pairing and native input.

## Downloads

Get desktop installers from the [latest GitHub Release](https://github.com/shirishkoirala/linkpad/releases/latest). Older builds remain available on the [Releases page](https://github.com/shirishkoirala/linkpad/releases).

| Platform | Installer | Requirements |
| --- | --- | --- |
| macOS | `Linkpad-<version>-macos-local.dmg` or signed `macos.dmg` | Accessibility permission for input control |
| Windows | `Linkpad-<version>-windows-x86_64-setup.exe` | 64-bit Intel/AMD Windows with an unlocked desktop session |
| Linux | `linkpad_<version>_amd64.deb` | Ubuntu 24.04 / Linux Mint 22-compatible x86_64 system using X11 |

The `amd64` Linux package works on both Intel and AMD 64-bit processors. ARM Linux packages are not currently built.

Current `macos-local` DMGs are ad-hoc signed and **not notarized**. The Windows installer is currently **unsigned**, so Windows may show a publisher or SmartScreen warning. Download only from the project releases; do not disable operating-system security protections. SHA-256 files accompany each installer to check download integrity.

Android and iOS controllers are prepared for Google Play and the App Store. For mobile availability, installation help and desktop setup, visit [Linkpad Support](https://shirishkoirala.com/linkpad-support/).

## Get connected

1. Install and open the desktop app. Quit any older Linkpad app or terminal server first.
2. Connect your phone and computer to the same reachable local network. The computer can use Ethernet while the phone uses Wi-Fi.
3. Complete the desktop setup and enable input control as prompted.
4. Open **Computers** on your phone, select the nearby computer and scan its pairing QR code. You can also enter pairing details manually.
5. Use **Touchpad**, **Remote** or **Keyboard** to control the computer.

Allow camera access for QR scanning and Local Network access on iOS. Pairing codes are single-use and expire after two minutes. Keep both devices' clocks correct; an incorrect clock can make a fresh code appear expired.

Saved computers reconnect without another QR scan. Local discovery can recover a paired computer's address after its IP changes, while still verifying the saved certificate identity. Discovery does not grant access to an unpaired device.

### Desktop permissions

- **macOS:** enable Linkpad under **System Settings → Privacy & Security → Accessibility**. Restart Linkpad if access remains unavailable after changing permission; the app provides a restart prompt when needed.
- **Windows:** run Linkpad in your logged-in desktop session. Allow access on your **Private** network if Windows Firewall asks. Lock screens and UAC secure desktops cannot be controlled; standard-permission Linkpad cannot control administrator apps.
- **Linux:** use an **X11/Xorg** desktop session and launch Linkpad as your normal desktop user. Wayland and headless console input are not supported. Terminal launches need the desktop session's `DISPLAY` and, where required, `XAUTHORITY`.

The desktop server listens on TCP **4747**. Guest Wi-Fi, client isolation, firewalls or blocked multicast can prevent connection or discovery. Manual pairing remains available when discovery is blocked.

## Controls

- **Touchpad:** relative cursor movement, tap to click, two-finger tap for right-click, and two-finger scrolling. Hold the left-click control while moving to drag windows or select items.
- **Keyboard:** text input, navigation keys and shortcuts with Ctrl, Alt, Shift and Windows/Command. Windows text input supports Unicode; Linux characters must be available in the active X11 keyboard layout.
- **Remote:** directional pad, Enter, navigation shortcuts and volume down/mute/up on supported desktop sessions.
- **Settings:** cursor sensitivity, optional keep-screen-awake behavior and remembered control tabs.
- **Computers:** saved computers, nearby discovery and switching between paired computers.

The desktop app includes QR pairing, connected-device management, tray/menu-bar controls and optional start-at-login. Closing the window keeps the server running when the tray is available; use **Quit Linkpad** to stop it. Installation does not enable start-at-login automatically.

Linkpad sends input commands; it does **not** stream the computer's screen. Internet relay, clipboard sync, file transfer and notification mirroring are not implemented. Mobile control sessions pause while the app is inactive. Linux scrolling uses wheel events rather than macOS-style pixel scrolling.

## Privacy and pairing

Connections use TLS 1.3 with mutual certificate authentication. Initial pairing verifies the desktop certificate fingerprint and a short-lived secret; subsequent connections verify the saved identity. Private identities and saved pairing information remain on the user's devices. The mobile app uses platform secure storage for its private authentication material.

Keep QR codes, pairing secrets and private keys private. Removing or replacing a desktop identity requires pairing again. Review the [privacy policy](https://shirishkoirala.com/linkpad-privacy/), [security notes](SECURITY.md) and [pairing protocol](protocol/pairing.md) for more detail.

## Build from source

Use the Go version specified in [go.mod](go.mod) and Flutter **3.47.7**, matching CI. Install the platform build tools: Xcode for Apple platforms, Android SDK and a compatible JDK for Android, Visual Studio's C++ desktop workload for Windows, or GTK/CMake/Ninja development packages for Linux. See [PACKAGING.md](PACKAGING.md) for desktop dependencies and installer tooling.

### Flutter apps

```sh
cd mobile
flutter pub get
flutter analyze
flutter test --concurrency=1
```

Build the target you need from `mobile/`:

```sh
flutter build macos --release
flutter build windows --release
flutter build linux --release
flutter build appbundle --release
flutter build ipa --release
```

Run each build on its supported host platform. Desktop builds bundle the Go helper automatically. Google Play and App Store uploads require the appropriate release signing; a successful local build alone does not establish store readiness.

### Command-line desktop server

The terminal server remains available alongside the graphical app:

```sh
go test -race ./...
go vet ./...
go build -o bin/linkpad ./cmd/linkpad
./bin/linkpad -listen 0.0.0.0:4747 -pair -allow-pointer
```

On Windows:

```powershell
go build -o linkpad-windows-x86_64.exe ./cmd/linkpad
.\linkpad-windows-x86_64.exe -listen 0.0.0.0:4747 -pair -allow-pointer
```

Only run one server on the same port. The default CLI listener is loopback; a phone needs a reachable LAN listener. Use `-advertise wss://YOUR-LAN-IP:4747/ws` if the automatically selected address is unsuitable. `-pair-qr PATH` saves a private QR PNG to a new file. `-state PATH` selects a separate server state directory; do not share or commit its private key.

## Release pipeline

[Desktop release](.github/workflows/desktop-release.yml) builds macOS, Linux x86_64 and Windows x86_64 installers on native GitHub runners. It runs Go race tests/vet, Flutter analysis/tests and an installed Windows GUI/helper smoke test. The Windows input backend also has a native CI smoke test.

To create a release:

1. Set `mobile/pubspec.yaml` to the intended version, for example `0.1.1+2`, then commit and push it.
2. Create and push the matching tag, for example `v0.1.1`. Omit the `+build` suffix from the tag.
3. Actions builds the installers, verifies checksums and creates a **draft GitHub Release**.
4. Review the artifacts and notes, complete physical installation checks, then publish the draft.

Manual runs from **Actions → Desktop release → Run workflow** produce artifacts by default. Select **Create/update a draft release** when wanted. A published release cannot be overwritten, and an existing draft from another commit must be removed or replaced with a new version before retrying. Keep a correctly created tag when removing an obsolete draft.

See [PACKAGING.md](PACKAGING.md) for artifact locations, signing/notarization secrets and local packaging. Public Mac signing/notarization and Windows code signing remain separate release requirements.

## Project and testing

| Path | Purpose |
| --- | --- |
| `mobile/` | Flutter mobile controllers and desktop apps |
| `cmd/linkpad/` | Go server and command-line controller |
| `internal/pointer/` | macOS CoreGraphics, Windows SendInput and Linux XTEST input backends |
| `internal/node/` | Sessions, pairing, trusted devices and input coordination |
| `internal/identity/` | Private identities and TLS certificate pinning |
| `protocol/` | Message schemas and capability specifications |
| `assets/release/` | Store descriptions, promotional graphics and screenshot assets |
| `.github/workflows/` | Automated tests, builds and desktop release workflow |

See [VALIDATION.md](VALIDATION.md) for test history, [Windows input](docs/windows-input.md) for native and Docker/Wine test details, and the [release plan](docs/release-plan.md) for outstanding work. Docker checks do not replace physical desktop testing.

## Support and contributing

- [Setup and support](https://shirishkoirala.com/linkpad-support/)
- [Report an issue](https://github.com/shirishkoirala/linkpad/issues)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

Linkpad is available under the [MIT License](LICENSE).
