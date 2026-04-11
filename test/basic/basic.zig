//! Basic language module — expression grammar for testing

pub const Tag = enum(u8) {
    module,
    neg,
    @"+",
    @"-",
    @"*",
    @"/",
    @"**",
    _,
};

pub fn keyword_as(_: []const u8, _: u16) ?u16 {
    return null;
}
