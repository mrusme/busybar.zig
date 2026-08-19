const std = @import("std");

pub const Format = enum { bgr888, gray4 };

pub const Geometry = struct {
    width: u32,
    height: u32,
    format: Format,
};

pub const Error = error{UnknownGeometry};

pub fn geometryFor(frame_len: usize) Error!Geometry {
    return switch (frame_len) {
        3456 => .{ .width = 72, .height = 16, .format = .bgr888 },
        6400 => .{ .width = 160, .height = 80, .format = .gray4 },
        else => Error.UnknownGeometry,
    };
}

pub fn encode(allocator: std.mem.Allocator, frame: []const u8) ![]u8 {
    const geometry = try geometryFor(frame.len);
    const row_bytes = geometry.width * 3;
    const padding = (4 - (row_bytes % 4)) % 4;
    const pixel_bytes = (row_bytes + padding) * geometry.height;
    const header_bytes = 54;

    var out = try allocator.alloc(u8, header_bytes + pixel_bytes);
    errdefer allocator.free(out);
    @memset(out, 0);

    out[0] = 'B';
    out[1] = 'M';
    std.mem.writeInt(u32, out[2..6], @intCast(out.len), .little);
    std.mem.writeInt(u32, out[10..14], header_bytes, .little);
    std.mem.writeInt(u32, out[14..18], 40, .little);
    std.mem.writeInt(i32, out[18..22], @intCast(geometry.width), .little);
    std.mem.writeInt(i32, out[22..26], @intCast(geometry.height), .little);
    std.mem.writeInt(u16, out[26..28], 1, .little);
    std.mem.writeInt(u16, out[28..30], 24, .little);
    std.mem.writeInt(u32, out[34..38], @intCast(pixel_bytes), .little);
    std.mem.writeInt(i32, out[38..42], 2835, .little);
    std.mem.writeInt(i32, out[42..46], 2835, .little);

    var y: u32 = 0;
    while (y < geometry.height) : (y += 1) {
        const source_row = geometry.height - 1 - y;
        var x: u32 = 0;
        while (x < geometry.width) : (x += 1) {
            const target = header_bytes + y * (row_bytes + padding) + x * 3;
            out[target..][0..3].* = pixelAt(geometry.format, frame, source_row * geometry.width + x);
        }
    }
    return out;
}

fn pixelAt(format: Format, frame: []const u8, index: u32) [3]u8 {
    return switch (format) {
        .bgr888 => frame[index * 3 ..][0..3].*,
        .gray4 => blk: {
            const packed_pair = frame[index / 2];
            const level = if (index % 2 == 0) packed_pair & 0x0f else packed_pair >> 4;
            break :blk @splat(level * 17);
        },
    };
}

test "front frame geometry" {
    const geometry = try geometryFor(3456);
    try std.testing.expectEqual(@as(u32, 72), geometry.width);
    try std.testing.expectEqual(@as(u32, 16), geometry.height);
    try std.testing.expectEqual(Format.bgr888, geometry.format);
}

test "back frame geometry" {
    const geometry = try geometryFor(6400);
    try std.testing.expectEqual(@as(u32, 160), geometry.width);
    try std.testing.expectEqual(@as(u32, 80), geometry.height);
    try std.testing.expectEqual(Format.gray4, geometry.format);
}

test "unknown frame size is rejected" {
    try std.testing.expectError(Error.UnknownGeometry, geometryFor(1234));
}

test "bitmap header" {
    const allocator = std.testing.allocator;
    const frame = try allocator.alloc(u8, 3456);
    defer allocator.free(frame);
    @memset(frame, 0);
    frame[0] = 0xAA;
    frame[1] = 0xBB;
    frame[2] = 0xCC;

    const encoded = try encode(allocator, frame);
    defer allocator.free(encoded);

    try std.testing.expectEqual(@as(u8, 'B'), encoded[0]);
    try std.testing.expectEqual(@as(u8, 'M'), encoded[1]);
    try std.testing.expectEqual(@as(u32, 54), std.mem.readInt(u32, encoded[10..14], .little));
    try std.testing.expectEqual(@as(i32, 72), std.mem.readInt(i32, encoded[18..22], .little));
    try std.testing.expectEqual(@as(i32, 16), std.mem.readInt(i32, encoded[22..26], .little));
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(u16, encoded[28..30], .little));
    try std.testing.expectEqual(@as(usize, 54 + 72 * 3 * 16), encoded.len);

    const last_row = 54 + 15 * 216;
    try std.testing.expectEqual(@as(u8, 0xAA), encoded[last_row + 0]);
    try std.testing.expectEqual(@as(u8, 0xBB), encoded[last_row + 1]);
    try std.testing.expectEqual(@as(u8, 0xCC), encoded[last_row + 2]);
}

test "front frame is already bgr" {
    const allocator = std.testing.allocator;
    const frame = try allocator.alloc(u8, 3456);
    defer allocator.free(frame);
    @memset(frame, 0);
    frame[0] = 0x00;
    frame[1] = 0x80;
    frame[2] = 0xFF;

    const encoded = try encode(allocator, frame);
    defer allocator.free(encoded);

    const last_row = 54 + 15 * 216;
    try std.testing.expectEqual(@as(u8, 0x00), encoded[last_row + 0]);
    try std.testing.expectEqual(@as(u8, 0x80), encoded[last_row + 1]);
    try std.testing.expectEqual(@as(u8, 0xFF), encoded[last_row + 2]);
}

test "back frame is two pixels per byte" {
    const allocator = std.testing.allocator;
    const frame = try allocator.alloc(u8, 6400);
    defer allocator.free(frame);
    @memset(frame, 0);
    frame[0] = 0x8F;
    frame[1] = 0x01;

    const encoded = try encode(allocator, frame);
    defer allocator.free(encoded);
    try std.testing.expectEqual(@as(usize, 54 + 160 * 3 * 80), encoded.len);
    try std.testing.expectEqual(@as(i32, 160), std.mem.readInt(i32, encoded[18..22], .little));
    try std.testing.expectEqual(@as(i32, 80), std.mem.readInt(i32, encoded[22..26], .little));

    const last_row = 54 + 79 * 480;
    try std.testing.expectEqual([3]u8{ 255, 255, 255 }, encoded[last_row..][0..3].*);
    try std.testing.expectEqual([3]u8{ 136, 136, 136 }, encoded[last_row + 3 ..][0..3].*);
    try std.testing.expectEqual([3]u8{ 17, 17, 17 }, encoded[last_row + 6 ..][0..3].*);
    try std.testing.expectEqual([3]u8{ 0, 0, 0 }, encoded[last_row + 9 ..][0..3].*);
}
