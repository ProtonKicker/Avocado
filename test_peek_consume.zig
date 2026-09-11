const std = @import("std");

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const stdin = std.Io.File.stdin();
    const kernel32 = struct {
        extern "kernel32" fn GetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, lpMode: *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, dwMode: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn WaitForSingleObject(hHandle: std.os.windows.HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    };
    
    var mode: u32 = 0;
    _ = kernel32.GetConsoleMode(stdin.handle, &mode);
    _ = kernel32.SetConsoleMode(stdin.handle, mode | 0x0200); // ENABLE_VIRTUAL_TERMINAL_INPUT

    const win = std.os.windows;
    const PeekConsoleInputW = struct {
        extern "kernel32" fn PeekConsoleInputW(
            hConsoleInput: win.HANDLE,
            lpBuffer: [*]win.INPUT_RECORD,
            nLength: win.DWORD,
            lpNumberOfEventsRead: *win.DWORD,
        ) callconv(.winapi) win.BOOL;
    }.PeekConsoleInputW;

    const ReadConsoleInputW = struct {
        extern "kernel32" fn ReadConsoleInputW(
            hConsoleInput: win.HANDLE,
            lpBuffer: [*]win.INPUT_RECORD,
            nLength: win.DWORD,
            lpNumberOfEventsRead: *win.DWORD,
        ) callconv(.winapi) win.BOOL;
    }.ReadConsoleInputW;

    std.debug.print("Press Shift alone, then click the mouse, then press 'a'.\n", .{});
    
    var events: [1]win.INPUT_RECORD = undefined;
    var read_count: win.DWORD = 0;

    while (true) {
        const wait_res = kernel32.WaitForSingleObject(stdin.handle, std.os.windows.INFINITE);
        if (wait_res == 0) {
            const peek_res = PeekConsoleInputW(stdin.handle, &events, 1, &read_count);
            if (peek_res != 0 and read_count > 0) {
                const ev = events[0];
                if (ev.EventType == win.KEY_EVENT) {
                    const ke = ev.Event.KeyEvent;
                    std.debug.print("Peeked KEY_EVENT: down={} char={d} vk={d}\n", .{ke.bKeyDown, ke.uChar.UnicodeChar, ke.wVirtualKeyCode});
                    if (ke.bKeyDown != 0 and ke.uChar.UnicodeChar != 0) {
                        // It's a character key, break to ReadFile
                        break;
                    }
                } else if (ev.EventType == win.MOUSE_EVENT) {
                    std.debug.print("Peeked MOUSE_EVENT\n", .{});
                    // DO NOT consume mouse events if we want them in ReadFile?
                    // Let's break and see if ReadFile reads it
                    break;
                } else {
                    std.debug.print("Peeked EventType: {}\n", .{ev.EventType});
                }
                // Consume it
                _ = ReadConsoleInputW(stdin.handle, &events, 1, &read_count);
                std.debug.print("Consumed event\n", .{});
            }
        }
    }

    var buf: [32]u8 = undefined;
    var reader = stdin.reader(io, &buf);
    const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
    std.debug.print("ReadFile read {} bytes: {s}\n", .{bytes_read, buf[0..bytes_read]});
}