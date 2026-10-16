//go:build linux

package pointer

import "fmt"

func nativeDrag(action string, dx, dy int) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return linuxInput.backend.drag(action, dx, dy)
}

func (x *x11Input) drag(action string, dx, dy int) error {
	if action == "move" {
		return x.move(dx, dy, "")
	}
	x.mu.Lock()
	defer x.mu.Unlock()
	switch action {
	case "start":
		return x.emit(x11Event{kind: x11ButtonPress, detail: 1})
	case "end":
		return x.emit(x11Event{kind: x11ButtonRelease, detail: 1})
	case "hold":
		return nil
	default:
		return fmt.Errorf("unsupported drag action")
	}
}
