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
    bKeyDown: c_int,
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
    bSetFocus: c_int,
};

const kernel32 = struct {
    pub extern "kernel32" fn WaitForSingleObject(hHandle: windows.HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    pub extern "kernel32" fn SetConsoleMode(hConsoleInput: windows.HANDLE, dwMode: u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: windows.HANDLE, lpcNumberOfEvents: *u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn PeekConsoleInputW(hConsoleInput: windows.HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: u32, lpNumberOfEventsRead: *u32) callconv(.winapi) c_int;
    pub extern "kernel32" fn ReadConsoleInputW(hConsoleInput: windows.HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: u32, lpNumberOfEventsRead: *u32) callconv(.winapi) c_int;
};

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    _ = kernel32.SetConsoleMode(stdin.handle, 0x0200 | 0x0010 | 0x0008 | 0x0004);
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    var buf: [32]u8 = undefined;
    
    std.debug.print("Press q to quit...\n", .{});
    
    while (true) {
        const wait_res = kernel32.WaitForSingleObject(stdin.handle, 0xFFFFFFFF);
        if (wait_res != 0) continue;
        
        var num_events: u32 = 0;
        if (kernel32.GetNumberOfConsoleInputEvents(stdin.handle, &num_events) == 0 or num_events == 0) continue;

        var records: [1]INPUT_RECORD = undefined;
        var read_count: u32 = 0;

        if (kernel32.PeekConsoleInputW(stdin.handle, &records, 1, &read_count) != 0 and read_count > 0) {
            const ev = records[0];
            var consume = false;

            if (ev.EventType == 0x0001) { // KEY_EVENT
                if (ev.Event.KeyEvent.bKeyDown == 0) {
                    consume = true;
                }
            } else if (ev.EventType == 0x0002) { // MOUSE_EVENT
                // VT input translates mouse events to characters, so we let ReadFile handle it.
                // Wait! Does ReadFile translate MOUSE_EVENTs if they don't have characters?
                // Let's NOT consume MOUSE_EVENTs and see if ReadFile gets them.
            } else {
                consume = true;
            }
            
            if (consume) {
                // Consume the event so it doesn't block ReadFile or cause infinite loops
                _ = kernel32.ReadConsoleInputW(stdin.handle, &records, 1, &read_count);
                continue; // Wait for next event
            }
        }
        
        // It's a KEY_EVENT (down) or MOUSE_EVENT. ReadFile should get characters!
        const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
        if (bytes_read > 0) {
            std.debug.print("Read {d} bytes: {any}\n", .{bytes_read, buf[0..bytes_read]});
            if (buf[0] == 'q') break;
        } else {
            // Wait, if it's a modifier key down, ReadFile might STILL return 0!
            // We need to consume it to avoid infinite loop!
            std.debug.print("ReadFile returned 0 bytes for event type {d}! Consuming it...\n", .{records[0].EventType});
            _ = kernel32.ReadConsoleInputW(stdin.handle, &records, 1, &read_count);
        }
    }
}
