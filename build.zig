const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Omit debug symbols from the binary") orelse false;

    const options = b.addOptions();
    options.addOption([]const u8, "version", @import("build.zig.zon").version);

    const busybar = b.addModule("busybar", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    cli.addImport("busybar", busybar);
    cli.addOptions("build_options", options);

    const exe = b.addExecutable(.{ .name = "busybar", .root_module = cli });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run the busybar command line tool").dependOn(&run.step);

    const busybar_tests = b.addTest(.{ .root_module = busybar });
    const cli_tests = b.addTest(.{ .root_module = cli });
    const test_step = b.step("test", "Run the unit tests");
    test_step.dependOn(&b.addRunArtifact(busybar_tests).step);
    test_step.dependOn(&b.addRunArtifact(cli_tests).step);

    const check_exe = b.addExecutable(.{ .name = "busybar-check", .root_module = cli });
    const check_step = b.step("check", "Type-check without emitting binaries");
    check_step.dependOn(&check_exe.step);
    check_step.dependOn(&busybar_tests.step);
    check_step.dependOn(&cli_tests.step);
}
