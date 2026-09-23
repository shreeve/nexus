//! Parser for the `@lexer` section of a .grammar file.
//!
//! Line-oriented; fills a grammar.LexerSpec with `state`, `after` and
//! `tokens` blocks, lexer-section `@code` imports, and rules of the form
//!
//!     pattern [@ guard (& guard)*] → token [, action]*
//!
//! Every pattern is parsed by lexgen/regex.zig here, so pattern errors are
//! reported with their exact location. Anything the section cannot parse is
//! a `file:line:col: error:` diagnostic; nothing is skipped.

const std = @import("std");
const diag = @import("../diag.zig");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const regex = @import("../lexgen/regex.zig");
const LexerSpec = grammar.LexerSpec;
const Guard = grammar.Guard;
const Action = grammar.Action;

pub const Error = error{ LexerSectionError, OutOfMemory };

pub const LexerParser = struct {
    allocator: Allocator,
    /// The whole grammar file (positions and line numbers are file-relative).
    source: []const u8,
    pos: usize,
    spec: LexerSpec,
    fileName: []const u8,
    scratch: std.ArrayListUnmanaged(u8) = .empty,
    /// Offset of the `tokens` block (for diagnostics about required tokens).
    tokensAt: usize = 0,

    /// `start` is the offset just past the `@lexer` marker.
    pub fn init(allocator: Allocator, source: []const u8, start: usize, fileName: []const u8) LexerParser {
        var spec = LexerSpec.init(allocator);
        spec.fileName = fileName;
        return .{
            .allocator = allocator,
            .source = source,
            .pos = start,
            .spec = spec,
            .fileName = fileName,
        };
    }

    pub fn deinit(self: *LexerParser) void {
        self.spec.deinit();
        self.scratch.deinit(self.allocator);
    }

    // -------------------------------------------------------------------------
    // Diagnostics
    // -------------------------------------------------------------------------

    pub const Location = struct { line: u32, col: u32 };

    pub fn locate(self: *const LexerParser, offset: usize) Location {
        var line: u32 = 1;
        var lineStart: usize = 0;
        for (self.source[0..@min(offset, self.source.len)], 0..) |c, i| {
            if (c == '\n') {
                line += 1;
                lineStart = i + 1;
            }
        }
        return .{ .line = line, .col = @intCast(offset - lineStart + 1) };
    }

    fn fail(self: *LexerParser, offset: usize, comptime fmt: []const u8, args: anytype) Error {
        const loc = self.locate(offset);
        diag.errAt(self.fileName, loc.line, loc.col, fmt, args);
        return error.LexerSectionError;
    }

    /// The text at `offset` up to whitespace or end of line, for messages.
    fn wordAt(self: *const LexerParser, offset: usize) []const u8 {
        var e = offset;
        while (e < self.source.len and self.source[e] != '\n' and self.source[e] != ' ' and self.source[e] != '\t' and self.source[e] != '\r') e += 1;
        if (e == offset) return if (offset >= self.source.len or self.source[offset] == '\n') "end of line" else self.source[offset .. offset + 1];
        return self.source[offset..e];
    }

    // -------------------------------------------------------------------------
    // Scanning helpers
    // -------------------------------------------------------------------------

    fn peek(self: *const LexerParser) u8 {
        return if (self.pos < self.source.len) self.source[self.pos] else 0;
    }

    fn atEol(self: *const LexerParser) bool {
        return self.pos >= self.source.len or self.source[self.pos] == '\n' or self.source[self.pos] == '#';
    }

    /// Skip spaces, tabs and carriage returns (not newlines).
    fn skipBlanks(self: *LexerParser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') self.pos += 1 else break;
        }
    }

    /// Require the rest of the line to be blank or a comment, then move past it.
    fn endLine(self: *LexerParser) Error!void {
        self.skipBlanks();
        if (self.pos < self.source.len and self.source[self.pos] != '\n' and self.source[self.pos] != '#') {
            return self.fail(self.pos, "unexpected '{s}' at end of line", .{self.wordAt(self.pos)});
        }
        while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
        if (self.pos < self.source.len) self.pos += 1;
    }

    /// True if the line starting at `self.pos` is blank or a comment.
    fn lineIsBlank(self: *const LexerParser) bool {
        var p = self.pos;
        while (p < self.source.len and (self.source[p] == ' ' or self.source[p] == '\t' or self.source[p] == '\r')) p += 1;
        return p >= self.source.len or self.source[p] == '\n' or self.source[p] == '#';
    }

    fn skipLine(self: *LexerParser) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
        if (self.pos < self.source.len) self.pos += 1;
    }

    /// At a line start: is the next non-blank line indented? Blank and
    /// comment lines are skipped.
    fn nextLineIndented(self: *LexerParser) bool {
        while (self.pos < self.source.len and self.lineIsBlank()) self.skipLine();
        return self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t');
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn parseIdentifier(self: *LexerParser) ?[]const u8 {
        self.skipBlanks();
        const start = self.pos;
        if (self.pos >= self.source.len or !isIdentStart(self.source[self.pos])) return null;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) self.pos += 1;
        return self.source[start..self.pos];
    }

    fn parseInt(self: *LexerParser) ?i32 {
        self.skipBlanks();
        const start = self.pos;
        if (self.peek() == '-') self.pos += 1;
        const digits = self.pos;
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) self.pos += 1;
        if (self.pos == digits) {
            self.pos = start;
            return null;
        }
        return std.fmt.parseInt(i32, self.source[start..self.pos], 10) catch {
            self.pos = start;
            return null;
        };
    }

    fn expectChar(self: *LexerParser, c: u8) bool {
        self.skipBlanks();
        if (self.peek() == c) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn startsWith(self: *const LexerParser, s: []const u8) bool {
        return std.mem.startsWith(u8, self.source[self.pos..], s);
    }

    /// A whole keyword at the cursor (not a prefix of a longer word).
    fn atKeyword(self: *const LexerParser, kw: []const u8) bool {
        if (!self.startsWith(kw)) return false;
        const e = self.pos + kw.len;
        return e >= self.source.len or !(std.ascii.isAlphanumeric(self.source[e]) or self.source[e] == '_');
    }

    /// Arrow: `→`, `->` or `=>`.
    fn arrowLen(self: *const LexerParser, p: usize) usize {
        const s = self.source;
        if (p + 1 < s.len and (s[p] == '-' or s[p] == '=') and s[p + 1] == '>') return 2;
        if (p + 2 < s.len and s[p] == 0xE2 and s[p + 1] == 0x86 and s[p + 2] == 0x92) return 3;
        return 0;
    }

    // -------------------------------------------------------------------------
    // Section
    // -------------------------------------------------------------------------

    pub fn parseLexerSection(self: *LexerParser) Error!void {
        // Rest of the `@lexer` line.
        try self.endLine();
        while (self.pos < self.source.len) {
            if (self.lineIsBlank()) {
                self.skipLine();
                continue;
            }
            self.skipBlanks();
            if (self.atKeyword("@parser")) break;
            if (self.atKeyword("state")) {
                try self.parseStateBlock();
            } else if (self.atKeyword("after")) {
                try self.parseAfterBlock();
            } else if (self.atKeyword("tokens")) {
                try self.parseTokensBlock();
            } else if (self.atKeyword("@code")) {
                try self.parseCode();
            } else switch (self.peek()) {
                '\'', '"', '[', '.', '@', '(', '\\' => try self.parseRule(),
                else => return self.fail(self.pos, "unrecognized line in the @lexer section: '{s}' (expected state, after, tokens, @code, or a rule)", .{self.wordAt(self.pos)}),
            }
        }
        try self.validate();
    }

    /// `state` followed by indented `name = value` lines, or `state name = value`.
    fn parseStateBlock(self: *LexerParser) Error!void {
        self.pos += "state".len;
        self.skipBlanks();
        if (!self.atEol()) return self.parseStateVar();
        try self.endLine();
        while (self.nextLineIndented()) try self.parseStateVar();
    }

    fn parseStateVar(self: *LexerParser) Error!void {
        self.skipBlanks();
        const at = self.pos;
        const name = self.parseIdentifier() orelse return self.fail(self.pos, "expected a state variable name, found '{s}'", .{self.wordAt(self.pos)});
        for (self.spec.states.items) |s| {
            if (std.mem.eql(u8, s.name, name)) return self.fail(at, "state variable '{s}' is declared twice", .{name});
        }
        if (std.mem.eql(u8, name, "pre")) return self.fail(at, "'pre' is the built-in whitespace count; choose another state variable name", .{});
        if (!self.expectChar('=')) return self.fail(self.pos, "expected '=' after state variable '{s}'", .{name});
        const value = try self.parseStateValue(name);
        try self.spec.states.append(self.allocator, .{ .name = name, .initialValue = value });
        try self.endLine();
    }

    /// An i8 value: an integer, `true` (1) or `false` (0).
    fn parseStateValue(self: *LexerParser, name: []const u8) Error!i32 {
        self.skipBlanks();
        const at = self.pos;
        if (self.atKeyword("true")) {
            self.pos += 4;
            return 1;
        }
        if (self.atKeyword("false")) {
            self.pos += 5;
            return 0;
        }
        const v = self.parseInt() orelse return self.fail(at, "state variable '{s}' needs an integer, true, or false; found '{s}'", .{ name, self.wordAt(at) });
        if (v < -128 or v > 127) return self.fail(at, "value {d} for '{s}' does not fit a state variable (i8, -128..127)", .{ v, name });
        return v;
    }

    /// `after` followed by indented `name = value` lines, or `after name = value`.
    fn parseAfterBlock(self: *LexerParser) Error!void {
        self.pos += "after".len;
        self.skipBlanks();
        if (!self.atEol()) return self.parseAfterAssignment();
        try self.endLine();
        while (self.nextLineIndented()) try self.parseAfterAssignment();
    }

    fn parseAfterAssignment(self: *LexerParser) Error!void {
        self.skipBlanks();
        const at = self.pos;
        const name = self.parseIdentifier() orelse return self.fail(self.pos, "expected 'variable = value' in the after block, found '{s}'", .{self.wordAt(self.pos)});
        if (!self.expectChar('=')) return self.fail(self.pos, "expected '=' after '{s}' in the after block", .{name});
        const value = try self.parseStateValue(name);
        if (!self.isState(name)) return self.fail(at, "after block assigns '{s}', which is not a declared state variable", .{name});
        try self.spec.afterActions.append(self.allocator, .{ .kind = .set, .variable = name, .value = value });
        try self.endLine();
    }

    fn parseTokensBlock(self: *LexerParser) Error!void {
        self.tokensAt = self.pos;
        self.pos += "tokens".len;
        try self.endLine();
        while (self.nextLineIndented()) {
            // One or more names per line, separated by commas or blanks.
            while (true) {
                self.skipBlanks();
                if (self.atEol()) break;
                const at = self.pos;
                const name = self.parseIdentifier() orelse return self.fail(self.pos, "expected a token name, found '{s}'", .{self.wordAt(self.pos)});
                for (self.spec.tokens.items) |t| {
                    if (std.mem.eql(u8, t.name, name)) return self.fail(at, "token '{s}' is declared twice", .{name});
                }
                try self.spec.tokens.append(self.allocator, .{ .name = name });
                _ = self.expectChar(',');
            }
            try self.endLine();
        }
    }

    fn parseCode(self: *LexerParser) Error!void {
        self.pos += "@code".len;
        if (!self.expectChar('=')) return self.fail(self.pos, "expected '=' after @code", .{});
        const name = self.parseIdentifier() orelse return self.fail(self.pos, "expected a function name after '@code ='", .{});
        try self.spec.codeFunctions.append(self.allocator, name);
        try self.endLine();
    }

    // -------------------------------------------------------------------------
    // Rules
    // -------------------------------------------------------------------------

    fn parseRule(self: *LexerParser) Error!void {
        const patStart = self.pos;
        const patEnd = try self.scanPattern();
        var pattern = self.source[patStart..patEnd];
        while (pattern.len > 0 and (pattern[pattern.len - 1] == ' ' or pattern[pattern.len - 1] == '\t')) pattern = pattern[0 .. pattern.len - 1];
        const loc = self.locate(patStart);

        var literal: ?[]const u8 = null;
        if (pattern.len > 0) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            var d: regex.Diagnostic = .{};
            const parsed = regex.parse(arena.allocator(), pattern, &d) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidPattern => return self.fail(patStart + d.offset, "{s}", .{d.message}),
            };
            if (parsed.trail == null) {
                if (try regex.literal(parsed.main, &self.scratch, self.allocator)) |lit| literal = try self.allocator.dupe(u8, lit);
            }
        }

        // Guards
        var guards: std.ArrayListUnmanaged(Guard) = .empty;
        self.skipBlanks();
        if (self.peek() == '@') {
            self.pos += 1;
            while (true) {
                try guards.append(self.allocator, try self.parseGuard());
                self.skipBlanks();
                if (self.peek() != '&') break;
                self.pos += 1;
            }
        }
        if (pattern.len == 0 and guards.items.len == 0) return self.fail(patStart, "a rule needs a pattern or a guard", .{});

        self.skipBlanks();
        const arrow = self.arrowLen(self.pos);
        if (arrow == 0) {
            if (guards.items.len > 0) return self.fail(self.pos, "expected '&' or '→' after the guard, found '{s}'", .{self.wordAt(self.pos)});
            return self.fail(self.pos, "expected '@' or '→' after the pattern, found '{s}'", .{self.wordAt(self.pos)});
        }
        self.pos += arrow;

        const token = self.parseIdentifier() orelse return self.fail(self.pos, "expected a token name after '→', found '{s}'", .{self.wordAt(self.pos)});

        var rule: grammar.LexerRule = .{
            .pattern = pattern,
            .guards = &.{},
            .token = token,
            .actions = &.{},
            .literal = literal,
            .line = loc.line,
            .col = loc.col,
        };
        var actions: std.ArrayListUnmanaged(Action) = .empty;
        while (true) {
            self.skipBlanks();
            if (self.peek() != ',') break;
            self.pos += 1;
            try self.parseRuleAction(&rule, &actions);
        }
        try self.endLine();

        if (rule.hold and rule.rewind != null) return self.fail(patStart, "a rule cannot both hold and rewind", .{});
        if (rule.hold and rule.isSkip) return self.fail(patStart, "a held (zero-width) rule cannot also skip", .{});
        rule.guards = try guards.toOwnedSlice(self.allocator);
        rule.actions = try actions.toOwnedSlice(self.allocator);
        try self.spec.rules.append(self.allocator, rule);
    }

    /// Scan pattern text up to an unquoted `@` or arrow (or end of line);
    /// returns the end offset. Quotes and classes honor backslash escapes.
    fn scanPattern(self: *LexerParser) Error!usize {
        const s = self.source;
        while (self.pos < s.len) {
            const c = s[self.pos];
            if (c == '\n' or c == '#') break;
            if (c == '@') break;
            if (self.arrowLen(self.pos) != 0) break;
            if (c == '\'' or c == '"') {
                const open = self.pos;
                self.pos += 1;
                while (self.pos < s.len and s[self.pos] != c and s[self.pos] != '\n') {
                    if (s[self.pos] == '\\' and self.pos + 1 < s.len and s[self.pos + 1] != '\n') self.pos += 1;
                    self.pos += 1;
                }
                if (self.pos >= s.len or s[self.pos] != c) return self.fail(open, "unterminated quoted literal", .{});
                self.pos += 1;
                continue;
            }
            if (c == '[') {
                const open = self.pos;
                self.pos += 1;
                if (self.peek() == '^') self.pos += 1;
                if (self.peek() == ']') self.pos += 1;
                while (self.pos < s.len and s[self.pos] != ']' and s[self.pos] != '\n') {
                    if (s[self.pos] == '\\' and self.pos + 1 < s.len and s[self.pos + 1] != '\n') self.pos += 1;
                    self.pos += 1;
                }
                if (self.pos >= s.len or s[self.pos] != ']') return self.fail(open, "unclosed '['", .{});
                self.pos += 1;
                continue;
            }
            if (c == '\\' and self.pos + 1 < s.len and s[self.pos + 1] != '\n') {
                self.pos += 2;
                continue;
            }
            self.pos += 1;
        }
        return self.pos;
    }

    fn parseGuard(self: *LexerParser) Error!Guard {
        self.skipBlanks();
        var negated = false;
        if (self.peek() == '!') {
            negated = true;
            self.pos += 1;
        }
        const variable = self.parseIdentifier() orelse return self.fail(self.pos, "expected a state variable or 'pre' in the guard, found '{s}'", .{self.wordAt(self.pos)});
        self.skipBlanks();
        const ops = [_]struct { text: []const u8, op: Guard.Op }{
            .{ .text = "==", .op = .eq }, .{ .text = "!=", .op = .ne },
            .{ .text = ">=", .op = .ge }, .{ .text = "<=", .op = .le },
            .{ .text = ">", .op = .gt },  .{ .text = "<", .op = .lt },
        };
        for (ops) |o| {
            if (!self.startsWith(o.text)) continue;
            // `->` / `=>` is the arrow, not a comparison.
            if (self.arrowLen(self.pos) != 0) break;
            self.pos += o.text.len;
            const at = self.pos;
            const value = self.parseInt() orelse return self.fail(at, "expected a number after '{s}' in the guard, found '{s}'", .{ o.text, self.wordAt(self.skipped(at)) });
            return .{ .variable = variable, .op = o.op, .value = value, .negated = negated };
        }
        return .{ .variable = variable, .op = .truthy, .value = 0, .negated = negated };
    }

    fn skipped(self: *const LexerParser, at: usize) usize {
        var p = at;
        while (p < self.source.len and (self.source[p] == ' ' or self.source[p] == '\t')) p += 1;
        return p;
    }

    fn parseRuleAction(self: *LexerParser, rule: *grammar.LexerRule, actions: *std.ArrayListUnmanaged(Action)) Error!void {
        self.skipBlanks();
        const at = self.pos;
        if (self.peek() == '{') {
            self.pos += 1;
            try actions.append(self.allocator, try self.parseBraceAction());
            self.skipBlanks();
            if (self.peek() != '}') return self.fail(self.pos, "expected '}}' to close the action, found '{s}'", .{self.wordAt(self.pos)});
            self.pos += 1;
            return;
        }
        const word = self.parseIdentifier() orelse return self.fail(at, "expected an action after ',', found '{s}'", .{self.wordAt(at)});
        if (std.mem.eql(u8, word, "skip")) {
            rule.isSkip = true;
        } else if (std.mem.eql(u8, word, "hold")) {
            rule.hold = true;
        } else if (std.mem.eql(u8, word, "simd_to")) {
            if (!self.expectChar('\'')) return self.fail(self.pos, "expected a quoted byte after simd_to, as in simd_to '\\n'", .{});
            const c = try self.parseQuotedByte();
            rule.isSimd = true;
            rule.simdChar = c;
        } else if (std.mem.eql(u8, word, "rewind")) {
            if (!self.expectChar('(')) return self.fail(self.pos, "expected '(' after rewind", .{});
            const n = self.parseInt() orelse return self.fail(self.pos, "expected a byte count in rewind(n)", .{});
            if (n < 0 or n > 65535) return self.fail(at, "rewind({d}) is out of range", .{n});
            if (!self.expectChar(')')) return self.fail(self.pos, "expected ')' after rewind(n)", .{});
            rule.rewind = @intCast(n);
        } else if (std.mem.eql(u8, word, "counting") or std.mem.eql(u8, word, "matching")) {
            return self.fail(at, "{s}() describes balanced nesting, which no finite automaton can recognize; use trailing context '/' for bounded lookahead or handle nesting in the lang Lexer wrapper", .{word});
        } else {
            return self.fail(at, "unknown lexer action '{s}' (expected {{...}}, skip, hold, rewind(n), or simd_to 'c')", .{word});
        }
    }

    /// Inside `{ ... }`: `v = n`, `v = true|false`, `v++`, `v--`, `v = counted('c')`.
    fn parseBraceAction(self: *LexerParser) Error!Action {
        const name = self.parseIdentifier() orelse return self.fail(self.pos, "expected a variable name in the action, found '{s}'", .{self.wordAt(self.pos)});
        self.skipBlanks();
        if (self.startsWith("++")) {
            self.pos += 2;
            return .{ .kind = .inc, .variable = name };
        }
        if (self.startsWith("--")) {
            self.pos += 2;
            return .{ .kind = .dec, .variable = name };
        }
        if (!self.expectChar('=')) return self.fail(self.pos, "expected '=', '++' or '--' after '{s}' in the action", .{name});
        self.skipBlanks();
        if (self.atKeyword("counted")) {
            self.pos += "counted".len;
            if (!self.expectChar('(')) return self.fail(self.pos, "expected '(' after counted", .{});
            if (!self.expectChar('\'')) return self.fail(self.pos, "expected a quoted byte in counted('c')", .{});
            const c = try self.parseQuotedByte();
            if (!self.expectChar(')')) return self.fail(self.pos, "expected ')' after counted('c')", .{});
            return .{ .kind = .counted, .variable = name, .char = c };
        }
        const value = try self.parseStateValue(name);
        return .{ .kind = .set, .variable = name, .value = value };
    }

    /// A single byte in single quotes; the opening quote is already consumed.
    fn parseQuotedByte(self: *LexerParser) Error!u8 {
        const open = self.pos - 1;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var e = self.pos;
        while (e < self.source.len and self.source[e] != '\'' and self.source[e] != '\n') {
            if (self.source[e] == '\\') e += 1;
            e += 1;
        }
        if (e >= self.source.len or self.source[e] != '\'') return self.fail(open, "unterminated quoted byte", .{});
        var d: regex.Diagnostic = .{};
        const p = regex.parse(arena.allocator(), self.source[open .. e + 1], &d) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidPattern => return self.fail(open + d.offset, "{s}", .{d.message}),
        };
        const b = (if (p.main.* == .set) p.main.set.only() else null) orelse return self.fail(open, "expected exactly one byte in quotes", .{});
        self.pos = e + 1;
        return b;
    }

    // -------------------------------------------------------------------------
    // Validation
    // -------------------------------------------------------------------------

    fn isState(self: *const LexerParser, name: []const u8) bool {
        for (self.spec.states.items) |s| if (std.mem.eql(u8, s.name, name)) return true;
        return false;
    }

    fn isToken(self: *const LexerParser, name: []const u8) bool {
        if (std.mem.eql(u8, name, "skip")) return true;
        for (self.spec.tokens.items) |t| if (std.mem.eql(u8, t.name, name)) return true;
        return false;
    }

    fn failAt(self: *LexerParser, line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
        diag.errAt(self.fileName, line, col, fmt, args);
        return error.LexerSectionError;
    }

    /// Names used by rules must be declared: tokens in `tokens` (plus the
    /// built-in `skip`), variables in `state` (guards may also test `pre`,
    /// and actions may assign it).
    fn validate(self: *LexerParser) Error!void {
        for ([_][]const u8{ "eof", "err" }) |required| {
            if (!self.isToken(required)) {
                const loc = self.locate(if (self.tokensAt != 0) self.tokensAt else self.pos);
                return self.failAt(loc.line, loc.col, "the tokens block must declare '{s}' (the lexer emits it at end of input / on unmatched bytes)", .{required});
            }
        }
        for (self.spec.rules.items) |r| {
            if (!self.isToken(r.token)) return self.failAt(r.line, r.col, "token '{s}' is not declared in the tokens block", .{r.token});
            for (r.guards) |g| {
                if (!std.mem.eql(u8, g.variable, "pre") and !self.isState(g.variable))
                    return self.failAt(r.line, r.col, "guard tests '{s}', which is not a declared state variable or 'pre'", .{g.variable});
            }
            for (r.actions) |a| {
                const v = a.variable.?;
                if (std.mem.eql(u8, v, "pre")) {
                    if (a.kind == .inc or a.kind == .dec) return self.failAt(r.line, r.col, "'pre' can only be assigned ({{pre = n}} or {{pre = counted('c')}})", .{});
                } else if (!self.isState(v)) {
                    return self.failAt(r.line, r.col, "action assigns '{s}', which is not a declared state variable", .{v});
                }
            }
        }
    }
};
