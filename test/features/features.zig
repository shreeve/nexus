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

pub fn keyword_as(_: []const u8, _: u16) ?u16 {
    return null;
}
