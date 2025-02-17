const std = @import("std");

const core = @import("core.zig");
const vm = @import("vm.zig");

const BytecodeError = error{MissingMagicBytes};

pub const ModuleReader = struct {
    buffer: []const u8,
    ptr: usize = 0,
    constants: std.ArrayList(core.HValue),

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8) ModuleReader {
        return .{ .buffer = buffer, .ptr = 0, .constants = std.ArrayList(core.HValue).init(allocator) };
    }

    pub fn deinit(self: ModuleReader) void {
        self.constants.deinit();
    }

    // Bytecode layout of a module:
    // - 4 bytes: literal bytes 'hiss'
    // - 1 byte: single u8 representing number of program constants
    // - One or more module constants
    // - Module code

    pub fn readModule(self: *ModuleReader) (std.mem.Allocator.Error || BytecodeError)!vm.Module {
        if (!std.mem.startsWith(u8, self.buffer, "hiss")) {
            return BytecodeError.MissingMagicBytes;
        }

        const num_constants = self.buffer[4];

        self.ptr = 5;

        for (0..num_constants) |_| {
            try self.constants.append(self.readConstant());
        }

        const code = self.buffer[self.ptr..];

        return .{ .constants = self.constants.items, .code = code };
    }

    // Bytecode layout of a constant
    // - 1 byte: single u8 representing its type
    // - Bytes representing the value

    pub fn readConstant(self: *ModuleReader) core.HValue {
        const htype: core.HType = @enumFromInt(self.readByte());
        return switch (htype) {
            .hint => core.HValue{ .hint = self.readInt() },
            .hfunc => {
                const arity: u8 = self.readByte();
                const offset: usize = @intCast(self.readInt());
                return core.HValue{ .hfunc = .{ .offset = offset, .arity = arity } };
            },
        };
    }

    pub fn readByte(self: *ModuleReader) u8 {
        const b = self.buffer[self.ptr];
        self.ptr += 1;
        return b;
    }

    pub fn readInt(self: *ModuleReader) i64 {
        const bytes = @as(*const [8]u8, @ptrCast(self.buffer[self.ptr .. self.ptr + 8]));
        const i = std.mem.readInt(i64, bytes, .big);
        self.ptr += 8;
        return i;
    }
};

test "expect readModule fails on missing magic bytes" {
    var reader = ModuleReader.init(std.testing.allocator, "foobar");
    try std.testing.expect(reader.readModule() == error.MissingMagicBytes);
}
