//! nexis language module — the `@lang = "nexis"` companion for
//! `nexis.grammar`.
//!
//! Responsibilities:
//!   - `Lexer` wrapper that fully replaces nexus's generated `BaseLexer`
//!     tokenization. The generated scanner is tailored to imperative-language
//!     conventions (hardcoded integer/keyword/ident shapes, no support for
//!     Clojure-style `-?[0-9]+` numbers, no char literals, no multi-char
//!     sharp-dispatch tokens beyond the ones listed in the operator switch).
//!     Overriding `Lexer` here is the clean fix: the parser continues to
//!     drive `self.lexer.next()` but our scanner produces exactly the token
//!     shapes §7.2 of PLAN.md and FORMS.md §2 demand.

const std = @import("std");
const parser = @import("parser.zig");

// =============================================================================
// Lexer — full hand-written replacement
// =============================================================================

const Token = parser.Token;
const TokenCat = parser.TokenCat;
const makeToken = parser.BaseLexer.makeToken;

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }

    pub fn next(self: *Lexer) Token {
        const src = self.base.source;

        // Skip whitespace (spaces, tabs, CR, LF, commas) and line comments.
        const ws_start: u32 = self.base.pos;
        while (true) {
            while (self.base.pos < src.len) : (self.base.pos += 1) {
                switch (src[self.base.pos]) {
                    ' ', '\t', '\r', '\n', ',' => {},
                    else => break,
                }
            }
            if (self.base.pos < src.len and src[self.base.pos] == ';') {
                while (self.base.pos < src.len and src[self.base.pos] != '\n') : (self.base.pos += 1) {}
                continue;
            }
            break;
        }
        const pre: u8 = @intCast(@min(self.base.pos - ws_start, 255));

        if (self.base.pos >= src.len) {
            return .{ .cat = .eof, .pre = pre, .pos = self.base.pos, .len = 0 };
        }

        const start = self.base.pos;
        const c = src[start];

        switch (c) {
            '(' => return self.single(.lparen, start, pre),
            ')' => return self.single(.rparen, start, pre),
            '[' => return self.single(.lbracket, start, pre),
            ']' => return self.single(.rbracket, start, pre),
            '{' => return self.single(.lbrace, start, pre),
            '}' => return self.single(.rbrace, start, pre),
            '\'' => return self.single(.quote_tok, start, pre),
            '`' => return self.single(.syntax_quote_tok, start, pre),
            '@' => return self.single(.deref_tok, start, pre),
            '^' => return self.single(.caret, start, pre),
            '~' => {
                if (start + 1 < src.len and src[start + 1] == '@') {
                    self.base.pos += 2;
                    return .{ .cat = .unquote_splicing_tok, .pre = pre, .pos = start, .len = 2 };
                }
                return self.single(.unquote_tok, start, pre);
            },
            '#' => {
                if (start + 1 < src.len) {
                    switch (src[start + 1]) {
                        '{' => {
                            self.base.pos += 2;
                            return .{ .cat = .hash_lbrace, .pre = pre, .pos = start, .len = 2 };
                        },
                        '(' => {
                            self.base.pos += 2;
                            return .{ .cat = .hash_lparen, .pre = pre, .pos = start, .len = 2 };
                        },
                        '_' => {
                            self.base.pos += 2;
                            return .{ .cat = .hash_discard, .pre = pre, .pos = start, .len = 2 };
                        },
                        else => {},
                    }
                }
                return self.single(.err, start, pre);
            },
            '"' => return self.scanString(start, pre),
            '\\' => return self.scanChar(start, pre),
            ':' => return self.scanKeyword(start, pre),
            '0'...'9' => return self.scanNumber(start, pre, false),
            '-' => {
                // `-` followed by digit begins a negative number.
                if (start + 1 < src.len and isAsciiDigit(src[start + 1])) {
                    return self.scanNumber(start, pre, true);
                }
                return self.scanIdent(start, pre);
            },
            else => {
                if (isIdentStart(c)) return self.scanIdent(start, pre);
                return self.single(.err, start, pre);
            },
        }
    }

    inline fn single(self: *Lexer, cat: TokenCat, start: u32, pre: u8) Token {
        self.base.pos = start + 1;
        return .{ .cat = cat, .pre = pre, .pos = start, .len = 1 };
    }

    inline fn isAsciiDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    inline fn isHexDigit(c: u8) bool {
        return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
    }

    inline fn isBinDigit(c: u8) bool {
        return c == '0' or c == '1';
    }

    /// Clojure-style symbol start: letters, underscore, and the accepted
    /// symbolic chars. `-` is handled at the dispatch level so we can
    /// disambiguate negative numbers.
    inline fn isIdentStart(c: u8) bool {
        return switch (c) {
            'a'...'z', 'A'...'Z', '_', '!', '$', '%', '&', '*', '+', '.', '/', '<', '=', '>', '?' => true,
            else => false,
        };
    }

    inline fn isIdentCont(c: u8) bool {
        return switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '!', '$', '%', '&', '*', '+', '-', '.', '/', ':', '<', '=', '>', '?', '\'', '#' => true,
            else => false,
        };
    }

    fn scanString(self: *Lexer, start: u32, pre: u8) Token {
        const src = self.base.source;
        // start points at the opening '"'.
        self.base.pos = start + 1;
        while (self.base.pos < src.len) {
            const ch = src[self.base.pos];
            if (ch == '"') {
                self.base.pos += 1;
                return makeToken(.string, pre, start, self.base.pos);
            }
            if (ch == '\\') {
                // Accept any next byte; detailed escape validation is the
                // reader's job.
                self.base.pos += @min(2, src.len - self.base.pos);
                continue;
            }
            if (ch == '\n') break; // no multi-line strings (PLAN §7.2).
            self.base.pos += 1;
        }
        return makeToken(.err, pre, start, self.base.pos);
    }

    fn scanChar(self: *Lexer, start: u32, pre: u8) Token {
        const src = self.base.source;
        // start points at '\\'. A char literal needs at least one char after.
        self.base.pos = start + 1;
        if (self.base.pos >= src.len) {
            return .{ .cat = .err, .pre = pre, .pos = start, .len = 1 };
        }

        // `\u{HEX}` — unicode scalar.
        if (src[self.base.pos] == 'u' and self.base.pos + 1 < src.len and src[self.base.pos + 1] == '{') {
            self.base.pos += 2;
            while (self.base.pos < src.len and isHexDigit(src[self.base.pos])) : (self.base.pos += 1) {}
            if (self.base.pos < src.len and src[self.base.pos] == '}') {
                self.base.pos += 1;
                return makeToken(.char, pre, start, self.base.pos);
            }
            return makeToken(.err, pre, start, self.base.pos);
        }

        // `\name` — named character (alpha run). `\a` and friends fall out of
        // this path because a single alpha run of length 1 is still valid.
        if (isNamedCharStart(src[self.base.pos])) {
            self.base.pos += 1;
            while (self.base.pos < src.len and isAlpha(src[self.base.pos])) : (self.base.pos += 1) {}
            return makeToken(.char, pre, start, self.base.pos);
        }

        // `\<any>` — any single literal character (incl. punctuation).
        self.base.pos += 1;
        return makeToken(.char, pre, start, self.base.pos);
    }

    inline fn isNamedCharStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    inline fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    fn scanKeyword(self: *Lexer, start: u32, pre: u8) Token {
        const src = self.base.source;
        // start points at ':'. Accept any of the symbolic start chars; `-`
        // is admissible here even though the top-level dispatch excludes it
        // (the top level reserves `-` for negative numbers). After `:`
        // there is no negative-number ambiguity, so `:-foo` is just a
        // keyword whose body starts with `-` — matching Clojure.
        self.base.pos = start + 1;
        if (self.base.pos >= src.len) {
            return .{ .cat = .err, .pre = pre, .pos = start, .len = 1 };
        }
        const first = src[self.base.pos];
        if (!isIdentStart(first) and first != '-') {
            return .{ .cat = .err, .pre = pre, .pos = start, .len = 1 };
        }
        while (self.base.pos < src.len and isIdentCont(src[self.base.pos])) : (self.base.pos += 1) {}
        return makeToken(.keyword, pre, start, self.base.pos);
    }

    fn scanIdent(self: *Lexer, start: u32, pre: u8) Token {
        const src = self.base.source;
        self.base.pos = start + 1;
        while (self.base.pos < src.len and isIdentCont(src[self.base.pos])) : (self.base.pos += 1) {}
        return makeToken(.ident, pre, start, self.base.pos);
    }

    fn scanNumber(self: *Lexer, start: u32, pre: u8, has_minus: bool) Token {
        const src = self.base.source;
        self.base.pos = if (has_minus) start + 1 else start;

        // Hex `0x...` / binary `0b...`.
        if (self.base.pos + 1 < src.len and src[self.base.pos] == '0') {
            const d = src[self.base.pos + 1];
            if (d == 'x' or d == 'X') {
                self.base.pos += 2;
                const hex_body = self.base.pos;
                while (self.base.pos < src.len and isHexDigit(src[self.base.pos])) : (self.base.pos += 1) {}
                if (self.base.pos == hex_body) {
                    return makeToken(.err, pre, start, self.base.pos);
                }
                return makeToken(.integer, pre, start, self.base.pos);
            }
            if (d == 'b' or d == 'B') {
                self.base.pos += 2;
                const bin_body = self.base.pos;
                while (self.base.pos < src.len and isBinDigit(src[self.base.pos])) : (self.base.pos += 1) {}
                if (self.base.pos == bin_body) {
                    return makeToken(.err, pre, start, self.base.pos);
                }
                return makeToken(.integer, pre, start, self.base.pos);
            }
        }

        // Decimal integer / real.
        while (self.base.pos < src.len and isAsciiDigit(src[self.base.pos])) : (self.base.pos += 1) {}
        var is_real = false;
        if (self.base.pos < src.len and src[self.base.pos] == '.') {
            const after = self.base.pos + 1;
            if (after < src.len and isAsciiDigit(src[after])) {
                is_real = true;
                self.base.pos = after;
                while (self.base.pos < src.len and isAsciiDigit(src[self.base.pos])) : (self.base.pos += 1) {}
            }
        }
        if (self.base.pos < src.len and (src[self.base.pos] == 'e' or src[self.base.pos] == 'E')) {
            var pp = self.base.pos + 1;
            if (pp < src.len and (src[pp] == '+' or src[pp] == '-')) pp += 1;
            if (pp < src.len and isAsciiDigit(src[pp])) {
                is_real = true;
                self.base.pos = pp + 1;
                while (self.base.pos < src.len and isAsciiDigit(src[self.base.pos])) : (self.base.pos += 1) {}
            }
        }
        return makeToken(if (is_real) .real else .integer, pre, start, self.base.pos);
    }
};

test "an identifier or string longer than a token can hold is an err token" {
    const source = try std.testing.allocator.alloc(u8, 65536 + 1 + 65538);
    defer std.testing.allocator.free(source);
    const ident = source[0..65536];
    const string = source[65537..];
    @memset(ident, 'a');
    source[65536] = ' ';
    string[0] = '"';
    @memset(string[1 .. string.len - 1], 'b');
    string[string.len - 1] = '"';
    var lx = Lexer.init(source);
    for ([_]u32{ 0, 65537 }) |pos| {
        const tok = lx.next();
        try std.testing.expectEqual(TokenCat.err, tok.cat);
        try std.testing.expectEqual(pos, tok.pos);
        try std.testing.expectEqual(std.math.maxInt(u16), tok.len);
    }
    try std.testing.expectEqual(TokenCat.eof, lx.next().cat);
}
