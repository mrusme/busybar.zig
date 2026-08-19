const std = @import("std");
const Client = @import("../Client.zig");

pub const SecurityMethod = enum {
    Open,
    WPA,
    WPA2,
    WEP,
    @"WPA/WPA2",
    WPA3,
    @"WPA2/WPA3",
    Unsupported,
};

pub const IpMethod = enum { dhcp, static };

pub const IpType = enum { ipv4, ipv6 };

pub const State = enum {
    unknown,
    disconnected,
    connected,
    connecting,
    disconnecting,
    reconnecting,
};

pub const IpConfig = struct {
    ip_method: ?IpMethod = null,
    ip_type: ?IpType = null,
    address: ?[]const u8 = null,
};

pub const Status = struct {
    state: State,
    ssid: ?[]const u8 = null,
    bssid: ?[]const u8 = null,
    channel: ?i64 = null,
    rssi: ?i64 = null,
    security: ?SecurityMethod = null,
    ip_config: ?IpConfig = null,
};

pub const Network = struct {
    ssid: ?[]const u8 = null,
    security: ?SecurityMethod = null,
    rssi: ?i64 = null,
};

pub const NetworkList = struct {
    count: ?i64 = null,
    networks: ?[]const Network = null,
};

pub const ConnectIpConfig = struct {
    ip_method: ?IpMethod = null,
    address: ?[]const u8 = null,
    mask: ?[]const u8 = null,
    gateway: ?[]const u8 = null,
};

pub const ConnectRequest = struct {
    ssid: ?[]const u8 = null,
    password: ?[]const u8 = null,
    security: ?SecurityMethod = null,
    ip_config: ?ConnectIpConfig = null,
};

pub const Api = struct {
    client: *Client,

    pub fn status(self: Api) !std.json.Parsed(Status) {
        return self.client.get(Status, "/api/wifi/status", &.{});
    }

    pub fn connect(self: Api, request: ConnectRequest) !void {
        return self.client.sendJson(.POST, "/api/wifi/connect", &.{}, request);
    }

    pub fn disconnect(self: Api) !void {
        return self.client.expectOk(.POST, "/api/wifi/disconnect", &.{}, null, null);
    }

    pub fn networks(self: Api) !std.json.Parsed(NetworkList) {
        return self.client.get(NetworkList, "/api/wifi/networks", &.{});
    }
};

test "connected status" {
    const allocator = std.testing.allocator;
    const body =
        \\{"state":"connected","ssid":"W32/STUXNET.EXE","security":"WPA3","bssid":"2A:F9:C2:FD:42:45",
        \\"channel":1,"rssi":-52,"ip_config":{"ip_method":"dhcp","ip_type":"ipv4","address":"10.0.0.119"}}
    ;
    const parsed = try std.json.parseFromSlice(Status, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(State.connected, parsed.value.state);
    try std.testing.expectEqual(SecurityMethod.WPA3, parsed.value.security.?);
    try std.testing.expectEqual(IpMethod.dhcp, parsed.value.ip_config.?.ip_method.?);
    try std.testing.expectEqualStrings("10.0.0.119", parsed.value.ip_config.?.address.?);
}

test "disconnected status" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        Status,
        allocator,
        "{\"state\":\"disconnected\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(State.disconnected, parsed.value.state);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.value.ssid);
}

test "security names with a slash" {
    const allocator = std.testing.allocator;
    for ([_][2][]const u8{
        .{ "\"WPA/WPA2\"", "WPA/WPA2" },
        .{ "\"WPA2/WPA3\"", "WPA2/WPA3" },
        .{ "\"Open\"", "Open" },
        .{ "\"Unsupported\"", "Unsupported" },
    }) |case| {
        const parsed = try std.json.parseFromSlice(SecurityMethod, allocator, case[0], .{});
        defer parsed.deinit();
        try std.testing.expectEqualStrings(case[1], @tagName(parsed.value));
    }
}
