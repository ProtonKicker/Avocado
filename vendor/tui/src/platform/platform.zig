//! Platform abstraction layer for cross-platform terminal handling.
//!
//! This module provides a unified interface for terminal operations across
//! Linux, macOS, and Windows platforms.

const std = @import("std");
const builtin = @import("builtin");

/// Saved handle for control handler
var saved_windows_handle: ?WindowsHandle = null;

/// Windows control handler to restore console state on exit
fn windowsCtrlHandler(ctrl_type: u32) callconv(.winapi) std.os.windows.BOOL {
    _ = ctrl_type;
    if (saved_windows_handle) |handle| {
        const kernel32 = struct {
            extern "kernel32" fn SetConsoleMode(h: std.os.windows.HANDLE, mode: u32) callconv(.winapi) std.os.windows.BOOL;
            extern "kernel32" fn SetConsoleCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
            extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        };

        _ = kernel32.SetConsoleMode(handle.stdin_handle, handle.original_input_mode);
        _ = kernel32.SetConsoleMode(handle.stdout_handle, handle.original_output_mode);

        if (handle.original_input_cp != 0) _ = kernel32.SetConsoleCP(handle.original_input_cp);
        if (handle.original_output_cp != 0) _ = kernel32.SetConsoleOutputCP(handle.original_output_cp);
    }
    return .FALSE;
}

/// Platform-specific terminal handle type
pub const TerminalHandle = switch (builtin.os.tag) {
    .windows => WindowsHandle,
    else => PosixHandle,
};

/// POSIX terminal handle (Linux/macOS)
pub const PosixHandle = struct {
    fd: std.posix.fd_t,
    original_termios: ?std.posix.termios = null,

    pub fn init() PosixHandle {
        return .{ .fd = std.posix.STDOUT_FILENO };
    }

    pub fn getInputFd() std.posix.fd_t {
        return std.posix.STDIN_FILENO;
    }
};

/// Windows console handle
pub const WindowsHandle = struct {
    stdout_handle: std.os.windows.HANDLE,
    stdin_handle: std.os.windows.HANDLE,
    original_input_mode: u32 = 0,
    original_output_mode: u32 = 0,
    original_input_cp: u32 = 0,
    original_output_cp: u32 = 0,

    const INVALID_HANDLE_VALUE = @as(std.os.windows.HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))));

    pub fn init() WindowsHandle {
        const kernel32 = struct {
            extern "kernel32" fn GetStdHandle(nStdHandle: i32) callconv(.winapi) std.os.windows.HANDLE;
        };

        const STD_INPUT_HANDLE: i32 = -10;
        const STD_OUTPUT_HANDLE: i32 = -11;

        const stdin = kernel32.GetStdHandle(STD_INPUT_HANDLE);
        const stdout = kernel32.GetStdHandle(STD_OUTPUT_HANDLE);

        const stdin_handle = if (stdin != INVALID_HANDLE_VALUE and @intFromPtr(stdin) != 0)
            stdin
        else
            std.os.windows.peb().ProcessParameters.hStdInput;

        const stdout_handle = if (stdout != INVALID_HANDLE_VALUE and @intFromPtr(stdout) != 0)
            stdout
        else
            std.os.windows.peb().ProcessParameters.hStdOutput;

        return .{
            .stdout_handle = stdout_handle,
            .stdin_handle = stdin_handle,
        };
    }
};

/// Terminal dimensions
pub const TerminalSize = struct {
    cols: u16,
    rows: u16,

    pub fn default() TerminalSize {
        return .{ .cols = 80, .rows = 24 };
    }
};

/// Get terminal size
pub fn getTerminalSize() !TerminalSize {
    switch (builtin.os.tag) {
        .windows => return getWindowsTerminalSize(),
        else => return getPosixTerminalSize(),
    }
}

fn getPosixTerminalSize() !TerminalSize {
    var wsz: std.posix.winsize = .{
        .col = 0,
        .row = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (result != 0) {
        return TerminalSize.default();
    }

    return .{
        .cols = wsz.col,
        .rows = wsz.row,
    };
}

fn getWindowsTerminalSize() !TerminalSize {
    if (builtin.os.tag != .windows) {
        return TerminalSize.default();
    }

    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: extern struct { X: i16, Y: i16 },
        dwCursorPosition: extern struct { X: i16, Y: i16 },
        wAttributes: u16,
        srWindow: extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 },
        dwMaximumWindowSize: extern struct { X: i16, Y: i16 },
    };

    const kernel32 = struct {
        extern "kernel32" fn GetConsoleScreenBufferInfo(
            handle: std.os.windows.HANDLE,
            info: *CONSOLE_SCREEN_BUFFER_INFO,
        ) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetStdHandle(nStdHandle: i32) callconv(.winapi) std.os.windows.HANDLE;
    };

    const STD_OUTPUT_HANDLE: i32 = -11;
    const handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE);

    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(handle, &info) == .FALSE) {
        return TerminalSize.default();
    }

    return .{
        .cols = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
        .rows = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
    };
}

/// Enable raw mode for terminal input
pub fn enableRawMode(handle: *TerminalHandle) !void {
    switch (builtin.os.tag) {
        .windows => try enableWindowsRawMode(handle),
        else => try enablePosixRawMode(handle),
    }
}

/// Disable raw mode and restore terminal
pub fn disableRawMode(handle: *TerminalHandle) void {
    switch (builtin.os.tag) {
        .windows => disableWindowsRawMode(handle),
        else => disablePosixRawMode(handle),
    }
}

fn enablePosixRawMode(handle: *PosixHandle) !void {
    handle.original_termios = try std.posix.tcgetattr(handle.fd);
    var raw = handle.original_termios.?;

    // Input flags: disable break signal, CR to NL, parity, strip, flow control
    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;

    // Output flags: disable post-processing
    raw.oflag.OPOST = false;

    // Control flags: set 8-bit chars
    raw.cflag.CSIZE = .CS8;

    // Local flags: disable echo, canonical mode, signals, extended input
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    // Read with timeout
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 100ms timeout

    try std.posix.tcsetattr(handle.fd, .FLUSH, raw);
}

fn disablePosixRawMode(handle: *PosixHandle) void {
    if (handle.original_termios) |orig| {
        std.posix.tcsetattr(handle.fd, .FLUSH, orig) catch {};
        handle.original_termios = null;
    }
}

fn enableWindowsRawMode(handle: *WindowsHandle) !void {
    if (builtin.os.tag != .windows) return;

    const kernel32 = struct {
        extern "kernel32" fn GetConsoleMode(h: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(h: std.os.windows.HANDLE, mode: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetConsoleCP() callconv(.winapi) u32;
        extern "kernel32" fn SetConsoleCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
        extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleCtrlHandler(HandlerRoutine: ?*const fn (u32) callconv(.winapi) std.os.windows.BOOL, Add: std.os.windows.BOOL) callconv(.winapi) std.os.windows.BOOL;
    };

    // Save original CPs
    handle.original_input_cp = kernel32.GetConsoleCP();
    handle.original_output_cp = kernel32.GetConsoleOutputCP();

    // Set UTF-8 CP (65001)
    _ = kernel32.SetConsoleCP(65001);
    _ = kernel32.SetConsoleOutputCP(65001);

    // Save original modes
    const got_in = kernel32.GetConsoleMode(handle.stdin_handle, &handle.original_input_mode) != .FALSE;
    const got_out = kernel32.GetConsoleMode(handle.stdout_handle, &handle.original_output_mode) != .FALSE;

    // Register control handler
    saved_windows_handle = handle.*;
    _ = kernel32.SetConsoleCtrlHandler(windowsCtrlHandler, @enumFromInt(1));

    if (got_out) {
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
        _ = kernel32.SetConsoleMode(handle.stdout_handle, handle.original_output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }

    if (got_in) {
        const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
        const ENABLE_LINE_INPUT: u32 = 0x0002;
        const ENABLE_ECHO_INPUT: u32 = 0x0004;
        const ENABLE_WINDOW_INPUT: u32 = 0x0008;
        const ENABLE_MOUSE_INPUT: u32 = 0x0010;
        const ENABLE_EXTENDED_FLAGS: u32 = 0x0080;
        const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

        var new_mode: u32 = handle.original_input_mode;
        new_mode |= ENABLE_EXTENDED_FLAGS | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT | ENABLE_VIRTUAL_TERMINAL_INPUT;
        new_mode &= ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
        _ = kernel32.SetConsoleMode(handle.stdin_handle, new_mode);
    }
}

fn disableWindowsRawMode(handle: *WindowsHandle) void {
    if (builtin.os.tag != .windows) return;

    const kernel32 = struct {
        extern "kernel32" fn SetConsoleMode(h: std.os.windows.HANDLE, mode: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleCtrlHandler(HandlerRoutine: ?*const fn (u32) callconv(.winapi) std.os.windows.BOOL, Add: std.os.windows.BOOL) callconv(.winapi) std.os.windows.BOOL;
    };

    // Unregister control handler
    _ = kernel32.SetConsoleCtrlHandler(windowsCtrlHandler, .FALSE);
    saved_windows_handle = null;

    _ = kernel32.SetConsoleMode(handle.stdin_handle, handle.original_input_mode);
    _ = kernel32.SetConsoleMode(handle.stdout_handle, handle.original_output_mode);

    // Restore original CPs
    if (handle.original_input_cp != 0) _ = kernel32.SetConsoleCP(handle.original_input_cp);
    if (handle.original_output_cp != 0) _ = kernel32.SetConsoleOutputCP(handle.original_output_cp);
}

/// Write bytes to terminal
pub fn write(bytes: []const u8) !void {
    const stdout = std.Io.File.stdout();
    const io = std.Io.Threaded.global_single_threaded.io();
    try stdout.writeStreamingAll(io, bytes);
}

/// Flush terminal output
pub fn flush() void {
    // stdout is typically line-buffered, but we want immediate output
    // In Zig, std.io.getStdOut() returns an unbuffered writer
}

/// Check if we're running in a terminal
pub fn isTerminal() bool {
    switch (builtin.os.tag) {
        .windows => {
            const kernel32 = struct {
                extern "kernel32" fn GetConsoleMode(h: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) std.os.windows.BOOL;
                extern "kernel32" fn GetStdHandle(nStdHandle: i32) callconv(.winapi) std.os.windows.HANDLE;
            };
            const STD_OUTPUT_HANDLE: i32 = -11;
            const handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE);
            var mode: u32 = undefined;
            return kernel32.GetConsoleMode(handle, &mode) != .FALSE;
        },
        else => {
            return std.c.isatty(std.posix.STDOUT_FILENO) != 0;
        },
    }
}

/// Get an environment variable, returning null if not found
fn getEnvOwned(allocator: std.mem.Allocator, key: [*:0]const u8) ?[]u8 {
    const value = std.c.getenv(key) orelse return null;
    return allocator.dupe(u8, std.mem.span(value)) catch null;
}

/// Get the terminal type from TERM environment variable
pub fn getTermType() []const u8 {
    return getEnvOwned(std.heap.page_allocator, "TERM") orelse "xterm-256color";
}

/// Check if the terminal supports true color (24-bit)
pub fn supportsTrueColor() bool {
    const colorterm = getEnvOwned(std.heap.page_allocator, "COLORTERM") orelse return false;
    defer std.heap.page_allocator.free(colorterm);
    return std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit");
}

/// Check if the terminal supports 256 colors
pub fn supports256Colors() bool {
    const term = getTermType();
    return std.mem.indexOf(u8, term, "256color") != null;
}

test "terminal size" {
    const size = try getTerminalSize();
    try std.testing.expect(size.cols > 0);
    try std.testing.expect(size.rows > 0);
}

test "is terminal check" {
    // Just test that it doesn't crash
    _ = isTerminal();
}
