package pointer

import (
	"os"
	"testing"
	"time"
	"unsafe"
)

func TestWindowsNativeInputLayout(t *testing.T) {
	var input winNativeInput
	wantSize, wantOffset := uintptr(40), uintptr(8)
	if unsafe.Sizeof(uintptr(0)) == 4 {
		wantSize, wantOffset = 28, 4
	}
	if unsafe.Sizeof(input) != wantSize || unsafe.Offsetof(input.payload) != wantOffset {
		t.Fatalf("INPUT size=%d payload offset=%d", unsafe.Sizeof(input), unsafe.Offsetof(input.payload))
	}
	inputs := windowsNativeInputs([]winEvent{{kind: winKeyboard, vk: 0x25, flags: winExtended}, {kind: winKeyboard, scan: 0xd83d, flags: winUnicode}, {kind: winMouse, dx: -9, dy: 3, flags: winMove}})
	key := (*winKeyboardInput)(unsafe.Pointer(&inputs[0].payload))
	unicode := (*winKeyboardInput)(unsafe.Pointer(&inputs[1].payload))
	if key.vk != 0x25 || key.flags != winExtended || unicode.scan != 0xd83d || unicode.flags != winUnicode || inputs[2].payload.dx != -9 {
		t.Fatalf("INPUT union packing incorrect: %+v", inputs)
	}
	vk, _, err := windowsMapRune('a')
	if err != nil || vk == 0 {
		t.Fatalf("Windows keyboard mapping: %x %v", vk, err)
	}
}

func TestWindowsNativeInputIntegration(t *testing.T) {
	if os.Getenv("LINKPAD_WINDOWS_INTEGRATION") != "1" {
		t.Skip("opt-in only; changes the cursor in an isolated Windows/Wine desktop")
	}
	if err := AvailabilityError(); err != nil {
		t.Fatal(err)
	}
	type point struct{ x, y int32 }
	var before, after point
	get := winUser32.NewProc("GetCursorPos")
	set := winUser32.NewProc("SetCursorPos")
	if ok, _, err := get.Call(uintptr(unsafe.Pointer(&before))); ok == 0 {
		t.Fatal(err)
	}
	set.Call(200, 200)
	defer set.Call(uintptr(before.x), uintptr(before.y))
	if err := native(12, 8, ""); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		get.Call(uintptr(unsafe.Pointer(&after)))
		if after.x > 200 && after.y > 200 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if after.x <= 200 || after.y <= 200 {
		t.Fatalf("SendInput did not move cursor: %+v", after)
	}
	if err := nativeDrag("start", 0, 0); err != nil {
		t.Fatal(err)
	}
	defer nativeDrag("end", 0, 0)
	if err := nativeDrag("end", 0, 0); err != nil {
		t.Fatal(err)
	}
	if state, _, _ := winGetAsyncKeyState.Call(1); state&0x8000 != 0 {
		t.Fatal("left button remained held")
	}
	if err := nativeScroll(40, -40); err != nil {
		t.Fatal(err)
	}
	if err := nativeKeyboard("", "é😀", nil); err != nil {
		t.Fatal(err)
	}
}
