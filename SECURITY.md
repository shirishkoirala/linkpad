# Security

Linkpad has not had an independent security audit. Do not expose its listener to the public internet.

## Connections and trust

Connections use TLS 1.3 with mutual proof of private-key possession. The controller verifies the exact desktop certificate fingerprint and certificate validity dates instead of relying on a public certificate authority. QR pairing transfers the expected fingerprint and a random 256-bit secret directly from the desktop; verify manual details through a trusted channel.

The server permits an unknown self-signed certificate through TLS only so it can request pairing. Input requires successful application-level authentication and capability negotiation. Pairing is opt-in, single-use and expires after two minutes. Discovery exposes public identity/address information, never a pairing secret, and does not authorize a device.

The command-line listener defaults to loopback. The graphical desktop app starts a LAN listener on TCP 4747. Use a trusted local network and appropriate firewall rules.

## Revocation and local state

Revoking a phone from the desktop app removes its persisted trust, closes its active sessions and releases its held input immediately. A restart is not required for this management action. Removing a computer from the phone only forgets that saved connection; it does not revoke desktop trust. Stop the server before manually editing state files.

Desktop private keys are stored in the user's configuration directory. The mobile private identity uses platform secure storage, but the key is loaded into application memory. A process or attacker with access as the same user may be able to read keys or modify trust. State corruption fails closed. Automatic certificate renewal and multi-process coordination of shared state are not implemented.

All locally enabled capabilities are available to a trusted peer after negotiation; finer per-device permissions are not implemented. Unknown connections can still consume resources during TLS and onboarding, and there is no global admission quota. Keep pairing secrets and private keys private.

Native input obeys operating-system session and permission limits. Windows secure desktops and administrator apps, macOS Accessibility restrictions, and unsupported Linux sessions are not bypassed.

## Report a vulnerability

Email **shirishkoirala@gmail.com** with the affected version/platform, a description and reproduction steps. Do not post sensitive details in a public issue before contacting the maintainer, and never include private keys, pairing secrets or unrelated personal data.
