const std = @import("std");
const busybar = @import("busybar");
const Args = @import("Args.zig");
const bmp = @import("bmp.zig");
const render = @import("render.zig");
const usage = @import("usage.zig");

pub const Error = error{
    UnknownCommand,
    MissingArgument,
    InvalidArgument,
    NotConfirmed,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *busybar.Client,
    args: Args,
    out: render.Writer,

    fn require(self: Context, index: usize, label: []const u8) ![]const u8 {
        return self.args.positional(index) orelse {
            try self.out.fail("missing argument <{s}>", .{label});
            return Error.MissingArgument;
        };
    }

    fn requireOption(self: Context, names: []const []const u8, label: []const u8) ![]const u8 {
        return self.args.getAny(names) orelse {
            try self.out.fail("missing option --{s}", .{label});
            return Error.MissingArgument;
        };
    }

    fn confirm(self: Context, what: []const u8) !void {
        if (self.args.has("yes")) return;
        try self.out.fail("{s} needs --yes", .{what});
        return Error.NotConfirmed;
    }

    fn readInput(self: Context, path: []const u8) ![]u8 {
        if (std.mem.eql(u8, path, "-")) {
            var buffer: [4096]u8 = undefined;
            var reader = std.Io.File.stdin().readerStreaming(self.io, &buffer);
            return reader.interface.allocRemaining(self.allocator, .unlimited);
        }
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .unlimited);
    }

    fn emit(self: Context, payload: []const u8, target: ?[]const u8) !void {
        const destination = target orelse {
            try self.out.bytes(payload);
            return;
        };
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = destination, .data = payload });
        try self.out.line("wrote {d} bytes to {s}", .{ payload.len, destination });
    }
};

pub fn dispatch(ctx: Context) !void {
    const group = ctx.args.positional(0) orelse return usage.print(ctx.out);
    const command = ctx.args.positional(1);

    if (eq(group, "version")) return version(ctx);
    if (eq(group, "status")) return status(ctx, command);
    if (eq(group, "transport")) return transport(ctx);
    if (eq(group, "log-dump")) return logDump(ctx);
    if (eq(group, "name")) return name(ctx, command);
    if (eq(group, "access")) return access(ctx, command);
    if (eq(group, "brightness")) return brightness(ctx, command);
    if (eq(group, "volume")) return volume(ctx, command);
    if (eq(group, "input")) return input(ctx, command);
    if (eq(group, "screen")) return screen(ctx, command);
    if (eq(group, "display")) return display(ctx, command);
    if (eq(group, "audio")) return audio(ctx, command);
    if (eq(group, "assets")) return assets(ctx, command);
    if (eq(group, "storage")) return storage(ctx, command);
    if (eq(group, "busy")) return busy(ctx, command);
    if (eq(group, "ble")) return ble(ctx, command);
    if (eq(group, "wifi")) return wifi(ctx, command);
    if (eq(group, "time")) return timeNow(ctx, command);
    if (eq(group, "timezone")) return timezone(ctx, command);
    if (eq(group, "tzlist")) return tzlist(ctx);
    if (eq(group, "smarthome")) return smartHome(ctx, command);
    if (eq(group, "account")) return account(ctx, command);
    if (eq(group, "update")) return update(ctx, command);

    try ctx.out.fail("unknown command '{s}', try --help", .{group});
    return Error.UnknownCommand;
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn version(ctx: Context) !void {
    const parsed = try ctx.client.system().version();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("api", "{s}", .{parsed.value.api_semver});
}

fn status(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "all";

    if (eq(which, "device")) {
        const parsed = try ctx.client.system().device();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        return printDevice(ctx, parsed.value);
    }
    if (eq(which, "firmware")) {
        const parsed = try ctx.client.system().firmware();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        return printFirmware(ctx, parsed.value);
    }
    if (eq(which, "system")) {
        const parsed = try ctx.client.system().systemStatus();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        return printSystem(ctx, parsed.value);
    }
    if (eq(which, "power")) {
        const parsed = try ctx.client.system().power();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        return printPower(ctx, parsed.value);
    }
    if (!eq(which, "all")) {
        try ctx.out.fail("unknown status section '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.system().status();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    if (parsed.value.device) |value| try printDevice(ctx, value);
    if (parsed.value.firmware) |value| try printFirmware(ctx, value);
    if (parsed.value.system) |value| try printSystem(ctx, value);
    if (parsed.value.power) |value| try printPower(ctx, value);
}

fn printDevice(ctx: Context, value: busybar.system.Device) !void {
    try ctx.out.field("serial", "{s}", .{value.serial_number});
    try ctx.out.field("model", "{?s}", .{value.otp_model});
    try ctx.out.field("usb mac", "{s}", .{value.usb_mac});
    try ctx.out.field("wifi mac", "{?s}", .{value.wifi_mac});
    try ctx.out.field("ble mac", "{?s}", .{value.ble_mac});
    try ctx.out.field("otp valid", "{}", .{value.otp_valid});
    try ctx.out.field("firmware security", "{t}", .{value.firmware_security});
}

fn printFirmware(ctx: Context, value: busybar.system.Firmware) !void {
    try ctx.out.field("firmware", "{s}", .{value.version});
    try ctx.out.field("branch", "{s}", .{value.branch});
    try ctx.out.field("commit", "{s}", .{value.commit_hash});
    try ctx.out.field("built", "{s}", .{value.build_date});
    try ctx.out.field("target", "{d}", .{value.target});
    try ctx.out.field("radio", "{?s}", .{value.nwp_version});
    try ctx.out.field("matter", "{?s}", .{value.matter_version});
}

fn printSystem(ctx: Context, value: busybar.system.System) !void {
    try ctx.out.field("api", "{s}", .{value.api_semver});
    try ctx.out.field("uptime", "{s}", .{value.uptime});
    try ctx.out.field("boot time", "{d}", .{value.boot_time});
    try ctx.out.field("auto update", "{}", .{value.auto_update_enabled});
}

fn printPower(ctx: Context, value: busybar.system.Power) !void {
    try ctx.out.field("power", "{t}", .{value.state});
    try ctx.out.field("battery", "{d}%", .{value.battery_charge});
    try ctx.out.field("battery voltage", "{d} mV", .{value.battery_voltage});
    try ctx.out.field("battery current", "{d} mA", .{value.battery_current});
    try ctx.out.field("usb voltage", "{d} mV", .{value.usb_voltage});
}

fn transport(ctx: Context) !void {
    const parsed = try ctx.client.system().transport();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("transport", "{t}", .{parsed.value.type});
}

fn logDump(ctx: Context) !void {
    const parsed = try ctx.client.system().logDump(ctx.args.get("filename"));
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("written", "{s}", .{parsed.value.path});
}

fn name(ctx: Context, command: ?[]const u8) !void {
    if (command) |value| {
        try ctx.client.settings().setName(value);
        return ctx.out.ok("name set to {s}", .{value});
    }
    const parsed = try ctx.client.settings().name();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("name", "{s}", .{parsed.value.name});
}

fn access(ctx: Context, command: ?[]const u8) !void {
    if (command) |mode_name| {
        const mode = std.meta.stringToEnum(busybar.settings.AccessMode, mode_name) orelse {
            try ctx.out.fail("mode must be disabled, enabled or key", .{});
            return Error.InvalidArgument;
        };
        if (mode == .key and ctx.args.get("key") == null) {
            try ctx.out.fail("mode key needs --key with 4 to 10 digits", .{});
            return Error.MissingArgument;
        }
        try ctx.client.settings().setAccess(mode, ctx.args.get("key"));
        return ctx.out.ok("access set to {s}", .{mode_name});
    }
    const parsed = try ctx.client.settings().access();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("access mode", "{t}", .{parsed.value.mode});
    try ctx.out.field("key stored", "{?}", .{parsed.value.key_valid});
}

fn brightness(ctx: Context, command: ?[]const u8) !void {
    if (command) |value| {
        try ctx.client.settings().setBrightness(value);
        return ctx.out.ok("brightness set to {s}", .{value});
    }
    const parsed = try ctx.client.settings().brightness();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("brightness", "{s}", .{parsed.value.value});
}

fn volume(ctx: Context, command: ?[]const u8) !void {
    if (command) |value| {
        const parsed_value = parseVolume(value) orelse {
            try ctx.out.fail("volume must be a number from 0 to 100", .{});
            return Error.InvalidArgument;
        };
        try ctx.client.settings().setVolume(parsed_value, ctx.args.has("silent"));
        return ctx.out.ok("volume set to {d}", .{parsed_value});
    }
    const parsed = try ctx.client.settings().volume();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("volume", "{d}", .{parsed.value.volume});
}

fn parseVolume(text: []const u8) ?f64 {
    const value = std.fmt.parseFloat(f64, text) catch return null;
    if (!(value >= 0 and value <= 100)) return null;
    return value;
}

fn input(ctx: Context, command: ?[]const u8) !void {
    const key_name = command orelse {
        try ctx.out.fail("missing key name, try --help", .{});
        return Error.MissingArgument;
    };
    const key = std.meta.stringToEnum(busybar.input.Key, key_name) orelse {
        try ctx.out.fail("unknown key '{s}'", .{key_name});
        return Error.InvalidArgument;
    };
    try ctx.client.input().key(key);
    try ctx.out.ok("sent {s}", .{key_name});
}

fn screen(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "front";
    const surface = std.meta.stringToEnum(busybar.display.Surface, which) orelse {
        try ctx.out.fail("display must be front or back", .{});
        return Error.InvalidArgument;
    };

    const frame = try ctx.client.display().screen(surface);
    defer ctx.allocator.free(frame);

    if (!ctx.args.has("bmp")) return ctx.emit(frame, ctx.args.get("output"));

    const image = bmp.encode(ctx.allocator, frame) catch {
        try ctx.out.fail("cannot map a {d} byte frame to a known geometry", .{frame.len});
        return Error.InvalidArgument;
    };
    defer ctx.allocator.free(image);
    try ctx.emit(image, ctx.args.get("output"));
}

fn display(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse {
        try ctx.out.fail("display needs draw, text or clear", .{});
        return Error.MissingArgument;
    };

    if (eq(which, "clear")) {
        try ctx.client.display().clear(ctx.args.get("app"));
        return ctx.out.ok("cleared", .{});
    }
    if (eq(which, "draw")) {
        const source = try ctx.requireOption(&.{"file"}, "file");
        const body = try ctx.readInput(source);
        defer ctx.allocator.free(body);
        const parsed = std.json.parseFromSlice(
            busybar.display.Elements,
            ctx.allocator,
            body,
            busybar.Client.json_parse_options,
        ) catch {
            try ctx.out.fail("{s} is not a valid display payload", .{source});
            return Error.InvalidArgument;
        };
        defer parsed.deinit();
        try ctx.client.display().draw(parsed.value);
        return ctx.out.ok("drawn", .{});
    }
    if (!eq(which, "text")) {
        try ctx.out.fail("unknown display command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const content = try ctx.require(2, "text");
    const app = try ctx.requireOption(&.{"app"}, "app");

    var element: busybar.display.Text = .{
        .id = ctx.args.get("id") orelse "text",
        .text = content,
        .font = .normal,
    };
    if (ctx.args.get("font")) |value| {
        element.font = std.meta.stringToEnum(busybar.display.Font, value) orelse {
            try ctx.out.fail("unknown font '{s}'", .{value});
            return Error.InvalidArgument;
        };
    }
    if (ctx.args.get("display")) |value| {
        element.display = std.meta.stringToEnum(busybar.display.Surface, value) orelse {
            try ctx.out.fail("display must be front or back", .{});
            return Error.InvalidArgument;
        };
    }
    if (ctx.args.get("align")) |value| {
        element.@"align" = std.meta.stringToEnum(busybar.display.Align, value) orelse {
            try ctx.out.fail("unknown alignment '{s}'", .{value});
            return Error.InvalidArgument;
        };
    }
    element.x = try optionalInt(ctx, i16, "x");
    element.y = try optionalInt(ctx, i16, "y");
    element.width = try optionalInt(ctx, u32, "width");
    element.timeout = try optionalInt(ctx, u32, "timeout");
    element.color = ctx.args.get("color");

    const payload: busybar.display.Elements = .{
        .application_name = app,
        .priority = try optionalInt(ctx, u8, "priority"),
        .led_notification_color = ctx.args.get("led"),
        .elements = &.{.{ .text = element }},
    };
    try ctx.client.display().draw(payload);
    try ctx.out.ok("drawn", .{});
}

fn optionalInt(ctx: Context, comptime T: type, option: []const u8) !?T {
    const raw = ctx.args.get(option) orelse return null;
    return std.fmt.parseInt(T, raw, 10) catch {
        try ctx.out.fail("--{s} must be a whole number", .{option});
        return Error.InvalidArgument;
    };
}

fn audio(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse {
        try ctx.out.fail("audio needs play or stop", .{});
        return Error.MissingArgument;
    };
    if (eq(which, "stop")) {
        try ctx.client.audio().stop();
        return ctx.out.ok("stopped", .{});
    }
    if (!eq(which, "play")) {
        try ctx.out.fail("unknown audio command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const app = try ctx.requireOption(&.{"app"}, "app");
    const path = ctx.args.get("path");
    const stock = ctx.args.get("stock");
    if (path == null and stock == null) {
        try ctx.out.fail("audio play needs --path or --stock", .{});
        return Error.MissingArgument;
    }
    try ctx.client.audio().play(.{
        .application_name = app,
        .path = path,
        .stock_path = stock,
    });
    try ctx.out.ok("playing", .{});
}

fn assets(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse {
        try ctx.out.fail("assets needs upload or delete", .{});
        return Error.MissingArgument;
    };
    const app = try ctx.requireOption(&.{"app"}, "app");

    if (eq(which, "delete")) {
        try ctx.confirm("deleting every asset of an application");
        try ctx.client.assets().deleteAll(app);
        return ctx.out.ok("deleted assets of {s}", .{app});
    }
    if (!eq(which, "upload")) {
        try ctx.out.fail("unknown assets command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const source = try ctx.require(2, "local-file");
    const body = try ctx.readInput(source);
    defer ctx.allocator.free(body);
    const target = ctx.args.get("name") orelse std.Io.Dir.path.basename(source);
    try ctx.client.assets().upload(app, target, body);
    try ctx.out.ok("uploaded {d} bytes as {s}", .{ body.len, target });
}

fn storage(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse {
        try ctx.out.fail("storage needs list, read, write, remove, mkdir, rename or status", .{});
        return Error.MissingArgument;
    };

    if (eq(which, "status")) {
        const parsed = try ctx.client.storage().status();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        var buffer: [64]u8 = undefined;
        if (parsed.value.used_bytes) |used|
            try ctx.out.field("used", "{s}", .{render.humanBytes(&buffer, used)});
        if (parsed.value.free_bytes) |free|
            try ctx.out.field("free", "{s}", .{render.humanBytes(&buffer, free)});
        if (parsed.value.total_bytes) |total|
            try ctx.out.field("total", "{s}", .{render.humanBytes(&buffer, total)});
        return;
    }

    const path = try ctx.require(2, "path");

    if (eq(which, "list")) {
        const parsed = try ctx.client.storage().list(path);
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        var buffer: [64]u8 = undefined;
        for (parsed.value.list) |entry| {
            const size = if (entry.size) |value| render.humanBytes(&buffer, value) else "";
            try ctx.out.line("{s: <5} {s: >10}  {s}", .{ @tagName(entry.type), size, entry.name });
        }
        return;
    }
    if (eq(which, "read")) {
        const body = try ctx.client.storage().read(path);
        defer ctx.allocator.free(body);
        return ctx.emit(body, ctx.args.get("output"));
    }
    if (eq(which, "write")) {
        const source = try ctx.require(3, "local-file");
        const body = try ctx.readInput(source);
        defer ctx.allocator.free(body);
        try ctx.client.storage().write(path, body);
        return ctx.out.ok("wrote {d} bytes to {s}", .{ body.len, path });
    }
    if (eq(which, "remove")) {
        try ctx.confirm("removing a path");
        try ctx.client.storage().remove(path);
        return ctx.out.ok("removed {s}", .{path});
    }
    if (eq(which, "mkdir")) {
        try ctx.client.storage().mkdir(path);
        return ctx.out.ok("created {s}", .{path});
    }
    if (eq(which, "rename")) {
        const new_path = try ctx.require(3, "new-path");
        try ctx.client.storage().rename(path, new_path);
        return ctx.out.ok("renamed {s} to {s}", .{ path, new_path });
    }

    try ctx.out.fail("unknown storage command '{s}'", .{which});
    return Error.UnknownCommand;
}

fn busy(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse {
        try ctx.out.fail("busy needs start, stop, pause, resume, snapshot or profile", .{});
        return Error.MissingArgument;
    };

    if (eq(which, "start")) {
        const slot_name = ctx.args.positional(2) orelse "busy";
        const slot = std.meta.stringToEnum(busybar.busy.Slot, slot_name) orelse {
            try ctx.out.fail("slot must be busy or custom", .{});
            return Error.InvalidArgument;
        };
        try ctx.client.busy().start(slot);
        return ctx.out.ok("timer started from the {s} profile", .{slot_name});
    }
    if (eq(which, "stop")) {
        try ctx.client.busy().stop();
        return ctx.out.ok("timer stopped", .{});
    }
    if (eq(which, "pause") or eq(which, "resume")) {
        const paused = eq(which, "pause");
        ctx.client.busy().setPaused(paused) catch |err| switch (err) {
            busybar.busy.Error.TimerNotRunning => {
                try ctx.out.fail("no timer is running", .{});
                return Error.InvalidArgument;
            },
            else => return err,
        };
        return ctx.out.ok("timer {s}", .{if (paused) "paused" else "resumed"});
    }
    if (eq(which, "snapshot")) {
        if (ctx.args.get("file")) |source| {
            const body = try ctx.readInput(source);
            defer ctx.allocator.free(body);
            const parsed = std.json.parseFromSlice(
                busybar.busy.Snapshot,
                ctx.allocator,
                body,
                busybar.Client.json_parse_options,
            ) catch {
                try ctx.out.fail("{s} is not a valid snapshot", .{source});
                return Error.InvalidArgument;
            };
            defer parsed.deinit();
            try ctx.client.busy().setSnapshot(parsed.value);
            return ctx.out.ok("snapshot set", .{});
        }
        const parsed = try ctx.client.busy().snapshot();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        const now = ctx.client.system().nowMs() catch null;
        return printSnapshot(ctx, parsed.value, now);
    }
    if (!eq(which, "profile")) {
        try ctx.out.fail("unknown busy command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const slot_name = try ctx.require(2, "busy|custom");
    const slot = std.meta.stringToEnum(busybar.busy.Slot, slot_name) orelse {
        try ctx.out.fail("slot must be busy or custom", .{});
        return Error.InvalidArgument;
    };

    if (ctx.args.get("file")) |source| {
        const body = try ctx.readInput(source);
        defer ctx.allocator.free(body);
        const parsed = std.json.parseFromSlice(
            busybar.busy.Profile,
            ctx.allocator,
            body,
            busybar.Client.json_parse_options,
        ) catch {
            try ctx.out.fail("{s} is not a valid profile", .{source});
            return Error.InvalidArgument;
        };
        defer parsed.deinit();
        try ctx.client.busy().setProfile(slot, parsed.value);
        return ctx.out.ok("profile set", .{});
    }

    const parsed = try ctx.client.busy().profile(slot);
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("title", "{s}", .{parsed.value.title});
    try ctx.out.field("id", "{s}", .{parsed.value.id});
    try ctx.out.field("sort order", "{d}", .{parsed.value.sort_order});
    try ctx.out.field("theme", "{s}", .{parsed.value.busy_bar_settings.theme});
    var buffer: [64]u8 = undefined;
    switch (parsed.value.timer_settings) {
        .infinite => try ctx.out.field("timer", "infinite", .{}),
        .simple => |value| try ctx.out.field("timer", "simple, {s}", .{
            render.duration(&buffer, value.total_time_ms),
        }),
        .interval => |value| {
            try ctx.out.field("timer", "interval, {d} cycles", .{value.interval_work_cycles_count});
            try ctx.out.field("work", "{s}", .{render.duration(&buffer, value.interval_work_ms)});
            try ctx.out.field("rest", "{s}", .{render.duration(&buffer, value.interval_rest_ms)});
            try ctx.out.field("autostart", "{}", .{value.is_autostart_enabled});
        },
    }
}

fn printSnapshot(ctx: Context, value: busybar.busy.Snapshot, now_ms: ?i64) !void {
    var buffer: [64]u8 = undefined;
    switch (value.snapshot) {
        .not_started => return ctx.out.field("timer", "not started", .{}),
        .infinite => |state| {
            try ctx.out.field("timer", "infinite", .{});
            try ctx.out.field("paused", "{}", .{state.is_paused});
        },
        .simple => |state| {
            try ctx.out.field("timer", "simple", .{});
            try ctx.out.field("paused", "{}", .{state.is_paused});
        },
        .interval => |state| {
            try ctx.out.field("timer", "interval", .{});
            try ctx.out.field("interval", "{d} of {d}", .{
                state.current_interval +| 1,
                state.interval_settings.interval_work_cycles_count,
            });
            try ctx.out.field("paused", "{}", .{state.is_paused});
        },
    }

    const now = now_ms orelse value.snapshot_timestamp_ms;
    if (busybar.busy.remainingMs(value.snapshot, value.snapshot_timestamp_ms, now)) |left| {
        try ctx.out.field("time left", "{s}", .{render.duration(&buffer, left)});
    }
    if (now_ms == null) try ctx.out.field("as of", "{d}", .{value.snapshot_timestamp_ms});
}

fn ble(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "status";

    if (eq(which, "enable")) {
        try ctx.client.ble().enable();
        return ctx.out.ok("ble enabled", .{});
    }
    if (eq(which, "disable")) {
        try ctx.client.ble().disable();
        return ctx.out.ok("ble disabled", .{});
    }
    if (eq(which, "unpair")) {
        try ctx.confirm("removing the bluetooth pairing");
        try ctx.client.ble().removePairing();
        return ctx.out.ok("pairing removed", .{});
    }
    if (!eq(which, "status")) {
        try ctx.out.fail("unknown ble command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.ble().status();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("ble", "{t}", .{parsed.value.status});
    try ctx.out.field("peer", "{?s}", .{parsed.value.address});
}

fn wifi(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "status";

    if (eq(which, "disconnect")) {
        try ctx.confirm("disconnecting from wi-fi");
        try ctx.client.wifi().disconnect();
        return ctx.out.ok("disconnected", .{});
    }
    if (eq(which, "connect")) {
        const ssid = try ctx.requireOption(&.{"ssid"}, "ssid");
        var request: busybar.wifi.ConnectRequest = .{
            .ssid = ssid,
            .password = ctx.args.get("password"),
        };
        if (ctx.args.get("security")) |value| {
            request.security = std.meta.stringToEnum(busybar.wifi.SecurityMethod, value) orelse {
                try ctx.out.fail("unknown security method '{s}'", .{value});
                return Error.InvalidArgument;
            };
        }
        if (ctx.args.get("ip")) |value| {
            request.ip_config = .{
                .ip_method = .static,
                .address = value,
                .mask = ctx.args.get("mask"),
                .gateway = ctx.args.get("gateway"),
            };
        }
        try ctx.client.wifi().connect(request);
        return ctx.out.ok("connected to {s}", .{ssid});
    }
    if (eq(which, "networks")) {
        const parsed = try ctx.client.wifi().networks();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        const list = parsed.value.networks orelse return;
        for (list) |network| {
            try ctx.out.line("{d: >4} dBm  {t: <12} {?s}", .{
                network.rssi orelse 0,
                network.security orelse .Unsupported,
                network.ssid,
            });
        }
        return;
    }
    if (!eq(which, "status")) {
        try ctx.out.fail("unknown wifi command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.wifi().status();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("wifi", "{t}", .{parsed.value.state});
    try ctx.out.field("ssid", "{?s}", .{parsed.value.ssid});
    try ctx.out.field("bssid", "{?s}", .{parsed.value.bssid});
    if (parsed.value.security) |value| try ctx.out.field("security", "{t}", .{value});
    if (parsed.value.channel) |value| try ctx.out.field("channel", "{d}", .{value});
    if (parsed.value.rssi) |value| try ctx.out.field("signal", "{d} dBm", .{value});
    if (parsed.value.ip_config) |config| {
        try ctx.out.field("address", "{?s}", .{config.address});
        if (config.ip_method) |method| try ctx.out.field("ip method", "{t}", .{method});
    }
}

fn timeNow(ctx: Context, command: ?[]const u8) !void {
    if (command) |timestamp| {
        try ctx.client.time().setTimestamp(timestamp);
        return ctx.out.ok("clock set to {s}", .{timestamp});
    }
    const parsed = try ctx.client.time().now();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("time", "{s}", .{parsed.value.timestamp});
}

fn timezone(ctx: Context, command: ?[]const u8) !void {
    if (command) |zone| {
        try ctx.client.time().setTimezone(zone);
        return ctx.out.ok("timezone set to {s}", .{zone});
    }
    const parsed = try ctx.client.time().timezone();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("timezone", "{s}", .{parsed.value.name});
    try ctx.out.field("offset", "{s}", .{parsed.value.offset});
    try ctx.out.field("abbreviation", "{s}", .{parsed.value.abbr});
}

fn tzlist(ctx: Context) !void {
    const parsed = try ctx.client.time().timezoneList();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    for (parsed.value.list) |zone| {
        try ctx.out.line("{s: <8} {s: <6} {s}", .{ zone.offset, zone.abbr, zone.name });
    }
}

fn smartHome(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "pairing";

    if (eq(which, "pair")) {
        const parsed = try ctx.client.smartHome().startPairing();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.field("qr code", "{?s}", .{parsed.value.qr_code});
        try ctx.out.field("manual code", "{?s}", .{parsed.value.manual_code});
        try ctx.out.field("available until", "{?s}", .{parsed.value.available_until});
        return;
    }
    if (eq(which, "unpair")) {
        try ctx.confirm("erasing every smart home pairing");
        try ctx.client.smartHome().erasePairings();
        return ctx.out.ok("pairings erased, restart the device", .{});
    }
    if (eq(which, "switch")) {
        if (ctx.args.positional(2)) |state| {
            const on = eq(state, "on") or eq(state, "true") or eq(state, "1");
            const off = eq(state, "off") or eq(state, "false") or eq(state, "0");
            if (!on and !off) {
                try ctx.out.fail("switch state must be on or off", .{});
                return Error.InvalidArgument;
            }
            var payload: busybar.smart_home.SwitchState = .{ .state = on };
            if (ctx.args.get("startup")) |value| {
                payload.startup = std.meta.stringToEnum(busybar.smart_home.StartupState, value) orelse {
                    try ctx.out.fail("startup must be off, on, toggle or last", .{});
                    return Error.InvalidArgument;
                };
            }
            try ctx.client.smartHome().setSwitchState(payload);
            return ctx.out.ok("switch turned {s}", .{if (on) "on" else "off"});
        }
        const parsed = try ctx.client.smartHome().switchState();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.field("switch", "{s}", .{if (parsed.value.state orelse false) "on" else "off"});
        return;
    }
    if (!eq(which, "pairing")) {
        try ctx.out.fail("unknown smarthome command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.smartHome().pairing();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("fabrics", "{?d}", .{parsed.value.fabric_count});
    if (parsed.value.latest_pairing_status) |latest| {
        try ctx.out.field("last pairing", "{t}", .{latest.value});
        if (latest.timestamp) |stamp| try ctx.out.field("at", "{d}", .{stamp});
    }
}

fn account(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "info";

    if (eq(which, "status")) {
        const parsed = try ctx.client.account().status();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        if (parsed.value.status) |value| try ctx.out.field("mqtt", "{t}", .{value});
        return;
    }
    if (eq(which, "link")) {
        const parsed = try ctx.client.account().link();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.field("code", "{?s}", .{parsed.value.code});
        try ctx.out.field("expires at", "{?d}", .{parsed.value.expires_at});
        return;
    }
    if (eq(which, "unlink")) {
        try ctx.confirm("unlinking the device from its account");
        try ctx.client.account().unlink();
        return ctx.out.ok("unlinked", .{});
    }
    if (eq(which, "backend")) {
        if (ctx.args.get("url")) |url| {
            var config: busybar.account.Backend = .{
                .server_url = url,
                .client_cert_type = .default,
                .ignore_server_cert = ctx.args.has("insecure"),
            };
            if (ctx.args.get("cert")) |value| {
                config.client_cert_type = std.meta.stringToEnum(busybar.account.CertType, value) orelse {
                    try ctx.out.fail("cert must be default, custom or none", .{});
                    return Error.InvalidArgument;
                };
            }
            try ctx.client.account().setBackend(config);
            return ctx.out.ok("backend set to {s}", .{url});
        }
        const parsed = try ctx.client.account().backend();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.field("server", "{s}", .{parsed.value.server_url});
        try ctx.out.field("client cert", "{t}", .{parsed.value.client_cert_type});
        try ctx.out.field("ignore server cert", "{}", .{parsed.value.ignore_server_cert});
        return;
    }
    if (!eq(which, "info")) {
        try ctx.out.fail("unknown account command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.account().info();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    try ctx.out.field("linked", "{?}", .{parsed.value.linked});
    try ctx.out.field("email", "{?s}", .{parsed.value.email});
    try ctx.out.field("device id", "{?s}", .{parsed.value.id});
    try ctx.out.field("user id", "{?s}", .{parsed.value.user_id});
}

fn update(ctx: Context, command: ?[]const u8) !void {
    const which = command orelse "status";

    if (eq(which, "check")) {
        try ctx.client.update().check();
        return ctx.out.ok("update check started", .{});
    }
    if (eq(which, "abort")) {
        try ctx.client.update().abortDownload();
        return ctx.out.ok("abort signalled", .{});
    }
    if (eq(which, "changelog")) {
        const wanted = try ctx.require(2, "version");
        const parsed = try ctx.client.update().changelog(wanted);
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.line("{?s}", .{parsed.value.changelog});
        return;
    }
    if (eq(which, "install")) {
        const wanted = try ctx.require(2, "version");
        try ctx.confirm("installing firmware");
        try ctx.client.update().install(wanted);
        return ctx.out.ok("installing {s}", .{wanted});
    }
    if (eq(which, "upload")) {
        const source = try ctx.require(2, "package");
        try ctx.confirm("uploading a firmware package");
        const body = try ctx.readInput(source);
        defer ctx.allocator.free(body);
        try ctx.client.update().upload(body);
        return ctx.out.ok("uploaded {d} bytes", .{body.len});
    }
    if (eq(which, "autoupdate")) {
        const enable = ctx.args.has("enable");
        const disable = ctx.args.has("disable");
        const start = ctx.args.get("start");
        const end = ctx.args.get("end");
        if (enable or disable or start != null or end != null) {
            try ctx.client.update().setAutoupdate(.{
                .is_enabled = if (enable) true else if (disable) false else null,
                .interval_start = start,
                .interval_end = end,
            });
            return ctx.out.ok("autoupdate settings applied", .{});
        }
        const parsed = try ctx.client.update().autoupdate();
        defer parsed.deinit();
        if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
        try ctx.out.field("autoupdate", "{?}", .{parsed.value.is_enabled});
        try ctx.out.field("window start", "{?s}", .{parsed.value.interval_start});
        try ctx.out.field("window end", "{?s}", .{parsed.value.interval_end});
        return;
    }
    if (!eq(which, "status")) {
        try ctx.out.fail("unknown update command '{s}'", .{which});
        return Error.UnknownCommand;
    }

    const parsed = try ctx.client.update().status();
    defer parsed.deinit();
    if (ctx.out.mode == .json) return ctx.out.value(parsed.value);
    if (parsed.value.check) |check| {
        if (check.status) |value| try ctx.out.field("check", "{t}", .{value});
        if (check.available_version) |value| {
            if (value.len > 0) try ctx.out.field("available", "{s}", .{value});
        }
    }
    if (parsed.value.install) |install| {
        if (install.status) |value| try ctx.out.field("install", "{t}", .{value});
        if (install.action) |value| try ctx.out.field("action", "{t}", .{value});
        if (install.is_allowed) |value| try ctx.out.field("allowed", "{}", .{value});
        if (install.download) |download| {
            const total = download.total_bytes orelse 0;
            if (total > 0) {
                var received_buffer: [64]u8 = undefined;
                var total_buffer: [64]u8 = undefined;
                try ctx.out.field("downloaded", "{s} of {s}", .{
                    render.humanBytes(&received_buffer, @intCast(@max(download.received_bytes orelse 0, 0))),
                    render.humanBytes(&total_buffer, @intCast(total)),
                });
            }
        }
    }
}
