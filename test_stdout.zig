const std = @import("std");
pub fn main() !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "Hello from writeStreamingAll!\n");
}