package protocol

import "testing"

func TestDecode(t *testing.T) {
	for _, raw := range []string{`{}`, `{"version":2,"type":"hello"}`, `{"version":1,"type":"nope"}`, `[]`} {
		if _, e := Decode([]byte(raw)); e == nil {
			t.Fatal(raw)
		}
	}
	if _, e := Decode([]byte(`{"version":1,"type":"hello"}`)); e != nil {
		t.Fatal(e)
	}
}
func TestPointerBounds(t *testing.T) {
	for _, m := range []Message{{Type: "pointer", DX: 501}, {Type: "pointer", DY: -501}, {Type: "pointer", Button: "middle"}, {Type: "hello"}} {
		if m.ValidatePointer() == nil {
			t.Fatal(m)
		}
	}
	if (Message{Type: "pointer", DX: 500, DY: -500, Button: "left"}).ValidatePointer() != nil {
		t.Fatal("valid movement rejected")
	}
}
func FuzzDecode(f *testing.F) {
	f.Add([]byte(`{"version":1,"type":"hello"}`))
	f.Fuzz(func(t *testing.T, b []byte) { _, _ = Decode(b) })
}
func TestKeyValidation(t *testing.T) {
	m, err := Decode([]byte(`{"version":1,"type":"key","key":"up"}`))
	if err != nil || m.ValidateKey() != nil {
		t.Fatalf("valid key rejected: %v", err)
	}
	for _, m := range []Message{
		{Type: "pointer", Key: "up"}, {Type: "key"}, {Type: "key", Key: "enter"},
		{Type: "key", Key: "left", DX: 1}, {Type: "key", Key: "right", Button: "left"},
	} {
		if m.ValidateKey() == nil {
			t.Fatalf("accepted invalid key: %+v", m)
		}
	}
}
