const std = @import("std");

pub fn main() void {
    const KEY_EVENT_RECORD = extern struct {
        bKeyDown: c_int,
        wRepeatCount: u16,
        wVirtualKeyCode: u16,
        wVirtualScanCode: u16,
        uChar: extern union { UnicodeChar: u16, AsciiChar: u8 },
        dwControlKeyState: u32,
    };
    const MOUSE_EVENT_RECORD = extern struct {
        dwMousePosition: extern struct { X: i16, Y: i16 },
        dwButtonState: u32,
        dwControlKeyState: u32,
        dwEventFlags: u32,
    };
    const WINDOW_BUFFER_SIZE_RECORD = extern struct { dwSize: extern struct { X: i16, Y: i16 } };
    const MENU_EVENT_RECORD = extern struct { dwCommandId: u32 };
    const FOCUS_EVENT_RECORD = extern struct { bSetFocus: c_int };
    const INPUT_RECORD = extern struct {
        EventType: u16,
        Event: extern union {
            KeyEvent: KEY_EVENT_RECORD,
            MouseEvent: MOUSE_EVENT_RECORD,
            WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
            MenuEvent: MENU_EVENT_RECORD,
            FocusEvent: FOCUS_EVENT_RECORD,
        },
    };
    std.debug.print("INPUT_RECORD size: {}, alignment: {}\n", .{@sizeOf(INPUT_RECORD), @alignOf(INPUT_RECORD)});
    std.debug.print("KEY_EVENT_RECORD size: {}\n", .{@sizeOf(KEY_EVENT_RECORD)});
    std.debug.print("MOUSE_EVENT_RECORD size: {}\n", .{@sizeOf(MOUSE_EVENT_RECORD)});
}