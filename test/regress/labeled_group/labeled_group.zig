//! Minimal @lang module: a pass-through Lexer wrapper, plus a reference
//! that makes the compiler analyze writeFacts.
const parser = @import("parser.zig");

comptime {
    _ = &parser.BaseParser.writeFacts;
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
