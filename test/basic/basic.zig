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
