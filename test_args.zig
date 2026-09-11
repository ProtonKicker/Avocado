const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args_iter = init.minimal.args;
    const args = try args_iter.toSlice(arena);
    std.debug.print("Args len: {}\n", .{args.len});
}