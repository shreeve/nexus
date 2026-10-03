//! @lang module of the as_stale_id test: the keyword group's Id enum and
//! lookup.
const std = @import("std");

pub const KwId = enum(u16) { KW = 1, X = 2, Y = 3 };

pub fn kwAs(text: []const u8) ?KwId {
    if (std.mem.eql(u8, text, "kw")) return .KW;
    if (std.mem.eql(u8, text, "x")) return .X;
    if (std.mem.eql(u8, text, "y")) return .Y;
    return null;
}
