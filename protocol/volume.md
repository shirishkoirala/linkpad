# System volume (`media.volume.v1`)

The phone requests this capability independently of keyboard support. Updated
receivers advertise it when native desktop input is enabled. A client must not
send volume messages unless the receiver negotiated this capability.

Messages use `{"version":1,"type":"volume","action":"down"}` with `up`, `down`,
or `mute`. Mute toggles the system mute state. No movement, text, keyboard key,
button, or modifier fields are allowed. Actions use the ordinary ordered ACK
barriers and bounded queue; reconnect clears pending commands.

macOS sends system-defined media key down/up events. Linux X11 sends
XF86AudioLowerVolume, XF86AudioMute, or XF86AudioRaiseVolume using XTest; the
active desktop session handles the system volume and its normal HUD. Both
backends balance press/release events. No shell commands or audio service
credentials are sent over the network.

Remote replaces its modifier row with these controls. Ctrl/Alt/Shift/Win/Command
remain in Keyboard. Unsupported receivers show disabled controls with an update
tooltip. Volume up/down can repeat while held; repeats are skipped while a reply or prior command is pending, preventing delayed bursts after release. Mute never repeats.
