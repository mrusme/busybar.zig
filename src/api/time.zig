const std = @import("std");
const Client = @import("../Client.zig");

pub const TimestampInfo = struct {
    timestamp: []const u8,
};

pub const TimezoneInfo = struct {
    name: []const u8,
    offset: []const u8,
    abbr: []const u8,
};

pub const TimezoneList = struct {
    list: []const TimezoneInfo,
};

pub const Api = struct {
    client: *Client,

    pub fn now(self: Api) !std.json.Parsed(TimestampInfo) {
        return self.client.get(TimestampInfo, "/api/time", &.{});
    }

    pub fn setTimestamp(self: Api, timestamp: []const u8) !void {
        return self.client.expectOk(.POST, "/api/time/timestamp", &.{
            .{ "timestamp", timestamp },
        }, null, null);
    }

    pub fn timezone(self: Api) !std.json.Parsed(TimezoneInfo) {
        return self.client.get(TimezoneInfo, "/api/time/timezone", &.{});
    }

    pub fn setTimezone(self: Api, name: []const u8) !void {
        return self.client.expectOk(.POST, "/api/time/timezone", &.{.{ "timezone", name }}, null, null);
    }

    pub fn timezoneList(self: Api) !std.json.Parsed(TimezoneList) {
        return self.client.get(TimezoneList, "/api/time/tzlist", &.{});
    }
};

test "timezone payload" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        TimezoneInfo,
        allocator,
        "{\"name\":\"Madrid\",\"offset\":\"+02:00\",\"abbr\":\"CEST\"}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Madrid", parsed.value.name);
    try std.testing.expectEqualStrings("+02:00", parsed.value.offset);
}

test "timezone list" {
    const allocator = std.testing.allocator;
    const body =
        \\{"list":[{"name":"Midway","offset":"-11:00","abbr":"SST"},
        \\{"name":"Honolulu","offset":"-10:00","abbr":"HST"}]}
    ;
    const parsed = try std.json.parseFromSlice(TimezoneList, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.list.len);
    try std.testing.expectEqualStrings("Honolulu", parsed.value.list[1].name);
}
