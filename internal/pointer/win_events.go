package pointer

import (
	"errors"
	"fmt"
	"sync"
	"unicode/utf16"
)

const (
	winMouse     = 0
	winKeyboard  = 1
	winMove      = 0x0001
	winLeftDown  = 0x0002
	winLeftUp    = 0x0004
	winRightDown = 0x0008
	winRightUp   = 0x0010
	winWheel     = 0x0800
	winHWheel    = 0x1000
	winExtended  = 0x0001
	winKeyUp     = 0x0002
	winUnicode   = 0x0004
)

// Keep command translation portable so it is exercised in Linux containers too.
type winEvent struct {
	kind        uint32
	dx, dy      int32
	data, flags uint32
	vk, scan    uint16
}

type winInput struct {
	mu                 sync.Mutex
	send               func([]winEvent) (int, error)
	mapRune            func(rune) (uint16, byte, error)
	held               func(uint16) bool
	dragReleasePending bool
}

func (w *winInput) deferDragRelease() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.dragReleasePending = true
}

func (w *winInput) flushDragRelease() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.dragReleasePending {
		return nil
	}
	if err := w.emit([]winEvent{{kind: winMouse, flags: winLeftUp}}); err != nil {
		return err
	}
	w.dragReleasePending = false
	return nil
}

func (w *winInput) emit(events []winEvent) error {
	if len(events) == 0 {
		return nil
	}
	n, err := w.send(events)
	if n == len(events) && err == nil {
		return nil
	}
	if err == nil {
		err = fmt.Errorf("SendInput inserted %d of %d events; Windows may block input to administrator apps", n, len(events))
	}
	// Release only keys/buttons actually inserted before a partial failure.
	var pending []winEvent
	for _, event := range events[:max(0, min(n, len(events)))] {
		up, down := winRelease(event)
		if down {
			pending = append(pending, up)
			continue
		}
		for i := len(pending) - 1; i >= 0; i-- {
			if pending[i] == event {
				pending = append(pending[:i], pending[i+1:]...)
				break
			}
		}
	}
	for i := len(pending) - 1; i >= 0; i-- {
		count, releaseErr := w.send([]winEvent{pending[i]})
		if count != 1 && releaseErr == nil {
			releaseErr = fmt.Errorf("Windows input release failed")
		}
		err = errors.Join(err, releaseErr)
	}
	return err
}

func winRelease(e winEvent) (winEvent, bool) {
	if e.kind == winKeyboard && e.flags&winKeyUp == 0 {
		e.flags |= winKeyUp
		return e, true
	}
	if e.kind == winMouse {
		switch e.flags {
		case winLeftDown:
			e.flags = winLeftUp
			return e, true
		case winRightDown:
			e.flags = winRightUp
			return e, true
		}
	}
	return winEvent{}, false
}

func (w *winInput) move(dx, dy int, button string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if dx < -500 || dx > 500 || dy < -500 || dy > 500 {
		return fmt.Errorf("invalid pointer bounds")
	}
	if button != "" && button != "left" && button != "right" {
		return fmt.Errorf("unsupported button")
	}
	var events []winEvent
	if dx != 0 || dy != 0 {
		events = append(events, winEvent{kind: winMouse, dx: int32(dx), dy: int32(dy), flags: winMove})
	}
	if button != "" {
		flags := uint32(winLeftDown)
		if button == "right" {
			flags = winRightDown
		}
		e := winEvent{kind: winMouse, flags: flags}
		up, _ := winRelease(e)
		events = append(events, e, up)
	}
	return w.emit(events)
}

func (w *winInput) scroll(dx, dy int) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if dx < -500 || dx > 500 || dy < -500 || dy > 500 {
		return fmt.Errorf("invalid scroll bounds")
	}
	var events []winEvent
	// Match natural scrolling: 40 touch pixels correspond to one 120-unit notch.
	if dy != 0 {
		events = append(events, winEvent{kind: winMouse, flags: winWheel, data: uint32(int32(dy * 3))})
	}
	if dx != 0 {
		events = append(events, winEvent{kind: winMouse, flags: winHWheel, data: uint32(int32(-dx * 3))})
	}
	return w.emit(events)
}

func (w *winInput) drag(action string, dx, dy int) error {
	if action == "move" {
		return w.move(dx, dy, "")
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	switch action {
	case "start":
		return w.emit([]winEvent{{kind: winMouse, flags: winLeftDown}})
	case "end":
		err := w.emit([]winEvent{{kind: winMouse, flags: winLeftUp}})
		w.dragReleasePending = err != nil
		return err
	case "hold":
		return nil
	default:
		return fmt.Errorf("unsupported drag action")
	}
}

func winKey(vk uint16) winEvent {
	e := winEvent{kind: winKeyboard, vk: vk}
	switch vk {
	case 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2e, 0x5b:
		e.flags = winExtended
	}
	return e
}

func winPair(e winEvent) []winEvent { up, _ := winRelease(e); return []winEvent{e, up} }

func (w *winInput) keyboard(key, text string, modifiers []string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if text != "" {
		if key != "" || len(modifiers) != 0 {
			return fmt.Errorf("text cannot include a key or modifiers")
		}
		var events []winEvent
		for _, unit := range utf16.Encode([]rune(text)) {
			events = append(events, winPair(winEvent{kind: winKeyboard, scan: unit, flags: winUnicode})...)
		}
		return w.emit(events)
	}
	keys := map[string]uint16{"backspace": 0x08, "tab": 0x09, "enter": 0x0d, "escape": 0x1b, "space": 0x20, "pageup": 0x21, "pagedown": 0x22, "end": 0x23, "home": 0x24, "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28, "delete": 0x2e, "super": 0x5b, "mute": 0xad, "volumedown": 0xae, "volumeup": 0xaf}
	vk, named := keys[key]
	var implicit byte
	if !named {
		runes := []rune(key)
		if len(runes) != 1 || w.mapRune == nil {
			return fmt.Errorf("unsupported keyboard key")
		}
		var err error
		vk, implicit, err = w.mapRune(runes[0])
		if err != nil {
			return err
		}
	}
	if implicit&^byte(7) != 0 {
		return fmt.Errorf("unsupported keyboard layout modifiers")
	}
	mods := map[string]uint16{"shift": 0xa0, "ctrl": 0xa2, "alt": 0xa4, "super": 0x5b}
	var codes []uint16
	for _, name := range modifiers {
		code, ok := mods[name]
		if !ok {
			return fmt.Errorf("unsupported keyboard modifier")
		}
		codes = append(codes, code)
	}
	for i, code := range []uint16{0xa0, 0xa2, 0xa4} {
		if implicit&(1<<i) != 0 {
			codes = append(codes, code)
		}
	}
	var events, releases []winEvent
	seen := map[uint16]bool{}
	for _, code := range codes {
		if seen[code] || (w.held != nil && w.held(code)) {
			continue
		}
		seen[code] = true
		e := winKey(code)
		up, _ := winRelease(e)
		events = append(events, e)
		releases = append(releases, up)
	}
	events = append(events, winPair(winKey(vk))...)
	for i := len(releases) - 1; i >= 0; i-- {
		events = append(events, releases[i])
	}
	return w.emit(events)
}
