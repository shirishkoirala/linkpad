# Run Linkpad automatically on Linux desktop login

This setup runs Linkpad as your desktop user and restarts it at each graphical login with the current X11 display credentials. It avoids keeping a system service attached to an old desktop session after logout.

## Requirements

- An X11 desktop session. Wayland and login-screen control are not supported by the current backend.
- The Linux executable installed at `/usr/local/bin/linkpad`. Change `ExecStart` below if you installed it elsewhere.
- An existing phone pairing. The service does not open a pairing window.

Run the commands below from a terminal inside your logged-in Linux desktop. Use your normal user account; only disabling the old system service requires `sudo`.

## 1. Disable the old system service

```bash
sudo systemctl disable --now linkpad.service
mkdir -p ~/.config/systemd/user ~/.config/autostart
```

If your old service has a different name, substitute that name in the first command.

Keep the existing Linkpad identity and trust files. The default state directory is `~/.config/linkpad`, or `$XDG_CONFIG_HOME/linkpad` if configured. If your old service used another state directory, add `-state /path/to/existing/state` to `ExecStart` and ensure your user can access it. Reusing the same state preserves existing phone pairings.

## 2. Create the user service

Save this as `~/.config/systemd/user/linkpad.service`:

```ini
[Unit]
Description=Linkpad remote input server
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/linkpad -listen 0.0.0.0:4747 -allow-pointer
Restart=on-failure
RestartSec=3
```

Do not add `User=` or `Group=`: a user service already runs as your account. Do not hardcode `DISPLAY=:0` or an `XAUTHORITY` path; the login step below imports the current session's values.

`PartOf=graphical-session.target` stops the service with the graphical session on desktops that manage that target. The autostart entry below explicitly restarts Linkpad at each desktop login, including desktops that do not manage that target.

## 3. Create the desktop autostart entry

Save this as `~/.config/autostart/linkpad.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Linkpad
Exec=sh -c "systemctl --user import-environment DISPLAY XAUTHORITY; systemctl --user restart linkpad.service"
Terminal=false
```

At each login, this imports your desktop's display credentials into the user service manager and restarts Linkpad. This is necessary because the process can remain alive while its old X11 connection no longer works.

The autostart entry starts the service; a separate `systemctl --user enable` command is not needed. If your desktop does not process XDG autostart entries, add the same command to its session startup settings.

## 4. Start it now

```bash
systemctl --user daemon-reload
systemctl --user import-environment DISPLAY XAUTHORITY
systemctl --user restart linkpad.service
systemctl --user status linkpad.service
```

Reconnect from the already-paired phone. After logging out and back in, the autostart entry will restart Linkpad for the new desktop session.

## Listening address and phone connection

`0.0.0.0:4747` tells the server to accept connections on all network interfaces. It is not the address to enter on the phone. Use the Linux PC's reachable LAN address, for example `wss://192.168.1.202:4747/ws`.

Find the current address with:

```bash
hostname -I
```

Both devices must be able to reach each other over the network, and the Linux firewall must allow inbound TCP port 4747 from the phone.

## Troubleshooting

Read recent server logs:

```bash
journalctl --user -u linkpad.service -b -n 100 --no-pager
```

Check the current desktop session:

```bash
echo "$XDG_SESSION_TYPE"
echo "$DISPLAY"
echo "$XAUTHORITY"
```

The session type must be `x11`, and `DISPLAY` must be set. `XAUTHORITY` can be unset when X11 uses its default authority location.

If the phone connects but returns to computer selection when you move the pointer, the first input command may be failing against a stale X11 connection. From a fresh terminal in your desktop session, run:

```bash
systemctl --user import-environment DISPLAY XAUTHORITY
systemctl --user restart linkpad.service
```

Use `systemctl --user` for this service, without `sudo`. Restarting the process refreshes its X11 connection; `Restart=on-failure` alone cannot fix a stale connection while the process remains alive.

This configuration does not enable control before login. Supporting the login screen requires a different input backend and service architecture.
