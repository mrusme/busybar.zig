const std = @import("std");
const Client = @import("../Client.zig");

pub const Api = struct {
    client: *Client,

    pub fn upload(self: Api, application_name: []const u8, file: []const u8, bytes: []const u8) !void {
        return self.client.upload("/api/assets/upload", &.{
            .{ "application_name", application_name },
            .{ "file", file },
        }, bytes);
    }

    pub fn deleteAll(self: Api, application_name: []const u8) !void {
        return self.client.expectOk(.DELETE, "/api/assets/upload", &.{
            .{ "application_name", application_name },
        }, null, null);
    }
};
