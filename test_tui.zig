const std = @import("std");
const tui = @import("tui");

const AppWidget = struct {
    pub fn render(self: *AppWidget, ctx: *tui.RenderContext) void {
        _ = self;
        ctx.screen.moveCursor(0, 0);
        ctx.screen.putString("Hello, TUI!");
    }
    pub fn handleEvent(self: *AppWidget, event: tui.Event) tui.widget.EventResult {
        _ = self;
        if (event == .key) {
            const key_event = event.key;
            if (key_event.key == .char and key_event.key.char == 'q') {
                return .ignored;
            }
        }
        return .ignored;
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var app = try tui.App.initWithAllocator(allocator, .{
        .alternate_screen = true,
        .hide_cursor = true,
        .enable_mouse = true,
        .enable_paste = true,
        .enable_focus = true,
    });
    defer app.deinit();

    var widget = AppWidget{};
    try app.setRoot(&widget);
    try app.run();
}
