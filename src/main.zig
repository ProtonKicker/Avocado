const std = @import("std");
const builtin = @import("builtin");
const tui = @import("tui");
const Avocado = @import("Avocado");

const TextArea = tui.TextArea;
const InputField = tui.InputField;
const Event = tui.events.Event;
const EventResult = tui.EventResult;
const Key = tui.events.Key;
const KeyEvent = tui.events.KeyEvent;
const MouseEvent = tui.events.MouseEvent;
const MouseKind = tui.events.MouseKind;
const MouseButton = tui.events.MouseButton;
const RenderContext = tui.RenderContext;
const Screen = tui.screen.Screen;
const Style = tui.style.Style;
const Color = tui.style.Color;
const SubScreen = tui.widget.SubScreen;

const toolbar_label = "ctrl+q quit  ctrl+n new  ctrl+s save  ctrl+r results";
const app_name = "Avocado's Constant";
const min_editor_width: u16 = 24;
const base_bg = Color.hex(0x0B0B0F);
const base_fg = Color.hex(0xE8E8F0);
const accent_fg = Color.hex(0x7EC850);
const muted_fg = Color.hex(0x8B8D97);
const line_fg = Color.hex(0x3A3D45);
const cursor_bg = Color.hex(0xDADAE4);
const cursor_fg = Color.hex(0x0B0B0F);

const PromptMode = enum {
    new_file,
    save,
};

const Layout = struct {
    width: u16,
    height: u16,
    body_y: u16,
    body_height: u16,
    editor_width: u16,
    divider_x: ?u16,
    results_x: ?u16,
    results_width: u16,
    toolbar_y: u16,
};

const FilenameDisplay = struct {
    prefix_len: usize = 0,
    suffix_start: ?usize = null,
    uses_ellipsis: bool = false,
};

const AvocadoShell = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    launch_dir: []u8,
    file_path: ?[]u8 = null,
    config_path: ?[]u8 = null,
    editor: TextArea,
    prompt_input: InputField,
    prompt_mode: ?PromptMode = null,
    requested_results_width: u16 = Avocado.default_results_width,
    results_visible: bool = true,
    dragging_divider: bool = false,
    rendered_results: ?[][]u8 = null,
    last_screen_width: u16 = 80,
    last_screen_height: u16 = 24,

    fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        launch_dir: []const u8,
        config_path: ?[]const u8,
        file_path: ?[]const u8,
        initial_text: []const u8,
    ) !AvocadoShell {
        var editor = try TextArea.initWithContent(allocator, initial_text);
        editor.setFocus(true);

        var prompt_input = InputField.init(allocator);
        prompt_input.setFocus(false);

        var shell = AvocadoShell{
            .allocator = allocator,
            .io = io,
            .launch_dir = try allocator.dupe(u8, launch_dir),
            .file_path = if (file_path) |path| try allocator.dupe(u8, path) else null,
            .config_path = if (config_path) |path| try allocator.dupe(u8, path) else null,
            .editor = editor,
            .prompt_input = prompt_input,
        };
        shell.requested_results_width = shell.loadResultsWidth();
        shell.evaluate() catch {
            shell.setSingleResultMessage("Startup evaluation failed") catch {};
        };
        return shell;
    }

    fn deinit(self: *AvocadoShell) void {
        self.editor.deinit();
        self.prompt_input.deinit();
        self.clearRenderedResults();
        self.allocator.free(self.launch_dir);
        if (self.file_path) |path| self.allocator.free(path);
        if (self.config_path) |path| self.allocator.free(path);
    }

    pub fn render(self: *AvocadoShell, ctx: *RenderContext) void {
        var screen = ctx.getSubScreen();
        screen.setStyle(baseStyle());
        screen.clear();
        self.last_screen_width = screen.width;
        self.last_screen_height = screen.height;

        const layout = computeLayout(screen.width, screen.height, self.results_visible, self.requested_results_width);
        self.drawBanner(&screen);
        self.drawHorizontalRule(&screen, 1, "");
        self.drawBody(&screen, layout);
        self.drawHorizontalRule(&screen, layout.toolbar_y, toolbar_label);

        if (self.prompt_mode != null) {
            self.drawPrompt(&screen);
        }
    }

    pub fn handleEvent(self: *AvocadoShell, event: Event) EventResult {
        switch (event) {
            .resize => {
                self.evaluate() catch {
                    self.setSingleResultMessage("Resize refresh failed") catch {};
                };
                return .needs_redraw;
            },
            .mouse => |mouse_event| return self.handleMouse(mouse_event),
            .key => |key_event| return self.handleKey(key_event),
            .paste => {
                if (self.prompt_mode != null) {
                    _ = self.prompt_input.handleEvent(event);
                } else {
                    _ = self.editor.handleEvent(event);
                    self.evaluate() catch {
                        self.setSingleResultMessage("Evaluation failed") catch {};
                    };
                }
                return .needs_redraw;
            },
            else => return .ignored,
        }
    }

    fn handleKey(self: *AvocadoShell, key_event: KeyEvent) EventResult {
        if (self.prompt_mode != null) {
            return self.handlePromptKey(key_event);
        }

        if (key_event.modifiers.ctrl and key_event.key == .char) {
            const c = std.ascii.toLower(@as(u8, @truncate(key_event.key.char)));
            switch (c) {
                'n' => {
                    self.openPrompt(.new_file) catch {};
                    return .needs_redraw;
                },
                's' => {
                    self.openPrompt(.save) catch {};
                    return .needs_redraw;
                },
                'r' => {
                    self.results_visible = !self.results_visible;
                    self.evaluate() catch {
                        self.setSingleResultMessage("Evaluation failed") catch {};
                    };
                    return .needs_redraw;
                },
                else => {},
            }
        }

        const result = self.editor.handleEvent(.{ .key = key_event });
        switch (result) {
            .ignored => return .ignored,
            else => {
                self.evaluate() catch {
                    self.setSingleResultMessage("Evaluation failed") catch {};
                };
                return .needs_redraw;
            },
        }
    }

    fn handlePromptKey(self: *AvocadoShell, key_event: KeyEvent) EventResult {
        switch (key_event.key) {
            .escape => {
                self.closePrompt();
                return .needs_redraw;
            },
            .enter => {
                self.confirmPrompt() catch {
                    self.setSingleResultMessage("Save failed") catch {};
                };
                return .needs_redraw;
            },
            else => {
                const result = self.prompt_input.handleEvent(.{ .key = key_event });
                return switch (result) {
                    .ignored => .ignored,
                    else => .needs_redraw,
                };
            },
        }
    }

    fn handleMouse(self: *AvocadoShell, mouse_event: MouseEvent) EventResult {
        if (self.prompt_mode != null) return .ignored;
        const layout = computeLayout(self.last_screen_width, self.last_screen_height, self.results_visible, self.requested_results_width);

        if (!self.results_visible) return .ignored;

        switch (mouse_event.kind) {
            .press => {
                if (mouse_event.button == .left and layout.divider_x != null and mouse_event.x == layout.divider_x.?) {
                    self.dragging_divider = true;
                    self.updateResultsWidthForMouse(mouse_event.x, self.last_screen_width);
                    return .needs_redraw;
                }
            },
            .drag => {
                if (self.dragging_divider) {
                    self.updateResultsWidthForMouse(mouse_event.x, self.last_screen_width);
                    return .needs_redraw;
                }
            },
            .release => {
                if (self.dragging_divider) {
                    self.dragging_divider = false;
                    self.saveResultsWidth() catch {};
                    return .needs_redraw;
                }
            },
            else => {},
        }

        return .ignored;
    }

    fn drawBanner(self: *AvocadoShell, screen: *SubScreen) void {
        if (screen.height == 0 or screen.width == 0) return;
        const padding_x: u16 = if (screen.width > 2) 1 else 0;
        const content_width: usize = screen.width -| (padding_x * 2);
        if (content_width == 0) return;

        screen.setStyle(baseStyle());
        screen.moveCursor(0, 0);
        screen.putChar(' ');
        screen.moveCursor(padding_x, 0);
        screen.setStyle(accentStyle());
        screen.putString(app_name);

        if (self.file_path) |path| {
            const app_width = app_name.len;
            if (content_width <= app_width + 1) return;

            const available_right = content_width - app_width - 1;
            const filename = std.fs.path.basename(path);

            if (path.len <= available_right) {
                const x: u16 = padding_x + @as(u16, @intCast(content_width - path.len));
                putStringClipped(screen, x, 0, path, mutedStyle());
                if (lastPathSeparator(path)) |idx| {
                    putStringClipped(screen, x + @as(u16, @intCast(idx + 1)), 0, path[idx + 1 ..], accentStyle());
                } else {
                    putStringClipped(screen, x, 0, path, accentStyle());
                }
            } else {
                const display_width: u16 = @intCast(@min(filename.len, available_right));
                const x: u16 = padding_x + @as(u16, @intCast(content_width - display_width));
                drawFilenameDisplay(screen, x, 0, filename, display_width, accentStyle());
            }
        }
    }

    fn drawHorizontalRule(self: *AvocadoShell, screen: *SubScreen, y: u16, label: []const u8) void {
        _ = self;
        if (y >= screen.height or screen.width == 0) return;

        screen.setStyle(lineStyle());
        screen.moveCursor(0, y);

        if (label.len == 0) {
            var i: u16 = 0;
            while (i < screen.width) : (i += 1) screen.putChar('─');
            return;
        }

        const label_width = label.len + 2;
        if (label_width >= screen.width) {
            putTruncated(screen, 0, y, label, screen.width, accentStyle());
            return;
        }

        const line_width = screen.width - @as(u16, @intCast(label_width));
        var i: u16 = 0;
        while (i < line_width) : (i += 1) screen.putChar('─');
        screen.setStyle(lineStyle().bold());
        screen.putChar(' ');
        screen.putString(label);
        screen.putChar(' ');
    }

    fn drawBody(self: *AvocadoShell, screen: *SubScreen, layout: Layout) void {
        if (layout.body_height == 0 or layout.body_y >= screen.height) return;

        var body = screen.subRegion(0, layout.body_y, layout.width, layout.body_height);
        body.setStyle(baseStyle());
        body.clear();

        var editor_region = body.subRegion(0, 0, layout.editor_width, layout.body_height);
        self.renderEditor(&editor_region);

        if (layout.divider_x) |divider_x| {
            var divider_region = body.subRegion(divider_x, 0, 1, layout.body_height);
            divider_region.setStyle(if (self.dragging_divider) accentStyle() else lineStyle());
            divider_region.clear();
            var y: u16 = 0;
            while (y < divider_region.height) : (y += 1) {
                divider_region.moveCursor(0, y);
                divider_region.putChar('│');
            }
        }

        if (layout.results_x) |results_x| {
            var results_region = body.subRegion(results_x, 0, layout.results_width, layout.body_height);
            self.renderResults(&results_region);
        }
    }

    fn renderEditor(self: *AvocadoShell, region: *SubScreen) void {
        region.setStyle(baseStyle());
        region.clear();

        if (region.width == 0 or region.height == 0) return;

        self.ensureEditorCursorVisible(region.width, region.height);

        var visible_index: u16 = 0;
        while (visible_index < region.height) : (visible_index += 1) {
            const line_index = self.editor.scroll_y + visible_index;
            if (line_index >= self.editor.lines.items.len) break;
            const line = self.editor.lines.items[line_index].items;
            if (self.editor.scroll_x < line.len) {
                const start = self.editor.scroll_x;
                const end = @min(line.len, start + region.width);
                putStringClipped(region, 0, visible_index, line[start..end], baseStyle());
            }
        }

        if (self.editor.cursor_line >= self.editor.scroll_y and self.editor.cursor_line < self.editor.scroll_y + region.height) {
            const cursor_y: u16 = @intCast(self.editor.cursor_line - self.editor.scroll_y);
            if (self.editor.cursor_col >= self.editor.scroll_x and self.editor.cursor_col <= self.editor.scroll_x + region.width) {
                const cursor_x: u16 = @intCast(self.editor.cursor_col - self.editor.scroll_x);
                const line = self.editor.lines.items[self.editor.cursor_line].items;
                const ch: u21 = if (self.editor.cursor_col < line.len) line[self.editor.cursor_col] else ' ';
                region.setStyle(cursorStyle());
                region.moveCursor(@min(cursor_x, region.width -| 1), cursor_y);
                region.putChar(ch);
            }
        }
    }

    fn renderResults(self: *AvocadoShell, region: *SubScreen) void {
        region.setStyle(mutedStyle());
        region.clear();

        if (region.width == 0 or region.height == 0) return;
        const lines = self.rendered_results orelse return;
        const start_line = self.editor.scroll_y;

        var visible_index: u16 = 0;
        while (visible_index < region.height) : (visible_index += 1) {
            const line_index = start_line + visible_index;
            if (line_index >= lines.len) break;
            putStringClipped(region, 0, visible_index, lines[line_index], mutedStyle());
        }
    }

    fn drawPrompt(self: *AvocadoShell, screen: *SubScreen) void {
        const mode = self.prompt_mode orelse return;
        if (screen.height < 5 or screen.width == 0) return;

        const title = switch (mode) {
            .new_file => "Enter document name and path",
            .save => "Enter document name and path",
        };
        const submit = switch (mode) {
            .new_file => "Enter=create",
            .save => "Enter=save",
        };
        var help_buf: [512]u8 = undefined;
        const help = std.fmt.bufPrint(&help_buf, "Relative paths start from {s} and save as .txt", .{self.launch_dir}) catch "Relative paths save as .txt";
        const padding_x: u16 = if (screen.width > 4) 2 else 0;
        const input_width = screen.width -| (padding_x * 2);

        putStringClipped(screen, padding_x, 1, title, accentStyle());

        if (screen.height > 2) {
            var input_region = screen.subRegion(padding_x, 2, input_width, 1);
            self.renderPromptInput(&input_region);
        }
        if (screen.height > 3) {
            const help_width = @min(help.len, input_width);
            const help_x = screen.width -| @as(u16, @intCast(help_width)) -| padding_x;
            putTruncated(screen, help_x, 3, help, input_width, mutedStyle());
        }
        if (screen.height > 4) putStringClipped(screen, padding_x, 4, submit, mutedStyle());
        if (screen.height > 5) putStringClipped(screen, padding_x, 5, "Esc=cancel", mutedStyle());
    }

    fn renderPromptInput(self: *AvocadoShell, region: *SubScreen) void {
        region.setStyle(overlayStyle());
        region.clear();
        if (region.width == 0) return;

        const value = self.prompt_input.getValue();
        const cursor = self.prompt_input.cursor;
        if (cursor < self.prompt_input.scroll_offset) {
            self.prompt_input.scroll_offset = cursor;
        } else if (cursor >= self.prompt_input.scroll_offset + region.width) {
            self.prompt_input.scroll_offset = cursor - region.width + 1;
        }

        const display_text = if (value.len == 0) "path\\to\\document.txt" else value;
        const start = @min(self.prompt_input.scroll_offset, display_text.len);
        const end = @min(display_text.len, start + region.width);
        putStringClipped(region, 0, 0, display_text[start..end], if (value.len == 0) mutedStyle() else overlayStyle());

        const cursor_x: u16 = @intCast(@min(cursor - start, region.width -| 1));
        const ch: u21 = if (cursor < value.len) value[cursor] else ' ';
        region.setStyle(cursorStyle());
        region.moveCursor(cursor_x, 0);
        region.putChar(ch);
    }

    fn ensureEditorCursorVisible(self: *AvocadoShell, width: u16, height: u16) void {
        if (height == 0 or width == 0) return;

        if (self.editor.cursor_line < self.editor.scroll_y) {
            self.editor.scroll_y = self.editor.cursor_line;
        } else if (self.editor.cursor_line >= self.editor.scroll_y + height) {
            self.editor.scroll_y = self.editor.cursor_line - height + 1;
        }

        if (self.editor.cursor_col < self.editor.scroll_x) {
            self.editor.scroll_x = self.editor.cursor_col;
        } else if (self.editor.cursor_col >= self.editor.scroll_x + width) {
            self.editor.scroll_x = self.editor.cursor_col - width + 1;
        }
    }

    fn evaluate(self: *AvocadoShell) !void {
        self.clearRenderedResults();

        const source = try self.editor.getText(self.allocator);
        defer self.allocator.free(source);

        var output = try Avocado.evaluateSourceLinewiseAlloc(self.allocator, source, true);
        defer output.deinit();

        const crop_width: usize = @max(@as(usize, 1), @as(usize, self.requested_results_width) - 1);
        self.rendered_results = try Avocado.truncateLinesAlloc(self.allocator, output.lines.items, crop_width);
    }

    fn setSingleResultMessage(self: *AvocadoShell, message: []const u8) !void {
        self.clearRenderedResults();
        var lines = try self.allocator.alloc([]u8, 1);
        lines[0] = try self.allocator.dupe(u8, message);
        self.rendered_results = lines;
    }

    fn clearRenderedResults(self: *AvocadoShell) void {
        if (self.rendered_results) |lines| {
            for (lines) |line| self.allocator.free(line);
            self.allocator.free(lines);
        }
        self.rendered_results = null;
    }

    fn openPrompt(self: *AvocadoShell, mode: PromptMode) !void {
        self.prompt_mode = mode;
        self.editor.setFocus(false);
        self.prompt_input.setFocus(true);

        const base_dir = if (self.file_path) |path|
            std.fs.path.dirname(path) orelse self.launch_dir
        else
            self.launch_dir;

        const suggestion = switch (mode) {
            .new_file => try std.fs.path.join(self.allocator, &.{ base_dir, "untitled.txt" }),
            .save => if (self.file_path) |path|
                try self.allocator.dupe(u8, path)
            else
                try std.fs.path.join(self.allocator, &.{ self.launch_dir, "untitled.txt" }),
        };
        defer self.allocator.free(suggestion);

        try self.prompt_input.setValue(suggestion);
        self.prompt_input.cursor = suggestion.len;
        self.prompt_input.scroll_offset = 0;
    }

    fn closePrompt(self: *AvocadoShell) void {
        self.prompt_mode = null;
        self.prompt_input.clear();
        self.prompt_input.setFocus(false);
        self.editor.setFocus(true);
    }

    fn confirmPrompt(self: *AvocadoShell) !void {
        const mode = self.prompt_mode orelse return;
        const raw = std.mem.trim(u8, self.prompt_input.getValue(), " \t\r\n");
        if (raw.len == 0) {
            self.closePrompt();
            return;
        }

        const txt_path = try Avocado.ensureTxtPathAlloc(self.allocator, raw);
        defer self.allocator.free(txt_path);

        const resolved = try Avocado.resolveUserPathAlloc(self.allocator, self.launch_dir, txt_path);
        defer self.allocator.free(resolved);

        try self.replaceFilePath(resolved);

        switch (mode) {
            .new_file => {
                self.editor.clear();
                try self.evaluate();
            },
            .save => try self.saveCurrentDocument(),
        }

        self.closePrompt();
    }

    fn replaceFilePath(self: *AvocadoShell, path: []const u8) !void {
        if (self.file_path) |old_path| self.allocator.free(old_path);
        self.file_path = try self.allocator.dupe(u8, path);
    }

    fn saveCurrentDocument(self: *AvocadoShell) !void {
        const path = self.file_path orelse return;
        const text = try self.editor.getText(self.allocator);
        defer self.allocator.free(text);

        if (std.fs.path.dirname(path)) |parent| {
            try std.Io.Dir.cwd().createDirPath(self.io, parent);
        }
        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = path,
            .data = text,
        });
    }

    fn loadResultsWidth(self: *AvocadoShell) u16 {
        const config_path = self.config_path orelse return Avocado.default_results_width;
        const file_path = self.file_path orelse return Avocado.default_results_width;

        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, config_path, self.allocator, .limited(64 * 1024)) catch {
            return Avocado.default_results_width;
        };
        defer self.allocator.free(contents);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, contents, .{}) catch {
            return Avocado.default_results_width;
        };
        defer parsed.deinit();

        if (parsed.value != .object) return Avocado.default_results_width;
        const width_map = parsed.value.object.get("results_width") orelse return Avocado.default_results_width;
        if (width_map != .object) return Avocado.default_results_width;
        const value = width_map.object.get(file_path) orelse return Avocado.default_results_width;
        return clampConfiguredWidth(jsonValueToWidth(value) orelse Avocado.default_results_width);
    }

    fn saveResultsWidth(self: *AvocadoShell) !void {
        const config_path = self.config_path orelse return;
        const file_path = self.file_path orelse return;

        var widths = std.StringHashMap(u16).init(self.allocator);
        defer {
            var it = widths.iterator();
            while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
            widths.deinit();
        }

        if (std.Io.Dir.cwd().readFileAlloc(self.io, config_path, self.allocator, .limited(64 * 1024))) |contents| {
            defer self.allocator.free(contents);
            var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, contents, .{}) catch null;
            if (parsed) |*parsed_value| {
                defer parsed_value.deinit();
                if (parsed_value.value == .object) {
                    if (parsed_value.value.object.get("results_width")) |value| {
                        if (value == .object) {
                            var it = value.object.iterator();
                            while (it.next()) |entry| {
                                if (jsonValueToWidth(entry.value_ptr.*)) |width| {
                                    try putOwnedWidth(&widths, self.allocator, entry.key_ptr.*, clampConfiguredWidth(width));
                                }
                            }
                        }
                    }
                }
            }
        } else |_| {}

        try putOwnedWidth(&widths, self.allocator, file_path, self.requested_results_width);

        if (std.fs.path.dirname(config_path)) |parent| {
            try std.Io.Dir.cwd().createDirPath(self.io, parent);
        }

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();

        var json_writer: std.json.Stringify = .{
            .writer = &out.writer,
            .options = .{ .whitespace = .indent_2 },
        };
        try json_writer.beginObject();
        try json_writer.objectField("results_width");
        try json_writer.beginObject();
        var it = widths.iterator();
        while (it.next()) |entry| {
            try json_writer.objectField(entry.key_ptr.*);
            try json_writer.write(entry.value_ptr.*);
        }
        try json_writer.endObject();
        try json_writer.endObject();

        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = config_path,
            .data = out.written(),
        });
    }

    fn updateResultsWidthForMouse(self: *AvocadoShell, mouse_x: u16, total_width: u16) void {
        if (total_width <= min_editor_width + 1) return;
        const new_width = @max(@as(i32, Avocado.min_results_width), @as(i32, total_width) - @as(i32, mouse_x) - 1);
        const max_width = maxResultsWidth(total_width);
        self.requested_results_width = clampResultsWidth(@min(new_width, max_width));
        self.evaluate() catch {
            self.setSingleResultMessage("Evaluation failed") catch {};
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const launch_dir_z = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(launch_dir_z);
    const launch_dir = launch_dir_z[0..launch_dir_z.len];

    const config_path = try resolveConfigPathAlloc(allocator, init.environ_map);
    defer if (config_path) |path| allocator.free(path);

    var file_path: ?[]u8 = null;
    defer if (file_path) |path| allocator.free(path);

    if (args.len == 2 and std.mem.eql(u8, args[1], "--self-test")) {
        try runSelfTest(io, allocator, launch_dir, config_path);
        return;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "--dump-frame")) {
        const initial_text = try allocator.dupe(u8, "");
        defer allocator.free(initial_text);

        var shell = try AvocadoShell.init(allocator, io, launch_dir, config_path, null, initial_text);
        defer shell.deinit();

        var screen = try Screen.init(allocator, 80, 24);
        defer screen.deinit();

        var theme = tui.Theme.default_theme;
        var ctx = RenderContext{
            .screen = &screen,
            .theme = &theme,
            .bounds = .{ .x = 0, .y = 0, .width = screen.width, .height = screen.height },
            .clip = .{ .x = 0, .y = 0, .width = screen.width, .height = screen.height },
            .focused_id = null,
            .time_ns = 0,
        };
        shell.render(&ctx);
        try dumpScreenPlain(io, allocator, &screen);
        return;
    }

    if (args.len > 2) {
        std.debug.print("usage: avocado [path]\n", .{});
        return error.InvalidArgument;
    }

    if (args.len == 2) {
        file_path = try Avocado.normalizeDocumentPathAlloc(allocator, launch_dir, args[1]);
        try ensureDocumentReady(io, file_path.?);
    }

    const initial_text = if (file_path) |path|
        loadDocumentAlloc(allocator, io, path) catch try allocator.dupe(u8, "")
    else
        try allocator.dupe(u8, "");
    defer allocator.free(initial_text);

    var shell = try AvocadoShell.init(allocator, io, launch_dir, config_path, file_path, initial_text);
    defer shell.deinit();

    const is_windows = builtin.os.tag == .windows;
    var app = try tui.App.initWithAllocator(allocator, .{
        .alternate_screen = !is_windows,
        .hide_cursor = !is_windows,
        .enable_mouse = !is_windows,
        .enable_paste = !is_windows,
        .enable_focus = !is_windows,
    });
    defer app.deinit();

    try app.setRoot(&shell);
    try app.run();
}

fn runSelfTest(io: std.Io, allocator: std.mem.Allocator, launch_dir: []const u8, config_path: ?[]const u8) !void {
    const stdout = std.Io.File.stdout();

    const initial_text = try allocator.dupe(u8, "");
    defer allocator.free(initial_text);

    var shell = try AvocadoShell.init(allocator, io, launch_dir, config_path, null, initial_text);
    defer shell.deinit();

    var screen = try Screen.init(allocator, 80, 24);
    defer screen.deinit();

    var theme = tui.Theme.default_theme;
    var ctx = RenderContext{
        .screen = &screen,
        .theme = &theme,
        .bounds = .{ .x = 0, .y = 0, .width = screen.width, .height = screen.height },
        .clip = .{ .x = 0, .y = 0, .width = screen.width, .height = screen.height },
        .focused_id = null,
        .time_ns = 0,
    };
    shell.render(&ctx);

    if (!screenHasInk(&screen)) return error.EmptyFrame;

    if (builtin.os.tag == .windows) {
        const kernel32 = struct {
            extern "kernel32" fn GetConsoleMode(h: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) std.os.windows.BOOL;
            extern "kernel32" fn SetConsoleMode(h: std.os.windows.HANDLE, mode: u32) callconv(.winapi) std.os.windows.BOOL;
        };

        var out_mode: u32 = 0;
        if (kernel32.GetConsoleMode(stdout.handle, &out_mode) == .FALSE) {
            try stdout.writeStreamingAll(io, "SELFTEST_OK_NO_CONSOLE\n");
            return;
        }

        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
        if (kernel32.SetConsoleMode(stdout.handle, out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING) == .FALSE) return error.VTNotAvailable;
        _ = kernel32.SetConsoleMode(stdout.handle, out_mode);
    }

    try stdout.writeStreamingAll(io, "SELFTEST_OK\n");
}

fn screenHasInk(screen: *const Screen) bool {
    for (0..screen.height) |y| {
        for (0..screen.width) |x| {
            const cell = screen.getCell(@intCast(x), @intCast(y)) orelse continue;
            if (cell.width == 0) continue;
            switch (cell.content) {
                .codepoint => |cp| if (cp != ' ') return true,
                .grapheme => |g| if (!(g.len == 1 and g[0] == ' ')) return true,
            }
        }
    }
    return false;
}

fn dumpScreenPlain(io: std.Io, allocator: std.mem.Allocator, screen: *const Screen) !void {
    const stdout = std.Io.File.stdout();

    var line: std.ArrayListUnmanaged(u8) = .empty;
    defer line.deinit(allocator);

    for (0..screen.height) |y| {
        line.clearRetainingCapacity();
        var keep_len: usize = 0;

        for (0..screen.width) |x| {
            const cell = screen.getCell(@intCast(x), @intCast(y)) orelse continue;
            if (cell.width == 0) continue;

            var buf: [4]u8 = undefined;
            const s = cell.getContent(&buf);
            try line.appendSlice(allocator, s);

            const is_space = switch (cell.content) {
                .codepoint => |cp| cp == ' ',
                .grapheme => |g| g.len == 1 and g[0] == ' ',
            };
            if (!is_space) keep_len = line.items.len;
        }

        try stdout.writeStreamingAll(io, line.items[0..keep_len]);
        try stdout.writeStreamingAll(io, "\n");
    }
}

fn ensureDocumentReady(io: std.Io, path: []const u8) !void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (std.fs.path.dirname(path)) |parent| {
                try std.Io.Dir.cwd().createDirPath(io, parent);
            }
            try std.Io.Dir.cwd().writeFile(io, .{
                .sub_path = path,
                .data = "",
            });
            return;
        },
        else => return err,
    };

    if (stat.kind == .directory) return error.IsDir;
}

fn loadDocumentAlloc(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024));
}

fn resolveConfigPathAlloc(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !?[]u8 {
    const home = environ_map.get("USERPROFILE") orelse environ_map.get("HOME") orelse return null;
    return try std.fs.path.join(allocator, &.{ home, ".avocado", "config.json" });
}

fn computeLayout(total_width: u16, total_height: u16, results_visible: bool, requested_results_width: u16) Layout {
    const toolbar_y = total_height -| 1;
    const body_y: u16 = if (total_height >= 2) 2 else total_height;
    const reserved_rows: u16 = if (total_height >= 3) 3 else total_height;
    const body_height = total_height -| reserved_rows;

    if (!results_visible or total_width <= min_editor_width + 1 + Avocado.min_results_width) {
        return .{
            .width = total_width,
            .height = total_height,
            .body_y = body_y,
            .body_height = body_height,
            .editor_width = total_width,
            .divider_x = null,
            .results_x = null,
            .results_width = 0,
            .toolbar_y = toolbar_y,
        };
    }

    const max_width = maxResultsWidth(total_width);
    const results_width = clampResultsWidth(@min(requested_results_width, max_width));
    const editor_width = total_width -| results_width -| 1;
    return .{
        .width = total_width,
        .height = total_height,
        .body_y = body_y,
        .body_height = body_height,
        .editor_width = editor_width,
        .divider_x = editor_width,
        .results_x = editor_width + 1,
        .results_width = results_width,
        .toolbar_y = toolbar_y,
    };
}

fn maxResultsWidth(total_width: u16) u16 {
    if (total_width <= min_editor_width + 1 + Avocado.min_results_width) {
        return Avocado.min_results_width;
    }
    return @min(Avocado.max_results_width, total_width - min_editor_width - 1);
}

fn clampResultsWidth(width: anytype) u16 {
    const as_i32: i32 = switch (@typeInfo(@TypeOf(width))) {
        .int, .comptime_int => @intCast(width),
        .float, .comptime_float => @intFromFloat(width),
        else => @compileError("unsupported width type"),
    };
    return clampConfiguredWidth(as_i32);
}

fn clampConfiguredWidth(width: i32) u16 {
    return @intCast(std.math.clamp(width, @as(i32, Avocado.min_results_width), @as(i32, Avocado.max_results_width)));
}

fn jsonValueToWidth(value: std.json.Value) ?i32 {
    return switch (value) {
        .integer => |n| std.math.cast(i32, n),
        .float => |n| @intFromFloat(n),
        else => null,
    };
}

fn putOwnedWidth(map: *std.StringHashMap(u16), allocator: std.mem.Allocator, key: []const u8, width: u16) !void {
    if (map.getPtr(key)) |existing| {
        existing.* = width;
        return;
    }
    try map.put(try allocator.dupe(u8, key), width);
}

fn baseStyle() Style {
    return Style.default.setFg(base_fg).setBg(base_bg);
}

fn mutedStyle() Style {
    return baseStyle().setFg(muted_fg);
}

fn accentStyle() Style {
    return baseStyle().setFg(accent_fg).bold();
}

fn lineStyle() Style {
    return baseStyle().setFg(line_fg);
}

fn overlayStyle() Style {
    return baseStyle().setFg(base_fg).setBg(Color.hex(0x17171C));
}

fn cursorStyle() Style {
    return Style.default.setFg(cursor_fg).setBg(cursor_bg);
}

fn putStringClipped(screen: *SubScreen, x: u16, y: u16, text: []const u8, style: Style) void {
    if (y >= screen.height or x >= screen.width) return;
    screen.setStyle(style);
    screen.moveCursor(x, y);
    const width = screen.width - x;
    const end = @min(text.len, width);
    screen.putString(text[0..end]);
}

fn putTruncated(screen: *SubScreen, x: u16, y: u16, text: []const u8, width: u16, style: Style) void {
    if (width == 0 or y >= screen.height or x >= screen.width) return;
    screen.setStyle(style);
    screen.moveCursor(x, y);
    if (text.len <= width) {
        screen.putString(text);
        return;
    }
    if (width == 1) {
        screen.putChar('…');
        return;
    }
    screen.putString(text[0 .. width - 1]);
    screen.putChar('…');
}

fn computeFilenameDisplay(filename: []const u8, width: u16) FilenameDisplay {
    if (width == 0) return .{};
    const width_usize: usize = width;
    if (filename.len <= width_usize) {
        return .{ .prefix_len = filename.len };
    }

    const suffix = std.fs.path.extension(filename);
    if (suffix.len > 0 and suffix.len + 2 <= width_usize) {
        return .{
            .prefix_len = width_usize - suffix.len - 1,
            .suffix_start = filename.len - suffix.len,
            .uses_ellipsis = true,
        };
    }

    return .{
        .prefix_len = if (width_usize == 1) 0 else width_usize - 1,
        .uses_ellipsis = true,
    };
}

fn drawFilenameDisplay(screen: *SubScreen, x: u16, y: u16, filename: []const u8, width: u16, style: Style) void {
    if (width == 0 or y >= screen.height or x >= screen.width) return;

    const display = computeFilenameDisplay(filename, width);
    screen.setStyle(style);
    screen.moveCursor(x, y);

    if (!display.uses_ellipsis) {
        screen.putString(filename[0..display.prefix_len]);
        return;
    }

    if (display.prefix_len > 0) {
        screen.putString(filename[0..display.prefix_len]);
    }
    screen.putChar('…');

    if (display.suffix_start) |suffix_start| {
        const suffix = filename[suffix_start..];
        const remaining = width -| @as(u16, @intCast(display.prefix_len)) -| 1;
        if (remaining > 0) {
            screen.putString(suffix[0..@min(suffix.len, remaining)]);
        }
    }
}

fn lastPathSeparator(path: []const u8) ?usize {
    var idx = path.len;
    while (idx > 0) : (idx -= 1) {
        const ch = path[idx - 1];
        if (ch == '\\' or ch == '/') return idx - 1;
    }
    return null;
}

test "compute layout hides results when terminal is too narrow" {
    const layout = computeLayout(30, 20, true, 44);
    try std.testing.expect(layout.results_x == null);
    try std.testing.expectEqual(@as(u16, 30), layout.editor_width);
}

test "resolve config path uses home directory" {
    const allocator = std.testing.allocator;
    var env = std.process.Environ.Map.init(allocator);
    defer env.deinit();
    try env.put("HOME", "C:/Users/tester");

    const path = (try resolveConfigPathAlloc(allocator, &env)).?;
    defer allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".avocado\\config.json") or std.mem.endsWith(u8, path, ".avocado/config.json"));
}

test "initial render draws banner text" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    var shell = try AvocadoShell.init(allocator, io, "C:\\workspace", null, null, "");
    defer shell.deinit();

    var screen = try Screen.init(allocator, 80, 24);
    defer screen.deinit();

    var ctx = RenderContext{
        .screen = &screen,
        .theme = &tui.Theme.default_theme,
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .clip = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .focused_id = null,
        .time_ns = 0,
    };

    shell.render(&ctx);

    const cell_a = screen.getCell(1, 0).?;
    const cell_v = screen.getCell(2, 0).?;
    const cell_o = screen.getCell(3, 0).?;
    try std.testing.expectEqual(@as(u21, 'A'), cell_a.content.codepoint);
    try std.testing.expectEqual(@as(u21, 'v'), cell_v.content.codepoint);
    try std.testing.expectEqual(@as(u21, 'o'), cell_o.content.codepoint);
}

test "app root render callback draws banner text" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    var shell = try AvocadoShell.init(allocator, io, "C:\\workspace", null, null, "");
    defer shell.deinit();

    var app = try tui.App.initWithAllocator(allocator, .{});
    defer app.deinit();
    try app.setRoot(&shell);

    var screen = try Screen.init(allocator, 80, 24);
    defer screen.deinit();

    var ctx = RenderContext{
        .screen = &screen,
        .theme = &tui.Theme.default_theme,
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .clip = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .focused_id = null,
        .time_ns = 0,
    };

    try std.testing.expect(app.root != null);
    try std.testing.expect(app.root_render_fn != null);
    app.root_render_fn.?(app.root.?, &ctx);

    const cell_a = screen.getCell(1, 0).?;
    try std.testing.expectEqual(@as(u21, 'A'), cell_a.content.codepoint);
}

test "compute filename display preserves suffix when truncated" {
    const display = computeFilenameDisplay("very_long_document_name.txt", 12);
    try std.testing.expect(display.uses_ellipsis);
    try std.testing.expectEqual(@as(usize, 7), display.prefix_len);
    try std.testing.expectEqual(@as(?usize, 23), display.suffix_start);
}

test "compute filename display uses full text when it fits" {
    const display = computeFilenameDisplay("demo.txt", 20);
    try std.testing.expect(!display.uses_ellipsis);
    try std.testing.expectEqual(@as(usize, 8), display.prefix_len);
    try std.testing.expectEqual(@as(?usize, null), display.suffix_start);
}
