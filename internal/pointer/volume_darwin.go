//go:build darwin && cgo

package pointer

/*
#cgo LDFLAGS: -framework AppKit -framework ApplicationServices
int linkpadSendVolumeKey(int code);
*/
import "C"
import "fmt"

// macOS NX media key values: SOUND_UP=0, SOUND_DOWN=1, MUTE=7.
func darwinVolumeKey(action string) (int, error) {
	switch action {
	case "up":
		return 0, nil
	case "down":
		return 1, nil
	case "mute":
		return 7, nil
	}
	return 0, fmt.Errorf("unsupported volume action")
}
func nativeVolume(action string) error {
	code, err := darwinVolumeKey(action)
	if err != nil {
		return err
	}
	if C.linkpadSendVolumeKey(C.int(code)) == 0 {
		return fmt.Errorf("macOS media input unavailable; check Accessibility permission")
	}
	return nil
}
