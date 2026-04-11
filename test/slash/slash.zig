//! Slash — Language module for the Slash shell
//!
//! Provides language-specific support for the generated parser:
//!   - Tag enum for s-expression node types
//!   - Keyword matching (CmdId, cmdAs)
//!   - Lexer wrapper (heredocs, indent/outdent, regex literals)
//!
//! Imported by parser.zig via @lang = "slash" directive.

const std = @import("std");
const parser = @import("parser.zig");
pub const Token = parser.Token;
pub const TokenCat = parser.TokenCat;
const BaseLexer = parser.BaseLexer;

// =============================================================================
// Tag Enum (s-expression node types)
// =============================================================================

pub const Tag = enum(u8) {
    @"!1",
    program,
    display,
    unset,
    assign_argv,
    append_argv,
    assign,
    seq,
    bg,
    @"and",
    @"or",
    xor,
    pipe_err,
    pipe,
    not,
    subshell,
    @"test",
    exit,
    @"break",
    @"continue",
    shift,
    source,
    exec,
    cmd,
    procsub_in,
    procsub_out,
    capture,
    redir_out,
    redir_append,
    redir_in,
    redir_err,
    redir_err_app,
    redir_both,
    redir_dup,
    redir_fd_dup,
    redir_fd_out,
    redir_fd_in,
    herestring,
    heredoc_literal,
    heredoc_interp,
    heredoc_lang,
    @"if",
    unless,
    @"else",
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    match,
    nomatch,
    @"for",
    @"while",
    until,
    list,
    @"try",
    arm,
    arm_else,
    block,
    cmd_missing,
    cmd_missing_del,
    cmd_missing_show,
    cmd_def,
    cmd_del,
    cmd_show,
    cmd_list,
    @"!2",
    key,
    key_del,
    key_list,
    key_combo_eq,
    set_reset,
    set,
    set_show,
    set_list,
    default,
    add,
    sub,
    mul,
    div,
    mod,
    pow,
    neg,
    shift_value,
    _,
};

// =============================================================================
// Keyword Matching
// =============================================================================

pub const CmdId = enum(u16) {
    IF,
    UNLESS,
    ELSE,
    FOR,
    IN,
    WHILE,
    UNTIL,
    TRY,
    AND,
    OR,
    NOT,
    XOR,
    CMD,
    KEY,
    SET,
    TEST,
    SOURCE,
    EXIT,
    BREAK,
    CONTINUE,
    SHIFT,
    EXEC,
};

const cmdMap = std.StaticStringMap(CmdId).initComptime(.{
    .{ "if", .IF },
    .{ "unless", .UNLESS },
    .{ "else", .ELSE },
    .{ "for", .FOR },
    .{ "in", .IN },
    .{ "while", .WHILE },
    .{ "until", .UNTIL },
    .{ "try", .TRY },
    .{ "and", .AND },
    .{ "or", .OR },
    .{ "not", .NOT },
    .{ "xor", .XOR },
    .{ "cmd", .CMD },
    .{ "key", .KEY },
    .{ "set", .SET },
    .{ "test", .TEST },
    .{ "source", .SOURCE },
    .{ "exit", .EXIT },
    .{ "break", .BREAK },
    .{ "continue", .CONTINUE },
    .{ "shift", .SHIFT },
    .{ "exec", .EXEC },
});

pub fn cmdAs(name: []const u8) ?CmdId {
    return cmdMap.get(name);
}

// =============================================================================
// Lexer (shell-specific wrapper around generated BaseLexer)
// =============================================================================

pub const Lexer = struct {
    base: BaseLexer,

    // Heredoc state
    hd_type: u8 = 0,
    hd_margin: u32 = 0,
    hd_scanned: bool = false,
    hd_buf: [255]Token = undefined,
    hd_buf_count: u8 = 0,
    hd_buf_pos: u8 = 0,
    pending_err: bool = false,

    // Indent state
    indent_level: u32 = 0,
    indent_stack: [64]u32 = .{0} ** 64,
    indent_depth: u8 = 0,
    indent_pending: u8 = 0,
    indent_queued: ?Token = null,
    indent_trailing_newline: bool = false,

    // Regex context
    last_cat: TokenCat = .eof,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
        self.hd_type = 0;
        self.hd_margin = 0;
        self.hd_scanned = false;
        self.hd_buf_count = 0;
        self.hd_buf_pos = 0;
        self.pending_err = false;
        self.indent_level = 0;
        self.indent_depth = 0;
        self.indent_pending = 0;
        self.indent_queued = null;
        self.indent_trailing_newline = false;
        self.last_cat = .eof;
    }

    // Expose source for external use
    pub fn getSource(self: *const Lexer) []const u8 {
        return self.base.source;
    }

    /// Sync lexer `math_lhs` guard state from the last emitted token (for grammar `@ math_lhs` rules).
    fn syncMathLhsFromLastCat(self: *Lexer) void {
        self.base.math_lhs = switch (self.last_cat) {
            .ident, .integer, .real, .variable, .var_braced, .rparen, .rbracket, .string_sq, .string_dq => 1,
            else => 0,
        };
    }

    pub fn next(self: *Lexer) Token {
        if (self.pending_err) {
            self.pending_err = false;
            return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }
        if (self.indent_queued) |q| {
            self.indent_queued = null;
            return q;
        }
        if (self.indent_pending > 0) {
            self.indent_pending -= 1;
            if (self.indent_pending == 0 and self.indent_trailing_newline) {
                self.indent_trailing_newline = false;
                self.indent_queued = Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            }
            return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }
        if (self.hd_type == 0 and self.hd_buf_pos < self.hd_buf_count) {
            const tok = self.hd_buf[self.hd_buf_pos];
            self.hd_buf_pos += 1;
            if (self.hd_buf_pos >= self.hd_buf_count) {
                self.hd_buf_count = 0;
                self.hd_buf_pos = 0;
            }
            return tok;
        }
        if (self.hd_type != 0) {
            return self.collectHeredocLine();
        }

        // Regex context check after =~ / !~
        var ws_skip: u32 = 0;
        while (self.base.pos + ws_skip < self.base.source.len and
            (self.base.source[self.base.pos + ws_skip] == ' ' or self.base.source[self.base.pos + ws_skip] == '\t'))
            ws_skip += 1;
        const rx_pos = self.base.pos + ws_skip;
        if (rx_pos < self.base.source.len) {
            const ch = self.base.source[rx_pos];
            const match_ctx = self.last_cat == .match or self.last_cat == .nomatch;
            const try_arm_ctx = self.last_cat == .lbrace or self.last_cat == .newline or self.last_cat == .indent;
            if (match_ctx) {
                if (ch == '~' and rx_pos + 1 < self.base.source.len) {
                    const d = self.base.source[rx_pos + 1];
                    if (!std.ascii.isAlphanumeric(d) and d != ' ' and d != '\t' and d != '\n') {
                        self.base.pos = rx_pos;
                        const result = self.collectRegex();
                        self.last_cat = result.cat;
                        return result;
                    }
                } else if (ch == '/') {
                    self.base.pos = rx_pos;
                    const result = self.collectRegexBare();
                    self.last_cat = result.cat;
                    return result;
                }
            } else if (try_arm_ctx and ch == '/' and self.looksLikeTryArmBareRegex(rx_pos)) {
                self.base.pos = rx_pos;
                const result = self.collectRegexBare();
                self.last_cat = result.cat;
                return result;
            }
        }

        // Standalone regex: ~<delim> where delim is not / or alnum (peek past whitespace)
        {
            var wp: u32 = self.base.pos;
            while (wp < self.base.source.len and (self.base.source[wp] == ' ' or self.base.source[wp] == '\t')) wp += 1;
            if (wp + 1 < self.base.source.len and self.base.source[wp] == '~') {
                const rd = self.base.source[wp + 1];
                if (!std.ascii.isAlphanumeric(rd) and rd != '/' and rd != ' ' and rd != '\t' and rd != '\n' and rd != '\r' and rd != '_') {
                    const ws_count: u8 = @intCast(@min(wp - self.base.pos, 255));
                    self.base.pos = wp;
                    var result = self.collectRegex();
                    result.pre = ws_count;
                    self.last_cat = result.cat;
                    return result;
                }
            }
        }

        self.syncMathLhsFromLastCat();
        var tok = self.base.matchRules();

        // Promote lparen to lparen_tight when no preceding whitespace
        if (tok.cat == .lparen and tok.pre == 0) {
            tok.cat = .lparen_tight;
        }

        // lparen_tight is meaningful after an ident or ??? (for cmd name(params) / cmd ???(name)).
        if (tok.cat == .lparen_tight and self.last_cat != .ident and self.last_cat != .missing) {
            tok.cat = .lparen;
        }

        // `=` enables math mode in the base lexer. If the first RHS token is a
        // bare word, this is a non-expression assignment form (shift value, key/set
        // command RHS), so disable math interception before later command args.
        if (self.base.math != 0 and self.last_cat == .assign and tok.cat == .ident) {
            self.base.math = 0;
        }

        self.last_cat = tok.cat;

        if (tok.cat == .newline) return self.handleIndent(tok);

        if (tok.cat == .eof and self.indent_depth > 0) {
            self.indent_pending = self.indent_depth;
            self.indent_depth = 0;
            self.indent_level = 0;
            self.indent_trailing_newline = true;
            return Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }

        if (tok.cat == .heredoc_sq or tok.cat == .heredoc_dq or tok.cat == .heredoc_bt) {
            self.hd_type = switch (tok.cat) {
                .heredoc_sq => 1,
                .heredoc_dq => 2,
                .heredoc_bt => 3,
                else => 0,
            };
            self.hd_margin = 0;
            self.hd_scanned = false;
            self.hd_buf_count = 0;
            self.hd_buf_pos = 0;
            self.syncMathLhsFromLastCat();
            while (true) {
                const t = self.base.matchRules();
                if (t.cat == .newline or t.cat == .eof) break;
                if (self.hd_buf_count < self.hd_buf.len) {
                    self.hd_buf[self.hd_buf_count] = t;
                    self.hd_buf_count += 1;
                } else {
                    self.pending_err = true;
                    break;
                }
            }
            return tok;
        }
        return tok;
    }

    fn collectHeredocLine(self: *Lexer) Token {
        if (self.base.pos >= self.base.source.len) {
            self.hd_type = 0;
            return Token{ .cat = .eof, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }
        var ws: u32 = 0;
        while (self.base.pos + ws < self.base.source.len and
            (self.base.source[self.base.pos + ws] == ' ' or self.base.source[self.base.pos + ws] == '\t'))
            ws += 1;
        const content_start = self.base.pos + ws;
        const delim: []const u8 = switch (self.hd_type) {
            1 => "'''",
            2 => "\"\"\"",
            3 => "```",
            else => "",
        };
        if (!self.hd_scanned) {
            self.hd_scanned = true;
            var scan = self.base.pos;
            while (scan < self.base.source.len) {
                var sws: u32 = 0;
                while (scan + sws < self.base.source.len and
                    (self.base.source[scan + sws] == ' ' or self.base.source[scan + sws] == '\t'))
                    sws += 1;
                const sc = scan + sws;
                if (sc + delim.len <= self.base.source.len and std.mem.eql(u8, self.base.source[sc..][0..delim.len], delim)) {
                    self.hd_margin = sws;
                    break;
                }
                while (scan < self.base.source.len and self.base.source[scan] != '\n') scan += 1;
                if (scan < self.base.source.len) scan += 1;
            }
        }
        if (content_start + delim.len <= self.base.source.len) {
            const candidate = self.base.source[content_start..][0..delim.len];
            if (std.mem.eql(u8, candidate, delim)) {
                const after = content_start + @as(u32, @intCast(delim.len));
                const is_closing = after >= self.base.source.len or
                    self.base.source[after] == '\n' or self.base.source[after] == ' ' or
                    self.base.source[after] == '\t' or self.base.source[after] == '|' or
                    self.base.source[after] == '\r' or self.base.source[after] == ';' or
                    self.base.source[after] == '&' or self.base.source[after] == '<' or
                    self.base.source[after] == '>' or self.base.source[after] == ')' or
                    self.base.source[after] == '}' or self.base.source[after] == '#';
                if (is_closing) {
                    const close_cat: TokenCat = switch (self.hd_type) {
                        1 => .heredoc_sq,
                        2 => .heredoc_dq,
                        3 => .heredoc_end,
                        else => .err,
                    };
                    self.base.pos = after;
                    self.hd_type = 0;
                    while (self.base.pos < self.base.source.len and
                        (self.base.source[self.base.pos] == ' ' or self.base.source[self.base.pos] == '\t'))
                        self.base.pos += 1;
                    if (self.base.pos < self.base.source.len and self.base.source[self.base.pos] != '\n' and self.base.source[self.base.pos] != '\r') {
                        self.syncMathLhsFromLastCat();
                        while (true) {
                            const t = self.base.matchRules();
                            if (t.cat == .newline) {
                                if (self.hd_buf_count < self.hd_buf.len) {
                                    self.hd_buf[self.hd_buf_count] = t;
                                    self.hd_buf_count += 1;
                                } else {
                                    self.pending_err = true;
                                }
                                break;
                            }
                            if (t.cat == .eof) break;
                            if (self.hd_buf_count < self.hd_buf.len) {
                                self.hd_buf[self.hd_buf_count] = t;
                                self.hd_buf_count += 1;
                            } else {
                                self.pending_err = true;
                                break;
                            }
                        }
                    }
                    return Token{ .cat = close_cat, .pre = @intCast(@min(ws, 255)), .pos = @intCast(content_start), .len = @intCast(delim.len) };
                }
            }
        }
        var line_end = self.base.pos;
        while (line_end < self.base.source.len and self.base.source[line_end] != '\n') line_end += 1;
        const strip = @min(ws, self.hd_margin);
        const body_start = self.base.pos + strip;
        const body_len = if (line_end > body_start) line_end - body_start else 0;
        self.base.pos = line_end;
        if (self.base.pos < self.base.source.len and self.base.source[self.base.pos] == '\n') self.base.pos += 1;
        return Token{ .cat = .heredoc_body, .pre = 0, .pos = @intCast(body_start), .len = @intCast(body_len) };
    }

    fn handleIndent(self: *Lexer, nl_tok: Token) Token {
        // Suppress indentation semantics inside grouping constructs
        if (self.base.paren > 0 or self.base.brace > 0) return nl_tok;

        var ws: u32 = 0;
        while (self.base.pos + ws < self.base.source.len) {
            const ch = self.base.source[self.base.pos + ws];
            if (ch == ' ' or ch == '\t') {
                ws += 1;
            } else break;
        }
        if (self.base.pos + ws >= self.base.source.len or self.base.source[self.base.pos + ws] == '\n' or
            self.base.source[self.base.pos + ws] == '\r' or self.base.source[self.base.pos + ws] == '#')
            return nl_tok;
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
                self.indent_pending = count;
                self.indent_trailing_newline = !self.nextTokenIsElse();
                return nl_tok;
            }
            return nl_tok;
        }
        return nl_tok;
    }

    fn nextTokenIsElse(self: *const Lexer) bool {
        var probe = self.base;
        probe.math_lhs = switch (self.last_cat) {
            .ident, .integer, .real, .variable, .var_braced, .rparen, .rbracket, .string_sq, .string_dq => 1,
            else => 0,
        };
        const tok = probe.matchRules();
        return tok.cat == .ident and std.mem.eql(u8, probe.text(tok), "else");
    }

    fn collectRegexBare(self: *Lexer) Token {
        return self.scanRegex(self.base.pos);
    }

    fn collectRegex(self: *Lexer) Token {
        const start = self.base.pos;
        self.base.pos += 1;
        const result = self.scanRegex(start);
        if (result.cat == .err) self.base.pos = start + 1;
        return result;
    }

    fn scanRegex(self: *Lexer, start: u32) Token {
        const delim = self.base.source[self.base.pos];
        self.base.pos += 1;
        var in_class = false;
        while (self.base.pos < self.base.source.len) {
            const ch = self.base.source[self.base.pos];
            if (ch == '\\' and self.base.pos + 1 < self.base.source.len) {
                self.base.pos += 2;
                continue;
            }
            if (ch == '[' and !in_class) {
                in_class = true;
                self.base.pos += 1;
                continue;
            }
            if (ch == ']' and in_class) {
                in_class = false;
                self.base.pos += 1;
                continue;
            }
            if (ch == delim and !in_class) {
                self.base.pos += 1;
                while (self.base.pos < self.base.source.len) {
                    const f = self.base.source[self.base.pos];
                    if (f == 'i') {
                        self.base.pos += 1;
                    } else break;
                }
                return Token{ .cat = .regex, .pre = 0, .pos = @intCast(start), .len = @intCast(self.base.pos - start) };
            }
            if (ch == '\n') break;
            self.base.pos += 1;
        }
        return Token{ .cat = .err, .pre = 0, .pos = @intCast(start), .len = 1 };
    }

    fn looksLikeTryArmBareRegex(self: *const Lexer, start: u32) bool {
        if (start >= self.base.source.len or self.base.source[start] != '/') return false;
        var p = start + 1;
        var in_class = false;
        while (p < self.base.source.len) {
            const ch = self.base.source[p];
            if (ch == '\\' and p + 1 < self.base.source.len) {
                p += 2;
                continue;
            }
            if (ch == '[' and !in_class) {
                in_class = true;
                p += 1;
                continue;
            }
            if (ch == ']' and in_class) {
                in_class = false;
                p += 1;
                continue;
            }
            if (ch == '/' and !in_class) {
                p += 1;
                while (p < self.base.source.len and self.base.source[p] == 'i') p += 1;
                while (p < self.base.source.len and (self.base.source[p] == ' ' or self.base.source[p] == '\t')) p += 1;
                if (p >= self.base.source.len) return false;
                const next_ch = self.base.source[p];
                return next_ch == '{' or next_ch == '\n' or next_ch == '\r' or next_ch == '#';
            }
            if (ch == '\n' or ch == '\r') return false;
            p += 1;
        }
        return false;
    }
};

pub fn lineNeedsContinuation(line: []const u8) bool {
    const trimmed = std.mem.trimRight(u8, line, " \t");
    if (trimmed.len == 0) return false;

    var lex = Lexer.init(trimmed);
    var sig_count: usize = 0;
    var first_text: []const u8 = "";
    var last_text: []const u8 = "";
    var last_cat: TokenCat = .eof;
    var saw_lbrace = false;
    var saw_unterminated_quote = false;

    while (true) {
        const tok = lex.next();
        switch (tok.cat) {
            .eof => break,
            .comment, .newline => continue,
            .lbrace => saw_lbrace = true,
            .err => {
                const text = lex.text(tok);
                if (text.len == 1 and (text[0] == '"' or text[0] == '\'')) {
                    saw_unterminated_quote = true;
                    break;
                }
            },
            else => {},
        }
        if (sig_count == 0) first_text = lex.text(tok);
        sig_count += 1;
        last_cat = tok.cat;
        last_text = lex.text(tok);
    }

    if (saw_unterminated_quote) return true;
    if (lex.base.paren > 0 or lex.base.brace > 0) return true;

    switch (last_cat) {
        .backslash,
        .pipe,
        .pipe_err,
        .and_sym,
        .or_sym,
        .plus,
        .minus,
        .star,
        .slash,
        .percent,
        .power,
        .assign,
        .default_op,
        .match,
        .nomatch,
        .comma,
        .heredoc_sq,
        .heredoc_dq,
        .heredoc_bt,
        => return true,
        else => {},
    }

    if (!saw_lbrace) {
        if (std.mem.eql(u8, first_text, "if") or
            std.mem.eql(u8, first_text, "unless") or
            std.mem.eql(u8, first_text, "for") or
            std.mem.eql(u8, first_text, "while") or
            std.mem.eql(u8, first_text, "until") or
            std.mem.eql(u8, first_text, "try") or
            std.mem.eql(u8, first_text, "else"))
        {
            return true;
        }
    }

    if (std.mem.eql(u8, first_text, "cmd") and last_cat == .rparen) return true;
    if (std.mem.eql(u8, first_text, "cmd") and sig_count == 2 and (last_cat == .ident or last_cat == .missing)) return true;
    if (std.mem.eql(u8, last_text, "else")) return true;

    return false;
}

test "lineNeedsContinuation recognizes trailing minus operator" {
    try std.testing.expect(lineNeedsContinuation("= 1 -"));
    try std.testing.expect(!lineNeedsContinuation("= 1 - 2"));
}
