//go:build linux

package pointer

import "fmt"

func nativeVolume(action string) error {
	key := ""
	switch action {
	case "up":
		key = "volumeup"
	case "down":
		key = "volumedown"
	case "mute":
		key = "mute"
	default:
		return fmt.Errorf("unsupported volume action")
	}
	return nativeKeyboard(key, "", nil)
}
