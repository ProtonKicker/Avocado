const std = @import("std");
const windows = std.os.windows;

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

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: windows.BOOL,
    wRepeatCount: u16,
    wVirtualKeyCode: u16,
    wVirtualScanCode: u16,
    uChar: extern union {
        UnicodeChar: u16,
        AsciiChar: u8,
    },
    dwControlKeyState: u32,
};

const MOUSE_EVENT_RECORD = extern struct {
    dwMousePosition: COORD,
    dwButtonState: u32,
    dwControlKeyState: u32,
    dwEventFlags: u32,
};

const COORD = extern struct {
    X: i16,
    Y: i16,
};

const WINDOW_BUFFER_SIZE_RECORD = extern struct {
    dwSize: COORD,
};

const MENU_EVENT_RECORD = extern struct {
    dwCommandId: u32,
};

const FOCUS_EVENT_RECORD = extern struct {
    bSetFocus: windows.BOOL,
};

const kernel32 = struct {
    extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: windows.HANDLE, lpcNumberOfEvents: *u32) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn PeekConsoleInputW(hConsoleInput: windows.HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: u32, lpNumberOfEventsRead: *u32) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn ReadConsoleInputW(hConsoleInput: windows.HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: u32, lpNumberOfEventsRead: *u32) callconv(.winapi) windows.BOOL;
};

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    const handle = stdin.handle;
    
    var count: u32 = 0;
    if (kernel32.GetNumberOfConsoleInputEvents(handle, &count) == 0) {
        std.debug.print("GetNumberOfConsoleInputEvents failed\n", .{});
        return;
    }
    std.debug.print("events: {d}\n", .{count});
}
