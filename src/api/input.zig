const Client = @import("../Client.zig");

pub const Key = enum {
    up,
    down,
    ok,
    back,
    start,
    busy,
    custom,
    off,
    apps,
    settings,
};

pub const Api = struct {
    client: *Client,

    pub fn key(self: Api, which: Key) !void {
        return self.client.expectOk(.POST, "/api/input", &.{.{ "key", @tagName(which) }}, null, null);
    }
};
