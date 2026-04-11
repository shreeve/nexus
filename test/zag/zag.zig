//! Zag Language Module
//!
//! Provides keyword lookup and tag definitions for the Zag language.
//! Imported by the generated parser via @lang = "zag".

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;
const TokenCat = parser.TokenCat;

// =============================================================================
// Tag Enum — semantic node types for S-expression output
// =============================================================================

pub const Tag = enum(u8) {
    // Module structure
    @"module",
    @"use",
    @"enum",
    @"struct",
    @"packed",
    @"labeled",
    @"type",
    @"pub",
    @"extern",
    @"export",
    @"callconv",
    @"extern_var",
    @"extern_const",
    @"opaque",
    @"volatile_ptr",
    @"many_ptr",
    @"sentinel_ptr",
    @"array_type",
    @"aligned",
    @"errors",
    @"test",
    @"zig",
    @"null",
    @"unreachable",
    @"undefined",
    @"comptime",
    @"as",
    @"??",
    @"catch",
    @"ternary",
    @"builtin",
    @"error_union",

    // Routines
    @"fun",
    @"sub",
    @"return",

    // Bindings
    @"const",
    @"typed_assign",
    @"typed_const",
    @"=",
    @"+=",
    @"-=",
    @"*=",
    @"/=",

    // Control flow
    @"if",
    @"while",
    @"for",
    @"for_ptr",
    @"match",
    @"arm",
    @"range_pattern",
    @"enum_pattern",
    @"break",
    @"continue",
    @"defer",
    @"errdefer",
    @"try",
    @"inline",
    @"lambda",

    // Calls and access
    @"addr_of",
    @"call",
    @".",
    @"deref",
    @"index",
    @"array",
    @"record",
    @"pair",

    // Operators — arithmetic
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"**",
    @"neg",
    @"not",

    // Operators — comparison
    @"==",
    @"!=",
    @"<",
    @">",
    @"<=",
    @">=",

    // Operators — logical
    @"||",
    @"&&",

    // Operators — bitwise
    @"&",
    @"|",
    @"^",
    @"<<",
    @">>",
    @"bit_not",

    // Operators — pipe and range
    @"|>",
    @"..",

    // Type annotations and type constructors
    @"typed",
    @"valued",
    @"default",
    @":",
    @"?",
    @"ptr",
    @"const_ptr",
    @"sentinel_slice",
    @"fn_type",
    @"error_merge",
    @"comptime_param",
    @"anon_init",
    @"slice",

    // Structure
    @"block",

    _,
};

// =============================================================================
// Keyword Lookup — maps identifier text to parser symbol IDs
// =============================================================================

pub const keyword_id = enum(u16) {
    FUN,
    SUB,
    USE,
    IF,
    ELSE,
    WHILE,
    FOR,
    IN,
    MATCH,
    RETURN,
    BREAK,
    CONTINUE,
    DEFER,
    ERRDEFER,
    TRY,
    FN,
    PUB,
    EXTERN,
    EXPORT,
    INLINE,
    VOLATILE,
    CONST,
    ALIGN,
    CALLCONV,
    ENUM,
    STRUCT,
    PACKED,
    OPAQUE,
    ERROR,
    TYPE,
    TEST,
    COMPTIME,
    ZIG,
    NULL,
    UNREACHABLE,
    UNDEFINED,
    AS,
    CATCH,
    TRUE,
    FALSE,
    AND,
    OR,
    NOT,
    COMMENT,
    NEWLINE,
    IDENT,
    INTEGER,
    REAL,
    STRING_SQ,
    STRING_DQ,
    INDENT,
    OUTDENT,
};

const keyword_map = std.StaticStringMap(keyword_id).initComptime(.{
    .{ "fun", .FUN },
    .{ "sub", .SUB },
    .{ "use", .USE },
    .{ "if", .IF },
    .{ "else", .ELSE },
    .{ "while", .WHILE },
    .{ "for", .FOR },
    .{ "in", .IN },
    .{ "match", .MATCH },
    .{ "return", .RETURN },
    .{ "break", .BREAK },
    .{ "continue", .CONTINUE },
    .{ "defer", .DEFER },
    .{ "errdefer", .ERRDEFER },
    .{ "try", .TRY },
    .{ "fn", .FN },
    .{ "pub", .PUB },
    .{ "extern", .EXTERN },
    .{ "export", .EXPORT },
    .{ "inline", .INLINE },
    .{ "volatile", .VOLATILE },
    .{ "const", .CONST },
    .{ "align", .ALIGN },
    .{ "callconv", .CALLCONV },
    .{ "enum", .ENUM },
    .{ "struct", .STRUCT },
    .{ "packed", .PACKED },
    .{ "opaque", .OPAQUE },
    .{ "error", .ERROR },
    .{ "type", .TYPE },
    .{ "test", .TEST },
    .{ "comptime", .COMPTIME },
    .{ "zig", .ZIG },
    .{ "null", .NULL },
    .{ "unreachable", .UNREACHABLE },
    .{ "undefined", .UNDEFINED },
    .{ "as", .AS },
    .{ "catch", .CATCH },
    .{ "true", .TRUE },
    .{ "false", .FALSE },
    .{ "and", .AND },
    .{ "or", .OR },
    .{ "not", .NOT },
});

pub fn keyword_as(name: []const u8) ?keyword_id {
    return keyword_map.get(name);
}

// =============================================================================
// Lexer — indentation-tracking wrapper around generated BaseLexer
// =============================================================================

pub const Lexer = struct {
    base: BaseLexer,
    indent_level: u32 = 0,
    indent_stack: [64]u32 = .{0} ** 64,
    indent_depth: u8 = 0,
    indent_pending: u8 = 0,
    indent_queued: ?Token = null,
    indent_trailing_newline: bool = false,
    last_cat: TokenCat = .eof,
    flow_if_active: bool = false,
    bracket_depth: u8 = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
        self.indent_level = 0;
        self.indent_depth = 0;
        self.indent_pending = 0;
        self.indent_queued = null;
        self.indent_trailing_newline = false;
        self.last_cat = .eof;
        self.flow_if_active = false;
        self.bracket_depth = 0;
    }

    pub fn next(self: *Lexer) Token {
        if (self.indent_queued) |q| {
            self.indent_queued = null;
            self.last_cat = q.cat;
            return q;
        }
        if (self.indent_pending > 0) {
            self.indent_pending -= 1;
            if (self.indent_pending == 0 and self.indent_trailing_newline) {
                self.indent_trailing_newline = false;
                self.indent_queued = Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            }
            self.last_cat = .outdent;
            return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }

        while (true) {
            const tok = self.base.matchRules();

            // Skip comment tokens
            if (tok.cat == .comment) continue;

            // Skip duplicate newlines, but still process indent changes on the last one
            if (tok.cat == .newline and (self.last_cat == .newline or self.last_cat == .indent or self.last_cat == .outdent or self.last_cat == .eof)) {
                // Peek ahead: if this newline leads to an indent change, process it
                var ws: u32 = 0;
                while (self.base.pos + ws < self.base.source.len) {
                    const ch = self.base.source[self.base.pos + ws];
                    if (ch == ' ' or ch == '\t') {
                        ws += 1;
                    } else break;
                }
                const dup_at_eof = self.base.pos + ws >= self.base.source.len;
                const dup_next = if (!dup_at_eof) self.base.source[self.base.pos + ws] else 0;
                const dup_is_empty = dup_at_eof or dup_next == '\n' or dup_next == '\r';
                if (dup_is_empty) continue;
                if (dup_next == '#' and ws == self.indent_level) continue;
                if (ws != self.indent_level) {
                    self.flow_if_active = false;
                    const result = self.handleIndent(tok);
                    self.last_cat = result.cat;
                    return result;
                }
                continue;
            }

            if (tok.cat == .newline) {
                self.flow_if_active = false;
                const result = self.handleIndent(tok);
                self.last_cat = result.cat;
                return result;
            }

            if (tok.cat == .eof) {
                self.flow_if_active = false;
                if (self.indent_depth > 0) {
                    self.indent_depth -= 1;
                    if (self.indent_depth > 0) {
                        self.indent_pending = self.indent_depth;
                        self.indent_depth = 0;
                    }
                    self.indent_level = 0;
                    self.indent_trailing_newline = false;
                    self.last_cat = .outdent;
                    return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                }
                self.last_cat = .eof;
                return tok;
            }

            if (tok.cat == .minus) {
                var classified = tok;
                classified.cat = self.classifyMinus(tok);
                self.last_cat = classified.cat;
                return classified;
            }

            if (tok.cat == .lbracket) self.bracket_depth += 1;
            if (tok.cat == .rbracket and self.bracket_depth > 0) self.bracket_depth -= 1;

            // .{ → fuse into dot_lbrace token for anonymous struct init
            if (tok.cat == .dot and self.base.pos < self.base.source.len and
                self.base.source[self.base.pos] == '{')
            {
                var fused = tok;
                fused.cat = .dot_lbrace;
                fused.len = 2;
                self.base.pos += 1;
                self.base.brace += 1;
                self.last_cat = .dot_lbrace;
                return fused;
            }

            // | → classify as bar_capture when in |name| capture context
            if (tok.cat == .bar) {
                if (self.isCapturePipe()) {
                    var cap = tok;
                    cap.cat = .bar_capture;
                    self.last_cat = .bar_capture;
                    return cap;
                }
            }

            if (tok.cat == .ident) {
                const ident_text = self.base.source[tok.pos..][0..tok.len];
                if (std.mem.eql(u8, ident_text, "if") and self.flow_if_active and
                    self.base.paren == 0 and self.base.brace == 0 and self.bracket_depth == 0)
                {
                    var post = tok;
                    post.cat = .post_if;
                    self.flow_if_active = false;
                    self.last_cat = .post_if;
                    return post;
                }
                if (std.mem.eql(u8, ident_text, "if") and !self.flow_if_active and
                    isValueCat(self.last_cat) and self.hasElseOnLine())
                {
                    var ternary = tok;
                    ternary.cat = .ternary_if;
                    self.last_cat = .ternary_if;
                    return ternary;
                }
                if (std.mem.eql(u8, ident_text, "return") or
                    std.mem.eql(u8, ident_text, "break") or
                    std.mem.eql(u8, ident_text, "continue"))
                {
                    self.flow_if_active = true;
                }
            }

            self.last_cat = tok.cat;
            return tok;
        }
    }

    fn classifyMinus(self: *const Lexer, tok: Token) TokenCat {
        const end = tok.pos + tok.len;
        const space_after = end >= self.base.source.len or
            self.base.source[end] == ' ' or self.base.source[end] == '\t' or
            self.base.source[end] == '\n' or self.base.source[end] == '\r';
        if (space_after) return .minus;
        if (!canEndExpr(self.last_cat) or tok.pre > 0) return .minus_prefix;
        return .minus;
    }

    fn canEndExpr(cat: TokenCat) bool {
        return switch (cat) {
            .ident, .integer, .real, .string_sq, .string_dq,
            .@"true", .@"false",
            .rparen, .rbracket, .rbrace,
            => true,
            else => false,
        };
    }

    fn handleIndent(self: *Lexer, nl_tok: Token) Token {
        if (self.base.paren > 0 or self.base.brace > 0) return nl_tok;

        var ws: u32 = 0;
        while (self.base.pos + ws < self.base.source.len) {
            const ch = self.base.source[self.base.pos + ws];
            if (ch == ' ' or ch == '\t') {
                ws += 1;
            } else break;
        }
        // Scan past blank lines to find the first content line's indent
        var line_start = self.base.pos;
        while (line_start + ws < self.base.source.len) {
            const ch = self.base.source[line_start + ws];
            if (ch == '\n' or ch == '\r') {
                line_start = line_start + ws + 1;
                ws = 0;
                while (line_start + ws < self.base.source.len) {
                    const wc = self.base.source[line_start + ws];
                    if (wc == ' ' or wc == '\t') {
                        ws += 1;
                    } else break;
                }
                continue;
            }
            break;
        }
        const at_eof = line_start + ws >= self.base.source.len;
        if (!at_eof) {
            const next_ch = self.base.source[line_start + ws];
            if (next_ch == '#' and ws == self.indent_level) {
                return nl_tok;
            }
        }
        if (at_eof) {
            ws = 0;
        }

        if (ws > self.indent_level) {
            if (self.indent_depth >= 63)
                return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            self.indent_stack[self.indent_depth] = self.indent_level;
            self.indent_depth += 1;
            self.indent_level = ws;
            return Token{ .cat = .indent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        } else if (ws < self.indent_level) {
            var count: u8 = 0;
            var next_level = self.indent_level;
            while (next_level > ws) {
                if (self.indent_depth == 0)
                    return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                self.indent_depth -= 1;
                next_level = self.indent_stack[self.indent_depth];
                count += 1;
            }
            if (next_level != ws)
                return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            self.indent_level = ws;
            if (count > 0) {
                const needs_newline = !at_eof and !self.nextTokenIsElse();
                if (count > 1) {
                    self.indent_pending = count - 1;
                    self.indent_trailing_newline = needs_newline;
                } else if (needs_newline) {
                    self.indent_queued = Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                }
                return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            }
            return nl_tok;
        }
        return nl_tok;
    }

    fn nextTokenIsElse(self: *const Lexer) bool {
        var probe = self.base;
        const tok = probe.matchRules();
        return tok.cat == .ident and std.mem.eql(u8, self.base.source[tok.pos..][0..tok.len], "else");
    }

    fn hasElseOnLine(self: *const Lexer) bool {
        var probe = self.base;
        var depth: i32 = 0;
        while (true) {
            const tok = probe.matchRules();
            switch (tok.cat) {
                .newline, .eof => return false,
                .lparen => depth += 1,
                .rparen => depth -= 1,
                .lbracket => depth += 1,
                .rbracket => depth -= 1,
                .lbrace => depth += 1,
                .rbrace => depth -= 1,
                .ident => {
                    if (depth == 0 and tok.len == 4 and
                        std.mem.eql(u8, self.base.source[tok.pos..][0..4], "else"))
                        return true;
                },
                else => {},
            }
        }
    }

    fn isValueCat(cat: TokenCat) bool {
        return switch (cat) {
            .ident, .integer, .real, .string_sq, .string_dq,
            .true, .false, .rparen, .rbracket, .rbrace => true,
            else => false,
        };
    }

    fn isCapturePipe(self: *const Lexer) bool {
        var probe = self.base;
        const tok1 = probe.matchRules();
        if (tok1.cat != .ident) return false;
        const tok2 = probe.matchRules();
        return tok2.cat == .bar;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "keyword_as - core keywords" {
    try std.testing.expectEqual(keyword_id.FUN, keyword_as("fun").?);
    try std.testing.expectEqual(keyword_id.SUB, keyword_as("sub").?);
    try std.testing.expectEqual(keyword_id.USE, keyword_as("use").?);
    try std.testing.expectEqual(keyword_id.IF, keyword_as("if").?);
    try std.testing.expectEqual(keyword_id.ELSE, keyword_as("else").?);
    try std.testing.expectEqual(keyword_id.RETURN, keyword_as("return").?);
    try std.testing.expectEqual(keyword_id.TRUE, keyword_as("true").?);
    try std.testing.expectEqual(keyword_id.FALSE, keyword_as("false").?);
}

test "keyword_as - not a keyword" {
    try std.testing.expect(keyword_as("total") == null);
    try std.testing.expect(keyword_as("add") == null);
    try std.testing.expect(keyword_as("exists?") == null);
    try std.testing.expect(keyword_as("") == null);
}
