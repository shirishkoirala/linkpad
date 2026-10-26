package protocol

import "testing"

func TestStandaloneSuper(t *testing.T) {
	if err := (Message{Type: "keyboard", Key: "super"}).ValidateKeyboard(); err != nil {
		t.Fatal(err)
	}
	if err := (Message{Type: "keyboard", Key: "super", Modifiers: []string{"ctrl"}}).ValidateKeyboard(); err == nil {
		t.Fatal("standalone Super accepted modifiers")
	}
}
