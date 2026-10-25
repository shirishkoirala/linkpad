# First installation and setup

The core guided setup is implemented. The goal is a working phone-to-computer
input session, rather than just a successful installation or network connection.

## Recommended flow

Use a focused, resumable setup flow on first launch: **Enable control → Connect
phone → Try it**. Keep the regular desktop UI for subsequent launches. A compact
setup checklist is an alternative for people who prefer seeing everything at
once; the guided flow is recommended for new users.

Do not show the setup flow again just because the phone disconnects. Determine
readiness from live server/permission/session state. Remember completion locally,
but recheck prerequisites on every launch. Returning users with saved pairings
should see only a relevant repair banner if something is wrong.

### Install and open

- Mac: drag Linkpad to Applications and open it there. Detect launches from the
  DMG or an unstable temporary location, and explain where to install it before
  requesting Accessibility permission. Do not enable login startup from a DMG.
- Linux: the `.deb` installs the app, helper, icon, and launcher. Start it from
  the application menu inside the graphical session, not with `sudo`.
- Start the bundled server automatically. Show a brief checking state while
  inspecting listener, input access, and network-address availability. Bind or
  helper failures must not be presented as a permission problem.
- A public Mac release needs stable Developer ID signing and notarization.
  Explain local-build limitations separately from ordinary product onboarding.

### Enable control

Mac copy:

> Let your phone control this Mac
>
> Accessibility access lets Linkpad move the pointer, click, and type.

Primary action: **Open Accessibility settings**. Show the exact next step:
**Turn on Linkpad in Privacy & Security → Accessibility, then return here.**

Implementation requirements:

- Initiate an Accessibility trust request from the actual responsible process,
  using Apple's supported API, and open the relevant Settings pane. A deep link
  alone does not guarantee that Linkpad appears in the permission list.
- Verify attribution for the bundled Go helper in the signed app. The displayed
  app/helper name and instructions must match the identity macOS actually shows.
- On return to Linkpad, recheck actual backend readiness. Refresh or restart the
  helper automatically before pairing if that is required to register input
  capabilities; surface any restart failure. Do not require users to understand
  or manually restart a server.
- Never mark access as granted because a user pressed a button. An explicit
  **Check again** action is a fallback to the automatic foreground check.
- If macOS needs the app reopened, provide that specific action and resume setup
  afterward. Repeatedly restarting the helper must not create a loop.
- Show success as **Desktop control enabled**, distinct from **Server running**.
- The current feature set needs Accessibility, not Screen Recording or Input
  Monitoring. Do not ask for unrelated permissions.

Linux:

- Detect X11, display authentication, XTEST, and backend readiness. Skip a manual
  permission step when the checks pass: **Desktop control is ready**.
- For Wayland, show **An X11 session is needed** with distribution-neutral
  instructions to sign out and choose an available X11/Xorg session. If the
  distribution has no such session, say this configuration is unsupported.
  A button cannot switch the active display server.
- For display/authentication failures, say **Open Linkpad from your desktop
  session** and offer **Check again** plus expandable diagnostics. Do not send
  Linux users to Mac Accessibility settings or suggest running as root.
- Check for another Linkpad/systemd process using port 4747. Explain how to stop
  the old instance; do not kill arbitrary processes or disable services silently.

### Connect the phone

Once desktop input is ready, show **Connect your phone** and **Create pairing
code**. Say **Your phone and computer need to be on the same local network**;
the computer can use Ethernet while the phone uses Wi-Fi.

- Create a QR only when the user starts pairing. Show a readable two-minute
  expiry countdown and a single **Create new code** action after expiry.
- Explain that the code grants control to the scanning phone. Keep the existing
  single-use pairing window, certificate pinning, and cancellation behavior.
- Use the selected reachable LAN address. Never display `0.0.0.0` as an address
  the phone should connect to. If no usable address exists, fix that state before
  showing a misleading QR code. Keep interface selection under troubleshooting.
- Wait for the authenticated phone session and negotiated input capability to
  show **Connected and ready**. Camera access or scanning a QR alone is not
  completion. Give both desktop and phone matching state labels.
- Keep manual pairing under **Can't scan?**. Preserve fingerprint verification;
  ease of setup must not bypass the existing identity check.

Phone first-run actions:

1. **Connect to a computer** opens a short explanation: install/open Linkpad on
   the computer and display its pairing code.
2. **Scan code** requests Camera permission in context, with a purpose explaining
   that it scans the computer's code. Do not request it at app launch.
3. Scanning a valid code starts the local connection. Explain the iOS Local
   Network prompt in this context and request access through the real network
   operation. Do not require permissions for a user who has not begun pairing.
4. If Camera access is denied, offer **Open Settings**, **Try again**, and
   **Enter manually**. Distinguish denial from unavailable hardware and scanner
   failures. Recheck scanner lifecycle on return from Settings.
5. If connection fails, offer a short set of checks: local-network access, same
   reachable network, computer awake, firewall, and server running. Do not label
   a generic timeout as a proven Local Network permission denial; iOS does not
   supply a simple universal permission-status API for that conclusion.

If macOS also presents a Local Network or incoming-connections prompt, explain
why access is needed. Verify supported OS behavior and add the app usage
description where required. Never disable a firewall automatically. Linux
firewall instructions should be specific to the user's environment and remain
behind a connection failure rather than mandatory terminal setup.

### Try it and finish

Show **Try your touchpad** on the phone and a small click target on the desktop.
Guide the user through moving the pointer and tapping, then optionally scrolling
and typing in a local test field. Do not inject test text into another app or
move the pointer without the user's action. A user click alone cannot prove it
came from Linkpad: use acknowledged remote input plus explicit user confirmation
that the pointer actually moved/clicked. Do not store the test text.

- If transport is healthy but input fails, return to the relevant permission or
  backend repair step while preserving pairing.
- Finish only when the user confirms control works. Keep an explicit **Test
  later** path with an incomplete-test label for users who wish to defer it.
- Offer **Start Linkpad when I sign in** unchecked. Explain the menu bar/tray and
  how to quit. Apply the setting only if the user opts in; handle OS rejection.
- Never make startup at login a prerequisite for controlling the computer.

## Recovery and language

Use specific, distinct states: **Checking**, **Permission needed**, **Waiting for
phone**, **Connected and ready**, **Connection slow**, and **Input unavailable**.
Always give one primary recovery action. Expand technical details only when
requested; do not place ports, certificate fingerprints, or environment variables
in the happy path.

Resume at the earliest unmet requirement after app restart. Camera denial,
expired QR, app suspension, network changes, and permission revocation must not
erase trusted device identities. Reopening an existing session should not
silently enroll another device or auto-enable login startup.

## Current gaps and implementation order

The current desktop app starts its helper immediately, places Accessibility
instructions in preferences, and requires a manual helper restart. Input plugin
availability is selected at helper startup. The QR UI is usable even when input
is unavailable. The phone scanner currently maps all camera errors to one
settings/manual-entry message. These behaviors account for much of the earlier
"connected but not working" confusion.

1. Add a desktop readiness/setup state model and resumable guided screen, with
   backend checks driving each step. Start with Mac permission recovery and
   Linux session/backend failures. Keep regular controls available afterward.
2. Add the native Accessibility request and foreground recheck/restart path.
   Handle stable installation location and signed helper attribution.
3. Gate the first-run QR flow on working input, integrate expiry/error recovery,
   and add the phone's contextual Camera/Local Network guidance and Settings
   return path.
4. Add the explicit control test, optional login startup, and completion state.
5. Validate clean installs and upgrades on real Mac/iPhone and Linux X11.
   Containers cover packaging/session/input logic but cannot validate real macOS
   permission prompts, iOS Local Network prompts, or physical desktop tray hosts.

## Acceptance checks

- A new Mac user can open the correct settings page, grant access, return, and
  continue without knowing the helper exists.
- A new Linux X11 user reaches pairing without a Mac-specific permission step;
  Wayland and invalid display authentication get accurate recovery instructions.
- Denying Camera or Local Network access gives a useful recovery path. Existing
  permission is not requested again, and manual pairing remains usable.
- Expired codes, unavailable addresses, port conflicts, and restarts never show
  fake success. Pairing tokens are not persisted in onboarding preferences.
- Fresh installs show setup; completed users are not forced through it on each
  disconnect. Revoked desktop permission triggers repair without losing pairing.
- The control test, completion, and startup preference are separate states.
  No startup option is enabled without an explicit user choice.

## Implementation status

Implemented: resumable desktop readiness/permission/pair/test flow, DMG-location
guard, helper-originated macOS Accessibility request, focus/status-based access
recheck with a single capability-refresh restart, Linux session-specific repair,
QR expiry/manual recovery, acknowledged remote-input activity plus explicit user
confirmation, optional login startup, deferred control testing, persisted
completion, and migration of existing trusted installations.

Phone changes include a contextual first-pairing explanation, Camera-specific
denial/settings recovery, retry for scanner failures, a working manual-entry
fallback, and connection help that does not mislabel timeouts as permission
denials. The Camera request still belongs to the scanner and the Local Network
request to the actual network connection. Native iOS and Android settings actions
open only Linkpad's application settings.

Remaining physical validation: macOS permission attribution to the responsible
app/helper with Developer ID signing, settings-return behavior on real OS versions,
iPhone Camera/Local Network prompts, and physical Linux tray/login behavior.
The implementation blocks running setup from a mounted Mac disk image; it does
not automatically relocate apps or block intentional non-DMG development builds.
It gives explicit quit/reopen guidance for access that remains unavailable rather
than repeatedly restarting the helper.

The setup-start marker is saved before pairing so closing the app midway does
not turn an incomplete setup into an apparent legacy installation. A returning
trusted phone is asked to reconnect instead of being required to scan again.
Android build tooling was aligned with the installed Flutter SDK minimums
(Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20); its Settings-channel
change passed Kotlin compilation without producing an APK.
