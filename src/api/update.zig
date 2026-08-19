const std = @import("std");
const Client = @import("../Client.zig");

pub const InstallEvent = enum {
    session_start,
    session_stop,
    action_begin,
    action_done,
    detail_change,
    action_progress,
    none,
};

pub const InstallAction = enum {
    download,
    sha_verification,
    unpack,
    prepare,
    apply,
    none,
};

pub const InstallStatus = enum {
    ok,
    battery_low,
    busy,
    download_failure,
    download_abort,
    sha_mismatch,
    unpack_staging_dir_failure,
    unpack_archive_open_failure,
    unpack_archive_unpack_failure,
    install_manifest_not_found,
    install_manifest_invalid,
    install_session_config_failure,
    install_pointer_setup_failure,
    unknown_failure,
};

pub const CheckEvent = enum { start, stop, none };

pub const CheckStatus = enum { available, not_available, failure, none };

pub const Download = struct {
    speed_bytes_per_sec: ?i64 = null,
    received_bytes: ?i64 = null,
    total_bytes: ?i64 = null,
};

pub const Install = struct {
    is_allowed: ?bool = null,
    event: ?InstallEvent = null,
    action: ?InstallAction = null,
    status: ?InstallStatus = null,
    detail: ?[]const u8 = null,
    download: ?Download = null,
};

pub const Check = struct {
    available_version: ?[]const u8 = null,
    event: ?CheckEvent = null,
    status: ?CheckStatus = null,
};

pub const Status = struct {
    install: ?Install = null,
    check: ?Check = null,
};

pub const Changelog = struct {
    changelog: ?[]const u8 = null,
};

pub const AutoupdateSettings = struct {
    is_enabled: ?bool = null,
    interval_start: ?[]const u8 = null,
    interval_end: ?[]const u8 = null,
};

pub const Api = struct {
    client: *Client,

    pub fn status(self: Api) !std.json.Parsed(Status) {
        return self.client.get(Status, "/api/update/status", &.{});
    }

    pub fn check(self: Api) !void {
        return self.client.expectOk(.POST, "/api/update/check", &.{}, null, null);
    }

    pub fn changelog(self: Api, version: []const u8) !std.json.Parsed(Changelog) {
        return self.client.get(Changelog, "/api/update/changelog", &.{.{ "version", version }});
    }

    pub fn install(self: Api, version: []const u8) !void {
        return self.client.expectOk(.POST, "/api/update/install", &.{.{ "version", version }}, null, null);
    }

    pub fn abortDownload(self: Api) !void {
        return self.client.expectOk(.POST, "/api/update/abort_download", &.{}, null, null);
    }

    pub fn autoupdate(self: Api) !std.json.Parsed(AutoupdateSettings) {
        return self.client.get(AutoupdateSettings, "/api/update/autoupdate", &.{});
    }

    pub fn setAutoupdate(self: Api, settings: AutoupdateSettings) !void {
        return self.client.sendJson(.POST, "/api/update/autoupdate", &.{}, settings);
    }

    pub fn upload(self: Api, package: []const u8) !void {
        return self.client.upload("/api/update", &.{}, package);
    }
};

test "autoupdate omits absent fields" {
    const allocator = std.testing.allocator;
    const encoded = try std.json.Stringify.valueAlloc(
        allocator,
        AutoupdateSettings{ .is_enabled = true },
        Client.json_stringify_options,
    );
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"is_enabled\":true}", encoded);
}

test "status payload" {
    const allocator = std.testing.allocator;
    const body =
        \\{"install":{"is_allowed":true,"event":"none","action":"none","status":"ok","detail":"",
        \\"download":{"speed_bytes_per_sec":0,"received_bytes":0,"total_bytes":0}},
        \\"check":{"available_version":"","event":"stop","status":"not_available"}}
    ;
    const parsed = try std.json.parseFromSlice(Status, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(InstallStatus.ok, parsed.value.install.?.status.?);
    try std.testing.expectEqual(CheckStatus.not_available, parsed.value.check.?.status.?);
}
