//! Slash language module — Tag enum, keyword promotion, lexer wrapper.
//!
//! The lexer wrapper around the generated `BaseLexer` adds three responsibilities
//! that would clutter the grammar if done declaratively:
//!
//!   1. Comment trivia is dropped at the lexer boundary so the parser never
//!      sees it.
//!
//!   2. `IDENT '='` (no whitespace between, and no second `=` immediately
//!      after) fuses into a single `NAME_EQ` token. This is what makes
//!      env-prefix `FOO=bar cmd` and standalone assignment `x=5` work
//!      without LR(1) ambiguity. Loose `x = 5` parses as a command (`x`
//!      with args `=` and `5`); the shell rejects it with a clear "command
//!      not found".
//!
//!   3. Indentation tracks a stack of column levels and emits virtual
//!      `INDENT`/`OUTDENT` tokens at level changes. Spaces only — a tab
//!      in indentation is a hard error. The stack is suspended inside
//!      `(`, `{`, and `[` so multi-line bracketed forms aren't disrupted.
//!      Brace blocks `{ ... }` and indented blocks share one `block_form`
//!      production in the grammar, so `if cmd { body }` and
//!      `if cmd\n  body` produce the same Shape.

const std = @import("std");
const parser = @import("parser.zig");
pub const Token = parser.Token;
pub const TokenCat = parser.TokenCat;
const BaseLexer = parser.BaseLexer;

// =============================================================================
// Tag enum — every s-expression head emitted by the parser
// =============================================================================

pub const Tag = enum(u8) {
    // ---- Compound ----
    sequence,
    seq_always,
    seq_and,
    seq_or,
    seq_bg,
    pipeline,
    command,
    subshell,
    block,
    redirects,

    // ---- Words ----
    word,
    @"var",
    var_braced,
    cmd_subst,
    list_capture,
    proc_sub_in,
    proc_sub_out,
    scalar,
    list,
    words,

    // ---- Assignment / env-prefix ----
    env_binds,
    env_bind,
    assigns,

    // ---- Control flow ----
    @"if",
    @"else",
    elif,
    body,
    cond_and,
    cond_or,
    @"while",
    @"for",
    cmd_def,
    @"match",
    match_arms,
    match_arm,

    // ---- Redirects ----
    redir_read,
    redir_read_fd,
    redir_write,
    redir_write_fd,
    redir_append,
    redir_both,
    redir_both_append,
    redir_dup_out,
    redir_dup_in,
    redir_heredoc,
    redir_heredoc_lit,
};

// =============================================================================
// Keyword promotion
// =============================================================================
//
// `@as ident = [keyword]` in the grammar invokes `keywordAs` for every IDENT
// lookahead. The returned `KeywordId` is mapped by the generated parser to
// the actual symbol id; if that symbol is legal in the current state, the
// IDENT is promoted to the keyword token and shifted.

pub const KeywordId = enum(u16) {
    IF,
    ELSE,
    WHILE,
    FOR,
    IN,
    CMD,
    MATCH,
};

const keyword_map = std.StaticStringMap(KeywordId).initComptime(.{
    .{ "if", .IF },
    .{ "else", .ELSE },
    .{ "while", .WHILE },
    .{ "for", .FOR },
    .{ "in", .IN },
    .{ "cmd", .CMD },
    .{ "match", .MATCH },
});

pub fn keywordAs(text: []const u8) ?KeywordId {
    return keyword_map.get(text);
}

// =============================================================================
// Lexer wrapper
// =============================================================================

pub const Lexer = struct {
    base: BaseLexer,

    // Indentation tracking
    indent_level: u32 = 0,
    indent_stack: [64]u32 = [_]u32{0} ** 64,
    indent_depth: u8 = 0,
    pending_outdents: u8 = 0,
    queued: ?Token = null,
    last_cat: TokenCat = .eof,

    // Heredoc tracking. The parser wants a `heredoc_body` token
    // immediately after each `heredoc_open` (the grammar rule is
    // `HEREDOC_OPEN HEREDOC_BODY`), but bodies live on subsequent
    // physical lines. The wrapper resolves bodies eagerly at
    // open-sigil time by scanning forward past `heredoc_resume_pos`
    // (which advances as each body is consumed) and queues a single
    // body token to be emitted right after the open.
    queued_body: ?Token = null,
    /// Source offset at which the next heredoc body should start its
    /// search. Initially zero; bumped past the trailing newline of the
    /// closing-tag line each time a body is consumed. When the lexer
    /// reaches the newline at the end of the line that opened heredocs,
    /// `base.pos` jumps to `heredoc_resume_pos` so the rest of the
    /// source picks up after every consumed body.
    heredoc_resume_pos: u32 = 0,

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
        self.pending_outdents = 0;
        self.queued = null;
        self.last_cat = .eof;
        self.queued_body = null;
        self.heredoc_resume_pos = 0;
    }

    pub fn next(self: *Lexer) Token {
        // Drain any queued virtual tokens first.
        if (self.queued) |q| {
            self.queued = null;
            self.last_cat = q.cat;
            return q;
        }
        if (self.pending_outdents > 0) {
            self.pending_outdents -= 1;
            const t = Token{
                .cat = .outdent,
                .pre = 0,
                .pos = @intCast(self.base.pos),
                .len = 0,
            };
            self.last_cat = .outdent;
            return t;
        }

        // Drain a queued heredoc body. The body always immediately
        // follows its open sigil so the parser sees the pair atomically.
        if (self.queued_body) |body| {
            self.queued_body = null;
            self.last_cat = body.cat;
            return body;
        }

        while (true) {
            const tok = self.base.next();

            // Drop comment trivia.
            if (tok.cat == .comment) continue;

            // `lt` may be the start of a `<<TAG` or `<<'TAG'` heredoc
            // sigil. The auto-generated lexer dispatches `<` to a
            // single-char token before the multi-char heredoc patterns
            // get a chance, so we recover here.
            if (tok.cat == .lt) {
                if (self.tryFuseHeredocOpen(tok)) |fused| {
                    self.last_cat = fused.cat;
                    return fused;
                }
            }

            // Newlines: maybe become INDENT, OUTDENT(s), or stay as semi.
            if (tok.cat == .semi and self.isNewlineToken(tok)) {
                // If heredocs were resolved on this line, jump base.pos
                // past their bodies and closing tags before continuing.
                // The newline that triggered this advance is replaced
                // by the (possibly different) newline at the end of the
                // last consumed closing-tag line.
                if (self.heredoc_resume_pos > tok.pos) {
                    self.base.pos = self.heredoc_resume_pos;
                    self.heredoc_resume_pos = 0;
                    // Rewind one byte so the next token picks up the
                    // newline that ended the closing-tag line (or EOF
                    // if the source ended there).
                    if (self.base.pos > 0 and self.base.pos <= self.base.source.len and
                        self.base.pos - 1 < self.base.source.len and
                        self.base.source[self.base.pos - 1] == '\n')
                    {
                        // The trailing newline of the closing line is
                        // already consumed; emit it now as the
                        // statement separator for the original line.
                    }
                }
                if (self.handleNewline(tok)) |result| {
                    // Suppress a leading-of-block SEMI: `{`/`INDENT` followed
                    // by a newline shouldn't manifest as a stray sequence
                    // separator before the first body statement.
                    if (result.cat == .semi and isBlockOpener(self.last_cat)) {
                        continue;
                    }
                    self.last_cat = result.cat;
                    return result;
                }
                continue;
            }

            // Drop SEMIs immediately following SEMIs (collapses a run of
            // newlines into a single statement separator).
            if (tok.cat == .semi and self.last_cat == .semi) continue;

            // EOF: flush any open indentation as OUTDENTs.
            if (tok.cat == .eof) {
                if (self.indent_depth > 0) {
                    self.pending_outdents = self.indent_depth - 1;
                    self.indent_depth = 0;
                    self.indent_level = 0;
                    self.queued = tok;
                    self.last_cat = .outdent;
                    return Token{
                        .cat = .outdent,
                        .pre = 0,
                        .pos = tok.pos,
                        .len = 0,
                    };
                }
                self.last_cat = .eof;
                return tok;
            }

            // ASCII identifiers can be followed by UTF-8 bytes. Run
            // this BEFORE NAME_EQ so a name like `café=` fuses as
            // `name_eq` rather than splitting into `caf` + `é=`.
            var working = tok;
            if (working.cat == .ident and working.pos + working.len < self.base.source.len) {
                const after_ident = working.pos + working.len;
                if (self.base.source[after_ident] >= 0x80) {
                    var j = after_ident;
                    while (j < self.base.source.len and isBareWordContinueOrUtf8(self.base.source[j])) : (j += 1) {}
                    self.base.pos = j;
                    working.len = @intCast(j - working.pos);
                }
            }

            // NAME_EQ fusion: IDENT immediately followed by `=` (no whitespace
            // between) and not followed by another `=`. Fuse into one
            // NAME_EQ token whose source slice covers `name=`. The Shape
            // converter strips the trailing `=` to recover the bare name.
            if (working.cat == .ident) {
                const after = working.pos + working.len;
                if (after < self.base.source.len and
                    self.base.source[after] == '=' and
                    (after + 1 >= self.base.source.len or
                        self.base.source[after + 1] != '='))
                {
                    self.base.pos = after + 1;
                    var fused = working;
                    fused.cat = .name_eq;
                    fused.len += 1;
                    self.last_cat = .name_eq;
                    return fused;
                }
            }
            if (working.len != tok.len) {
                self.last_cat = .ident;
                return working;
            }

            // Special-parameter variables: `$?`, `$$`, `$#`, `$@`, `$!`, `$*`.
            // The base lexer's auto-generated `$...` handling covers `${name}`,
            // `$alpha+`, and `$digit`, but doesn't cover the special params.
            // Fuse them in the wrapper from the err+`$` shape.
            if (tok.cat == .err and tok.len == 1 and
                tok.pos < self.base.source.len and
                self.base.source[tok.pos] == '$' and
                tok.pos + 1 < self.base.source.len)
            {
                const next_ch = self.base.source[tok.pos + 1];
                if (next_ch == '?' or next_ch == '#' or next_ch == '@' or
                    next_ch == '!' or next_ch == '*' or next_ch == '$')
                {
                    self.base.pos = tok.pos + 2;
                    var t = tok;
                    t.cat = .variable;
                    t.len = 2;
                    self.last_cat = .variable;
                    return t;
                }
            }

            // List-capture fusion: a bare `@` immediately followed by `(`
            // has to become a single `at_paren` token. The grammar says
            // so, but the auto-generated lexer dispatches LETTER-class
            // bytes (`@` is one) into `scanIdent` before reaching the
            // operator switch, so `@(` arrives here as an `ident` of
            // length 1 trailed by an `lparen`. Recover.
            if (tok.cat == .ident and tok.len == 1 and
                self.base.source[tok.pos] == '@' and
                tok.pos + 1 < self.base.source.len and
                self.base.source[tok.pos + 1] == '(')
            {
                self.base.pos = tok.pos + 2;
                self.base.paren += 1;
                var t = tok;
                t.cat = .at_paren;
                t.len = 2;
                self.last_cat = .at_paren;
                return t;
            }

            // UTF-8 high-bit bytes lex as `err` from the auto-generated
            // dispatcher (ASCII-only LETTER class). Recover by scanning
            // onward as a bare ident — multibyte names like `café` or
            // Chinese filenames pass through as one word. The Shape
            // converter and downstream layers only care about byte
            // contents; column counting is byte-based for now.
            if (tok.cat == .err and tok.len == 1 and
                self.base.source[tok.pos] >= 0x80)
            {
                var j = tok.pos + 1;
                while (j < self.base.source.len and isBareWordContinueOrUtf8(self.base.source[j])) : (j += 1) {}
                self.base.pos = j;
                var t = tok;
                t.cat = .ident;
                t.len = @intCast(j - tok.pos);
                self.last_cat = .ident;
                return t;
            }

            // (UTF-8 ident extension runs above, before NAME_EQ fusion.)

            // Same trick for `$name` references — the auto-generated
            // variable scan stops at the first non-ASCII byte, so an
            // identifier like `naïve` is split into `na` (variable)
            // and `ïve` (extending text run). Extend the variable
            // token to swallow any trailing UTF-8 bytes that match the
            // bare-word continuation class.
            if (tok.cat == .variable and tok.pos + tok.len < self.base.source.len) {
                const after = tok.pos + tok.len;
                if (self.base.source[after] >= 0x80) {
                    var j = after;
                    while (j < self.base.source.len and isVarNameUtf8Cont(self.base.source[j])) : (j += 1) {}
                    self.base.pos = j;
                    var t = tok;
                    t.len = @intCast(j - tok.pos);
                    self.last_cat = .variable;
                    return t;
                }
            }

            // Track bracket depth for indent suspension. The base lexer
            // already tracks `paren` and `brace` (from grammar `{paren++}`
            // actions); we add `bracket` here as a wrapper-side field.
            self.last_cat = tok.cat;
            return tok;
        }
    }

    fn isNewlineToken(self: *const Lexer, tok: Token) bool {
        if (tok.len == 0) return false;
        const ch = self.base.source[tok.pos];
        return ch == '\n' or ch == '\r';
    }

    /// Try to fuse a plain `<` token plus the bytes that follow into a
    /// heredoc-open sigil (`<<TAG` or `<<'TAG'`) and resolve the body
    /// of THAT specific heredoc by scanning forward from
    /// `heredoc_resume_pos`. Returns the open token; queues the body
    /// token so the parser sees `(open, body)` back-to-back.
    fn tryFuseHeredocOpen(self: *Lexer, lt_tok: Token) ?Token {
        const src = self.base.source;
        var p = lt_tok.pos + 1;
        if (p >= src.len or src[p] != '<') return null;
        p += 1;

        var literal = false;
        if (p < src.len and src[p] == '\'') {
            literal = true;
            p += 1;
        }

        const tag_start = p;
        if (p >= src.len or !isHeredocTagStart(src[p])) return null;
        p += 1;
        while (p < src.len and isHeredocTagCont(src[p])) : (p += 1) {}
        const tag_end = p;
        if (tag_end == tag_start) return null;

        if (literal) {
            if (p >= src.len or src[p] != '\'') return null;
            p += 1;
        }

        const tag = src[tag_start..tag_end];

        // The body for this heredoc begins after the line that opens
        // it. If we've already resolved an earlier heredoc on the same
        // line, `heredoc_resume_pos` already points past that body.
        // Otherwise it's zero, and we use the current line's end.
        var body_start: u32 = self.heredoc_resume_pos;
        if (body_start == 0) body_start = lineEnd(src, p);
        if (body_start < src.len and src[body_start] == '\n') body_start += 1;

        // Find the closing tag.
        var line_start = body_start;
        var close_at: ?u32 = null;
        while (line_start < src.len) {
            const ln_end = lineEnd(src, line_start);
            const trimmed = trimAscii(src[line_start..ln_end]);
            if (std.mem.eql(u8, trimmed, tag)) {
                close_at = line_start;
                break;
            }
            line_start = if (ln_end < src.len) ln_end + 1 else ln_end;
        }

        const body_end: u32 = if (close_at) |c| c else @intCast(src.len);
        const after_close: u32 = if (close_at) |c| blk: {
            const ln_end = lineEnd(src, c);
            break :blk if (ln_end < src.len) ln_end + 1 else ln_end;
        } else @intCast(src.len);
        self.heredoc_resume_pos = after_close;

        // Consume the open sigil's bytes and queue the body.
        self.base.pos = p;
        self.queued_body = Token{
            .cat = .heredoc_body,
            .pre = 0,
            .pos = body_start,
            .len = @intCast(body_end - body_start),
        };

        const kind: TokenCat = if (literal) .heredoc_open_lit else .heredoc_open;
        return Token{
            .cat = kind,
            .pre = lt_tok.pre,
            .pos = lt_tok.pos,
            .len = @intCast(p - lt_tok.pos),
        };
    }

    /// True for tokens that introduce a block body and should swallow an
    /// immediately-following newline so the body parses cleanly.
    fn isBlockOpener(cat: TokenCat) bool {
        return switch (cat) {
            .lbrace, .lparen, .lbracket, .indent, .eof => true,
            else => false,
        };
    }

    /// Process a newline token. Returns:
    ///   - the original semi token (level unchanged)
    ///   - an INDENT token (level increased)
    ///   - an OUTDENT token, queueing more if multiple levels closed
    ///   - null to swallow (blank line; another newline will follow)
    fn handleNewline(self: *Lexer, nl: Token) ?Token {
        // Indentation is suspended inside (), {}, [] groupings.
        if (self.base.paren > 0 or self.base.brace > 0) return nl;

        // Skip blank/comment-only lines: scan past them and look at the
        // first content line's indent.
        var ws: u32 = 0;
        var p = self.base.pos;
        while (true) {
            ws = 0;
            while (p + ws < self.base.source.len) {
                const ch = self.base.source[p + ws];
                if (ch == ' ') {
                    ws += 1;
                } else if (ch == '\t') {
                    // Tabs in indentation are an error.
                    return Token{
                        .cat = .err,
                        .pre = 0,
                        .pos = @intCast(p + ws),
                        .len = 1,
                    };
                } else break;
            }
            if (p + ws >= self.base.source.len) {
                ws = 0;
                break; // EOF after whitespace
            }
            const next_ch = self.base.source[p + ws];
            if (next_ch == '\n' or next_ch == '\r') {
                // blank line; advance past and try again
                p = p + ws + 1;
                continue;
            }
            if (next_ch == '#') {
                // comment-only line; advance past comment + newline
                var q = p + ws;
                while (q < self.base.source.len and self.base.source[q] != '\n')
                    q += 1;
                if (q < self.base.source.len) q += 1;
                p = q;
                continue;
            }
            break;
        }

        const at_eof = p + ws >= self.base.source.len;

        if (!at_eof and ws > self.indent_level) {
            // Indent in: push current level, set new level, emit INDENT.
            if (self.indent_depth >= 63) return nl;
            self.indent_stack[self.indent_depth] = self.indent_level;
            self.indent_depth += 1;
            self.indent_level = ws;
            // Suppress the original newline; INDENT acts as the boundary.
            return Token{
                .cat = .indent,
                .pre = 0,
                .pos = nl.pos,
                .len = 0,
            };
        }

        if (ws < self.indent_level) {
            // Indent out: pop levels until we match. Emit OUTDENT(s),
            // followed by the original newline UNLESS the next non-
            // whitespace identifier is `else` — in that case the newline
            // is suppressed so the conditional flows naturally.
            var count: u8 = 0;
            var lvl = self.indent_level;
            while (lvl > ws) {
                if (self.indent_depth == 0) break;
                self.indent_depth -= 1;
                lvl = self.indent_stack[self.indent_depth];
                count += 1;
            }
            if (lvl != ws and !at_eof) {
                return Token{
                    .cat = .err,
                    .pre = 0,
                    .pos = nl.pos,
                    .len = 0,
                };
            }
            self.indent_level = ws;
            if (count > 0) {
                if (!sourceStartsWithElse(self.base.source, p + ws)) {
                    self.queued = nl;
                }
                self.pending_outdents = count - 1;
                return Token{
                    .cat = .outdent,
                    .pre = 0,
                    .pos = nl.pos,
                    .len = 0,
                };
            }
        }

        // Same level — original newline acts as statement separator.
        return nl;
    }
};

fn isHeredocTagStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isHeredocTagCont(c: u8) bool {
    return isHeredocTagStart(c) or (c >= '0' and c <= '9');
}

/// Index of the next `\n` (or end of source). The byte at the returned
/// index, if it's within bounds, is the newline itself.
fn lineEnd(src: []const u8, start: u32) u32 {
    var i = start;
    while (i < src.len and src[i] != '\n') : (i += 1) {}
    return i;
}

/// Strip leading and trailing ASCII whitespace (including `\r`).
fn trimAscii(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t\r");
}

/// Continuation bytes of the bare-word class (matching the grammar's
/// ident rule: `[A-Za-z_./\-+~@%!*?:,^][A-Za-z0-9_./\-+~@%!*?:,^]*`).
fn isBareWordContinue(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9',
        '_', '.', '/', '-', '+', '~', '@', '%', '!', '*', '?', ':', ',', '^',
        => true,
        else => false,
    };
}

/// Like `isBareWordContinue` but also admits any byte ≥ 0x80 so a
/// UTF-8 sequence — start byte plus continuation bytes — flows
/// through the ident scan as one token. The lexer treats the entire
/// run as raw bytes; semantic interpretation (case folding, etc.)
/// would be the next step but isn't needed for v0 correctness.
fn isBareWordContinueOrUtf8(c: u8) bool {
    return c >= 0x80 or isBareWordContinue(c);
}

/// Variable-name continuation: tighter than the bare-word class
/// because a name like `$x.y` legitimately splits at the dot. Allow
/// alphanumerics, `_`, and any high-bit byte.
fn isVarNameUtf8Cont(c: u8) bool {
    return c >= 0x80 or
        (c >= 'A' and c <= 'Z') or
        (c >= 'a' and c <= 'z') or
        (c >= '0' and c <= '9') or
        c == '_';
}

/// True if `source[pos..]` begins with the keyword `else` followed by a
/// non-identifier byte (so `elseif` doesn't match). Free helper because
/// it's pure source inspection with no Lexer state.
fn sourceStartsWithElse(source: []const u8, pos: usize) bool {
    if (pos + 4 > source.len) return false;
    if (!std.mem.eql(u8, source[pos .. pos + 4], "else")) return false;
    if (pos + 4 == source.len) return true;
    const next = source[pos + 4];
    return next == ' ' or next == '\t' or next == '\n' or
        next == '\r' or next == '{' or next == '#';
}
