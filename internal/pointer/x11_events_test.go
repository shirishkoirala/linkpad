package pointer

import (
	"errors"
	"reflect"
	"sync"
	"testing"
	"time"
)

func TestX11RelativeMovementAndClicks(t *testing.T) {
	var events []x11Event
	x := &x11Input{emit: func(e x11Event) error { events = append(events, e); return nil }}
	if err := x.move(10, 5, ""); err != nil {
		t.Fatal(err)
	}
	if err := x.move(10, 5, "left"); err != nil {
		t.Fatal(err)
	}
	if err := x.move(0, 0, "right"); err != nil {
		t.Fatal(err)
	}
	want := []x11Event{
		{kind: x11Motion, detail: x11Relative, dx: 10, dy: 5},
		{kind: x11Motion, detail: x11Relative, dx: 10, dy: 5},
		{kind: x11ButtonPress, detail: 1}, {kind: x11ButtonRelease, detail: 1},
		{kind: x11ButtonPress, detail: 3}, {kind: x11ButtonRelease, detail: 3},
	}
	if !reflect.DeepEqual(events, want) {
		t.Fatalf("wrong relative/click events: %v", events)
	}
	for _, test := range []struct {
		dx, dy int
		button string
	}{{501, 0, ""}, {0, -501, ""}, {0, 0, "middle"}} {
		if x.move(test.dx, test.dy, test.button) == nil {
			t.Fatal("invalid pointer accepted")
		}
	}
	if len(events) != len(want) {
		t.Fatal("invalid pointer emitted input")
	}
}

func TestX11ScrollAccumulatesAndExpires(t *testing.T) {
	var events []x11Event
	now := time.Unix(100, 0)
	x := &x11Input{emit: func(e x11Event) error { events = append(events, e); return nil }, clock: func() time.Time { return now }}
	for i := 0; i < 3; i++ {
		if err := x.scroll(10, 10); err != nil {
			t.Fatal(err)
		}
	}
	if len(events) != 0 {
		t.Fatal("small samples were amplified into wheel events")
	}
	if err := x.scroll(10, 10); err != nil {
		t.Fatal(err)
	}
	if err := x.scroll(-40, -40); err != nil {
		t.Fatal(err)
	}
	want := []byte{4, 4, 6, 6, 5, 5, 7, 7}
	for i, event := range events {
		if event.detail != want[i] {
			t.Fatalf("wrong wheel direction: %v", events)
		}
	}
	if len(events) != len(want) {
		t.Fatalf("wrong wheel count: %v", events)
	}
	events = nil
	x.scroll(0, 30)
	now = now.Add(151 * time.Millisecond)
	x.scroll(0, 10)
	if len(events) != 0 {
		t.Fatal("expired scroll remainder replayed")
	}
	x.scroll(0, 30)
	if len(events) != 2 {
		t.Fatal("fresh scroll remainder lost")
	}
}

func TestX11KeysAndFailedPressRelease(t *testing.T) {
	var events []x11Event
	x := &x11Input{
		emit: func(e x11Event) error {
			events = append(events, e)
			if len(events) == 1 {
				return errors.New("lost press response")
			}
			return nil
		},
		keycode: func(key string) (byte, error) {
			if key != "up" {
				t.Fatal("wrong key lookup")
			}
			return 111, nil
		},
	}
	if x.pressKey("up") == nil {
		t.Fatal("emitter error lost")
	}
	if len(events) != 2 || events[0].kind != x11KeyPress || events[1].kind != x11KeyRelease || events[1].detail != 111 {
		t.Fatalf("release not attempted: %v", events)
	}
	if x.pressKey("arbitrary") == nil {
		t.Fatal("unsupported key accepted")
	}
}

func TestX11ConcurrentClicksStayBalanced(t *testing.T) {
	var events []x11Event
	x := &x11Input{emit: func(e x11Event) error { events = append(events, e); return nil }}
	var group sync.WaitGroup
	for i := 0; i < 50; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			if err := x.move(0, 0, "left"); err != nil {
				t.Error(err)
			}
		}()
	}
	group.Wait()
	if len(events) != 100 {
		t.Fatal("clicks lost")
	}
	for i := 0; i < len(events); i += 2 {
		if events[i].kind != x11ButtonPress || events[i+1].kind != x11ButtonRelease {
			t.Fatal("interleaved click pair")
		}
	}
}
