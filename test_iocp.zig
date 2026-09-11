const std = @import("std");

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    var buf: [32]u8 = undefined;
    
    std.debug.print("Reading from console using IOCP...\n", .{});
    const bytes_read = reader.interface.readSliceShort(&buf) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        return;
    };
    std.debug.print("Read {d} bytes\n", .{bytes_read});
}
