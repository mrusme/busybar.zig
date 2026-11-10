const std = @import("std");
const Client = @import("../Client.zig");

pub const Slot = enum { busy, custom };

pub const BarSettings = struct {
    theme: []const u8,
    show_work_phase_only: bool,
    trigger_smart_home: bool,
};

pub const IntervalSettings = struct {
    type: []const u8 = "INTERVAL",
    interval_work_ms: i64,
    interval_rest_ms: i64,
    interval_work_cycles_count: i64,
    is_autostart_enabled: bool,
};

pub const InfiniteSettings = struct {
    type: []const u8 = "INFINITE",
};

pub const SimpleSettings = struct {
    type: []const u8 = "SIMPLE",
    total_time_ms: i64,
};

pub const TimerSettings = union(enum) {
    infinite: InfiniteSettings,
    simple: SimpleSettings,
    interval: IntervalSettings,

    pub fn jsonStringify(self: TimerSettings, jw: anytype) !void {
        switch (self) {
            inline else => |payload| try jw.write(payload),
        }
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !TimerSettings {
        const value = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) !TimerSettings {
        const tag = try discriminator(source);
        if (std.mem.eql(u8, tag, "INFINITE")) return .{
            .infinite = try std.json.parseFromValueLeaky(InfiniteSettings, allocator, source, options),
        };
        if (std.mem.eql(u8, tag, "SIMPLE")) return .{
            .simple = try std.json.parseFromValueLeaky(SimpleSettings, allocator, source, options),
        };
        if (std.mem.eql(u8, tag, "INTERVAL")) return .{
            .interval = try std.json.parseFromValueLeaky(IntervalSettings, allocator, source, options),
        };
        return error.UnknownField;
    }
};

pub const NotStarted = struct {
    type: []const u8 = "NOT_STARTED",
    busy_bar_settings: BarSettings,
};

pub const Infinite = struct {
    type: []const u8 = "INFINITE",
    card_id: []const u8,
    is_paused: bool,
    busy_bar_settings: BarSettings,
};

pub const Simple = struct {
    type: []const u8 = "SIMPLE",
    card_id: []const u8,
    time_left_ms: i64,
    is_paused: bool,
    busy_bar_settings: BarSettings,
};

pub const Interval = struct {
    type: []const u8 = "INTERVAL",
    card_id: []const u8,
    current_interval: i64,
    current_interval_time_total_ms: i64,
    current_interval_time_left_ms: i64,
    is_paused: bool,
    interval_settings: IntervalSettings,
    busy_bar_settings: BarSettings,
};

pub const State = union(enum) {
    not_started: NotStarted,
    infinite: Infinite,
    simple: Simple,
    interval: Interval,

    pub fn jsonStringify(self: State, jw: anytype) !void {
        switch (self) {
            inline else => |payload| try jw.write(payload),
        }
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !State {
        const value = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) !State {
        const tag = try discriminator(source);
        if (std.mem.eql(u8, tag, "NOT_STARTED")) return .{
            .not_started = try std.json.parseFromValueLeaky(NotStarted, allocator, source, options),
        };
        if (std.mem.eql(u8, tag, "INFINITE")) return .{
            .infinite = try std.json.parseFromValueLeaky(Infinite, allocator, source, options),
        };
        if (std.mem.eql(u8, tag, "SIMPLE")) return .{
            .simple = try std.json.parseFromValueLeaky(Simple, allocator, source, options),
        };
        if (std.mem.eql(u8, tag, "INTERVAL")) return .{
            .interval = try std.json.parseFromValueLeaky(Interval, allocator, source, options),
        };
        return error.UnknownField;
    }
};

pub const Snapshot = struct {
    snapshot: State,
    snapshot_timestamp_ms: i64,
};

pub const Profile = struct {
    sort_order: i64,
    title: []const u8,
    id: []const u8,
    timer_settings: TimerSettings,
    busy_bar_settings: BarSettings,
    profile_timestamp_ms: i64,
};

fn discriminator(source: std.json.Value) ![]const u8 {
    const object = switch (source) {
        .object => |map| map,
        else => return error.UnexpectedToken,
    };
    const tag = object.get("type") orelse return error.MissingField;
    return switch (tag) {
        .string => |name| name,
        else => error.UnexpectedToken,
    };
}

pub const Error = error{TimerNotRunning};

pub fn settingsOf(state: State) BarSettings {
    return switch (state) {
        inline else => |payload| payload.busy_bar_settings,
    };
}

pub fn isPaused(state: State) ?bool {
    return switch (state) {
        .not_started => null,
        inline else => |payload| payload.is_paused,
    };
}

pub fn stateFromProfile(profile: Profile) State {
    return switch (profile.timer_settings) {
        .infinite => .{ .infinite = .{
            .card_id = profile.id,
            .is_paused = false,
            .busy_bar_settings = profile.busy_bar_settings,
        } },
        .simple => |settings| .{ .simple = .{
            .card_id = profile.id,
            .time_left_ms = settings.total_time_ms,
            .is_paused = false,
            .busy_bar_settings = profile.busy_bar_settings,
        } },
        .interval => |settings| .{ .interval = .{
            .card_id = profile.id,
            .current_interval = 0,
            .current_interval_time_total_ms = settings.interval_work_ms,
            .current_interval_time_left_ms = settings.interval_work_ms,
            .is_paused = false,
            .interval_settings = settings,
            .busy_bar_settings = profile.busy_bar_settings,
        } },
    };
}

pub fn advanceTimestamp(now_ms: i64, stored_ms: i64) i64 {
    return if (now_ms > stored_ms) now_ms else stored_ms +| 1;
}

pub fn remainingMs(state: State, snapshot_timestamp_ms: i64, now_ms: i64) ?i64 {
    const stored = switch (state) {
        .not_started, .infinite => return null,
        .simple => |payload| payload.time_left_ms,
        .interval => |payload| payload.current_interval_time_left_ms,
    };
    if (isPaused(state) orelse false) return stored;

    const elapsed = now_ms -| snapshot_timestamp_ms;
    if (elapsed <= 0) return stored;
    return if (elapsed >= stored) 0 else stored - elapsed;
}

pub const Api = struct {
    client: *Client,

    pub fn snapshot(self: Api) !std.json.Parsed(Snapshot) {
        return self.client.get(Snapshot, "/api/busy/snapshot", &.{});
    }

    pub fn setSnapshot(self: Api, value: Snapshot) !void {
        return self.client.sendJson(.PUT, "/api/busy/snapshot", &.{}, value);
    }

    pub fn nextTimestamp(self: Api, stored_ms: i64) !i64 {
        return advanceTimestamp(try self.client.system().nowMs(), stored_ms);
    }

    pub fn start(self: Api, slot: Slot) !void {
        const current = try self.snapshot();
        defer current.deinit();
        const wanted = try self.profile(slot);
        defer wanted.deinit();

        const now = try self.nextTimestamp(current.value.snapshot_timestamp_ms);
        return self.setSnapshot(.{
            .snapshot = stateFromProfile(wanted.value),
            .snapshot_timestamp_ms = now,
        });
    }

    pub fn stop(self: Api) !void {
        const current = try self.snapshot();
        defer current.deinit();
        const now = try self.nextTimestamp(current.value.snapshot_timestamp_ms);
        return self.setSnapshot(.{
            .snapshot = .{ .not_started = .{
                .busy_bar_settings = settingsOf(current.value.snapshot),
            } },
            .snapshot_timestamp_ms = now,
        });
    }

    pub fn setPaused(self: Api, paused: bool) !void {
        const current = try self.snapshot();
        defer current.deinit();
        if (current.value.snapshot == .not_started) return Error.TimerNotRunning;

        const now = try self.nextTimestamp(current.value.snapshot_timestamp_ms);
        var value = current.value;
        const live = remainingMs(value.snapshot, value.snapshot_timestamp_ms, now);
        switch (value.snapshot) {
            .not_started => unreachable,
            .infinite => |*state| state.is_paused = paused,
            .simple => |*state| {
                state.is_paused = paused;
                state.time_left_ms = live.?;
            },
            .interval => |*state| {
                state.is_paused = paused;
                state.current_interval_time_left_ms = live.?;
            },
        }
        value.snapshot_timestamp_ms = now;
        return self.setSnapshot(value);
    }

    pub fn profile(self: Api, slot: Slot) !std.json.Parsed(Profile) {
        const path = if (slot == .busy) "/api/busy/profiles/busy" else "/api/busy/profiles/custom";
        return self.client.get(Profile, path, &.{});
    }

    pub fn setProfile(self: Api, slot: Slot, value: Profile) !void {
        const path = if (slot == .busy) "/api/busy/profiles/busy" else "/api/busy/profiles/custom";
        return self.client.sendJson(.PUT, path, &.{}, value);
    }
};

test "interval snapshot" {
    const allocator = std.testing.allocator;
    const body =
        \\{"snapshot":{"type":"INTERVAL","card_id":"00000000-0000-0000-0000-000000000000",
        \\"is_paused":false,"current_interval":0,"current_interval_time_total_ms":3600000,
        \\"current_interval_time_left_ms":3600000,"interval_settings":{"type":"INTERVAL",
        \\"interval_work_ms":3600000,"interval_rest_ms":300000,"interval_work_cycles_count":3,
        \\"is_autostart_enabled":false},"busy_bar_settings":{"theme":"on_call",
        \\"show_work_phase_only":false,"trigger_smart_home":true}},"snapshot_timestamp_ms":1786472525242}
    ;
    const parsed = try std.json.parseFromSlice(Snapshot, allocator, body, Client.json_parse_options);
    defer parsed.deinit();

    try std.testing.expect(parsed.value.snapshot == .interval);
    const interval = parsed.value.snapshot.interval;
    try std.testing.expectEqual(@as(i64, 3600000), interval.current_interval_time_left_ms);
    try std.testing.expectEqual(@as(i64, 300000), interval.interval_settings.interval_rest_ms);
    try std.testing.expectEqualStrings("on_call", interval.busy_bar_settings.theme);
    try std.testing.expectEqual(@as(i64, 1786472525242), parsed.value.snapshot_timestamp_ms);
}

test "not started and simple snapshots" {
    const allocator = std.testing.allocator;
    const settings = "{\"theme\":\"on_air\",\"show_work_phase_only\":false,\"trigger_smart_home\":true}";

    const not_started = "{\"snapshot\":{\"type\":\"NOT_STARTED\",\"busy_bar_settings\":" ++ settings ++
        "},\"snapshot_timestamp_ms\":1}";
    const a = try std.json.parseFromSlice(Snapshot, allocator, not_started, Client.json_parse_options);
    defer a.deinit();
    try std.testing.expect(a.value.snapshot == .not_started);

    const simple = "{\"snapshot\":{\"type\":\"SIMPLE\",\"card_id\":\"x\",\"time_left_ms\":9000," ++
        "\"is_paused\":true,\"busy_bar_settings\":" ++ settings ++ "},\"snapshot_timestamp_ms\":2}";
    const b = try std.json.parseFromSlice(Snapshot, allocator, simple, Client.json_parse_options);
    defer b.deinit();
    try std.testing.expect(b.value.snapshot == .simple);
    try std.testing.expectEqual(@as(i64, 9000), b.value.snapshot.simple.time_left_ms);
    try std.testing.expect(b.value.snapshot.simple.is_paused);
}

test "profile timer settings serialize flat" {
    const allocator = std.testing.allocator;
    const body =
        \\{"sort_order":0,"title":"ZEN","id":"00000000-0000-0000-0000-000000000002",
        \\"timer_settings":{"type":"INFINITE"},"busy_bar_settings":{"theme":"on_call",
        \\"show_work_phase_only":false,"trigger_smart_home":true},"profile_timestamp_ms":1786382141111}
    ;
    const parsed = try std.json.parseFromSlice(Profile, allocator, body, Client.json_parse_options);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.timer_settings == .infinite);
    try std.testing.expectEqualStrings("ZEN", parsed.value.title);

    const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.find(u8, encoded, "\"timer_settings\":{\"type\":\"INFINITE\"}") != null);
}

test "unknown discriminator is rejected" {
    const allocator = std.testing.allocator;
    const body = "{\"snapshot\":{\"type\":\"WHAT\"},\"snapshot_timestamp_ms\":1}";
    try std.testing.expectError(
        error.UnknownField,
        std.json.parseFromSlice(Snapshot, allocator, body, Client.json_parse_options),
    );
}

test "bar settings from every variant" {
    const settings: BarSettings = .{
        .theme = "on_air",
        .show_work_phase_only = false,
        .trigger_smart_home = true,
    };
    const states = [_]State{
        .{ .not_started = .{ .busy_bar_settings = settings } },
        .{ .infinite = .{ .card_id = "x", .is_paused = false, .busy_bar_settings = settings } },
        .{ .simple = .{
            .card_id = "x",
            .time_left_ms = 1,
            .is_paused = false,
            .busy_bar_settings = settings,
        } },
        .{ .interval = .{
            .card_id = "x",
            .current_interval = 0,
            .current_interval_time_total_ms = 1,
            .current_interval_time_left_ms = 1,
            .is_paused = true,
            .interval_settings = .{
                .interval_work_ms = 1,
                .interval_rest_ms = 1,
                .interval_work_cycles_count = 1,
                .is_autostart_enabled = false,
            },
            .busy_bar_settings = settings,
        } },
    };
    for (states) |state| {
        try std.testing.expectEqualStrings("on_air", settingsOf(state).theme);
    }
    try std.testing.expectEqual(@as(?bool, null), isPaused(states[0]));
    try std.testing.expectEqual(@as(?bool, false), isPaused(states[1]));
    try std.testing.expectEqual(@as(?bool, true), isPaused(states[3]));
}

test "stop keeps the bar settings" {
    const allocator = std.testing.allocator;
    const body =
        \\{"snapshot":{"type":"INTERVAL","card_id":"c","current_interval":2,
        \\"current_interval_time_total_ms":3600000,"current_interval_time_left_ms":1200000,
        \\"is_paused":false,"interval_settings":{"type":"INTERVAL","interval_work_ms":3600000,
        \\"interval_rest_ms":300000,"interval_work_cycles_count":3,"is_autostart_enabled":false},
        \\"busy_bar_settings":{"theme":"on_call","show_work_phase_only":false,
        \\"trigger_smart_home":true}},"snapshot_timestamp_ms":1786476592003}
    ;
    const parsed = try std.json.parseFromSlice(Snapshot, allocator, body, Client.json_parse_options);
    defer parsed.deinit();

    const stopped: Snapshot = .{
        .snapshot = .{ .not_started = .{
            .busy_bar_settings = settingsOf(parsed.value.snapshot),
        } },
        .snapshot_timestamp_ms = parsed.value.snapshot_timestamp_ms,
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, stopped, Client.json_stringify_options);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(
        "{\"snapshot\":{\"type\":\"NOT_STARTED\",\"busy_bar_settings\":{\"theme\":\"on_call\"," ++
            "\"show_work_phase_only\":false,\"trigger_smart_home\":true}}," ++
            "\"snapshot_timestamp_ms\":1786476592003}",
        encoded,
    );
}

test "pause leaves the rest of the snapshot alone" {
    const allocator = std.testing.allocator;
    const body =
        \\{"snapshot":{"type":"SIMPLE","card_id":"c","time_left_ms":9000,"is_paused":false,
        \\"busy_bar_settings":{"theme":"on_air","show_work_phase_only":false,
        \\"trigger_smart_home":true}},"snapshot_timestamp_ms":42}
    ;
    const parsed = try std.json.parseFromSlice(Snapshot, allocator, body, Client.json_parse_options);
    defer parsed.deinit();

    var value = parsed.value;
    switch (value.snapshot) {
        .not_started => unreachable,
        inline else => |*state| state.is_paused = true,
    }
    try std.testing.expectEqual(@as(?bool, true), isPaused(value.snapshot));
    try std.testing.expectEqual(@as(i64, 9000), value.snapshot.simple.time_left_ms);
    try std.testing.expectEqual(@as(i64, 42), value.snapshot_timestamp_ms);
    try std.testing.expectEqualStrings("c", value.snapshot.simple.card_id);
}

test "remaining time only counts down while running" {
    const settings: BarSettings = .{
        .theme = "on_air",
        .show_work_phase_only = false,
        .trigger_smart_home = true,
    };
    const running: State = .{ .simple = .{
        .card_id = "c",
        .time_left_ms = 60_000,
        .is_paused = false,
        .busy_bar_settings = settings,
    } };
    const paused: State = .{ .simple = .{
        .card_id = "c",
        .time_left_ms = 60_000,
        .is_paused = true,
        .busy_bar_settings = settings,
    } };

    try std.testing.expectEqual(@as(?i64, 60_000), remainingMs(running, 1000, 1000));
    try std.testing.expectEqual(@as(?i64, 45_000), remainingMs(running, 1000, 16_000));
    try std.testing.expectEqual(@as(?i64, 0), remainingMs(running, 1000, 999_000));
    try std.testing.expectEqual(@as(?i64, 60_000), remainingMs(paused, 1000, 999_000));
    try std.testing.expectEqual(@as(?i64, 60_000), remainingMs(running, 1000, 500));
    try std.testing.expectEqual(@as(?i64, 0), remainingMs(running, std.math.minInt(i64), std.math.maxInt(i64)));
    try std.testing.expectEqual(
        @as(?i64, 60_000),
        remainingMs(running, std.math.maxInt(i64), std.math.minInt(i64)),
    );

    const infinite: State = .{ .infinite = .{
        .card_id = "c",
        .is_paused = false,
        .busy_bar_settings = settings,
    } };
    try std.testing.expectEqual(@as(?i64, null), remainingMs(infinite, 0, 0));
    try std.testing.expectEqual(
        @as(?i64, null),
        remainingMs(.{ .not_started = .{ .busy_bar_settings = settings } }, 0, 0),
    );
}

test "interval counts down from its own field" {
    const settings: BarSettings = .{
        .theme = "on_call",
        .show_work_phase_only = false,
        .trigger_smart_home = true,
    };
    const state: State = .{ .interval = .{
        .card_id = "c",
        .current_interval = 2,
        .current_interval_time_total_ms = 3_600_000,
        .current_interval_time_left_ms = 2_767_000,
        .is_paused = false,
        .interval_settings = .{
            .interval_work_ms = 3_600_000,
            .interval_rest_ms = 300_000,
            .interval_work_cycles_count = 3,
            .is_autostart_enabled = false,
        },
        .busy_bar_settings = settings,
    } };
    try std.testing.expectEqual(
        @as(?i64, 2_545_130),
        remainingMs(state, 1_786_477_481_347, 1_786_477_703_217),
    );
}

test "start builds a state from the profile" {
    const settings: BarSettings = .{
        .theme = "on_call",
        .show_work_phase_only = false,
        .trigger_smart_home = true,
    };

    const interval = stateFromProfile(.{
        .sort_order = 0,
        .title = "BUSY",
        .id = "00000000-0000-0000-0000-000000000000",
        .timer_settings = .{ .interval = .{
            .interval_work_ms = 3_600_000,
            .interval_rest_ms = 300_000,
            .interval_work_cycles_count = 3,
            .is_autostart_enabled = false,
        } },
        .busy_bar_settings = settings,
        .profile_timestamp_ms = 1,
    });
    try std.testing.expect(interval == .interval);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", interval.interval.card_id);
    try std.testing.expectEqual(@as(i64, 0), interval.interval.current_interval);
    try std.testing.expectEqual(@as(i64, 3_600_000), interval.interval.current_interval_time_left_ms);
    try std.testing.expectEqual(@as(i64, 3_600_000), interval.interval.current_interval_time_total_ms);
    try std.testing.expectEqual(false, interval.interval.is_paused);

    const infinite = stateFromProfile(.{
        .sort_order = 0,
        .title = "ZEN",
        .id = "00000000-0000-0000-0000-000000000002",
        .timer_settings = .{ .infinite = .{} },
        .busy_bar_settings = settings,
        .profile_timestamp_ms = 1,
    });
    try std.testing.expect(infinite == .infinite);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000002", infinite.infinite.card_id);

    const simple = stateFromProfile(.{
        .sort_order = 0,
        .title = "FOCUS",
        .id = "id",
        .timer_settings = .{ .simple = .{ .total_time_ms = 300_000 } },
        .busy_bar_settings = settings,
        .profile_timestamp_ms = 1,
    });
    try std.testing.expect(simple == .simple);
    try std.testing.expectEqual(@as(i64, 300_000), simple.simple.time_left_ms);
}

test "start writes the wire form the device accepts" {
    const allocator = std.testing.allocator;
    const state = stateFromProfile(.{
        .sort_order = 0,
        .title = "BUSY",
        .id = "00000000-0000-0000-0000-000000000000",
        .timer_settings = .{ .interval = .{
            .interval_work_ms = 3_600_000,
            .interval_rest_ms = 300_000,
            .interval_work_cycles_count = 3,
            .is_autostart_enabled = false,
        } },
        .busy_bar_settings = .{
            .theme = "on_call",
            .show_work_phase_only = false,
            .trigger_smart_home = true,
        },
        .profile_timestamp_ms = 1,
    });
    const encoded = try std.json.Stringify.valueAlloc(
        allocator,
        Snapshot{ .snapshot = state, .snapshot_timestamp_ms = 1786478393000 },
        Client.json_stringify_options,
    );
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(
        "{\"snapshot\":{\"type\":\"INTERVAL\",\"card_id\":\"00000000-0000-0000-0000-000000000000\"," ++
            "\"current_interval\":0,\"current_interval_time_total_ms\":3600000," ++
            "\"current_interval_time_left_ms\":3600000,\"is_paused\":false," ++
            "\"interval_settings\":{\"type\":\"INTERVAL\",\"interval_work_ms\":3600000," ++
            "\"interval_rest_ms\":300000,\"interval_work_cycles_count\":3,\"is_autostart_enabled\":false}," ++
            "\"busy_bar_settings\":{\"theme\":\"on_call\",\"show_work_phase_only\":false," ++
            "\"trigger_smart_home\":true}},\"snapshot_timestamp_ms\":1786478393000}",
        encoded,
    );
}

test "a written timestamp is newer than the stored one" {
    try std.testing.expectEqual(@as(i64, 2000), advanceTimestamp(2000, 1000));
    try std.testing.expectEqual(@as(i64, 1001), advanceTimestamp(1000, 1000));
    try std.testing.expectEqual(@as(i64, 1501), advanceTimestamp(1000, 1500));
    try std.testing.expectEqual(
        @as(i64, 1786477481348),
        advanceTimestamp(1786477481000, 1786477481347),
    );
    try std.testing.expectEqual(
        @as(i64, std.math.maxInt(i64)),
        advanceTimestamp(0, std.math.maxInt(i64)),
    );
}
