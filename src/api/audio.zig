const std = @import("std");
const Client = @import("../Client.zig");

pub const PlayRequest = struct {
    application_name: []const u8,
    path: ?[]const u8 = null,
    stock_path: ?[]const u8 = null,
};

pub const Api = struct {
    client: *Client,

    pub fn play(self: Api, request: PlayRequest) !void {
        return self.client.sendJson(.POST, "/api/audio/play", &.{}, request);
    }

    pub fn stop(self: Api) !void {
        return self.client.expectOk(.DELETE, "/api/audio/play", &.{}, null, null);
    }
};

test "play request omits the unused source" {
    const allocator = std.testing.allocator;
    const by_path = try std.json.Stringify.valueAlloc(
        allocator,
        PlayRequest{ .application_name = "my_app", .path = "data.snd" },
        Client.json_stringify_options,
    );
    defer allocator.free(by_path);
    try std.testing.expectEqualStrings(
        "{\"application_name\":\"my_app\",\"path\":\"data.snd\"}",
        by_path,
    );

    const by_stock = try std.json.Stringify.valueAlloc(
        allocator,
        PlayRequest{ .application_name = "my_app", .stock_path = "shared/beep.snd" },
        Client.json_stringify_options,
    );
    defer allocator.free(by_stock);
    try std.testing.expectEqualStrings(
        "{\"application_name\":\"my_app\",\"stock_path\":\"shared/beep.snd\"}",
        by_stock,
    );
}
