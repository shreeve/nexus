//! Features language module — exercises lexer features and function calls

pub const Tag = enum(u8) {
    module,
    assign,
    call,
    @"+",
    @"-",
    @"*",
    _,
};
