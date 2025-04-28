const std = @import("std");

pub fn build(b: *std.Build) void {
    // Create an executable and add to install step.
    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
    });
    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{ .root_source_file = b.path("src/main.zig"), .target = b.host });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Format check and fix
    const fmt_include_paths = &.{ "build.zig", "src" };

    const check_fmt = b.addFmt(.{ .paths = fmt_include_paths, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check formatting");
    fmt_check_step.dependOn(&check_fmt.step);

    const fix_fmt = b.addFmt(.{ .paths = fmt_include_paths, .check = false });
    const fmt_fix_step = b.step("fmt-fix", "Fix formatting in-place");
    fmt_fix_step.dependOn(&fix_fmt.step);

    const all = b.step("all", "Check formatting, run unit tests, and install");
    all.dependOn(fmt_check_step);
    all.dependOn(test_step);
}
