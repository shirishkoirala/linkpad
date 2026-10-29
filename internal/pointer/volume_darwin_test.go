//go:build darwin && cgo

package pointer

import "testing"

func TestDarwinVolumeMediaKeys(t *testing.T) {
	for _, test := range []struct {
		action string
		code   int
	}{{"up", 0}, {"down", 1}, {"mute", 7}} {
		code, err := darwinVolumeKey(test.action)
		if err != nil || code != test.code {
			t.Fatalf("%s: code %d, %v", test.action, code, err)
		}
	}
	if _, err := darwinVolumeKey("set"); err == nil {
		t.Fatal("unsupported media action accepted")
	}
}
