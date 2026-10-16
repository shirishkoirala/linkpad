//go:build darwin && cgo

package pointer

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
static int dragPointer(int action, int dx, int dy) {
 if (!AXIsProcessTrusted()) return 0;
 CGEventRef current = CGEventCreate(NULL);
 if (!current) return 0;
 CGPoint p = CGEventGetLocation(current); CFRelease(current);
 p.x += dx; p.y += dy;
 CGEventType type = action==1 ? kCGEventLeftMouseDown : action==2 ? kCGEventLeftMouseDragged : kCGEventLeftMouseUp;
 CGEventRef event = CGEventCreateMouseEvent(NULL, type, p, kCGMouseButtonLeft);
 if (!event) return 0;
 CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
 CGEventPost(kCGHIDEventTap,event);CFRelease(event);return 1;
}
*/
import "C"
import "fmt"

func nativeDrag(action string, dx, dy int) error {
	code := 3
	switch action {
	case "start":
		code = 1
	case "move":
		code = 2
	case "hold":
		return nil
	case "end":
	default:
		return fmt.Errorf("unsupported drag action")
	}
	if C.dragPointer(C.int(code), C.int(dx), C.int(dy)) == 0 {
		return fmt.Errorf("macOS drag input unavailable; check Accessibility permission")
	}
	return nil
}
