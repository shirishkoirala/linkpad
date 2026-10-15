//go:build linux

package pointer

import (
	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
	"os"
	"testing"
	"time"
)

func TestKeyboardX11Integration(t *testing.T) {
	if os.Getenv("LINKPAD_X11_INTEGRATION") != "1" {
		t.Skip("requires an isolated Xvfb display")
	}
	conn, err := xgb.NewConn()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	screen := xproto.Setup(conn).DefaultScreen(conn)
	window, err := xproto.NewWindowId(conn)
	if err != nil {
		t.Fatal(err)
	}
	if err = xproto.CreateWindowChecked(conn, screen.RootDepth, window, screen.Root, 0, 0, 200, 200, 0, xproto.WindowClassInputOutput, screen.RootVisual, xproto.CwEventMask, []uint32{xproto.EventMaskKeyPress | xproto.EventMaskKeyRelease}).Check(); err != nil {
		t.Fatal(err)
	}
	defer xproto.DestroyWindow(conn, window)
	if err = xproto.MapWindowChecked(conn, window).Check(); err != nil {
		t.Fatal(err)
	}
	if err = xproto.SetInputFocusChecked(conn, xproto.InputFocusPointerRoot, window, xproto.TimeCurrentTime).Check(); err != nil {
		t.Fatal(err)
	}
	if err = nativeKeyboard("", "aA", nil); err != nil {
		t.Fatal(err)
	}
	if err = nativeKeyboard("c", "", []string{"ctrl"}); err != nil {
		t.Fatal(err)
	}
	if err = nativeKeyboard("enter", "", nil); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	presses, releases := 0, 0
	shifted, controlled := false, false
	for time.Now().Before(deadline) && releases < 6 {
		event, err := conn.PollForEvent()
		if err != nil {
			t.Fatal(err)
		}
		switch e := event.(type) {
		case xproto.KeyPressEvent:
			presses++
			shifted = shifted || e.State&xproto.ModMaskShift != 0
			controlled = controlled || e.State&xproto.ModMaskControl != 0
		case xproto.KeyReleaseEvent:
			releases++
		}
		if event == nil {
			time.Sleep(time.Millisecond)
		}
	}
	if presses != 6 || releases != 6 || !shifted || !controlled {
		t.Fatalf("unbalanced keys or missing modifiers: presses=%d releases=%d shift=%v ctrl=%v", presses, releases, shifted, controlled)
	}
}
