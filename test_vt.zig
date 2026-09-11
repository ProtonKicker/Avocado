const std = @import("std"); pub fn main() !void {
    const stdout = std.Io.File.stdout();
    const stdin = std.Io.File.stdin();
    const kernel32 = struct {
        extern "kernel32" fn GetConsoleMode(h: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(h: std.os.windows.HANDLE, mode: u32) callconv(.winapi) std.os.windows.BOOL;
    };
    var in_mode: u32 = 0;
    var out_mode: u32 = 0;
    _ = kernel32.GetConsoleMode(stdin.handle, &in_mode);
    _ = kernel32.GetConsoleMode(stdout.handle, &out_mode);
    _ = kernel32.SetConsoleMode(stdout.handle, out_mode | 0x0004); // ENABLE_VIRTUAL_TERMINAL_PROCESSING
    _ = kernel32.SetConsoleMode(stdin.handle, 0x0200 | 0x0010 | 0x0008 | 0x0080); // VT_INPUT | MOUSE | WINDOW | EXTENDED
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006hMove mouse! ");
    var reader_buf: [128]u8 = undefined;
    var buf: [32]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    const len = try reader.interface.readSliceShort(&buf);
    _ = kernel32.SetConsoleMode(stdin.handle, in_mode);
    _ = kernel32.SetConsoleMode(stdout.handle, out_mode);
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l");
    std.debug.print("Read {} bytes\n", .{len});
}
