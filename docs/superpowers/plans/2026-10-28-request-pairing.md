# Open desktop QR from Nearby computers

**Goal:** Tapping Pair beside a nearby server opens a fresh QR on that desktop.
**Architecture:** A TLS endpoint accepts a display request using the phone certificate; it returns no secret. A bounded desktop event creates/reuses the normal two-minute invitation, delivered only over the private child-process pipe. DesktopPlatform raises its window on a new invitation. The phone pins the advertised certificate and falls back to manual desktop action on older servers.
**Constraints:** No remote enrollment or trust approval; no pairing secrets in HTTP; require client identity dates; rate limit requests; preserve active codes and existing connections; no commits requested.

- [x] Test and implement POST /pairing/request, disabled for non-desktop servers, with 10-second rate limit and bounded callback.
- [x] Test and implement desktop event creation/reuse of invitation and window activation.
- [x] Test and implement phone request with bounded timeout, certificate pinning, fallback, and no pairing-state changes.
- [x] Verify Go race tests, Flutter suite/analyzer, native builds; install local Mac and iPhone updates where available.

Review focus: untrusted network callers can only display a short-lived QR; stale/duplicate requests must not rotate active codes; old servers retain QR/manual pairing.

## Verification

- Full Go race suite and go vet passed.
- Flutter suite: 141 passed, one existing skipped desktop helper smoke test; analyzer clean.
- Independent review identified QR visibility at stale scroll offsets. Added a failing minimum-window regression and made the QR scroll into view after layout.
- Native macOS DMG and iOS release builds passed; installed and launched on this Mac and iPhone 16 Pro.
- Live installed-server test: a temporary unpaired client sent a pinned TLS POST and received HTTP 202; desktop accessibility tree showed the QR and expiry without local pairing button interaction. Temporary client keys removed; no test identity enrolled.
- Updated Mac reports input permission needs attention after replacement; user must re-enable Accessibility for cursor control. QR display works independently.
- Linux source updated and portable tests passed; Linux PC installation was not changed in this task.
- No commit requested.
