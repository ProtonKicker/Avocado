const std = @import("std");
pub fn main() void {
    const stdin = std.Io.File.stdin();
    var reader_buf: [128]u8 = undefined;
    const reader = stdin.reader(std.Io.Threaded.global_single_threaded.io(), &reader_buf);
    std.debug.print("{any}\n", .{@TypeOf(reader)});
}
