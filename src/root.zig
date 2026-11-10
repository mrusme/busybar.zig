const std = @import("std");

pub const Client = @import("Client.zig");
pub const Options = Client.Options;
pub const ApiError = Client.ApiError;
pub const Error = Client.Error;

pub const account = @import("api/account.zig");
pub const assets = @import("api/assets.zig");
pub const audio = @import("api/audio.zig");
pub const ble = @import("api/ble.zig");
pub const busy = @import("api/busy.zig");
pub const display = @import("api/display.zig");
pub const input = @import("api/input.zig");
pub const settings = @import("api/settings.zig");
pub const smart_home = @import("api/smart_home.zig");
pub const storage = @import("api/storage.zig");
pub const system = @import("api/system.zig");
pub const time = @import("api/time.zig");
pub const update = @import("api/update.zig");
pub const wifi = @import("api/wifi.zig");

test {
    std.testing.refAllDecls(@This());
    inline for (comptime std.meta.declarations(@This())) |name| {
        const namespace = @field(@This(), name);
        if (@TypeOf(namespace) == type and @typeInfo(namespace) == .@"struct") {
            std.testing.refAllDecls(namespace);
        }
    }
}
