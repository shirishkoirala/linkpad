# Local Discovery and Address Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconnect an already-paired computer when DHCP changes its address, without re-pairing or changing certificate trust.

**Architecture:** The Go server advertises `_linkpad._tcp.local.` with its actual listener port and public certificate fingerprint. A native Bonjour/NSD adapter supplies untrusted candidate endpoints to the existing Flutter connection state machine; only the normal authenticated ready response permits saving a changed address. Browsing and resolution are generation-scoped and never participate in initial secret-based pairing.

**Tech Stack:** Go 1.26.5, `github.com/hashicorp/mdns` v1.0.7, Flutter/Dart, Bonsoir 6.1.0, existing TLS/WebSocket protocol and secure computer store. Pin Bonsoir to 6.1.0 and lock compatible 6.x platform dependencies; Bonsoir 7 requires Dart 3.13 and is incompatible with the current Linux container's Dart 3.12.

**Spec:** `docs/superpowers/specs/2026-10-26-local-discovery-design.md`

## Global Constraints

- `_linkpad._tcp.local.`; TXT keys `v=1` and `fp=<64 lowercase SHA-256 hex characters>`; no secrets or private keys in advertisements.
- Preserve actual TLS fingerprint/validity checks, mutual authentication, hello/ready validation, and existing revoked/unpaired handling.
- Preserve QR/manual pairing, existing saved computer names, current control mode, and all uncommitted input/keyboard fixes.
- macOS/Linux server support and iOS/Android controller support; no new restricted Apple multicast entitlement.
- Do not scan public networks, auto-pair new computers, or modify the router/live PC IP.
- Every shell invocation uses `rtk` or `rtk proxy`. Network/SDK/install operations use the existing approval mechanism.
- Keep unrelated current changes intact; do not automatically commit them or create a worktree without the user's choice.

## Review Focus

1. Old IP reassigned to an unrelated certificate: reject it, then search for the original pinned identity.
2. Forged TXT fingerprint: the actual TLS certificate must still match before an address is persisted.
3. Late resolution after disconnect/forget/switch/background: no connection resurrection or saved-address overwrite.
4. DHCP changes while the server stays running: refresh advertisements and withdraw obsolete addresses.
5. Denied local-network permission, unavailable multicast, or an old server: bounded failure while saved/manual paths remain usable.

## Task 1: Advertise the authenticated server and track interface changes

**Files:**
- Create `internal/discovery/advertise.go`, `internal/discovery/advertise_test.go`.
- Modify `go.mod`, `go.sum`, `cmd/linkpad/main.go`, `cmd/linkpad/desktop.go`.

**Interfaces:**
- Consume the actual bound `net.Listener` and `identity.Fingerprint(cert.Certificate[0])`.
- Produce `discovery.Start(ctx context.Context, listener net.Listener, fingerprint string, report func(error)) (stop func(), err error)`.
- `stop` is idempotent. Invalid arguments fail immediately; runtime registration failures are reported and retried without stopping TLS serving.

- [ ] Write failing tests asserting exact service/TXT metadata and actual port; reject invalid fingerprints; omit loopback-only and unreachable interface addresses. Use internal fake network/address sources and announcers, not real multicast in unit tests.
- [ ] Add tests that replace the interface address set while the listener remains open, and assert old registration shutdown before the replacement becomes active. Assert cancellation and repeated stop release every registration.
- [ ] Add a registration-failure test: serving stays available, retry succeeds after the network returns, and no pairing token reaches metadata or logs.
- [ ] Run `rtk proxy go test ./internal/discovery` and confirm missing implementation failures.
- [ ] Implement with hashicorp/mdns v1.0.7. Refresh interface addresses every five seconds; also retry failed registrations at that bounded interval. Advertise LAN-facing bindings only; do not advertise wildcard addresses as endpoint IPs. Derive a stable instance from the full public identity and shorten the label safely to DNS limits.
- [ ] In both entry points, bind the actual listener before advertising. Convert CLI serving to the same explicit TLS listener lifecycle if needed; preserve CLI QR/manual behavior. Defer advertiser stop and close it on listener/parent-pipe shutdown. Send diagnostics to stderr, never unrelated lines on the desktop JSON stdout channel.
- [ ] Run discovery and command tests, then `rtk proxy go test ./...` and `rtk proxy go vet ./...`; checkpoint only these files for review, without committing unrelated work.

## Task 2: Add a native, bounded discovery adapter

**Files:**
- Create `mobile/lib/server_discovery.dart`, `mobile/test/server_discovery_test.dart`.
- Modify `mobile/pubspec.yaml`, `mobile/pubspec.lock`, `mobile/ios/Runner/Info.plist`, `mobile/android/app/src/main/AndroidManifest.xml` and platform-generated plugin registration files only where dependency resolution requires them.

**Interfaces:**
- `DiscoveredServer` is immutable and exposes `String fingerprint` and `Uri address`.
- `abstract interface class ServerDiscovery` exposes `Future<List<DiscoveredServer>> find(String fingerprint, {required Duration timeout})` and `Future<void> stop()`.
- `BonjourServerDiscovery` implements this using Bonsoir 6.1.0; keep native plugin calls inside this adapter. A no-op implementation is available for unsupported platforms/tests where native discovery is not injected.

- [ ] Write tests with fake native service events: only `v=1`, a complete matching fingerprint, an integer port 1–65535, and resolved ordinary LAN IPs become candidates. Construct `wss://host:port/ws` locally; never parse an advertised URL.
- [ ] Add malformed/oversized metadata, wrong fingerprint, duplicate service, two different computers, IPv4, IPv6/zone encoding, withdrawn service, resolution error, and permission-refusal tests. Unsupported scopes are rejected explicitly, not misformatted.
- [ ] Add cancellation/timeout tests: a late resolve cannot complete an old search with candidates, listeners stop once, and permission failure completes rather than hanging.
- [ ] Run the adapter tests and observe the expected missing implementation failures.
- [ ] Add and lock the compatible dependency. Resolve at most eight candidates in a three-second search, deduplicated by endpoint; use no persistent cross-search cache initially so stale advertisements are not retained. Stop browser/resolve subscriptions on completion or cancellation.
- [ ] Declare `_linkpad._tcp` in `NSBonjourServices`, update the local-network explanation, and add only the Android permissions required by the plugin's documented native NSD implementation. Verify native browsing does not require the restricted multicast entitlement.
- [ ] Run the adapter tests and Flutter analysis. Verify both the existing iOS SDK and Linux container can resolve the locked dependency versions before proceeding.

## Task 3: Recover the paired endpoint without weakening trust

**Files:**
- Modify `mobile/lib/peer_client.dart`, `mobile/lib/mobile_controls.dart` only if necessary for status display.
- Extend `mobile/test/peer_client_test.dart`, `mobile/test/computer_store_test.dart`, `mobile/test/connection_indicator_test.dart`.
- Create `mobile/test/address_recovery_test.dart` if the recovery scenarios would otherwise obscure the existing input-delivery fixture.

**Interfaces:**
- Add optional `ServerDiscovery? discovery` injection to `PeerClient`; lazy production construction must not invoke native plugins in existing fake-peer widget tests.
- Reuse Task 2's `find` and `stop` methods and existing `ComputerStore.saveVerified(String address, String fingerprint, {DateTime? usedAt})`.
- Keep public `connect`, `disconnect`, `setForeground`, and input APIs compatible. The active connection generation owns all candidate work and any pending save.

- [ ] Write an actual loopback TLS regression: persisted old address fails, injected discovery resolves a second endpoint using the same server certificate, authentication completes, and only then is the saved URL replaced. The computer's custom name and pin must remain unchanged.
- [ ] Write the reassigned-IP regression: old endpoint presents a different certificate; discovery finds the original certificate elsewhere; recovery succeeds. A spoofed advertisement with the correct TXT fingerprint but wrong actual certificate must never persist an endpoint or displace the trust pin.
- [ ] Write cancellation regressions for disconnect, background, switch to another computer, and forget. Deliver late fake resolve/TLS results and assert no connection or save is resurrected. If a tentative candidate's transport ends, clear input exactly as on existing reconnect; never replay keyboard, click, or drag state.
- [ ] Write failure regressions: no multicast, permission denied, service withdrawal, two paired identities, stale/duplicate candidates, and older servers. Manual/QR pairing with a secret must use only its explicitly selected endpoint and must never send that secret to discovered candidates. Verified revoked/unpaired responses remain terminal.
- [ ] Run these regressions against the current fixed-address implementation and observe expected failures.
- [ ] Start one bounded lookup alongside the initial saved-address attempt only for a known paired identity and secret-free connection. Keep the saved address as the initial path; after failure, try up to four deduplicated discovered candidates serially before returning to the existing retry/backoff policy. Do not browse or change endpoints while the existing connection is healthy.
- [ ] Factor shared candidate TLS validation rather than duplicating or bypassing existing pin/validity checks. Reject a mismatching candidate locally and continue other candidates. Distinguish candidate failures from verified server authorization failures. Keep the selected pin immutable and the persisted address unchanged until authenticated ready.
- [ ] Present “Finding your computer…” through the existing subtitle during lookup, then ordinary reconnect/connected status. Failures must leave scan/manual actions available, without reintroducing a connection banner or instructing users to forget a valid pairing.
- [ ] Stop discovery and invalidate its generation from every existing lifecycle cancellation path. Check the generation/selected identity again before invoking persistence; a forgotten computer must not be recreated by a late result.
- [ ] Run recovery, store, connection-indicator, and peer tests; then the full Flutter suite and analysis. Re-run the existing keyboard/drag regressions to detect unintended reconnect changes.

## Task 4: Review, native validation, packaging, and delivery

**Files:**
- Modify `DESKTOP.md` and `PACKAGING.md` with recovery behavior, updated-server requirement, local-network permission troubleshooting, and multicast fallback.
- Keep generated installers under the existing ignored `bin/` paths.

- [ ] Request an independent code review of discovery advertisement, candidate validation, cancellation, and TLS/save ordering. Address concrete findings with failing regressions before continuing.
- [ ] Run `rtk proxy go test ./...`, `rtk proxy go vet ./...`, Flutter analysis and all Flutter tests against a freshly built helper, and `rtk proxy git diff --check`.
- [ ] Run `rtk proxy python3 mobile/tool/test_linux_container.py`. Confirm Go X11 integration, the full Flutter suite, dependency analysis, and desktop startup/shutdown. Use the corrected current test fixture and delivery-based waits already in this checkout; do not mask regressions with broad timeout changes.
- [ ] Verify service discovery from the Mac against the Linux LAN server and native iOS browsing. Use an isolated server identity/listener to change the endpoint with the same certificate and demonstrate recovery; do not change the real PC/router IP or disrupt the live SSH recovery path.
- [ ] Build the iOS release and the macOS/Linux installers with the existing packaging scripts, and verify checksums. Install/launch on the authorized iPhone 16 device `00008140-0005182036BB001C` if connected. If locked/disconnected, report installation and launch states accurately.
- [ ] Transfer the Linux package to `shirish@192.168.1.203`, verify its checksum, and use existing SSH access. If sudo needs a password, leave the exact verified installer/command for entry on the PC; never request a password in chat. Restart and verify the server only after successful installation.
- [ ] Summarize observed recovery behavior, platform verification limits, installer locations, and uncommitted state. Do not claim native Android behavior was device-tested unless a device was actually available.

## Self-review

All spec sections map to Tasks 1–4. The five Review Focus scenarios have explicit
owning tests in Tasks 1–3. Cross-task names and signatures match, public input
APIs remain stable, and platform/version constraints are fixed above. No user
product decisions remain open; implementation method and workspace consent are
the execution handoff choices.

## Execution ledger

- Ruling: use github.com/libp2p/zeroconf/v2 v2.2.0 for advertising, instead of hashicorp/mdns. Inspection showed the latter only responds to queries and closes sockets on shutdown; zeroconf sends cache-flush announcements and goodbye records required for address changes. Risk: an older library; native LAN checks and lifecycle tests must confirm interoperability.
- Workspace: implementing inline in the existing checkout as explicitly requested. Preserve previous fixes; no automatic commits.

- Ruling: vendor the 48 KB Bonsoir Darwin 6.1.0 plugin with one explicit Foundation import, retaining its license, because Xcode 27 cannot compile JSONSerialization otherwise. The normal global pub cache remains untouched; the override is reproducible across builds.

- Task 1 complete: advertiser metadata/lifecycle/address-change tests RED→GREEN; Go suite and race checks passed. Native DNS-SD exposed a RegisterProxy hostname double-suffix bug; a failing hostname assertion preceded the fix, and real OS DNS now resolves the installed Linux server to 192.168.1.203.
- Task 2 complete: native adapter tests RED→GREEN, including metadata validation, service withdrawal, delayed/immediate cancellation, and bounded concurrent resolution. Review's unbounded-lookups finding was reproduced and fixed.
- Task 3 complete: real TLS tests verify recovery, wrong old-IP certificate, forged candidate rejection, preserving names, disconnect/forget cancellation, and background selection/resume. ComputerStore checks cancellation before queued persistence edits.
- Task 4 complete: 133 Flutter tests passed on macOS and under Linux x86_64 emulation. Final Linux desktop/helper smoke test passed; exact installed helper hash matches the verified binary. Independent review completed and its finding fixed. iPhone 16 update installed/launched; final Linux package installed by user and server restarted; Mac/Linux installer checksums verified. Native Android was not device-tested. No live DHCP/router address was changed.
- Test fixture correction: generate the second server certificate before starting an active drag; synchronous cryptography under x86_64 emulation otherwise starves the fixture's short ACK timers. No production timeout was weakened.
- Changes remain uncommitted as the user has not requested a discovery commit.
