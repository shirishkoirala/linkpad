# Flutter validation — 14 October 2026

Environment: macOS arm64, Flutter 3.32.5 stable, Dart 3.8.1.

- `flutter analyze`: no issues found. Dart formatting is clean.

- Seven tests pass: wire pairing/reconnect format, pointer bounds, malformed/oversized message rejection, endpoint validation, real loopback TLS 1.3 with client certificate proof, pinned server verification, pairing and acknowledgement pacing, wrong-pin rejection, and reconnect with stored identity.
- Secure storage is mocked in tests; these tests do not validate Android encrypted storage or iOS Keychain on hardware.
- Android APK build was stopped at the user's request to prioritize their iPhone. No Flutter APK is claimed as built.
- Signed iOS debug build succeeded with Xcode 27 after setting the app and CocoaPods deployment targets to iOS 15. The release build also succeeded and was installed and launched on the connected iPhone. Debugger launch stalled; release launch succeeded. Pairing and actual pointer interaction remain unverified.
- Physical iPhone-to-desktop pairing, Local Network permission, Keychain persistence, lifecycle disconnection and actual pointer movement remain unverified.
- Flutter CI is configured but has not run remotely.

To run on iPhone: install full Xcode, complete its first-launch setup, select it as the active developer directory, connect the iPhone and enable Developer Mode if prompted. Run `flutter pub get`, open `ios/Runner.xcworkspace` to choose your signing team, then use `flutter run -d <device-id>` from this directory. Verify the desktop fingerprint before pairing.

## iOS 27 launch repair

The initial app launch crashed in UIKit at UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption. Added a scene manifest and UIWindowSceneDelegate using the shared Flutter engine. The rebuilt release app installed and launched successfully; Xcode device diagnostics confirmed the Runner process remained running afterward. Hardware pairing and pointer control still need user verification.

## Relative touchpad movement

Ten Flutter tests passed, including finger lift/reposition without cursor jumps and fractional motion preserved across strokes. Input is relative to each contact and queued while awaiting desktop acknowledgements. Real-device feel still requires hardware feedback.

## Tap gestures

Twelve tests passed, including one-finger left tap, two-finger right tap without an extra left click, rejection of drags/holds/cancellation, and clicks queued through acknowledgement backpressure. Flutter analysis is clean.

## Connection and input stability

Current suite: 29 passing Flutter tests; `flutter analyze` reports no issues. Added real TLS tests for automatic reconnect with hello instead of reusing the pairing secret, renegotiated capabilities, slow replies, stale-click removal, response timeout recovery, background/resume, manual disconnect cancelling recovery, actionable unpaired/expired-secret failures, repeated lifecycle cycles, changed certificates stopping retries, malformed responses and idle heartbeat failure. Input-buffer tests cover expiry, ordering, bounded motion/clicks, fractional movement and capped retry delays.

iOS scene lifecycle callbacks now explicitly forward resumed/inactive/paused/detached state to the Flutter engine so the client can suspend and resume its sessions. Tests exercise loopback faults; physical Wi-Fi switching, long-running sessions and screen-lock behavior still need hardware verification. These checks do not constitute a security audit.

The stability release built and launched on the paired iPhone. A new phone-to-server connection appeared automatically after launch. The desktop process was then stopped and restarted without a pairing window; the iPhone established a new connection to the restarted server without manual input. Pointer feel, screen-lock recovery and actual Wi-Fi switching remain hardware checks for the user.
