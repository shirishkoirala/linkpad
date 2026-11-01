# Desktop installers

## GitHub Actions releases

The **Desktop release** workflow builds Linux x86_64, macOS and Windows x86_64 installers on native runners, runs Go race tests/vet and Flutter analysis/tests, and retains installers and checksums as Actions artifacts. Tag-triggered runs attach them to a **draft** GitHub Release. It never publishes a release automatically.

Run it from **Actions → Desktop release → Run workflow**, or push a tag such as `v0.1.0`. A tag must match the version in `mobile/pubspec.yaml` (without the `+build` suffix). Manual runs use the version from the selected source ref and build artifacts only by default; enable **Create/update a draft release** when ready. Build all installers from the same approved commit.

Artifacts appear under `desktop-Linux`, `desktop-macOS` and `desktop-Windows`. Failed builds prevent the draft-release job. Reruns can replace assets in a draft from the same commit, but refuse to overwrite a published release or a draft from another commit. When replacing a draft, remove any obsolete installer asset before publishing (for example, an old `macos-local.dmg` after signing is enabled).

### Windows installer

On Windows x64 with Flutter, Go, Visual Studio's C++ desktop workload and Inno Setup 6.3 or newer installed:

```powershell
cd mobile
flutter build windows --release
cd ..
python mobile/tool/package_desktop.py windows
```

The installer is `bin/releases/Linkpad-0.1.0-windows-x86_64-setup.exe`, with a `.sha256` checksum. It installs the GUI, bundled Go helper, plugins and Visual C++ runtime DLLs into the current user's Local AppData Programs directory and adds a Start menu entry. Administrator access is not required for installation. No firewall rule, service or automatic startup is enabled by the installer. Start-at-login remains an explicit setting in the app.

Quit any old command-line server or running GUI before installing/upgrading. Keep Windows time synchronized for pairing, and allow Linkpad on the Private network if Windows Firewall asks. The app runs in your logged-in desktop session; secure desktop and elevated-app restrictions still apply.

The Windows package is currently **unsigned**; publisher/SmartScreen warnings may appear. Code signing is a separate release requirement. CI silently installs into an isolated test directory, verifies a visible GUI and a bundled server child listening on TCP 4747, then verifies terminating the GUI stops the helper. This supplements, rather than replaces, physical installer and tray/startup testing.

### Mac signing secrets

For a public Mac installer, configure these repository secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` export of your **Developer ID Application** certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `MACOS_SIGNING_IDENTITY` | Exact identity, e.g. `Developer ID Application: Shirish Koirala (TEAMID)` |
| `APPLE_ID` | Apple Account email authorized to notarize the app |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_APP_PASSWORD` | Apple app-specific password for notarization |

An Apple Development or Apple Distribution certificate does not replace Developer ID Application signing. Export the Developer ID identity from Keychain Access, including its private key. Base64 is encoding, not encryption: put it directly into GitHub Secrets, never a tracked file or issue. Do not send credentials in chat.

With all secrets configured, the workflow imports the identity into a temporary keychain and uses the existing signing/notarization packager. Missing parts of a signing configuration cause failure rather than a silent unsigned fallback. With **none** configured, the workflow produces the clearly labelled `macos-local.dmg` for testing only and warns in the draft notes. Configure signing and rerun before distributing a public Mac installer.

### Final publication

Verify downloaded checksums, test both installed apps and upgrades on physical computers, and confirm the Mac DMG is notarized. Edit the draft release notes, remove any local-testing installer, then click **Publish release**. Public installers can then be linked from the support page. Linux packages target Ubuntu 24.04 / Linux Mint 22-compatible x86_64 systems; other Linux distributions and Wayland input are not covered by this workflow.

Run these commands from the repository root with Python 3.10 or newer.
Generated installers and SHA-256 checksum files go into `bin/releases/`, which
is already ignored by Git. Both installers include the Go server helper.
Application data and existing phone pairings remain in the user's configuration
directory, outside the installation.

## macOS DMG

With Flutter, Go, and Xcode installed:

```sh
python3 mobile/tool/package_desktop.py macos
```

This builds the current release app and produces
`bin/releases/Linkpad-0.1.0-macos-local.dmg`. Drag Linkpad to Applications, eject
the DMG, and open the installed app. Grant Accessibility permission and restart
its server when prompted. Quit the old app before replacing it.

The default DMG is ad-hoc signed and **not notarized**. It is for local testing;
it is not a Gatekeeper-approved public release. Replacing an ad-hoc build may
require granting Accessibility permission again. Do not disable Gatekeeper.

For public distribution, install a **Developer ID Application** certificate
with its private key, and configure a notarization keychain profile through
`xcrun notarytool store-credentials`. Apple Development certificates cannot
replace Developer ID signing for this workflow. Then run:

```sh
python3 mobile/tool/package_desktop.py macos \
  --identity 'Developer ID Application: YOUR NAME (TEAMID)' \
  --notary-profile linkpad-notary
```

The script signs frameworks and the server helper before the app, enables the
hardened runtime, submits the app to Apple, staples its ticket, creates the DMG,
then signs/notarizes/staples the DMG. Notarization errors stop packaging; there
is no fallback to an unnotarized public release. Signing never changes the
original build bundle. Credentials stay in Keychain, not in the repository.

`--skip-build` packages an existing release build. `--app /path/Linkpad.app`
selects another bundle. The package version must match its Info.plist.

## Linux amd64 Debian package

On Linux x86_64, build the app as described in `DESKTOP.md`, install
`dpkg-dev`, and package it:

```sh
python3 mobile/tool/package_desktop.py linux \
  --bundle mobile/build/linux/x64/release/bundle
```

On a Mac with Docker, first create the tested Linux image/bundle:

```sh
python3 mobile/tool/test_linux_container.py
python3 mobile/tool/package_desktop.py linux --docker
```

`--docker` packages the bundle already in the `linkpad-linux-test` image; it does
not rebuild it. Re-run the container build after source changes. Use
`--bundle /path/to/bundle --docker` to package a different host bundle instead.
`--image` selects a different packaging image containing Debian packaging tools.
The build and packaging environment must match the target distribution.

The package installs the whole bundle in `/opt/linkpad`, provides the `linkpad`
command in `/usr/bin`, and installs an application-menu entry and icon. Runtime
dependencies are derived from every bundled ELF using `dpkg-shlibdeps`; tray and
secret-storage libraries are also declared explicitly. No system service or
automatic login startup is enabled by installation. Enable login startup in the
app only if wanted.

For the current version, copy the `.deb` to the Linux PC and run:

```sh
sudo apt install ./linkpad_0.1.0_amd64.deb
linkpad
```

Quit any previously running Linkpad instance or CLI/systemd server first. The
current Docker build targets Ubuntu 24.04-compatible systems (glibc 2.39+) and
requires an X11 desktop session. It does not add Wayland or login-screen input.
Older distributions require a release bundle built against their libraries.

For an upgrade, quit Linkpad and install the new `.deb` the same way. During
development, if the version number has not changed, use
`sudo apt install --reinstall ./linkpad_0.1.0_amd64.deb` to replace the old build. To remove
it, turn off its login startup setting, quit the app, then run
`sudo apt remove linkpad`. Pairing state is preserved. There are no maintainer
scripts that start processes or edit users' home directories.

## Versions and verification

The default package version comes from `mobile/pubspec.yaml`, without the
mobile build-number suffix. Update that version before a release and rebuild
both platforms. `--version 0.2.0` overrides the package version; `--output PATH`
overrides the output directory. The Linux bundle must be built from the matching
source version. `--version` does not rebuild or relabel the app itself.

On macOS, verify the DMG and installed signature:

```sh
hdiutil verify bin/releases/Linkpad-0.1.0-macos-local.dmg
codesign --verify --deep --strict /Applications/Linkpad.app
```

For notarized releases, also run `xcrun stapler validate` on the DMG and
`spctl --assess --type execute /Applications/Linkpad.app`.

On Linux, inspect the package before installation:

```sh
dpkg-deb --info linkpad_0.1.0_amd64.deb
dpkg-deb --contents linkpad_0.1.0_amd64.deb
sha256sum -c linkpad_0.1.0_amd64.deb.sha256
```

Use `shasum -a 256 -c FILE.sha256` for checksums on macOS. Install packages
from trusted sources; the checksum detects corruption but is not a signature.

## Local discovery and changed addresses

Updated servers advertise `_linkpad._tcp` on the local network using only their
public certificate fingerprint and listener port. Updated phones keep trying the
saved address and can rediscover the same paired identity if DHCP changes its IP.
The actual TLS certificate must still match before a new address is saved; no new
pairing token is sent and saved computer names are preserved.

The server refreshes advertisements when interface addresses change and withdraws
them on shutdown. Discovery failure does not stop ordinary QR/manual connections.
On iPhone, allow Linkpad under Settings > Privacy & Security > Local Network.
Networks that isolate clients or block multicast may require scanning a fresh QR
or updating the manual address; do not delete a pairing just because its IP changed.
Old servers must be upgraded to advertise discovery. The update does not change
router settings, and it does not provide remote/cloud discovery.
