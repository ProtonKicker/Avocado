const std = @import("std");
pub fn main() !void {
    const kernel32 = struct {
        extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
        extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    };
    
    const before = kernel32.GetConsoleOutputCP();
    std.debug.print("Before: {}\n", .{before});
    
    const res = kernel32.SetConsoleOutputCP(65001);
    std.debug.print("SetConsoleOutputCP(65001) returned {}\n", .{res});
    if (res == .FALSE) {
        std.debug.print("Error: {}\n", .{kernel32.GetLastError()});
    }
    
    const after = kernel32.GetConsoleOutputCP();
    std.debug.print("After: {}\n", .{after});
    
    std.debug.print("Box: ─\n", .{});
}