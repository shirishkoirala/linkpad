# Linkpad desktop app

For Mac DMG and Linux Debian installers, see [PACKAGING.md](PACKAGING.md).

The Flutter project in `mobile/` now has desktop server screens for macOS and
Linux. Android and iOS continue to open the mobile controller. The desktop app
bundles the existing Go server; users do not need Go or a terminal to run a built
application.

## Use

1. Open **Linkpad**. It starts a LAN listener on TCP 4747.
2. Choose **Create pairing code**, then scan it from Linkpad on your phone.
   Keep the phone and computer on the same reachable network.
3. A code is single-use and expires after two minutes. **Cancel pairing** closes
   enrollment immediately. Creating another code replaces the previous one.
4. **Your phones** shows live connection status. Its menu can rename a phone or
   revoke its access. Revocation disconnects all sessions for that identity and
   removes its trust on disk. The phone must pair again afterward.

On macOS, enable Linkpad in **System Settings → Privacy & Security →
Accessibility**, then choose **Restart server** in the app. macOS may identify the
bundled `linkpad-server` helper or its responsible application in the permission
list. Input permissions are checked at server startup; pairing works without
input access. Rebuilding or moving an ad-hoc signed app can require granting
permission again. For regular use, keep the app in a stable location such as
Applications.

Linux input requires a logged-in **X11** desktop session. Open Linkpad from that
session so it inherits `DISPLAY` and `XAUTHORITY`. Wayland and the login screen
are unsupported. The permission panel shows the Go backend's actual diagnostic.

Close the window to keep the server in the tray/menu bar. **Open Linkpad** brings
it back; **Quit Linkpad** stops the server and releases held input. If tray
initialization fails, closing quits instead. Some GNOME installations need an
AppIndicator extension to display tray icons; reopening Linkpad from the launcher
also restores the existing Linux window. Minimizing keeps the app running.

**Start at login** is opt-in and uses the operating system's login mechanism.
On Linux it creates `~/.config/autostart/Linkpad.desktop`; on macOS it registers
the app with login items using ServiceManagement (macOS 13+). Move/install the app to its permanent location before
enabling this. Do not also run the terminal server or a Linkpad systemd service
on port 4747. The app reports a conflict instead of taking over another process.
To replace the user service described in `LINUX-SERVICE.md`, stop and disable that
service first, then enable the desktop app's login setting.

For several network interfaces, **Use a different network address** generates
a code using an explicit `wss://LAN-IP:4747/ws` address. It does not change the
listener or firewall rules. **Copy diagnostics** includes recent backend errors,
but excludes pairing invitations and secrets.

## Build on macOS

Install Flutter, Go 1.26+, Xcode, and CocoaPods. From `mobile/`:

```sh
flutter pub get
flutter build macos --release
open build/macos/Build/Products/Release/Linkpad.app
```

The Xcode embed phase runs `tool/build_server.sh` before signing the app. It
compiles and signs `Contents/Resources/linkpad-server` with matching app
architectures. The app uses bundle ID `org.linkpad.desktop`, a separate identity
from the mobile controller. The macOS desktop target is intentionally outside
App Sandbox so the helper can use desktop input and the existing server state.
Public distribution still needs appropriate signing and notarization; the local
ad-hoc build is for development.

## Build on Linux x86_64

Build on Linux; Flutter cannot produce a Linux GUI bundle from macOS. Install
Flutter, Go 1.26+, and native build dependencies, for example on Ubuntu:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev
cd mobile
flutter pub get
flutter build linux --release
./build/linux/x64/release/bundle/linkpad_controller
```

CMake compiles the Go helper and installs it into the bundle's `lib/` directory.
Distribute the **whole bundle directory**. Keep it at a stable path for autostart.
This GUI bundle requires the listed system libraries and a graphical session;
it differs from the existing standalone, statically linked Go server download.

## Container validation on macOS or Linux

With Docker running, from the repository root:

```sh
python3 mobile/tool/test_linux_container.py
```

The helper stages only application sources in a temporary build context, builds
for `linux/amd64`, then runs Go's X11 integration tests against an isolated Xvfb
display, Flutter tests, linked-library checks, and a real GTK app startup/shutdown
smoke test. No host display, pairing state, or server port is mounted/published.
The first run downloads the pinned Flutter and Go SDK images.

Test logs and `Linkpad-Linux-x86_64-desktop.tar.gz` go in
`bin/linux-container-test/`. Extract the archive on Linux and run
`./linkpad_controller`; keep its `lib/` and `data/` folders alongside it.
The container's Ubuntu 24.04 base targets glibc 2.39 or newer and still requires
the desktop runtime libraries on the destination machine. A successful virtual
display test does not validate a physical machine's tray host, login mechanism,
firewall, or network reachability.

## State and lifecycle

The helper uses the same default private server state directory as the CLI:
`~/Library/Application Support/linkpad` on macOS, or the user configuration
directory's `linkpad` folder on Linux. Existing server identity and pairings carry
over. Run only one server per state directory. Phone display names are separate
Flutter application data and do not change certificate identities.

Flutter starts a child with `-desktop -listen 0.0.0.0:4747 -allow-pointer`. Commands
and status travel over private stdin/stdout pipes, with no network administration
API. Pairing secrets stay in memory. Closing the parent's pipe stops the listener
and releases active drags. Quit waits for graceful shutdown and escalates to
process termination only if the child fails to stop. A crashed helper is shown
as stopped and can be started again from the window or tray.

For development only, `LINKPAD_SERVER_BINARY=/absolute/path/to/linkpad` overrides
the bundled executable. It must be a build that supports `-desktop`.

## Validation

```sh
go test -race ./...
go vet ./...
go build -o bin/linkpad-desktop-test ./cmd/linkpad
cd mobile
flutter analyze
flutter test
LINKPAD_DESKTOP_TEST_BINARY="$PWD/../bin/linkpad-desktop-test" \
  flutter test test/server_controller_test.dart
```

Go integration tests exercise real TLS pairing, code rotation/cancellation,
active-session revocation, durable trust removal, and shutdown on parent EOF.
Flutter tests cover desktop enrollment, confirmation before revocation, minimum
window layout, and real helper lifecycle/port cleanup on an isolated test port.
The Go backend remains shared with the existing CLI and mobile protocol.

Verified locally on macOS: release build, deep signature verification, server startup, existing phone trust, QR generation, and reading login-item status. The iOS release build also passes.

Linux x86_64 container validation passes using Ubuntu 24.04, Flutter 3.44.0 / Dart 3.12.0, and Go 1.26.5: release GUI build, 68 Flutter tests, Go race tests including X11 input integration, static analysis, shared-library resolution, GTK startup with the bundled helper, and listener cleanup on parent termination. A physical Linux desktop still needs its own tray, login, and network checks.

Login-item registration was left disabled during validation. macOS input requires the user to grant Accessibility permission to the current signed build.
