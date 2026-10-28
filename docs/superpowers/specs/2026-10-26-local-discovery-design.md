# Recover paired computers after an address change

## Intent and agreed approach

Linkpad currently persists a WebSocket URL and certificate fingerprint for each
paired computer. Reconnect keeps using that URL, so a DHCP address change makes
an otherwise trusted computer unreachable. The user chose the proposed
mDNS/Bonjour approach: advertise the server locally, rediscover its endpoint,
and verify the existing fingerprint before saving the new address.

This changes discovery and connection recovery, not the pairing trust model.

## Goals

- Reconnect an already-paired computer after its IP address or listening port
  changes, without entering another pairing secret or forgetting the computer.
- Support the Go CLI and desktop server on macOS and Linux, and the Flutter
  controller on iOS and Android.
- Keep current pointer, keyboard, drag, and disconnect safety behavior.
- Keep QR/manual pairing and saved-address connections working when multicast
  is blocked, discovery permission is denied, or the server predates discovery.
- Stop discovery work when the user disconnects, switches computers, forgets
  the selected computer, backgrounds the phone, or disposes the controller.

## Non-goals

No cloud account, relay, public network scan, router configuration, automatic
pairing, or new-device picker is included. Do not change certificate identity,
replay pairing secrets, rename saved computers, or silently trust a replacement
certificate. Discovery across isolated VLANs is not promised.

## Approaches considered

1. **DHCP reservation:** stabilizes one router's address allocation, but requires
   manual router administration and does not make the app recover elsewhere.
2. **Saved hostname only:** can help on machines with working local name
   resolution, but does not identify the paired certificate or discover ports.
3. **mDNS service discovery plus existing TLS pinning (chosen):** recovers the
   endpoint independently of its IP, while keeping the existing trust boundary.
   It requires multicast access and platform local-network permissions.

## Server advertisement

Advertise `_linkpad._tcp.local.` only after the TLS listener is successfully
bound and the server identity is loaded. The SRV port comes from the actual
listener, including dynamically assigned ports. Advertisement must cover only
interfaces reachable through the listening address; loopback-only servers do
not advertise to the LAN.

Refresh or re-register records when the active interface/address set changes,
including DHCP renewal while the server remains running. Withdraw obsolete
addresses rather than continuing to announce the startup address indefinitely.

Use a stable, collision-resistant service instance derived from the certificate
identity, rather than the current IP. TXT metadata contains a format version
and the complete SHA-256 certificate fingerprint. An optional display name may
be included, but never a pairing secret, bearer token, or private key.

Close/withdraw the advertisement on normal shutdown, desktop pipe EOF, listener
failure, or restart. An advertisement failure is diagnostic and nonfatal: the
server must continue serving QR/manual clients. Log/report the discovery issue
without corrupting desktop JSON status output.

## Phone discovery adapter

Put discovery behind an injectable interface with a production implementation
using native Bonjour/Android NSD through a maintained Flutter plugin. Avoid raw
iOS multicast sockets, which can require an additional Apple entitlement.
Library selection and versions are implementation choices to verify against
the project's Flutter/Dart and Linux build compatibility before adoption.

Add `_linkpad._tcp` to iOS Bonjour service declarations and an accurate local
network usage description. Add Android networking permissions required by the
chosen native implementation. Permission refusal must leave manual connection
available and produce a concise actionable status, without an endless spinner.

Advertisements are untrusted hints. Validate the metadata version, fingerprint
shape, port, resolved IP family, and bounded lengths. Consider only ordinary
LAN endpoints resolved from this service. Do not accept arbitrary URLs, URL
credentials, or paths from TXT data. Construct the existing `wss://host:port/ws`
endpoint, including correct IPv6 encoding and interface scope where supported.
Unsupported scoped addresses are skipped rather than stored incorrectly.

## Recovery and identity verification

The saved address remains the initial connection path. A bounded discovery
lookup can run alongside that attempt so recovery does not require waiting
through several long backoff intervals. Retry uses the existing session and
backoff machinery, with a small bounded candidate list and no parallel input
connections. Discovery must not suspend an already healthy connection.

For a saved computer, consider discovered candidates only when their advertised
fingerprint equals the saved fingerprint. The advertisement does not prove
identity: each candidate must pass the existing actual TLS certificate hash
and validity checks, client-certificate authentication, and `hello`/`ready`
handshake. No pairing token is sent during rediscovery.

If DHCP reassigns the old IP to another computer, a certificate mismatch at that
old endpoint must not prevent searching for the original pinned identity. A
spoofed advertisement or mismatching candidate is rejected without overwriting
the saved pin or preventing other candidates from being tried. If the original
identity cannot be found, retain the existing actionable connection/certificate
error. A verified server that reports revoked/unpaired access still requires
the existing explicit re-pairing flow.

Only after a successful authenticated ready response persist the changed URL
through `ComputerStore.saveVerified`, preserving the user's name and pin.
Failed candidate attempts do not alter the saved address. Initial pairing with
a new secret continues to use the explicitly selected QR/manual endpoint;
discovery does not redirect that secret.

Use generation/cancellation checks around browsing, resolving, TLS completion,
and persistence. Results from a previous selection must not reconnect or save
after a disconnect, background transition, computer switch, or forget action.
Cache resolved endpoints only for a bounded lifetime and invalidate withdrawn
or failed candidates. Do not persist unverified discovered endpoints.

## User-facing behavior

Keep the existing selected tab and connection-quality display. During recovery,
the existing subtitle may say “Finding your computer…” and then “Reconnecting…”.
Successful recovery returns to the current controls without a pairing screen.
No extra disconnected banner or new discovery page is needed.

If recovery cannot succeed, provide the existing connection failure plus the
option to scan a fresh QR/manual address. Do not instruct users to delete a
pairing merely because an IP changed. Older servers remain usable through
their saved/explicitly updated address but cannot advertise a new one.

## Verification

Server tests cover identity-only metadata, actual bound port, listener-address
restrictions, advertisement startup failure, and shutdown/withdrawal.
They also cover updating advertisements after an interface address changes
without a server restart.

Client tests exercise:

- A saved address fails, a discovered same-identity server succeeds, and only
  the authenticated endpoint is persisted.
- The old address now has a different certificate, while the original paired
  server is successfully rediscovered elsewhere.
- Forged TXT fingerprints and wrong actual certificates cannot change trust.
- Two paired computers, duplicate services, changing ports, stale cache, and
  malformed/scoped address candidates remain isolated and bounded.
- Disconnect, background, switch, and forget cancel late discovery/resolution
  results and do not replay old input or pairing secrets.
- Denied permission, no multicast, and an old server fail gracefully while
  QR/manual paths and normal saved-address reconnection still work.

Run the existing Flutter analysis/tests and Go tests, plus Linux container
checks. Verify native iOS discovery against a running LAN server. Exercise an
endpoint change with the same certificate in an isolated test setup; do not
change the live Linux PC's network address or router configuration without a
separate reason and recovery path.

## Delivery

Rebuild the iPhone app and desktop installers after review and validation. The
Linux PC needs the updated server for advertisement. Preserve all currently
uncommitted keyboard/input fixes; they are outside this feature's scope.
Use existing authorized installation access, and keep administrator-password
entry on the Linux PC if package installation requires it.

## Builder choices

Choose maintained discovery libraries, bounded timeout/cache values, and the
smallest internal interfaces that support the above tests. These are builder
decisions, not additional user-facing requirements. A native dependency that
needs unavailable Apple entitlements or cannot build for existing targets must
be replaced rather than weakening certificate checks or silently dropping a
platform.
