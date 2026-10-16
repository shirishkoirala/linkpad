//go:build linux

package pointer

import (
	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
	"os"
	"testing"
)

func TestDragX11Integration(t *testing.T) {
	if os.Getenv("LINKPAD_X11_INTEGRATION") != "1" {
		t.Skip("requires isolated Xvfb display")
	}
	conn, err := xgb.NewConn()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	root := xproto.Setup(conn).DefaultScreen(conn).Root
	query := func() *xproto.QueryPointerReply {
		p, err := xproto.QueryPointer(conn, root).Reply()
		if err != nil {
			t.Fatal(err)
		}
		return p
	}
	before := query()
	if err = nativeDrag("start", 0, 0); err != nil {
		t.Fatal(err)
	}
	defer nativeDrag("end", 0, 0)
	if query().Mask&xproto.ButtonMask1 == 0 {
		t.Fatal("left button was not held")
	}
	if err = nativeDrag("move", 20, 10); err != nil {
		t.Fatal(err)
	}
	moved := query()
	if moved.Mask&xproto.ButtonMask1 == 0 || moved.RootX != before.RootX+20 || moved.RootY != before.RootY+10 {
		t.Fatalf("movement did not retain hold: %+v", moved)
	}
	if err = nativeDrag("end", 0, 0); err != nil {
		t.Fatal(err)
	}
	if query().Mask&xproto.ButtonMask1 != 0 {
		t.Fatal("left button stuck after release")
	}
}
