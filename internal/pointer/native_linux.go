//go:build linux

package pointer

import (
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
	"github.com/jezek/xgb/xtest"
)

var linuxInput struct {
	once    sync.Once
	backend *x11Input
	err     error
}

func initializeX11() {
	if strings.EqualFold(os.Getenv("XDG_SESSION_TYPE"), "wayland") {
		linuxInput.err = fmt.Errorf("Wayland input is not supported; log into an X11 desktop session")
		return
	}
	if os.Getenv("DISPLAY") == "" {
		linuxInput.err = fmt.Errorf("DISPLAY is not set; run Linkpad as your desktop user in a terminal inside the X11 session")
		return
	}
	conn, err := xgb.NewConn()
	if err != nil {
		linuxInput.err = fmt.Errorf("cannot access X11 display: %w; run as the desktop user with its DISPLAY and XAUTHORITY", err)
		return
	}
	if err = xtest.Init(conn); err != nil {
		conn.Close()
		linuxInput.err = fmt.Errorf("X11 XTEST extension unavailable: %w", err)
		return
	}
	if _, err = xtest.GetVersion(conn, 2, 2).Reply(); err != nil {
		conn.Close()
		linuxInput.err = fmt.Errorf("X11 XTEST initialization failed: %w", err)
		return
	}
	linuxInput.backend = &x11Input{
		emit: func(event x11Event) error {
			return xtest.FakeInputChecked(conn, event.kind, event.detail, 0, 0, event.dx, event.dy, 0).Check()
		},
		keycode: func(key string) (byte, error) {
			wanted := map[string]xproto.Keysym{"left": 0xff51, "up": 0xff52, "right": 0xff53, "down": 0xff54}[key]
			setup := xproto.Setup(conn)
			count := byte(int(setup.MaxKeycode) - int(setup.MinKeycode) + 1)
			mapping, err := xproto.GetKeyboardMapping(conn, setup.MinKeycode, count).Reply()
			if err != nil {
				return 0, fmt.Errorf("read X11 keyboard map: %w", err)
			}
			width := int(mapping.KeysymsPerKeycode)
			if width > 0 {
				// Use a base-level symbol so no modifier keys need to be held.
				for index := 0; index < len(mapping.Keysyms); index += width {
					if mapping.Keysyms[index] == wanted {
						return byte(int(setup.MinKeycode) + index/width), nil
					}
				}
			}
			return 0, fmt.Errorf("arrow key %s is unavailable in the X11 keyboard map", key)
		},
	}
}

func AvailabilityError() error { linuxInput.once.Do(initializeX11); return linuxInput.err }
func Available() bool          { return AvailabilityError() == nil }

func native(dx, dy int, button string) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return linuxInput.backend.move(dx, dy, button)
}
func nativeScroll(dx, dy int) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return linuxInput.backend.scroll(dx, dy)
}
func nativeKey(key string) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return linuxInput.backend.pressKey(key)
}
