//! @lang module of the schema-mode test grammar: re-exports the Tag enum and
//! provides a Lexer
//! wrapper that turns keyword identifiers into keyword tokens.
const std = @import("std");
const parser = @import("parser.zig");

/// The tags, generated from the grammar's @schema.
pub const Tag = parser.Tag;

const keywords = std.StaticStringMap(parser.TokenCat).initComptime(.{
    .{ "let", .let },     .{ "if", .@"if" },       .{ "unless", .unless },
    .{ "then", .then },   .{ "else", .@"else" },   .{ "return", .@"return" },
    .{ "for", .@"for" },  .{ "ptr", .ptr },        .{ "in", .in },
    .{ "do", .do },       .{ "call", .call },      .{ "swap", .swap },
    .{ "with", .with },   .{ "pass", .pass },      .{ "yield", .yield },
});

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        var tok = self.base.next();
        if (tok.cat == .ident) {
            if (keywords.get(self.base.text(tok))) |cat| tok.cat = cat;
        }
        return tok;
    }
    pub fn text(self: *const Lexer, tok: parser.Token) []const u8 {
        return self.base.text(tok);
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};
