const std = @import("std");
const Client = @import("../Client.zig");

pub const PairingStatus = enum {
    never_started,
    started,
    completed_successfully,
    failed,
};

pub const LatestPairingStatus = struct {
    value: PairingStatus,
    timestamp: ?i64 = null,
};

pub const PairingInfo = struct {
    fabric_count: ?i64 = null,
    latest_pairing_status: ?LatestPairingStatus = null,
};

pub const PairingPayload = struct {
    available_until: ?[]const u8 = null,
    qr_code: ?[]const u8 = null,
    manual_code: ?[]const u8 = null,
};

pub const StartupState = enum { off, on, toggle, last };

pub const SwitchState = struct {
    state: ?bool = null,
    startup: ?StartupState = null,
};

pub const Api = struct {
    client: *Client,

    pub fn pairing(self: Api) !std.json.Parsed(PairingInfo) {
        return self.client.get(PairingInfo, "/api/smart_home/pairing", &.{});
    }

    pub fn startPairing(self: Api) !std.json.Parsed(PairingPayload) {
        return self.client.fetchJson(PairingPayload, .POST, "/api/smart_home/pairing", &.{}, null);
    }

    pub fn erasePairings(self: Api) !void {
        return self.client.expectOk(.DELETE, "/api/smart_home/pairing", &.{}, null, null);
    }

    pub fn switchState(self: Api) !std.json.Parsed(SwitchState) {
        return self.client.get(SwitchState, "/api/smart_home/switch", &.{});
    }

    pub fn setSwitchState(self: Api, state: SwitchState) !void {
        return self.client.sendJson(.POST, "/api/smart_home/switch", &.{}, state);
    }
};

test "pairing info without a timestamp" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        PairingInfo,
        allocator,
        "{\"fabric_count\":0,\"latest_pairing_status\":{\"value\":\"never_started\"}}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(PairingStatus.never_started, parsed.value.latest_pairing_status.?.value);
    try std.testing.expectEqual(@as(?i64, null), parsed.value.latest_pairing_status.?.timestamp);
}

test "switch state without startup" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        SwitchState,
        allocator,
        "{\"state\":true}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(true, parsed.value.state.?);

    const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"state\":true}", encoded);
}
