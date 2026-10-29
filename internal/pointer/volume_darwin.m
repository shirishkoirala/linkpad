//go:build darwin && cgo

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

// System-defined media events mirror physical volume keys, including the OS HUD.
int linkpadSendVolumeKey(int code) {
  if (!AXIsProcessTrusted()) return 0;
  @autoreleasepool {
    NSEvent *down = [NSEvent otherEventWithType:NSEventTypeSystemDefined
        location:NSZeroPoint modifierFlags:(NSEventModifierFlags)0xa00
        timestamp:0 windowNumber:0 context:nil subtype:(NSEventSubtype)8
        data1:(code << 16) | 0xa00 data2:-1];
    NSEvent *up = [NSEvent otherEventWithType:NSEventTypeSystemDefined
        location:NSZeroPoint modifierFlags:(NSEventModifierFlags)0xb00
        timestamp:0 windowNumber:0 context:nil subtype:(NSEventSubtype)8
        data1:(code << 16) | 0xb00 data2:-1];
    if (!down || !up || !down.CGEvent || !up.CGEvent) return 0;
    CGEventPost(kCGHIDEventTap, down.CGEvent);
    CGEventPost(kCGHIDEventTap, up.CGEvent);
    return 1;
  }
}
