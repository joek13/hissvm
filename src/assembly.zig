const vm = @import("./vm.zig");
const core = @import("./core.zig");
const std = @import("std");

const AssemblerError = error{ InvalidToken, UnexpectedToken, OutOfRange, UnresolvedReference, DuplicateLabel };

const TokenType = enum { section, lbrace, rbrace, int, label, htype, instr, ident, eof };

const Token = union(TokenType) {
    // Section header, e.g.
    // .constants
    section: []const u8,
    // Left brace, i.e., {
    lbrace: void,
    // Right brace, i.e., }
    rbrace: void,
    // Base-agnostic integer literal.
    int: u64,
    // Jump label, e.g.,
    // main:
    label: []const u8,
    // Type declaration.
    htype: core.HType,
    // VM instruction.
    instr: vm.Op,
    // Label reference, e.g.,
    // $main
    ident: []const u8,
    // End of file
    eof: void,

    fn eql(self: Token, other: Token) bool {
        // Check that both tokens are the same variant
        if (@as(std.meta.Tag(Token), self) != @as(std.meta.Tag(Token), other)) {
            return false;
        }

        return switch (self) {
            .section => std.mem.eql(u8, self.section, other.section),
            .lbrace => true,
            .rbrace => true,
            .int => self.int == other.int,
            .label => std.mem.eql(u8, self.label, other.label),
            .htype => self.htype == other.htype,
            .instr => self.instr == other.instr,
            .ident => std.mem.eql(u8, self.ident, other.ident),
            .eof => true,
        };
    }
};

fn convertToken(token_or_null: ?[]const u8) AssemblerError!Token {
    const token = token_or_null orelse return .eof;
    if (token.len == 0) return AssemblerError.InvalidToken;

    if (std.mem.eql(u8, token, "{")) {
        // Left brace
        return .lbrace;
    } else if (std.mem.eql(u8, token, "}")) {
        // Right brace
        return .rbrace;
    } else if (std.fmt.parseInt(u64, token, 0) catch null) |i| {
        // Integer literal
        return .{ .int = i };
    } else if (token[0] == '.') {
        // Section header
        const section_name = token[1..token.len];
        return .{ .section = section_name };
    } else if (token[token.len - 1] == ':') {
        // Jump label
        const label_name = token[0 .. token.len - 1];
        return .{ .label = label_name };
    } else if (token[0] == '$') {
        // Label reference
        const label_name = token[1..];
        return .{ .ident = label_name };
    } else {
        // VM instruction or type
        const op_or_null = std.meta.stringToEnum(vm.Op, token);
        const type_or_null = std.meta.stringToEnum(core.HType, token);

        return if (op_or_null) |op| .{ .instr = op } else if (type_or_null) |htype| .{ .htype = htype } else error.InvalidToken;
    }
}

/// Returns the data type associated with a given token type.
/// E.g., for .instr, it's vm.Op. For .lbrace, it's void.
fn TokenData(comptime tokenType: TokenType) type {
    const info = @typeInfo(Token).Union;
    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, @tagName(tokenType))) return field.type;
    }
    @compileError("Invalid tag");
}

const TokenIterator = struct {
    inner: std.mem.TokenIterator(u8, .any),

    fn init(source: []const u8) TokenIterator {
        return TokenIterator{ .inner = std.mem.tokenizeAny(u8, source, &std.ascii.whitespace) };
    }

    fn peek(self: *TokenIterator) AssemblerError!Token {
        return convertToken(self.inner.peek());
    }

    fn next(self: *TokenIterator) AssemblerError!Token {
        return convertToken(self.inner.next());
    }

    fn expectLit(self: *TokenIterator, expected: Token) AssemblerError!void {
        const actual = try self.next();
        if (!expected.eql(actual)) return AssemblerError.UnexpectedToken;
    }

    /// Expect any token of type `expectedType`. Returns token data.
    fn expectAny(self: *TokenIterator, comptime expectedType: TokenType) AssemblerError!TokenData(expectedType) {
        const actual = try self.next();
        if (@as(TokenType, actual) != expectedType) return AssemblerError.UnexpectedToken;
        return @field(actual, @tagName(expectedType));
    }
};

test "expect us to correctly tokenize a simple string" {
    const source = ".constants: { hint } 16 0x10 main: pushc $main";
    var iter = TokenIterator.init(source);

    try iter.expectLit(.{ .section = "constants" });
    try iter.expectLit(.lbrace);
    try iter.expectLit(.{ .htype = .hint });
    try iter.expectLit(.rbrace);
    try iter.expectLit(.{ .int = 16 });
    try iter.expectLit(.{ .int = 16 });
    try iter.expectLit(.{ .label = "main" });
    try iter.expectLit(.{ .instr = vm.Op.pushc });
    try iter.expectLit(.{ .ident = "main" });
    // Should return EOF after input is exhausted
    try iter.expectLit(.eof);
    try iter.expectLit(.eof);
}

test "expect us to fail on an invalid instruction" {
    const source = "main: popcount";
    var iter = TokenIterator.init(source);

    try iter.expectLit(.{ .label = "main" });
    try std.testing.expectEqual(error.InvalidToken, iter.next());
}

test "expect us to fail on an unexpected token" {
    const source = "}";
    var iter = TokenIterator.init(source);

    // Expect lbrace, but actual token is rbrace
    try std.testing.expectEqual(error.UnexpectedToken, iter.expectLit(.lbrace));
}

const LabelReference = struct {
    /// Bytecode offset to paste resolved symbol address.
    offset: usize,
    /// Label to resolve.
    label: []const u8,
    /// Whether this reference has been resolved.
    resolved: bool = false,
};

pub const Assembler = struct {
    tokens: TokenIterator,
    bytecode: std.ArrayList(u8),
    references: std.ArrayList(LabelReference),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Assembler {
        return .{ .tokens = TokenIterator.init(source), .bytecode = std.ArrayList(u8).init(allocator), .references = std.ArrayList(LabelReference).init(allocator) };
    }

    pub fn deinit(self: Assembler) void {
        self.bytecode.deinit();
        self.references.deinit();
    }

    /// Reads module constants.
    fn readConstants(self: *Assembler) !void {
        // Module constants are expected to have the following format:
        // .constants {
        //   hfunc 0 $main
        //   hint 0x5
        //   <...>
        // }

        try self.tokens.expectLit(.{ .section = "constants" });
        try self.tokens.expectLit(.lbrace);

        // Read constants until end of block.
        var num_constants: u8 = 0;
        while (!(try self.tokens.peek()).eql(.rbrace)) {
            num_constants += 1;

            // First token of a constant is its type declaration
            const decl_type = try self.tokens.expectAny(.htype);

            // Append type tag to bytecode
            try self.bytecode.append(@intFromEnum(decl_type));

            switch (decl_type) {
                .hint => {
                    // hint <value>
                    const value = try self.tokens.expectAny(.int);
                    var buffer: [8]u8 = undefined;
                    std.mem.writeInt(u64, &buffer, value, .big);

                    try self.bytecode.appendSlice(&buffer);
                },
                .hfunc => {
                    // hfunc <arity> <function offset>
                    const arity = try self.tokens.expectAny(.int);
                    const arity_u8 = std.math.cast(u8, arity) orelse return AssemblerError.OutOfRange;

                    try self.bytecode.append(arity_u8);

                    const offset_token = try self.tokens.next();
                    switch (offset_token) {
                        .int => |offset| {
                            var buffer: [8]u8 = undefined;
                            std.mem.writeInt(u64, &buffer, offset, .big);
                            try self.bytecode.appendSlice(&buffer);
                        },
                        .ident => |label| {
                            // We don't yet know the offset for the referenced label. Add a placeholder for us to fill later.
                            try self.references.append(.{ .offset = self.bytecode.items.len, .label = label });
                            try self.bytecode.appendNTimes(0xFF, 8);
                        },
                        else => return error.UnexpectedToken,
                    }
                },
            }
        }

        // Write number of constants
        self.bytecode.items[4] = num_constants;

        try self.tokens.expectLit(.rbrace);
    }

    /// Reads module code.
    fn readCode(self: *Assembler) !void {
        try self.tokens.expectLit(.{ .section = "code" });
        try self.tokens.expectLit(.lbrace);

        // Bytecode offset of .code section
        const code_section = self.bytecode.items.len;

        // Read until end of block
        while (!(try self.tokens.peek()).eql(.rbrace)) {
            const token = try self.tokens.next();
            switch (token) {
                .label => |label| {
                    // Function offsets are relative to the beginning of the .code section
                    const code_offset = self.bytecode.items.len - code_section;
                    const code_offset_i64 = std.math.cast(i64, code_offset) orelse return AssemblerError.OutOfRange;

                    // When we see a label, go back and fill in its placeholders
                    for (self.references.items) |*reference| {
                        if (std.mem.eql(u8, label, reference.label)) {
                            if (reference.resolved) {
                                // Reference has already been resolved. This label must be duplicated
                                return error.DuplicateLabel;
                            } else {
                                reference.resolved = true;
                            }

                            const placeholder = self.bytecode.items[reference.offset..][0..8];
                            std.mem.writeInt(i64, placeholder, code_offset_i64, .big);
                        }
                    }
                },
                .instr => |op| {
                    try self.bytecode.append(@intFromEnum(op));
                },
                .int => |value| {
                    const byte = std.math.cast(u8, value) orelse return AssemblerError.OutOfRange;
                    try self.bytecode.append(byte);
                },
                else => return AssemblerError.UnexpectedToken,
            }
        }

        try self.tokens.expectLit(.rbrace);
    }

    pub fn readModule(self: *Assembler) ![]const u8 {
        // Append hiss magic bytes
        try self.bytecode.appendSlice("hiss");

        // Append placeholder for number of constants
        try self.bytecode.append(0x00);

        // Read module constants and code
        try self.readConstants();
        try self.readCode();

        // Check that all references were resolved
        for (self.references.items) |reference| {
            if (!reference.resolved) return AssemblerError.UnresolvedReference;
        }

        return self.bytecode.items;
    }
};

test "expect us to read well formed assembly" {
    const source =
        \\ .constants {
        \\   hfunc 0 0xDEADBEEF
        \\   hint 0x05
        \\ }
        \\ 
        \\ .code {
        \\   main: noop
        \\ }
    ;
    var assembler = Assembler.init(std.testing.allocator, source);
    defer assembler.deinit();

    const buffer = try assembler.readModule();
    std.debug.print("{any}", .{buffer});
}
