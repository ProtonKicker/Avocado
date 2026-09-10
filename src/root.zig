const std = @import("std");

pub const min_results_width: u16 = 12;
pub const max_results_width: u16 = 160;
pub const default_results_width: u16 = 44;

pub const EvalError = error{
    ParseError,
    UnknownIdentifier,
    InvalidCall,
    InvalidIndex,
    InvalidOperation,
    EmptyExpression,
    MismatchedBrackets,
    ZeroStep,
};

pub const NumberArray = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(f64) = .empty,

    pub fn init(allocator: std.mem.Allocator) NumberArray {
        return .{ .allocator = allocator };
    }

    pub fn append(self: *NumberArray, value: f64) !void {
        try self.items.append(self.allocator, value);
    }

    pub fn clone(self: NumberArray, allocator: std.mem.Allocator) !NumberArray {
        var out = NumberArray.init(allocator);
        try out.items.appendSlice(allocator, self.items.items);
        return out;
    }

    pub fn deinit(self: *NumberArray) void {
        self.items.deinit(self.allocator);
        self.* = NumberArray.init(self.allocator);
    }
};

pub const NumberMatrix = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayListUnmanaged(NumberArray) = .empty,

    pub fn init(allocator: std.mem.Allocator) NumberMatrix {
        return .{ .allocator = allocator };
    }

    pub fn appendRow(self: *NumberMatrix, row: NumberArray) !void {
        try self.rows.append(self.allocator, row);
    }

    pub fn clone(self: NumberMatrix, allocator: std.mem.Allocator) !NumberMatrix {
        var out = NumberMatrix.init(allocator);
        for (self.rows.items) |row| {
            try out.rows.append(allocator, try row.clone(allocator));
        }
        return out;
    }

    pub fn deinit(self: *NumberMatrix) void {
        for (self.rows.items) |*row| row.deinit();
        self.rows.deinit(self.allocator);
        self.* = NumberMatrix.init(self.allocator);
    }
};

pub const Value = union(enum) {
    none,
    number: f64,
    py_list: NumberArray,
    array: NumberArray,
    matrix: NumberMatrix,

    pub fn clone(self: Value, allocator: std.mem.Allocator) !Value {
        return switch (self) {
            .none => .none,
            .number => |n| .{ .number = n },
            .py_list => |list| .{ .py_list = try list.clone(allocator) },
            .array => |array| .{ .array = try array.clone(allocator) },
            .matrix => |matrix| .{ .matrix = try matrix.clone(allocator) },
        };
    }

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .py_list => |*list| list.deinit(),
            .array => |*array| array.deinit(),
            .matrix => |*matrix| matrix.deinit(),
            else => {},
        }
        self.* = .none;
    }
};

pub const EvalOutput = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayListUnmanaged([]u8) = .empty,
    namespace: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) EvalOutput {
        return .{
            .allocator = allocator,
            .namespace = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *EvalOutput) void {
        for (self.lines.items) |line| self.allocator.free(line);
        self.lines.deinit(self.allocator);

        var it = self.namespace.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.namespace.deinit();
    }
};

fn cloneIntoNamespace(namespace: *std.StringHashMap(Value), allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
    const gop = try namespace.getOrPut(try allocator.dupe(u8, name));
    if (gop.found_existing) {
        allocator.free(gop.key_ptr.*);
        gop.key_ptr.* = try allocator.dupe(u8, name);
        gop.value_ptr.deinit();
    }
    gop.value_ptr.* = try value.clone(allocator);
}

fn valueToNumber(value: Value) EvalError!f64 {
    return switch (value) {
        .number => |n| n,
        else => EvalError.InvalidOperation,
    };
}

fn floatToI64Checked(value: f64) ?i64 {
    if (std.math.isNan(value) or std.math.isInf(value)) return null;
    const truncated = std.math.trunc(value);
    const max_f: f64 = @floatFromInt(std.math.maxInt(i64));
    const min_f: f64 = @floatFromInt(std.math.minInt(i64));
    if (truncated >= max_f or truncated <= min_f) return null;
    return @intFromFloat(truncated);
}

fn floatToUsizeChecked(value: f64) ?usize {
    if (std.math.isNan(value) or std.math.isInf(value)) return null;
    const truncated = std.math.trunc(value);
    if (truncated < 0) return null;
    const max_f: f64 = @floatFromInt(std.math.maxInt(usize));
    if (truncated >= max_f) return null;
    return @intFromFloat(truncated);
}

fn clampWidth(width: i32) u16 {
    return @intCast(@max(@as(i32, min_results_width), @min(@as(i32, max_results_width), width)));
}

pub fn ensureTxtPathAlloc(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, raw_path, " \t\r\n");
    if (trimmed.len == 0) return allocator.dupe(u8, "untitled.txt");

    var last_sep: ?usize = null;
    var last_dot: ?usize = null;
    for (trimmed, 0..) |ch, idx| {
        if (ch == '/' or ch == '\\') {
            last_sep = idx;
            last_dot = null;
        } else if (ch == '.') {
            last_dot = idx;
        }
    }

    if (last_dot) |dot_idx| {
        const suffix = trimmed[dot_idx..];
        if (std.ascii.eqlIgnoreCase(suffix, ".txt")) {
            return allocator.dupe(u8, trimmed);
        }
        const prefix = trimmed[0..dot_idx];
        return std.fmt.allocPrint(allocator, "{s}.txt", .{prefix});
    }

    return std.fmt.allocPrint(allocator, "{s}.txt", .{trimmed});
}

fn expandUserAlloc(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    if (raw_path.len == 0 or raw_path[0] != '~') return allocator.dupe(u8, raw_path);
    return allocator.dupe(u8, raw_path);
}

pub fn resolveUserPathAlloc(allocator: std.mem.Allocator, launch_dir: []const u8, raw_path: []const u8) ![]u8 {
    const expanded = try expandUserAlloc(allocator, std.mem.trim(u8, raw_path, " \t\r\n"));
    defer allocator.free(expanded);

    if (std.fs.path.isAbsolute(expanded)) {
        return std.fs.path.resolve(allocator, &.{expanded});
    }
    return std.fs.path.resolve(allocator, &.{ launch_dir, expanded });
}

pub fn normalizeDocumentPathAlloc(allocator: std.mem.Allocator, launch_dir: []const u8, raw_path: []const u8) ![]u8 {
    const txt_path = try ensureTxtPathAlloc(allocator, raw_path);
    defer allocator.free(txt_path);
    return resolveUserPathAlloc(allocator, launch_dir, txt_path);
}

fn splitTopLevelAlloc(allocator: std.mem.Allocator, text: []const u8, separator: u8) !std.ArrayList([]const u8) {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);

    var depth: i32 = 0;
    var start: usize = 0;
    for (text, 0..) |ch, idx| {
        switch (ch) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => depth -= 1,
            else => {},
        }
        if (depth == 0 and ch == separator) {
            try out.append(allocator, std.mem.trim(u8, text[start..idx], " \t\r\n"));
            start = idx + 1;
        }
    }
    if (depth != 0) return EvalError.MismatchedBrackets;
    try out.append(allocator, std.mem.trim(u8, text[start..], " \t\r\n"));
    return out;
}

fn topLevelAssignment(line: []const u8) ?struct { name: []const u8, expr: []const u8 } {
    var depth: i32 = 0;
    for (line, 0..) |ch, idx| {
        switch (ch) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => depth -= 1,
            '=' => {
                if (depth != 0) continue;
                if (idx > 0 and (line[idx - 1] == '=' or line[idx - 1] == '!' or line[idx - 1] == '<' or line[idx - 1] == '>')) continue;
                if (idx + 1 < line.len and line[idx + 1] == '=') continue;
                const lhs = std.mem.trim(u8, line[0..idx], " \t\r\n");
                const rhs = std.mem.trim(u8, line[idx + 1 ..], " \t\r\n");
                if (lhs.len == 0 or rhs.len == 0) return null;
                if (!isIdentifier(lhs)) return null;
                return .{ .name = lhs, .expr = rhs };
            },
            else => {},
        }
    }
    return null;
}

fn isIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!(std.ascii.isAlphabetic(text[0]) or text[0] == '_')) return false;
    for (text[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    }
    return true;
}

fn topLevelColonCount(text: []const u8) EvalError!usize {
    var depth: i32 = 0;
    var count: usize = 0;
    for (text) |ch| {
        switch (ch) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => depth -= 1,
            ':' => {
                if (depth == 0) count += 1;
            },
            else => {},
        }
    }
    if (depth != 0) return EvalError.MismatchedBrackets;
    return count;
}

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,
    namespace: *std.StringHashMap(Value),
    line_output: *std.ArrayListUnmanaged(u8),

    fn parseExpression(self: *Parser) anyerror!Value {
        return self.parseAdditive();
    }

    fn parseAdditive(self: *Parser) anyerror!Value {
        var left = try self.parseMultiplicative();
        errdefer left.deinit();

        while (true) {
            self.skipSpaces();
            if (self.peek() == '+') {
                self.pos += 1;
                var right = try self.parseMultiplicative();
                defer right.deinit();
                const lhs = try valueToNumber(left);
                const rhs = try valueToNumber(right);
                left.deinit();
                left = .{ .number = lhs + rhs };
            } else if (self.peek() == '-') {
                self.pos += 1;
                var right = try self.parseMultiplicative();
                defer right.deinit();
                const lhs = try valueToNumber(left);
                const rhs = try valueToNumber(right);
                left.deinit();
                left = .{ .number = lhs - rhs };
            } else break;
        }
        return left;
    }

    fn parseMultiplicative(self: *Parser) anyerror!Value {
        var left = try self.parsePower();
        errdefer left.deinit();

        while (true) {
            self.skipSpaces();
            if (self.peek() == '*') {
                self.pos += 1;
                var right = try self.parsePower();
                defer right.deinit();
                const lhs = try valueToNumber(left);
                const rhs = try valueToNumber(right);
                left.deinit();
                left = .{ .number = lhs * rhs };
            } else if (self.peek() == '/') {
                self.pos += 1;
                var right = try self.parsePower();
                defer right.deinit();
                const lhs = try valueToNumber(left);
                const rhs = try valueToNumber(right);
                left.deinit();
                left = .{ .number = lhs / rhs };
            } else break;
        }
        return left;
    }

    fn parsePower(self: *Parser) anyerror!Value {
        var left = try self.parseUnary();
        errdefer left.deinit();
        self.skipSpaces();
        if (self.peek() == '^') {
            self.pos += 1;
            var right = try self.parsePower();
            defer right.deinit();
            const lhs = try valueToNumber(left);
            const rhs = try valueToNumber(right);
            left.deinit();
            left = .{ .number = std.math.pow(f64, lhs, rhs) };
        }
        return left;
    }

    fn parseUnary(self: *Parser) anyerror!Value {
        self.skipSpaces();
        if (self.peek() == '+') {
            self.pos += 1;
            return self.parseUnary();
        }
        if (self.peek() == '-') {
            self.pos += 1;
            var inner = try self.parseUnary();
            defer inner.deinit();
            return .{ .number = -(try valueToNumber(inner)) };
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) anyerror!Value {
        var value = try self.parsePrimary();
        errdefer value.deinit();

        while (true) {
            self.skipSpaces();
            if (self.peek() == '[') {
                self.pos += 1;
                var index_value = try self.parseExpression();
                defer index_value.deinit();
                self.skipSpaces();
                if (self.peek() != ']') return EvalError.ParseError;
                self.pos += 1;
                const raw_index = try valueToNumber(index_value);
                const idx = floatToUsizeChecked(raw_index) orelse return EvalError.InvalidIndex;
                value = try self.indexValue(value, idx);
            } else break;
        }
        return value;
    }

    fn parsePrimary(self: *Parser) anyerror!Value {
        self.skipSpaces();
        const ch = self.peek() orelse return EvalError.EmptyExpression;
        if (ch == '(') {
            self.pos += 1;
            var inner = try self.parseExpression();
            self.skipSpaces();
            if (self.peek() != ')') {
                inner.deinit();
                return EvalError.ParseError;
            }
            self.pos += 1;
            return inner;
        }
        if (ch == '[') return self.parseBracketLiteral();
        if (std.ascii.isDigit(ch) or ch == '.') return self.parseNumber();
        if (std.ascii.isAlphabetic(ch) or ch == '_') return self.parseIdentifierOrCall();
        return EvalError.ParseError;
    }

    fn parseNumber(self: *Parser) anyerror!Value {
        const start = self.pos;
        var saw_dot = false;
        while (self.peek()) |ch| {
            if (std.ascii.isDigit(ch)) {
                self.pos += 1;
            } else if (ch == '.' and !saw_dot) {
                saw_dot = true;
                self.pos += 1;
            } else break;
        }
        const slice = self.source[start..self.pos];
        return .{ .number = try std.fmt.parseFloat(f64, slice) };
    }

    fn parseIdentifierOrCall(self: *Parser) anyerror!Value {
        const name = self.parseIdentifier();
        self.skipSpaces();
        if (self.peek() == '(') {
            self.pos += 1;
            var args: std.ArrayList(Value) = .empty;
            defer {
                for (args.items) |*item| item.deinit();
                args.deinit(self.allocator);
            }

            self.skipSpaces();
            if (self.peek() != ')') {
                while (true) {
                    try args.append(self.allocator, try self.parseExpression());
                    self.skipSpaces();
                    if (self.peek() == ',') {
                        self.pos += 1;
                        continue;
                    }
                    break;
                }
            }
            if (self.peek() != ')') return EvalError.ParseError;
            self.pos += 1;
            return self.callBuiltin(name, args.items);
        }

        if (self.namespace.get(name)) |value| {
            return value.clone(self.allocator);
        }
        if (builtinValue(name)) |value| {
            return value;
        }
        return EvalError.UnknownIdentifier;
    }

    fn parseIdentifier(self: *Parser) []const u8 {
        const start = self.pos;
        self.pos += 1;
        while (self.peek()) |ch| {
            if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                self.pos += 1;
            } else break;
        }
        return self.source[start..self.pos];
    }

    fn parseBracketLiteral(self: *Parser) anyerror!Value {
        const start = self.pos;
        const end = try self.findMatchingBracket(start);
        const content = self.source[start + 1 .. end];
        self.pos = end + 1;

        if (std.mem.indexOfScalar(u8, content, ';') != null or isWhitespaceMatrix(content)) {
            return parseMatrixLiteralAlloc(self.allocator, self.namespace, content);
        }
        return parsePythonListAlloc(self.allocator, self.namespace, content);
    }

    fn findMatchingBracket(self: *Parser, start: usize) !usize {
        var depth: i32 = 0;
        for (self.source[start..], start..) |ch, idx| {
            if (ch == '[') depth += 1;
            if (ch == ']') {
                depth -= 1;
                if (depth == 0) return idx;
            }
        }
        return EvalError.MismatchedBrackets;
    }

    fn callBuiltin(self: *Parser, name: []const u8, args: []Value) anyerror!Value {
        _ = self;
        if (std.mem.eql(u8, name, "sin")) return .{ .number = @sin(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "cos")) return .{ .number = @cos(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "tan")) return .{ .number = @tan(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "asin") or std.mem.eql(u8, name, "arcsin")) return .{ .number = std.math.asin(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "acos") or std.mem.eql(u8, name, "arccos")) return .{ .number = std.math.acos(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "atan") or std.mem.eql(u8, name, "arctan")) return .{ .number = std.math.atan(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "ln")) return .{ .number = @log(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "log")) return .{ .number = std.math.log10(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "sqrt")) return .{ .number = std.math.sqrt(try valueToNumber(args[0])) };
        if (std.mem.eql(u8, name, "int")) {
            const value = try valueToNumber(args[0]);
            const as_i64 = floatToI64Checked(value) orelse return EvalError.InvalidCall;
            return .{ .number = @floatFromInt(as_i64) };
        }
        return EvalError.InvalidCall;
    }

    fn indexValue(self: *Parser, value_in: Value, idx: usize) anyerror!Value {
        _ = self;
        var original = value_in;
        defer original.deinit();
        return switch (original) {
            .py_list => |list| blk: {
                if (idx >= list.items.items.len) break :blk EvalError.InvalidIndex;
                break :blk Value{ .number = list.items.items[idx] };
            },
            .array => |array| blk: {
                if (idx >= array.items.items.len) break :blk EvalError.InvalidIndex;
                break :blk Value{ .number = array.items.items[idx] };
            },
            else => EvalError.InvalidIndex,
        };
    }

    fn skipSpaces(self: *Parser) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) : (self.pos += 1) {}
    }

    fn remainingTrimmed(self: *Parser) []const u8 {
        return std.mem.trim(u8, self.source[self.pos..], " \t\r\n");
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }
};

fn parsePythonListAlloc(allocator: std.mem.Allocator, namespace: *std.StringHashMap(Value), content: []const u8) anyerror!Value {
    var list = NumberArray.init(allocator);
    var parts = try splitTopLevelAlloc(allocator, content, ',');
    defer parts.deinit(allocator);

    if (parts.items.len == 1 and parts.items[0].len == 0) return .{ .py_list = list };
    for (parts.items) |part| {
        var temp = try evaluateExpressionAlloc(allocator, namespace, part);
        defer temp.deinit();
        try list.append(try valueToNumber(temp));
    }
    return .{ .py_list = list };
}

fn evaluateRangeWholeAlloc(allocator: std.mem.Allocator, namespace: *std.StringHashMap(Value), expr: []const u8) anyerror!Value {
    var parts = try splitTopLevelAlloc(allocator, expr, ':');
    defer parts.deinit(allocator);

    if (parts.items.len != 2 and parts.items.len != 3) return EvalError.ParseError;

    var start_value = try evaluateExpressionAlloc(allocator, namespace, parts.items[0]);
    defer start_value.deinit();
    var stop_value = try evaluateExpressionAlloc(allocator, namespace, parts.items[parts.items.len - 1]);
    defer stop_value.deinit();

    const start_num = try valueToNumber(start_value);
    const stop_num = try valueToNumber(stop_value);
    const step_num = if (parts.items.len == 3) blk: {
        var temp = try evaluateExpressionAlloc(allocator, namespace, parts.items[1]);
        defer temp.deinit();
        break :blk try valueToNumber(temp);
    } else if (stop_num >= start_num) @as(f64, 1.0) else @as(f64, -1.0);

    if (std.math.approxEqAbs(f64, step_num, 0.0, 1e-12)) return EvalError.ZeroStep;

    var array = NumberArray.init(allocator);
    const epsilon = @abs(step_num) * 1e-9 + 1e-12;
    var current = start_num;
    if (step_num > 0) {
        while (current <= stop_num + epsilon) : (current += step_num) try array.append(current);
    } else {
        while (current >= stop_num - epsilon) : (current += step_num) try array.append(current);
    }
    return .{ .array = array };
}

fn parseMatrixLiteralAlloc(allocator: std.mem.Allocator, namespace: *std.StringHashMap(Value), content: []const u8) anyerror!Value {
    var matrix = NumberMatrix.init(allocator);
    var row_parts = try splitTopLevelAlloc(allocator, content, ';');
    defer row_parts.deinit(allocator);

    for (row_parts.items) |row_text| {
        var row = NumberArray.init(allocator);
        errdefer row.deinit();

        if (std.mem.indexOfScalar(u8, row_text, ',') != null) {
            var parts = try splitTopLevelAlloc(allocator, row_text, ',');
            defer parts.deinit(allocator);
            for (parts.items) |part| {
                var temp = try evaluateExpressionAlloc(allocator, namespace, part);
                defer temp.deinit();
                try row.append(try valueToNumber(temp));
            }
        } else {
            var token_iter = std.mem.tokenizeAny(u8, row_text, " \t");
            while (token_iter.next()) |token| {
                var temp = try evaluateExpressionAlloc(allocator, namespace, token);
                defer temp.deinit();
                try row.append(try valueToNumber(temp));
            }
        }

        if (row.items.items.len == 0) return EvalError.ParseError;
        try matrix.appendRow(row);
    }
    return .{ .matrix = matrix };
}

fn isWhitespaceMatrix(content: []const u8) bool {
    if (std.mem.indexOfScalar(u8, content, ',') != null) return false;
    var token_iter = std.mem.tokenizeAny(u8, content, " \t");
    var count: usize = 0;
    while (token_iter.next() != null) count += 1;
    return count > 1;
}

fn builtinValue(name: []const u8) ?Value {
    if (std.mem.eql(u8, name, "pi")) return .{ .number = std.math.pi };
    if (std.mem.eql(u8, name, "e")) return .{ .number = std.math.e };
    if (std.mem.eql(u8, name, "tau")) return .{ .number = std.math.tau };
    if (std.mem.eql(u8, name, "g")) return .{ .number = 9.80665 };
    if (std.mem.eql(u8, name, "c")) return .{ .number = 299_792_458.0 };
    if (std.mem.eql(u8, name, "G")) return .{ .number = 6.67430e-11 };
    if (std.mem.eql(u8, name, "h")) return .{ .number = 6.62607015e-34 };
    if (std.mem.eql(u8, name, "k")) return .{ .number = 1.380649e-23 };
    if (std.mem.eql(u8, name, "mu0")) return .{ .number = 1.25663706212e-6 };
    if (std.mem.eql(u8, name, "eps0") or std.mem.eql(u8, name, "epsilon0") or std.mem.eql(u8, name, "varepsilon0")) return .{ .number = 8.8541878128e-12 };
    if (std.mem.eql(u8, name, "NA")) return .{ .number = 6.02214076e23 };
    if (std.mem.eql(u8, name, "R")) return .{ .number = 8.31446261815324 };
    if (std.mem.eql(u8, name, "F")) return .{ .number = 96485.33212331001 };
    if (std.mem.eql(u8, name, "atm")) return .{ .number = 101325.0 };
    if (std.mem.eql(u8, name, "Vm")) return .{ .number = 22.413969545014137 };
    if (std.mem.eql(u8, name, "np") or std.mem.eql(u8, name, "numpy")) return .none;
    return null;
}

pub fn evaluateExpressionAlloc(allocator: std.mem.Allocator, namespace: *std.StringHashMap(Value), expr: []const u8) anyerror!Value {
    var output = std.ArrayListUnmanaged(u8).empty;
    defer output.deinit(allocator);
    const trimmed = std.mem.trim(u8, expr, " \t\r\n");
    if (trimmed.len == 0) return EvalError.EmptyExpression;
    const colon_count = try topLevelColonCount(trimmed);
    if (colon_count == 1 or colon_count == 2) {
        return evaluateRangeWholeAlloc(allocator, namespace, trimmed);
    }

    var parser = Parser{
        .allocator = allocator,
        .source = trimmed,
        .namespace = namespace,
        .line_output = &output,
    };
    var value = try parser.parseExpression();
    parser.skipSpaces();
    if (parser.pos != parser.source.len) {
        value.deinit();
        return EvalError.ParseError;
    }
    return value;
}

pub fn formatValueAlloc(allocator: std.mem.Allocator, value: Value) ![]u8 {
    switch (value) {
        .none => return allocator.dupe(u8, "None"),
        .number => |n| return formatNumberOnlyAlloc(allocator, n),
        .py_list => |list| return formatNumberArrayAlloc(allocator, list, ", ", "[", "]"),
        .array => |list| return formatNumberArrayAlloc(allocator, list, ", ", "[", "]"),
        .matrix => |matrix| {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(allocator);
            try out.append(allocator, '[');
            for (matrix.rows.items, 0..) |row, idx| {
                const row_text = try formatNumberArrayAlloc(allocator, row, ", ", "[", "]");
                defer allocator.free(row_text);
                try out.appendSlice(allocator, row_text);
                if (idx + 1 < matrix.rows.items.len) try out.appendSlice(allocator, ", ");
            }
            try out.append(allocator, ']');
            return out.toOwnedSlice(allocator);
        },
    }
}

fn formatNumberOnlyAlloc(allocator: std.mem.Allocator, n: f64) ![]u8 {
    const rounded = @round(n);
    if (std.math.approxEqAbs(f64, rounded, n, 1e-9)) {
        if (floatToI64Checked(rounded)) |as_i64| {
            return std.fmt.allocPrint(allocator, "{d}", .{as_i64});
        }
    }
    return std.fmt.allocPrint(allocator, "{d}", .{n});
}

fn formatNumberArrayAlloc(allocator: std.mem.Allocator, array: NumberArray, joiner: []const u8, prefix: []const u8, suffix: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, prefix);
    for (array.items.items, 0..) |item, idx| {
        const item_text = try formatNumberOnlyAlloc(allocator, item);
        defer allocator.free(item_text);
        try out.appendSlice(allocator, item_text);
        if (idx + 1 < array.items.items.len) try out.appendSlice(allocator, joiner);
    }
    try out.appendSlice(allocator, suffix);
    return out.toOwnedSlice(allocator);
}

pub fn truncateLinesAlloc(allocator: std.mem.Allocator, lines: []const []const u8, width: usize) ![][]u8 {
    var out = try allocator.alloc([]u8, lines.len);
    for (lines, 0..) |line, idx| {
        if (width == 0) {
            out[idx] = try allocator.dupe(u8, "");
        } else if (line.len <= width) {
            out[idx] = try allocator.dupe(u8, line);
        } else if (width == 1) {
            out[idx] = try allocator.dupe(u8, "…");
        } else {
            out[idx] = try std.fmt.allocPrint(allocator, "{s}…", .{line[0 .. width - 1]});
        }
    }
    return out;
}

pub fn evaluateSourceLinewiseAlloc(allocator: std.mem.Allocator, source: []const u8, stop_on_error: bool) !EvalOutput {
    var output = EvalOutput.init(allocator);
    errdefer output.deinit();

    var error_seen = false;
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (error_seen and stop_on_error) {
            try output.lines.append(allocator, try allocator.dupe(u8, "Skipped"));
            continue;
        }
        if (trimmed.len == 0 or trimmed[0] == '#') {
            try output.lines.append(allocator, try allocator.dupe(u8, ""));
            continue;
        }

        if (topLevelAssignment(trimmed)) |assignment| {
            var value = evaluateExpressionAlloc(allocator, &output.namespace, assignment.expr) catch |err| {
                const text = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(err), assignment.expr });
                try output.lines.append(allocator, text);
                error_seen = true;
                continue;
            };
            defer value.deinit();
            try cloneIntoNamespace(&output.namespace, allocator, assignment.name, value);
            try output.lines.append(allocator, try formatValueAlloc(allocator, value));
            continue;
        }

        var value = evaluateExpressionAlloc(allocator, &output.namespace, trimmed) catch |err| {
            const text = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(err), trimmed });
            try output.lines.append(allocator, text);
            error_seen = true;
            continue;
        };
        defer value.deinit();
        try output.lines.append(allocator, try formatValueAlloc(allocator, value));
    }

    return output;
}

test "ensure txt path rewrites non txt suffixes" {
    const allocator = std.testing.allocator;
    const a = try ensureTxtPathAlloc(allocator, "notes");
    defer allocator.free(a);
    const b = try ensureTxtPathAlloc(allocator, "notes.py");
    defer allocator.free(b);
    const c = try ensureTxtPathAlloc(allocator, "notes.txt");
    defer allocator.free(c);

    try std.testing.expectEqualStrings("notes.txt", a);
    try std.testing.expectEqualStrings("notes.txt", b);
    try std.testing.expectEqualStrings("notes.txt", c);
}

test "resolve user path uses launch dir for relative paths" {
    const allocator = std.testing.allocator;
    const launch_dir = try std.fs.path.resolve(allocator, &.{ "C:/workspace/demo" });
    defer allocator.free(launch_dir);
    const resolved = try resolveUserPathAlloc(allocator, launch_dir, "nested/file.txt");
    defer allocator.free(resolved);
    const expected = try std.fs.path.resolve(allocator, &.{ launch_dir, "nested/file.txt" });
    defer allocator.free(expected);

    try std.testing.expectEqualStrings(expected, resolved);
}

test "evaluate int and addition" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "int(3.14)\n1 + int(3.14)", true);
    defer out.deinit();

    try std.testing.expectEqualStrings("3", out.lines.items[0]);
    try std.testing.expectEqualStrings("4", out.lines.items[1]);
}

test "math aliases and assignments share namespace" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "x = 3\ny = e^x\nz = sin(pi / 2) + x", true);
    defer out.deinit();

    try std.testing.expect(out.namespace.contains("x"));
    try std.testing.expect(out.namespace.contains("y"));
    try std.testing.expect(out.namespace.contains("z"));
}

test "matlab range and matrix literals" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "r = 1:1:5\nm = [1 2 3; 4 5 6]", true);
    defer out.deinit();

    const r = out.namespace.get("r").?;
    const m = out.namespace.get("m").?;
    try std.testing.expectEqual(@as(usize, 5), r.array.items.items.len);
    try std.testing.expectEqual(@as(usize, 2), m.matrix.rows.items.len);
    try std.testing.expectEqual(@as(usize, 3), m.matrix.rows.items[0].items.items.len);
}

test "python lists and indexing still work" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "items = [1, 2, 3]\nitems[1]", true);
    defer out.deinit();

    try std.testing.expectEqualStrings("[1, 2, 3]", out.lines.items[0]);
    try std.testing.expectEqualStrings("2", out.lines.items[1]);
}

test "invalid indices do not trap" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "items = [1, 2, 3]\nitems[-1]\nitems[18446744073709551616]", false);
    defer out.deinit();
    try std.testing.expect(std.mem.startsWith(u8, out.lines.items[1], "InvalidIndex"));
    try std.testing.expect(std.mem.startsWith(u8, out.lines.items[2], "InvalidIndex"));
}

test "int out of range does not trap" {
    const allocator = std.testing.allocator;
    var out = try evaluateSourceLinewiseAlloc(allocator, "int(1/0)", true);
    defer out.deinit();
    try std.testing.expect(std.mem.startsWith(u8, out.lines.items[0], "InvalidCall"));
}
