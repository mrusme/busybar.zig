const std = @import("std");
const Client = @import("../Client.zig");

pub const EntryType = enum { file, dir };

pub const Entry = struct {
    type: EntryType,
    name: []const u8,
    size: ?u64 = null,
};

pub const List = struct {
    list: []const Entry,
};

pub const Status = struct {
    used_bytes: ?u64 = null,
    free_bytes: ?u64 = null,
    total_bytes: ?u64 = null,
};

pub const Api = struct {
    client: *Client,

    pub fn list(self: Api, path: []const u8) !std.json.Parsed(List) {
        return self.client.get(List, "/api/storage/list", &.{.{ "path", path }});
    }

    pub fn read(self: Api, path: []const u8) ![]u8 {
        return self.client.send(.GET, "/api/storage/read", &.{.{ "path", path }}, null, null);
    }

    pub fn write(self: Api, path: []const u8, bytes: []const u8) !void {
        return self.client.upload("/api/storage/write", &.{.{ "path", path }}, bytes);
    }

    pub fn remove(self: Api, path: []const u8) !void {
        return self.client.expectOk(.DELETE, "/api/storage/remove", &.{.{ "path", path }}, null, null);
    }

    pub fn mkdir(self: Api, path: []const u8) !void {
        return self.client.expectOk(.POST, "/api/storage/mkdir", &.{.{ "path", path }}, null, null);
    }

    pub fn rename(self: Api, path: []const u8, new_path: []const u8) !void {
        return self.client.expectOk(.POST, "/api/storage/rename", &.{
            .{ "path", path },
            .{ "new_path", new_path },
        }, null, null);
    }

    pub fn status(self: Api) !std.json.Parsed(Status) {
        return self.client.get(Status, "/api/storage/status", &.{});
    }
};

test "only files have a size" {
    const allocator = std.testing.allocator;
    const body =
        \\{"list":[{"type":"file","name":".sys_update.txt","size":31},
        \\{"type":"dir","name":"apps_data"},{"type":"file","name":"Manifest","size":36939}]}
    ;
    const parsed = try std.json.parseFromSlice(List, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.value.list.len);
    try std.testing.expectEqual(EntryType.file, parsed.value.list[0].type);
    try std.testing.expectEqual(@as(?u64, 31), parsed.value.list[0].size);
    try std.testing.expectEqual(EntryType.dir, parsed.value.list[1].type);
    try std.testing.expectEqual(@as(?u64, null), parsed.value.list[1].size);
    try std.testing.expectEqual(@as(?u64, 36939), parsed.value.list[2].size);
}

test "byte counts" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        Status,
        allocator,
        "{\"used_bytes\":76021760,\"free_bytes\":7465500672,\"total_bytes\":7541522432}",
        Client.json_parse_options,
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u64, 7541522432), parsed.value.total_bytes);
}
