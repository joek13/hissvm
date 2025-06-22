// Hiss assembler.
// usage: hissasm assembly.hissa

const std = @import("std");
const hissvm = @import("hissvm");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip(); // skip process name

    const asm_path = args.next() orelse {
        std.debug.print("usage: hissasm assembly.hissa\n", .{});
        std.process.exit(1);
    };

    var asm_file = try std.fs.cwd().openFile(asm_path, .{});
    defer asm_file.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try asm_file.reader().readAllArrayList(&buffer, std.math.maxInt(usize));

    const bc = try hissvm.readModule(allocator, buffer.items);
    defer allocator.free(bc);

    const stem = std.fs.path.stem(asm_path);
    const output_path = try std.fmt.allocPrint(allocator, "{s}.hissc", .{stem});
    defer allocator.free(output_path);

    var output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    _ = try output_file.write(bc);

    std.debug.print("Output written to {s}\n", .{output_path});
}
