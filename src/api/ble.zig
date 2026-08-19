const std = @import("std");
const Client = @import("../Client.zig");

pub const Status = enum {
    reset,
    initialization,
    disabled,
    enabled,
    connectable,
    connected,
    @"internal error",
};

pub const StatusResponse = struct {
    status: Status,
    address: ?[]const u8 = null,
};

pub const Api = struct {
    client: *Client,

    pub fn status(self: Api) !std.json.Parsed(StatusResponse) {
        return self.client.get(StatusResponse, "/api/ble/status", &.{});
    }

    pub fn enable(self: Api) !void {
        return self.client.expectOk(.POST, "/api/ble/enable", &.{}, null, null);
    }

    pub fn disable(self: Api) !void {
        return self.client.expectOk(.POST, "/api/ble/disable", &.{}, null, null);
    }

    pub fn removePairing(self: Api) !void {
        return self.client.expectOk(.DELETE, "/api/ble/pairing", &.{}, null, null);
    }
};

test "status name with a space" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        StatusResponse,
        allocator,
        "{\"status\":\"internal error\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(Status.@"internal error", parsed.value.status);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.value.address);
}

test "connected status has the peer address" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        StatusResponse,
        allocator,
        "{\"status\":\"connected\",\"address\":\"64:31:35:5D:FD:70\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings("64:31:35:5D:FD:70", parsed.value.address.?);
}
