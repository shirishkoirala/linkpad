//go:build !darwin || !cgo

package pointer

import "fmt"

func Available() bool { return false }
func nativeScroll(dx, dy int) error {
	return fmt.Errorf("scroll backend unavailable on this platform/build")
}
func native(dx, dy int, button string) error {
	return fmt.Errorf("pointer backend unavailable on this platform/build")
}
func nativeKey(key string) error {
	return fmt.Errorf("key backend unavailable on this platform/build")
}
