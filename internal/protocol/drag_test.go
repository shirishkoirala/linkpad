package protocol

import "testing"

func TestValidateDrag(t *testing.T) {
	for _, action := range []string{"start", "move", "hold", "end"} {
		if err := (Message{Type: "drag", Action: action}).ValidateDrag(); err != nil {
			t.Fatal(err)
		}
	}
	for _, m := range []Message{{Type: "drag", Action: "bad"}, {Type: "drag", Action: "start", DX: 1}, {Type: "drag", Action: "move", DX: 501}, {Type: "drag", Action: "end", Button: "left"}, {Type: "drag", Action: "hold", Text: "a"}} {
		if m.ValidateDrag() == nil {
			t.Fatalf("accepted invalid input: %+v", m)
		}
	}
}
