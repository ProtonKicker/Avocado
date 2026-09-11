const std = @import("std");

pub fn main() !void {
    const stdin = std.Io.File.stdin();
    
    var reader_buf: [128]u8 = undefined;
    var reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    
    std.debug.print("Reader type: {s}\n", .{@typeName(@TypeOf(reader))});
}
