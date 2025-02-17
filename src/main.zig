const std = @import("std");

const core = @import("core.zig");
const vm = @import("vm.zig");
const bytecode = @import("bytecode.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const program = [_]u8{
        // hiss magic bytes
        0x68, 0x69, 0x73, 0x73,
        // number of constants
        0x04,
        // constant for main function
        0x02, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00,
        // constant for add function
        0x02,
        0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x0A,
        // Constant integer 4
        0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x04,
        // Constant integer 6
        0x01, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x06,
        // Program code
        // main
        0x00,
        0x11, 0x02, // pushc $4
        0x11, 0x03, // pushc $6
        0x11, 0x01, // pushc add()
        0x21, // call
        0xf0, // print
        0x20, // halt

        // add(x, y)
        0x13, 0x00, // loadv 0
        0x13, 0x01, // loadv 1
        0x30, // iadd
        0x22, // ret
    };

    var reader = bytecode.ModuleReader.init(allocator, &program);
    defer reader.deinit();

    const mod = try reader.readModule();
    var machine = try vm.Machine.init(allocator, mod);
    defer machine.deinit();

    const stdin = std.io.getStdIn().reader();
    while (true) {
        machine.printState();
        var buf: [10]u8 = undefined;
        _ = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        const halt = try machine.step();
        if (halt) break;
    }
}
