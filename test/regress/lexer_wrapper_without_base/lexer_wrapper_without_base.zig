//! A Lexer wrapper whose generated lexer is not in a `base` field.
const parser = @import("parser.zig");

pub const Lexer = struct {
    inner: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .inner = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        return self.inner.next();
    }
};
