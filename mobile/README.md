# Flutter controller

Shared Android and iOS touchpad client for the existing Go desktop agent. The native Kotlin controller in `../android` remains available.

## Run

Install Flutter stable and run from this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

For Android, use Android 10/API 29 or later. For iOS, use iOS 15 or later, Xcode and a configured signing team; approve the Local Network permission prompt. Both devices must reach the desktop over the same LAN.

Start the desktop with `-pair -allow-pointer`, enter `wss://DESKTOP-IP:4747/ws`, verify its fingerprint on the desktop, and enter the short-lived secret. Successful pairing saves the address and pin and clears the secret. Reconnect without a secret. Grant macOS Accessibility permission to enable actual mouse input. An empty capability list means pairing succeeded but pointer control is unavailable.

The client creates an EC identity certificate, stores its PEM credentials with flutter_secure_storage (Android encrypted storage / iOS Keychain), requires TLS 1.3 and checks the exact desktop certificate SHA-256 fingerprint and validity dates. Unlike the Kotlin implementation, this identity uses a software private key that is read into Dart memory, rather than a non-exportable Android Keystore signing key. This is a deliberate portability tradeoff. Uninstall/backup/keychain behavior varies by OS; loss of the identity requires re-pairing. Certificates last ten years; renewal is not implemented.

Connections are foreground-only. The app automatically connects to the last successfully saved desktop on launch. Brief interruptions retry with delays of 1, 2, 4, 8, then at most 15 seconds. Leaving the app closes the session and drops input; returning reconnects without a pairing secret. Disconnect cancels retries and resume recovery until you explicitly connect again (opening the app on a later launch restores the saved desktop).

Every new connection verifies the saved certificate fingerprint and renegotiates capabilities. A changed/expired certificate, rejected pairing, unpaired identity or invalid protocol response stops retries with an actionable error. Pairing secrets are used only in the explicitly requested attempt, never stored or automatically replayed. If a connection drops during first enrollment, the server might have enrolled the device before the response was lost: try connecting without a secret, or start a new pairing window if the server reports it unpaired.

Motion and clicks retain their order and allow one request awaiting acknowledgement. The input buffer is bounded and expires entries after 150 ms. A reply taking longer than 150 ms pauses input and clears the backlog; a two-second response timeout reconnects. A heartbeat every 15 seconds detects idle failures. Disconnect and backgrounding also clear all pending input. Already transmitted input cannot be recalled, so an action executed before a lost acknowledgement is never retried. No discovery or background control is included.

## Build

```sh
flutter build apk --debug
flutter build ios --simulator --debug
# Physical iPhone: configure signing in ios/Runner.xcworkspace, then:
flutter build ios --release
```

Platform builds and hardware pairing must be validated separately. Simulator builds do not establish signing or actual iPhone connectivity.

Touchpad gestures: one-finger tap clicks left; a brief two-finger tap clicks right. Moving a finger, holding longer than 300 ms, or cancelling a contact does not click. Complete click buttons remain available.
