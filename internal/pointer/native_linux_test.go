//go:build linux

package pointer

import (
	"os"
	"testing"
	"time"

	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
)

// Only run against an explicitly requested virtual display. Normal tests must
// never inject mouse/keyboard events into the developer's live desktop.
func TestX11VirtualDisplayIntegration(t *testing.T) {
	if os.Getenv("LINKPAD_X11_INTEGRATION") != "1" {
		t.Skip("set LINKPAD_X11_INTEGRATION=1 under xvfb-run")
	}
	if !Available() {
		t.Fatal(AvailabilityError())
	}
	viewer, err := xgb.NewConn()
	if err != nil {
		t.Fatal(err)
	}
	defer viewer.Close()
	screen := xproto.Setup(viewer).DefaultScreen(viewer)
	window, err := xproto.NewWindowId(viewer)
	if err != nil {
		t.Fatal(err)
	}
	mask := uint32(xproto.EventMaskButtonPress | xproto.EventMaskButtonRelease | xproto.EventMaskKeyPress | xproto.EventMaskKeyRelease)
	if err = xproto.CreateWindowChecked(viewer, screen.RootDepth, window, screen.Root, 0, 0, 640, 480, 0, xproto.WindowClassInputOutput, screen.RootVisual, xproto.CwEventMask, []uint32{mask}).Check(); err != nil {
		t.Fatal(err)
	}
	defer xproto.DestroyWindow(viewer, window)
	if err = xproto.MapWindowChecked(viewer, window).Check(); err != nil {
		t.Fatal(err)
	}
	if err = xproto.SetInputFocusChecked(viewer, xproto.InputFocusPointerRoot, window, xproto.TimeCurrentTime).Check(); err != nil {
		t.Fatal(err)
	}
	if err = xproto.WarpPointerChecked(viewer, 0, screen.Root, 0, 0, 0, 0, 100, 100).Check(); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if err = native(10, 5, ""); err != nil {
			t.Fatal(err)
		}
	}
	position, err := xproto.QueryPointer(viewer, screen.Root).Reply()
	if err != nil || position.RootX != 120 || position.RootY != 110 {
		t.Fatalf("relative cursor: %v %v", position, err)
	}
	if err = native(0, 0, "left"); err != nil {
		t.Fatal(err)
	}
	if err = native(0, 0, "right"); err != nil {
		t.Fatal(err)
	}
	if err = nativeScroll(0, 40); err != nil {
		t.Fatal(err)
	}
	if err = nativeScroll(-40, 0); err != nil {
		t.Fatal(err)
	}
	if err = nativeKey("up"); err != nil {
		t.Fatal(err)
	}
	var buttons []byte
	var keyDown, keyUp byte
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) && (len(buttons) < 8 || keyUp == 0) {
		event, pollErr := viewer.PollForEvent()
		if pollErr != nil {
			t.Fatal(pollErr)
		}
		switch e := event.(type) {
		case xproto.ButtonPressEvent:
			buttons = append(buttons, byte(e.Detail))
		case xproto.ButtonReleaseEvent:
			buttons = append(buttons, byte(e.Detail))
		case xproto.KeyPressEvent:
			keyDown = byte(e.Detail)
		case xproto.KeyReleaseEvent:
			keyUp = byte(e.Detail)
		}
		if event == nil {
			time.Sleep(5 * time.Millisecond)
		}
	}
	want := []byte{1, 1, 3, 3, 4, 4, 7, 7}
	if len(buttons) != len(want) {
		t.Fatalf("button events: %v", buttons)
	}
	for i, button := range buttons {
		if button != want[i] {
			t.Fatalf("button order: %v", buttons)
		}
	}
	if keyDown == 0 || keyUp != keyDown {
		t.Fatalf("unbalanced key: %d %d", keyDown, keyUp)
	}
	position, err = xproto.QueryPointer(viewer, screen.Root).Reply()
	if err != nil {
		t.Fatal(err)
	}
	if position.Mask&(xproto.ButtonMask1|xproto.ButtonMask3|xproto.ButtonMask4|xproto.ButtonMask5) != 0 {
		t.Fatal("button left held")
	}
}
