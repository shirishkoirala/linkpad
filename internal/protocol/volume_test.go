package protocol

import "testing"

func TestVolumeValidation(t *testing.T) {
	for _, action := range []string{"up", "down", "mute"} {
		m, err := Decode([]byte(`{"version":1,"type":"volume","action":"` + action + `"}`))
		if err != nil {
			t.Fatal(err)
		}
		if err := m.ValidateVolume(); err != nil {
			t.Fatal(err)
		}
	}
	for _, m := range []Message{
		{Type: "volume"}, {Type: "volume", Action: "set"}, {Type: "keyboard", Action: "up"},
		{Type: "volume", Action: "up", DX: 1}, {Type: "volume", Action: "down", Key: "a"},
		{Type: "volume", Action: "mute", Modifiers: []string{"shift"}}, {Type: "volume", Action: "up", Text: "hello"},
		{Type: "volume", Action: "up", Button: "left"},
	} {
		if m.ValidateVolume() == nil {
			t.Fatalf("accepted invalid volume: %+v", m)
		}
	}
}
