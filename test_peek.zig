const std = @import("std");

pub fn main(init: std.process.Init) !void {
    _ = init;
    const stdin = std.Io.File.stdin();
    const handle = stdin.handle;
    
    const kernel32 = struct {
        extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: std.os.windows.HANDLE, lpcNumberOfEvents: *u32) callconv(.winapi) i32;
    };
    
    var count: u32 = 0;
    if (kernel32.GetNumberOfConsoleInputEvents(handle, &count) == 0) {
        std.debug.print("GetNumberOfConsoleInputEvents failed\n", .{});
        return;
    }
    std.debug.print("events: {d}\n", .{count});
}
