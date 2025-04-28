const std = @import("std");

const assembly = @import("assembly.zig");
const bytecode = @import("bytecode.zig");
const vm = @import("vm.zig");

pub fn readModule(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var assembler = assembly.Assembler.init(allocator, source);
    defer assembler.deinit();

    const bc = try assembler.readModule();
    return bc;
}

pub fn interpretModule(allocator: std.mem.Allocator, bc: []const u8, writer: anytype) !void {
    var mod_reader = bytecode.ModuleReader.init(allocator, bc);
    defer mod_reader.deinit();

    const mod = try mod_reader.readModule();
    var machine = try vm.Machine.init(allocator, mod);
    defer machine.deinit();

    while (true) {
        if (try machine.step(writer)) break;
    }
}

test {
    std.testing.refAllDecls(@This());
}
