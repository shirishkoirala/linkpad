# Security

This experimental implementation has not had an independent security audit. TLS encryption alone does not establish the intended device: verify the SHA-256 desktop fingerprint through a trusted channel before entering the pairing secret. Neither native client uses generic trust-all TLS; hostname validation is replaced by exact certificate identity pinning. Both peers prove private-key possession during TLS 1.3.

Pairing is opt-in, expires in two minutes and consumes a cryptographically random 256-bit secret once. The listener defaults to loopback. Pointer control is opt-in and negotiated after trust verification. Existing trust grants all enabled capabilities; finer permission policy is future work. The server does not authenticate unknown certificates at TLS level against a CA because onboarding uses self-signed peer certificates; it authenticates them at the application handshake before granting capabilities.

Unknown connections can still consume TLS/session resources. No global admission quota, multi-process trust coordination or hardware-protected desktop key exists. State corruption fails closed, but filesystem attackers running as the same user can read the desktop key or edit trust. Stop/restart is required for revocation. Expired certificates fail connections; automatic renewal is absent.

Do not expose the listener to the public internet. When reporting a vulnerability, do not publish secrets/private keys. A private reporting contact will be added when the repository owner and hosting are selected; this scaffold cannot provide a working reporting address yet.
