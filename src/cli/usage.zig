const std = @import("std");
const render = @import("render.zig");

const text =
    \\busybar controls a Flipper BUSY Bar over its HTTP API.
    \\
    \\Usage: busybar [options] <command> [arguments]
    \\
    \\Options:
    \\  -a, --address <host>   Device address, or BUSYBAR_ADDRESS
    \\  -t, --token <token>    API token, or BUSYBAR_TOKEN
    \\      --json             Print responses as JSON
    \\      --yes              Confirm a destructive command
    \\      --help             Show this text
    \\      --version          Show the version
    \\
    \\System:
    \\  version                          API version
    \\  status [device|firmware|system|power]
    \\  transport                        Connection type
    \\  log-dump [--filename <name>]     Snapshot the log buffer
    \\
    \\Settings:
    \\  name [<new-name>]                Read or set the device name
    \\  access [<disabled|enabled|key>] [--key <digits>]
    \\  brightness [<0-100|auto>]        Read or set display brightness
    \\  volume [<0-100>] [--silent]      Read or set audio volume
    \\  input <key>                      Send up, down, ok, back, start,
    \\                                   busy, custom, off, apps or settings
    \\
    \\Display:
    \\  screen [front|back] [--output <file>] [--bmp]
    \\  display text <text> --app <name> [--font <font>] [--display <front|back>]
    \\                      [--x <n>] [--y <n>] [--align <anchor>] [--color <#RRGGBBAA>]
    \\                      [--timeout <seconds>] [--priority <1-100>] [--id <id>]
    \\                      [--width <n>] [--led <#RRGGBBAA>]
    \\  display draw --file <file|->      Draw a full JSON element payload
    \\  display clear [--app <name>]      Clear drawn elements
    \\
    \\Audio and assets:
    \\  audio play --app <name> (--path <file> | --stock <file>)
    \\  audio stop
    \\  assets upload <local-file> --app <name> [--name <target>]
    \\  assets delete --app <name> --yes
    \\
    \\Storage:
    \\  storage list <path>
    \\  storage read <path> [--output <file>]
    \\  storage write <path> <local-file>
    \\  storage remove <path> --yes
    \\  storage mkdir <path>
    \\  storage rename <path> <new-path>
    \\  storage status
    \\
    \\Timers:
    \\  busy start [busy|custom]         Start a timer from a profile
    \\  busy stop                        Stop the running timer
    \\  busy pause                       Pause the running timer
    \\  busy resume                      Resume a paused timer
    \\  busy snapshot [--file <file|->]
    \\  busy profile <busy|custom> [--file <file|->]
    \\
    \\Time:
    \\  time [<iso-8601>]                Read or set the clock
    \\  timezone [<name>]                Read or set the time zone
    \\  tzlist                           Supported time zones
    \\
    \\Connectivity:
    \\  ble [status|enable|disable|unpair]
    \\  wifi [status|networks]
    \\  wifi connect --ssid <ssid> [--password <pass>] [--security <method>]
    \\               [--ip <address> --mask <mask> --gateway <gateway>]
    \\  wifi disconnect --yes
    \\
    \\Smart home:
    \\  smarthome [pairing|pair]
    \\  smarthome unpair --yes
    \\  smarthome switch [on|off] [--startup <off|on|toggle|last>]
    \\
    \\Account:
    \\  account [info|status|link]
    \\  account unlink --yes
    \\  account backend [--url <url> --cert <default|custom|none> [--insecure]]
    \\
    \\Updates:
    \\  update [status|check|abort]
    \\  update changelog <version>
    \\  update install <version> --yes
    \\  update upload <package> --yes
    \\  update autoupdate [--enable|--disable] [--start <HH:MM>] [--end <HH:MM>]
    \\
;

pub fn print(out: render.Writer) !void {
    try out.bytes(text);
}
