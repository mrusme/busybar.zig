const std = @import("std");

const Args = @This();

positionals: std.ArrayList([]const u8),
options: std.ArrayList(Option),
allocator: std.mem.Allocator,

pub const Option = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const Error = error{
    MissingOptionValue,
    OutOfMemory,
};

const value_options = [_][]const u8{
    "a",       "address",  "align", "app",      "cert",     "color",
    "display", "end",      "file",  "filename", "font",     "gateway",
    "id",      "ip",       "key",   "led",      "mask",     "name",
    "output",  "password", "path",  "priority", "security", "ssid",
    "start",   "startup",  "stock", "t",        "timeout",  "token",
    "url",     "width",    "x",     "y",
};

pub fn parse(allocator: std.mem.Allocator, argv: []const [:0]const u8) Error!Args {
    var self: Args = .{
        .positionals = .empty,
        .options = .empty,
        .allocator = allocator,
    };
    errdefer self.deinit();

    var index: usize = 0;
    var only_positionals = false;
    while (index < argv.len) : (index += 1) {
        const arg: []const u8 = argv[index];

        if (only_positionals) {
            try self.positionals.append(allocator, arg);
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            only_positionals = true;
            continue;
        }
        if (!std.mem.startsWith(u8, arg, "-") or arg.len == 1 or isNegativeNumber(arg)) {
            try self.positionals.append(allocator, arg);
            continue;
        }

        const stripped = std.mem.trimStart(u8, arg, "-");
        if (std.mem.findScalar(u8, stripped, '=')) |split| {
            try self.options.append(allocator, .{
                .name = stripped[0..split],
                .value = stripped[split + 1 ..],
            });
            continue;
        }
        if (takesValue(stripped)) {
            index += 1;
            if (index >= argv.len) return Error.MissingOptionValue;
            try self.options.append(allocator, .{ .name = stripped, .value = argv[index] });
            continue;
        }
        try self.options.append(allocator, .{ .name = stripped, .value = null });
    }
    return self;
}

pub fn deinit(self: *Args) void {
    self.positionals.deinit(self.allocator);
    self.options.deinit(self.allocator);
    self.* = undefined;
}

pub fn get(self: Args, name: []const u8) ?[]const u8 {
    for (self.options.items) |option| {
        if (std.mem.eql(u8, option.name, name)) return option.value;
    }
    return null;
}

pub fn getAny(self: Args, names: []const []const u8) ?[]const u8 {
    for (names) |name| {
        if (self.get(name)) |value| return value;
    }
    return null;
}

pub fn has(self: Args, name: []const u8) bool {
    for (self.options.items) |option| {
        if (std.mem.eql(u8, option.name, name)) return true;
    }
    return false;
}

pub fn hasAny(self: Args, names: []const []const u8) bool {
    for (names) |name| {
        if (self.has(name)) return true;
    }
    return false;
}

pub fn positional(self: Args, index: usize) ?[]const u8 {
    if (index >= self.positionals.items.len) return null;
    return self.positionals.items[index];
}

pub fn count(self: Args) usize {
    return self.positionals.items.len;
}

fn isNegativeNumber(arg: []const u8) bool {
    return switch (arg[1]) {
        '0'...'9', '.' => true,
        else => false,
    };
}

fn takesValue(name: []const u8) bool {
    for (value_options) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

test "separates positionals from options" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{ "storage", "list", "--address", "10.0.0.119", "/ext", "--json" };
    var parsed = try parse(allocator, &argv);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.count());
    try std.testing.expectEqualStrings("storage", parsed.positional(0).?);
    try std.testing.expectEqualStrings("list", parsed.positional(1).?);
    try std.testing.expectEqualStrings("/ext", parsed.positional(2).?);
    try std.testing.expectEqualStrings("10.0.0.119", parsed.get("address").?);
    try std.testing.expect(parsed.has("json"));
    try std.testing.expect(!parsed.has("yes"));
}

test "equals form and short names" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{ "-a=10.0.0.119", "--token=abc", "-t", "xyz" };
    var parsed = try parse(allocator, &argv);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("10.0.0.119", parsed.get("a").?);
    try std.testing.expectEqualStrings("abc", parsed.get("token").?);
    try std.testing.expectEqualStrings("xyz", parsed.get("t").?);
    try std.testing.expectEqualStrings("10.0.0.119", parsed.getAny(&.{ "address", "a" }).?);
}

test "double dash stops option parsing" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{ "storage", "read", "--", "--not-an-option" };
    var parsed = try parse(allocator, &argv);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.count());
    try std.testing.expectEqualStrings("--not-an-option", parsed.positional(2).?);
    try std.testing.expect(!parsed.has("not-an-option"));
}

test "negative numbers stay positional" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{ "display", "text", "-" };
    var parsed = try parse(allocator, &argv);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.count());

    const numbers = [_][:0]const u8{ "volume", "-50", "-0.5", "-.5" };
    var counted = try parse(allocator, &numbers);
    defer counted.deinit();
    try std.testing.expectEqual(@as(usize, 4), counted.count());
    try std.testing.expectEqualStrings("-50", counted.positional(1).?);
    try std.testing.expectEqualStrings("-0.5", counted.positional(2).?);
    try std.testing.expectEqualStrings("-.5", counted.positional(3).?);
    try std.testing.expect(!counted.has("50"));
}

test "missing option value" {
    const allocator = std.testing.allocator;
    const argv = [_][:0]const u8{"--address"};
    try std.testing.expectError(Error.MissingOptionValue, parse(allocator, &argv));
}

test "bare flags never consume the next argument" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "version", "json", "yes", "bmp", "silent", "help", "enable", "disable", "insecure" }) |flag| {
        try std.testing.expect(!takesValue(flag));
    }
    const argv = [_][:0]const u8{ "screen", "front", "--bmp", "--output", "shot.bmp" };
    var parsed = try parse(allocator, &argv);
    defer parsed.deinit();
    try std.testing.expect(parsed.has("bmp"));
    try std.testing.expectEqualStrings("shot.bmp", parsed.get("output").?);
    try std.testing.expectEqual(@as(usize, 2), parsed.count());
}
