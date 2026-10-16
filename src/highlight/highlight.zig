//! highlight.zig: the `@highlight` directive, read against the lexer spec.
//!
//! Each line of the block is a metadata line (`language "Rig"`,
//! `scope-name source.rig`, `word-chars [A-Za-z0-9_]`, ...) or an entry,
//! `SCOPE text`: a list of literals, token names and `@keywords` groups,
//! or one pattern (with `scope:( ... )` captures at its top level),
//! followed by contexts (`after P`, `not after P`, `before P`,
//! `not before P`, `line-start`, `line-end`), which bind to the whole
//! entry, and `within TOKEN`. `analyze` checks every line (each mistake is a
//! located error) and orders what the editor files match: `Highlight.items`
//! (emit.zig writes them in each format).
//!
//! The order: entries with a pattern, a context, `line-start` or
//! `line-end`, as written; then literals and `@keywords` words, longest
//! first; then a run of blanks, uncoloured; then every lexer rule in lexer
//! order: a listed token's coloured, any other uncoloured, so that no
//! later entry colours part of its text. A token named by `within` is a
//! region (begin, body, end), which matches the entries within it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const diag = @import("../diag.zig");
const grammar = @import("../grammar.zig");
const regex = @import("../lexgen/regex.zig");
const render = @import("render.zig");
const Rx = render.Rx;
const Look = render.Look;
const Node = regex.Node;

/// The scopes an entry may name, each with its name in a TextMate
/// grammar (followed by `.` and the language id), a highlight.js
/// definition and a Vim syntax file (the default group it links to).
pub const Scope = enum {
    keyword,
    keyword_control,
    keyword_operator,
    constant,
    constant_numeric,
    constant_symbol,
    string,
    string_escape,
    comment,
    operator,
    punctuation,
    type,
    function,
    function_builtin,
    label,
    storage_modifier,
    variable_parameter,
    variable_special,
    invalid,

    pub const Names = struct { name: []const u8, textmate: []const u8, hljs: []const u8, vim: []const u8 };

    pub fn names(self: Scope) Names {
        return table[@backingInt(self)];
    }

    const table = [_]Names{
        .{ .name = "keyword", .textmate = "keyword.other", .hljs = "keyword", .vim = "Keyword" },
        .{ .name = "keyword.control", .textmate = "keyword.control", .hljs = "keyword", .vim = "Statement" },
        .{ .name = "keyword.operator", .textmate = "keyword.operator.word", .hljs = "keyword", .vim = "Operator" },
        .{ .name = "constant", .textmate = "constant.language", .hljs = "literal", .vim = "Constant" },
        .{ .name = "constant.numeric", .textmate = "constant.numeric", .hljs = "number", .vim = "Number" },
        .{ .name = "constant.symbol", .textmate = "constant.other.symbol", .hljs = "symbol", .vim = "Constant" },
        .{ .name = "string", .textmate = "string.quoted", .hljs = "string", .vim = "String" },
        .{ .name = "string.escape", .textmate = "constant.character.escape", .hljs = "char.escape", .vim = "SpecialChar" },
        .{ .name = "comment", .textmate = "comment", .hljs = "comment", .vim = "Comment" },
        .{ .name = "operator", .textmate = "keyword.operator", .hljs = "operator", .vim = "Operator" },
        .{ .name = "punctuation", .textmate = "punctuation", .hljs = "punctuation", .vim = "Delimiter" },
        .{ .name = "type", .textmate = "entity.name.type", .hljs = "type", .vim = "Type" },
        .{ .name = "function", .textmate = "entity.name.function", .hljs = "title.function", .vim = "Function" },
        .{ .name = "function.builtin", .textmate = "support.function", .hljs = "built_in", .vim = "Function" },
        .{ .name = "label", .textmate = "entity.name.label", .hljs = "symbol", .vim = "Label" },
        .{ .name = "storage.modifier", .textmate = "storage.modifier", .hljs = "keyword", .vim = "StorageClass" },
        .{ .name = "variable.parameter", .textmate = "variable.parameter", .hljs = "params", .vim = "Identifier" },
        .{ .name = "variable.special", .textmate = "variable.language", .hljs = "variable.language", .vim = "Identifier" },
        .{ .name = "invalid", .textmate = "invalid.illegal", .hljs = "deletion", .vim = "Error" },
    };

    pub fn parse(text: []const u8) ?Scope {
        for (table, 0..) |n, i| if (std.mem.eql(u8, n.name, text)) return @fromBackingInt(@intCast(i));
        return null;
    }
};

pub const Highlight = struct {
    language: []const u8,
    scopeName: []const u8,
    /// The last part of `scopeName`: the suffix of TextMate scopes, the
    /// prefix of Vim groups, highlight.js's language name.
    id: []const u8,
    extensions: []const []const u8,
    lineComment: ?[]const u8 = null,
    blockComment: ?[2][]const u8 = null,
    /// VS Code's indentation rules: lines that indent the next line, and
    /// lines that outdent themselves.
    indent: ?Pattern = null,
    dedent: ?Pattern = null,
    /// The characters of words: a literal that starts or ends with one
    /// does not match next to another.
    wordChars: regex.ByteSet = render.defaultWordChars,
    /// The entries as written.
    entries: []const Entry,
    /// What the editor files match outside every region, first to last.
    items: []const Item,
};

/// A pattern with its contexts: what `indent` and `dedent` give.
pub const Pattern = struct {
    lineStart: bool,
    lineEnd: bool,
    looks: []const Context,
    core: *const Node,
};

pub const Context = struct {
    kind: Look,
    text: []const u8,
    node: *const Node,
};

/// One entry line, as written (for `--describe`).
pub const Entry = struct {
    scope: Scope,
    line: u32,
    /// Literal targets, their escapes decoded.
    literals: []const []const u8 = &.{},
    /// Token targets, as written (`STRING`).
    tokens: []const []const u8 = &.{},
    groups: []const []const u8 = &.{},
    /// A pattern target: its text, and its parts (one, uncaptured, when it
    /// has no captures).
    pattern: ?[]const u8 = null,
    pieces: []const Piece = &.{},
    lineStart: bool = false,
    lineEnd: bool = false,
    contexts: []const Context = &.{},
    /// `within TOKEN`, as written.
    within: ?[]const u8 = null,
};

/// A part of a match with its scope: a capture, or a part between
/// captures (the entry's scope).
pub const Piece = struct {
    scope: Scope,
    captured: bool,
    rx: Rx,
};

pub const Item = union(enum) {
    match: Match,
    region: Region,
    /// Text matched to keep it from later items, uncoloured: blanks, and
    /// the rules of tokens no entry lists.
    plain: Plain,
};

pub const Plain = struct {
    rx: Rx,
    /// A rule's trailing context.
    looks: []const Context,
};

pub const Match = struct {
    /// One piece, or the parts of a pattern with captures.
    pieces: []const Piece,
    lineStart: bool,
    lineEnd: bool,
    looks: []const Context,
};

/// A token matched in parts: `begin` (its pattern's literal prefix), the
/// entries within it and its `body` (one repetition of what lies between
/// prefix and suffix), each tried before `end` (its suffix).
pub const Region = struct {
    scope: ?Scope,
    /// The token as written in `within` (`STRING_DQ`).
    token: []const u8,
    begin: []const u8,
    end: Rx,
    body: ?Rx,
    items: []const Item,
};

pub const Error = error{ HighlightError, OutOfMemory };

/// Reads `@highlight` (`lines`) against the lexer spec and the keyword
/// groups; the first mistake is reported and returned as HighlightError.
pub fn analyze(
    allocator: Allocator,
    lines: grammar.HighlightLines,
    spec: *const grammar.LexerSpec,
    groups: []const grammar.KeywordGroup,
    source: diag.Source,
) Error!Highlight {
    var a: Analyzer = .{ .allocator = allocator, .spec = spec, .groups = groups, .source = source };
    return a.run(lines);
}

const empty: Node = .empty;
const blank: Node = .{ .set = blk: {
    var s = regex.ByteSet.single(' ');
    s.add('\t');
    break :blk s;
} };
const blanks: Node = .{ .repeat = .{ .sub = &blank, .min = 1, .max = null } };

const Analyzer = struct {
    allocator: Allocator,
    spec: *const grammar.LexerSpec,
    groups: []const grammar.KeywordGroup,
    source: diag.Source,

    /// The entries, with what the ordering needs of each.
    entries: std.ArrayList(Entry) = .empty,
    built: std.ArrayList(Built) = .empty,
    /// Each target's key (`T:token`, `L:bytes`, `G:group`, then `@within`)
    /// and the entry that lists it.
    seen: std.StringHashMapUnmanaged(usize) = .empty,
    /// Every lexer rule's pattern (empty for a zero-width rule); the
    /// lowerer has parsed each one.
    patterns: []const regex.Pattern = &.{},
    /// The line being read: offsets into its text locate errors.
    line: grammar.HighlightLines.Line = undefined,
    /// `word-chars`, or the default.
    wordChars: regex.ByteSet = render.defaultWordChars,

    const Built = struct {
        entry: usize,
        pos: u32,
        /// Literal targets and `@keywords` words.
        literals: []const render.Literal,
        /// Token targets: TokenCat names.
        tokens: []const []const u8,
        /// The pattern target's pieces; empty without one.
        pieces: []const Piece,
        contextual: bool,
    };

    /// The grammar-file offset of `offset` in the current line's text.
    fn at(self: *const Analyzer, offset: usize) u32 {
        return self.line.at(offset);
    }

    fn fail(self: *const Analyzer, pos: usize, comptime fmt: []const u8, args: anytype) Error {
        diag.errAt(self.source, pos, fmt, args);
        return error.HighlightError;
    }

    fn run(self: *Analyzer, lines: grammar.HighlightLines) Error!Highlight {
        const patterns = try self.allocator.alloc(regex.Pattern, self.spec.rules.items.len);
        for (self.spec.rules.items, patterns) |rule, *p| {
            var d: regex.Diagnostic = .{};
            p.* = if (rule.pattern.len == 0) .{ .main = &empty } else regex.parse(self.allocator, rule.pattern, &d) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidPattern => unreachable,
            };
        }
        self.patterns = patterns;
        var meta: Meta = .{};
        for (lines.lines) |line| {
            self.line = line;
            if (Scope.parse(line.key)) |scope| {
                try self.entry(scope, line);
            } else if (metaKey(line.key)) |key| {
                try self.metaLine(&meta, key, line);
            } else {
                return self.fail(line.keyPos, "`{s}` is neither a scope nor a metadata key of @highlight (scopes: " ++ scopeList ++ "; metadata: " ++ metaList ++ ")", .{line.key});
            }
        }
        const language = meta.language orelse return self.fail(lines.pos, "@highlight needs `language \"Name\"`, the language's name in editors", .{});
        const scopeName = meta.scopeName orelse return self.fail(lines.pos, "@highlight needs `scope-name source.x`, the TextMate scope of the language", .{});
        const extensions = meta.extensions orelse return self.fail(lines.pos, "@highlight needs `extensions x ...`, the file extensions of the language", .{});
        if ((meta.indent == null) != (meta.dedent == null)) {
            const given = meta.indentPos orelse meta.dedentPos.?;
            return self.fail(given, "`indent` and `dedent` go together: VS Code's indentation rules need both", .{});
        }
        if (self.entries.items.len == 0) return self.fail(lines.pos, "@highlight lists no entries: give at least one `scope target ...` line", .{});
        try self.checkRegions();
        const items = try self.order(null);
        return .{
            .language = language,
            .scopeName = scopeName,
            .id = scopeName[std.mem.findScalarLast(u8, scopeName, '.').? + 1 ..],
            .extensions = extensions,
            .lineComment = meta.lineComment,
            .blockComment = meta.blockComment,
            .indent = meta.indent,
            .dedent = meta.dedent,
            .wordChars = self.wordChars,
            .entries = try self.entries.toOwnedSlice(self.allocator),
            .items = items,
        };
    }

    // --- Metadata ---------------------------------------------------------

    const scopeList = "keyword, keyword.control, keyword.operator, constant, constant.numeric, constant.symbol, string, string.escape, comment, operator, punctuation, type, function, function.builtin, label, storage.modifier, variable.parameter, variable.special, invalid";
    const metaList = "language, scope-name, extensions, line-comment, block-comment, indent, dedent, word-chars";

    const MetaKey = enum { language, scope_name, extensions, line_comment, block_comment, indent, dedent, word_chars };

    fn metaKey(text: []const u8) ?MetaKey {
        const keys = [_]struct { []const u8, MetaKey }{
            .{ "language", .language },           .{ "scope-name", .scope_name },
            .{ "extensions", .extensions },       .{ "line-comment", .line_comment },
            .{ "block-comment", .block_comment }, .{ "indent", .indent },
            .{ "dedent", .dedent },               .{ "word-chars", .word_chars },
        };
        for (keys) |k| if (std.mem.eql(u8, k[0], text)) return k[1];
        return null;
    }

    const Meta = struct {
        language: ?[]const u8 = null,
        scopeName: ?[]const u8 = null,
        extensions: ?[]const []const u8 = null,
        lineComment: ?[]const u8 = null,
        blockComment: ?[2][]const u8 = null,
        indent: ?Pattern = null,
        dedent: ?Pattern = null,
        indentPos: ?u32 = null,
        dedentPos: ?u32 = null,
        given: std.EnumSet(MetaKey) = .empty,
    };

    fn metaLine(self: *Analyzer, meta: *Meta, key: MetaKey, line: grammar.HighlightLines.Line) Error!void {
        if (meta.given.contains(key)) return self.fail(line.keyPos, "duplicate `{s}` in @highlight", .{line.key});
        meta.given.insert(key);
        if (line.text.len == 0) return self.fail(line.keyPos, "`{s}` needs a value", .{line.key});
        switch (key) {
            .indent, .dedent => {
                const p = try self.pattern(line);
                if (key == .indent) {
                    meta.indent = p;
                    meta.indentPos = line.keyPos;
                } else {
                    meta.dedent = p;
                    meta.dedentPos = line.keyPos;
                }
                return;
            },
            .word_chars => {
                const node = try self.parsePattern(line.text, 0);
                if (node.* != .set)
                    return self.fail(self.at(0), "`word-chars` takes one character class: word-chars [A-Za-z0-9_]", .{});
                if (render.checkEditor(.{ .node = node })) |problem|
                    return self.fail(self.at(0), "this pattern has no editor form: it matches {s}", .{problem});
                self.wordChars = node.set;
                return;
            },
            else => {},
        }
        const words = try self.metaWords(line);
        const want: usize = switch (key) {
            .block_comment => 2,
            .extensions => 0,
            else => 1,
        };
        if (want > 0 and words.len != want)
            return self.fail(self.at(0), "`{s}` takes {s}", .{ line.key, switch (key) {
                .language => "one string, the language's name: language \"Name\"",
                .scope_name => "one name: scope-name source.x",
                .line_comment => "one string: line-comment \"#\"",
                .block_comment => "two strings: block-comment \"/*\" \"*/\"",
                else => unreachable,
            } });
        switch (key) {
            .language, .line_comment, .block_comment => for (words) |w| {
                if (!w.quoted) return self.fail(w.pos, "`{s}` takes strings: quote '{s}'", .{ line.key, w.text });
                if (w.text.len == 0) return self.fail(w.pos, "`{s}` takes a string that is not empty", .{line.key});
            },
            .scope_name, .extensions => for (words) |w| if (w.quoted) return self.fail(w.pos, "`{s}` takes names, not strings", .{line.key}),
            else => unreachable,
        }
        switch (key) {
            .language => meta.language = words[0].text,
            .line_comment => meta.lineComment = words[0].text,
            .block_comment => meta.blockComment = .{ words[0].text, words[1].text },
            .scope_name => {
                const name = words[0].text;
                if (!validScopeName(name))
                    return self.fail(words[0].pos, "scope name `{s}` is not `source.x` or `text.x` (lowercase letters, digits and `_` in each dot-separated part)", .{name});
                meta.scopeName = name;
            },
            .extensions => {
                var list: std.ArrayList([]const u8) = .empty;
                for (words) |w| {
                    if (w.text[0] == '.' or std.mem.findAny(u8, w.text, "/\\*") != null)
                        return self.fail(w.pos, "extension `{s}` is a file name ending without its dot, as in `extensions rig`", .{w.text});
                    for (list.items) |o| if (std.mem.eql(u8, o, w.text)) return self.fail(w.pos, "extension `{s}` is given twice", .{w.text});
                    try list.append(self.allocator, w.text);
                }
                meta.extensions = try list.toOwnedSlice(self.allocator);
            },
            else => unreachable,
        }
    }

    fn validScopeName(name: []const u8) bool {
        if (!std.mem.startsWith(u8, name, "source.") and !std.mem.startsWith(u8, name, "text.")) return false;
        var parts = std.mem.splitScalar(u8, name, '.');
        while (parts.next()) |part| {
            if (part.len == 0 or !std.ascii.isLower(part[0])) return false;
            for (part) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
        }
        return true;
    }

    const Word = struct { text: []const u8, quoted: bool, pos: u32 };

    /// The blank-separated words of a metadata value: strings (decoded)
    /// and names.
    fn metaWords(self: *Analyzer, line: grammar.HighlightLines.Line) Error![]const Word {
        var words: std.ArrayList(Word) = .empty;
        const t = line.text;
        var i: usize = 0;
        while (i < t.len) {
            if (t[i] == ' ' or t[i] == '\t') {
                i += 1;
                continue;
            }
            const start = i;
            if (t[i] == '"' or t[i] == '\'') {
                const end = try self.quotedEnd(t, i);
                try words.append(self.allocator, .{ .text = try self.decode(t[start + 1 .. end - 1], start + 1), .quoted = true, .pos = self.at(start) });
                i = end;
                continue;
            }
            while (i < t.len and t[i] != ' ' and t[i] != '\t') i += 1;
            try words.append(self.allocator, .{ .text = t[start..i], .quoted = false, .pos = self.at(start) });
        }
        return words.toOwnedSlice(self.allocator);
    }

    /// The end (past the closing quote) of the quoted string at `t[i]`.
    fn quotedEnd(self: *Analyzer, t: []const u8, i: usize) Error!usize {
        var j = i + 1;
        while (j < t.len and t[j] != t[i]) : (j += 1) {
            if (t[j] == '\\' and j + 1 < t.len) j += 1;
        }
        if (j >= t.len) return self.fail(self.at(i), "unterminated quoted literal", .{});
        return j + 1;
    }

    /// A string body with its escapes decoded; an unknown escape is an
    /// error at its backslash.
    fn decode(self: *Analyzer, body: []const u8, offset: usize) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var k: usize = 0;
        while (k < body.len) {
            var e: grammar.Escape = .{ .byte = body[k], .len = 1 };
            if (body[k] == '\\') e = grammar.escapeAt(body, k) orelse
                return self.fail(self.at(offset + k), "unknown escape sequence (the escapes are \\n \\r \\t \\0 \\\\ \\' \\\" and \\xHH)", .{});
            try out.append(self.allocator, e.byte);
            k += e.len;
        }
        return out.toOwnedSlice(self.allocator);
    }

    // --- Entry text ---------------------------------------------------------

    /// A top-level item of an entry's text.
    const Tok = struct {
        kind: enum { word, string, capture, other },
        start: usize,
        end: usize,
        /// A capture's pattern, inside its parentheses.
        inner: [2]usize = .{ 0, 0 },
    };

    /// Splits `t`, the current line's text, into top-level items.
    fn scan(self: *Analyzer, t: []const u8) Error![]const Tok {
        var toks: std.ArrayList(Tok) = .empty;
        var i: usize = 0;
        while (i < t.len) {
            const c = t[i];
            if (c == ' ' or c == '\t') {
                i += 1;
                continue;
            }
            const start = i;
            if (c == '"' or c == '\'') {
                i = try self.quotedEnd(t, i);
                try toks.append(self.allocator, .{ .kind = .string, .start = start, .end = i });
            } else if (c == '[') {
                i = try self.classEnd(t, i);
                try toks.append(self.allocator, .{ .kind = .other, .start = start, .end = i });
            } else if (c == '(') {
                i = try self.groupEnd(t, i);
                try toks.append(self.allocator, .{ .kind = .other, .start = start, .end = i });
            } else if (std.ascii.isAlphabetic(c) or c == '_') {
                i = wordEnd(t, i);
                if (i < t.len and t[i] == ':') {
                    if (i + 1 >= t.len or t[i + 1] != '(')
                        return self.fail(self.at(start), "a capture is `scope:( pattern )`: `{s}:` is not followed by `(`", .{t[start..i]});
                    const close = try self.groupEnd(t, i + 1);
                    try toks.append(self.allocator, .{ .kind = .capture, .start = start, .end = close, .inner = .{ i + 2, close - 1 } });
                    i = close;
                } else try toks.append(self.allocator, .{ .kind = .word, .start = start, .end = i });
            } else if (c == '\\' and i + 1 < t.len) {
                i += 2;
                try toks.append(self.allocator, .{ .kind = .other, .start = start, .end = i });
            } else {
                i += 1;
                try toks.append(self.allocator, .{ .kind = .other, .start = start, .end = i });
            }
        }
        return toks.toOwnedSlice(self.allocator);
    }

    /// A name, with `.` or `-` joining its parts (`string.escape`,
    /// `line-start`).
    fn wordEnd(t: []const u8, start: usize) usize {
        var i = start;
        while (i < t.len) {
            if (std.ascii.isAlphanumeric(t[i]) or t[i] == '_') {
                i += 1;
            } else if ((t[i] == '.' or t[i] == '-') and i + 1 < t.len and std.ascii.isAlphanumeric(t[i + 1]) and i > start) {
                i += 1;
            } else break;
        }
        return i;
    }

    fn classEnd(self: *Analyzer, t: []const u8, i: usize) Error!usize {
        var j = i + 1;
        if (j < t.len and t[j] == '^') j += 1;
        if (j < t.len and t[j] == ']') j += 1;
        while (j < t.len and t[j] != ']') : (j += 1) {
            if (t[j] == '\\' and j + 1 < t.len) j += 1;
        }
        if (j >= t.len) return self.fail(self.at(i), "unclosed '['", .{});
        return j + 1;
    }

    /// The end of the group at `t[i]`; a capture inside it is an error.
    fn groupEnd(self: *Analyzer, t: []const u8, i: usize) Error!usize {
        var depth: usize = 0;
        var j = i;
        while (j < t.len) {
            switch (t[j]) {
                '(' => {
                    depth += 1;
                    j += 1;
                },
                ')' => {
                    depth -= 1;
                    j += 1;
                    if (depth == 0) return j;
                },
                '"', '\'' => j = try self.quotedEnd(t, j),
                '[' => j = try self.classEnd(t, j),
                '\\' => j += 2,
                else => if (std.ascii.isAlphabetic(t[j]) or t[j] == '_') {
                    const e = wordEnd(t, j);
                    if (e < t.len and t[e] == ':' and depth > 0 and j > i)
                        return self.fail(self.at(j), "a capture belongs at the top level of a pattern, not inside ( )", .{});
                    j = e;
                } else {
                    j += 1;
                },
            }
        }
        return self.fail(self.at(i), "unclosed '('", .{});
    }

    const Reserved = enum { after, before, not, within, line_start, line_end };

    fn reserved(text: []const u8) ?Reserved {
        const words = [_]struct { []const u8, Reserved }{
            .{ "after", .after },   .{ "before", .before },         .{ "not", .not },
            .{ "within", .within }, .{ "line-start", .line_start }, .{ "line-end", .line_end },
        };
        for (words) |w| if (std.mem.eql(u8, w[0], text)) return w[1];
        return null;
    }

    /// An entry's text split into its core (the targets) and clauses.
    const Parts = struct {
        core: []const Tok,
        lineStart: bool,
        lineEnd: bool,
        looks: []const Context,
        within: ?Tok,
    };

    fn split(self: *Analyzer, t: []const u8, toks: []const Tok) Error!Parts {
        var parts: Parts = .{ .core = &.{}, .lineStart = false, .lineEnd = false, .looks = &.{}, .within = null };
        var looks: std.ArrayList(Context) = .empty;
        var i: usize = 0;
        var coreSeen = false;
        while (i < toks.len) {
            const tok = toks[i];
            const r = if (tok.kind == .word) reserved(t[tok.start..tok.end]) else null;
            if (r == null) {
                if (coreSeen) return self.fail(self.at(tok.start), "the targets of an entry come before its contexts", .{});
                var j = i;
                while (j < toks.len and !(toks[j].kind == .word and reserved(t[toks[j].start..toks[j].end]) != null)) j += 1;
                parts.core = toks[i..j];
                coreSeen = true;
                i = j;
                continue;
            }
            switch (r.?) {
                .line_start, .line_end => {
                    const flag = if (r.? == .line_start) &parts.lineStart else &parts.lineEnd;
                    if (flag.*) return self.fail(self.at(tok.start), "`{s}` is given twice", .{t[tok.start..tok.end]});
                    flag.* = true;
                    i += 1;
                    if (r.? == .line_end and !coreSeen) coreSeen = true;
                },
                .within => {
                    if (parts.within != null) return self.fail(self.at(tok.start), "`within` is given twice", .{});
                    const next = if (i + 1 < toks.len) toks[i + 1] else null;
                    if (next == null or next.?.kind != .word or !std.ascii.isUpper(t[next.?.start]))
                        return self.fail(self.at(tok.start), "`within` names a token: within STRING", .{});
                    parts.within = next.?;
                    i += 2;
                    if (!coreSeen) coreSeen = true;
                },
                .not, .after, .before => {
                    var kind: Look = if (r.? == .after) .after else .before;
                    var k = i + 1;
                    if (r.? == .not) {
                        const next = if (k < toks.len and toks[k].kind == .word) reserved(t[toks[k].start..toks[k].end]) else null;
                        if (next != Reserved.after and next != Reserved.before)
                            return self.fail(self.at(tok.start), "`not` is followed by `after` or `before`", .{});
                        kind = if (next.? == .after) .not_after else .not_before;
                        k += 1;
                    }
                    var j = k;
                    while (j < toks.len and !(toks[j].kind == .word and reserved(t[toks[j].start..toks[j].end]) != null)) j += 1;
                    if (j == k) return self.fail(self.at(tok.start), "`{s}` needs a pattern", .{kind.name()});
                    const text = t[toks[k].start..toks[j - 1].end];
                    const node = try self.parsePattern(text, toks[k].start);
                    if (render.checkEditor(.{ .node = node })) |problem|
                        return self.fail(self.at(toks[k].start), "this pattern has no editor form: it matches {s}", .{problem});
                    if (regex.nullable(node))
                        return self.fail(self.at(toks[k].start), "a context pattern must not match the empty string", .{});
                    if (kind == .before or kind == .not_before) {
                        const len = render.charLen(node);
                        if (len.max == null or len.max.? != len.min)
                            return self.fail(self.at(toks[k].start), "a `{s}` pattern must have a fixed length: editors cannot look back over a varying length", .{kind.name()});
                    }
                    try looks.append(self.allocator, .{ .kind = kind, .text = text, .node = node });
                    if (!coreSeen) coreSeen = true;
                    i = j;
                },
            }
        }
        parts.looks = try looks.toOwnedSlice(self.allocator);
        return parts;
    }

    /// A Nexus pattern of an entry (no trailing context: `after` says it).
    fn parsePattern(self: *Analyzer, text: []const u8, offset: usize) Error!*const Node {
        var d: regex.Diagnostic = .{};
        const p = regex.parse(self.allocator, text, &d) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidPattern => return self.fail(self.at(offset + d.offset), "{s}", .{d.message}),
        };
        if (p.trail != null) {
            const slash = std.mem.findScalar(u8, text, '/') orelse 0;
            return self.fail(self.at(offset + slash), "in @highlight, trailing context is written `after P`", .{});
        }
        return p.main;
    }

    /// `indent` / `dedent`: one pattern with contexts.
    fn pattern(self: *Analyzer, line: grammar.HighlightLines.Line) Error!Pattern {
        const toks = try self.scan(line.text);
        const parts = try self.split(line.text, toks);
        if (parts.within) |w| return self.fail(self.at(w.start), "`{s}` is a pattern: it takes no `within`", .{line.key});
        if (parts.core.len == 0) return self.fail(line.keyPos, "`{s}` needs a pattern", .{line.key});
        for (parts.core) |tok| if (tok.kind == .capture)
            return self.fail(self.at(tok.start), "`{s}` is a pattern: it takes no captures", .{line.key});
        const start = parts.core[0].start;
        const core = try self.parsePattern(line.text[start..parts.core[parts.core.len - 1].end], start);
        if (render.checkEditor(.{ .node = core })) |problem|
            return self.fail(self.at(start), "this pattern has no editor form: it matches {s}", .{problem});
        return .{ .lineStart = parts.lineStart, .lineEnd = parts.lineEnd, .looks = parts.looks, .core = core };
    }

    // --- Entries ----------------------------------------------------------

    fn entry(self: *Analyzer, scope: Scope, line: grammar.HighlightLines.Line) Error!void {
        if (line.text.len == 0) return self.fail(line.keyPos, "`{s}` needs targets: literals, tokens, @keywords groups, or a pattern", .{line.key});
        const t = line.text;
        const toks = try self.scan(t);
        const parts = try self.split(t, toks);
        if (parts.core.len == 0) return self.fail(line.keyPos, "`{s}` needs targets: literals, tokens, @keywords groups, or a pattern", .{line.key});

        var e: Entry = .{ .scope = scope, .line = self.source.at(line.keyPos).line, .lineStart = parts.lineStart, .lineEnd = parts.lineEnd, .contexts = parts.looks };
        var b: Built = .{ .entry = self.entries.items.len, .pos = line.keyPos, .literals = &.{}, .tokens = &.{}, .pieces = &.{}, .contextual = parts.lineStart or parts.lineEnd or parts.looks.len > 0 };
        var withinKey: []const u8 = "";
        if (parts.within) |w| {
            const name = t[w.start..w.end];
            const cat = try self.tokenCat(name, self.at(w.start));
            _ = try self.tokenRules(cat, name, self.at(w.start));
            e.within = name;
            withinKey = try std.mem.concat(self.allocator, u8, &.{ "@", cat });
        }

        const isList = for (parts.core) |tok| {
            if (tok.kind != .word and tok.kind != .string) break false;
        } else true;
        if (isList) {
            var literals: std.ArrayList([]const u8) = .empty;
            var tokens: std.ArrayList([]const u8) = .empty;
            var groups: std.ArrayList([]const u8) = .empty;
            var lits: std.ArrayList(render.Literal) = .empty;
            var cats: std.ArrayList([]const u8) = .empty;
            for (parts.core) |tok| {
                const text = t[tok.start..tok.end];
                const pos = self.at(tok.start);
                if (tok.kind == .string) {
                    const bytes = try self.decode(text[1 .. text.len - 1], tok.start + 1);
                    if (bytes.len == 0) return self.fail(pos, "empty literal", .{});
                    if (!try self.lexesWhole(bytes))
                        return self.fail(pos, "{s} is no token: no lexer rule matches it whole", .{text});
                    const owner = self.literalToken(bytes);
                    const key = if (owner) |o| try std.mem.concat(self.allocator, u8, &.{ "T:", o, withinKey }) else try std.mem.concat(self.allocator, u8, &.{ "L:", bytes, withinKey });
                    if (!b.contextual) try self.claim(key, text, pos, scope);
                    try literals.append(self.allocator, bytes);
                    try lits.append(self.allocator, .{ .bytes = bytes, .min = bytes.len, .bounded = true });
                } else if (std.ascii.isUpper(text[0])) {
                    const cat = try self.tokenCat(text, pos);
                    _ = try self.tokenRules(cat, text, pos);
                    if (!b.contextual) try self.claim(try std.mem.concat(self.allocator, u8, &.{ "T:", cat, withinKey }), text, pos, scope);
                    try tokens.append(self.allocator, text);
                    try cats.append(self.allocator, cat);
                } else {
                    const group = for (self.groups) |g| {
                        if (std.mem.eql(u8, g.name, text)) break g;
                    } else return self.fail(pos, "`{s}` is no @keywords group (a lowercase name in a target list names a group; tokens are capitalized)", .{text});
                    if (!b.contextual) try self.claim(try std.mem.concat(self.allocator, u8, &.{ "G:", text, withinKey }), text, pos, scope);
                    try groups.append(self.allocator, text);
                    for (group.entries) |ge| try lits.append(self.allocator, .{ .bytes = ge.word, .min = ge.min, .caseless = group.caseless, .bounded = true });
                }
            }
            e.literals = try literals.toOwnedSlice(self.allocator);
            e.tokens = try tokens.toOwnedSlice(self.allocator);
            e.groups = try groups.toOwnedSlice(self.allocator);
            b.literals = try lits.toOwnedSlice(self.allocator);
            b.tokens = try cats.toOwnedSlice(self.allocator);
            for (b.literals) |l| if (render.checkEditor(.{ .literal = l })) |problem|
                return self.fail(self.at(0), "this literal has no editor form: it matches {s}", .{problem});
        } else {
            const first = parts.core[0].start;
            const last = parts.core[parts.core.len - 1].end;
            e.pattern = t[first..last];
            b.contextual = true;
            var pieces: std.ArrayList(Piece) = .empty;
            const hasCaptures = for (parts.core) |tok| {
                if (tok.kind == .capture) break true;
            } else false;
            if (!hasCaptures) {
                const node = try self.parsePattern(t[first..last], first);
                try pieces.append(self.allocator, .{ .scope = scope, .captured = false, .rx = .{ .node = node } });
            } else {
                for (parts.core) |tok| if (tok.kind == .other and t[tok.start] == '|')
                    return self.fail(self.at(tok.start), "a pattern with captures is a sequence: group an alternation in ( )", .{});
                var i: usize = 0;
                while (i < parts.core.len) {
                    const tok = parts.core[i];
                    if (tok.kind == .capture) {
                        const name = t[tok.start .. tok.inner[0] - 2];
                        const capScope = Scope.parse(name) orelse
                            return self.fail(self.at(tok.start), "`{s}` is not a scope (scopes: " ++ scopeList ++ ")", .{name});
                        const inner = t[tok.inner[0]..tok.inner[1]];
                        if (std.mem.trim(u8, inner, " \t").len == 0) return self.fail(self.at(tok.start), "the capture `{s}:( )` is empty", .{name});
                        const node = try self.parsePattern(inner, tok.inner[0]);
                        try pieces.append(self.allocator, .{ .scope = capScope, .captured = true, .rx = .{ .node = node } });
                        i += 1;
                        continue;
                    }
                    var j = i;
                    while (j < parts.core.len and parts.core[j].kind != .capture) j += 1;
                    const start = parts.core[i].start;
                    const node = try self.parsePattern(t[start..parts.core[j - 1].end], start);
                    try pieces.append(self.allocator, .{ .scope = scope, .captured = false, .rx = .{ .node = node } });
                    i = j;
                }
                for (pieces.items, 0..) |p, k| if (regex.nullable(p.rx.node)) {
                    const where = pieceStart(parts.core, k);
                    return self.fail(self.at(where), "each part of a pattern with captures must match something (use + rather than *)", .{});
                };
            }
            for (pieces.items, 0..) |p, k| {
                if (render.checkEditor(p.rx)) |problem|
                    return self.fail(self.at(if (hasCaptures) pieceStart(parts.core, k) else first), "this pattern has no editor form: it matches {s}", .{problem});
            }
            if (!hasCaptures and regex.nullable(pieces.items[0].rx.node))
                return self.fail(self.at(first), "this pattern matches the empty string", .{});
            e.pieces = try pieces.toOwnedSlice(self.allocator);
            b.pieces = e.pieces;
        }
        try self.entries.append(self.allocator, e);
        try self.built.append(self.allocator, b);
    }

    /// The start of the `k`-th piece of a pattern with captures.
    fn pieceStart(core: []const Tok, k: usize) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < core.len) {
            if (n == k) return core[i].start;
            if (core[i].kind == .capture) {
                i += 1;
            } else {
                while (i < core.len and core[i].kind != .capture) i += 1;
            }
            n += 1;
        }
        return core[0].start;
    }

    /// Records that the entry with `scope` lists the target `key`. Only an
    /// entry without contexts claims: one with a context, `line-start` or
    /// `line-end` is tried first, so it may name a target another lists.
    fn claim(self: *Analyzer, key: []const u8, text: []const u8, pos: u32, scope: Scope) Error!void {
        const gop = try self.seen.getOrPut(self.allocator, key);
        if (gop.found_existing) {
            const other = self.entries.items[gop.value_ptr.*];
            if (other.scope == scope)
                return self.fail(pos, "{s} is listed twice under {s} (first on line {d})", .{ text, scope.names().name, other.line });
            return self.fail(pos, "{s} is listed under {s} on line {d} and under {s}: a target has one scope", .{ text, other.scope.names().name, other.line, scope.names().name });
        }
        gop.value_ptr.* = self.entries.items.len;
    }

    /// The TokenCat name of the token written `name` (`STRING_DQ`).
    fn tokenCat(self: *Analyzer, name: []const u8, pos: usize) Error![]const u8 {
        const cat = try std.ascii.allocLowerString(self.allocator, name);
        for (self.spec.tokens.items) |tok| if (std.mem.eql(u8, tok, cat)) return tok;
        return self.fail(pos, "{s} is no token of the tokens block", .{name});
    }

    /// The indexes of the lexer rules whose text is token `cat`'s
    /// (zero-width rules and `hold` give none); a rule that rewinds is an
    /// error.
    fn tokenRules(self: *Analyzer, cat: []const u8, name: []const u8, pos: usize) Error![]const usize {
        var rules: std.ArrayList(usize) = .empty;
        for (self.spec.rules.items, 0..) |rule, r| {
            if (!std.mem.eql(u8, rule.token, cat) or rule.pattern.len == 0 or rule.hold) continue;
            if (rule.rewind != null)
                return self.fail(pos, "{s}'s rule on line {d} rewinds, so its pattern is not the token's text; highlight the text with a pattern", .{ name, rule.line });
            try rules.append(self.allocator, r);
        }
        if (rules.items.len == 0)
            return self.fail(pos, "no lexer rule matches the text of {s} (a lang Lexer makes it, or a zero-width rule); highlight its text with a pattern", .{name});
        return rules.toOwnedSlice(self.allocator);
    }

    /// The token of the lexer rule whose pattern is exactly `bytes`.
    fn literalToken(self: *const Analyzer, bytes: []const u8) ?[]const u8 {
        for (self.spec.rules.items) |*rule| {
            const lit = grammar.ruleLiteral(rule) orelse continue;
            if (std.mem.eql(u8, lit, bytes)) return rule.token;
        }
        return null;
    }

    /// Whether some lexer rule's pattern matches all of `bytes`.
    fn lexesWhole(self: *Analyzer, bytes: []const u8) Error!bool {
        for (self.spec.rules.items, self.patterns) |rule, p| {
            if (rule.pattern.len == 0) continue;
            if (try matchesWhole(self.allocator, p.main, bytes)) return true;
        }
        return false;
    }

    // --- Regions and order ------------------------------------------------

    /// Every token named by `within` is a region: its rules have a literal
    /// prefix and suffix, it takes no context, and no region is within
    /// another.
    fn checkRegions(self: *Analyzer) Error!void {
        for (self.entries.items, self.built.items) |e, b| {
            const w = e.within orelse continue;
            const cat = try std.ascii.allocLowerString(self.allocator, w);
            for (try self.tokenRules(cat, w, b.pos)) |r| _ = try self.regionOf(r, w, b.pos);
            for (self.built.items, self.entries.items) |ob, oe| for (ob.tokens, oe.tokens) |t, written| {
                if (!std.mem.eql(u8, t, cat)) continue;
                if (oe.within != null)
                    return self.fail(ob.pos, "{s} is a region (an entry is `within` it), and regions do not nest", .{written});
                if (ob.contextual)
                    return self.fail(ob.pos, "{s} is a region (an entry is `within` it), so its entry takes no context, line-start or line-end", .{written});
            };
        }
    }

    fn isRegion(self: *const Analyzer, cat: []const u8) bool {
        for (self.entries.items) |e| if (e.within) |w| if (std.ascii.eqlIgnoreCase(w, cat)) return true;
        return false;
    }

    /// The parts of a region rule: `prefix body* suffix`.
    fn regionOf(self: *Analyzer, r: usize, name: []const u8, pos: u32) Error!Region {
        const bad = "{s} is a region (an entry is `within` it), so its pattern (line {d}) must be a literal, then a body, then a suffix ending in a literal";
        const rule = self.spec.rules.items[r];
        const p = self.patterns[r];
        if (p.trail != null or p.main.* != .concat) return self.fail(pos, bad, .{ name, rule.line });
        // A multi-byte literal is a concatenation of its own.
        var flat: std.ArrayList(*const Node) = .empty;
        try self.flatten(p.main, &flat);
        const kids = flat.items;
        var prefix: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i + 1 < kids.len) : (i += 1) {
            const byte = (if (kids[i].* == .set) kids[i].set.only() else null) orelse break;
            try prefix.append(self.allocator, byte);
        }
        var j = kids.len;
        while (j > i and !regex.nullable(kids[j - 1])) j -= 1;
        const last = kids[kids.len - 1];
        if (prefix.items.len == 0 or j == kids.len or last.* != .set or last.set.only() == null)
            return self.fail(pos, bad, .{ name, rule.line });
        const end = try self.concat(kids[j..]);
        const middle = kids[i..j];
        const body: ?*const Node = if (middle.len == 1 and middle[0].* == .repeat)
            middle[0].repeat.sub
        else if (middle.len > 0)
            try self.concat(middle)
        else
            null;
        return .{
            .scope = null,
            .token = name,
            .begin = try prefix.toOwnedSlice(self.allocator),
            .end = .{ .node = end },
            .body = if (body) |n| (if (regex.nullable(n)) null else Rx{ .node = n }) else null,
            .items = &.{},
        };
    }

    fn flatten(self: *Analyzer, n: *const Node, out: *std.ArrayList(*const Node)) Error!void {
        if (n.* != .concat) return out.append(self.allocator, n);
        for (n.concat) |k| try self.flatten(k, out);
    }

    fn concat(self: *Analyzer, kids: []const *const Node) Error!*const Node {
        if (kids.len == 1) return kids[0];
        const n = try self.allocator.create(Node);
        n.* = .{ .concat = try self.allocator.dupe(*const Node, kids) };
        return n;
    }

    /// The items of the entries within `region` (TokenCat name), or of
    /// those within none, in the order the editors try them.
    fn order(self: *Analyzer, region: ?[]const u8) Error![]const Item {
        var items: std.ArrayList(Item) = .empty;
        const Lit = struct { lit: render.Literal, scope: Scope };
        var lits: std.ArrayList(Lit) = .empty;
        for (self.entries.items, self.built.items) |e, b| {
            if (!sameRegion(e.within, region)) continue;
            if (!b.contextual) {
                for (b.literals) |l| try lits.append(self.allocator, .{ .lit = l, .scope = e.scope });
                continue;
            }
            const m: Match = .{ .pieces = &.{}, .lineStart = e.lineStart, .lineEnd = e.lineEnd, .looks = e.contexts };
            if (b.pieces.len > 0) {
                try items.append(self.allocator, .{ .match = .{ .pieces = b.pieces, .lineStart = m.lineStart, .lineEnd = m.lineEnd, .looks = m.looks } });
                continue;
            }
            if (b.literals.len > 0) {
                const sorted = try self.allocator.dupe(render.Literal, b.literals);
                std.mem.sort(render.Literal, sorted, {}, longerLiteral);
                const alts = try self.allocator.alloc(Rx, sorted.len);
                for (sorted, alts) |l, *x| x.* = .{ .literal = l };
                try items.append(self.allocator, .{ .match = .{ .pieces = try self.one(e.scope, .{ .alt = alts }), .lineStart = m.lineStart, .lineEnd = m.lineEnd, .looks = m.looks } });
            }
            for (b.tokens) |cat| for (self.spec.rules.items, self.patterns) |rule, p| {
                if (!std.mem.eql(u8, rule.token, cat) or rule.pattern.len == 0 or rule.hold) continue;
                const looks = if (p.trail) |trail| try std.mem.concat(self.allocator, Context, &.{ m.looks, &.{.{ .kind = .after, .text = "", .node = trail }} }) else m.looks;
                try items.append(self.allocator, .{ .match = .{ .pieces = try self.one(e.scope, .{ .node = p.main }), .lineStart = m.lineStart, .lineEnd = m.lineEnd, .looks = looks } });
            };
        }

        // Literals: a literal that could match the start of a longer one
        // comes after it. Each item holds the literals of one scope whose
        // longer literals are placed, longest first; a scope takes several
        // items only when another scope's literal must come between.
        const n = lits.items.len;
        const placed = try self.allocator.alloc(bool, n);
        const batch = try self.allocator.alloc(bool, n);
        @memset(placed, false);
        var left = n;
        while (left > 0) {
            // The first scope, in order, with literals free to go now: none
            // a prefix of a literal still to place outside the batch.
            const scope = for (lits.items, 0..) |l, k| {
                if (placed[k]) continue;
                for (lits.items, 0..) |o, m| batch[m] = !placed[m] and o.scope == l.scope;
                var changed = true;
                while (changed) {
                    changed = false;
                    for (lits.items, 0..) |a, x| {
                        if (!batch[x]) continue;
                        for (lits.items, 0..) |b, y| if (!placed[y] and !batch[y] and self.prefixOf(a.lit, b.lit)) {
                            batch[x] = false;
                            changed = true;
                            break;
                        };
                    }
                }
                if (std.mem.findScalar(bool, batch, true) != null) break l.scope;
            } else unreachable; // the longest literal left is free
            var chosen: std.ArrayList(render.Literal) = .empty;
            for (lits.items, 0..) |l, k| if (batch[k]) {
                try chosen.append(self.allocator, l.lit);
                placed[k] = true;
                left -= 1;
            };
            std.mem.sort(render.Literal, chosen.items, {}, longerLiteral);
            const alts = try self.allocator.alloc(Rx, chosen.items.len);
            for (chosen.items, alts) |c, *x| x.* = .{ .literal = c };
            try items.append(self.allocator, .{ .match = .{
                .pieces = try self.one(scope, if (alts.len == 1) alts[0] else .{ .alt = alts }),
                .lineStart = false,
                .lineEnd = false,
                .looks = &.{},
            } });
        }

        // Every rule, in lexer order (outside regions): listed tokens and
        // regions coloured, the rest plain. Blanks start no token.
        if (region == null) try items.append(self.allocator, .{ .plain = .{ .rx = .{ .node = &blanks }, .looks = &.{} } });
        for (self.spec.rules.items, self.patterns, 0..) |rule, p, r| {
            if (rule.pattern.len == 0 or rule.hold) continue;
            var scope: ?Scope = null;
            var listed = false;
            for (self.entries.items, self.built.items) |e, b| {
                if (b.contextual or !sameRegion(e.within, region)) continue;
                for (b.tokens) |cat| if (std.mem.eql(u8, cat, rule.token)) {
                    scope = e.scope;
                    listed = true;
                };
            }
            if (region == null and self.isRegion(rule.token)) {
                const written = self.writtenName(rule.token);
                var reg = try self.regionOf(r, written, 0);
                reg.scope = scope;
                reg.items = try self.order(rule.token);
                try items.append(self.allocator, .{ .region = reg });
                continue;
            }
            const looks: []const Context = if (p.trail) |trail| try self.allocator.dupe(Context, &.{.{ .kind = .after, .text = "", .node = trail }}) else &.{};
            if (listed) {
                try items.append(self.allocator, .{ .match = .{ .pieces = try self.one(scope.?, .{ .node = p.main }), .lineStart = false, .lineEnd = false, .looks = looks } });
            } else if (region == null and rule.rewind == null and !self.listedAsLiteral(rule.token)) {
                try items.append(self.allocator, .{ .plain = .{ .rx = .{ .node = p.main }, .looks = looks } });
            }
        }
        return items.toOwnedSlice(self.allocator);
    }

    /// Whether an entry outside every region lists token `cat` by a
    /// literal (which matches before the tokens).
    fn listedAsLiteral(self: *const Analyzer, cat: []const u8) bool {
        for (self.entries.items, self.built.items) |e, b| {
            if (b.contextual or e.within != null) continue;
            for (e.literals) |l| if (self.literalToken(l)) |t| if (std.mem.eql(u8, t, cat)) return true;
        }
        return false;
    }

    /// Longest first, stable for equal lengths (the sort keeps no order:
    /// ties compare the text).
    fn longerLiteral(_: void, x: render.Literal, y: render.Literal) bool {
        if (x.bytes.len != y.bytes.len) return x.bytes.len > y.bytes.len;
        return std.mem.lessThan(u8, x.bytes, y.bytes);
    }

    /// Whether `a` can match where `b` starts, ending inside it: a
    /// spelling of `a` is a proper prefix of `b` (ASCII case aside), and
    /// not both are words (a word's boundary keeps it out of a longer
    /// word).
    fn prefixOf(self: *const Analyzer, a: render.Literal, b: render.Literal) bool {
        if (self.allWord(a.bytes) and self.allWord(b.bytes) and a.bounded) return false;
        var k = a.min;
        while (k <= a.bytes.len) : (k += 1) {
            if (k < b.bytes.len and std.ascii.eqlIgnoreCase(a.bytes[0..k], b.bytes[0..k])) return true;
        }
        return false;
    }

    fn allWord(self: *const Analyzer, text: []const u8) bool {
        for (text) |c| if (!self.wordChars.has(c)) return false;
        return true;
    }

    fn sameRegion(within: ?[]const u8, region: ?[]const u8) bool {
        if (within == null or region == null) return within == null and region == null;
        return std.ascii.eqlIgnoreCase(within.?, region.?);
    }

    /// The token as an entry's `within` writes it.
    fn writtenName(self: *const Analyzer, cat: []const u8) []const u8 {
        for (self.entries.items) |e| if (e.within) |w| if (std.ascii.eqlIgnoreCase(w, cat)) return w;
        unreachable;
    }

    fn one(self: *Analyzer, scope: Scope, rx: Rx) Error![]const Piece {
        return self.allocator.dupe(Piece, &.{.{ .scope = scope, .captured = false, .rx = rx }});
    }
};

/// Whether `node` matches all of `input` (a set-of-positions matcher).
fn matchesWhole(allocator: Allocator, node: *const Node, input: []const u8) Allocator.Error!bool {
    const start = try allocator.alloc(bool, input.len + 1);
    @memset(start, false);
    start[0] = true;
    const reached = try ends(allocator, node, input, start);
    return reached[input.len];
}

fn ends(allocator: Allocator, n: *const Node, input: []const u8, from: []const bool) Allocator.Error![]const bool {
    const out = try allocator.alloc(bool, from.len);
    @memset(out, false);
    switch (n.*) {
        .empty => @memcpy(out, from),
        .set => |s| for (from, 0..) |on, p| {
            if (on and p < input.len and s.has(input[p])) out[p + 1] = true;
        },
        .concat => |kids| {
            var cur = from;
            for (kids) |k| cur = try ends(allocator, k, input, cur);
            @memcpy(out, cur);
        },
        .alt => |kids| for (kids) |k| {
            const r = try ends(allocator, k, input, from);
            for (out, r) |*o, x| o.* = o.* or x;
        },
        .repeat => |rep| {
            var cur = from;
            var i: u32 = 0;
            while (i < rep.min) : (i += 1) cur = try ends(allocator, rep.sub, input, cur);
            @memcpy(out, cur);
            var extra: u32 = 0;
            while (rep.max == null or extra < rep.max.? - rep.min) : (extra += 1) {
                cur = try ends(allocator, rep.sub, input, cur);
                var grew = false;
                for (out, cur) |*o, x| if (x and !o.*) {
                    o.* = true;
                    grew = true;
                };
                if (!grew) break;
            }
        },
    }
    return out;
}

test "matchesWhole follows the pattern" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: regex.Diagnostic = .{};
    const p = try regex.parse(a, "[a-z]+ ('_' [a-z]+)*", &d);
    try std.testing.expect(try matchesWhole(a, p.main, "abc_de"));
    try std.testing.expect(!try matchesWhole(a, p.main, "abc_"));
    try std.testing.expect(!try matchesWhole(a, p.main, "_"));
}
