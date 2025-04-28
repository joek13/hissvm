const std = @import("std");

const core = @import("core.zig");
const vm = @import("vm.zig");
const bytecode = @import("bytecode.zig");
const assembly = @import("assembly.zig");

const Subcommand = enum { assemble, debug, exec };

const CliError = error{ InvalidSubcommand, NotEnoughArgs };

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip(); // Skip process name
    const subcommand_str = args.next() orelse return CliError.NotEnoughArgs;

    const subcommand = std.meta.stringToEnum(Subcommand, subcommand_str) orelse return CliError.InvalidSubcommand;
    switch (subcommand) {
        .assemble => try assemble(&args),
        .exec => try exec(&args, false),
        .debug => try exec(&args, true),
    }
}

fn assemble(args: *std.process.ArgIterator) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const assembly_path = args.next() orelse return error.NotEnoughArgs;
    const assembly_file = try std.fs.cwd().openFile(assembly_path, .{});

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try assembly_file.reader().readAllArrayList(&buffer, std.math.maxInt(usize));

    var assembler = assembly.Assembler.init(allocator, buffer.items);
    defer assembler.deinit();

    const bc = try assembler.readModule();

    const out_path = try std.fmt.allocPrint(allocator, "{s}.hissc", .{std.fs.path.stem(assembly_path)});
    defer allocator.free(out_path);

    const out_file = try std.fs.cwd().createFile(out_path, .{ .read = true });
    try out_file.writer().writeAll(bc);

    std.debug.print("Bytecode written to {s}\n", .{out_path});
}

fn exec(args: *std.process.ArgIterator, debug: bool) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bc_path = args.next() orelse return error.NotEnoughArgs;
    const bc_file = try std.fs.cwd().openFile(bc_path, .{});

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try bc_file.reader().readAllArrayList(&buffer, std.math.maxInt(usize));

    var mod_reader = bytecode.ModuleReader.init(allocator, buffer.items);
    defer mod_reader.deinit();

    const mod = try mod_reader.readModule();
    var machine = try vm.Machine.init(allocator, mod);
    defer machine.deinit();

    var stdin = std.io.getStdIn();
    while (true) {
        if (debug) {
            machine.printState();
            var buf: [10]u8 = undefined;
            _ = try stdin.reader().readUntilDelimiterOrEof(&buf, '\n');
        }
        const halt = try machine.step();
        if (halt) break;
    }
}

test {
    std.testing.refAllDecls(@This());
}
