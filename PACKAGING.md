# Desktop installers

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

For an upgrade, quit Linkpad and install the new `.deb` the same way. To remove
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
