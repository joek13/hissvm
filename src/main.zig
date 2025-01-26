const std = @import("std");

const core = @import("core.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const mod = vm.Module{
        .constants = &[_]core.HValue{
            // main()
            .{ .hfunc = core.Func{ .offset = 0, .arity = 0 } },
            // add(x,y)
            .{ .hfunc = core.Func{ .offset = 10, .arity = 2 } },
            .{ .hint = 4 },
            .{ .hint = 6 },
        },
        .code = &[_]u8{
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
        },
    };
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
