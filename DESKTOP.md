# Linkpad desktop app

The shared Flutter app provides a graphical desktop server for macOS, Windows and Linux. It bundles the Go helper, so installed users do not need Go or a terminal. Get installers from [GitHub Releases](https://github.com/shirishkoirala/linkpad/releases/latest); see [PACKAGING.md](PACKAGING.md) for installer builds and signing requirements.

## Setup and use

1. Install and open Linkpad. Quit any older GUI, command-line server or system service using port 4747 first.
2. Complete **Enable control → Connect phone → Try it**. Keep both devices on the same reachable local network; Ethernet on the computer is supported.
3. Open Computers on the phone. Pair a nearby server by scanning the QR code displayed on the desktop, or enter verified pairing details manually.
4. Confirm input works. The final setup test uses received input and your confirmation; **Test later** defers it.

Codes are single-use and expire after two minutes. Cancelling or replacing an invitation invalidates it. Keep both clocks correct. Existing trusted phones can reconnect without new pairing codes and do not restart onboarding.

**Your phones** shows connection status. You can rename a phone, disconnect it or revoke its access. Revocation removes trust and disconnects its active sessions immediately; it must pair again afterward.

### macOS

Install into Applications before granting Accessibility access. A mounted DMG or translocated launch prompts you to move the app first.

Enable Linkpad under **System Settings → Privacy & Security → Accessibility**, then return to the app and choose **Check access** if needed. Linkpad refreshes helper capabilities when possible. If macOS needs a new application process, the recovery panel offers **Restart Linkpad**. Pairings are preserved. Replacing or moving an ad-hoc signed app can require granting permission again.

### Windows

Use the per-user x86_64 installer, then open Linkpad from the Start menu. The helper runs without a separate console window and communicates with the app over private pipes. Run in your normal logged-in desktop session.

Allow Linkpad on the Private network if Windows Firewall asks. The installer does not add firewall rules or require administrator access. Secure lock/UAC desktops cannot be controlled, and administrator apps may reject input from a standard-permission server. See [Windows input](docs/windows-input.md) for details and verification records.

### Linux

Use a logged-in **X11/Xorg** session. Launch the app from the application menu, or from a terminal with the correct `DISPLAY` and `XAUTHORITY`. Wayland and login-screen input are not supported. The permission panel shows actual backend diagnostics and recovery guidance.

The packaged x86_64 build targets Ubuntu 24.04 / Linux Mint 22-compatible systems. Other distributions need compatible runtime libraries or a source build.

## Tray and startup

Closing the window keeps the server running when a tray/menu-bar host is available. **Open Linkpad** restores the window; **Quit Linkpad** stops the helper and releases held input. If tray initialization fails, closing the window quits instead. Some Linux desktops require an AppIndicator extension; minimizing keeps the app running when no tray is available.

Start-at-login is optional. Install into a stable location before enabling it. Windows uses the current user's startup registration, macOS uses login items, and Linux uses an autostart desktop entry. Turn off start-at-login before uninstalling. Do not enable another Linkpad service on the same port; see [LINUX-SERVICE.md](LINUX-SERVICE.md) if migrating from a Linux service.

## Network discovery and pairing

The app starts a LAN listener on TCP 4747. Local advertisements use `_linkpad._tcp` with a public certificate fingerprint and listener port. Phones can list nearby servers or recover saved connections after an IP change, but must still verify the pinned certificate. Advertisements refresh when interfaces change and stop with the server.

Tap **Pair** on a nearby computer from the phone to request that the desktop reveal its QR code. Existing active codes are reused; requests are rate-limited and return no secret or access grant. This does not wake a sleeping PC or start a stopped server. Headless servers and older versions retain manual QR creation.

If automatic address selection chooses the wrong interface, **Use a different network address** creates a QR with an explicit `wss://LAN-IP:4747/ws` endpoint. It does not change the listener or firewall. Guest-network isolation or blocked multicast may require manual pairing details. Do not delete trusted identity merely because DHCP changed the address.

## Controls

Native backends provide cursor movement, complete clicks, leased dragging, scrolling, keyboard input, the standalone Windows/Command key and volume controls. Capabilities are negotiated; unsupported or older receivers leave the corresponding controls disabled. Hold volume up/down to repeat; repeats are skipped while the connection is busy, and mute is single-shot.

## Build and package

From `mobile/`, use the target's supported host:

```sh
flutter pub get
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Build only the relevant target on each machine. Native build tooling and Go are required. macOS bundles `Contents/Resources/linkpad-server`, Windows places `linkpad-server.exe` beside `Linkpad.exe`, and Linux places `linkpad-server` in the bundle's `lib/` directory. Distribute the complete bundle or use the installers described in [PACKAGING.md](PACKAGING.md).

For Linux container verification on a Mac or Linux Docker host, from the repository root:

```sh
python3 mobile/tool/test_linux_container.py
```

The tool stages source files into a temporary context, builds Linux x86_64, and runs isolated Xvfb input checks, Flutter tests and GTK helper lifecycle checks. It does not mount the host display or pairing state. Results go under `bin/linux-container-test/`; container results do not replace physical desktop testing.

## Helper lifecycle and state

The GUI starts its bundled helper with `-desktop -listen 0.0.0.0:4747 -allow-pointer`. Management commands and status use private stdin/stdout pipes. The network pairing-display endpoint can only request that a QR be shown; it cannot read pairing secrets or administer trust.

The helper uses the same default server state directory as the CLI: the user's configuration directory under `linkpad` (on macOS, `~/Library/Application Support/linkpad`). Existing server identities and trusted phones carry over. Run one server per state directory. UI preferences, phone display names and onboarding completion are stored separately from the private server identity.

Closing the parent pipe stops the listener and releases active drags. Quit waits for shutdown and escalates only if the helper fails to stop. A crashed helper is shown as stopped and can be restarted. For development only, `LINKPAD_SERVER_BINARY` overrides the bundled helper path.

**Copy diagnostics** includes backend errors and connection state while excluding pairing invitations and secrets. See [VALIDATION.md](VALIDATION.md) for test history and [the release plan](docs/release-plan.md) for remaining installation and signing checks.
