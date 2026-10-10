//! Containers: the layout, the kind, `union(enum)`'s `enum`, the argument,
//! the container doc comments (`doc`), then the members; a field's doc
//! comments, `comptime`, name, type, alignment and default value.

const S = extern struct {
    //! S's doc
    /// x's doc
    comptime x: u32 align(4) = 1,
    u8,
};
const U = packed union(enum(u8)) {
    //! U's doc
    a: u8,
};
const T = enum(u8) {
    //! an empty container
};
