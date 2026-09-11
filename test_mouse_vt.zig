const std = @import("std");

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const stdin = std.Io.File.stdin();
    const kernel32 = struct {
        extern "kernel32" fn GetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, lpMode: *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, dwMode: u32) callconv(.winapi) std.os.windows.BOOL;
    };
    
    var mode: u32 = 0;
    _ = kernel32.GetConsoleMode(stdin.handle, &mode);
    // ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_MOUSE_INPUT
    _ = kernel32.SetConsoleMode(stdin.handle, mode | 0x0200 | 0x0010);

    std.debug.print("Click the mouse or press any key...\n", .{});
    
    var buf: [32]u8 = undefined;
    var reader = stdin.reader(io, &buf);
    
    while (true) {
        const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
        if (bytes_read > 0) {
            std.debug.print("ReadFile read {} bytes: {any} ('{s}')\n", .{bytes_read, buf[0..bytes_read], buf[0..bytes_read]});
            if (buf[0] == 'q') break;
        } else {
            std.debug.print("ReadFile returned 0 bytes!\n", .{});
        }
    }
}
