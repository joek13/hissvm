const std = @import("std");

const core = @import("core.zig");

pub const Op = enum(u8) {
    // noop - no operation
    // Does nothing.
    noop = 0x00,

    // == STACK MANIPULATION ==

    // pushc <idx> - push a constant onto the stack
    // Reads constant at given index and pushes onto the stack.
    pushc = 0x11,

    // pop - pop a value off of the stack
    // Removes the value at the top of the stack.
    pop = 0x12,

    // loadv <idx> - load from a local variable
    // Loads the local variable at given index and pushes onto the stack.
    loadv = 0x13,

    // storev <idx> - store into a local variable
    // Pops a value off the top of the stack and stores in a local variable at the given index.
    storev = 0x14,

    // == CONTROL FLOW ==

    // halt - stops program execution
    halt = 0x20,

    // call - calls a function
    // Pops a function off the top of the stack and begins executing it.
    call = 0x21,

    // ret - return to caller
    // Execution returns to the caller.
    ret = 0x22,

    // br <then1> <then2> - conditional branch
    // Pops a boolean off the stack.
    // then1 and then2 form the high and low byte of a signed 16-bit offset.
    // If true, adjusts PC by this offset.
    // Otherwise, continues to next instruction.
    br = 0x23,

    // jmp <offset1> <offset2> - jump
    // offset1 and offset2 form the high and low byte of a signed 16-bit offset.
    // Adjusts PC by this offset.
    jmp = 0x24,

    // == ARITHMETIC ==

    // iadd - integer addition
    // Pops x,y off of the stack and then pushes x+y
    iadd = 0x30,

    // isub - integer subtraction
    // Pops x,y off of the stack and then pushes x-y
    isub = 0x31,

    // imul - integer multiplication
    // Pops x,y off of the stack and then pushes x*y
    imul = 0x32,

    // idiv - integer division
    // Pops x,y off of the stack and then pushes x/y
    idiv = 0x33,

    // iand - bitwise AND
    // Pops x,y off of the stack and then pushes x&y
    iand = 0x34,

    // ior - bitwise OR
    // Pops x,y off of the stack and then pushes x|y
    ior = 0x35,

    // icmp <op> - integer comparison
    // Pops x off the stack and compares with zero. Pushes result.
    icmp = 0x36,

    // == DEBUG ==

    // print - print a value
    // Prints the value at the top of the stack without modifying it.
    print = 0xf0,
};

const Cmp = enum(u8) {
    // x == 0
    eq = 0x00,
    // x != 0
    neq = 0x01,
    // x < 0
    lt = 0x02,
    // x <= 0
    leq = 0x03,
    // x > 0
    gt = 0x04,
    // x >= 0
    geq = 0x05,
};

const Frame = struct {
    func: core.Func,
    /// Frame pointer. Stack offset where this frame's locals begin.
    fp: usize,
    ret_addr: usize,
};

pub const Module = struct {
    constants: []const core.HValue,
    code: []const u8,
};

/// Reads a signed offsets from two u8's.
/// High and low are taken as the high and low bytes of an i16.
fn readSignedOffset(high: u8, low: u8) isize {
    const unsigned = @as(u16, high) << 8 | low;
    const signed: i16 = @bitCast(unsigned);
    return @intCast(signed);
}

pub const Machine = struct {
    mod: Module,
    pc: usize,
    stack: std.ArrayList(core.HValue),
    frames: std.ArrayList(Frame),

    pub fn init(allocator: std.mem.Allocator, mod: Module) !Machine {
        const stack = std.ArrayList(core.HValue).init(allocator);
        var frames = std.ArrayList(Frame).init(allocator);

        // By convention, constant 0 is the main function
        const main = mod.constants[0].hfunc;
        const frame = Frame{ .func = main, .fp = 0, .ret_addr = 0 };
        try frames.append(frame);

        const machine = Machine{ .mod = mod, .pc = main.offset, .stack = stack, .frames = frames };
        return machine;
    }

    pub fn deinit(self: *Machine) void {
        self.stack.deinit();
        self.frames.deinit();
    }

    fn readByte(self: *Machine) u8 {
        const byte = self.mod.code[self.pc];
        self.pc += 1;
        return byte;
    }

    fn readOp(self: *Machine) Op {
        return @enumFromInt(self.readByte());
    }

    fn readCmp(self: *Machine) Cmp {
        return @enumFromInt(self.readByte());
    }

    fn curFrame(self: *Machine) *Frame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn popStack(self: *Machine) core.HValue {
        return self.stack.pop() orelse @panic("pop on empty stack");
    }

    fn pushStack(self: *Machine, v: core.HValue) !void {
        try self.stack.append(v);
    }

    pub fn step(self: *Machine, writer: anytype) !bool {
        if (self.frames.items.len == 0)
            return true; // halt if we return from main

        if (self.pc >= self.mod.code.len)
            return true; // halt if we run out of code to execute

        switch (self.readOp()) {
            .noop => {},

            // pushc <idx>
            .pushc => {
                const c = self.mod.constants[self.readByte()];
                try self.pushStack(c);
            },

            .pop => {
                _ = self.popStack();
            },

            // loadv <idx>
            .loadv => {
                // Assigning to a var here is a workaround to prevent the compiler
                // from applying an incorrect parameter reference optimization that
                // can cause undefined behavior and segfaults.
                // Ref: https://github.com/ziglang/zig/issues/23050
                var v: core.HValue = undefined;
                v = self.stack.items[self.curFrame().fp + self.readByte()];
                try self.pushStack(v);
            },

            // storev <idx>
            .storev => {
                const v = self.popStack();
                self.stack.items[self.curFrame().fp + self.readByte()] = v;
            },

            .halt => {
                return true; // halt program execution
            },

            .call => {
                const callee = self.popStack().hfunc;

                // Function arguments are last N items on stack
                const fp = self.stack.items.len - callee.arity;

                const frame = Frame{ .func = callee, .fp = fp, .ret_addr = self.pc };
                try self.frames.append(frame);

                self.pc = callee.offset;
            },

            .ret => {
                // Pop frame we are returning from and jump to its ret_addr
                const frame = self.frames.pop() orelse @panic("ret with empty callstack");
                self.pc = frame.ret_addr;

                // Pop return value from stack and deallocate remaining stack variables
                const ret_val = self.popStack();
                self.stack.items.len = frame.fp;
                // Push return value to stack
                try self.pushStack(ret_val);
            },

            .br => {
                const cond = self.popStack().hint;
                const br_offset = readSignedOffset(self.readByte(), self.readByte());

                switch (cond) {
                    1 => self.pc = @intCast(@as(isize, @intCast(self.pc)) + br_offset),
                    0 => {},
                    else => @panic("Invalid bool"),
                }
            },

            .jmp => {
                const jmp_offset = readSignedOffset(self.readByte(), self.readByte());
                self.pc = @intCast(@as(isize, @intCast(self.pc)) + jmp_offset);
            },

            .iadd => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = x + y });
            },

            .isub => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = x - y });
            },

            .imul => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = x * y });
            },

            .idiv => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = @divTrunc(x, y) });
            },

            .iand => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = x & y });
            },

            .ior => {
                const x = self.popStack().hint;
                const y = self.popStack().hint;
                try self.pushStack(.{ .hint = x | y });
            },

            .icmp => {
                const x = self.popStack().hint;
                const result = switch (self.readCmp()) {
                    .eq => x == 0,
                    .neq => x != 0,
                    .lt => x < 0,
                    .leq => x <= 0,
                    .gt => x > 0,
                    .geq => x >= 0,
                };
                try self.pushStack(core.hbool(result));
            },

            .print => {
                const v = self.stack.getLast();
                switch (v) {
                    .hint => |x| {
                        try writer.print("{}\n", .{x});
                    },
                    .hfunc => |f| {
                        try writer.print("<{}-ary fn @ 0x{X:0>2}>\n", .{ f.arity, f.offset });
                    },
                }
            },
        }

        return false;
    }

    pub fn printState(self: *Machine) void {
        const codeWidth = 8;

        // Clear screen and reset cursor
        std.debug.print("\x1b[2J\x1b[H", .{});

        // Print out constants
        std.debug.print("Constants:\n", .{});
        for (self.mod.constants, 0..) |c, i| {
            std.debug.print("{}. {}\n", .{ i, c });
        }
        std.debug.print("\n", .{});

        // Print out program code
        std.debug.print("Code:\n", .{});
        for (self.mod.code, 0..) |b, i| {
            if (i % codeWidth == 0) {
                // Print out current address
                std.debug.print("{X:0>2}: ", .{i});
            }
            // Print out the byte
            std.debug.print("{X:0>2}  ", .{b});

            // Handle end of line
            if ((i + 1) % codeWidth == 0 or i + 1 == self.mod.code.len) {
                std.debug.print("\n", .{});

                // Does the program counter cursor live on this line?
                if ((self.pc / codeWidth) >= (i / codeWidth) and self.pc <= i) {
                    // Print spacer for the address labels
                    std.debug.print("    ", .{});
                    for (0..self.pc % codeWidth) |_| {
                        std.debug.print("    ", .{});
                    }
                    std.debug.print("^^", .{});
                }

                std.debug.print("\n", .{});
            }
        }
        std.debug.print("pc: {X:0>2}\n", .{self.pc});
        std.debug.print("\n", .{});

        // Print each value on stack
        std.debug.print("Stack:\n", .{});
        for (self.stack.items, 0..) |v, stack_idx| {
            std.debug.print("{}. {}", .{ stack_idx, v });

            // Annotate this element if it is the frame pointer of some frame
            for (self.frames.items, 0..) |frame, frame_idx| {
                if (stack_idx == frame.fp) {
                    std.debug.print(" <- FP #{}", .{frame_idx});
                }
            }

            std.debug.print("\n", .{});
        }

        // Print each frame
        std.debug.print("\n", .{});
        std.debug.print("Frames:\n", .{});
        for (self.frames.items, 0..) |frame, frame_idx| {
            std.debug.print("{}. {}\n", .{ frame_idx, frame });
        }
    }
};
