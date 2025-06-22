const std = @import("std");

pub fn build(b: *std.Build) void {
    // Create module for the library.
    const mod = b.addModule("hissvm", .{ .root_source_file = b.path("src/hissvm.zig"), .target = b.graph.host });

    // Unit tests
    const unit_tests = b.addTest(.{ .root_source_file = b.path("src/hissvm.zig"), .target = b.graph.host });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Format check and fix
    const fmt_include_paths = &.{ "build.zig", "src", "tools" };

    const check_fmt = b.addFmt(.{ .paths = fmt_include_paths, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check formatting");
    fmt_check_step.dependOn(&check_fmt.step);

    const fix_fmt = b.addFmt(.{ .paths = fmt_include_paths, .check = false });
    const fmt_fix_step = b.step("fmt-fix", "Fix formatting in-place");
    fmt_fix_step.dependOn(&fix_fmt.step);

    const mod_iotests = b.addModule("iotests", .{ .root_source_file = b.path("tools/iotests.zig"), .target = b.graph.host });
    // Make hissvm module available to iotests.
    mod_iotests.addImport("hissvm", mod);

    // Compile and run iotests
    const iotests = b.addExecutable(.{
        .name = "iotests",
        .root_module = mod_iotests,
    });
    const install_iotests = b.addInstallArtifact(iotests, .{});

    const run_iotests = b.addRunArtifact(iotests);
    run_iotests.addFileArg(b.path("sample/")); // Run iotests under samples/

    const iotests_step = b.step("iotests", "Run iotests");
    iotests_step.dependOn(&run_iotests.step);
    iotests_step.dependOn(&install_iotests.step);

    // hissasm tool
    const mod_hissasm = b.addModule("hissasm", .{ .root_source_file = b.path("tools/hissasm.zig"), .target = b.graph.host });
    mod_hissasm.addImport("hissvm", mod);

    // compile and install hissasm
    const hissasm = b.addExecutable(.{ .name = "hissasm", .root_module = mod_hissasm });
    const install_hissasm = b.addInstallArtifact(hissasm, .{});
    b.getInstallStep().dependOn(&install_hissasm.step);

    // hissvm tool
    const mod_hissvm = b.addModule("hissvm", .{ .root_source_file = b.path("tools/hissvm.zig"), .target = b.graph.host });
    mod_hissvm.addImport("hissvm", mod);

    // compile and install hissvm
    const hissvm = b.addExecutable(.{ .name = "hissvm", .root_module = mod_hissvm });
    const install_hissvm = b.addInstallArtifact(hissvm, .{});
    b.getInstallStep().dependOn(&install_hissvm.step);

    const all = b.step("all", "Check formatting, run unit tests, and run iotests");
    all.dependOn(fmt_check_step);
    all.dependOn(test_step);
    all.dependOn(iotests_step);
    all.dependOn(&install_hissasm.step);
    all.dependOn(&install_hissvm.step);
}
