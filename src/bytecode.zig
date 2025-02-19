const std = @import("std");

const core = @import("core.zig");
const vm = @import("vm.zig");

const BytecodeError = error{ MissingMagicBytes, UnexpectedEof };

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
    // - 1 byte: single u8 representing number of module constants
    // - One or more module constants
    // - Module code

    pub fn readModule(self: *ModuleReader) (std.mem.Allocator.Error || BytecodeError)!vm.Module {
        if (!std.mem.startsWith(u8, self.buffer, "hiss")) {
            return BytecodeError.MissingMagicBytes;
        }

        self.ptr = 4; // Starting from after the magic bytes
        const num_constants = try self.readByte();
        for (0..num_constants) |_| {
            try self.constants.append(try self.readConstant());
        }

        // Remaining bytes represent program code
        const code = self.buffer[self.ptr..];

        return .{ .constants = self.constants.items, .code = code };
    }

    // Bytecode layout of a constant
    // - 1 byte: single u8 representing its type
    // - Bytes representing the value

    pub fn readConstant(self: *ModuleReader) !core.HValue {
        const htype: core.HType = @enumFromInt(try self.readByte());
        return switch (htype) {
            // Bytecode layout of an hint
            // - 8 bytes: single i64, big-endian
            .hint => core.HValue{ .hint = try self.readInt() },

            // Bytecode layout of a function
            // - 1 byte: single u8 representing function arity
            // - 8 bytes: single i64 representing function offset
            .hfunc => {
                const arity: u8 = try self.readByte();
                const offset: usize = @intCast(try self.readInt());
                return core.HValue{ .hfunc = .{ .offset = offset, .arity = arity } };
            },
        };
    }

    pub fn readByte(self: *ModuleReader) !u8 {
        if (self.ptr >= self.buffer.len) return BytecodeError.UnexpectedEof;

        const b = self.buffer[self.ptr];
        self.ptr += 1;
        return b;
    }

    pub fn readInt(self: *ModuleReader) !i64 {
        if (self.ptr + 7 >= self.buffer.len) return BytecodeError.UnexpectedEof;

        const bytes = self.buffer[self.ptr..][0..8];
        const i = std.mem.readInt(i64, bytes, .big);
        self.ptr += 8;
        return i;
    }
};

test "expect readModule fails on missing magic bytes" {
    var reader = ModuleReader.init(std.testing.allocator, "foobar");
    try std.testing.expect(reader.readModule() == error.MissingMagicBytes);
}
