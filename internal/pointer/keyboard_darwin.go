//go:build darwin && cgo

package pointer

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
static int sendKeyboard(int code, UniChar *text, int length, unsigned long long flags) {
 if (!AXIsProcessTrusted()) return 0;
 CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)code, true);
 CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)code, false);
 if (!down || !up) { if(down)CFRelease(down); if(up)CFRelease(up); return 0; }
 CGEventSetFlags(down, (CGEventFlags)flags); CGEventSetFlags(up, (CGEventFlags)flags);
 if (length) { CGEventKeyboardSetUnicodeString(down, length, text); CGEventKeyboardSetUnicodeString(up, length, text); }
 CGEventPost(kCGHIDEventTap, down); CGEventPost(kCGHIDEventTap, up);
 CFRelease(down); CFRelease(up); return 1;
}
*/
import "C"
import (
	"fmt"
	"strings"
	"unicode/utf16"
)

func nativeKeyboard(key, text string, modifiers []string) error {
	codes := map[string]int{"up": 126, "down": 125, "left": 123, "right": 124, "enter": 36, "backspace": 51, "tab": 48, "escape": 53, "space": 49, "delete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121}
	// Physical US key positions are used for shortcuts; ordinary text uses Unicode.
	for k, v := range map[string]int{"a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50} {
		codes[k] = v
	}
	var flags C.ulonglong
	for _, mod := range modifiers {
		switch mod {
		case "shift":
			flags |= 1 << 17
		case "ctrl":
			flags |= 1 << 18
		case "alt":
			flags |= 1 << 19
		case "super":
			flags |= 1 << 20
		}
	}
	code := 0
	if key != "" {
		if value, ok := codes[strings.ToLower(key)]; ok {
			code = value
		} else if len(modifiers) > 0 {
			return fmt.Errorf("shortcut key unavailable")
		} else {
			text = key
		}
	}
	var ptr *C.UniChar
	units := utf16.Encode([]rune(text))
	buffer := make([]C.UniChar, len(units))
	for i, u := range units {
		buffer[i] = C.UniChar(u)
	}
	if len(buffer) > 0 {
		ptr = &buffer[0]
	}
	if C.sendKeyboard(C.int(code), ptr, C.int(len(buffer)), flags) == 0 {
		return fmt.Errorf("macOS keyboard input unavailable; check Accessibility permission")
	}
	return nil
}
