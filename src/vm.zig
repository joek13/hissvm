const std = @import("std");

const core = @import("core.zig");

const Op = enum(u8) {
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

    // == ARITHMETIC ==

    // iadd - integer addition
    // Pops x,y off of the stack and then pushes x+y
    iadd = 0x30,

    // == DEBUG ==

    // print - print a value
    // Prints the value at the top of the stack without modifying it.
    print = 0xf0,
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
        const frame = .{ .func = main, .fp = 0, .ret_addr = 0 };
        try frames.append(frame);

        const machine = .{ .mod = mod, .pc = main.offset, .stack = stack, .frames = frames };
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

    fn curFrame(self: *Machine) *Frame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    pub fn step(self: *Machine) !bool {
        if (self.frames.items.len == 0)
            return true; // halt if we return from main

        if (self.pc >= self.mod.code.len)
            return true; // halt if we run out of code to execute

        switch (self.readOp()) {
            .noop => {},

            // pushc <idx>
            .pushc => {
                const c = self.mod.constants[self.readByte()];
                try self.stack.append(c);
            },

            .pop => {
                _ = self.stack.pop();
            },

            // loadv <idx>
            .loadv => {
                const v = self.stack.items[self.curFrame().fp + self.readByte()];
                try self.stack.append(v);
            },

            // storev <idx>
            .storev => {
                const v = self.stack.pop();
                self.stack.items[self.curFrame().fp + self.readByte()] = v;
            },

            .halt => {
                return true; // halt program execution
            },

            .call => {
                const callee = self.stack.pop().hfunc;
                const fp = self.stack.items.len;

                // Allocate locals for function arguments by copying last N items on stack
                try self.stack.appendSlice(self.stack.items[fp - callee.arity .. fp]);

                const frame = .{ .func = callee, .fp = fp, .ret_addr = self.pc };
                try self.frames.append(frame);

                self.pc = callee.offset;
            },

            .ret => {
                // Pop frame we are returning from and jump to its ret_addr
                const frame = self.frames.pop();
                self.pc = frame.ret_addr;

                // Pop return value from stack and deallocate remaining stack variables
                const ret_val = self.stack.pop();
                self.stack.items.len = frame.fp;
                // Push return value to stack
                try self.stack.append(ret_val);
            },

            .iadd => {
                const x = self.stack.pop().hint;
                const y = self.stack.pop().hint;
                try self.stack.append(.{ .hint = x + y });
            },

            .print => {
                const v = self.stack.getLast();
                std.debug.print("{}\n", .{v});
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
