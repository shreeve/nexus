//! @lang module of the schema-mode test grammar: the Tag enum and a Lexer
//! wrapper that turns keyword identifiers into keyword tokens.
const std = @import("std");
const parser = @import("parser.zig");

pub const Tag = enum(u8) {
    module,
    set,
    let,
    @"if",
    @"for",
    call,
    swap,
    @"return",
    yield,
    pass,
    array,
    neg,
    num,
    name,
    @"+",
    @"-",
    @"*",
    @"/",
    note,
    ptr,
    flag,
    @"+=",
};

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
