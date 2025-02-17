pub const HType = enum { hint, hfunc };

pub const HValue = union(HType) { hint: i64, hfunc: Func };

// Hiss booleans are represented as signed integers.
pub fn hbool(b: bool) HValue {
    return HValue{ .hint = if (b) 1 else 0 };
}

pub const Func = struct {
    /// Offset into program.
    offset: usize,
    arity: usize,
};
