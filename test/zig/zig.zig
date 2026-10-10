//! @lang module for zig.grammar.
const std = @import("std");
const parser = @import("parser.zig");
const Token = parser.Token;
const Cat = parser.TokenCat;

/// The generated lexer, starting after a UTF-8 byte order mark at offset 0
/// (std.zig.Tokenizer.init skips it; no lexer rule can see the start of
/// the input), with the decisions Parse.zig makes by looking at more than
/// the next token, or at the bytes around one, given as token categories
/// of their own. It only renames tokens; their bytes are the base lexer's.
///
///   label             an identifier followed by `:` and then `{`, `while`,
///                     `for`, `inline` or `switch`, except after `.` or a
///                     break label's `:` (parsePrimaryExpr,
///                     parsePrimaryTypeExpr, parseBlockExpr,
///                     parseLabeledStatement look two tokens ahead)
///   break_colon       the `:` after `break` or `continue` when an
///                     identifier follows (parseBreakLabel)
///   ptr_star          a `*` right after `[`: a many-item or C pointer
///                     `[*]T`, `[*c]T`, `[*:s]T` (parseTypeExpr)
///   c_ptr             after `[` ptr_star, an identifier `c` followed by
///                     nothing but whitespace and then `]` (parseTypeExpr
///                     compares the source up to the next token, trimmed)
///   enum_tag          `enum` right after `union (` (expectContainerDeclAuto)
///   bad_doc_comment   a doc comment on the line of the token before it
///                     (same_line_doc_comment)
///   minus_prefix, minus_percent_prefix, ampersand_prefix, asterisk_prefix,
///   pipe_payload, bad_operator
///                     a binary operator with whitespace on one side only
///                     (mismatched_binary_op_whitespace), or an `&` right
///                     before `&` (invalid_ampersand_ampersand). Such a
///                     token can only be a prefix operator, a pointer's
///                     star or a payload's bar; any other one is
///                     bad_operator, which the grammar never takes.
pub const Lexer = struct {
    base: parser.BaseLexer,
    /// Tokens read from `base` ahead of the one returned: ahead[0..n].
    ahead: [2]Token = undefined,
    n: u8 = 0,
    /// The categories of the last two tokens returned (`eof`: none) and the
    /// start of the last one.
    prev: Cat = .eof,
    prev2: Cat = .eof,
    prev_pos: u32 = 0,

    pub fn init(source: []const u8) Lexer {
        var base = parser.BaseLexer.init(source);
        if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) base.pos = 3;
        return .{ .base = base };
    }

    pub fn next(self: *Lexer) parser.Token {
        var tok = self.take();
        tok.cat = self.classify(tok);
        self.prev2 = self.prev;
        self.prev = tok.cat;
        self.prev_pos = tok.pos;
        return tok;
    }

    fn take(self: *Lexer) Token {
        if (self.n == 0) return self.base.next();
        const tok = self.ahead[0];
        self.ahead[0] = self.ahead[1];
        self.n -= 1;
        return tok;
    }

    /// The category of the token `i` places after the one being classified.
    fn peek(self: *Lexer, i: u8) Cat {
        while (self.n <= i) : (self.n += 1) self.ahead[self.n] = self.base.next();
        return self.ahead[i].cat;
    }

    fn classify(self: *Lexer, tok: Token) Cat {
        const src = self.base.source;
        switch (tok.cat) {
            .identifier => {
                if (self.prev == .ptr_star and self.prev2 == .l_bracket) {
                    if (self.peek(0) != .r_bracket) return .identifier;
                    const end = self.ahead[0].pos;
                    const text = std.mem.trimEnd(u8, src[tok.pos..end], &std.ascii.whitespace);
                    return if (std.mem.eql(u8, text, "c")) .c_ptr else .identifier;
                }
                if (self.prev == .period or self.prev == .break_colon) return .identifier;
                if (self.peek(0) != .colon) return .identifier;
                return switch (self.peek(1)) {
                    .l_brace, .keyword_while, .keyword_for, .keyword_inline, .keyword_switch => .label,
                    else => .identifier,
                };
            },
            .colon => {
                if (self.prev != .keyword_break and self.prev != .keyword_continue) return .colon;
                return if (self.peek(0) == .identifier) .break_colon else .colon;
            },
            .keyword_enum => {
                return if (self.prev == .l_paren and self.prev2 == .keyword_union) .enum_tag else .keyword_enum;
            },
            .doc_comment => {
                if (self.prev == .eof) return .doc_comment;
                const between = src[self.prev_pos..tok.pos];
                return if (std.mem.findScalar(u8, between, '\n') == null) .bad_doc_comment else .doc_comment;
            },
            .asterisk => {
                if (self.prev == .l_bracket) return .ptr_star;
                return spacing(src, tok);
            },
            .keyword_or,
            .keyword_and,
            .equal_equal,
            .bang_equal,
            .angle_bracket_left,
            .angle_bracket_right,
            .angle_bracket_left_equal,
            .angle_bracket_right_equal,
            .ampersand,
            .caret,
            .pipe,
            .keyword_orelse,
            .keyword_catch,
            .angle_bracket_angle_bracket_left,
            .angle_bracket_angle_bracket_left_pipe,
            .angle_bracket_angle_bracket_right,
            .plus,
            .minus,
            .plus_plus,
            .plus_percent,
            .minus_percent,
            .plus_pipe,
            .minus_pipe,
            .pipe_pipe,
            .slash,
            .percent,
            .asterisk_percent,
            .asterisk_pipe,
            => return spacing(src, tok),
            else => return tok.cat,
        }
    }

    /// A binary operator's category by the bytes around it, as
    /// Parse.zig parseExprPrecedence checks them.
    fn spacing(src: []const u8, tok: Token) Cat {
        const end = @as(usize, tok.pos) + tok.len;
        if (tok.cat == .ampersand and end < src.len and src[end] == '&') return .ampersand_prefix;
        const before = tok.pos == 0 or std.ascii.isWhitespace(src[tok.pos - 1]);
        const after = end >= src.len or std.ascii.isWhitespace(src[end]);
        if (before == after) return tok.cat;
        return switch (tok.cat) {
            .minus => .minus_prefix,
            .minus_percent => .minus_percent_prefix,
            .ampersand => .ampersand_prefix,
            .asterisk => .asterisk_prefix,
            .pipe => .pipe_payload,
            else => .bad_operator,
        };
    }
};
