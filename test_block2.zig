const std = @import("std");
const windows = std.os.windows;
const kernel32 = struct {
    extern "kernel32" fn WaitForSingleObject(hHandle: windows.HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    extern "kernel32" fn SetConsoleMode(hConsoleInput: windows.HANDLE, dwMode: u32) callconv(.winapi) windows.BOOL;
};

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    
    // Set raw mode + VT input (ENABLE_VIRTUAL_TERMINAL_INPUT)
    _ = kernel32.SetConsoleMode(stdin.handle, 0x0200 | 0x0010 | 0x0008 | 0x0004); // VT + Mouse + Window + ...
    
    std.debug.print("Waiting for event...\n", .{});
    const wait_res = kernel32.WaitForSingleObject(stdin.handle, 0xFFFFFFFF);
    std.debug.print("Wait returned: {d}\n", .{wait_res});
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    var buf: [32]u8 = undefined;
    
    std.debug.print("Reading...\n", .{});
    const bytes_read = reader.interface.readSliceShort(&buf) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        return;
    };
    std.debug.print("Read {d} bytes\n", .{bytes_read});
}
