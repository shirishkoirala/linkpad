# QR pairing invitation v1

The desktop prints a terminal QR when started with `-pair`. `-pair-qr PATH` also writes a private PNG, refusing to overwrite existing files. No QR or enrollment secret is served over HTTP or sent to a QR-generation service. QR encoding happens locally.

The QR contains a UTF-8 JSON object:

```json
{
  "type": "linkpad-pairing",
  "version": 1,
  "address": "wss://192.0.2.10:4747/ws",
  "fingerprint": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "secret": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "expiresAt": "2099-01-01T00:02:00Z"
}
```

The example credentials are test data. The address must use `wss`, have a host and `/ws` path, and have no user information, query or fragment. Explicit ports must be 1–65535. Fingerprints and secrets are 32 bytes represented by 64 hexadecimal characters. The expiry is a UTC timestamp taken directly from the server's pairing window.

The mobile scanner rejects codes exceeding 4096 UTF-8 bytes, unsupported formats/versions, malformed credentials and expired invitations. Scanning a valid code fills the address, fingerprint and secret, then uses the normal mutual-TLS enrollment path. The scanner does not weaken certificate checks. The server remains authoritative about expiry and single-use consumption. Tokens are not stored in mobile preferences or replayed during automatic reconnects.

The QR must be scanned directly from the computer the user intends to trust. A QR received through an untrusted network does not independently authenticate that computer. Anyone with a copy of a live QR has its enrollment secret; PNG copies should be kept private. A code displayed after the window expires is no longer usable, even if it remains visible in terminal history or a PNG.

An explicit listener address is advertised as written. A wildcard listener chooses an active LAN address, preferring private IPv4 on non-virtual interfaces. On a multi-interface machine, `-advertise wss://LAN-IP:PORT/ws` overrides that choice. A loopback listener's QR is only usable on that computer; use a reachable LAN listener for a phone. QR pairing does not implement mDNS discovery or update previously saved IP addresses.

`testdata/pairing.json` is shared by the Go QR encoder/independent decoder tests and Dart invitation-parser tests.
