//! @lang module for the lexer feature suite: a Lexer that copies each
//! token's `pre` into `aux` so trees show it as `#N`.
const parser = @import("parser.zig");

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        const tok = self.base.next();
        self.base.aux = tok.pre;
        return tok;
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};
