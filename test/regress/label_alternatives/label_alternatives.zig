//! Minimal @lang module: the Tag enum and a pass-through Lexer wrapper,
//! plus a reference that makes the compiler analyze writeFacts.
const parser = @import("parser.zig");

pub const Tag = parser.Tag;

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
    pub fn text(self: *const Lexer, tok: parser.Token) []const u8 {
        return self.base.text(tok);
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};
