const std = @import("std");

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    const kernel32 = struct {
        extern "kernel32" fn GetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, lpMode: *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, dwMode: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: std.os.windows.HANDLE, lpcNumberOfEvents: *u32) callconv(.winapi) std.os.windows.BOOL;
    };
    
    var mode: u32 = 0;
    _ = kernel32.GetConsoleMode(stdin.handle, &mode);
    _ = kernel32.SetConsoleMode(stdin.handle, mode | 0x0200);

    std.debug.print("Press Shift alone...\n", .{});
    
    var buf: [32]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &buf);
    
    const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
    std.debug.print("ReadFile read {} bytes\n", .{bytes_read});

    var num_events: u32 = 0;
    _ = kernel32.GetNumberOfConsoleInputEvents(stdin.handle, &num_events);
    std.debug.print("Events remaining in queue: {}\n", .{num_events});
}