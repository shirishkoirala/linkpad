# Saved computers

Linkpad can remember multiple computers on the same phone. Open **Computers** from the control screen to disconnect from the current computer and choose another one.

## Pair and connect

- Tap **Pair another computer** and scan a fresh pairing QR code from that computer. Existing saved computers stay in the list.
- Manual pairing is available under **Enter pairing details**.
- A computer is saved after its certificate is verified and the desktop handshake succeeds. A failed connection is not saved.
- Tap **Connect** on a saved computer to reconnect without a pairing secret. The app starts at the chooser rather than automatically connecting to the last computer.
- Only one computer is controlled at a time. Switching closes the old WebSocket session and clears held input. The desktop releases that session's held mouse button on disconnect or drag-lease expiry.

## Names and forgetting

Open a computer's three-dot menu to **Rename** or **Forget** it. The default name is its network host; custom names survive reconnects and verified address updates. The list shows the most recently used computers first, without claiming they are currently online.

**Forget** removes the saved connection from this phone. It does not revoke the phone's access on the desktop, erase the phone's identity, or affect other saved computers. Desktop trust must be removed separately if access needs to be revoked.

## Storage and migration

Saved names, addresses, certificate fingerprints and last-used times live in platform secure storage under `computers_v1`. Pairing secrets are not saved. The phone continues to use its existing `peer_identity_v1` identity across computers.

The previous single saved desktop (`desktop_v1`) migrates automatically into the list. The new list is written before the legacy entry is removed. An empty new list remains authoritative, so forgetting the last computer cannot restore an old pairing on the next launch.

Computer identity is its verified certificate fingerprint. Pairing again with the same fingerprint updates the address while preserving the name. A different fingerprint is a different saved computer, even if the IP address matches; connecting to an existing entry still verifies its exact pin.

If saved data cannot be read, the app displays a warning and does not overwrite it. If a write fails, current changes remain available in memory and **Try again** retries saving them.

Nearby computers are discovered separately from saved trust. Selecting a discovered server still requires QR/manual pairing; discovering a saved identity after an address change still requires its pinned certificate. See [the mobile guide](README.md) and [desktop setup](../DESKTOP.md).
