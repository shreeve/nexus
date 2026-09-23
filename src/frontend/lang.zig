//! lang.zig: the @lang module of the self-hosted frontend (parser.zig).
//!
//! Provides the Tag enum of the frontend's S-expression tree and the Lexer
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
//!   - Comments. Trailing comments are dropped, except inside a
//!     `@conflicts` block, where the trailing comment of an entry is its
//!     rationale and is kept as a `comment` token.
//!   - Unicode: `→` is an arrow, `ε` an epsilon (the empty right-hand side
//!     in `@conflicts` entries).
//!   - Words. An identifier immediately followed by `:` is a `label`
//!     (`role:element`, `expr: "expression"`); the colon is consumed.
//!     Capitalized words are `token`s. `X` followed by a one-character
//!     string literal is the next-char hint keyword `kw_x`. `L` immediately
//!     followed by `(` is the list keyword `kw_list`. The word after a `@`
//!     is a directive keyword; `left right none` are keywords inside an
//!     `@infix` block, `over` inside `@conflicts`, `via` in an `@as` line.
//!     Inside `@schema` a `|` written without a space before it joins a
//!     type union (`union`); `|` after a space starts the side-band roles.
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

/// The tags of the frontend tree; see the schema at the top of nexus.grammar.
pub const Tag = enum(u8) {
    grammar,

    // Directives
    lang,
    conflicts,
    manifest,
    conflict,
    crule,
    as,
    as_entry,
    op,
    op_map,
    errors,
    display,
    name_pair,
    infix,
    level,
    infix_op,
    schema,
    kind_decl,
    kinds,
    roles,
    role,
    type,
    tagset,
    sides,
    tags,
    trivia,
    repair,
    repair_line,

    // Rules and alternatives
    rule,
    start,
    name,
    alt,

    // Kind discriminators and flags
    perm, // (as_entry perm IDENT)       permissive @as
    reduce, // (alt reduce ...)          `<` hint
    shift, // (alt shift ...)            `>` hint
    many, // (group many ...)            `[X ...]`
    rest, // (role rest NAME ...)        `...name`
    wrapper, // (kind_decl ... wrapper)  `@wrapper`

    // Elements
    ref,
    tok,
    lit,
    at_ref,
    list_req,
    group,
    quantified,
    skip,
    skip_q,
    exclude,
    label,

    // List-inner shapes
    plain,
    opt_items,
    sep_items,
    opt_items_nosep,

    // Quantifiers (opt is also the `[X]` group kind and the optional-role flag)
    opt,
    zero_plus,
    one_plus,

    // Actions
    pos,
    spread,
    symid,
    null,
    tag,
    named,
    node,
    list,
    keep,
};

pub const Lexer = struct {
    base: BaseLexer,
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
    /// A token scanned ahead of the one being returned.
    pending: ?Token = null,
    /// Position of the last line break, for the `newline` before `eof`.
    lastBreak: ?u32 = null,

    const Mode = enum { normal, action };
    const Block = enum { none, as, conflicts, infix, schema, other };

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
        if (self.pending) |tok| {
            self.pending = null;
            return self.emit(tok);
        }
        while (true) {
            const tok = (if (self.mode == .action) self.scanAction() else self.scanNormal()) orelse continue;
            return self.emit(tok);
        }
    }

    fn src(self: *const Lexer) []const u8 {
        return self.base.source;
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
        return tok;
    }

    // --- Normal mode -------------------------------------------------------

    /// One token in normal mode, or null when the scanned input produced no
    /// token (a dropped comment, a line break inside brackets).
    fn scanNormal(self: *Lexer) ?Token {
        const s = self.src();
        // Unicode arrow and epsilon are not in the generated lexer.
        var p = self.base.pos;
        while (p < s.len and (s[p] == ' ' or s[p] == '\t' or s[p] == '\r')) p += 1;
        if (p + 2 < s.len and s[p] == 0xE2 and s[p + 1] == 0x86 and s[p + 2] == 0x92) {
            self.base.pos = @intCast(p + 3);
            return self.arrow(make(.arrow, p, 3));
        }
        if (p + 1 < s.len and s[p] == 0xCE and s[p + 1] == 0xB5) {
            self.base.pos = @intCast(p + 2);
            return make(.epsilon, p, 2);
        }

        var tok = self.base.matchRules();
        switch (tok.cat) {
            .newline => return self.lineBreak(tok.pos),
            .eof => {
                if (!self.atStart and !self.afterLayout) {
                    self.pending = tok;
                    return make(.newline, self.lastBreak orelse tok.pos, if (self.lastBreak != null) 1 else 0);
                }
                return tok;
            },
            .comment => {
                if (self.block == .conflicts and !self.lineStart) return tok;
                return null;
            },
            .ident => tok.cat = self.classifyWord(tok),
            .lbracket => self.bracketDepth += 1,
            .rbracket => {
                if (self.bracketDepth > 0) self.bracketDepth -= 1;
            },
            .arrow => return self.arrow(tok),
            .pipe => if (self.block == .schema and tok.pos > 0 and !isBlank(s[tok.pos - 1])) {
                tok.cat = .@"union";
            },
            .at => if (self.lineStart) {
                // A directive: its keyword decides the block context.
                self.block = .other;
            },
            else => {},
        }
        return tok;
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
            .conflicts => if (eql(t, "over")) return .kw_over,
            .as => if (eql(t, "via")) return .kw_via,
            else => {},
        }
        if (t[0] >= 'A' and t[0] <= 'Z') return .token;
        return .ident;
    }

    fn directiveKeyword(t: []const u8) ?TokenCat {
        const map = [_]struct { []const u8, TokenCat }{
            .{ "lang", .kw_lang },         .{ "conflicts", .kw_conflicts },
            .{ "as", .kw_as },             .{ "op", .kw_op },
            .{ "errors", .kw_errors },     .{ "display", .kw_display },
            .{ "infix", .kw_infix },       .{ "schema", .kw_schema },
            .{ "tags", .kw_tags },         .{ "trivia", .kw_trivia },
            .{ "repair", .kw_repair },     .{ "wrapper", .kw_wrapper },
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
