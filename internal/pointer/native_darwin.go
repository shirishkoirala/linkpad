//go:build darwin && cgo

package pointer

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
static int permitted() { return AXIsProcessTrusted(); }
static int requestPermission() {
 const void *keys[] = { kAXTrustedCheckOptionPrompt };
 const void *values[] = { kCFBooleanTrue };
 CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1,
   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
 int trusted = AXIsProcessTrustedWithOptions(options);
 CFRelease(options);
 return trusted;
}
static int pressKey(int keycode) {
 if (!AXIsProcessTrusted()) return 0;
 CGEventRef down=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)keycode,true);
 CGEventRef up=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)keycode,false);
 if (!down || !up) {if(down)CFRelease(down);if(up)CFRelease(up);return 0;}
 CGEventPost(kCGHIDEventTap,down); CGEventPost(kCGHIDEventTap,up);
 CFRelease(down); CFRelease(up);
 return 1;
}
static int scrollPointer(int dx, int dy) {
 if (!AXIsProcessTrusted()) return 0;
 CGEventRef event=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,2,dy,dx);
 if (!event) return 0;
 CGEventSetIntegerValueField(event,kCGScrollWheelEventIsContinuous,1);
 CGEventPost(kCGHIDEventTap,event);
 CFRelease(event);
 return 1;
}
static int movePointer(int dx, int dy, int button) {
 if (!AXIsProcessTrusted()) return 0;
 CGEventRef current=CGEventCreate(NULL); if (!current) return 0;
 CGPoint p=CGEventGetLocation(current); CFRelease(current); p.x+=dx; p.y+=dy;
 CGEventRef move=CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,p,kCGMouseButtonLeft);
 if (!move) return 0; CGEventPost(kCGHIDEventTap,move); CFRelease(move);
 if (button) {
 CGMouseButton b=button==1?kCGMouseButtonLeft:kCGMouseButtonRight;
 CGEventType down=button==1?kCGEventLeftMouseDown:kCGEventRightMouseDown;
 CGEventType up=button==1?kCGEventLeftMouseUp:kCGEventRightMouseUp;
 CGEventRef d=CGEventCreateMouseEvent(NULL,down,p,b); CGEventRef u=CGEventCreateMouseEvent(NULL,up,p,b);
 if (!d || !u) {if(d)CFRelease(d);if(u)CFRelease(u);return 0;}
 CGEventPost(kCGHIDEventTap,d); CGEventPost(kCGHIDEventTap,u);CFRelease(d);CFRelease(u);
 } return 1;
}
*/
import "C"
import "fmt"

func Available() bool    { return C.permitted() != 0 }
func RequestPermission() { C.requestPermission() }
func AvailabilityError() error {
	if Available() {
		return nil
	}
	return fmt.Errorf("grant macOS Accessibility permission to the responsible application, then restart Linkpad")
}
func nativeScroll(dx, dy int) error {
	if C.scrollPointer(C.int(dx), C.int(dy)) == 0 {
		return fmt.Errorf("macOS Accessibility permission required or scroll event creation failed")
	}
	return nil
}
func native(dx, dy int, button string) error {
	b := 0
	if button == "left" {
		b = 1
	}
	if button == "right" {
		b = 2
	}
	if C.movePointer(C.int(dx), C.int(dy), C.int(b)) == 0 {
		return fmt.Errorf("macOS Accessibility permission required or event creation failed")
	}
	return nil
}
func nativeKey(key string) error {
	var code C.int
	switch key {
	case "up":
		code = 126
	case "down":
		code = 125
	case "left":
		code = 123
	case "right":
		code = 124
	default:
		return fmt.Errorf("unsupported key")
	}
	if C.pressKey(code) == 0 {
		return fmt.Errorf("macOS Accessibility permission required or key event creation failed")
	}
	return nil
}
