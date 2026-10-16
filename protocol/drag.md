# Dragging (`drag.v1`)

The phone requests `drag.v1` in its hello/pair capabilities. The desktop advertises it only when input is enabled and the native backend is available. Existing `pointer.v1` click messages remain complete press/release pairs.

## Messages

Press and hold the left mouse button:

```json
{"version":1,"type":"drag","action":"start"}
```

Move the pointer while the button remains held:

```json
{"version":1,"type":"drag","action":"move","dx":20,"dy":10}
```

Renew a stationary hold:

```json
{"version":1,"type":"drag","action":"hold"}
```

Release the button:

```json
{"version":1,"type":"drag","action":"end"}
```

Each message receives the normal `ack`. Only movement messages may contain deltas, each bounded to `[-500,500]`. Drag messages cannot include a separate button, keyboard key, text, or modifiers.

## Ownership and cleanup

- One WebSocket session owns a held button. Another session cannot release it or acquire it until it is released.
- Pointer and scroll input from other sessions is ignored during the hold, while those sessions remain connected.
- The desktop releases the button when the owner disconnects, an input operation fails, or its drag lease expires. The default lease is two seconds after the last start, move, or hold message.
- The phone sends stationary hold messages every 500 ms. It cancels its drag when input stalls, the app leaves the foreground, or the transport closes. It never restores a held state after reconnecting.
- Release messages are handled separately from expiring motion and keyboard queues, so an outstanding release is not dropped merely because it ages out.

## Mobile interaction

Hold **Left click** with one finger and move another finger on the touchpad. Release **Left click** to drop. A quick tap still performs a normal click. Cancelled contacts release an active hold without adding an extra click.

The app preserves ordinary clicks on older desktop servers. Both the app and desktop server must be updated to support dragging. Cursor sensitivity also applies to drag movement; scrolling remains separate.
