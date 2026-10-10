//! A lang module that declares the group @keywords declares too.
const parser = @import("parser.zig");

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        return self.base.next();
    }
};

pub fn kwAs(text: []const u8) ?parser.KwId {
    return parser.kwAs(text);
}
