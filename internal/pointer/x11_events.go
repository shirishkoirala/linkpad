package pointer

import (
	"errors"
	"fmt"
	"sync"
	"time"
)

const (
	x11KeyPress      = 2
	x11KeyRelease    = 3
	x11ButtonPress   = 4
	x11ButtonRelease = 5
	x11Motion        = 6
	x11Relative      = 1
	x11ScrollStep    = 40
)

type x11Event struct {
	kind, detail byte
	dx, dy       int16
}

// This small event layer keeps ordering and balanced press/release pairs in one
// place. Its emitter is an authenticated XTEST connection on Linux.
type x11Input struct {
	mu               sync.Mutex
	emit             func(x11Event) error
	keycode          func(string) (byte, error)
	scrollX, scrollY int
	scrollAt         time.Time
	clock            func() time.Time
}

func (x *x11Input) pair(kind, detail byte) error {
	press := x.emit(x11Event{kind: kind, detail: detail})
	// Attempt release even if a response to the press was lost.
	release := x.emit(x11Event{kind: kind + 1, detail: detail})
	return errors.Join(press, release)
}

func (x *x11Input) move(dx, dy int, button string) error {
	x.mu.Lock()
	defer x.mu.Unlock()
	if dx < -500 || dx > 500 || dy < -500 || dy > 500 {
		return fmt.Errorf("invalid pointer bounds")
	}
	if button != "" && button != "left" && button != "right" {
		return fmt.Errorf("unsupported button")
	}
	if dx != 0 || dy != 0 {
		if err := x.emit(x11Event{kind: x11Motion, detail: x11Relative, dx: int16(dx), dy: int16(dy)}); err != nil {
			return err
		}
	}
	switch button {
	case "left":
		return x.pair(x11ButtonPress, 1)
	case "right":
		return x.pair(x11ButtonPress, 3)
	}
	return nil
}

func (x *x11Input) scroll(dx, dy int) error {
	x.mu.Lock()
	defer x.mu.Unlock()
	if dx < -500 || dx > 500 || dy < -500 || dy > 500 {
		return fmt.Errorf("invalid scroll bounds")
	}
	now := time.Now()
	if x.clock != nil {
		now = x.clock()
	}
	if now.Sub(x.scrollAt) >= 150*time.Millisecond {
		x.scrollX, x.scrollY = 0, 0
	}
	x.scrollAt = now
	x.scrollX += dx
	x.scrollY += dy
	// XTEST core scrolling is wheel-based. Accumulate small deltas rather than
	// dropping them or emitting one wheel notch per touch sample. Positive finger
	// movement follows the content (natural direction), matching the Mac client.
	for _, axis := range []struct {
		remainder          *int
		positive, negative byte
	}{
		{&x.scrollY, 4, 5}, {&x.scrollX, 6, 7},
	} {
		for *axis.remainder >= x11ScrollStep || *axis.remainder <= -x11ScrollStep {
			button, step := axis.positive, x11ScrollStep
			if *axis.remainder < 0 {
				button, step = axis.negative, -x11ScrollStep
			}
			if err := x.pair(x11ButtonPress, button); err != nil {
				x.scrollX, x.scrollY = 0, 0
				return err
			}
			*axis.remainder -= step
		}
	}
	return nil
}

func (x *x11Input) pressKey(key string) error {
	x.mu.Lock()
	defer x.mu.Unlock()
	switch key {
	case "left", "right", "up", "down":
	default:
		return fmt.Errorf("unsupported key")
	}
	code, err := x.keycode(key)
	if err != nil {
		return err
	}
	return x.pair(x11KeyPress, code)
}
