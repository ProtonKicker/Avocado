const std = @import("std");
const windows = std.os.windows;
const kernel32 = struct {
    extern "kernel32" fn WaitForSingleObject(hHandle: windows.HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    extern "kernel32" fn SetConsoleMode(hConsoleInput: windows.HANDLE, dwMode: u32) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: windows.HANDLE, lpcNumberOfEvents: *u32) callconv(.winapi) windows.BOOL;
};

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    _ = kernel32.SetConsoleMode(stdin.handle, 0x0200 | 0x0010 | 0x0008 | 0x0004);
    
    std.debug.print("Please click outside this window and click back to generate FOCUS_EVENT...\n", .{});
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    var buf: [32]u8 = undefined;
    
    while (true) {
        const wait_res = kernel32.WaitForSingleObject(stdin.handle, 0xFFFFFFFF);
        if (wait_res != 0) continue;
        
        var num_events: u32 = 0;
        _ = kernel32.GetNumberOfConsoleInputEvents(stdin.handle, &num_events);
        std.debug.print("Events pending: {d}\n", .{num_events});
        
        std.debug.print("Calling readSliceShort...\n", .{});
        const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
        std.debug.print("Read {d} bytes\n", .{bytes_read});
        break;
    }
}
