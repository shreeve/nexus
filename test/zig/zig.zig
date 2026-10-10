//! @lang module for zig.grammar.
const std = @import("std");
const parser = @import("parser.zig");

/// The generated lexer, starting after a UTF-8 byte order mark at offset 0
/// (std.zig.Tokenizer.init skips it; no lexer rule can see the start of
/// the input).
pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        var base = parser.BaseLexer.init(source);
        if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) base.pos = 3;
        return .{ .base = base };
    }

    pub fn next(self: *Lexer) parser.Token {
        return self.base.next();
    }
};
