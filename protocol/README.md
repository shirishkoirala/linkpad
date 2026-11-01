# Protocol v1

Linkpad uses TLS 1.3 WebSocket connections at `wss://HOST:4747/ws`. Both peers present persistent self-signed certificates and prove private-key possession. Device identity is the lowercase SHA-256 of the DER certificate, not a claimed JSON name. The controller pins the desktop identity acquired through QR/manual verification. Browser Origin headers are denied on the WebSocket endpoint.

The server permits an unknown certificate through TLS only to support initial pairing; application access remains denied until pairing authorizes it. Local discovery supplies untrusted candidate addresses and public identity fingerprints, not permission to control a computer.

## Handshake

1. The operator creates a pairing invitation through the desktop UI or CLI. It has a random 256-bit secret, expires after two minutes and authorizes one device.
2. A new controller sends `{"version":1,"type":"pair","token":"<secret>","capabilities":["pointer.v1"]}`. The server persists its authenticated client-certificate fingerprint before consuming the secret. A trusted controller instead sends `hello` with requested capabilities and no secret.
3. The server responds with `ready` and the intersection of requested and locally enabled, available capabilities. An empty list means a successful trusted connection without usable input capabilities.

Unknown or revoked devices cannot send input. Revocation closes active sessions and removes persisted trust. Input errors produce an `error` response and close the session. Successful input produces `ack`.

## Messages and capabilities

Messages are UTF-8 JSON text frames with `version: 1` and `type`. The Go receiver limits frames to 4096 bytes. There is no screen streaming, arbitrary command execution or downloaded plugin code.

| Capability | Message | Behavior |
| --- | --- | --- |
| `pointer.v1` | `{"version":1,"type":"pointer","dx":10,"dy":-3}` | Relative cursor movement; optional `button` is `left` or `right` and emits a complete click |
| `scroll.v1` | `{"version":1,"type":"scroll","dx":0,"dy":20}` | Two-axis natural scrolling |
| `key.v1` | `{"version":1,"type":"key","key":"up"}` | Complete arrow-key press/release |
| `keyboard.v1` | `{"version":1,"type":"keyboard","key":"a","modifiers":["ctrl"]}` | Named keys, printable shortcuts, or a `text` payload of up to 128 printable Unicode characters; text cannot include modifiers |
| `keyboard.super.v1` | `{"version":1,"type":"keyboard","key":"super"}` | Separately negotiated support for a standalone Windows/Command key |
| `drag.v1` | `{"version":1,"type":"drag","action":"start"}` | Leased left-button hold, move, keepalive and release; see [dragging](drag.md) |
| `media.volume.v1` | `{"version":1,"type":"volume","action":"down"}` | Volume down/up/mute; see [volume](volume.md) |

Pointer, scroll and drag movement deltas are bounded to `[-500,500]`. Keyboard keys and modifiers are validated against supported names. Each native backend applies its platform's permission and layout limits; capabilities must be negotiated before dispatch.

## Ordering and timing

The controller allows up to four plain movement messages in flight, with a 16 ms transmission cadence. Other input waits for ordered acknowledgement barriers. Input is bounded and stale motion expires; queued keyboard and control actions follow their own ordering rules. Clicks are not intentionally discarded merely because movement is awaiting acknowledgement. See [input timing](../mobile/INPUT-LATENCY.md) for the client's current stall budgets and response timeout.

ACKs match messages in WebSocket order. There are no request IDs or exactly-once delivery guarantees. Already transmitted input cannot be recalled, and input whose acknowledgement was lost is not automatically replayed. Reconnect verifies the same identity and renegotiates capabilities.

The Flutter client sends an idle heartbeat every 15 seconds while active. A subsequent `hello` returns `ack`. The server permits 90 seconds between application messages, with a 10-second initial handshake deadline and 5-second write deadline. It currently sleeps 10 ms after each input acknowledgement per connection; this is per-connection pacing, not a global abuse quota. The drag lease expires independently, normally after two seconds without renewal.

Input ACKs may include `server_processing_us`, a nonnegative integer measuring management-lock wait and native execution. It excludes socket reads, earlier pacing sleeps and ACK transmission. Older peers may omit or ignore it. The client labels the remainder after subtracting this value from the same ACK's round trip as network plus queues, not a network-only ping.

## Specifications

- [JSON Schema](v1/message.schema.json) documents wire shape; it is not loaded at runtime.
- [Pairing invitations](pairing.md) document QR payloads and trust.
- [Dragging](drag.md) documents ownership, leases and disconnect cleanup.
- [Volume](volume.md) documents media controls.

Runtime tests cover validation and real TLS/WebSocket sessions. New capabilities must update the dispatcher, schema and peer tests together while preserving older peers.
