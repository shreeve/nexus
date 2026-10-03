//! @lang module of the as_large_id test: a keyword Id far past the
//! grammar's symbols, and a pass-through Lexer wrapper.
const std = @import("std");
const parser = @import("parser.zig");

pub const KwId = enum(u16) { PRINT = 1, LATER = 600 };

pub fn kwAs(text: []const u8) ?KwId {
    if (std.mem.eql(u8, text, "print")) return .PRINT;
    if (std.mem.eql(u8, text, "later")) return .LATER;
    return null;
}

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        return self.base.next();
    }
};
