package pointer

import (
	"errors"
	"reflect"
	"testing"
	"unicode/utf16"
)

func recordingWinInput() (*winInput, *[][]winEvent) {
	batches := new([][]winEvent)
	return &winInput{send: func(e []winEvent) (int, error) {
		*batches = append(*batches, append([]winEvent(nil), e...))
		return len(e), nil
	}, mapRune: func(r rune) (uint16, byte, error) {
		if r == 'A' {
			return 0x41, 1, nil
		}
		if r == 'a' {
			return 0x41, 0, nil
		}
		return 0, 0, errors.New("unmapped rune")
	}}, batches
}

func TestWindowsMouseScrollAndDragEvents(t *testing.T) {
	w, batches := recordingWinInput()
	if err := w.move(-17, 9, "right"); err != nil {
		t.Fatal(err)
	}
	want := []winEvent{{kind: winMouse, dx: -17, dy: 9, flags: winMove}, {kind: winMouse, flags: winRightDown}, {kind: winMouse, flags: winRightUp}}
	if !reflect.DeepEqual((*batches)[0], want) {
		t.Fatalf("movement/click: %+v", *batches)
	}
	if err := w.scroll(40, -20); err != nil {
		t.Fatal(err)
	}
	e := (*batches)[1]
	if len(e) != 2 || e[0].flags != winWheel || int32(e[0].data) != -60 || e[1].flags != winHWheel || int32(e[1].data) != -120 {
		t.Fatalf("natural wheel directions: %+v", e)
	}
	for _, a := range []string{"start", "hold", "move", "end"} {
		if err := w.drag(a, 0, 0); err != nil {
			t.Fatal(err)
		}
	}
	if len(*batches) != 4 || (*batches)[2][0].flags != winLeftDown || (*batches)[3][0].flags != winLeftUp {
		t.Fatalf("drag: %+v", *batches)
	}
	count := len(*batches)
	for _, err := range []error{w.move(501, 0, ""), w.move(0, 0, "middle"), w.scroll(0, -501), w.drag("bad", 0, 0)} {
		if err == nil {
			t.Fatal("invalid command accepted")
		}
	}
	if len(*batches) != count {
		t.Fatal("invalid command emitted input")
	}
}

func TestWindowsUnicodeAndShortcutEvents(t *testing.T) {
	w, batches := recordingWinInput()
	text := "aéन😀"
	if err := w.keyboard("", text, nil); err != nil {
		t.Fatal(err)
	}
	units := utf16.Encode([]rune(text))
	events := (*batches)[0]
	if len(events) != 2*len(units) {
		t.Fatalf("missing UTF-16 events: %+v", events)
	}
	for i, unit := range units {
		if events[2*i].scan != unit || events[2*i].vk != 0 || events[2*i].flags != winUnicode || events[2*i+1].flags != winUnicode|winKeyUp {
			t.Fatalf("Unicode unit %d: %+v", i, events)
		}
	}
	if err := w.keyboard("A", "", []string{"ctrl", "shift"}); err != nil {
		t.Fatal(err)
	}
	want := []winEvent{winKey(0xa2), winKey(0xa0)}
	want = append(want, winPair(winKey(0x41))...)
	for _, vk := range []uint16{0xa0, 0xa2} {
		up, _ := winRelease(winKey(vk))
		want = append(want, up)
	}
	if !reflect.DeepEqual((*batches)[1], want) {
		t.Fatalf("modifier dedup/order: %+v", (*batches)[1])
	}
	w.held = func(vk uint16) bool { return vk == 0xa2 }
	if err := w.keyboard("a", "", []string{"ctrl"}); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual((*batches)[2], winPair(winKey(0x41))) {
		t.Fatal("released a physically held modifier")
	}
	for key, vk := range map[string]uint16{"left": 0x25, "enter": 0x0d, "super": 0x5b, "volumeup": 0xaf, "volumedown": 0xae, "mute": 0xad} {
		if err := w.keyboard(key, "", nil); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual((*batches)[len(*batches)-1], winPair(winKey(vk))) {
			t.Fatalf("key %s: %+v", key, *batches)
		}
	}
	if winKey(0x25).flags != winExtended || winKey(0x5b).flags != winExtended {
		t.Fatal("extended navigation key missing flag")
	}
	for _, err := range []error{w.keyboard("", "a", []string{"ctrl"}), w.keyboard("bad", "", nil), w.keyboard("a", "", []string{"bad"}), w.keyboard("!", "", nil)} {
		if err == nil {
			t.Fatal("invalid/unmapped key accepted")
		}
	}
}

func TestWindowsPartialSendReleasesAcceptedPresses(t *testing.T) {
	for accepted := 0; accepted < 6; accepted++ {
		t.Run(string(rune('0'+accepted)), func(t *testing.T) {
			w, _ := recordingWinInput()
			first := true
			var pending []winEvent
			w.send = func(events []winEvent) (int, error) {
				n := len(events)
				var err error
				if first {
					first = false
					n = min(accepted, n)
					err = errors.New("blocked SendInput")
				}
				for _, e := range events[:n] {
					if up, down := winRelease(e); down {
						pending = append(pending, up)
					} else {
						for i := len(pending) - 1; i >= 0; i-- {
							if pending[i] == e {
								pending = append(pending[:i], pending[i+1:]...)
								break
							}
						}
					}
				}
				return n, err
			}
			if err := w.keyboard("A", "", []string{"ctrl"}); err == nil {
				t.Fatal("partial send error lost")
			}
			if len(pending) != 0 {
				t.Fatalf("stuck keys after %d accepted events: %+v", accepted, pending)
			}
		})
	}
	w, _ := recordingWinInput()
	calls := 0
	w.send = func(e []winEvent) (int, error) {
		calls++
		if calls == 1 {
			return 1, nil
		}
		if len(e) != 1 || e[0].flags != winLeftUp {
			t.Fatalf("incorrect button cleanup: %+v", e)
		}
		return 1, nil
	}
	if err := w.move(0, 0, "left"); err == nil || calls != 2 {
		t.Fatal("partial mouse click did not attempt release")
	}
}

func TestWindowsDeferredDragRelease(t *testing.T) {
	w, batches := recordingWinInput()
	w.deferDragRelease()
	if len(*batches) != 0 {
		t.Fatal("release sent before desktop became available")
	}
	if err := w.flushDragRelease(); err != nil {
		t.Fatal(err)
	}
	if err := w.flushDragRelease(); err != nil {
		t.Fatal(err)
	}
	if len(*batches) != 1 || (*batches)[0][0].flags != winLeftUp {
		t.Fatalf("deferred release missing or repeated: %+v", *batches)
	}
	w.send = func([]winEvent) (int, error) { return 0, errors.New("desktop locked") }
	if w.drag("end", 0, 0) == nil || !w.dragReleasePending {
		t.Fatal("failed drag release was forgotten")
	}
	if w.flushDragRelease() == nil || !w.dragReleasePending {
		t.Fatal("failed recovery was forgotten")
	}
}
