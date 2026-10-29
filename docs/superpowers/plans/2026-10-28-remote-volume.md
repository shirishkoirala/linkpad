# Remote system volume controls

**Goal:** Replace Remote modifiers with Volume down / Mute / Volume up while keeping modifiers in Keyboard and the larger adaptive touchpad.
**Architecture:** Negotiate `media.volume.v1` separately. Send `{version:1,type:"volume",action:"up"|"down"|"mute"}` through the existing ordered, bounded command queue. The server validates and dispatches to native system media keys: macOS system-defined media events, Linux X11 XF86 audio keys. Unsupported servers disable the row with an update tooltip.
**Constraints:** No changes to keyboard shortcuts in Keyboard; no replay after reconnect; no shell-generated audio commands; no new divider lines; retain compact layout.

- [x] Protocol and native backends: strict validation, capability-gated dispatch, native mapping and tests.
- [x] Client and Remote: negotiated volume support, bounded queue; replace modifiers; update obsolete Remote tests and preserve Keyboard tests.
- [x] Verify Go race tests, Flutter tests/analyzer, macOS native build and Linux X11 tests. Review before packaging/installing updated clients and servers.

Review focus: unsupported/old servers must not receive volume; mute is single-shot; held volume actions must stop on release/disconnect; no modifier state in Remote; touchpad keeps spare space.

## Verification and delivery

- Independent volume review found no actionable issues in protocol gating, native media key mappings, or modifier separation.
- Added a RED→GREEN slow-ACK regression after review: held volume repeats skip busy transport/queued work, preventing delayed bursts; ordinary taps remain ordered.
- macOS: Go race suite and vet passed; Flutter suite 148 passed, one existing platform skip; analyzer clean; macOS and iOS release builds passed.
- Linux x86_64: Go race/X11 checks passed, including real volume press/release symbols; Flutter 149 passed serially, analyzer clean, native desktop startup/shutdown and dependencies passed.
- Earlier wall-clock tests were interrupted by host sleep; final runs used a temporary caffeinate assertion. Linux parallel emulation hit the known computer-switch timing fixture; the final serial suite passed without production timeout changes.
- Installed/launched updated Mac receiver and iPhone 16 Pro. The Mac still reports Accessibility access needs attention; no permission changes were made automatically.
- iPhone 15 Pro Max unavailable; Linux PC at 192.168.1.203 unreachable over SSH. Linux installer prepared at bin/releases/linkpad_0.1.0_amd64.deb; no claim of installing on offline devices.
- No commit requested. Prior D-pad compact layout changes remain included in the working tree.
