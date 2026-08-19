const std = @import("std");
const busybar = @import("busybar");
const build_options = @import("build_options");

const Args = @import("cli/Args.zig");
const commands = @import("cli/commands.zig");
const render = @import("cli/render.zig");
const usage = @import("cli/usage.zig");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    var out_buffer: [16384]u8 = undefined;
    var err_buffer: [1024]u8 = undefined;
    var out_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    var err_writer = std.Io.File.stderr().writer(init.io, &err_buffer);
    defer out_writer.flush() catch {};
    defer err_writer.flush() catch {};

    const argv = try init.minimal.args.toSlice(arena);
    const tail = if (argv.len > 1) argv[1..] else argv[0..0];

    var args = Args.parse(allocator, tail) catch |err| switch (err) {
        Args.Error.MissingOptionValue => {
            try err_writer.interface.writeAll("busybar: an option is missing its value\n");
            return 2;
        },
        else => return err,
    };
    defer args.deinit();

    const out: render.Writer = .{
        .out = &out_writer.interface,
        .err = &err_writer.interface,
        .mode = if (args.has("json")) .json else .human,
        .allocator = allocator,
    };

    if (args.has("version") and args.count() == 0) {
        try out.bytes("busybar " ++ build_options.version ++ "\n");
        return 0;
    }
    if (args.hasAny(&.{ "help", "h" }) or args.count() == 0) {
        try usage.print(out);
        return 0;
    }

    const address = args.getAny(&.{ "address", "a" }) orelse
        init.environ_map.get("BUSYBAR_ADDRESS") orelse
        {
            try out.fail("no device address, pass --address or set BUSYBAR_ADDRESS", .{});
            return 2;
        };
    const token = args.getAny(&.{ "token", "t" }) orelse init.environ_map.get("BUSYBAR_TOKEN");

    var client = busybar.Client.init(allocator, init.io, .{
        .address = address,
        .token = token,
    }) catch {
        try out.fail("'{s}' is not a usable address", .{address});
        return 2;
    };
    defer client.deinit();

    commands.dispatch(.{
        .allocator = allocator,
        .io = init.io,
        .client = &client,
        .args = args,
        .out = out,
    }) catch |err| return report(out, &client, err);

    return 0;
}

fn report(out: render.Writer, client: *busybar.Client, err: anyerror) !u8 {
    switch (err) {
        commands.Error.MissingArgument,
        commands.Error.InvalidArgument,
        commands.Error.UnknownCommand,
        commands.Error.NotConfirmed,
        => return 2,
        else => {},
    }

    if (client.lastError()) |api| {
        try out.fail("{s} (HTTP {d})", .{ api.message, api.status });
        return 1;
    }

    switch (err) {
        error.HostUnreachable,
        error.ConnectionRefused,
        error.NetworkUnreachable,
        => try out.fail("cannot reach the device", .{}),
        error.NoAddressReturned, error.UnknownHostName => try out.fail("cannot resolve the address", .{}),
        error.TooManyHttpRedirects => try out.fail("the address redirects elsewhere, not a device", .{}),
        error.FileNotFound => try out.fail("no such file", .{}),
        error.AccessDenied => try out.fail("permission denied", .{}),
        else => try out.fail("{t}", .{err}),
    }
    return 1;
}

test {
    _ = Args;
    _ = commands;
    _ = render;
    _ = usage;
    _ = @import("cli/bmp.zig");
}
