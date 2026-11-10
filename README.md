# busybar.zig

[![SEGV LICENSE](https://img.shields.io/static/v1?label=SEGV%20LICENSE&message=1.1&labelColor=0060A8&color=ffffff)](https://xn--gckvb8fzb.com/segv/)

A Zig 0.17 client library for the Flipper BUSY Bar.

[<img src="https://xn--gckvb8fzb.com/images/chatroom.png" width="275">](https://xn--gckvb8fzb.com/contact/)

## Installation

Prebuilt binaries for Linux, macOS, Windows, FreeBSD, NetBSD and OpenBSD are
attached to every [release][releases]. To build from sauce use:

```sh
zig build -Doptimize=ReleaseSafe
```

The binary is written to `zig-out/bin/busybar`.

[releases]: https://github.com/mrusme/busybar.zig/releases

## Usage

The device can be specified with `--address`, or with `BUSYBAR_ADDRESS`, either
as a bare host, a host with a port, or a full URL. Without a scheme, `http://`
is assumed.

`--token` and `BUSYBAR_TOKEN` set the `X-API-Token` header.

### Example

```sh
export BUSYBAR_ADDRESS=10.0.4.20

busybar status
busybar storage list /ext
busybar display text "BUILDING" --app ci --font small --display front
busybar screen front --bmp --output frame.bmp
```

Commands print human-readable output by default. JSON output is available with
the `--json` flag.

Commands that destroy state need the additional `--yes` flag. Those are
`account unlink`, `ble unpair`, `smarthome unpair`, `assets delete`,
`storage remove`, `wifi disconnect`, `update install` and `update upload`.

Run `busybar --help` for the full command list.

Exit status is 0 on success, 1 when the device rejects a request or is
unreachable, and 2 for a usage error.

### Library

```sh
zig fetch --save https://github.com/mrusme/busybar.zig/archive/refs/tags/v0.2.0.tar.gz
```

```zig
const busybar = @import("busybar");

var client = try busybar.Client.init(gpa, io, .{ .address = "10.0.4.20" });
defer client.deinit();

const status = try client.system().status();
defer status.deinit();
std.debug.print("battery {d}%\n", .{status.value.power.?.battery_charge});

try client.display().draw(.{
    .application_name = "my_app",
    .elements = &.{
        .{ .text = .{ .id = "0", .text = "Hello", .font = .small } },
    },
});
```

Endpoints are grouped by path prefix, one accessor per group. Those are
`account`, `assets`, `audio`, `ble`, `busy`, `display`, `input`, `settings`,
`smartHome`, `storage`, `system`, `time`, `update` and `wifi`.

Calls returning JSON give back a `std.json.Parsed(T)` that the caller frees with
`deinit`. Calls returning binary data give back a slice owned by the caller's
allocator. Calls that only acknowledge return `void`.

A non-2xx response returns a Zig error, and the device's error message is
available from `client.lastError()` until the next request:

```zig
client.audio().stop() catch |err| {
    if (client.lastError()) |api| {
        std.debug.print("{s} (HTTP {d})\n", .{ api.message, api.status });
    }
    return err;
};
```

## License

Copyright © 2026 [マリウス](https://xn--gckvb8fzb.com)

busybar.zig is released under Version 1.1 of the
[SEGV License](https://xn--gckvb8fzb.com/segv/), whose full text is included in
the [LICENSE](LICENSE) file. Go read it, there will be a test on it on Monday.
