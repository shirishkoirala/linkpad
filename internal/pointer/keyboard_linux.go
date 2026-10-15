//go:build linux

package pointer

import (
	"errors"
	"fmt"
	"github.com/jezek/xgb/xproto"
)

func nativeKeyboard(key, text string, modifiers []string) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	x := linuxInput.backend
	x.mu.Lock()
	defer x.mu.Unlock()
	strokes, err := linuxInput.keyboard(key, text, modifiers)
	if err != nil {
		return err
	}
	for _, s := range strokes {
		var pressed []byte
		var eventErr error
		for _, mod := range s.mods {
			pressed = append(pressed, mod)
			if eventErr = x.emit(x11Event{kind: x11KeyPress, detail: mod}); eventErr != nil {
				break
			}
		}
		if eventErr == nil {
			eventErr = x.pair(x11KeyPress, s.code)
		}
		for i := len(pressed) - 1; i >= 0; i-- {
			eventErr = errors.Join(eventErr, x.emit(x11Event{kind: x11KeyRelease, detail: pressed[i]}))
		}
		if eventErr != nil {
			return eventErr
		}
	}
	return nil
}

type keyboardStroke struct {
	code byte
	mods []byte
}

func keyboardStrokes(mapping []xproto.Keysym, width int, min byte, key, text string, modifiers []string) ([]keyboardStroke, error) {
	lookup := func(wanted xproto.Keysym, shifted bool) (byte, bool, error) {
		for i := 0; width > 0 && i+width <= len(mapping); i += width {
			levels := 1
			if shifted && width > 1 {
				levels = 2
			}
			for level := 0; level < levels; level++ {
				if mapping[i+level] == wanted {
					return byte(int(min) + i/width), level == 1, nil
				}
			}
		}
		return 0, false, fmt.Errorf("character unavailable in the active X11 keyboard layout")
	}
	names := map[string]xproto.Keysym{"up": 0xff52, "down": 0xff54, "left": 0xff51, "right": 0xff53, "enter": 0xff0d, "backspace": 0xff08, "tab": 0xff09, "escape": 0xff1b, "space": 32, "delete": 0xffff, "home": 0xff50, "end": 0xff57, "pageup": 0xff55, "pagedown": 0xff56}
	modNames := map[string]xproto.Keysym{"shift": 0xffe1, "ctrl": 0xffe3, "alt": 0xffe9, "super": 0xffeb}
	var mods []byte
	for _, m := range modifiers {
		code, _, err := lookup(modNames[m], false)
		if err != nil {
			return nil, err
		}
		mods = append(mods, code)
	}
	var symbols []xproto.Keysym
	if key != "" {
		if symbol, ok := names[key]; ok {
			symbols = append(symbols, symbol)
		} else {
			symbols = append(symbols, xproto.Keysym([]rune(key)[0]))
		}
	} else {
		for _, r := range text {
			symbol := xproto.Keysym(r)
			if r > 255 {
				symbol |= 0x01000000
			}
			symbols = append(symbols, symbol)
		}
	}
	var strokes []keyboardStroke
	for _, symbol := range symbols {
		code, shift, err := lookup(symbol, true)
		if err != nil {
			return nil, err
		}
		stroke := keyboardStroke{code: code, mods: append([]byte{}, mods...)}
		if shift {
			shiftCode, _, err := lookup(modNames["shift"], false)
			if err != nil {
				return nil, err
			}
			found := false
			for _, m := range stroke.mods {
				if m == shiftCode {
					found = true
				}
			}
			if !found {
				stroke.mods = append(stroke.mods, shiftCode)
			}
		}
		strokes = append(strokes, stroke)
	}
	return strokes, nil
}
