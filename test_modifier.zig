const std = @import("std");
const windows = std.os.windows;

const kernel32 = struct {
    extern "kernel32" fn FlushConsoleInputBuffer(hConsoleInput: windows.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(hConsoleInput: windows.HANDLE, dwMode: u32) callconv(.winapi) i32;
};

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    
    // Enable VT input
    _ = kernel32.SetConsoleMode(stdin.handle, 0x0200 | 0x0010 | 0x0008 | 0x0004); // ENABLE_VIRTUAL_TERMINAL_INPUT etc
    
    _ = kernel32.FlushConsoleInputBuffer(stdin.handle);
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    var buf: [32]u8 = undefined;
    
    std.debug.print("Press Shift alone (or wait)...\n", .{});
    const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
    std.debug.print("Read {d} bytes\n", .{bytes_read});
}
