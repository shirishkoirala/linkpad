//go:build linux

package pointer

import (
	"github.com/jezek/xgb/xproto"
	"testing"
)

func TestKeyboardMapping(t *testing.T) {
	// Four physical keys: a/A, Shift, Control, Return.
	mapping := []xproto.Keysym{'a', 'A', 0xffe1, 0, 0xffe3, 0, 0xff0d, 0}
	strokes, err := keyboardStrokes(mapping, 2, 8, "", "aA", nil)
	if err != nil || len(strokes) != 2 || strokes[0].code != 8 || len(strokes[0].mods) != 0 || len(strokes[1].mods) != 1 || strokes[1].mods[0] != 9 {
		t.Fatalf("bad shifted text: %+v %v", strokes, err)
	}
	strokes, err = keyboardStrokes(mapping, 2, 8, "a", "", []string{"ctrl"})
	if err != nil || strokes[0].mods[0] != 10 {
		t.Fatalf("bad shortcut: %+v %v", strokes, err)
	}
	if _, err = keyboardStrokes(mapping, 2, 8, "", "a😀", nil); err == nil {
		t.Fatal("must reject the entire unmapped string before sending any events")
	}
}

func TestStandaloneSuperMapping(t *testing.T) {
	strokes, err := keyboardStrokes([]xproto.Keysym{0xffeb, 0}, 2, 133, "super", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(strokes) != 1 || strokes[0].code != 133 || len(strokes[0].mods) != 0 {
		t.Fatalf("unexpected standalone Super strokes: %#v", strokes)
	}
}
