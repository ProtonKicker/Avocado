const std = @import("std");
pub fn main() void {
    const frame_time_ns: i128 = 16_666_666;
    const elapsed_ns: i128 = 10_000_000_000;
    if (elapsed_ns < frame_time_ns) {
        const sleep_ns: u64 = @intCast(frame_time_ns - elapsed_ns);
        std.debug.print("sleep_ns = {d}\n", .{sleep_ns});
    } else {
        std.debug.print("Skipped sleep\n", .{});
    }
}
