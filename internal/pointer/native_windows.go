package pointer

import (
	"fmt"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var winUser32 = windows.NewLazySystemDLL("user32.dll")
var winSendInput = winUser32.NewProc("SendInput")
var winOpenInputDesktop = winUser32.NewProc("OpenInputDesktop")
var winCloseDesktop = winUser32.NewProc("CloseDesktop")
var winGetUserObjectInformation = winUser32.NewProc("GetUserObjectInformationW")
var winGetKeyboardLayout = winUser32.NewProc("GetKeyboardLayout")
var winGetForegroundWindow = winUser32.NewProc("GetForegroundWindow")
var winGetWindowThreadProcessID = winUser32.NewProc("GetWindowThreadProcessId")
var winVkKeyScan = winUser32.NewProc("VkKeyScanExW")
var winGetAsyncKeyState = winUser32.NewProc("GetAsyncKeyState")

// INPUT's union has pointer alignment: 40 bytes on 64-bit Windows, 28 on 32-bit.
type winMouseInput struct {
	dx, dy            int32
	data, flags, time uint32
	extra             uintptr
}
type winKeyboardInput struct {
	vk, scan    uint16
	flags, time uint32
	extra       uintptr
}
type winNativeInput struct {
	kind    uint32
	payload winMouseInput
}

var windowsInput = winInput{send: sendWindowsInput, mapRune: windowsMapRune, held: func(vk uint16) bool {
	state, _, _ := winGetAsyncKeyState.Call(uintptr(vk))
	return state&0x8000 != 0
}}

func AvailabilityError() error {
	desktop, _, err := winOpenInputDesktop.Call(0, 0, 0x0001|0x0080)
	if desktop == 0 {
		return fmt.Errorf("Windows interactive desktop unavailable: %v; run Linkpad in your logged-in desktop session", err)
	}
	defer winCloseDesktop.Call(desktop)
	var name [256]uint16
	var required uint32
	ok, _, err := winGetUserObjectInformation.Call(desktop, 2, uintptr(unsafe.Pointer(&name[0])), unsafe.Sizeof(name), uintptr(unsafe.Pointer(&required)))
	if ok == 0 {
		return fmt.Errorf("read Windows input desktop: %v", err)
	}
	if !strings.EqualFold(syscall.UTF16ToString(name[:]), "Default") {
		return fmt.Errorf("Windows lock and UAC secure desktops are not supported")
	}
	return windowsInput.flushDragRelease()
}

func Available() bool { return AvailabilityError() == nil }

func windowsNativeInputs(events []winEvent) []winNativeInput {
	inputs := make([]winNativeInput, len(events))
	for i, event := range events {
		inputs[i].kind = event.kind
		if event.kind == winKeyboard {
			key := (*winKeyboardInput)(unsafe.Pointer(&inputs[i].payload))
			key.vk, key.scan, key.flags = event.vk, event.scan, event.flags
		} else {
			inputs[i].payload = winMouseInput{dx: event.dx, dy: event.dy, data: event.data, flags: event.flags}
		}
	}
	return inputs
}

func sendWindowsInput(events []winEvent) (int, error) {
	inputs := windowsNativeInputs(events)
	if len(inputs) == 0 {
		return 0, nil
	}
	count, _, err := winSendInput.Call(uintptr(len(inputs)), uintptr(unsafe.Pointer(&inputs[0])), unsafe.Sizeof(inputs[0]))
	runtime.KeepAlive(inputs)
	if int(count) != len(inputs) {
		return int(count), fmt.Errorf("Windows SendInput inserted %d/%d events (%v); input to administrator apps may be blocked", count, len(inputs), err)
	}
	return int(count), nil
}

func windowsMapRune(r rune) (uint16, byte, error) {
	if r < 0 || r > 0xffff {
		return 0, 0, fmt.Errorf("shortcut character unavailable in Windows keyboard layout")
	}
	window, _, _ := winGetForegroundWindow.Call()
	thread, _, _ := winGetWindowThreadProcessID.Call(window, 0)
	layout, _, _ := winGetKeyboardLayout.Call(thread)
	value, _, _ := winVkKeyScan.Call(uintptr(r), layout)
	if uint16(value) == 0xffff {
		return 0, 0, fmt.Errorf("shortcut character unavailable in Windows keyboard layout")
	}
	return uint16(value) & 0xff, byte(value >> 8), nil
}

func native(dx, dy int, button string) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return windowsInput.move(dx, dy, button)
}
func nativeScroll(dx, dy int) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return windowsInput.scroll(dx, dy)
}
func nativeDrag(action string, dx, dy int) error {
	if err := AvailabilityError(); err != nil {
		if action == "end" {
			windowsInput.deferDragRelease()
		}
		return err
	}
	return windowsInput.drag(action, dx, dy)
}
func nativeKeyboard(key, text string, modifiers []string) error {
	if err := AvailabilityError(); err != nil {
		return err
	}
	return windowsInput.keyboard(key, text, modifiers)
}
func nativeKey(key string) error { return nativeKeyboard(key, "", nil) }
func nativeVolume(action string) error {
	key, ok := map[string]string{"up": "volumeup", "down": "volumedown", "mute": "mute"}[action]
	if !ok {
		return fmt.Errorf("unsupported volume action")
	}
	return nativeKeyboard(key, "", nil)
}
