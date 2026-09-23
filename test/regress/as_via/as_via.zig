//! @lang module of the as_via test: the Tag enum, the keyword Id enum, and
//! the explicitly named lookup function.
const std = @import("std");

pub const Tag = enum(u8) { program, go, stop, name };

pub const KwId = enum(u16) { GO = 1, STOP = 2 };

pub fn lookupKeyword(text: []const u8) ?KwId {
    if (std.mem.eql(u8, text, "go")) return .GO;
    if (std.mem.eql(u8, text, "stop")) return .STOP;
    return null;
}
