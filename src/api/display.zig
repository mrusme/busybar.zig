const std = @import("std");
const Client = @import("../Client.zig");

pub const Align = enum {
    top_left,
    top_mid,
    top_right,
    mid_left,
    center,
    mid_right,
    bottom_left,
    bottom_mid,
    bottom_right,
};

pub const Surface = enum { front, back };

pub const Font = enum {
    tiny,
    small,
    normal,
    condensed,
    bold,
    large,
    extra_large,
    global,
};

pub const Direction = enum { time_left, time_since };

pub const ShowHours = enum { when_non_zero, always };

pub const Fill = enum { none, solid, gradient_h, gradient_v };

pub const Text = struct {
    id: []const u8,
    type: enum { text } = .text,
    timeout: ?u32 = null,
    display_until: ?[]const u8 = null,
    x: ?i16 = null,
    y: ?i16 = null,
    display: ?Surface = null,
    @"align": ?Align = null,
    text: []const u8,
    font: Font,
    color: ?[]const u8 = null,
    width: ?u32 = null,
    scroll_rate: ?u32 = null,
    scroll_start_delay: ?u32 = null,
    scroll_repeat_delay: ?u32 = null,
};

pub const Image = struct {
    id: []const u8,
    type: enum { image } = .image,
    timeout: ?u32 = null,
    display_until: ?[]const u8 = null,
    x: ?i16 = null,
    y: ?i16 = null,
    display: ?Surface = null,
    @"align": ?Align = null,
    path: ?[]const u8 = null,
    stock_path: ?[]const u8 = null,
    opacity: ?u8 = null,
};

pub const Animation = struct {
    id: []const u8,
    type: enum { animation } = .animation,
    timeout: ?u32 = null,
    display_until: ?[]const u8 = null,
    x: ?i16 = null,
    y: ?i16 = null,
    display: ?Surface = null,
    @"align": ?Align = null,
    path: ?[]const u8 = null,
    stock_path: ?[]const u8 = null,
    loop: ?bool = null,
    await_previous_end: ?bool = null,
    section: ?[]const u8 = null,
    opacity: ?u8 = null,
};

pub const Countdown = struct {
    id: []const u8,
    type: enum { countdown } = .countdown,
    timeout: ?u32 = null,
    display_until: ?[]const u8 = null,
    x: ?i16 = null,
    y: ?i16 = null,
    display: ?Surface = null,
    @"align": ?Align = null,
    timestamp: []const u8,
    color: ?[]const u8 = null,
    direction: Direction,
    show_hours: ShowHours,
};

pub const Rectangle = struct {
    id: []const u8,
    type: enum { rectangle } = .rectangle,
    timeout: ?u32 = null,
    display_until: ?[]const u8 = null,
    x: ?i16 = null,
    y: ?i16 = null,
    display: ?Surface = null,
    @"align": ?Align = null,
    width: u32,
    height: u32,
    radius: ?u32 = null,
    fill: ?Fill = null,
    fill_colors: ?[]const []const u8 = null,
    border_width: ?u32 = null,
    border_color: ?[]const u8 = null,
};

pub const Element = union(enum) {
    text: Text,
    image: Image,
    animation: Animation,
    countdown: Countdown,
    rectangle: Rectangle,

    pub fn jsonStringify(self: Element, jw: anytype) !void {
        switch (self) {
            inline else => |payload| try jw.write(payload),
        }
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !Element {
        const value = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) !Element {
        const object = switch (source) {
            .object => |map| map,
            else => return error.UnexpectedToken,
        };
        const tag = object.get("type") orelse return error.MissingField;
        const name = switch (tag) {
            .string => |text| text,
            else => return error.UnexpectedToken,
        };
        inline for (@typeInfo(Element).@"union".fields) |field| {
            if (std.mem.eql(u8, name, field.name)) {
                return @unionInit(
                    Element,
                    field.name,
                    try std.json.parseFromValueLeaky(field.type, allocator, source, options),
                );
            }
        }
        return error.UnknownField;
    }
};

pub const Elements = struct {
    application_name: []const u8,
    priority: ?u8 = null,
    led_notification_color: ?[]const u8 = null,
    elements: []const Element,
};

pub const Api = struct {
    client: *Client,

    pub fn draw(self: Api, elements: Elements) !void {
        return self.client.sendJson(.POST, "/api/display/draw", &.{}, elements);
    }

    pub fn clear(self: Api, application_name: ?[]const u8) !void {
        if (application_name) |name| {
            return self.client.expectOk(.DELETE, "/api/display/draw", &.{
                .{ "application_name", name },
            }, null, null);
        }
        return self.client.expectOk(.DELETE, "/api/display/draw", &.{}, null, null);
    }

    pub fn screen(self: Api, surface: Surface) ![]u8 {
        const encoded = try self.client.send(.GET, "/api/screen", &.{
            .{ "display", if (surface == .front) "0" else "1" },
        }, null, null);
        defer self.client.allocator.free(encoded);

        const trimmed = std.mem.trim(u8, encoded, " \r\n\t");
        const decoder = std.base64.standard.Decoder;
        const size = decoder.calcSizeForSlice(trimmed) catch return Client.Error.MalformedResponse;
        const decoded = try self.client.allocator.alloc(u8, size);
        errdefer self.client.allocator.free(decoded);
        decoder.decode(decoded, trimmed) catch return Client.Error.MalformedResponse;
        return decoded;
    }
};

test "elements serialize flat" {
    const allocator = std.testing.allocator;
    const payload = Elements{
        .application_name = "my_app",
        .led_notification_color = "#FF0000FF",
        .elements = &.{
            .{ .text = .{ .id = "0", .text = "Hello", .font = .small, .x = 36, .@"align" = .center } },
            .{ .rectangle = .{ .id = "1", .width = 20, .height = 10, .fill = .solid } },
        },
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, payload, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(
        "{\"application_name\":\"my_app\",\"led_notification_color\":\"#FF0000FF\"," ++
            "\"elements\":[" ++
            "{\"id\":\"0\",\"type\":\"text\",\"x\":36,\"align\":\"center\",\"text\":\"Hello\",\"font\":\"small\"}," ++
            "{\"id\":\"1\",\"type\":\"rectangle\",\"width\":20,\"height\":10,\"fill\":\"solid\"}]}",
        encoded,
    );
}

test "countdown and animation required fields" {
    const allocator = std.testing.allocator;
    const payload = Elements{
        .application_name = "app",
        .elements = &.{
            .{ .countdown = .{
                .id = "c",
                .timestamp = "1786472525",
                .direction = .time_left,
                .show_hours = .always,
            } },
            .{ .animation = .{ .id = "a", .stock_path = "shared/spin.anim", .loop = true } },
        },
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, payload, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(
        "{\"application_name\":\"app\",\"elements\":[" ++
            "{\"id\":\"c\",\"type\":\"countdown\",\"timestamp\":\"1786472525\"," ++
            "\"direction\":\"time_left\",\"show_hours\":\"always\"}," ++
            "{\"id\":\"a\",\"type\":\"animation\",\"stock_path\":\"shared/spin.anim\",\"loop\":true}]}",
        encoded,
    );
}

test "elements parse back" {
    const allocator = std.testing.allocator;
    const body =
        \\{"application_name":"my_app","priority":50,"elements":[
        \\{"id":"0","type":"text","x":36,"align":"center","text":"Hello","font":"small"},
        \\{"id":"1","type":"rectangle","width":20,"height":10,"fill":"solid","fill_colors":["#FF0000FF"]},
        \\{"id":"2","type":"image","path":"data.png","opacity":80},
        \\{"id":"3","type":"countdown","timestamp":"1786472525","direction":"time_since","show_hours":"when_non_zero"},
        \\{"id":"4","type":"animation","stock_path":"shared/spin.anim","loop":false}]}
    ;
    const parsed = try std.json.parseFromSlice(Elements, allocator, body, Client.json_parse_options);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 5), parsed.value.elements.len);
    try std.testing.expect(parsed.value.elements[0] == .text);
    try std.testing.expectEqualStrings("Hello", parsed.value.elements[0].text.text);
    try std.testing.expectEqual(Align.center, parsed.value.elements[0].text.@"align".?);
    try std.testing.expect(parsed.value.elements[1] == .rectangle);
    try std.testing.expectEqual(@as(u32, 20), parsed.value.elements[1].rectangle.width);
    try std.testing.expectEqualStrings("#FF0000FF", parsed.value.elements[1].rectangle.fill_colors.?[0]);
    try std.testing.expect(parsed.value.elements[2] == .image);
    try std.testing.expectEqual(@as(u8, 80), parsed.value.elements[2].image.opacity.?);
    try std.testing.expect(parsed.value.elements[3] == .countdown);
    try std.testing.expectEqual(Direction.time_since, parsed.value.elements[3].countdown.direction);
    try std.testing.expect(parsed.value.elements[4] == .animation);
    try std.testing.expectEqual(false, parsed.value.elements[4].animation.loop.?);
}

test "an unknown element type is rejected" {
    const allocator = std.testing.allocator;
    const body = "{\"application_name\":\"a\",\"elements\":[{\"id\":\"x\",\"type\":\"hologram\"}]}";
    try std.testing.expectError(
        error.UnknownField,
        std.json.parseFromSlice(Elements, allocator, body, Client.json_parse_options),
    );
}

test "parse and serialize round-trip" {
    const allocator = std.testing.allocator;
    const body = "{\"application_name\":\"a\",\"elements\":[" ++
        "{\"id\":\"0\",\"type\":\"text\",\"text\":\"Hi\",\"font\":\"bold\"}]}";
    const parsed = try std.json.parseFromSlice(Elements, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(body, encoded);
}
