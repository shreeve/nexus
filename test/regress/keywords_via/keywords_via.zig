//! The lookup `@as ... via findKeyword` names for the @keywords group kw.
const std = @import("std");
const parser = @import("parser.zig");

pub fn findKeyword(text: []const u8) ?parser.KwId {
    if (std.mem.eql(u8, text, "halt")) return .STOP;
    return parser.kwAs(text);
}
