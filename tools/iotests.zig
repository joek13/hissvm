const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip(); // skip process name

    const dir_path = args.next() orelse fatal("Usage: iotests <path to iotests dir>", .{});

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    const results = try runTests(dir);
    std.debug.print("Ran {} tests, {} failed\n", .{results.ran, results.failed});
    if(results.failed != 0) {
        fatal("{} tests failed", .{results.failed});
    }
}

const TestResults = struct {
    ran: u32,
    failed: u32,

    fn plus(self: *TestResults, other: TestResults) void {
        self.ran += other.ran;
        self.failed += other.failed;
    }
};

fn runTests(dir: std.fs.Dir) !TestResults {
    var results =  TestResults { .ran = 0, .failed = 0};

    var iterator = dir.iterate();
    while(try iterator.next()) |item| {
        switch(item.kind) {
            .file => {
                // TODO: check for .expected and execute iotest
            },
            .directory => {
                var subdir = try dir.openDir(item.name, .{ .iterate = true });
                defer subdir.close();

                results.plus(try runTests(subdir));
            },
            else => {}
        }
    }

    return results;
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
