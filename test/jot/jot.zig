//! @lang module for jot.grammar: its Lexer reads `loop` as the keyword
//! where it starts a line, and as a name everywhere else.
const std = @import("std");
const parser = @import("parser.zig");

pub const Lexer = struct {
    base: parser.BaseLexer,
    /// No token but comments since the last line end (or the start).
    line_start: bool = true,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }

    pub fn next(self: *Lexer) parser.Token {
        var tok = self.base.next();
        if (tok.cat == .ident and self.line_start and std.mem.eql(u8, self.base.text(tok), "loop")) tok.cat = .kw_loop;
        if (tok.cat != .comment) self.line_start = tok.cat == .newline;
        return tok;
    }
};
