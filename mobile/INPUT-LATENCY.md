# Input timing

The controller permits up to four plain movement messages in flight, paced at
16 ms between sends. Pending deltas still coalesce in a bounded input buffer.
Clicks, scrolling, keyboard actions, and drag operations wait for outstanding
movement replies; subsequent movement waits for these actions to be acknowledged.
WebSocket ordering and FIFO acknowledgement timestamps retain action boundaries.
No server protocol change is required.

Queued input still expires after 150 ms by default. Stalled connections pause
input, and disconnect/background transitions discard queued actions.

A missing acknowledgement pauses input after at least 500 ms. The pause budget
adapts to three times the smoothed round trip, capped at one second. The controller
waits up to five seconds before tearing down TLS and reconnecting. This allows a temporary
Wi-Fi or desktop scheduling stall to recover on the same connection. The desktop
drag lease still expires independently after two seconds; the longer transport
timeout does not extend held input. A delayed reply never replays expired actions.

Response tolerance and event freshness are separate limits. A roughly 284 ms
round trip must not repeatedly disable the touchpad just because events older
than 150 ms are stale. Below the pause threshold, a late acknowledgement keeps
fresh queued input and expires older events by their own timestamps. At or beyond
the pause threshold, queued input is discarded and the active drag is cancelled.

The 16 ms send interval is measured from the previous transmission, not from
its acknowledgement. The first ready input can send immediately. If a response
takes longer than the interval, fresh queued input is eligible immediately on
acknowledgement when the movement window is full. Fast replies wait only for
the remainder of the interval. Timers follow the oldest outstanding message;
additional sends cannot postpone a stall or timeout. After a stall, all outstanding
replies must drain before controls resume, and buffered input is discarded.

The phone's connection status displays a smoothed acknowledgement round trip
after the first response. This includes network travel, server scheduling and
input processing; it is not a network-only ping. The estimate gives the newest
sample one-quarter weight after the initial sample. Status redraws are limited
to once per second during steady input; connection/stall transitions still
notify immediately. Estimates and cadence state reset when the transport closes.
While input is paused, the header omits the previous healthy response-time sample.
Long-press the Wi-Fi icon for the reconnect-attempt count and last interruption
reason. These survive automatic reconnects and reset when starting a new manual
connection or disconnecting.

The touchpad retains live finger identities while input is paused, including
contacts placed during reconnection. It tracks positions without emitting input.
After recovery, the first movement establishes a new baseline and subsequent
movement/scroll events resume without requiring another touch-down. Interrupted
contacts cannot generate tap clicks, and cancelled/released contacts are removed
normally. The touchpad keeps a stable widget identity when the reconnect warning
changes the layout, and deltas use screen coordinates to avoid layout-induced
cursor jumps. Cancelled button drags still require a fresh button press.

At 284 ms round-trip latency, four movements in flight allow roughly 14 movement
updates/s instead of roughly 3.5. This is a throughput estimate, not a reduction
in the network travel time. The window is deliberately small to bound input that
has already entered TCP and cannot be recalled during a network stall.

TLS integration tests hold an acknowledgement beyond the cadence interval and
check prompt flushing, coalesced movement, click ordering, latency reporting,
and reset on disconnect. A separate fast-response test checks rate limiting and
status-notification throttling. Existing stall, timeout, drag, and reconnect
tests cover stale input and release safety.

Additional TLS tests verify the four-message bound, click barriers, complete
window draining after a stall, and adaptation to a measured slow round trip.

## Connection diagnostics

Long-press the Wi-Fi icon to inspect response timing. Peak response, replies
at or above 250 ms, and input-pause counts describe the current transport and
reset on reconnect. Reconnect-attempt counts and the last interruption reason
continue across automatic retries. No input content is recorded.

Updated servers add optional `server_processing_us` metadata to input ACKs.
It measures management-lock wait and native input execution, excluding socket
reading, earlier server throttling, and ACK transmission. The phone smooths
this timing and the same response's remaining delay separately. The remainder
includes network travel, transport queues, and desktop/client scheduling; it
is not a pure network RTT. These values help locate delays but do not identify
a faulty cable, NIC, or router by themselves.

Older peers remain compatible. Without server metadata, the phone still shows
response diagnostics and says desktop processing timing is unavailable. Invalid
or impossible optional timings are ignored without interrupting control.
