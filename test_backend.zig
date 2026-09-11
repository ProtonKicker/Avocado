const std = @import("std");
const main_mod = @import("src/main.zig");
const AvocadoShell = main_mod.AvocadoShell;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.Io.Threaded.global_single_threaded.io();

    std.debug.print("Testing backend...\n", .{});
    const launch_dir = try std.process.currentPathAlloc(io, allocator);
    
    var shell = try AvocadoShell.init(allocator, io, launch_dir, null, null, "x = 5\ny = x * 2\nz = y + 10");
    defer shell.deinit();

    std.debug.print("Evaluating document...\n", .{});
    try shell.evaluate();
    
    std.debug.print("Results length: {}\n", .{shell.results.items.len});
    for (shell.results.items, 0..) |res, i| {
        std.debug.print("Line {}: {s}\n", .{i, res});
    }
    std.debug.print("Backend test complete.\n", .{});
}