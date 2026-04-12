// lang.zig — Language module for the Nexus grammar DSL self-hosting parser
//
// This module is imported by the generated parser (parser.zig).
// It provides the Tag enum and a custom Lexer wrapper that handles:
//   - Unicode arrow characters (→ and ←)
//   - Keyword reclassification (lang, conflicts, etc.)

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;
const TokenCat = parser.TokenCat;

pub const Tag = enum(u8) {
    grammar,
    lang,
    conflicts,
    as,
    op,
    op_map,
    code,
    errors,
    error_name,
    infix,
    infix_op,
    rule,
    start,
    name,
    alt,
    alt_reduce,
    alt_shift,
    quantified,
    skip,
    skip_q,
    ref,
    tok,
    lit,
    at_ref,
    group,
    list,
    opt_list,
    optional,
    opt_items,
    sep_items,
    opt_items_nosep,
    opt,
    zero_plus,
    one_plus,
};

pub const Lexer = struct {
    base: BaseLexer,
    lastCat: TokenCat = .newline,
    captureAction: bool = false,
    bracketDepth: u16 = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }

    pub fn next(self: *Lexer) Token {
        // After ARROW, capture the rest of the line as ACTION_TEXT
        if (self.captureAction) {
            self.captureAction = false;
            // Skip leading whitespace
            while (self.base.pos < self.base.source.len) {
                const ch = self.base.source[self.base.pos];
                if (ch == ' ' or ch == '\t') {
                    self.base.pos += 1;
                } else break;
            }
            const start = self.base.pos;
            // Capture to end of line, trimming trailing whitespace
            while (self.base.pos < self.base.source.len and self.base.source[self.base.pos] != '\n') {
                self.base.pos += 1;
            }
            var end = self.base.pos;
            while (end > start and (self.base.source[end - 1] == ' ' or self.base.source[end - 1] == '\t')) {
                end -= 1;
            }
            if (end > start) {
                self.lastCat = .@"action_text";
                return Token{ .cat = .@"action_text", .pre = 0, .pos = start, .len = @intCast(end - start) };
            }
        }

        // Check for UTF-8 arrows before falling back to base lexer
        const wsStart = self.base.pos;
        while (self.base.pos < self.base.source.len) {
            const ch = self.base.source[self.base.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r') {
                self.base.pos += 1;
            } else break;
        }
        const wsCount: u8 = @intCast(@min(self.base.pos - wsStart, 255));

        if (self.base.pos + 2 < self.base.source.len) {
            const b0 = self.base.source[self.base.pos];
            const b1 = self.base.source[self.base.pos + 1];
            const b2 = self.base.source[self.base.pos + 2];

            if (b0 == 0xE2 and b1 == 0x86) {
                const start = self.base.pos;
                if (b2 == 0x92) {
                    self.base.pos += 3;
                    if (self.bracketDepth == 0) self.captureAction = true;
                    self.lastCat = .@"arrow";
                    return Token{ .cat = .@"arrow", .pre = wsCount, .pos = start, .len = 3 };
                }
                if (b2 == 0x90) {
                    self.base.pos += 3;
                    self.lastCat = .@"larrow";
                    return Token{ .cat = .@"larrow", .pre = wsCount, .pos = start, .len = 3 };
                }
            }
        }

        // Reset position for base lexer (it handles its own whitespace)
        self.base.pos = wsStart;
        var tok = self.base.matchRules();

        // Reclassify idents: uppercase → token; keywords after @; assoc always
        if (tok.cat == .@"ident") {
            const t = self.base.source[tok.pos..][0..tok.len];
            if (t.len > 0 and t[0] >= 'A' and t[0] <= 'Z') {
                tok.cat = .@"token";
            } else if (self.lastCat == .@"at") {
                tok.cat = classifyKeyword(t);
            } else {
                tok.cat = classifyAlways(t);
            }
        }

        // Track bracket depth for context
        if (tok.cat == .@"lbracket") self.bracketDepth += 1;
        if (tok.cat == .@"rbracket" and self.bracketDepth > 0) self.bracketDepth -= 1;

        // After ARROW in a production (not inside brackets), capture action text
        if (tok.cat == .@"arrow" and self.bracketDepth == 0) {
            self.captureAction = true;
        }

        self.lastCat = tok.cat;
        return tok;
    }

    fn classifyAlways(t: []const u8) TokenCat {
        if (t.len < 4 or t.len > 5) return .@"ident";
        return switch (t[0]) {
            'l' => if (eql(t, "left")) .@"kw_left" else .@"ident",
            'r' => if (eql(t, "right")) .@"kw_right" else .@"ident",
            'n' => if (eql(t, "none")) .@"kw_none" else .@"ident",
            else => .@"ident",
        };
    }

    fn classifyKeyword(t: []const u8) TokenCat {
        if (t.len < 2 or t.len > 9) return .@"ident";
        return switch (t[0]) {
            'a' => if (eql(t, "as")) .@"kw_as" else .@"ident",
            'c' => if (eql(t, "code")) .@"kw_code" else if (eql(t, "conflicts")) .@"kw_conflicts" else .@"ident",
            'e' => if (eql(t, "errors")) .@"kw_errors" else .@"ident",
            'i' => if (eql(t, "infix")) .@"kw_infix" else .@"ident",
            'l' => if (eql(t, "lang")) .@"kw_lang" else if (eql(t, "left")) .@"kw_left" else .@"ident",
            'n' => if (eql(t, "none")) .@"kw_none" else .@"ident",
            'o' => if (eql(t, "op")) .@"kw_op" else .@"ident",
            'r' => if (eql(t, "right")) .@"kw_right" else .@"ident",
            's' => if (eql(t, "skip")) .@"kw_skip" else .@"ident",
            else => .@"ident",
        };
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};
