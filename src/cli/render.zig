const std = @import("std");

pub const Mode = enum { human, json };

pub const Writer = struct {
    out: *std.Io.Writer,
    err: *std.Io.Writer,
    mode: Mode,
    allocator: std.mem.Allocator,

    pub fn value(self: Writer, payload: anytype) !void {
        const encoded = try std.json.Stringify.valueAlloc(self.allocator, payload, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        });
        defer self.allocator.free(encoded);
        try self.out.writeAll(encoded);
        try self.out.writeByte('\n');
    }

    pub fn field(self: Writer, name: []const u8, comptime format: []const u8, arguments: anytype) !void {
        if (self.mode == .json) return;
        try self.out.print("{s: <22}", .{name});
        try self.out.print(format, arguments);
        try self.out.writeByte('\n');
    }

    pub fn line(self: Writer, comptime format: []const u8, arguments: anytype) !void {
        if (self.mode == .json) return;
        try self.out.print(format, arguments);
        try self.out.writeByte('\n');
    }

    pub fn ok(self: Writer, comptime format: []const u8, arguments: anytype) !void {
        if (self.mode == .json) {
            try self.value(.{ .result = "OK" });
            return;
        }
        try self.out.print(format, arguments);
        try self.out.writeByte('\n');
    }

    pub fn bytes(self: Writer, payload: []const u8) !void {
        try self.out.writeAll(payload);
    }

    pub fn fail(self: Writer, comptime format: []const u8, arguments: anytype) !void {
        try self.err.print("busybar: ", .{});
        try self.err.print(format, arguments);
        try self.err.writeByte('\n');
    }
};

pub fn humanBytes(buffer: []u8, amount: u64) []const u8 {
    const units = [_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB" };
    var size: f64 = @floatFromInt(amount);
    var unit: usize = 0;
    while (size >= 1024 and unit + 1 < units.len) : (unit += 1) size /= 1024;
    if (unit == 0) return std.fmt.bufPrint(buffer, "{d} B", .{amount}) catch "?";
    return std.fmt.bufPrint(buffer, "{d:.1} {s}", .{ size, units[unit] }) catch "?";
}

pub fn duration(buffer: []u8, milliseconds: i64) []const u8 {
    if (milliseconds < 0) return std.fmt.bufPrint(buffer, "-", .{}) catch "?";
    const total = @divTrunc(milliseconds, 1000);
    const hours = @divTrunc(total, 3600);
    const minutes = @divTrunc(@mod(total, 3600), 60);
    const seconds = @mod(total, 60);
    if (hours > 0) return std.fmt.bufPrint(buffer, "{d}h {d}m {d}s", .{ hours, minutes, seconds }) catch "?";
    if (minutes > 0) return std.fmt.bufPrint(buffer, "{d}m {d}s", .{ minutes, seconds }) catch "?";
    return std.fmt.bufPrint(buffer, "{d}s", .{seconds}) catch "?";
}

test humanBytes {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("512 B", humanBytes(&buffer, 512));
    try std.testing.expectEqualStrings("1.0 KiB", humanBytes(&buffer, 1024));
    try std.testing.expectEqualStrings("72.5 MiB", humanBytes(&buffer, 76021760));
    try std.testing.expectEqualStrings("7.0 GiB", humanBytes(&buffer, 7541522432));
}

test duration {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("9s", duration(&buffer, 9000));
    try std.testing.expectEqualStrings("5m 0s", duration(&buffer, 300000));
    try std.testing.expectEqualStrings("1h 0m 0s", duration(&buffer, 3600000));
}
