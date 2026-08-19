const std = @import("std");
const Client = @import("../Client.zig");

pub const VersionInfo = struct {
    api_semver: []const u8,
};

pub const TransportType = enum { usb, wifi };

pub const NetworkInterfaceInfo = struct {
    type: TransportType,
};

pub const FirmwareSecurity = enum { secure, insecure, other, unknown };

pub const Device = struct {
    serial_number: []const u8,
    usb_mac: []const u8,
    wifi_mac: ?[]const u8 = null,
    ble_mac: ?[]const u8 = null,
    otp_valid: bool,
    otp_model: ?[]const u8 = null,
    otp_timestamp: ?i64 = null,
    firmware_security: FirmwareSecurity,
};

pub const Firmware = struct {
    version: []const u8,
    target: i64,
    branch: []const u8,
    build_date: []const u8,
    commit_hash: []const u8,
    intercom_version: []const u8,
    nwp_version: ?[]const u8 = null,
    matter_version: ?[]const u8 = null,
};

pub const System = struct {
    api_semver: []const u8,
    uptime: []const u8,
    boot_time: i64,
    auto_update_enabled: bool,
};

pub const PowerState = enum { discharging, charging, charged };

pub const Power = struct {
    state: PowerState,
    battery_charge: i64,
    battery_voltage: i64,
    battery_current: i64,
    usb_voltage: i64,
};

pub const Status = struct {
    device: ?Device = null,
    firmware: ?Firmware = null,
    system: ?System = null,
    power: ?Power = null,
};

pub const LogDump = struct {
    result: []const u8,
    path: []const u8,
};

pub const Error = error{ InvalidUptime, InvalidClock };

fn accumulate(total: i64, value: i64, seconds_per_unit: i64) Error!i64 {
    const scaled = std.math.mul(i64, value, seconds_per_unit) catch return Error.InvalidUptime;
    return std.math.add(i64, total, scaled) catch Error.InvalidUptime;
}

pub fn parseUptimeMs(text: []const u8) Error!i64 {
    var total: i64 = 0;
    var value: i64 = 0;
    var pending = false;
    for (text) |character| {
        switch (character) {
            '0'...'9' => {
                const shifted = std.math.mul(i64, value, 10) catch return Error.InvalidUptime;
                value = std.math.add(i64, shifted, character - '0') catch return Error.InvalidUptime;
                pending = true;
            },
            'd' => {
                total = try accumulate(total, value, 86_400);
                value = 0;
                pending = false;
            },
            'h' => {
                total = try accumulate(total, value, 3_600);
                value = 0;
                pending = false;
            },
            'm' => {
                total = try accumulate(total, value, 60);
                value = 0;
                pending = false;
            },
            's' => {
                total = try accumulate(total, value, 1);
                value = 0;
                pending = false;
            },
            ' ' => {},
            else => return Error.InvalidUptime,
        }
    }
    if (pending) return Error.InvalidUptime;
    return std.math.mul(i64, total, 1000) catch Error.InvalidUptime;
}

pub const Api = struct {
    client: *Client,

    pub fn nowMs(self: Api) !i64 {
        const parsed = try self.systemStatus();
        defer parsed.deinit();
        const uptime_ms = try parseUptimeMs(parsed.value.uptime);
        const boot_ms = std.math.mul(i64, parsed.value.boot_time, 1000) catch return Error.InvalidClock;
        return std.math.add(i64, boot_ms, uptime_ms) catch Error.InvalidClock;
    }

    pub fn version(self: Api) !std.json.Parsed(VersionInfo) {
        return self.client.get(VersionInfo, "/api/version", &.{});
    }

    pub fn transport(self: Api) !std.json.Parsed(NetworkInterfaceInfo) {
        return self.client.get(NetworkInterfaceInfo, "/api/transport", &.{});
    }

    pub fn status(self: Api) !std.json.Parsed(Status) {
        return self.client.get(Status, "/api/status", &.{});
    }

    pub fn device(self: Api) !std.json.Parsed(Device) {
        return self.client.get(Device, "/api/status/device", &.{});
    }

    pub fn firmware(self: Api) !std.json.Parsed(Firmware) {
        return self.client.get(Firmware, "/api/status/firmware", &.{});
    }

    pub fn systemStatus(self: Api) !std.json.Parsed(System) {
        return self.client.get(System, "/api/status/system", &.{});
    }

    pub fn power(self: Api) !std.json.Parsed(Power) {
        return self.client.get(Power, "/api/status/power", &.{});
    }

    pub fn logDump(self: Api, filename: ?[]const u8) !std.json.Parsed(LogDump) {
        if (filename) |name| {
            return self.client.fetchJson(LogDump, .POST, "/api/log_dump", &.{.{ "filename", name }}, null);
        }
        return self.client.fetchJson(LogDump, .POST, "/api/log_dump", &.{}, null);
    }
};

test "full status payload" {
    const allocator = std.testing.allocator;
    const body =
        \\{"device":{"serial_number":"20343055323250170025000c","usb_mac":"0c:fa:22:00:c4:54",
        \\"wifi_mac":"0c:fa:22:00:c4:55","ble_mac":"0c:fa:22:00:c4:56","otp_valid":true,
        \\"otp_model":"BB.1","otp_timestamp":1782449492,"firmware_security":"secure"},
        \\"firmware":{"version":"1.1.1","target":22,"branch":"1.1.1","build_date":"2026-07-29",
        \\"commit_hash":"ac59f45c","intercom_version":"ac59f45c","nwp_version":"1611.2.1.1.255.11.71",
        \\"matter_version":"1.0"},"system":{"api_semver":"25.0.0","uptime":"00d 00h 45m 59s",
        \\"boot_time":1786469814,"auto_update_enabled":true},"power":{"state":"charging",
        \\"battery_charge":46,"battery_voltage":3869,"battery_current":1505,"usb_voltage":9155}}
    ;
    const parsed = try std.json.parseFromSlice(Status, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(FirmwareSecurity.secure, parsed.value.device.?.firmware_security);
    try std.testing.expectEqualStrings("1.1.1", parsed.value.firmware.?.version);
    try std.testing.expectEqual(PowerState.charging, parsed.value.power.?.state);
    try std.testing.expectEqual(@as(i64, 46), parsed.value.power.?.battery_charge);
}

test "device without the optional fields" {
    const allocator = std.testing.allocator;
    const body =
        \\{"serial_number":"x","usb_mac":"y","otp_valid":false,"firmware_security":"unknown"}
    ;
    const parsed = try std.json.parseFromSlice(Device, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.value.wifi_mac);
    try std.testing.expectEqual(FirmwareSecurity.unknown, parsed.value.firmware_security);
}

test "log dump path" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        LogDump,
        allocator,
        "{\"result\":\"OK\",\"path\":\"/ext/log.txt\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/ext/log.txt", parsed.value.path);
}

test parseUptimeMs {
    try std.testing.expectEqual(@as(i64, 0), try parseUptimeMs("00d 00h 00m 00s"));
    try std.testing.expectEqual(@as(i64, 17_000), try parseUptimeMs("00d 00h 00m 17s"));
    try std.testing.expectEqual(@as(i64, 6_077_000), try parseUptimeMs("00d 01h 41m 17s"));
    try std.testing.expectEqual(@as(i64, 90_061_000), try parseUptimeMs("01d 01h 01m 01s"));
    try std.testing.expectEqual(@as(i64, 864_000_000), try parseUptimeMs("10d 00h 00m 00s"));
    try std.testing.expectError(Error.InvalidUptime, parseUptimeMs("00d 01h 41m 17"));
    try std.testing.expectError(Error.InvalidUptime, parseUptimeMs("garbage"));
    try std.testing.expectError(Error.InvalidUptime, parseUptimeMs("99999999999999999999d"));
    try std.testing.expectError(Error.InvalidUptime, parseUptimeMs("9223372036854775807s"));
}
