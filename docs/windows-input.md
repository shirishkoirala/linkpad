# Windows desktop input

1 November 2026: the maintainer tested the Windows command-line server on a physical PC and reported all requested input controls working. Initial pairing failed because the Windows clock was wrong; correcting date/time resolved it. Automated native Windows CI results are tracked separately from this hands-on test.

Native Windows input CI passed in [run 41291427811](https://github.com/shirishkoirala/linkpad/actions/runs/41291427811). The Windows GUI and installer smoke test passed in [run 41291493315](https://github.com/shirishkoirala/linkpad/actions/runs/41291493315): installation, visible window, bundled server startup and helper shutdown. Download the `desktop-Windows` artifact from that run. The installer is unsigned; physical GUI/tray/start-at-login checks remain pending.

The Go server now includes a Windows `SendInput` backend. It supports relative mouse movement, complete left/right clicks, leased left-button dragging, natural vertical/horizontal scrolling, arrow keys, Unicode text, keyboard shortcuts, the Windows key, and volume up/down/mute.

## Build and run

On Windows with the Go version required by `go.mod`:

```powershell
go build -o linkpad-windows-x86_64.exe ./cmd/linkpad
.\linkpad-windows-x86_64.exe -listen 0.0.0.0:4747 -pair -allow-pointer
```

Run as the logged-in desktop user. Allow the server on your trusted private network in Windows Firewall when prompted; the phone needs access to TCP 4747. Pair with the displayed QR code as on other platforms. Keep pairing secrets private.

For the graphical app, run `flutter build windows --release` from `mobile/`. The Windows runner bundles the Go helper automatically. The per-user installer and GitHub Actions job are documented in [PACKAGING.md](../PACKAGING.md). The command-line executable remains available separately.

## Session and permission limits

- Input requires an accessible interactive Default desktop. Lock screens, UAC secure desktops and Session 0 services are not supported.
- Windows integrity protection prevents a standard-permission server from controlling apps running as administrator. Input failures report this limitation; the backend does not bypass it.
- Windows secure-attention shortcuts such as Ctrl+Alt+Delete cannot be synthesized with SendInput.
- Text uses UTF-16 Unicode events, including surrogate pairs. Printable shortcut keys use the foreground window's keyboard layout. App-specific handling of Unicode and media keys still needs physical-device testing.
- Modifiers are released in reverse order. Modifiers already physically held are left alone, and partial SendInput failures attempt to release only injected presses. Existing server drag ownership, timeout and disconnect cleanup also apply.
- If a secure desktop blocks a drag release, the backend remembers it and retries before accepting input when the normal desktop becomes available again.

## Automated verification

Portable command-translation tests run in the ordinary Go suite on every platform. They cover movement, complete clicks, scroll direction, Unicode, modifier ordering, Windows/media key codes and partial-send cleanup. Windows-specific tests check the native INPUT union size/alignment and keyboard-layout lookup. The Windows CI job also opts into a native desktop smoke test.

The smoke test moves the cursor and sends input. Only set `LINKPAD_WINDOWS_INTEGRATION=1` in an isolated test desktop.

### Docker with Wine

Docker on macOS runs Linux containers, not a Windows kernel. Wine supplies the Windows APIs; Xvfb provides an isolated display. These tests do not control your host desktop and do not prove physical Windows behavior.

From the repository root:

```sh
mkdir -p bin/windows-input-test
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go test -c -o bin/windows-input-test/pointer.test.exe ./internal/pointer
docker build --platform linux/amd64 -f mobile/tool/windows-input.Dockerfile -t linkpad-windows-input-test bin/windows-input-test
docker run --rm --platform linux/amd64 linkpad-windows-input-test
```

On this Apple Silicon host, Wine 9 started under Xvfb but the Windows executable failed before running tests with `rosetta error: invalid gdt selector index 5`. The Wine integration check is therefore **not passed**. Run it on an x86_64 Linux Docker host, or use the native Windows CI job. The Docker image does not mount the host display or alter Docker's global emulation settings.

On a Linux container with Go installed, `go test -race ./...` also exercises the portable Windows command translation. Real Windows testing remains required for cursor feel, Unicode in applications, media controls, firewall/discovery, reconnection, elevated-app errors, and disconnect recovery while dragging.
