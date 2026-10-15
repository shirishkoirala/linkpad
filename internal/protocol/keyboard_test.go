package protocol

import "testing"

func TestKeyboardValidation(t *testing.T) {
	for _, m := range []Message{{Type: "keyboard", Text: "Hello é"}, {Type: "keyboard", Key: "c", Modifiers: []string{"super"}}, {Type: "keyboard", Key: "enter"}} {
		if err := m.ValidateKeyboard(); err != nil {
			t.Fatal(err)
		}
	}
	for _, m := range []Message{{Type: "keyboard"}, {Type: "keyboard", Text: "\n"}, {Type: "keyboard", Text: "a", Key: "b"}, {Type: "keyboard", Key: "bad"}, {Type: "keyboard", Key: "a", Modifiers: []string{"ctrl", "ctrl"}}, {Type: "keyboard", Text: "a", Modifiers: []string{"alt"}}} {
		if err := m.ValidateKeyboard(); err == nil {
			t.Fatalf("accepted invalid input: %+v", m)
		}
	}
}
