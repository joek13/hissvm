// Hiss VM.
// Usage: hissvm bytecode.hissc

const std = @import("std");
const hissvm = @import("hissvm");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip(); // skip process name

    const bc_path = args.next() orelse {
        std.debug.print("usage: hissvm bytecode.hissc\n", .{});
        std.process.exit(1);
    };

    var bc_file = try std.fs.cwd().openFile(bc_path, .{});
    defer bc_file.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bc = std.ArrayList(u8).init(allocator);
    defer bc.deinit();
    try bc_file.reader().readAllArrayList(&bc, std.math.maxInt(usize));

    try hissvm.interpretModule(allocator, bc.items, std.io.getStdOut().writer());
}
