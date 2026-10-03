//! A Lexer wrapper that scans every token itself: words of a-z are
//! `ident`, blanks are skipped, anything else is `err`.

const parser = @import("parser.zig");
const Token = parser.Token;
const makeToken = parser.BaseLexer.makeToken;

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }

    pub fn next(self: *Lexer) Token {
        const src = self.base.source;
        const ws: usize = self.base.pos;
        while (self.base.pos < src.len and (src[self.base.pos] == ' ' or src[self.base.pos] == '\n')) self.base.pos += 1;
        const pre: u8 = @intCast(@min(self.base.pos - ws, 255));
        const start: usize = self.base.pos;
        if (start >= src.len) return makeToken(.eof, pre, start, start);
        while (self.base.pos < src.len and src[self.base.pos] >= 'a' and src[self.base.pos] <= 'z') self.base.pos += 1;
        if (self.base.pos > start) return makeToken(.ident, pre, start, self.base.pos);
        self.base.pos += 1;
        return makeToken(.err, pre, start, self.base.pos);
    }
};
