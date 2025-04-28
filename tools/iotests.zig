const std = @import("std");
const hissvm = @import("hissvm");

fn runTest(allocator: std.mem.Allocator, asm_path: []const u8, asm_file: std.fs.File, expected_file: std.fs.File) !u32 {
    std.debug.print("{s}... ", .{asm_path});
    // Read assembly and convert to bitcode
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try asm_file.reader().readAllArrayList(&buffer, std.math.maxInt(usize));

    const bc = hissvm.readModule(allocator, buffer.items) catch |err| {
        std.debug.print("fail: failed to read module: {}\n", .{err});
        return 1;
    };
    defer allocator.free(bc);

    // ArrayList to store program output
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    // Actually interpret the program
    hissvm.interpretModule(allocator, bc, output.writer()) catch |err| {
        std.debug.print("fail: interpreter failed: {}\n", .{err});
        return 1;
    };

    // Read expected output
    var expected_output = std.ArrayList(u8).init(allocator);
    defer expected_output.deinit();
    try expected_file.reader().readAllArrayList(&expected_output, std.math.maxInt(usize));

    const expected_trimmed = std.mem.trim(u8, expected_output.items, &std.ascii.whitespace);
    const output_trimmed = std.mem.trim(u8, output.items, &std.ascii.whitespace);

    // And make sure they match
    if (!std.mem.eql(u8, expected_trimmed, output_trimmed)) {
        // Write actual output to temp directory for comparison
        const tmp_dir_path = "/tmp/";
        var tmp_dir = try std.fs.openDirAbsolute(tmp_dir_path, .{});
        defer tmp_dir.close();

        const stem = std.fs.path.stem(asm_path);
        const output_path = try std.fmt.allocPrint(allocator, "{s}.actual", .{stem});
        defer allocator.free(output_path);

        var output_file = try tmp_dir.createFile(output_path, .{});
        defer output_file.close();

        try output_file.writeAll(output.items);

        // Print failure message
        const absolute = try std.fs.path.join(allocator, &[_][]const u8{ tmp_dir_path, output_path });
        defer allocator.free(absolute);

        std.debug.print("fail: unexpected output (actual output written to {s})\n", .{absolute});
        return 1;
    }

    std.debug.print("pass\n", .{});
    return 0;
}

const TestResults = struct {
    ran: u32,
    failed: u32,

    fn add(self: *TestResults, other: TestResults) void {
        self.ran += other.ran;
        self.failed += other.failed;
    }
};

fn runTests(allocator: std.mem.Allocator, dir: std.fs.Dir) !TestResults {
    var results = TestResults{ .ran = 0, .failed = 0 };

    var iterator = dir.iterate();
    while (try iterator.next()) |item| {
        switch (item.kind) {
            .file => {
                if (std.mem.endsWith(u8, item.name, ".expected")) {
                    const stem = std.fs.path.stem(item.name);
                    const asm_path = try std.fmt.allocPrint(allocator, "{s}.hissa", .{stem});
                    defer allocator.free(asm_path);

                    const expected_file = try dir.openFile(item.name, .{});
                    defer expected_file.close();

                    if (dir.openFile(asm_path, .{})) |asm_file| {
                        defer asm_file.close();

                        results.ran += 1;
                        results.failed += try runTest(allocator, asm_path, asm_file, expected_file);
                    } else |err| switch (err) {
                        error.FileNotFound => fatal("fatal: found {s} but not corresponding assembly {s}\n", .{ item.name, asm_path }),
                        else => |leftover_err| return leftover_err,
                    }
                }
            },
            .directory => {
                var subdir = try dir.openDir(item.name, .{ .iterate = true });
                defer subdir.close();

                results.add(try runTests(allocator, subdir));
            },
            else => {},
        }
    }

    return results;
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip(); // skip process name

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dir_path = args.next() orelse fatal("Usage: iotests <path to iotests dir>", .{});

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    const results = try runTests(allocator, dir);
    std.debug.print("Ran {} tests, {} failed\n", .{ results.ran, results.failed });
    if (results.failed != 0) {
        fatal("{} tests failed\n", .{results.failed});
    }
}
