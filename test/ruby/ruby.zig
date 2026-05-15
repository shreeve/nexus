//! Ruby — Language module for the Nanoruby grammar
//!
//! Provides language-specific support for the generated parser:
//!   - Tag enum for S-expression node types
//!   - Keyword matching (KeywordId, keywordAs)
//!   - Lexer wrapper with context-sensitive token rewriting
//!
//! Imported by parser.zig via @lang = "ruby" directive.

const std = @import("std");
const parser = @import("parser.zig");
pub const Token = parser.Token;
pub const TokenCat = parser.TokenCat;
const BaseLexer = parser.BaseLexer;

// =============================================================================
// Tag Enum — semantic node types for S-expression output
// =============================================================================

pub const Tag = enum(u8) {
    // Program structure
    program,
    stmts,

    // Control flow
    @"if",
    unless,
    @"while",
    until,
    @"for",
    case,
    when,
    begin,
    rescue,
    ensure,

    // Definitions
    alias,
    undef,
    def,
    defs,
    class,
    sclass,
    module,
    params,
    optarg,
    kwarg,
    kwoptarg,
    restarg,
    kwrestarg,
    blockarg,

    // Lambda
    lambda,

    // Method calls
    send,
    csend,
    index,
    scope,
    block,
    super,
    yield,

    // Assignment
    masgn,
    mlhs,
    mrhs,
    assign,
    attrasgn,
    indexasgn,
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"**=",
    @"|=",
    @"&=",
    @"^=",
    @"<<=",
    @">>=",
    @"||=",
    @"&&=",

    // String interpolation
    dstr,
    evstr,

    // Data structures
    array,
    hash,
    pair,
    splat,
    kwsplat,
    block_pass,
    args,

    // Keyword operators
    not,
    @"or",
    @"and",
    defined,

    // Flow statements
    @"return",
    @"break",
    next,
    retry,
    redo,

    // Literals
    @"true",
    @"false",
    nil,
    self,
    @"__FILE__",
    @"__LINE__",
    @"__ENCODING__",

    // Binary operators (from @infix, auto-generated tags)
    @"||",
    @"&&",
    @"..",
    @"...",
    @"==",
    @"!=",
    @"===",
    @"<=>",
    @"=~",
    @"!~",
    @">",
    @">=",
    @"<",
    @"<=",
    @"|",
    @"^",
    @"&",
    @"<<",
    @">>",
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"**",

    // Unary operators
    @"u-",
    @"u+",
    @"!",
    @"~",

    _,
};

// =============================================================================
// Keyword Lookup — maps identifier text to parser symbol IDs
// =============================================================================

pub const KeywordId = enum(u16) {
    // Keywords
    IF,
    UNLESS,
    ELSIF,
    ELSE,
    END,
    WHILE,
    UNTIL,
    FOR,
    IN,
    DO,
    CASE,
    WHEN,
    DEF,
    CLASS,
    MODULE,
    RETURN,
    BREAK,
    NEXT,
    YIELD,
    BEGIN_KW,
    RESCUE,
    ENSURE,
    THEN,
    AND_KW,
    OR_KW,
    NOT_KW,
    DEFINED,
    ALIAS,
    UNDEF,
    RETRY,
    REDO,
    SUPER,
    SELF,
    TRUE,
    FALSE,
    NIL,
    KW__FILE__,
    KW__LINE__,
    KW__ENCODING__,

    // Rewriter-classified keyword variants
    IF_MOD,
    UNLESS_MOD,
    WHILE_MOD,
    UNTIL_MOD,
    RESCUE_MOD,
    DO_BLOCK,
    DO_COND,

    // Token categories (parser needs these as symbols)
    IDENT,
    CONSTANT,
    IVAR,
    CVAR,
    GVAR,
    INTEGER,
    FLOAT,
    RATIONAL,
    IMAGINARY,
    STRING_SQ,
    STRING_DQ,
    SYMBOL,
    PCT_W,
    PCT_I,
    LABEL,
    CMD_IDENT,
    LBRACE_BLOCK,
    PLUS_U,
    MINUS_U,
    STAR_SPLAT,
    AMP_BLOCK,
    DSTR_BEG,
    STR_CONTENT,
    EMBEXPR_BEG,
    EMBEXPR_END,
    DSTR_END,
    NEWLINE,
    COMMENT,
    EOF,
};

const keywordMap = std.StaticStringMap(KeywordId).initComptime(.{
    .{ "if", .IF },
    .{ "unless", .UNLESS },
    .{ "elsif", .ELSIF },
    .{ "else", .ELSE },
    .{ "end", .END },
    .{ "while", .WHILE },
    .{ "until", .UNTIL },
    .{ "for", .FOR },
    .{ "in", .IN },
    .{ "do", .DO },
    .{ "case", .CASE },
    .{ "when", .WHEN },
    .{ "def", .DEF },
    .{ "class", .CLASS },
    .{ "module", .MODULE },
    .{ "return", .RETURN },
    .{ "break", .BREAK },
    .{ "next", .NEXT },
    .{ "yield", .YIELD },
    .{ "begin", .BEGIN_KW },
    .{ "rescue", .RESCUE },
    .{ "ensure", .ENSURE },
    .{ "then", .THEN },
    .{ "and", .AND_KW },
    .{ "or", .OR_KW },
    .{ "not", .NOT_KW },
    .{ "defined?", .DEFINED },
    .{ "alias", .ALIAS },
    .{ "undef", .UNDEF },
    .{ "retry", .RETRY },
    .{ "redo", .REDO },
    .{ "super", .SUPER },
    .{ "self", .SELF },
    .{ "true", .TRUE },
    .{ "false", .FALSE },
    .{ "nil", .NIL },
    .{ "__FILE__", .KW__FILE__ },
    .{ "__LINE__", .KW__LINE__ },
    .{ "__ENCODING__", .KW__ENCODING__ },
});

pub fn keywordAs(name: []const u8) ?KeywordId {
    return keywordMap.get(name);
}

// =============================================================================
// Lexer — context-sensitive rewriter wrapping the generated BaseLexer
//
// The rewriter sits between the generated lexer and the parser. It sees
// every token and reclassifies based on context that the grammar alone
// cannot express in SLR(1).
//
// Responsibilities:
//   1. Skip comments
//   2. Suppress / deduplicate newlines
//   3. Classify +/- as unary or binary
//   4. Classify */& as splat/block-pass or binary
//   5. Classify { as hash literal or block
//   6. Fuse ident+: into label tokens
//   7. Fuse :+ident into symbol tokens
//   8. Classify if/unless/while/until/rescue as head or modifier
//   9. Classify do as block or loop-condition
//  10. Classify bare identifiers as command calls
// =============================================================================

const HeadKind = enum {
    none,
    if_head,
    elsif_head,
    unless_head,
    while_head,
    until_head,
    for_vars,
    for_expr,
    when_head,
    case_head,
    rescue_head,
};

pub const Lexer = struct {
    base: BaseLexer,
    last_cat: TokenCat = .eof,
    cmd_context: bool = true,
    cond_depth: u8 = 0,
    head_kind: HeadKind = .none,

    // String interpolation state
    interp_queue: [64]Token = undefined,
    interp_count: u8 = 0,
    interp_pos: u8 = 0,
    interp_active: bool = false,
    interp_brace_depth: u8 = 0,
    interp_saved_pos: u32 = 0,
    interp_str_end: u32 = 0,
    interp_scan: u32 = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
        self.last_cat = .eof;
        self.cmd_context = true;
        self.cond_depth = 0;
        self.head_kind = .none;
        self.interp_count = 0;
        self.interp_pos = 0;
        self.interp_active = false;
        self.interp_brace_depth = 0;
    }

    pub fn next(self: *Lexer) Token {
        // ── Drain interpolation queue if active ─────────────────
        if (self.interp_pos < self.interp_count) {
            const tok = self.interp_queue[self.interp_pos];
            self.interp_pos += 1;
            if (self.interp_pos >= self.interp_count) {
                self.interp_count = 0;
                self.interp_pos = 0;
            }
            self.last_cat = tok.cat;
            return tok;
        }

        // ── Resume scanning string body after embedded expr ─────
        if (self.interp_active) {
            return self.scanStringBody();
        }

        while (true) {
            var tok = self.base.matchRules();

            // ── 0a. Float extension ─────────────────────────────────
            // BaseLexer.scanNumber is hand-rolled and only emits
            // `.integer` — so we post-process here: if the integer is
            // followed by `.digit(s)` or an exponent marker, consume
            // those and re-emit as `.float`. Keeps the generated
            // lexer regen-safe (Nexus overwrites parser.zig on
            // regeneration; this lives in the hand-maintained
            // companion).
            if (tok.cat == .integer) {
                if (self.tryExtendFloat(&tok)) {
                    self.last_cat = .float;
                    return tok;
                }
            }

            // ── 0b. %w[…] / %i[…] array literals ────────────────────
            // The grammar defines the `pct_w` / `pct_i` token cats and
            // uses them in `primary`, but the base lexer's hand-rolled
            // matchRules doesn't scan their bodies. Detect the `%w` /
            // `%i` prefix in a `.percent` token's position and
            // synthesize the full literal.
            if (tok.cat == .percent) {
                if (self.tryScanPctArray(&tok)) |pct_tok| {
                    self.last_cat = pct_tok.cat;
                    return pct_tok;
                }
            }

            // ── 1. Skip comments ────────────────────────────────────
            if (tok.cat == .comment) continue;

            // ── 2. Newline handling ─────────────────────────────────
            if (tok.cat == .newline) {
                if (self.base.paren > 0 or self.base.brack > 0 or self.base.brace > 0)
                    continue;

                if (isContinuation(self.last_cat))
                    continue;

                if (self.last_cat == .newline or self.last_cat == .eof)
                    continue;

                // Head-separator: newline terminates a control-flow head
                if (self.tryHeadSep(&tok)) |sep_tok| return sep_tok;

                self.last_cat = .newline;
                self.cmd_context = true;
                return tok;
            }

            // ── EOF ─────────────────────────────────────────────────
            if (tok.cat == .eof) {
                self.last_cat = .eof;
                return tok;
            }

            // ── 2b. Semicolon head-separator check ──────────────────
            if (tok.cat == .semicolon) {
                if (self.tryHeadSep(&tok)) |sep_tok| return sep_tok;
                self.last_cat = .semicolon;
                self.cmd_context = true;
                return tok;
            }

            // ── 3. Unary +/- classification ─────────────────────────
            if (tok.cat == .plus and !canEndExpr(self.last_cat)) {
                tok.cat = .plus_u;
                self.last_cat = .plus_u;
                return tok;
            }
            if (tok.cat == .minus and !canEndExpr(self.last_cat)) {
                tok.cat = .minus_u;
                self.last_cat = .minus_u;
                return tok;
            }

            // ── 4. Splat * and block-pass & classification ──────────
            if (tok.cat == .star and isSplatContext(self.last_cat)) {
                tok.cat = .star_splat;
                self.last_cat = .star_splat;
                return tok;
            }
            if (tok.cat == .ampersand and isSplatContext(self.last_cat)) {
                tok.cat = .amp_block;
                self.last_cat = .amp_block;
                return tok;
            }

            // ── 5. { classification (hash vs block) ─────────────────
            if (tok.cat == .lbrace) {
                if (canEndExpr(self.last_cat)) {
                    tok.cat = .lbrace_block;
                    self.last_cat = .lbrace_block;
                    return tok;
                }
                self.last_cat = .lbrace;
                return tok;
            }

            // ── 6. Label fusion: ident immediately followed by : ────
            if (tok.cat == .ident) {
                const ident_end = tok.pos + tok.len;
                if (ident_end < self.base.source.len and
                    self.base.source[ident_end] == ':' and
                    (ident_end + 1 >= self.base.source.len or self.base.source[ident_end + 1] != ':'))
                {
                    const after_colon = ident_end + 1;
                    const next_is_space = after_colon >= self.base.source.len or
                        self.base.source[after_colon] == ' ' or
                        self.base.source[after_colon] == '\t' or
                        self.base.source[after_colon] == '\n' or
                        self.base.source[after_colon] == '\r';
                    if (next_is_space and isLabelContext(self.last_cat)) {
                        self.base.pos = after_colon;
                        tok.cat = .label;
                        self.last_cat = .label;
                        self.cmd_context = false;
                        return tok;
                    }
                }
            }

            // ── 7. Symbol fusion: : immediately followed by ident ───
            if (tok.cat == .colon and !canEndExpr(self.last_cat)) {
                if (self.base.pos < self.base.source.len) {
                    const ch = self.base.source[self.base.pos];
                    if (std.ascii.isAlphabetic(ch) or ch == '_') {
                        var sym_end: u32 = self.base.pos;
                        while (sym_end < self.base.source.len and
                            (std.ascii.isAlphanumeric(self.base.source[sym_end]) or
                            self.base.source[sym_end] == '_'))
                        {
                            sym_end += 1;
                        }
                        if (sym_end < self.base.source.len and
                            (self.base.source[sym_end] == '?' or self.base.source[sym_end] == '!'))
                        {
                            sym_end += 1;
                        }
                        tok.cat = .symbol;
                        tok.len = @intCast(sym_end - tok.pos);
                        self.base.pos = sym_end;
                        self.last_cat = .symbol;
                        self.cmd_context = false;
                        return tok;
                    }
                    if (ch == '\'' or ch == '"') {
                        const str_tok = self.base.matchRules();
                        if (str_tok.cat == .string_sq or str_tok.cat == .string_dq) {
                            tok.cat = .symbol;
                            tok.len = @intCast(str_tok.pos + str_tok.len - tok.pos);
                            self.last_cat = .symbol;
                            self.cmd_context = false;
                            return tok;
                        }
                    }
                }
            }

            // ── String interpolation: split string_dq if it has #{
            if (tok.cat == .string_dq) {
                if (self.hasInterpolation(tok)) {
                    return self.startInterpolation(tok);
                }
                self.last_cat = .string_dq;
                self.cmd_context = false;
                return tok;
            }

            // ── 8. Keyword reclassification ─────────────────────────
            if (tok.cat == .ident) {
                const kw_text = self.base.source[tok.pos..][0..tok.len];

                // Modifier keywords: if/unless/while/until/rescue after expr
                if (canEndExpr(self.last_cat)) {
                    if (std.mem.eql(u8, kw_text, "if")) {
                        tok.cat = .if_mod;
                        self.last_cat = .if_mod;
                        self.cmd_context = false;
                        return tok;
                    }
                    if (std.mem.eql(u8, kw_text, "unless")) {
                        tok.cat = .unless_mod;
                        self.last_cat = .unless_mod;
                        self.cmd_context = false;
                        return tok;
                    }
                    if (std.mem.eql(u8, kw_text, "while")) {
                        tok.cat = .while_mod;
                        self.last_cat = .while_mod;
                        self.cmd_context = false;
                        return tok;
                    }
                    if (std.mem.eql(u8, kw_text, "until")) {
                        tok.cat = .until_mod;
                        self.last_cat = .until_mod;
                        self.cmd_context = false;
                        return tok;
                    }
                    if (std.mem.eql(u8, kw_text, "rescue")) {
                        tok.cat = .rescue_mod;
                        self.last_cat = .rescue_mod;
                        self.cmd_context = false;
                        return tok;
                    }
                }

                // `then` in head mode => THEN_SEP
                if (std.mem.eql(u8, kw_text, "then")) {
                    if (self.head_kind == .if_head or
                        self.head_kind == .elsif_head or
                        self.head_kind == .unless_head or
                        self.head_kind == .when_head or
                        self.head_kind == .case_head or
                        self.head_kind == .rescue_head)
                    {
                        self.head_kind = .none;
                        tok.cat = .then_sep;
                        self.last_cat = .then_sep;
                        self.cmd_context = true;
                        return tok;
                    }
                    self.cmd_context = true;
                    self.last_cat = tok.cat;
                    return tok;
                }

                // `do` in head mode => DO_SEP; else do_cond/do_block classification
                if (std.mem.eql(u8, kw_text, "do")) {
                    if (self.head_kind == .while_head or
                        self.head_kind == .until_head or
                        self.head_kind == .for_expr)
                    {
                        self.head_kind = .none;
                        if (self.cond_depth > 0) self.cond_depth -= 1;
                        tok.cat = .do_sep;
                        self.last_cat = .do_sep;
                        self.cmd_context = true;
                        return tok;
                    }
                    if (self.cond_depth > 0) {
                        self.cond_depth -= 1;
                        tok.cat = .do_cond;
                        self.last_cat = .do_cond;
                        self.cmd_context = true;
                        return tok;
                    }
                    if (canEndExpr(self.last_cat)) {
                        tok.cat = .do_block;
                        self.last_cat = .do_block;
                        self.cmd_context = true;
                        return tok;
                    }
                }

                // `in` transitions for_vars => for_expr
                if (std.mem.eql(u8, kw_text, "in")) {
                    if (self.head_kind == .for_vars) {
                        self.head_kind = .for_expr;
                    }
                    self.cmd_context = true;
                    self.last_cat = tok.cat;
                    return tok;
                }

                // Enter head mode for statement-form keywords
                if (!canEndExpr(self.last_cat)) {
                    if (std.mem.eql(u8, kw_text, "if")) {
                        self.head_kind = .if_head;
                    } else if (std.mem.eql(u8, kw_text, "unless")) {
                        self.head_kind = .unless_head;
                    } else if (std.mem.eql(u8, kw_text, "while")) {
                        self.head_kind = .while_head;
                        self.cond_depth += 1;
                    } else if (std.mem.eql(u8, kw_text, "until")) {
                        self.head_kind = .until_head;
                        self.cond_depth += 1;
                    } else if (std.mem.eql(u8, kw_text, "for")) {
                        self.head_kind = .for_vars;
                        self.cond_depth += 1;
                    } else if (std.mem.eql(u8, kw_text, "case")) {
                        self.head_kind = .case_head;
                    }
                }

                // `elsif` always enters head mode
                if (std.mem.eql(u8, kw_text, "elsif")) {
                    self.head_kind = .elsif_head;
                }

                // `when` enters head mode
                if (std.mem.eql(u8, kw_text, "when")) {
                    self.head_kind = .when_head;
                }

                // `rescue` (non-modifier) enters head mode
                if (std.mem.eql(u8, kw_text, "rescue") and !canEndExpr(self.last_cat)) {
                    self.head_kind = .rescue_head;
                }

                // Command ident classification
                if (self.cmd_context and keywordMap.get(kw_text) == null) {
                    if (self.isCommandArg()) {
                        tok.cat = .cmd_ident;
                        self.last_cat = .cmd_ident;
                        self.cmd_context = false;
                        return tok;
                    }
                }

                if (isStmtKeyword(kw_text)) {
                    self.cmd_context = true;
                    self.last_cat = tok.cat;
                    return tok;
                }
            }

            // ── 9. Update cmd_context ───────────────────────────────
            self.cmd_context = isCommandStart(tok.cat);
            self.last_cat = tok.cat;
            return tok;
        }
    }

    // ── Float-extension post-processor ──────────────────────────
    // The base lexer's scanNumber is generated-simple and only
    // produces `.integer` tokens. Ruby float literals
    // (`3.14`, `1_000.5`, `1.5e3`, `2e-9`) need a second pass:
    // after a `.integer` token, peek at the bytes immediately
    // after it and — if they form either `.digit(+)` or
    // `[eE][+-]?digit+` — widen the token's `len` to cover those
    // bytes and flip `cat` to `.float`. Speculative: `3.times`
    // must stay `.integer` + `.dot` + `.ident`, so we only
    // commit `.digit` consumption when a digit actually follows.
    fn tryExtendFloat(self: *Lexer, tok: *Token) bool {
        const src = self.base.source;
        var end: u32 = tok.pos + tok.len;

        // Consume any trailing `[0-9_]*` continuation the base lexer
        // didn't (scanNumber is generated-simple and stops at `_`).
        // This keeps the integer contiguous across underscore
        // separators even when we don't promote to float.
        const int_end_before = end;
        while (end < src.len and (isDigitByte(src[end]) or src[end] == '_')) : (end += 1) {}
        const extended_integer = end != int_end_before;

        var is_float = false;

        if (end + 1 < src.len and src[end] == '.' and isDigitByte(src[end + 1])) {
            is_float = true;
            end += 1; // consume '.'
            while (end < src.len and (isDigitByte(src[end]) or src[end] == '_')) : (end += 1) {}
        }

        if (end < src.len and (src[end] == 'e' or src[end] == 'E')) {
            var look: u32 = end + 1;
            if (look < src.len and (src[look] == '+' or src[look] == '-')) look += 1;
            if (look < src.len and isDigitByte(src[look])) {
                is_float = true;
                end = look;
                while (end < src.len and (isDigitByte(src[end]) or src[end] == '_')) : (end += 1) {}
            }
        }

        if (!is_float and !extended_integer) return false;
        self.base.pos = end;
        if (is_float) tok.cat = .float;
        tok.len = @intCast(end - tok.pos);
        return is_float; // only report "re-emit now" when widened to float
    }

    // ── `%w[…]` / `%i[…]` scanner ───────────────────────────────
    // Called when the base lexer just emitted a lone `.percent`
    // token (no `=` / `w[...]` extension). Checks whether the
    // next bytes form a Ruby word-array literal: `%w` or `%i`
    // followed by a delimiter and matching close. Supports the
    // four paired-delimiter shapes (`[] () {} <>`) which cover
    // the vast majority of idiomatic Ruby. Returns a synthesized
    // `.pct_w` / `.pct_i` token whose `pos`/`len` span the
    // entire literal including delimiters; the codegen strips
    // them when splitting into words.
    fn tryScanPctArray(self: *Lexer, tok: *Token) ?Token {
        const src = self.base.source;
        const start = tok.pos;
        // `%` already consumed — base.pos is just past it. Need
        // two more bytes: the w/i selector and the opening delim.
        if (self.base.pos + 1 >= src.len) return null;
        const sel = src[self.base.pos];
        if (sel != 'w' and sel != 'i') return null;
        const open = src[self.base.pos + 1];
        const close: u8 = switch (open) {
            '[' => ']',
            '(' => ')',
            '{' => '}',
            '<' => '>',
            else => return null,
        };

        // No `canEndExpr` gate here: the structural signature
        // `%[wi][<paired-delim>]` is distinctive enough that `%w[`
        // or `%i[` after an ident still means array literal in
        // practice. `3 % 2` still hits this code path with a lone
        // `%`-then-digit, which the switch above rejects. The
        // narrow case where this differs from MRI is `3%w[x]`
        // without whitespace, which nobody writes.

        // Once we've committed on the `%[wi]<paired>` signature, any
        // failure to find the matching close is a lex error — fall-back
        // to a plain `.percent` would cascade confusing downstream
        // errors as the rest of the file is (mis)interpreted with `%`
        // as the modulo operator. Ruby's `%w` / `%i` don't honor
        // nested opens of the same paired delimiter (unlike heredocs),
        // so a plain scan is correct.
        var p: u32 = self.base.pos + 2;
        while (p < src.len and src[p] != close) : (p += 1) {}
        if (p >= src.len) {
            // Unterminated. Synthesize an error token spanning
            // everything from the `%` through end-of-source; the
            // parser will surface this as a parse error with the
            // right location rather than a misleading modulo error
            // much later in the file.
            self.base.pos = p;
            tok.cat = .err;
            tok.pos = start;
            tok.len = @intCast(p - start);
            return tok.*;
        }
        p += 1; // consume close

        self.base.pos = p;
        tok.cat = if (sel == 'w') .pct_w else .pct_i;
        tok.pos = start;
        tok.len = @intCast(p - start);
        return tok.*;
    }

    fn isDigitByte(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    // ── Head-separator rewriting ────────────────────────────────
    // When in a control-flow head, the first non-suppressed
    // newline or semicolon ends the condition and becomes
    // THEN_SEP or DO_SEP.
    fn tryHeadSep(self: *Lexer, tok: *Token) ?Token {
        switch (self.head_kind) {
            .if_head, .elsif_head, .unless_head,
            .when_head, .case_head, .rescue_head => {
                self.head_kind = .none;
                tok.cat = .then_sep;
                self.last_cat = .then_sep;
                self.cmd_context = true;
                return tok.*;
            },
            .while_head, .until_head, .for_expr => {
                self.head_kind = .none;
                if (self.cond_depth > 0) self.cond_depth -= 1;
                tok.cat = .do_sep;
                self.last_cat = .do_sep;
                self.cmd_context = true;
                return tok.*;
            },
            .none, .for_vars => return null,
        }
    }

    // ─── Lookahead: is the next token a command argument? ────────────
    fn isCommandArg(self: *const Lexer) bool {
        if (self.base.pos >= self.base.source.len) return false;

        var p = self.base.pos;
        while (p < self.base.source.len and (self.base.source[p] == ' ' or self.base.source[p] == '\t'))
            p += 1;

        if (p >= self.base.source.len) return false;
        const ch = self.base.source[p];

        if (ch == '=' and p + 1 < self.base.source.len) {
            const ch2 = self.base.source[p + 1];
            if (ch2 != '=' and ch2 != '~' and ch2 != '>') return false;
        }
        if (ch == '.') return false;
        if (ch == '(') return false;
        if (ch == '\n' or ch == '\r' or ch == ';') return false;

        // `a[i]` with NO whitespace between ident and `[` is indexed
        // read, not a command call with array literal arg. With space,
        // `a [i]` stays ambiguous and we let the grammar continue as
        // cmd_ident (array literal as a single positional arg).
        if (ch == '[' and p == self.base.pos) return false;

        // `{` never starts a command argument — it's either a hash
        // literal (which Ruby requires to be parenthesized as an arg:
        // `f({a: 1})`) or a brace-block. Leaving `foo` as plain ident
        // lets canEndExpr-triggered reclassification turn `{` into
        // lbrace_block so the grammar's `IDENT block` rule matches.
        if (ch == '{') return false;

        // Binary operators preceded by space are not command arguments.
        // E.g., `a + b` is addition, not `a(+b)`.
        if (p > self.base.pos) {
            if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or
                ch == '<' or ch == '>' or ch == '|' or
                ch == '&' or ch == '^')
                return false;
            // `%` is special: `%w[…]`/`%i[…]` is an array literal and
            // IS a valid command argument (e.g., `puts %w[foo bar]`).
            // Only treat `%` as a binary modulo operator when NOT
            // followed by a percent-literal prefix.
            if (ch == '%') {
                const pw = p + 1;
                if (pw + 1 < self.base.source.len) {
                    const sel = self.base.source[pw];
                    const open = self.base.source[pw + 1];
                    if ((sel == 'w' or sel == 'i') and
                        (open == '[' or open == '(' or open == '{' or open == '<'))
                    {
                        return true;
                    }
                }
                return false;
            }
        }

        return isExprStartChar(ch);
    }

    // ─── Helper: tokens that can end an expression ──────────────────
    fn canEndExpr(cat: TokenCat) bool {
        return switch (cat) {
            .ident, .constant, .ivar, .cvar, .gvar,
            .integer, .float, .string_sq, .string_dq,
            .symbol, .label,
            .pct_w, .pct_i,
            .rparen, .rbracket, .rbrace,
            => true,
            else => false,
        };
    }

    // ─── Helper: keywords that start statement contexts ────────────
    fn isStmtKeyword(kw: []const u8) bool {
        return std.StaticStringMap(void).initComptime(.{
            .{ "begin", {} }, .{ "else", {} }, .{ "elsif", {} },
            .{ "end", {} }, .{ "ensure", {} }, .{ "rescue", {} },
            .{ "when", {} },
        }).has(kw);
    }

    // ─── Helper: tokens after which newlines should be suppressed ────
    fn isContinuation(cat: TokenCat) bool {
        return switch (cat) {
            // Binary operators
            .plus, .minus, .star, .slash, .percent, .power,
            .eq, .ne, .eqq, .cmp, .match_op, .nmatch,
            .lt, .gt, .le, .ge,
            .oror, .andand,
            .ampersand, .pipe, .caret, .lshift, .rshift,
            .bang,
            // Assignment
            .assign, .plus_eq, .minus_eq, .star_eq, .slash_eq,
            .percent_eq, .power_eq, .pipe_eq, .amp_eq, .caret_eq,
            .lshift_eq, .rshift_eq, .oror_eq, .andand_eq,
            // Punctuation that continues
            .comma, .dot, .safe_nav, .scope,
            .lparen, .lbracket, .lbrace, .lbrace_block,
            .fat_arrow, .question, .colon,
            // Unary / splat
            .plus_u, .minus_u, .star_splat, .amp_block, .tilde,
            // Modifier keywords (RHS follows)
            .if_mod, .unless_mod, .while_mod, .until_mod, .rescue_mod,
            => true,
            else => false,
        };
    }

    // ─── Helper: splat/block-pass context ────────────────────────────
    fn isSplatContext(cat: TokenCat) bool {
        return switch (cat) {
            .lparen, .comma, .lbracket, .lbrace, .lbrace_block,
            .pipe, .semicolon, .newline, .eof,
            .assign, .plus_eq, .minus_eq, .star_eq, .slash_eq,
            .percent_eq, .power_eq, .pipe_eq, .amp_eq, .caret_eq,
            .lshift_eq, .rshift_eq, .oror_eq, .andand_eq,
            .fat_arrow, .colon, .question,
            => true,
            else => false,
        };
    }

    // ─── Helper: label context (after { , ( [ or start of hash) ──────
    fn isLabelContext(cat: TokenCat) bool {
        return switch (cat) {
            .lbrace, .lbrace_block, .comma, .lparen, .lbracket,
            .newline, .semicolon, .eof,
            => true,
            else => false,
        };
    }

    // ─── Helper: tokens that start a command-call position ───────────
    fn isCommandStart(cat: TokenCat) bool {
        return switch (cat) {
            .newline, .semicolon, .eof,
            .do_block, .do_cond,
            .lbrace_block,
            .then_sep, .do_sep,
            => true,
            else => false,
        };
    }

    // ─── Helper: character that could start an expression ────────────
    fn isExprStartChar(ch: u8) bool {
        if (std.ascii.isAlphabetic(ch) or ch == '_') return true;
        if (std.ascii.isDigit(ch)) return true;
        return switch (ch) {
            '\'', '"', ':', '@', '[', '(', '{',
            '-', '+', '!', '~',
            => true,
            else => false,
        };
    }

    // ─── String interpolation helpers ────────────────────────────────

    fn hasInterpolation(self: *const Lexer, tok: Token) bool {
        const src = self.base.source;
        const start = tok.pos + 1;
        const end = tok.pos + tok.len - 1;
        var i: u32 = start;
        while (i < end) : (i += 1) {
            if (src[i] == '\\') {
                i += 1;
                continue;
            }
            if (src[i] == '#' and i + 1 < end and src[i + 1] == '{')
                return true;
        }
        return false;
    }

    fn startInterpolation(self: *Lexer, tok: Token) Token {
        self.interp_active = true;
        self.interp_scan = tok.pos + 1;
        self.interp_str_end = tok.pos + tok.len - 1;
        self.interp_saved_pos = self.base.pos;
        self.last_cat = .dstr_beg;
        self.cmd_context = false;

        const beg = Token{ .cat = .dstr_beg, .pos = tok.pos, .len = 1, .pre = tok.pre };
        self.interp_count = 0;
        self.interp_pos = 0;

        self.queueStringSegments();

        if (self.interp_count > 0) {
            self.interp_pos = 0;
        }

        return beg;
    }

    fn queueStringSegments(self: *Lexer) void {
        const src = self.base.source;
        var i = self.interp_scan;
        const end = self.interp_str_end;
        const seg_start = i;

        while (i < end) {
            if (src[i] == '\\' and i + 1 < end) {
                i += 2;
                continue;
            }
            if (src[i] == '#' and i + 1 < end and src[i + 1] == '{') {
                if (i > seg_start) {
                    self.enqueue(Token{ .cat = .str_content, .pos = seg_start, .len = @intCast(i - seg_start), .pre = 0 });
                }
                self.enqueue(Token{ .cat = .embexpr_beg, .pos = i, .len = 2, .pre = 0 });

                self.interp_scan = i + 2;
                self.interp_brace_depth = 1;
                self.base.pos = i + 2;
                return;
            }
            i += 1;
        }

        if (i > seg_start) {
            self.enqueue(Token{ .cat = .str_content, .pos = seg_start, .len = @intCast(i - seg_start), .pre = 0 });
        }
        self.enqueue(Token{ .cat = .dstr_end, .pos = end, .len = 1, .pre = 0 });
        self.interp_active = false;
        self.base.pos = self.interp_saved_pos;
    }

    fn scanStringBody(self: *Lexer) Token {
        if (self.interp_brace_depth > 0) {
            var tok = self.base.matchRules();
            if (tok.cat == .comment) return self.scanStringBody();
            if (tok.cat == .lbrace) {
                self.interp_brace_depth += 1;
            } else if (tok.cat == .rbrace) {
                self.interp_brace_depth -= 1;
                if (self.interp_brace_depth == 0) {
                    tok.cat = .embexpr_end;
                    self.interp_scan = self.base.pos;

                    self.interp_count = 0;
                    self.interp_pos = 0;
                    self.queueStringSegments();

                    self.last_cat = .embexpr_end;
                    return tok;
                }
            }
            self.last_cat = tok.cat;
            return tok;
        }

        if (self.interp_pos < self.interp_count) {
            const tok = self.interp_queue[self.interp_pos];
            self.interp_pos += 1;
            if (self.interp_pos >= self.interp_count) {
                self.interp_count = 0;
                self.interp_pos = 0;
            }
            self.last_cat = tok.cat;
            return tok;
        }

        self.interp_active = false;
        self.base.pos = self.interp_saved_pos;
        return self.next();
    }

    fn enqueue(self: *Lexer, tok: Token) void {
        if (self.interp_count < self.interp_queue.len) {
            self.interp_queue[self.interp_count] = tok;
            self.interp_count += 1;
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "keywordAs - core keywords" {
    try std.testing.expectEqual(KeywordId.IF, keywordAs("if").?);
    try std.testing.expectEqual(KeywordId.ELSE, keywordAs("else").?);
    try std.testing.expectEqual(KeywordId.DEF, keywordAs("def").?);
    try std.testing.expectEqual(KeywordId.END, keywordAs("end").?);
    try std.testing.expectEqual(KeywordId.TRUE, keywordAs("true").?);
    try std.testing.expectEqual(KeywordId.NIL, keywordAs("nil").?);
    try std.testing.expectEqual(KeywordId.RETURN, keywordAs("return").?);
    try std.testing.expectEqual(KeywordId.DEFINED, keywordAs("defined?").?);
}

test "keywordAs - not a keyword" {
    try std.testing.expect(keywordAs("puts") == null);
    try std.testing.expect(keywordAs("foo") == null);
    try std.testing.expect(keywordAs("Dog") == null);
    try std.testing.expect(keywordAs("") == null);
}
