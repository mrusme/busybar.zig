const std = @import("std");
const Client = @import("../Client.zig");

pub const Link = struct {
    code: ?[]const u8 = null,
    expires_at: ?i64 = null,
};

pub const Info = struct {
    linked: ?bool = null,
    id: ?[]const u8 = null,
    email: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
};

pub const ConnectionStatus = enum { @"error", disconnected, connected };

pub const Status = struct {
    status: ?ConnectionStatus = null,
};

pub const CertType = enum { default, custom, none };

pub const Backend = struct {
    server_url: []const u8,
    client_cert_type: CertType,
    ignore_server_cert: bool,
};

pub const Api = struct {
    client: *Client,

    pub fn info(self: Api) !std.json.Parsed(Info) {
        return self.client.get(Info, "/api/account/info", &.{});
    }

    pub fn status(self: Api) !std.json.Parsed(Status) {
        return self.client.get(Status, "/api/account/status", &.{});
    }

    pub fn link(self: Api) !std.json.Parsed(Link) {
        return self.client.fetchJson(Link, .POST, "/api/account/link", &.{}, null);
    }

    pub fn unlink(self: Api) !void {
        return self.client.expectOk(.DELETE, "/api/account", &.{}, null, null);
    }

    pub fn backend(self: Api) !std.json.Parsed(Backend) {
        return self.client.get(Backend, "/api/account/backend", &.{});
    }

    pub fn setBackend(self: Api, config: Backend) !void {
        return self.client.sendJson(.PUT, "/api/account/backend", &.{}, config);
    }
};

test "status name that is a zig keyword" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        Status,
        allocator,
        "{\"status\":\"error\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(ConnectionStatus.@"error", parsed.value.status.?);
}

test "backend payload round-trips" {
    const allocator = std.testing.allocator;
    const body = "{\"server_url\":\"default\",\"client_cert_type\":\"default\",\"ignore_server_cert\":false}";
    const parsed = try std.json.parseFromSlice(Backend, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(CertType.default, parsed.value.client_cert_type);

    const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(body, encoded);
}
