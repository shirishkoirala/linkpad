//go:build !darwin || !cgo

package pointer

// Non-macOS backends use their graphical session's existing permissions.
func RequestPermission() {}
