# Nearby computers implementation plan

**Goal:** Show unpaired LAN servers in the computer list and pair using the existing QR flow.
**Architecture:** Reuse validated Bonjour discovery in a separate bounded browse session; never trust advertisements for authentication. A dedicated widget owns scanning and lifecycle, filters saved identities, and offers QR pairing.
**Constraints:** Preserve pinned recovery; no advertised secrets; no automatic pairing; do not commit existing work.

- [x] Add browse API with metadata validation, identity-aware deduplication and regression tests; preserve find behavior.
- [x] Add Nearby computers widget with refresh, empty/error states, saved filtering and lifecycle cancellation; test selection and deletion visibility.
- [x] Integrate QR pairing, requiring the selected identity to match the scanned invitation.
- [x] Run Flutter tests and analyzer; inspect the final diff.

## Verification and review

- Flutter suite: 137 passed, one existing skipped test (`flutter test --concurrency=1`).
- Independent review found address-based result limits could hide an unpaired identity. Added a failing regression and fixed browse to deduplicate identities before the result limit; pinned recovery preserves address candidates.
- Controller integration verifies selection opens pairing and manual entry receives the discovered address without automatically connecting or saving trust.
- Existing first-run test updated to scroll past the nearby section on a narrow phone.
- No commit requested; all existing discovery changes preserved.
