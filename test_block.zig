const std = @import("std");

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    var buf: [32]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &buf);
    
    std.debug.print("Calling readSliceShort...\n", .{});
    const bytes_read = reader.interface.readSliceShort(&buf) catch 0;
    std.debug.print("ReadFile read {} bytes\n", .{bytes_read});
}
