package protocol

import (
	"fmt"
	"unicode"
	"unicode/utf8"
)

func (m Message) ValidateKeyboard() error {
	if m.Type != "keyboard" || m.DX != 0 || m.DY != 0 || m.Button != "" {
		return fmt.Errorf("invalid keyboard message")
	}
	if (m.Key == "") == (m.Text == "") {
		return fmt.Errorf("provide a key or text")
	}
	if m.Text != "" {
		if !utf8.ValidString(m.Text) || utf8.RuneCountInString(m.Text) > 128 || len(m.Modifiers) != 0 {
			return fmt.Errorf("invalid keyboard text")
		}
		for _, r := range m.Text {
			if !unicode.IsPrint(r) {
				return fmt.Errorf("text must be printable")
			}
		}
	}
	if m.Key != "" {
		switch m.Key {
		case "up", "down", "left", "right", "enter", "backspace", "tab", "escape", "space", "delete", "home", "end", "pageup", "pagedown":
		default:
			if len(m.Key) != 1 || m.Key[0] < 32 || m.Key[0] > 126 {
				return fmt.Errorf("unsupported keyboard key")
			}
		}
	}
	seen := map[string]bool{}
	for _, mod := range m.Modifiers {
		if seen[mod] {
			return fmt.Errorf("duplicate modifier")
		}
		seen[mod] = true
		switch mod {
		case "shift", "ctrl", "alt", "super":
		default:
			return fmt.Errorf("unsupported modifier")
		}
	}
	return nil
}
