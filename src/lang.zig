// lang.zig — Language module for the Nexus grammar DSL self-hosting parser
//
// Imported by the generated parser (parser.zig). Provides:
//   - Tag enum for S-expression node types
//   - Custom Lexer wrapper with three responsibilities:
//     1. Unicode arrow scanning (→ and ←)
//     2. Keyword reclassification (directive keywords after @, associativity always)
//     3. Action text capture (opaque rest-of-line after → outside brackets)

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;
const TokenCat = parser.TokenCat;

// Tag enum mirrors the canonical S-expression schema documented at the top of
// nexus.grammar. Every variant here corresponds to a tagged sexp the generated
// parser emits; the strict lowerer in nexus.zig consumes exactly this set.
pub const Tag = enum(u8) {
    grammar,

    // Directives
    lang,
    conflicts,
    code,
    as,
    as_strict,
    as_perm,
    op,
    op_map,
    errors,
    error_name,
    infix,
    level,
    infix_op,

    // Rules and alternatives
    rule,
    start,
    name,
    alt,
    alt_reduce,
    alt_shift,

    // Elements
    ref,
    tok,
    lit,
    at_ref,
    list_req,
    list_opt,
    group,
    group_many,
    group_opt,
    quantified,
    skip,
    skip_q,

    // List-inner shapes
    plain,
    opt_items,
    sep_items,
    opt_items_nosep,

    // Quantifiers
    opt,
    zero_plus,
    one_plus,
};

pub const Lexer = struct {
    base: BaseLexer,
    mode: Mode = .normal,
    afterAt: bool = false,
    bracketDepth: u16 = 0,

    const Mode = enum { normal, captureAction };

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
        if (self.mode == .captureAction) return self.scanActionText();

        const ws = self.skipWhitespace();

        if (self.scanUnicodeArrow(ws)) |tok| return self.emit(tok);

        self.base.pos = self.base.pos - @as(u32, @intCast(ws.count));
        var tok = self.base.matchRules();

        if (tok.cat == .@"ident") tok.cat = self.classifyIdent(tok);
        if (tok.cat == .@"lbracket") self.bracketDepth += 1;
        if (tok.cat == .@"rbracket" and self.bracketDepth > 0) self.bracketDepth -= 1;
        if (tok.cat == .@"arrow" and self.bracketDepth == 0) self.mode = .captureAction;

        return self.emit(tok);
    }

    // --- Action text capture (opaque island: everything after → to end of line) ---

    fn scanActionText(self: *Lexer) Token {
        self.mode = .normal;
        while (self.base.pos < self.base.source.len and
            (self.base.source[self.base.pos] == ' ' or self.base.source[self.base.pos] == '\t'))
        {
            self.base.pos += 1;
        }
        const start = self.base.pos;
        while (self.base.pos < self.base.source.len and self.base.source[self.base.pos] != '\n') {
            self.base.pos += 1;
        }
        var end = self.base.pos;
        while (end > start and (self.base.source[end - 1] == ' ' or self.base.source[end - 1] == '\t')) {
            end -= 1;
        }
        if (end > start) {
            self.afterAt = false;
            return Token{ .cat = .@"action_text", .pre = 0, .pos = start, .len = @intCast(end - start) };
        }
        return self.next();
    }

    // --- Unicode arrow scanning (→ U+2192, ← U+2190) ---

    const Whitespace = struct { start: u32, count: usize };

    fn skipWhitespace(self: *Lexer) Whitespace {
        const start = self.base.pos;
        while (self.base.pos < self.base.source.len) {
            const ch = self.base.source[self.base.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r') self.base.pos += 1 else break;
        }
        return .{ .start = start, .count = self.base.pos - start };
    }

    fn scanUnicodeArrow(self: *Lexer, ws: Whitespace) ?Token {
        if (self.base.pos + 2 >= self.base.source.len) return null;
        const s = self.base.source;
        if (s[self.base.pos] != 0xE2 or s[self.base.pos + 1] != 0x86) return null;
        const start = self.base.pos;
        const pre: u8 = @intCast(@min(ws.count, 255));
        return switch (s[self.base.pos + 2]) {
            0x92 => blk: { // → rightwards arrow
                self.base.pos += 3;
                if (self.bracketDepth == 0) self.mode = .captureAction;
                break :blk Token{ .cat = .@"arrow", .pre = pre, .pos = start, .len = 3 };
            },
            0x90 => blk: { // ← leftwards arrow
                self.base.pos += 3;
                break :blk Token{ .cat = .@"larrow", .pre = pre, .pos = start, .len = 3 };
            },
            else => null,
        };
    }

    // --- Keyword classification ---

    fn classifyIdent(self: *Lexer, tok: Token) TokenCat {
        const t = self.base.source[tok.pos..][0..tok.len];
        if (t.len > 0 and t[0] >= 'A' and t[0] <= 'Z') return .@"token";
        return classify(t, self.afterAt);
    }

    fn classify(t: []const u8, afterAt: bool) TokenCat {
        if (t.len < 2 or t.len > 9) return .@"ident";
        return switch (t[0]) {
            'a' => if (afterAt and eql(t, "as")) .@"kw_as" else .@"ident",
            'c' => if (afterAt and eql(t, "code")) .@"kw_code" else if (afterAt and eql(t, "conflicts")) .@"kw_conflicts" else .@"ident",
            'e' => if (afterAt and eql(t, "errors")) .@"kw_errors" else .@"ident",
            'i' => if (afterAt and eql(t, "infix")) .@"kw_infix" else .@"ident",
            'l' => if (eql(t, "left")) .@"kw_left" else if (afterAt and eql(t, "lang")) .@"kw_lang" else .@"ident",
            'n' => if (eql(t, "none")) .@"kw_none" else .@"ident",
            'o' => if (afterAt and eql(t, "op")) .@"kw_op" else .@"ident",
            'r' => if (eql(t, "right")) .@"kw_right" else .@"ident",
            's' => if (afterAt and eql(t, "skip")) .@"kw_skip" else .@"ident",
            else => .@"ident",
        };
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    // --- State tracking ---

    fn emit(self: *Lexer, tok: Token) Token {
        self.afterAt = (tok.cat == .@"at");
        return tok;
    }
};
