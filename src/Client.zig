const std = @import("std");

const Client = @This();

allocator: std.mem.Allocator,
io: std.Io,
http: std.http.Client,
base_url: []u8,
token: ?[]u8,
last_error: ?ApiError,

pub const Options = struct {
    address: []const u8,
    token: ?[]const u8 = null,
};

pub const ApiError = struct {
    status: u16,
    code: ?i64,
    message: []const u8,
};

pub const Error = error{
    BadRequest,
    Unauthorized,
    NotFound,
    Conflict,
    Gone,
    PayloadTooLarge,
    ServiceUnavailable,
    DeviceWriteFailed,
    UnexpectedStatus,
    MalformedResponse,
};

pub const Query = []const [2][]const u8;

pub const json_parse_options: std.json.ParseOptions = .{
    .ignore_unknown_fields = true,
    .allocate = .alloc_always,
};

pub const json_stringify_options: std.json.Stringify.Options = .{
    .emit_null_optional_fields = false,
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !Client {
    const base_url = try normalizeAddress(allocator, options.address);
    errdefer allocator.free(base_url);

    const token = if (options.token) |t| try allocator.dupe(u8, t) else null;
    errdefer if (token) |t| allocator.free(t);

    return .{
        .allocator = allocator,
        .io = io,
        .http = .{ .allocator = allocator, .io = io },
        .base_url = base_url,
        .token = token,
        .last_error = null,
    };
}

pub fn deinit(self: *Client) void {
    self.clearError();
    self.http.deinit();
    self.allocator.free(self.base_url);
    if (self.token) |t| self.allocator.free(t);
    self.* = undefined;
}

pub fn lastError(self: *const Client) ?ApiError {
    return self.last_error;
}

pub fn account(self: *Client) @import("api/account.zig").Api {
    return .{ .client = self };
}

pub fn assets(self: *Client) @import("api/assets.zig").Api {
    return .{ .client = self };
}

pub fn audio(self: *Client) @import("api/audio.zig").Api {
    return .{ .client = self };
}

pub fn ble(self: *Client) @import("api/ble.zig").Api {
    return .{ .client = self };
}

pub fn busy(self: *Client) @import("api/busy.zig").Api {
    return .{ .client = self };
}

pub fn display(self: *Client) @import("api/display.zig").Api {
    return .{ .client = self };
}

pub fn input(self: *Client) @import("api/input.zig").Api {
    return .{ .client = self };
}

pub fn settings(self: *Client) @import("api/settings.zig").Api {
    return .{ .client = self };
}

pub fn smartHome(self: *Client) @import("api/smart_home.zig").Api {
    return .{ .client = self };
}

pub fn storage(self: *Client) @import("api/storage.zig").Api {
    return .{ .client = self };
}

pub fn system(self: *Client) @import("api/system.zig").Api {
    return .{ .client = self };
}

pub fn time(self: *Client) @import("api/time.zig").Api {
    return .{ .client = self };
}

pub fn update(self: *Client) @import("api/update.zig").Api {
    return .{ .client = self };
}

pub fn wifi(self: *Client) @import("api/wifi.zig").Api {
    return .{ .client = self };
}

pub fn send(
    self: *Client,
    method: std.http.Method,
    path: []const u8,
    query: Query,
    payload: ?[]const u8,
    content_type: ?[]const u8,
) ![]u8 {
    const url = try self.buildUrl(path, query);
    defer self.allocator.free(url);

    var body: std.Io.Writer.Allocating = .init(self.allocator);
    errdefer body.deinit();

    var extra: [2]std.http.Header = undefined;
    var extra_len: usize = 0;
    if (self.token) |t| {
        extra[extra_len] = .{ .name = "X-API-Token", .value = t };
        extra_len += 1;
    }
    if (content_type) |ct| {
        extra[extra_len] = .{ .name = "Content-Type", .value = ct };
        extra_len += 1;
    }

    const effective_payload = payload orelse
        if (method.requestHasBody()) @as(?[]const u8, "") else null;

    const result = try self.http.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .payload = effective_payload,
        .extra_headers = extra[0..extra_len],
        .redirect_behavior = .not_allowed,
        .response_writer = &body.writer,
    });

    const status = @backingInt(result.status);
    if (status < 200 or status > 299) {
        return self.fail(status, body.written());
    }

    self.clearError();
    return body.toOwnedSlice();
}

pub fn expectOk(
    self: *Client,
    method: std.http.Method,
    path: []const u8,
    query: Query,
    payload: ?[]const u8,
    content_type: ?[]const u8,
) !void {
    const body = try self.send(method, path, query, payload, content_type);
    self.allocator.free(body);
}

pub fn fetchJson(
    self: *Client,
    comptime T: type,
    method: std.http.Method,
    path: []const u8,
    query: Query,
    payload: ?[]const u8,
) !std.json.Parsed(T) {
    const body = try self.send(method, path, query, payload, if (payload == null) null else "application/json");
    defer self.allocator.free(body);
    return std.json.parseFromSlice(T, self.allocator, body, json_parse_options) catch
        Error.MalformedResponse;
}

pub fn get(self: *Client, comptime T: type, path: []const u8, query: Query) !std.json.Parsed(T) {
    return self.fetchJson(T, .GET, path, query, null);
}

pub fn sendJson(
    self: *Client,
    method: std.http.Method,
    path: []const u8,
    query: Query,
    value: anytype,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(self.allocator, value, json_stringify_options);
    defer self.allocator.free(encoded);
    return self.expectOk(method, path, query, encoded, "application/json");
}

pub fn upload(self: *Client, path: []const u8, query: Query, bytes: []const u8) !void {
    return self.expectOk(.POST, path, query, bytes, "application/octet-stream");
}

fn buildUrl(self: *Client, path: []const u8, query: Query) ![]u8 {
    var url: std.Io.Writer.Allocating = .init(self.allocator);
    errdefer url.deinit();

    try url.writer.writeAll(self.base_url);
    try url.writer.writeAll(path);
    for (query, 0..) |pair, index| {
        try url.writer.writeByte(if (index == 0) '?' else '&');
        try std.Uri.Component.percentEncode(&url.writer, pair[0], isUnreserved);
        try url.writer.writeByte('=');
        try std.Uri.Component.percentEncode(&url.writer, pair[1], isUnreserved);
    }
    return url.toOwnedSlice();
}

fn fail(self: *Client, status: u16, body: []const u8) anyerror {
    self.clearError();
    self.last_error = self.parseError(status, body) catch null;
    return statusToError(status);
}

fn parseError(self: *Client, status: u16, body: []const u8) !ApiError {
    const Payload = struct {
        @"error": []const u8,
        code: ?i64 = null,
    };

    if (std.json.validate(self.allocator, body) catch false) {
        const parsed = std.json.parseFromSlice(Payload, self.allocator, body, json_parse_options) catch {
            return self.genericError(status);
        };
        defer parsed.deinit();
        return .{
            .status = status,
            .code = parsed.value.code,
            .message = try self.allocator.dupe(u8, parsed.value.@"error"),
        };
    }
    return self.genericError(status);
}

fn genericError(self: *Client, status: u16) !ApiError {
    const phrase = std.http.Status.phrase(@fromBackingInt(@intCast(status))) orelse "unknown status";
    return .{
        .status = status,
        .code = null,
        .message = try self.allocator.dupe(u8, phrase),
    };
}

fn clearError(self: *Client) void {
    if (self.last_error) |e| self.allocator.free(e.message);
    self.last_error = null;
}

fn statusToError(status: u16) Error {
    return switch (status) {
        400 => Error.BadRequest,
        401, 403 => Error.Unauthorized,
        404 => Error.NotFound,
        409 => Error.Conflict,
        410 => Error.Gone,
        413 => Error.PayloadTooLarge,
        503 => Error.ServiceUnavailable,
        508 => Error.DeviceWriteFailed,
        else => Error.UnexpectedStatus,
    };
}

fn isUnreserved(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

fn normalizeAddress(allocator: std.mem.Allocator, address: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, address, " \t\r\n");
    const without_slash = std.mem.trimEnd(u8, trimmed, "/");
    if (without_slash.len == 0) return error.InvalidAddress;

    if (std.mem.startsWith(u8, without_slash, "http://") or
        std.mem.startsWith(u8, without_slash, "https://"))
    {
        return allocator.dupe(u8, without_slash);
    }
    return allocator.print("http://{s}", .{without_slash});
}

fn testClient(base_url: []u8) Client {
    return .{
        .allocator = std.testing.allocator,
        .io = undefined,
        .http = undefined,
        .base_url = base_url,
        .token = null,
        .last_error = null,
    };
}

test normalizeAddress {
    const allocator = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "10.0.0.119", "http://10.0.0.119" },
        .{ "10.0.0.119/", "http://10.0.0.119" },
        .{ "  10.0.0.119  ", "http://10.0.0.119" },
        .{ "10.0.0.119:8080", "http://10.0.0.119:8080" },
        .{ "busybar.local", "http://busybar.local" },
        .{ "http://10.0.0.119", "http://10.0.0.119" },
        .{ "https://bar.example.com/", "https://bar.example.com" },
    };
    for (cases) |case| {
        const got = try normalizeAddress(allocator, case[0]);
        defer allocator.free(got);
        try std.testing.expectEqualStrings(case[1], got);
    }
    try std.testing.expectError(error.InvalidAddress, normalizeAddress(allocator, "///"));
}

test buildUrl {
    const base = try std.testing.allocator.dupe(u8, "http://10.0.0.119");
    defer std.testing.allocator.free(base);
    var client = testClient(base);

    const plain = try client.buildUrl("/api/version", &.{});
    defer std.testing.allocator.free(plain);
    try std.testing.expectEqualStrings("http://10.0.0.119/api/version", plain);

    const with_path = try client.buildUrl("/api/storage/list", &.{.{ "path", "/ext/a b" }});
    defer std.testing.allocator.free(with_path);
    try std.testing.expectEqualStrings("http://10.0.0.119/api/storage/list?path=%2Fext%2Fa%20b", with_path);

    const timestamp = try client.buildUrl("/api/time/timestamp", &.{.{ "timestamp", "2026-08-11T20:25:58+02:00" }});
    defer std.testing.allocator.free(timestamp);
    try std.testing.expectEqualStrings(
        "http://10.0.0.119/api/time/timestamp?timestamp=2026-08-11T20%3A25%3A58%2B02%3A00",
        timestamp,
    );

    const pair = try client.buildUrl("/api/audio/volume", &.{ .{ "volume", "50" }, .{ "silent", "1" } });
    defer std.testing.allocator.free(pair);
    try std.testing.expectEqualStrings("http://10.0.0.119/api/audio/volume?volume=50&silent=1", pair);
}

test statusToError {
    try std.testing.expectEqual(Error.BadRequest, statusToError(400));
    try std.testing.expectEqual(Error.Unauthorized, statusToError(401));
    try std.testing.expectEqual(Error.Unauthorized, statusToError(403));
    try std.testing.expectEqual(Error.Gone, statusToError(410));
    try std.testing.expectEqual(Error.DeviceWriteFailed, statusToError(508));
    try std.testing.expectEqual(Error.UnexpectedStatus, statusToError(418));
}

test "json error body" {
    var client = testClient(undefined);
    defer client.clearError();

    const parsed = try client.parseError(400, "{\"error\":\"Invalid profile slot name\"}");
    defer std.testing.allocator.free(parsed.message);
    try std.testing.expectEqual(@as(u16, 400), parsed.status);
    try std.testing.expectEqualStrings("Invalid profile slot name", parsed.message);
    try std.testing.expectEqual(@as(?i64, null), parsed.code);
}

test "error body with a code" {
    var client = testClient(undefined);
    const parsed = try client.parseError(400, "{\"error\":\"Invalid parameter\",\"code\":400}");
    defer std.testing.allocator.free(parsed.message);
    try std.testing.expectEqual(@as(?i64, 400), parsed.code);
}

test "html error page" {
    var client = testClient(undefined);
    const parsed = try client.parseError(404, "<!DOCTYPE html>\n<html><body><h1>404</h1></body></html>");
    defer std.testing.allocator.free(parsed.message);
    try std.testing.expectEqual(@as(u16, 404), parsed.status);
    try std.testing.expectEqualStrings("Not Found", parsed.message);
}

test "empty error body" {
    var client = testClient(undefined);
    const parsed = try client.parseError(503, "");
    defer std.testing.allocator.free(parsed.message);
    try std.testing.expectEqualStrings("Service Unavailable", parsed.message);
}
