package protocol

import "testing"

func TestScrollValidation(t *testing.T) {
	m, err := Decode([]byte(`{"version":1,"type":"scroll","dx":-500,"dy":500}`))
	if err != nil || m.ValidateScroll() != nil {
		t.Fatalf("valid scroll rejected: %v", err)
	}
	for _, m := range []Message{
		{Type: "pointer"}, {Type: "scroll", DX: -501}, {Type: "scroll", DY: 501}, {Type: "scroll", Button: "right"},
	} {
		if m.ValidateScroll() == nil {
			t.Fatalf("accepted invalid scroll: %+v", m)
		}
	}
}
