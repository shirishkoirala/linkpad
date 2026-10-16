# Input timing

The controller keeps one input message in flight. Movement and scroll deltas
coalesce in the bounded input buffer while waiting for its acknowledgement;
click boundaries and the drag/keyboard lifecycle retain their existing ordering.
Queued input still expires after 150 ms by default. Stalled connections pause
input, and disconnect/background transitions discard queued actions.

A missing acknowledgement pauses input at 150 ms, but the controller waits up
to five seconds before tearing down TLS and reconnecting. This allows a temporary
Wi-Fi or desktop scheduling stall to recover on the same connection. The desktop
drag lease still expires independently after two seconds; the longer transport
timeout does not extend held input. A delayed reply never replays expired actions.

The 16 ms send interval is measured from the previous transmission, not from
its acknowledgement. The first ready input can send immediately. If a response
takes longer than the interval, fresh queued input is eligible immediately on
acknowledgement. Fast replies wait only for the remainder of the interval.
No extra in-flight messages or server protocol changes are introduced.

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

This removes the previous extra frame wait, but the one-in-flight design still
limits throughput on high-latency Wi-Fi. For example, a steady 30 ms round trip
can support roughly 33 updates/s rather than the previous roughly 22 updates/s.
Further improvement on such links needs a separately tested bounded pipeline or
another transport; replaying old input would make control worse.

TLS integration tests hold an acknowledgement beyond the cadence interval and
check prompt flushing, coalesced movement, click ordering, latency reporting,
and reset on disconnect. A separate fast-response test checks rate limiting and
status-notification throttling. Existing stall, timeout, drag, and reconnect
tests cover stale input and release safety.
