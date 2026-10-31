# Linkpad v0.1.0 release plan

Updated: 30 October 2026

## Current status

The release app identifier is `com.shirishkoirala.linkpad` for Android, iOS, macOS and Linux. Apple test targets use the `.RunnerTests` suffix. Earlier development identifiers are retired; mobile builds with this identifier install as a separate app and may require pairing again. Store records must use the new identifier.

Mac, Linux, Android and iOS have had hands-on testing. Windows final testing is pending. These checks do not yet establish that every release scenario below has passed.

Known follow-ups:

- [ ] Complete Windows testing and confirm the Windows build and installer are ready.
- [ ] Investigate Linux volume controls. Media key mappings and Xfce shortcuts are present, but end-to-end operation is not verified. The requested Docker investigation is pending.
- [ ] Confirm the smaller Android adaptive icon fits the launcher mask on the physical device.

## 1. Finish platform testing

Run the following checks on Windows, macOS, Linux, Android and iOS wherever applicable. Record the OS version, device, build commit and result. Test Linux Mint Xfce and Ubuntu separately; containers can help verify builds and input events, but physical desktop testing is still required for permissions, audio and discovery.

- [ ] Fresh installation and first-run setup.
- [ ] Required permissions, including recovery after permission changes.
- [ ] Nearby discovery, QR pairing and saved computers.
- [ ] Touchpad movement, tap, right-click, drag and two-finger scroll.
- [ ] Keyboard input, modifiers, held keys, D-pad and Enter.
- [ ] Volume down, mute and volume up.
- [ ] Reconnect after Wi-Fi interruption, sleep/wake and server restart.
- [ ] Rediscovery after the server IP address changes.
- [ ] Switching computers and connecting multiple phones.
- [ ] Upgrade an existing installation while preserving pairings and settings.

## 2. Close known issues

- [ ] Resolve and verify release-blocking failures from testing.
- [ ] For any deferred issue, document the affected platform, limitation and workaround in release notes.
- [ ] Confirm there are no unresolved failures in core pairing, input or reconnection flows.

## 3. Freeze a release candidate

- [ ] Confirm permanent application identifiers and version/build numbers.
- [ ] Commit final fixes and record a single source commit for all release artifacts.
- [ ] Run relevant automated tests, static checks and platform builds.
- [ ] Build installers and mobile artifacts from that commit.
- [ ] Record artifact names, signing status and SHA-256 checksums.
- [ ] Tag the approved release candidate; repeat affected checks if its code changes.

## 4. Test distribution

| Platform | Initial distribution | Requirements |
| --- | --- | --- |
| Android | Google Play internal testing | Release-signed Android App Bundle, Play App Signing and tester access |
| iOS | TestFlight | App Store Connect record, Apple distribution signing and tester access |
| macOS | Direct-download DMG | Developer ID signing, notarization and stapling |
| Linux x86_64 | GitHub Releases | Verified package, dependency requirements and installation instructions |
| Windows | GitHub Releases | Verified installer and documented signing status |

- [ ] Install each distributed artifact through its actual delivery channel.
- [ ] Verify fresh installation and upgrades using the distributed artifacts.
- [ ] Verify the macOS download on a machine without development permissions or tooling.
- [ ] Confirm mobile reviewers and testers can obtain a compatible desktop server.

The initial macOS release uses direct distribution. Mac App Store sandbox compatibility requires a separate assessment.

## 5. Prepare public listings and support

- [ ] Complete the asset checklist below before submitting store listings.
- [ ] Publish a privacy policy describing actual data handling.
- [ ] Complete Google Play Data safety and Apple App Privacy disclosures.
- [ ] Prepare icons, screenshots, descriptions and platform requirements.
- [ ] Publish a support page and troubleshooting instructions.
- [ ] Explain camera, local network and desktop input permission requests.
- [ ] Provide Apple reviewers with desktop installation and pairing instructions.
- [ ] Write release notes, including supported platforms and known limitations.

### Release assets

Keep editable source artwork and exported assets in a versioned release asset folder. Capture screenshots from the approved release candidate, using sample computer names and no real pairing secrets, QR codes, IP addresses or personal information. Confirm current store upload requirements in Play Console and App Store Connect before final export.

| Destination | Assets to prepare |
| --- | --- |
| Shared branding | Approved logo master, light/dark variants, transparent exports, brand colors and a short app description |
| Google Play | 512 × 512 store icon, 1024 × 500 feature graphic and phone screenshots; additional device assets only for supported form factors |
| Android app | Adaptive foreground/background layers, monochrome themed icon and legacy launcher icons; verify circular and rounded-square masks |
| iOS App Store | 1024 × 1024 opaque app icon and screenshots for the supported device categories and sizes requested by App Store Connect |
| macOS download | App icon, DMG presentation artwork, desktop setup screenshot and Accessibility permission walkthrough |
| Linux and Windows downloads | Platform app/installer icons, desktop screenshots and illustrated installation instructions |
| Website and GitHub | Logo, social preview image, mobile/desktop overview images, download badges and support illustrations |

Screenshot storyboard:

1. Touchpad: demonstrate mouse control and scrolling.
2. Remote: show D-pad, Enter and volume controls.
3. Keyboard: show text input and modifier keys.
4. Computers: show discovery and saved computers using sample data.
5. Setup: explain desktop installation and secure QR pairing using nonfunctional illustrative content.

Asset completion checks:

- [ ] Approve the final logo and verify icon legibility at small sizes on each platform.
- [ ] Capture clean Android and iOS screenshots independently so system UI matches the platform.
- [ ] Capture current desktop screenshots for Windows, macOS and Linux.
- [ ] Export store artwork at the required dimensions and file formats.
- [ ] Write concise screenshot captions that accurately describe shipped features.
- [ ] Check typography, contrast, cropping, safe areas and consistency across exports.
- [ ] Confirm that all artwork, fonts and imagery have appropriate usage rights.
- [ ] Record which release candidate the screenshots represent; refresh them if visible UI changes.
- [ ] Review assets in the actual store listing previews before submission.

Store preview videos are optional for v0.1.0 and can follow after launch.

## 6. Publish

- [ ] Approve the tested release candidate for v0.1.0.
- [ ] Submit Android and iOS builds for store review.
- [ ] Create the final Git tag and GitHub Release for the approved source commit.
- [ ] Attach desktop installers, checksums, release notes and setup instructions.
- [ ] Verify public download links and store availability.
- [ ] Keep the previous working artifacts available for recovery.

## Release readiness

Publish only when core installation, pairing, input and reconnection checks pass on each advertised platform, distributed artifacts are verified, and remaining limitations are explicitly documented. Track store approval separately from technical readiness.
