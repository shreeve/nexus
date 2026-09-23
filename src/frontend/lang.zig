//! lang.zig: the @lang module of the self-hosted frontend (parser.zig).
//!
//! Re-exports the Tag enum of the frontend's S-expression tree and provides the Lexer
//! wrapper that turns the generated BaseLexer's tokens into the token
//! stream nexus.grammar parses. The wrapper owns everything that depends
//! on layout or context:
//!
//!   - Layout. Blank lines and comment-only lines produce no tokens. Each
//!     remaining line break becomes one token: `newline` when the next line
//!     starts in column 1, `cont` when it is indented (a continuation of the
//!     current rule or directive block), or `next_alt` when the next line
//!     starts with `|` (the `|` is consumed with it). Inside `[ ... ]` line
//!     breaks are plain whitespace. No layout token precedes the first
//!     token; one `newline` always precedes `eof` after content.
//!   - Comments. Trailing comments are dropped, except in `@conflicts`
//!     entries (below).
//!   - `@conflicts` entries. Each indented line of the block is split into
//!     the kind word (`ident`), the rule text verbatim (`rule_text`; any
//!     symbol syntax, `→`/`->`, `ε`), `over` (`kw_over`) and a second rule
//!     text, the count (`integer`: the last word), and the rationale
//!     (`comment`: from `#` to the end of the line).
//!   - Unicode: `→` is an arrow.
//!   - Words. An identifier immediately followed by `:` is a `label`
//!     (`role:element`, `expr: "expression"`); the colon is consumed.
//!     Capitalized words are `token`s. `X` followed by a one-character
//!     string literal is the next-char hint keyword `kw_x`. `L` immediately
//!     followed by `(` is the list keyword `kw_list`. The word after a `@`
//!     is a directive keyword; `left right none` are keywords inside an
//!     `@infix` block, `over` inside `@conflicts`, `via` in an `@as` line.
//!     Inside `@schema` a `|` within parentheses (`tag(a | b)`) or written
//!     without a space before it joins a type union (`union`); any other
//!     `|` starts the side-band roles.
//!   - Sections. A `@lexer` or `@parser` at the start of a line is `at`
//!     followed by `kw_lexer` / `kw_parser`, and switches the scanner to
//!     that section. Before the first marker (the preamble) and in the
//!     @parser section the rules above and below apply; the @lexer section
//!     is scanned line by line (below).
//!   - The @lexer section. Blank and comment lines produce no tokens. A
//!     `state`, `after` or `tokens` line (`kw_state` ...) opens a block:
//!     its indented lines are `cont` lines; every other line break is a
//!     `newline`. A line that opens no block starts with `@code` (`at`
//!     `kw_code`), with `@` (a zero-width rule), or with a pattern, which
//!     is scanned verbatim up to an unquoted `@`, arrow, or `#` (`pattern`,
//!     trailing blanks excluded). The rest of a line is `ident`s, integers
//!     (with an optional `-`), `quoted` bytes (`'c'`), `compare` (`==` `!=`
//!     `<` `<=` `>` `>=`), `incdec` (`++` `--`), arrows (`→` `->` `=>`), and
//!     `= ! & , ( ) { }`. Any other run of characters is `err`. An
//!     unterminated literal or class, an unterminated quoted byte, and a
//!     line that is not a rule are `err` tokens with a `problem` message.
//!   - Actions. After an arrow outside brackets (and outside `@conflicts`)
//!     the rest of the line is an action, scanned in action mode: `(` `)`,
//!     positions (`integer`), `...N` (`dots` + `integer`), `~N` (`tilde` +
//!     `integer`), `!N` (`bang` + `integer`), `_`/`nil` (`kw_nil`),
//!     `role:` (`label`), and any other run of non-blank characters is a
//!     `word` (a tag). An open parenthesis continues the action onto
//!     indented lines. A `#` outside parentheses starts a comment; `~`
//!     outside parentheses before a string is the coverage opt-out.

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;
const TokenCat = parser.TokenCat;

/// The tags of the frontend tree, generated from nexus.grammar's @schema.
pub const Tag = parser.Tag;

pub const Lexer = struct {
    base: BaseLexer,
    section: Section = .preamble,
    mode: Mode = .normal,
    block: Block = .none,
    afterAt: bool = false,
    /// The next token is the first of its line.
    lineStart: bool = true,
    /// No token has been emitted yet (layout tokens are suppressed).
    atStart: bool = true,
    /// The last emitted token was a layout token (or nothing yet).
    afterLayout: bool = true,
    bracketDepth: u16 = 0,
    parenDepth: u16 = 0,
    /// Tokens scanned ahead of the one being returned (a `@conflicts`
    /// entry line is split at once), in order from `queueHead`.
    queue: [8]Token = undefined,
    queueHead: u8 = 0,
    queueLen: u8 = 0,
    /// Position of the last line break, for the `newline` before `eof`.
    lastBreak: ?u32 = null,
    /// The last `at` began its line (a section marker can follow).
    atLineStart: bool = false,
    /// @lexer section: a `state`, `after` or `tokens` block is open, and
    /// the current line is one of its indented lines.
    lexBlock: bool = false,
    blockLine: bool = false,
    /// Why the last `err` token was produced, when the token alone does not
    /// say (see `Problem`).
    problem: ?Problem = null,
    /// The last @lexer-section pattern: a syntax error later on its line is
    /// reported as the pattern's own error when the pattern is invalid.
    lastPattern: ?Token = null,

    const Mode = enum { normal, action };
    const Block = enum { none, as, conflicts, infix, schema, other };
    pub const Section = enum { preamble, lexer, parser };

    /// A scanning error the parser reports instead of "unexpected err":
    /// the message for the `err` token at `pos`.
    pub const Problem = struct {
        pos: u32,
        buf: [160]u8 = undefined,
        len: u8 = 0,

        pub fn message(self: *const Problem) []const u8 {
            return self.buf[0..self.len];
        }
    };

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
        self.* = .{ .base = self.base };
    }

    pub fn next(self: *Lexer) Token {
        if (self.queueHead < self.queueLen) {
            const tok = self.queue[self.queueHead];
            self.queueHead += 1;
            return self.emit(tok);
        }
        while (true) {
            const tok = (if (self.section == .lexer)
                self.scanLexer()
            else if (self.mode == .action)
                self.scanAction()
            else
                self.scanNormal()) orelse continue;
            return self.emit(tok);
        }
    }

    fn src(self: *const Lexer) []const u8 {
        return self.base.source;
    }

    fn push(self: *Lexer, tok: Token) void {
        if (self.queueHead == self.queueLen) {
            self.queueHead = 0;
            self.queueLen = 0;
        }
        self.queue[self.queueLen] = tok;
        self.queueLen += 1;
    }

    fn make(cat: TokenCat, pos: usize, len: usize) Token {
        return .{ .cat = cat, .pre = 0, .pos = @intCast(pos), .len = @intCast(len) };
    }

    fn emit(self: *Lexer, tok: Token) Token {
        const layout = tok.cat == .newline or tok.cat == .cont or tok.cat == .next_alt;
        if (!layout and tok.cat != .eof) {
            self.atStart = false;
            self.lineStart = false;
        }
        self.afterLayout = layout;
        self.afterAt = tok.cat == .at;
        if (tok.cat == .at) self.atLineStart = tok.pos == 0 or self.src()[tok.pos - 1] == '\n';
        return tok;
    }

    // --- Normal mode -------------------------------------------------------

    /// One token in normal mode, or null when the scanned input produced no
    /// token (a dropped comment, a line break inside brackets).
    fn scanNormal(self: *Lexer) ?Token {
        const s = self.src();
        var p = self.base.pos;
        while (p < s.len and (s[p] == ' ' or s[p] == '\t' or s[p] == '\r')) p += 1;
        if (self.block == .conflicts and self.lineStart and !self.afterAt and p < s.len and s[p] != '\n') {
            return self.splitConflict(p);
        }
        // The Unicode arrow is not in the generated lexer.
        if (p + 2 < s.len and s[p] == 0xE2 and s[p + 1] == 0x86 and s[p + 2] == 0x92) {
            self.base.pos = @intCast(p + 3);
            return self.arrow(make(.arrow, p, 3));
        }

        var tok = self.base.matchRules();
        switch (tok.cat) {
            .newline => return self.lineBreak(tok.pos),
            .eof => {
                if (!self.atStart and !self.afterLayout) {
                    self.push(tok);
                    return make(.newline, self.lastBreak orelse tok.pos, if (self.lastBreak != null) 1 else 0);
                }
                return tok;
            },
            .comment => return null,
            .ident => tok.cat = self.classifyWord(tok),
            .lbracket => self.bracketDepth += 1,
            .rbracket => {
                if (self.bracketDepth > 0) self.bracketDepth -= 1;
            },
            .arrow => return self.arrow(tok),
            .pipe => if (self.block == .schema and (self.parenDepth > 0 or (tok.pos > 0 and !isBlank(s[tok.pos - 1])))) {
                tok.cat = .@"union";
            },
            .lparen => if (self.block == .schema) {
                self.parenDepth += 1;
            },
            .rparen => if (self.block == .schema and self.parenDepth > 0) {
                self.parenDepth -= 1;
            },
            .at => if (self.lineStart) {
                // A directive: its keyword decides the block context.
                self.block = .other;
            },
            else => {},
        }
        return tok;
    }

    /// Split a `@conflicts` entry line starting at `start` into its tokens
    /// (see the file header); returns the first and queues the rest.
    fn splitConflict(self: *Lexer, start: usize) Token {
        const s = self.src();
        var end = start;
        var inString = false;
        while (end < s.len and s[end] != '\n') : (end += 1) {
            if (inString and s[end] == '\\' and end + 1 < s.len and s[end + 1] != '\n') {
                end += 1;
                continue;
            }
            if (s[end] == '"') inString = !inString;
            if (s[end] == '#' and !inString) break;
        }
        const commentStart = end;
        var lineEnd = end;
        while (lineEnd < s.len and s[lineEnd] != '\n') lineEnd += 1;
        while (end > start and isBlank(s[end - 1])) end -= 1;

        // Words, outside strings.
        var words: [64]struct { a: usize, b: usize } = undefined;
        var n: usize = 0;
        var i = start;
        while (i < end and n < words.len) {
            while (i < end and isBlank(s[i])) i += 1;
            if (i >= end) break;
            const a = i;
            var quoted = false;
            while (i < end and (quoted or !isBlank(s[i]))) : (i += 1) {
                if (quoted and s[i] == '\\' and i + 1 < end) {
                    i += 1;
                    continue;
                }
                if (s[i] == '"') quoted = !quoted;
            }
            words[n] = .{ .a = a, .b = i };
            n += 1;
        }

        var toks: [6]Token = undefined;
        var t: usize = 0;
        if (n > 0) {
            toks[t] = make(.ident, words[0].a, words[0].b - words[0].a);
            t += 1;
            var last = n;
            const count: ?Token = if (n > 1 and allDigits(s[words[n - 1].a..words[n - 1].b])) blk: {
                last = n - 1;
                break :blk make(.integer, words[n - 1].a, words[n - 1].b - words[n - 1].a);
            } else null;
            // Rule texts, split at a standalone `over`.
            var from: usize = 1;
            for (1..last + 1) |w| {
                const isOver = w < last and eql(s[words[w].a..words[w].b], "over");
                if (w == last or isOver) {
                    if (w > from and t < toks.len) {
                        toks[t] = make(.rule_text, words[from].a, words[w - 1].b - words[from].a);
                        t += 1;
                    }
                    if (isOver and t < toks.len) {
                        toks[t] = make(.kw_over, words[w].a, 4);
                        t += 1;
                    }
                    from = w + 1;
                }
            }
            if (count) |c| if (t < toks.len) {
                toks[t] = c;
                t += 1;
            };
        }
        if (commentStart < lineEnd and t < toks.len) {
            toks[t] = make(.comment, commentStart, lineEnd - commentStart);
            t += 1;
        }
        self.base.pos = @intCast(lineEnd);
        if (t == 0) return make(.err, start, 1);
        for (toks[1..t]) |tok| self.push(tok);
        return toks[0];
    }

    fn arrow(self: *Lexer, tok: Token) Token {
        if (self.bracketDepth == 0 and self.block != .conflicts) {
            self.mode = .action;
            self.parenDepth = 0;
        }
        return tok;
    }

    /// A line break at `pos`: skips blank and comment-only lines, then
    /// returns the layout token for the next content line (or null inside
    /// brackets and before the first token).
    fn lineBreak(self: *Lexer, pos: usize) ?Token {
        const s = self.src();
        var i = pos;
        while (i < s.len and s[i] != '\n') i += 1;
        if (i < s.len) i += 1;
        while (true) {
            const lineBegin = i;
            while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\r')) i += 1;
            if (i >= s.len) {
                self.base.pos = @intCast(s.len);
                self.lastBreak = @intCast(pos);
                return null; // eof handling emits the final newline
            }
            if (s[i] == '\n') {
                i += 1;
                continue;
            }
            if (s[i] == '#') {
                while (i < s.len and s[i] != '\n') i += 1;
                continue;
            }
            self.base.pos = @intCast(i);
            if (self.bracketDepth > 0) return null;
            if (self.atStart) return null;
            self.lineStart = true;
            self.parenDepth = 0;
            if (s[i] == '|') {
                self.base.pos = @intCast(i + 1);
                return make(.next_alt, i, 1);
            }
            if (i > lineBegin) return make(.cont, pos, 1);
            self.block = .none;
            return make(.newline, pos, 1);
        }
    }

    fn classifyWord(self: *Lexer, tok: Token) TokenCat {
        const s = self.src();
        const end = tok.pos + tok.len;
        const t = s[tok.pos..end];

        if (self.afterAt and self.atLineStart and tok.pos > 0 and self.src()[tok.pos - 1] == '@') {
            if (eql(t, "lexer")) {
                self.section = .lexer;
                self.lexBlock = false;
                return .kw_lexer;
            }
            if (eql(t, "parser")) {
                self.section = .parser;
                return .kw_parser;
            }
        }
        if (self.afterAt) {
            if (directiveKeyword(t)) |kw| {
                if (self.block == .other) self.block = switch (kw) {
                    .kw_as => .as,
                    .kw_conflicts => .conflicts,
                    .kw_infix => .infix,
                    .kw_schema => .schema,
                    else => .other,
                };
                return kw;
            }
        }
        if (end < s.len and s[end] == ':' and !(end + 1 < s.len and s[end + 1] == ':')) {
            self.base.pos = @intCast(end + 1);
            return .label;
        }
        if (eql(t, "X") and isHintLiteral(s, end)) return .kw_x;
        if (eql(t, "L") and end < s.len and s[end] == '(') return .kw_list;
        switch (self.block) {
            .infix => {
                if (eql(t, "left")) return .kw_left;
                if (eql(t, "right")) return .kw_right;
                if (eql(t, "none")) return .kw_none;
            },
            .as => if (eql(t, "via")) return .kw_via,
            else => {},
        }
        if (t[0] >= 'A' and t[0] <= 'Z') return .token;
        return .ident;
    }

    fn directiveKeyword(t: []const u8) ?TokenCat {
        const map = [_]struct { []const u8, TokenCat }{
            .{ "lang", .kw_lang },     .{ "conflicts", .kw_conflicts },
            .{ "as", .kw_as },         .{ "op", .kw_op },
            .{ "errors", .kw_errors }, .{ "display", .kw_display },
            .{ "infix", .kw_infix },   .{ "schema", .kw_schema },
            .{ "tags", .kw_tags },     .{ "trivia", .kw_trivia },
            .{ "repair", .kw_repair }, .{ "wrapper", .kw_wrapper },
        };
        for (map) |entry| if (eql(t, entry[0])) return entry[1];
        return null;
    }

    /// Whether a one-character string literal (`"c"` or `"\c"`) follows
    /// position `end`, after blanks: the `X "c"` next-char hint.
    fn isHintLiteral(s: []const u8, end: usize) bool {
        var i = end;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t')) i += 1;
        if (i + 2 < s.len and s[i] == '"' and s[i + 1] != '\\' and s[i + 2] == '"') return true;
        return i + 3 < s.len and s[i] == '"' and s[i + 1] == '\\' and s[i + 3] == '"';
    }

    // --- The @lexer section ------------------------------------------------

    /// One token of the @lexer section, or null when the scanned input
    /// produced none (a comment, a skipped line).
    fn scanLexer(self: *Lexer) ?Token {
        const s = self.src();
        var p: usize = self.base.pos;
        while (p < s.len and isBlank(s[p])) p += 1;
        self.base.pos = @intCast(p);
        if (p >= s.len) return self.endOfInput(p);
        const c = s[p];
        if (c == '\n') return self.lexerLineBreak(p);
        if (c == '#') {
            while (p < s.len and s[p] != '\n') p += 1;
            self.base.pos = @intCast(p);
            return null;
        }
        if (self.lineStart and !self.blockLine) return self.lexerLineStart(p);
        return self.lexerToken(p);
    }

    /// The first token of a line that is not inside a block.
    fn lexerLineStart(self: *Lexer, p: usize) Token {
        const s = self.src();
        const c = s[p];
        if (c == '@') {
            const word = s[p + 1 .. p + 1 + wordLen(s, p + 1)];
            const kw: ?TokenCat = if (eql(word, "code"))
                .kw_code
            else if (eql(word, "parser"))
                .kw_parser
            else if (eql(word, "lexer"))
                .kw_lexer
            else
                null;
            self.base.pos = @intCast(p + 1);
            if (kw) |k| {
                self.base.pos = @intCast(p + 1 + word.len);
                self.push(make(k, p + 1, word.len));
                if (k == .kw_parser) self.section = .parser;
            }
            return make(.at, p, 1);
        }
        const word = s[p .. p + wordLen(s, p)];
        if (word.len > 0) {
            const kw: ?TokenCat = if (eql(word, "state"))
                .kw_state
            else if (eql(word, "after"))
                .kw_after
            else if (eql(word, "tokens"))
                .kw_tokens
            else
                null;
            if (kw) |k| {
                self.base.pos = @intCast(p + word.len);
                self.lexBlock = true;
                return make(k, p, word.len);
            }
        }
        switch (c) {
            '\'', '"', '[', '.', '(', '\\' => return self.lexerPattern(p),
            else => {},
        }
        const end = p + nonBlankLen(s, p);
        self.base.pos = @intCast(end);
        return self.fail(p, end - p, "unrecognized line in the @lexer section: '{s}' (expected state, after, tokens, @code, or a rule)", .{s[p..end]});
    }

    /// A rule's pattern: up to an unquoted `@`, arrow, or `#`, or the end
    /// of the line, without trailing blanks. Quotes and classes honor
    /// backslash escapes and must close on the line.
    fn lexerPattern(self: *Lexer, start: usize) Token {
        const s = self.src();
        var p = start;
        while (p < s.len) {
            const c = s[p];
            if (c == '\n' or c == '#' or c == '@' or arrowLen(s, p) != 0) break;
            if (c == '\'' or c == '"') {
                const open = p;
                p += 1;
                while (p < s.len and s[p] != c and s[p] != '\n') {
                    if (s[p] == '\\' and p + 1 < s.len and s[p + 1] != '\n') p += 1;
                    p += 1;
                }
                if (p >= s.len or s[p] != c) return self.failLine(open, "unterminated quoted literal", .{});
                p += 1;
                continue;
            }
            if (c == '[') {
                const open = p;
                p += 1;
                if (p < s.len and s[p] == '^') p += 1;
                if (p < s.len and s[p] == ']') p += 1;
                while (p < s.len and s[p] != ']' and s[p] != '\n') {
                    if (s[p] == '\\' and p + 1 < s.len and s[p + 1] != '\n') p += 1;
                    p += 1;
                }
                if (p >= s.len or s[p] != ']') return self.failLine(open, "unclosed '['", .{});
                p += 1;
                continue;
            }
            if (c == '\\' and p + 1 < s.len and s[p + 1] != '\n') {
                p += 2;
                continue;
            }
            p += 1;
        }
        self.base.pos = @intCast(p);
        var end = p;
        while (end > start and isBlank(s[end - 1])) end -= 1;
        const tok = make(.pattern, start, end - start);
        self.lastPattern = tok;
        return tok;
    }

    /// A token after the start of a @lexer-section line.
    fn lexerToken(self: *Lexer, p: usize) Token {
        const s = self.src();
        const c = s[p];
        const after: u8 = if (p + 1 < s.len) s[p + 1] else 0;
        const arrowBytes = arrowLen(s, p);
        if (arrowBytes != 0) return self.take(.arrow, p, arrowBytes);
        if (std.ascii.isAlphabetic(c) or c == '_') return self.take(.ident, p, wordLen(s, p));
        if (std.ascii.isDigit(c) or (c == '-' and std.ascii.isDigit(after))) {
            var e = p + 1;
            while (e < s.len and std.ascii.isDigit(s[e])) e += 1;
            return self.take(.integer, p, e - p);
        }
        switch (c) {
            '=' => return if (after == '=') self.take(.compare, p, 2) else self.take(.eq, p, 1),
            '!' => return if (after == '=') self.take(.compare, p, 2) else self.take(.bang, p, 1),
            '<', '>' => return self.take(.compare, p, if (after == '=') 2 else 1),
            '+', '-' => if (after == c) return self.take(.incdec, p, 2),
            '&' => return self.take(.amp, p, 1),
            ',' => return self.take(.comma, p, 1),
            '(' => return self.take(.lparen, p, 1),
            ')' => return self.take(.rparen, p, 1),
            '{' => return self.take(.lbrace, p, 1),
            '}' => return self.take(.rbrace, p, 1),
            '@' => return self.take(.at, p, 1),
            '\'' => {
                var e = p + 1;
                while (e < s.len and s[e] != '\'' and s[e] != '\n') {
                    if (s[e] == '\\' and e + 1 < s.len and s[e + 1] != '\n') e += 1;
                    e += 1;
                }
                if (e >= s.len or s[e] != '\'') return self.failLine(p, "unterminated quoted byte", .{});
                return self.take(.quoted, p, e + 1 - p);
            },
            else => {},
        }
        // Anything else, up to a blank or a character that starts a token.
        var e = p + 1;
        while (e < s.len and !isBlank(s[e]) and s[e] != '\n' and std.mem.indexOfScalar(u8, "=!<>&,(){}@'#", s[e]) == null) e += 1;
        return self.take(.err, p, e - p);
    }

    fn take(self: *Lexer, cat: TokenCat, pos: usize, len: usize) Token {
        self.base.pos = @intCast(pos + len);
        return make(cat, pos, len);
    }

    /// A line break in the @lexer section: skips blank and comment lines;
    /// an indented line inside a block is `cont`, any other line `newline`.
    fn lexerLineBreak(self: *Lexer, pos: usize) ?Token {
        const s = self.src();
        var i = pos + 1;
        while (true) {
            const lineBegin = i;
            while (i < s.len and isBlank(s[i])) i += 1;
            if (i >= s.len) {
                self.base.pos = @intCast(s.len);
                self.lastBreak = @intCast(pos);
                return null; // eof handling emits the final newline
            }
            if (s[i] == '\n') {
                i += 1;
                continue;
            }
            if (s[i] == '#') {
                while (i < s.len and s[i] != '\n') i += 1;
                continue;
            }
            self.base.pos = @intCast(i);
            if (self.atStart) return null;
            self.lineStart = true;
            if (i > lineBegin and self.lexBlock) {
                self.blockLine = true;
                return make(.cont, pos, 1);
            }
            self.lexBlock = false;
            self.blockLine = false;
            return make(.newline, pos, 1);
        }
    }

    /// End of input: one `newline` after content, then `eof`.
    fn endOfInput(self: *Lexer, p: usize) Token {
        const tok = make(.eof, p, 0);
        if (!self.atStart and !self.afterLayout) {
            self.push(tok);
            return make(.newline, self.lastBreak orelse p, if (self.lastBreak != null) 1 else 0);
        }
        return tok;
    }

    /// An `err` token for the rest of the line, with a problem message.
    fn failLine(self: *Lexer, pos: usize, comptime fmt: []const u8, args: anytype) Token {
        const s = self.src();
        var end = pos;
        while (end < s.len and s[end] != '\n') end += 1;
        self.base.pos = @intCast(end);
        return self.fail(pos, end - pos, fmt, args);
    }

    fn fail(self: *Lexer, pos: usize, len: usize, comptime fmt: []const u8, args: anytype) Token {
        var problem: Problem = .{ .pos = @intCast(pos) };
        const written = std.fmt.bufPrint(&problem.buf, fmt, args) catch problem.buf[0..];
        problem.len = @intCast(written.len);
        self.problem = problem;
        return make(.err, pos, len);
    }

    /// Arrow at `p`: `→`, `->` or `=>`; its length in bytes, or 0.
    fn arrowLen(s: []const u8, p: usize) usize {
        if (p + 1 < s.len and (s[p] == '-' or s[p] == '=') and s[p + 1] == '>') return 2;
        if (p + 2 < s.len and s[p] == 0xE2 and s[p + 1] == 0x86 and s[p + 2] == 0x92) return 3;
        return 0;
    }

    fn wordLen(s: []const u8, p: usize) usize {
        var e = p;
        if (e < s.len and (std.ascii.isAlphabetic(s[e]) or s[e] == '_')) {
            while (e < s.len and (std.ascii.isAlphanumeric(s[e]) or s[e] == '_')) e += 1;
        }
        return e - p;
    }

    fn nonBlankLen(s: []const u8, p: usize) usize {
        var e = p;
        while (e < s.len and !isBlank(s[e]) and s[e] != '\n') e += 1;
        return e - p;
    }

    // --- Action mode -------------------------------------------------------

    fn scanAction(self: *Lexer) ?Token {
        const s = self.src();
        var p: usize = self.base.pos;
        while (p < s.len and (s[p] == ' ' or s[p] == '\t' or s[p] == '\r')) p += 1;
        self.base.pos = @intCast(p);

        if (p >= s.len or s[p] == '\n') {
            if (self.parenDepth > 0 and self.continuesAction(p)) return null;
            self.mode = .normal;
            return null;
        }
        const c = s[p];
        if (c == '#' and self.parenDepth == 0) {
            while (p < s.len and s[p] != '\n') p += 1;
            self.base.pos = @intCast(p);
            self.mode = .normal;
            return null;
        }
        if (c == '(') {
            self.parenDepth += 1;
            self.base.pos += 1;
            return make(.lparen, p, 1);
        }
        if (c == ')') {
            if (self.parenDepth > 0) self.parenDepth -= 1;
            self.base.pos += 1;
            return make(.rparen, p, 1);
        }
        if (c == '~' and self.parenDepth == 0) {
            var q = p + 1;
            while (q < s.len and (s[q] == ' ' or s[q] == '\t')) q += 1;
            if (q < s.len and s[q] == '"') {
                self.base.pos += 1;
                self.mode = .normal;
                return make(.tilde, p, 1);
            }
        }

        var end = p;
        while (end < s.len and !isBlank(s[end]) and s[end] != '\n' and s[end] != '(' and s[end] != ')') end += 1;
        const w = s[p..end];

        // `role:` prefix
        if (identPrefix(w)) |n| if (n < w.len and w[n] == ':') {
            self.base.pos = @intCast(p + n + 1);
            return make(.label, p, n);
        };
        if (allDigits(w)) {
            self.base.pos = @intCast(end);
            return make(.integer, p, w.len);
        }
        const marks = [_]struct { []const u8, TokenCat }{ .{ "...", .dots }, .{ "~", .tilde }, .{ "!", .bang } };
        for (marks) |m| {
            if (w.len > m[0].len and std.mem.startsWith(u8, w, m[0]) and allDigits(w[m[0].len..])) {
                self.base.pos = @intCast(p + m[0].len);
                return make(m[1], p, m[0].len);
            }
        }
        self.base.pos = @intCast(end);
        if (eql(w, "_") or eql(w, "nil")) return make(.kw_nil, p, w.len);
        return make(.word, p, w.len);
    }

    /// Inside an open action parenthesis at the end of a line: whether the
    /// next content line is indented (the action continues there). Skips
    /// blank and comment-only lines; moves the scan position when it does.
    fn continuesAction(self: *Lexer, pos: usize) bool {
        const s = self.src();
        var i = pos;
        while (i < s.len) {
            if (s[i] == '\n') i += 1;
            const lineBegin = i;
            while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\r')) i += 1;
            if (i >= s.len) return false;
            if (s[i] == '\n') continue;
            if (s[i] == '#') {
                while (i < s.len and s[i] != '\n') i += 1;
                continue;
            }
            if (i == lineBegin) return false;
            self.base.pos = @intCast(i);
            return true;
        }
        return false;
    }

    fn identPrefix(w: []const u8) ?usize {
        if (w.len == 0) return null;
        if (!(std.ascii.isAlphabetic(w[0]) or w[0] == '_')) return null;
        var n: usize = 1;
        while (n < w.len and (std.ascii.isAlphanumeric(w[n]) or w[n] == '_')) n += 1;
        return n;
    }

    fn allDigits(w: []const u8) bool {
        if (w.len == 0) return false;
        for (w) |ch| if (!std.ascii.isDigit(ch)) return false;
        return true;
    }

    fn isBlank(ch: u8) bool {
        return ch == ' ' or ch == '\t' or ch == '\r';
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};
