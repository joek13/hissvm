pub const HType = enum { hint, hbool, hfunc };

pub const HValue = union(HType) { hint: i64, hbool: bool, hfunc: Func };

pub const Func = struct {
    /// Offset into program.
    offset: usize,
    arity: usize,
};
