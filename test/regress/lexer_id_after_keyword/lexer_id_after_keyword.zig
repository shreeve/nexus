//! @lang module of the lexer_id_after_keyword test: the keyword `print`
//! (ordinal 1), and a Lexer that gives every word the id 9.
const std = @import("std");
const parser = @import("parser.zig");

pub const KwId = enum(u16) { NONE = 0, PRINT = 1 };

pub fn kwAs(text: []const u8) ?KwId {
    return if (std.mem.eql(u8, text, "print")) .PRINT else null;
}

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        const tok = self.base.next();
        if (tok.cat == .ident) self.base.aux = 9;
        return tok;
    }
};
