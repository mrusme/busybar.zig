const std = @import("std");
const Client = @import("../Client.zig");

pub const AccessMode = enum { disabled, enabled, key };

pub const AccessInfo = struct {
    mode: AccessMode,
    key_valid: ?bool = null,
};

pub const NameInfo = struct {
    name: []const u8,
};

pub const BrightnessInfo = struct {
    value: []const u8,
};

pub const VolumeInfo = struct {
    volume: f64,
};

pub const Api = struct {
    client: *Client,

    pub fn access(self: Api) !std.json.Parsed(AccessInfo) {
        return self.client.get(AccessInfo, "/api/access", &.{});
    }

    pub fn setAccess(self: Api, mode: AccessMode, access_key: ?[]const u8) !void {
        if (access_key) |k| {
            return self.client.expectOk(.POST, "/api/access", &.{
                .{ "mode", @tagName(mode) },
                .{ "key", k },
            }, null, null);
        }
        return self.client.expectOk(.POST, "/api/access", &.{.{ "mode", @tagName(mode) }}, null, null);
    }

    pub fn name(self: Api) !std.json.Parsed(NameInfo) {
        return self.client.get(NameInfo, "/api/name", &.{});
    }

    pub fn setName(self: Api, value: []const u8) !void {
        return self.client.sendJson(.POST, "/api/name", &.{}, NameInfo{ .name = value });
    }

    pub fn brightness(self: Api) !std.json.Parsed(BrightnessInfo) {
        return self.client.get(BrightnessInfo, "/api/display/brightness", &.{});
    }

    pub fn setBrightness(self: Api, value: []const u8) !void {
        return self.client.expectOk(.POST, "/api/display/brightness", &.{.{ "value", value }}, null, null);
    }

    pub fn volume(self: Api) !std.json.Parsed(VolumeInfo) {
        return self.client.get(VolumeInfo, "/api/audio/volume", &.{});
    }

    pub fn setVolume(self: Api, value: f64, silent: bool) !void {
        var buffer: [32]u8 = undefined;
        const rendered = try std.mem.print(&buffer, "{d}", .{value});
        return self.client.expectOk(.POST, "/api/audio/volume", &.{
            .{ "volume", rendered },
            .{ "silent", if (silent) "1" else "0" },
        }, null, null);
    }
};

test "access info" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        AccessInfo,
        allocator,
        "{\"mode\":\"key\",\"key_valid\":true}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(AccessMode.key, parsed.value.mode);
    try std.testing.expectEqual(true, parsed.value.key_valid.?);
}

test "name payload" {
    const allocator = std.testing.allocator;
    const encoded = try std.json.Stringify.valueAlloc(
        allocator,
        NameInfo{ .name = "BUSY Bar" },
        Client.json_stringify_options,
    );
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"name\":\"BUSY Bar\"}", encoded);
}

test "brightness is auto or a number" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "{\"value\":\"auto\"}", "{\"value\":\"50\"}" }) |body| {
        const parsed = try std.json.parseFromSlice(BrightnessInfo, allocator, body, Client.json_parse_options);
        defer parsed.deinit();
        try std.testing.expect(parsed.value.value.len > 0);
    }
}
