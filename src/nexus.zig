// =============================================================================
// nexus.zig — Universal Parser Generator (Lexer + Parser)
//
// Reads a .grammar file with @lexer and @parser sections and generates
// a combined parser.zig module containing both lexer and parser.
//
// Usage: nexus <grammar-file> [output-file]
//
// Author: Steve Shreeve <steve.shreeve@gmail.com>
//   Date: April 2026
// =============================================================================

const std = @import("std");
const Allocator = std.mem.Allocator;

// The generated frontend parser for nexus.grammar itself. It lives alongside
// nexus.zig so the tool can load its own grammar DSL through the same table-
// driven machinery it emits for downstream languages.
const ngp = @import("parser.zig");

const version = "0.10.0";
const max_grammar_bytes: usize = 1 << 20; // 1 MiB cap for .grammar file reads

// =============================================================================
// Source Infrastructure — absolute byte offsets and span-based diagnostics
// =============================================================================

const Source = struct {
    path: []const u8,
    text: []const u8,
    line_starts: []const u32,

    fn init(allocator: Allocator, path: []const u8, text: []const u8) !Source {
        var starts: std.ArrayListUnmanaged(u32) = .empty;
        try starts.append(allocator, 0);
        for (text, 0..) |c, i| {
            if (c == '\n' and i + 1 < text.len) {
                try starts.append(allocator, @intCast(i + 1));
            }
        }
        return .{
            .path = path,
            .text = text,
            .line_starts = try starts.toOwnedSlice(allocator),
        };
    }

    fn deinit(self: *const Source, allocator: Allocator) void {
        allocator.free(self.line_starts);
    }

    fn location(self: *const Source, offset: u32) Location {
        var lo: usize = 0;
        var hi: usize = self.line_starts.len;
        while (lo + 1 < hi) {
            const mid = (lo + hi) / 2;
            if (self.line_starts[mid] <= offset) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        return .{
            .line = @intCast(lo + 1),
            .col = @intCast(offset - self.line_starts[lo] + 1),
        };
    }

    fn lineText(self: *const Source, line: u32) []const u8 {
        if (line == 0 or line > self.line_starts.len) return "";
        const start = self.line_starts[line - 1];
        var end = start;
        while (end < self.text.len and self.text[end] != '\n') : (end += 1) {}
        return self.text[start..end];
    }
};

const Location = struct {
    line: u32,
    col: u32,
};

const Span = struct {
    start: u32,
    end: u32,

    fn text(self: Span, source: *const Source) []const u8 {
        const s: usize = @min(self.start, source.text.len);
        const e: usize = @min(self.end, source.text.len);
        return source.text[s..e];
    }

    fn location(self: Span, source: *const Source) Location {
        return source.location(self.start);
    }
};

const Diagnostic = struct {
    span: Span,
    message: []const u8,
    severity: Severity,

    const Severity = enum { err, warning, note };

    fn print(self: *const Diagnostic, source: *const Source) void {
        const loc = source.location(self.span.start);
        const sev = switch (self.severity) {
            .err => "error",
            .warning => "warning",
            .note => "note",
        };
        std.debug.print("{s}:{d}:{d}: {s}: {s}\n", .{
            source.path, loc.line, loc.col, sev, self.message,
        });
        const line = source.lineText(loc.line);
        if (line.len > 0) {
            std.debug.print("  {s}\n", .{line});
            var i: u32 = 0;
            while (i + 1 < loc.col) : (i += 1) {
                std.debug.print(" ", .{});
            }
            std.debug.print("  ^\n", .{});
        }
    }
};

// =============================================================================
// Lexer DSL Data Structures
// =============================================================================

/// State variable declaration
const StateVar = struct {
    name: []const u8,
    initialValue: i32,
};

/// Token type name
const TokenDef = struct {
    name: []const u8,
};

/// Guard condition
const Guard = struct {
    variable: []const u8,
    op: Op,
    value: i32,
    negated: bool = false,

    const Op = enum {
        eq, // ==
        ne, // !=
        gt, // >
        lt, // <
        ge, // >=
        le, // <=
        truthy, // just variable name (non-zero)
    };
};

/// Action in a lexer rule
const Action = struct {
    kind: Kind,
    variable: ?[]const u8 = null,
    value: ?i32 = null,
    char: ?u8 = null,

    const Kind = enum {
        set, // {var = val}
        inc, // {var++}
        dec, // {var--}
        counted, // {var = counted('x')}
        skip, // skip
        simdTo, // simd_to 'x'
    };
};

/// Lexer rule
const LexerRule = struct {
    pattern: []const u8,
    guards: []const Guard,
    token: []const u8,
    actions: []const Action,
    isSimd: bool = false,
    simdChar: ?u8 = null,
    isSkip: bool = false,
};

/// Default action
const DefaultAction = struct {
    variable: []const u8,
    value: i32,
};

/// Complete lexer specification
const LexerSpec = struct {
    allocator: Allocator,
    states: std.ArrayListUnmanaged(StateVar),
    defaults: std.ArrayListUnmanaged(DefaultAction),
    tokens: std.ArrayListUnmanaged(TokenDef),
    rules: std.ArrayListUnmanaged(LexerRule),
    codeFunctions: std.ArrayListUnmanaged([]const u8),
    langName: ?[]const u8 = null,

    fn init(allocator: Allocator) LexerSpec {
        return .{
            .allocator = allocator,
            .states = .empty,
            .defaults = .empty,
            .tokens = .empty,
            .rules = .empty,
            .codeFunctions = .empty,
        };
    }

    fn deinit(self: *LexerSpec) void {
        for (self.rules.items) |rule| {
            self.allocator.free(rule.guards);
            self.allocator.free(rule.actions);
        }
        self.states.deinit(self.allocator);
        self.defaults.deinit(self.allocator);
        self.tokens.deinit(self.allocator);
        self.rules.deinit(self.allocator);
        self.codeFunctions.deinit(self.allocator);
    }
};

// =============================================================================
// Lexer DSL Parser
// =============================================================================

const LexerParser = struct {
    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    spec: LexerSpec,

    fn init(allocator: Allocator, source: []const u8) LexerParser {
        return .{
            .allocator = allocator,
            .source = source,
            .spec = LexerSpec.init(allocator),
        };
    }

    fn deinit(self: *LexerParser) void {
        self.spec.deinit();
    }

    fn peek(self: *LexerParser) u8 {
        return if (self.pos < self.source.len) self.source[self.pos] else 0;
    }

    fn advance(self: *LexerParser) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') self.line += 1;
            self.pos += 1;
        }
    }

    /// Parse a character, handling escape sequences like \n, \r, \t, \\, \'
    fn parseEscapedChar(self: *LexerParser) u8 {
        const c = self.peek();
        self.advance();
        if (c != '\\') return c;

        // Handle escape sequence
        const escaped = self.peek();
        self.advance();
        return switch (escaped) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            '0' => 0,
            else => escaped,
        };
    }

    fn skipWhitespace(self: *LexerParser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
            } else if (c == '#') {
                // Skip comment to end of line
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    /// Check if the current position is at the start of an indented line.
    /// Skips blank lines and comment-only lines to find the next content line.
    fn atIndentedLine(self: *LexerParser) bool {
        var p = self.pos;
        while (p < self.source.len) {
            if (self.source[p] == ' ' or self.source[p] == '\t') return true;
            if (self.source[p] == '\n') {
                p += 1;
                continue;
            }
            if (self.source[p] == '#') {
                while (p < self.source.len and self.source[p] != '\n') p += 1;
                if (p < self.source.len) p += 1;
                continue;
            }
            return false;
        }
        return false;
    }

    /// Skip to the end of the current line (past the newline).
    fn skipToNextLine(self: *LexerParser) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
        if (self.pos < self.source.len) {
            self.line += 1;
            self.pos += 1;
        }
    }

    /// Skip blank lines and comment-only lines at column 0.
    fn skipBlankLines(self: *LexerParser) void {
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.pos += 1;
                continue;
            }
            if (self.source[self.pos] == '#') {
                self.skipToNextLine();
                continue;
            }
            break;
        }
    }

    fn skipWhitespaceAndNewlines(self: *LexerParser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                if (c == '\n') self.line += 1;
                self.pos += 1;
            } else if (c == '#') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parseIdentifier(self: *LexerParser) ?[]const u8 {
        self.skipWhitespace();
        const start = self.pos;
        if (self.pos >= self.source.len) return null;
        const first = self.source[self.pos];
        if (!((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z') or first == '_')) return null;
        self.pos += 1;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_')
            {
                self.pos += 1;
            } else {
                break;
            }
        }
        return if (self.pos > start) self.source[start..self.pos] else null;
    }

    fn parseInt(self: *LexerParser) ?i32 {
        self.skipWhitespace();
        var negative = false;
        if (self.peek() == '-') {
            negative = true;
            self.advance();
        }
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] >= '0' and self.source[self.pos] <= '9') {
            self.pos += 1;
        }
        if (self.pos == start) return null;
        const num = std.fmt.parseInt(i32, self.source[start..self.pos], 10) catch return null;
        return if (negative) -num else num;
    }

    fn expect(self: *LexerParser, c: u8) bool {
        self.skipWhitespace();
        if (self.peek() == c) {
            self.advance();
            return true;
        }
        return false;
    }

    fn expectStr(self: *LexerParser, s: []const u8) bool {
        self.skipWhitespace();
        if (self.pos + s.len <= self.source.len and
            std.mem.eql(u8, self.source[self.pos..][0..s.len], s))
        {
            self.pos += s.len;
            return true;
        }
        return false;
    }

    /// Check for arrow: =>, ->, or → (UTF-8: 0xE2 0x86 0x92)
    fn expectArrow(self: *LexerParser) bool {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return false;

        // Check for => (fat arrow)
        if (self.pos + 1 < self.source.len and
            self.source[self.pos] == '=' and self.source[self.pos + 1] == '>')
        {
            self.pos += 2;
            return true;
        }

        // Check for -> (ASCII arrow)
        if (self.pos + 1 < self.source.len and
            self.source[self.pos] == '-' and self.source[self.pos + 1] == '>')
        {
            self.pos += 2;
            return true;
        }

        // Check for → (UTF-8: 0xE2 0x86 0x92)
        if (self.pos + 2 < self.source.len and
            self.source[self.pos] == 0xE2 and
            self.source[self.pos + 1] == 0x86 and
            self.source[self.pos + 2] == 0x92)
        {
            self.pos += 3;
            return true;
        }

        return false;
    }

    /// Parse the @lexer section
    fn parseLexerSection(self: *LexerParser) !void {
        self.skipWhitespaceAndNewlines();

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndNewlines();
            if (self.pos >= self.source.len) break;

            // Check for @parser marker (end of lexer section)
            if (self.expectStr("@parser")) {
                break;
            }

            // Parse state declaration
            if (self.expectStr("state")) {
                try self.parseStateDecl();
                continue;
            }

            // Parse defaults block
            if (self.expectStr("after")) {
                try self.parseDefaultsBlock();
                continue;
            }

            // Parse tokens block
            if (self.expectStr("tokens")) {
                try self.parseTokensBlock();
                continue;
            }

            // Parse @code directive in lexer section
            if (self.expectStr("@code")) {
                self.skipWhitespace();
                _ = self.expect('=');
                self.skipWhitespace();
                const name = self.parseIdentifier() orelse return error.ExpectedIdentifier;
                try self.spec.codeFunctions.append(self.spec.allocator, name);
                continue;
            }

            // Parse lexer rule (starts with pattern, including empty-pattern @ guards)
            if (self.peek() == '\'' or self.peek() == '"' or self.peek() == '[' or self.peek() == '.' or self.peek() == '@') {
                try self.parseLexerRule();
                continue;
            }

            // Unrecognized line — log and skip (may be wrapper-handled syntax)
            const lineStart = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            const content = std.mem.trim(u8, self.source[lineStart..self.pos], " \t\r");
            if (content.len > 0) {
                std.debug.print("   ⚠ Skipped lexer line {d} (handled by lang wrapper): {s}\n", .{ self.line, content });
            }
        }
    }

    fn parseStateDecl(self: *LexerParser) !void {
        self.skipWhitespace();
        if (self.peek() != '\n' and self.peek() != '#') return error.ExpectedNewline;
        self.skipToNextLine();
        while (self.atIndentedLine()) {
            try self.parseOneState();
            self.skipWhitespace();
            if (self.peek() == '\n' or self.peek() == '#') self.skipToNextLine();
        }
    }

    fn parseOneState(self: *LexerParser) !void {
        const name = self.parseIdentifier() orelse return error.ExpectedIdentifier;
        if (!self.expect('=')) return error.ExpectedEquals;

        self.skipWhitespace();
        var value: i32 = 0;
        if (self.expectStr("true")) {
            value = 1;
        } else if (self.expectStr("false")) {
            value = 0;
        } else {
            value = self.parseInt() orelse return error.ExpectedValue;
        }

        try self.spec.states.append(self.allocator, .{ .name = name, .initialValue = value });
    }

    fn parseDefaultsBlock(self: *LexerParser) !void {
        self.skipWhitespace();
        if (self.peek() == '\n' or self.peek() == '#') self.skipToNextLine();
        while (self.atIndentedLine()) {
            const name = self.parseIdentifier() orelse {
                self.skipToNextLine();
                continue;
            };
            if (!self.expect('=')) return error.ExpectedEquals;
            const value = self.parseInt() orelse return error.ExpectedValue;
            try self.spec.defaults.append(self.allocator, .{ .variable = name, .value = value });
            self.skipWhitespace();
            if (self.peek() == '\n' or self.peek() == '#') self.skipToNextLine();
        }
    }

    fn parseTokensBlock(self: *LexerParser) !void {
        self.skipToNextLine();
        while (self.atIndentedLine()) {
            self.skipBlankLines();
            if (!self.atIndentedLine()) break;
            const name = self.parseIdentifier() orelse {
                self.skipToNextLine();
                continue;
            };
            try self.spec.tokens.append(self.allocator, .{ .name = name });
            _ = self.expect(',');
            self.skipWhitespace();
            if (self.peek() == '\n' or self.peek() == '#') self.skipToNextLine();
        }
    }

    fn parseLexerRule(self: *LexerParser) !void {
        // Parse pattern
        const pattern = try self.parsePattern();

        // Parse optional guards (@ condition & condition & ...)
        var guards: std.ArrayListUnmanaged(Guard) = .empty;
        defer guards.deinit(self.allocator);

        self.skipWhitespace();
        if (self.expect('@')) {
            while (true) {
                const guard = try self.parseGuard();
                try guards.append(self.allocator, guard);

                // Check for & (multiple guards)
                self.skipWhitespace();
                if (!self.expect('&')) break;
            }
        }

        // Expect arrow: =>, ->, or →
        self.skipWhitespace();
        if (!self.expectArrow()) return error.ExpectedArrow;

        // Parse token name
        const token = self.parseIdentifier() orelse return error.ExpectedTokenName;

        // Parse optional actions
        var actions: std.ArrayListUnmanaged(Action) = .empty;
        defer actions.deinit(self.allocator);

        var isSimd = false;
        var simdChar: ?u8 = null;
        var isSkip = false;

        self.skipWhitespace();
        while (self.expect(',')) {
            self.skipWhitespace();

            if (self.expectStr("simd_to")) {
                isSimd = true;
                self.skipWhitespace();
                if (!self.expect('\'')) return error.ExpectedQuote;
                simdChar = self.parseEscapedChar();
                if (!self.expect('\'')) return error.ExpectedQuote;
                continue;
            }

            if (self.expectStr("skip")) {
                isSkip = true;
                continue;
            }

            // Parse action block {var = val} or {var++} etc.
            if (self.expect('{')) {
                const action = try self.parseAction();
                try actions.append(self.allocator, action);
                if (!self.expect('}')) return error.ExpectedCloseBrace;
            }
        }

        // Store the rule
        try self.spec.rules.append(self.allocator, .{
            .pattern = pattern,
            .guards = try guards.toOwnedSlice(self.allocator),
            .token = token,
            .actions = try actions.toOwnedSlice(self.allocator),
            .isSimd = isSimd,
            .simdChar = simdChar,
            .isSkip = isSkip,
        });
    }

    fn parsePattern(self: *LexerParser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;

        // Scan until we hit unquoted @ or => or end of line
        var inSingleQuote = false;
        var inDoubleQuote = false;
        var inBracket = false;
        var parenDepth: u32 = 0;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\n') break;

            // Track quote/bracket/paren state
            if (!inSingleQuote and !inDoubleQuote and !inBracket) {
                if (c == '\'') {
                    inSingleQuote = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '"') {
                    inDoubleQuote = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '[') {
                    inBracket = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '(') {
                    parenDepth += 1;
                    self.pos += 1;
                    continue;
                }
                if (c == ')' and parenDepth > 0) {
                    parenDepth -= 1;
                    self.pos += 1;
                    continue;
                }
            }

            // Handle closing quotes/brackets
            if (inSingleQuote and c == '\'') {
                inSingleQuote = false;
                self.pos += 1;
                continue;
            }
            if (inDoubleQuote and c == '"') {
                inDoubleQuote = false;
                self.pos += 1;
                continue;
            }
            if (inBracket and c == ']') {
                inBracket = false;
                self.pos += 1;
                continue;
            }

            // Only check for @ and arrows when not inside quotes/brackets/parens
            if (!inSingleQuote and !inDoubleQuote and !inBracket and parenDepth == 0) {
                if (c == '@') break;
                // Check for -> (ASCII arrow)
                if (c == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>') break;
                // Check for → (UTF-8: 0xE2 0x86 0x92)
                if (c == 0xE2 and self.pos + 2 < self.source.len and
                    self.source[self.pos + 1] == 0x86 and self.source[self.pos + 2] == 0x92) break;
            }

            self.pos += 1;
        }

        // Trim trailing whitespace
        var end = self.pos;
        while (end > start and (self.source[end - 1] == ' ' or self.source[end - 1] == '\t')) {
            end -= 1;
        }

        return self.source[start..end];
    }

    fn parseGuard(self: *LexerParser) !Guard {
        self.skipWhitespace();

        var negated = false;
        if (self.expect('!')) {
            negated = true;
        }

        const variable = self.parseIdentifier() orelse return error.ExpectedIdentifier;

        self.skipWhitespace();

        // Check for comparison operator
        var op: Guard.Op = .truthy;
        var value: i32 = 0;

        if (self.expectStr("==")) {
            op = .eq;
            value = self.parseInt() orelse return error.ExpectedValue;
        } else if (self.expectStr("!=")) {
            op = .ne;
            value = self.parseInt() orelse return error.ExpectedValue;
        } else if (self.expectStr(">=")) {
            op = .ge;
            value = self.parseInt() orelse return error.ExpectedValue;
        } else if (self.expectStr("<=")) {
            op = .le;
            value = self.parseInt() orelse return error.ExpectedValue;
        } else if (self.expect('>')) {
            op = .gt;
            value = self.parseInt() orelse return error.ExpectedValue;
        } else if (self.expect('<')) {
            op = .lt;
            value = self.parseInt() orelse return error.ExpectedValue;
        }

        return Guard{
            .variable = variable,
            .op = op,
            .value = value,
            .negated = negated,
        };
    }

    fn parseAction(self: *LexerParser) !Action {
        const name = self.parseIdentifier() orelse return error.ExpectedIdentifier;

        self.skipWhitespace();

        // {var++}
        if (self.expectStr("++")) {
            return Action{ .kind = .inc, .variable = name };
        }

        // {var--}
        if (self.expectStr("--")) {
            return Action{ .kind = .dec, .variable = name };
        }

        // {var = counted('x')} or {var = val}
        if (self.expect('=')) {
            self.skipWhitespace();
            if (self.expectStr("counted")) {
                if (!self.expect('(')) return error.ExpectedOpenParen;
                if (!self.expect('\'')) return error.ExpectedQuote;
                const ch = self.parseEscapedChar();
                if (!self.expect('\'')) return error.ExpectedQuote;
                if (!self.expect(')')) return error.ExpectedCloseParen;
                return Action{ .kind = .counted, .variable = name, .char = ch };
            }
            const value = self.parseInt() orelse return error.ExpectedValue;
            return Action{ .kind = .set, .variable = name, .value = value };
        }

        return error.InvalidAction;
    }
};

// =============================================================================
// Lexer Rule Helpers — shared by lexer/parser code generation
// =============================================================================

fn findTokenForChar(spec: *const LexerSpec, ch: u8) ?[]const u8 {
    var guardedMatch: ?[]const u8 = null;
    for (spec.rules.items) |rule| {
        if (rule.isSkip) continue;

        // Single-quoted char: 'X' or '\n'
        if (rule.pattern.len >= 3 and rule.pattern[0] == '\'') {
            const c: u8 = if (rule.pattern[1] == '\\' and rule.pattern.len >= 4)
                switch (rule.pattern[2]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '\'' => '\'',
                    else => rule.pattern[2],
                }
            else
                rule.pattern[1];
            const close = if (rule.pattern[1] == '\\') @as(usize, 4) else @as(usize, 3);
            if (c == ch and close <= rule.pattern.len) {
                const after = std.mem.trim(u8, rule.pattern[close..], " \t");
                if (after.len == 0) {
                    if (rule.guards.len == 0) return rule.token;
                    if (guardedMatch == null) guardedMatch = rule.token;
                }
            }
        }

        // Double-quoted single char: "X" (used when the char itself is a quote)
        if (rule.pattern.len == 3 and rule.pattern[0] == '"' and rule.pattern[2] == '"') {
            if (rule.pattern[1] == ch) {
                if (rule.guards.len == 0) return rule.token;
                if (guardedMatch == null) guardedMatch = rule.token;
            }
        }
    }
    return guardedMatch;
}

fn findTokenForLiteral(spec: *const LexerSpec, literal: []const u8) ?[]const u8 {
    for (spec.rules.items) |rule| {
        if (rule.isSkip) continue;
        if (rule.pattern.len >= 3 and rule.pattern[0] == '"') {
            var i: usize = 1;
            while (i < rule.pattern.len) : (i += 1) {
                if (rule.pattern[i] == '\\' and i + 1 < rule.pattern.len) {
                    i += 1;
                    continue;
                }
                if (rule.pattern[i] == '"') break;
            }
            if (i < rule.pattern.len) {
                const inner = rule.pattern[1..i];
                if (std.mem.eql(u8, inner, literal)) return rule.token;
            }
        }
    }
    return null;
}

// =============================================================================
// Lexer Code Generator
// =============================================================================

const LexerGenerator = struct {
    allocator: Allocator,
    spec: *const LexerSpec,
    output: std.Io.Writer.Allocating,

    // Rules whose tokenization is emitted at the top of matchRules by
    // generateMultiCharLiteralPreemption. generateOperatorSwitch skips
    // these so the same multi-char literal isn't handled twice.
    preemptedRules: std.ArrayListUnmanaged(usize) = .empty,

    fn structName(self: *const LexerGenerator) []const u8 {
        return if (self.spec.langName != null) "BaseLexer" else "Lexer";
    }

    fn init(allocator: Allocator, spec: *const LexerSpec) LexerGenerator {
        return .{
            .allocator = allocator,
            .spec = spec,
            .output = .init(allocator),
        };
    }

    fn deinit(self: *LexerGenerator) void {
        self.output.deinit();
        self.preemptedRules.deinit(self.allocator);
    }

    fn isRulePreempted(self: *const LexerGenerator, ruleIndex: usize) bool {
        for (self.preemptedRules.items) |idx| {
            if (idx == ruleIndex) return true;
        }
        return false;
    }

    fn write(self: *LexerGenerator, s: []const u8) !void {
        try self.output.writer.writeAll(s);
    }

    fn print(self: *LexerGenerator, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer.print(fmt, args);
    }

    // =========================================================================
    // Generic operator switch generation
    // =========================================================================

    const PatternInfo = struct {
        chars: [8]u8,
        len: u8,
    };

    fn parseLiteralPattern(pattern: []const u8) ?PatternInfo {
        if (pattern.len < 3) return null;
        var info = PatternInfo{ .chars = undefined, .len = 0 };

        if (pattern[0] == '\'' or pattern[0] == '"') {
            const delim = pattern[0];
            var i: usize = 1;
            while (i < pattern.len) {
                if (pattern[i] == delim) {
                    i += 1;
                    const after = std.mem.trim(u8, pattern[i..], " \t");
                    if (after.len != 0) return null;
                    return if (info.len > 0) info else null;
                }
                if (info.len >= 8) return null;
                if (pattern[i] == '\\' and i + 1 < pattern.len) {
                    info.chars[info.len] = switch (pattern[i + 1]) {
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        '\\' => '\\',
                        '\'' => '\'',
                        '"' => '"',
                        else => pattern[i + 1],
                    };
                    i += 2;
                } else {
                    info.chars[info.len] = pattern[i];
                    i += 1;
                }
                info.len += 1;
            }
            return null;
        }
        return null;
    }

    fn charToZigLiteral(c: u8) struct { buf: [4]u8, len: u8 } {
        return switch (c) {
            '\n' => .{ .buf = "\\n".* ++ .{ 0, 0 }, .len = 2 },
            '\r' => .{ .buf = "\\r".* ++ .{ 0, 0 }, .len = 2 },
            '\t' => .{ .buf = "\\t".* ++ .{ 0, 0 }, .len = 2 },
            '\\' => .{ .buf = "\\\\".* ++ .{ 0, 0 }, .len = 2 },
            '\'' => .{ .buf = "\\'".* ++ .{ 0, 0 }, .len = 2 },
            else => .{ .buf = .{ c, 0, 0, 0 }, .len = 1 },
        };
    }

    fn emitGuardCondition(self: *LexerGenerator, guard: Guard) !void {
        const isPre = std.mem.eql(u8, guard.variable, "pre");
        const lhs = if (isPre) "wsCount" else guard.variable;
        const prefix = if (isPre) "" else "self.";

        if (guard.negated and guard.op == .truthy) {
            try self.print("{s}{s} == 0", .{ prefix, lhs });
        } else if (guard.op == .truthy) {
            try self.print("{s}{s} != 0", .{ prefix, lhs });
        } else {
            const op: []const u8 = switch (guard.op) {
                .gt => ">",
                .lt => "<",
                .eq => "==",
                .ne => "!=",
                .ge => ">=",
                .le => "<=",
                .truthy => unreachable,
            };
            try self.print("{s}{s} {s} {d}", .{ prefix, lhs, op, guard.value });
        }
    }

    fn emitAllGuards(self: *LexerGenerator, guards: []const Guard) !void {
        for (guards, 0..) |guard, i| {
            if (i > 0) try self.write(" and ");
            try self.emitGuardCondition(guard);
        }
    }

    fn emitActions(self: *LexerGenerator, actions: []const Action, indent: []const u8) !void {
        for (actions) |action| {
            try self.write(indent);
            switch (action.kind) {
                .set => try self.print("self.{s} = {d};\n", .{ action.variable.?, action.value.? }),
                .inc => try self.print("self.{s} += 1;\n", .{action.variable.?}),
                .dec => try self.print("self.{s} -= 1;\n", .{action.variable.?}),
                .counted => {
                    const ch = charToZigLiteral(action.char.?);
                    try self.print("{{ var count: u8 = 0; while (self.pos < self.source.len and self.source[self.pos] == {s}) {{ self.pos += 1; count +|= 1; while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) self.pos += 1; }} self.{s} = count; }}\n", .{ ch.buf[0..ch.len], action.variable.? });
                },
                else => {},
            }
        }
    }

    fn emitTokenReturn(self: *LexerGenerator, keyword: []const u8, token: []const u8, charCount: u8) !void {
        try self.print("                    {s} Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ keyword, token, charCount });
    }

    /// Find the state variable that complex rules set for a given character.
    /// Used to determine which state variable an @code function affects.
    fn findCodeFnStateVar(self: *LexerGenerator, firstChar: u8) ?[]const u8 {
        for (self.spec.rules.items) |rule| {
            if (parseLiteralPattern(rule.pattern) != null) continue;
            if (rule.pattern.len == 0) continue;
            var startsWith: ?u8 = null;
            if (rule.pattern.len >= 3 and (rule.pattern[0] == '\'' or rule.pattern[0] == '"')) {
                startsWith = rule.pattern[1];
            }
            if (startsWith) |sw| {
                if (sw != firstChar) continue;
            } else continue;
            for (rule.actions) |action| {
                if (action.kind == .set and action.variable != null) return action.variable;
            }
        }
        return null;
    }

    const OpRule = struct {
        chars: [8]u8,
        charCount: u8,
        token: []const u8,
        guards: []const Guard,
        actions: []const Action,
    };

    fn generateOperatorSwitch(self: *LexerGenerator) !void {
        var groups: [256]std.ArrayListUnmanaged(OpRule) = @splat(.empty);
        defer for (&groups) |*g| g.deinit(self.allocator);

        // Build set of characters that start string literal patterns
        // (these are handled by the string scanner, not the operator switch)
        var stringStartChars: [256]bool = @splat(false);
        for (self.spec.rules.items) |rule| {
            const isStringTok = std.mem.startsWith(u8, rule.token, "string");
            if (!isStringTok) continue;
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len >= 3) {
                const delim = rule.pattern[0];
                if (delim == '\'' or delim == '"') {
                    stringStartChars[rule.pattern[1]] = true;
                }
            }
        }

        // Find the comment start character from the grammar
        var commentStartChar: u8 = 0;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "comment")) {
                const info = parseLiteralPattern(rule.pattern) orelse continue;
                if (info.len > 0) commentStartChar = info.chars[0];
                break;
            }
        }

        for (self.spec.rules.items, 0..) |rule, ri| {
            const info = parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len == 0) continue;
            const fc = info.chars[0];
            if (fc == '\n' or fc == '\r') continue;
            if (fc == commentStartChar) continue;
            if (stringStartChars[fc]) continue;
            // Skip rules already emitted by generateMultiCharLiteralPreemption.
            // Keeps the operator switch from redundantly re-handling multi-char
            // literals like MUMPS's `'=`, `'<` or slash's `???`, `??`.
            if (self.isRulePreempted(ri)) continue;

            try groups[fc].append(self.allocator, .{
                .chars = info.chars,
                .charCount = info.len,
                .token = rule.token,
                .guards = rule.guards,
                .actions = rule.actions,
            });
        }

        try self.write(
            \\        // Single/multi-char operators
            \\        self.pos += 1;
            \\        return switch (c) {
            \\
        );

        for (0..256) |i| {
            const c: u8 = @intCast(i);
            if (groups[c].items.len == 0) continue;
            try self.emitSwitchArm(c, groups[c].items, null);
        }

        try self.write(
            \\            else => Token{ .cat = .@"err", .pre = wsCount, .pos = start, .len = 1 },
            \\        };
            \\    }
            \\
        );
    }

    fn emitSwitchArm(self: *LexerGenerator, firstChar: u8, rules: []const OpRule, codeFn: ?[]const u8) !void {
        var singleRules: std.ArrayListUnmanaged(OpRule) = .empty;
        defer singleRules.deinit(self.allocator);
        var multiRules: std.ArrayListUnmanaged(OpRule) = .empty;
        defer multiRules.deinit(self.allocator);

        for (rules) |rule| {
            if (rule.charCount > 1)
                try multiRules.append(self.allocator, rule)
            else
                try singleRules.append(self.allocator, rule);
        }

        const lit = charToZigLiteral(firstChar);
        const litStr = lit.buf[0..lit.len];

        const hasGuards = blk: {
            for (singleRules.items) |r| if (r.guards.len > 0) break :blk true;
            break :blk false;
        };
        const hasActions = blk: {
            for (singleRules.items) |r| if (r.actions.len > 0) break :blk true;
            break :blk false;
        };
        const needsBlk = multiRules.items.len > 0 or hasGuards or hasActions;

        if (!needsBlk) {
            const r = singleRules.items[0];
            try self.print("            '{s}' => Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ litStr, r.token });
            return;
        }

        // Pre-guard shortcut: two rules for same char differing only by pre guard,
        // both producing single-char tokens with no actions.
        // Skip shortcut if pattern-exit logic is needed (requires a block).
        if (multiRules.items.len == 0 and singleRules.items.len == 2 and !hasActions) {
            var guarded: ?[]const u8 = null;
            var default: ?[]const u8 = null;
            for (singleRules.items) |r| {
                if (r.guards.len > 0) {
                    var isPre = false;
                    for (r.guards) |g| {
                        if (std.mem.eql(u8, g.variable, "pre") and !g.negated and
                            (g.op == .truthy or (g.op == .gt and g.value == 0)))
                            isPre = true;
                    }
                    if (isPre) guarded = r.token;
                } else {
                    default = r.token;
                }
            }
            if (guarded != null and default != null) {
                try self.print("            '{s}' => Token{{ .cat = if (wsCount > 0) .@\"{s}\" else .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ litStr, guarded.?, default.? });
                return;
            }
        }

        try self.print("            '{s}' => blk: {{\n", .{litStr});

        // Multi-char rules: group by second char, longest first
        if (multiRules.items.len > 0) {
            try self.emitMultiCharPeekAhead(multiRules.items, 1, codeFn);
        }

        // Single-char rules with guards
        try self.emitGuardedSingleCharRules(singleRules.items);

        // If multi-char rules exist but no unguarded single-char fallback,
        // the blk: may not return. Add a fallback: rewind pos and route to
        // the appropriate scanner, or emit an error token.
        // Skip if guarded rules form an exhaustive chain (2+ guards, no unguarded).
        if (multiRules.items.len > 0) {
            const hasUnguarded = blk: {
                for (singleRules.items) |r| {
                    if (r.guards.len == 0) break :blk true;
                }
                break :blk false;
            };
            var guardedCount: usize = 0;
            for (singleRules.items) |r| {
                if (r.guards.len > 0) guardedCount += 1;
            }
            const exhaustive = !hasUnguarded and guardedCount >= 2;
            if (!hasUnguarded and !exhaustive) {
                // Determine fallback based on what this character starts
                const isStringStart = (firstChar == '\'' or firstChar == '"');
                const isDigit = (firstChar >= '0' and firstChar <= '9');

                if (isStringStart) {
                    // scanString re-reads from start, so rewind pos.
                    try self.write("                self.pos -= 1;\n");
                    try self.write("                break :blk self.scanString(start, wsCount);\n");
                } else if (isDigit) {
                    // scanNumber re-reads from start, so rewind pos.
                    try self.write("                self.pos -= 1;\n");
                    try self.write("                break :blk self.scanNumber(start, wsCount);\n");
                } else {
                    // Err fallback: pos was already advanced by the outer
                    // consumer; emit `len=1` covering the offending byte and
                    // keep `pos` advanced so the next call moves on. (The
                    // previous `self.pos -= 1` here caused an infinite loop in
                    // BaseLexer-only callers such as the syntax highlighter
                    // when the buffer ended mid-token, e.g. `echo $!`.)
                    try self.write("                break :blk Token{ .cat = .@\"err\", .pre = wsCount, .pos = start, .len = 1 };\n");
                }
            }
        }

        try self.write("            },\n");
    }

    fn emitMultiCharPeekAhead(self: *LexerGenerator, rules: []const OpRule, depth: u8, codeFn: ?[]const u8) !void {
        const baseIndent = "                ";
        var indentBuf: [64]u8 = undefined;
        const extra: usize = (@as(usize, depth) - 1) * 4;
        const indent = blk: {
            @memset(&indentBuf, ' ');
            break :blk indentBuf[0 .. baseIndent.len + extra];
        };

        var seenSecond: [256]bool = @splat(false);
        var secondChars: [256]u8 = undefined;
        var secondCount: usize = 0;

        for (rules) |r| {
            if (r.charCount <= depth) continue;
            const sc = r.chars[depth];
            if (!seenSecond[sc]) {
                seenSecond[sc] = true;
                secondChars[secondCount] = sc;
                secondCount += 1;
            }
        }

        for (secondChars[0..secondCount]) |sc| {
            var matching: std.ArrayListUnmanaged(OpRule) = .empty;
            defer matching.deinit(self.allocator);
            for (rules) |r| {
                if (r.charCount > depth and r.chars[depth] == sc)
                    try matching.append(self.allocator, r);
            }

            const scLit = charToZigLiteral(sc);
            const scStr = scLit.buf[0..scLit.len];

            // Check if ALL matching rules share the same guard
            const allSameGuard = blk: {
                if (matching.items.len == 0) break :blk false;
                const firstGuards = matching.items[0].guards;
                for (matching.items[1..]) |r| {
                    if (r.guards.len != firstGuards.len) break :blk false;
                }
                break :blk firstGuards.len > 0;
            };

            if (allSameGuard) {
                try self.write(indent);
                try self.write("if (");
                try self.emitAllGuards(matching.items[0].guards);
                try self.print(" and self.peek() == '{s}') {{\n", .{scStr});
            } else {
                try self.write(indent);
                try self.print("if (self.peek() == '{s}') {{\n", .{scStr});
            }
            try self.write(indent);
            try self.write("    self.pos += 1;\n");

            // Check for deeper (3-char) rules
            var hasDeeper = false;
            for (matching.items) |r| {
                if (r.charCount > depth + 1) {
                    hasDeeper = true;
                    break;
                }
            }
            if (hasDeeper) {
                try self.emitMultiCharPeekAhead(matching.items, depth + 1, codeFn);
            }

            // Emit terminating rules at this depth
            var terminated = false;
            for (matching.items) |r| {
                if (r.charCount == depth + 1) {
                    if (!allSameGuard and r.guards.len > 0) {
                        try self.write(indent);
                        try self.write("    if (");
                        try self.emitAllGuards(r.guards);
                        try self.write(") {\n");
                        try self.emitActions(r.actions, indent);
                        try self.emitTokenReturn("break :blk", r.token, r.charCount);
                        try self.write(indent);
                        try self.write("    }\n");
                    } else if (!terminated) {
                        try self.emitActions(r.actions, indent);
                        try self.emitTokenReturn("break :blk", r.token, r.charCount);
                        terminated = true;
                    }
                }
            }

            // If deeper rules didn't all terminate, rewind pos on failure
            if (!terminated) {
                try self.write(indent);
                try self.write("    self.pos -= 1;\n");
            }
            try self.write(indent);
            try self.write("}\n");
        }
    }

    fn emitGuardedSingleCharRules(self: *LexerGenerator, rules: []const OpRule) !void {
        if (rules.len == 0) return;

        // Separate guarded from unguarded
        var guarded: std.ArrayListUnmanaged(OpRule) = .empty;
        defer guarded.deinit(self.allocator);
        var unguarded: ?OpRule = null;

        for (rules) |r| {
            if (r.guards.len > 0)
                try guarded.append(self.allocator, r)
            else
                unguarded = r;
        }

        // Emit guarded rules as if-chain
        for (guarded.items, 0..) |r, i| {
            const isLast = (i == guarded.items.len - 1);
            if (i == 0) {
                try self.write("                if (");
                try self.emitAllGuards(r.guards);
                try self.write(") {\n");
            } else if (isLast and unguarded == null) {
                try self.write(" else {\n");
            } else {
                try self.write(" else if (");
                try self.emitAllGuards(r.guards);
                try self.write(") {\n");
            }
            try self.emitActions(r.actions, "                    ");
            try self.emitTokenReturn("break :blk", r.token, r.charCount);
            try self.write("                }");
        }

        // Emit unguarded fallback
        if (unguarded) |r| {
            if (guarded.items.len > 0) {
                try self.write("\n");
            }
            try self.emitActions(r.actions, "                ");
            try self.emitTokenReturn("break :blk", r.token, r.charCount);
        } else if (guarded.items.len > 0) {
            // If the last guarded rule was emitted as a bare `else`, the chain
            // is already exhaustive — no fallback needed.
            const exhaustive = guarded.items.len >= 2 and unguarded == null;
            if (!exhaustive) {
                try self.write("\n                break :blk Token{ .cat = .@\"err\", .pre = wsCount, .pos = start, .len = 1 };\n");
            } else {
                try self.write("\n");
            }
        }
    }

    fn generateEmptyPatternGuards(self: *LexerGenerator) !void {
        // Collect rules with empty patterns (guard-only, zero-width tokens)
        var hasAny = false;
        for (self.spec.rules.items) |rule| {
            if (rule.pattern.len > 0) continue;
            if (rule.guards.len == 0) continue;
            hasAny = true;
            break;
        }
        if (!hasAny) return;

        try self.write("        // Empty-pattern guard rules (zero-width tokens based on state)\n");
        for (self.spec.rules.items) |rule| {
            if (rule.pattern.len > 0) continue;
            if (rule.guards.len == 0) continue;

            try self.write("        if (");
            for (rule.guards, 0..) |guard, gi| {
                if (gi > 0) try self.write(" and ");
                try self.emitGuardCondition(guard);
            }
            try self.write(") {\n");

            // Emit actions (e.g., {beg = 0}, {pre = counted('.')})
            for (rule.actions) |action| {
                switch (action.kind) {
                    .set => {
                        if (std.mem.eql(u8, action.variable.?, "pre")) {
                            try self.print("            wsCount = {d};\n", .{@as(u32, @intCast(action.value.?))});
                        } else {
                            try self.print("            self.{s} = {d};\n", .{ action.variable.?, action.value.? });
                        }
                    },
                    .counted => {
                        const ch = charToZigLiteral(action.char.?);
                        try self.print(
                            \\            {{
                            \\                var count: u8 = 0;
                            \\                while (self.pos < self.source.len and self.source[self.pos] == '{s}') {{
                            \\                    self.pos += 1;
                            \\                    count +|= 1;
                            \\                    while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) self.pos += 1;
                            \\                }}
                            \\                wsCount = count;
                            \\            }}
                            \\
                        , .{ch.buf[0..ch.len]});
                    },
                    .inc => try self.print("            self.{s} += 1;\n", .{action.variable.?}),
                    .dec => try self.print("            self.{s} -= 1;\n", .{action.variable.?}),
                    else => {},
                }
            }

            try self.print("            return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = wsStart, .len = @intCast(self.pos - wsStart) }};\n", .{rule.token});
            try self.write("        }\n");
        }
        try self.write("\n");
    }

    fn generateNewlineHandling(self: *LexerGenerator) !void {
        // Collect newline rules from grammar (literal patterns for \n, \r, \r\n)
        const NlRule = struct {
            chars: [2]u8,
            charCount: u8,
            token: []const u8,
            guards: []const Guard,
            actions: []const Action,
        };

        var crlfRules: std.ArrayListUnmanaged(NlRule) = .empty;
        defer crlfRules.deinit(self.allocator);
        var lfRules: std.ArrayListUnmanaged(NlRule) = .empty;
        defer lfRules.deinit(self.allocator);
        var crRules: std.ArrayListUnmanaged(NlRule) = .empty;
        defer crRules.deinit(self.allocator);

        for (self.spec.rules.items) |rule| {
            const info = parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len == 2 and info.chars[0] == '\r' and info.chars[1] == '\n') {
                try crlfRules.append(self.allocator, .{
                    .chars = .{ '\r', '\n' },
                    .charCount = 2,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            } else if (info.len == 1 and info.chars[0] == '\n') {
                try lfRules.append(self.allocator, .{
                    .chars = .{ '\n', 0 },
                    .charCount = 1,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            } else if (info.len == 1 and info.chars[0] == '\r') {
                try crRules.append(self.allocator, .{
                    .chars = .{ '\r', 0 },
                    .charCount = 1,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            }
        }

        if (lfRules.items.len == 0 and crRules.items.len == 0) return;

        try self.write(
            \\        // Newline handling (generated from grammar rules)
            \\        if (c == '\n' or c == '\r') {
            \\
        );

        // CRLF check first (longest match)
        if (crlfRules.items.len > 0) {
            try self.write("            if (c == '\\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\\n') {\n");
            try self.emitNewlineRules(crlfRules.items, 2);
            try self.write("            }\n");
        }

        // Single-char newline rules (\n and standalone \r)
        // After CRLF is excluded, \n and \r have identical handling — use \n rules
        const singleRules = if (lfRules.items.len > 0) lfRules.items else crRules.items;
        if (singleRules.len > 0) {
            try self.emitNewlineRules(singleRules, 1);
        }

        try self.write(
            \\        }
            \\
        );
    }

    fn emitNewlineRules(self: *LexerGenerator, rules: anytype, charCount: u8) !void {
        var guarded: std.ArrayListUnmanaged(@TypeOf(rules[0])) = .empty;
        defer guarded.deinit(self.allocator);
        var unguarded: ?@TypeOf(rules[0]) = null;

        for (rules) |r| {
            if (r.guards.len > 0) {
                try guarded.append(self.allocator, r);
            } else {
                unguarded = r;
            }
        }

        // Consume the newline character(s)
        if (charCount == 2) {
            try self.write("                self.pos += 2;\n");
        } else {
            try self.write("                self.pos += 1;\n");
        }

        for (guarded.items) |r| {
            try self.write("                if (");
            try self.emitAllGuards(r.guards);
            try self.write(") {\n");
            try self.emitActions(r.actions, "                    ");
            try self.print("                    return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, charCount });
            try self.write("                }\n");
        }

        if (unguarded) |r| {
            try self.emitActions(r.actions, "                ");
            try self.print("                return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, charCount });
        }
    }

    fn resolveEscape(pattern: []const u8, pos: usize) struct { ch: u8, next: usize } {
        if (pos < pattern.len and pattern[pos] == '\\' and pos + 1 < pattern.len) {
            return .{ .ch = switch (pattern[pos + 1]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                else => pattern[pos + 1],
            }, .next = pos + 2 };
        }
        return .{ .ch = pattern[pos], .next = pos + 1 };
    }

    fn parseCharClass(pattern: []const u8) ?struct { chars: [256]bool, endPos: usize } {
        if (pattern.len == 0 or pattern[0] != '[') return null;
        var chars: [256]bool = @splat(false);
        var i: usize = 1;
        const negated = i < pattern.len and pattern[i] == '^';
        if (negated) i += 1;
        while (i < pattern.len and pattern[i] != ']') {
            if (pattern[i] == '\\' and i + 1 < pattern.len) {
                switch (pattern[i + 1]) {
                    'w' => {
                        for ('a'..('z' + 1)) |c| chars[c] = true;
                        for ('A'..('Z' + 1)) |c| chars[c] = true;
                        for ('0'..('9' + 1)) |c| chars[c] = true;
                        chars['_'] = true;
                        i += 2;
                        continue;
                    },
                    'd' => {
                        for ('0'..('9' + 1)) |c| chars[c] = true;
                        i += 2;
                        continue;
                    },
                    's' => {
                        chars[' '] = true;
                        chars['\t'] = true;
                        chars['\n'] = true;
                        chars['\r'] = true;
                        i += 2;
                        continue;
                    },
                    else => {},
                }
            }
            const first = resolveEscape(pattern, i);
            if (first.next < pattern.len and pattern[first.next] == '-' and
                first.next + 1 < pattern.len and pattern[first.next + 1] != ']')
            {
                const second = resolveEscape(pattern, first.next + 1);
                var c: u16 = first.ch;
                while (c <= second.ch) : (c += 1) chars[@intCast(c)] = true;
                i = second.next;
            } else {
                chars[first.ch] = true;
                i = first.next;
            }
        }
        if (i >= pattern.len or pattern[i] != ']') return null;
        if (negated) for (0..256) |c| {
            chars[c] = !chars[c];
        };
        return .{ .chars = chars, .endPos = i + 1 };
    }

    const IdentInfo = struct {
        token: []const u8,
        startChars: [256]bool,
        contChars: [256]bool,     // Main-loop continuation class (from [class]* or [class]+ after start)
        hasCont: bool,             // True if the rule had an explicit continuation class
        suffixChars: [256]bool,
        hasSuffix: bool,
    };

    const PunctIdentInfo = struct {
        token: []const u8,
        startChars: [256]bool,
        contChars: [256]bool,
        requireOne: bool, // true for `+` quantifier, false for `*`
        guards: []const Guard,
    };

    /// Collect rules of shape `[punct_class][cont_class]* → token` where the
    /// start class contains no letters/underscore (pure punctuation start).
    /// Examples: Slash's `[./~][\w./-]* → ident` (path-ident) and globs.
    /// These rules cannot use the alpha-led ident fast-path and need their
    /// own pre-switch dispatch so the start char doesn't get consumed as a
    /// standalone operator. Guards are preserved verbatim.
    fn collectPunctIdentRules(spec: *const LexerSpec) !struct {
        rules: [16]PunctIdentInfo,
        count: usize,
    } {
        var result: [16]PunctIdentInfo = undefined;
        var count: usize = 0;

        for (spec.rules.items) |rule| {
            if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real") or
                std.mem.eql(u8, rule.token, "err")) continue;

            const cc = parseCharClass(rule.pattern) orelse continue;

            // Must contain at least one non-alnum-non-underscore char in the
            // start class (e.g. `.`, `/`, `~`, `*`, `?`) AND have no alpha.
            // This is the marker of a genuine punct-start rule: rules that
            // begin with `[0-9]` are number-suffixed idents, not paths.
            var hasAlpha = false;
            var hasPunct = false;
            for (0..256) |c| {
                if (!cc.chars[c]) continue;
                if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
                    hasAlpha = true;
                } else if (c >= 0x20 and c < 0x7f and !(c >= '0' and c <= '9')) {
                    hasPunct = true;
                }
            }
            if (hasAlpha) continue;
            if (!hasPunct) continue;

            // Must have [class]* or [class]+ continuation. `*` allows zero
            // continuation chars (bare leader tokenizes as len-1 ident);
            // `+` requires at least one, which becomes a pre-commit peek
            // gate in the emitted dispatch.
            var pos = cc.endPos;
            while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
            if (pos >= rule.pattern.len or rule.pattern[pos] != '[') continue;
            const cont = parseCharClass(rule.pattern[pos..]) orelse continue;
            pos += cont.endPos;
            if (pos >= rule.pattern.len or
                (rule.pattern[pos] != '*' and rule.pattern[pos] != '+')) continue;
            const requireOne = rule.pattern[pos] == '+';

            if (count >= result.len) {
                std.debug.print("error: too many punct-ident rules (max {d})\n", .{result.len});
                return error.Overflow;
            }
            result[count] = .{
                .token = rule.token,
                .startChars = cc.chars,
                .contChars = cont.chars,
                .requireOne = requireOne,
                .guards = rule.guards,
            };
            count += 1;
        }
        return .{ .rules = result, .count = count };
    }

    fn collectIdentRules(spec: *const LexerSpec) !struct { rules: [8]IdentInfo, count: usize } {
        var result: [8]IdentInfo = undefined;
        var count: usize = 0;

        for (spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real") or
                std.mem.eql(u8, rule.token, "err")) continue;

            var dup = false;
            for (result[0..count]) |existing| {
                if (std.mem.eql(u8, existing.token, rule.token)) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;

            const cc = parseCharClass(rule.pattern) orelse continue;

            var hasAlpha = false;
            for (0..256) |c| {
                if (cc.chars[c] and ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_')) {
                    hasAlpha = true;
                    break;
                }
            }
            if (!hasAlpha) continue;

            // Detect continuation + trailing suffix: parse past body classes.
            //   [class]* / [class]+          → main-loop continuation class
            //   [chars]? / 'c'?              → optional suffix after main loop
            var contChars: [256]bool = @splat(false);
            var hasCont = false;
            var suffixChars: [256]bool = @splat(false);
            var hasSuffix = false;
            var pos = cc.endPos;

            while (pos < rule.pattern.len) {
                if (rule.pattern[pos] == '[') {
                    if (parseCharClass(rule.pattern[pos..])) |cls| {
                        pos += cls.endPos;
                        if (pos < rule.pattern.len and rule.pattern[pos] == '?') {
                            suffixChars = cls.chars;
                            hasSuffix = true;
                            pos += 1;
                        } else if (pos < rule.pattern.len and
                            (rule.pattern[pos] == '*' or rule.pattern[pos] == '+'))
                        {
                            contChars = cls.chars;
                            hasCont = true;
                            hasSuffix = false;
                            pos += 1;
                        } else {
                            hasSuffix = false;
                        }
                    } else break;
                } else if (pos + 2 < rule.pattern.len and rule.pattern[pos] == '\'' and
                    rule.pattern[pos + 2] == '\'')
                {
                    const ch = rule.pattern[pos + 1];
                    pos += 3;
                    if (pos < rule.pattern.len and rule.pattern[pos] == '?') {
                        suffixChars = @splat(false);
                        suffixChars[ch] = true;
                        hasSuffix = true;
                        pos += 1;
                    } else {
                        hasSuffix = false;
                    }
                } else if (rule.pattern[pos] == ' ') {
                    pos += 1;
                } else break;
            }

            if (count >= result.len) {
                std.debug.print("error: too many identifier-like token types (max {d})\n", .{result.len});
                return error.Overflow;
            }
            result[count] = .{
                .token = rule.token,
                .startChars = cc.chars,
                .contChars = contChars,
                .hasCont = hasCont,
                .suffixChars = suffixChars,
                .hasSuffix = hasSuffix,
            };
            count += 1;
        }
        return .{ .rules = result, .count = count };
    }

    fn generateCharClassification(self: *LexerGenerator) !void {
        var letterChars: [256]bool = @splat(false);
        var digitChars: [256]bool = @splat(false);
        var identExtraChars: [256]bool = @splat(false);

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
            if (std.mem.eql(u8, rule.token, "integer") or std.mem.eql(u8, rule.token, "real")) {
                if (parseCharClass(rule.pattern)) |cc| {
                    for (0..256) |c| {
                        if (cc.chars[c]) digitChars[c] = true;
                    }
                }
            }
        }

        const ident = try collectIdentRules(self.spec);
        for (ident.rules[0..ident.count]) |r| {
            for (0..256) |c| {
                if (r.startChars[c]) letterChars[c] = true;
            }
        }

        // IDENT_EXTRA = continuation chars that aren't letters or digits.
        // E.g. Slash's `[\w./-]` yields extras `{'.', '/', '-'}`. Grammars
        // whose continuation is `[\w]` yield an empty extra set.
        for (ident.rules[0..ident.count]) |r| {
            if (!r.hasCont) continue;
            for (0..256) |c| {
                if (!r.contChars[c]) continue;
                if (letterChars[c]) continue;
                if (digitChars[c]) continue;
                identExtraChars[c] = true;
            }
        }
        // Also absorb punct-ident rule continuation chars — but only for
        // UNGUARDED rules. Guarded rules (e.g. Slash's globs with
        // `@ math == 0`) introduce chars like `*` and `?` that must not
        // leak into the globally-shared isIdentChar helper. Those rules
        // emit their own per-rule continuation checks in the pre-switch
        // dispatch.
        const punctIdent = try collectPunctIdentRules(self.spec);
        for (punctIdent.rules[0..punctIdent.count]) |r| {
            if (r.guards.len > 0) continue;
            for (0..256) |c| {
                if (!r.contChars[c]) continue;
                if (letterChars[c]) continue;
                if (digitChars[c]) continue;
                identExtraChars[c] = true;
            }
        }
        var hasIdentExtra = false;
        for (0..256) |c| {
            if (identExtraChars[c]) {
                hasIdentExtra = true;
                break;
            }
        }

        // Emit the char_flags table
        try self.write(
            \\    // Character classification flags (generated from grammar patterns)
            \\    const DIGIT: u8 = 1 << 0;
            \\    const LETTER: u8 = 1 << 1;
            \\    const WHITESPACE: u8 = 1 << 2;
        );
        if (hasIdentExtra) try self.write(
            \\
            \\    const IDENT_EXTRA: u8 = 1 << 3;
        );
        try self.write(
            \\
            \\
            \\    const charFlags: [256]u8 = blk: {
            \\        var table: [256]u8 = [_]u8{0} ** 256;
            \\
        );

        // Emit DIGIT entries
        var hasDigitRange = true;
        for ('0'..('9' + 1)) |c| {
            if (!digitChars[c]) {
                hasDigitRange = false;
                break;
            }
        }
        if (hasDigitRange) {
            try self.write("        for ('0'..'9' + 1) |c| table[c] = DIGIT;\n");
        } else {
            for (0..256) |c| {
                if (digitChars[c]) {
                    const lit = charToZigLiteral(@intCast(c));
                    try self.print("        table['{s}'] = DIGIT;\n", .{lit.buf[0..lit.len]});
                }
            }
        }

        // Emit LETTER entries — check for standard ranges first
        var hasUpper = true;
        var hasLower = true;
        for ('A'..('Z' + 1)) |c| {
            if (!letterChars[c]) {
                hasUpper = false;
                break;
            }
        }
        for ('a'..('z' + 1)) |c| {
            if (!letterChars[c]) {
                hasLower = false;
                break;
            }
        }

        if (hasUpper) try self.write("        for ('A'..'Z' + 1) |c| table[c] = LETTER;\n");
        if (hasLower) try self.write("        for ('a'..'z' + 1) |c| table[c] = LETTER;\n");

        // Emit individual LETTER chars outside standard ranges
        for (0..256) |c| {
            if (!letterChars[c]) continue;
            if (hasUpper and c >= 'A' and c <= 'Z') continue;
            if (hasLower and c >= 'a' and c <= 'z') continue;
            const lit = charToZigLiteral(@intCast(c));
            try self.print("        table['{s}'] = LETTER;\n", .{lit.buf[0..lit.len]});
        }

        // Emit IDENT_EXTRA entries for continuation chars outside letter/digit.
        // These are the `./–` in `[\w./-]` that mainline isIdentChar doesn't cover.
        for (0..256) |c| {
            if (identExtraChars[c]) {
                const lit = charToZigLiteral(@intCast(c));
                try self.print("        table['{s}'] = IDENT_EXTRA;\n", .{lit.buf[0..lit.len]});
            }
        }

        // Whitespace is always space + tab
        try self.write(
            \\        table[' '] = WHITESPACE;
            \\        table['\t'] = WHITESPACE;
            \\        break :blk table;
            \\    };
            \\
            \\    inline fn isDigit(c: u8) bool {
            \\        return (charFlags[c] & DIGIT) != 0;
            \\    }
            \\
            \\    inline fn isLetter(c: u8) bool {
            \\        return (charFlags[c] & LETTER) != 0;
            \\    }
            \\
            \\    inline fn isWhitespace(c: u8) bool {
            \\        return (charFlags[c] & WHITESPACE) != 0;
            \\    }
            \\
            \\
        );
        if (hasIdentExtra) {
            try self.write(
                \\    inline fn isIdentChar(c: u8) bool {
                \\        return (charFlags[c] & (LETTER | DIGIT | IDENT_EXTRA)) != 0;
                \\    }
                \\
            );
        } else {
            try self.write(
                \\    inline fn isIdentChar(c: u8) bool {
                \\        return isLetter(c) or isDigit(c);
                \\    }
                \\
            );
        }
    }

    fn generateScannerDispatch(self: *LexerGenerator) !void {
        // Derive dispatch conditions from grammar patterns
        var hasNumber = false;
        var numberHasLeadingDot = false;
        var hasIdent = false;

        // Collect string patterns (heredocs are handled by the language wrapper, not the engine)
        const StringInfo = struct { openChar: u8, token: []const u8, useDoubledEscape: bool };
        var stringInfos: [4]StringInfo = undefined;
        var stringInfoCount: usize = 0;

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;

            const isStringTok = std.mem.eql(u8, rule.token, "string") or
                std.mem.startsWith(u8, rule.token, "string_");
            if (isStringTok) {
                if (rule.pattern.len >= 3 and (rule.pattern[0] == '\'' or rule.pattern[0] == '"')) {
                    if (rule.pattern[1] != rule.pattern[0]) {
                        if (stringInfoCount < stringInfos.len) {
                            const delim = rule.pattern[0]; // grammar quote delimiter
                            const openChar = rule.pattern[1]; // actual string delimiter in target language
                            const quotedDoubled = [4]u8{ delim, openChar, openChar, delim };
                            stringInfos[stringInfoCount] = .{
                                .openChar = openChar,
                                .token = rule.token,
                                .useDoubledEscape = std.mem.indexOf(u8, rule.pattern, &quotedDoubled) != null,
                            };
                            stringInfoCount += 1;
                        } else {
                            @panic("too many string token patterns (max 4)");
                        }
                    }
                }
            }
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real"))
            {
                hasNumber = true;
                if (std.mem.indexOf(u8, rule.pattern, "'.'") != null and
                    rule.pattern.len > 0 and rule.pattern[0] == '[')
                {
                    const cc = parseCharClass(rule.pattern);
                    if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.endPos..], "* '.'"))
                        numberHasLeadingDot = true;
                }
            }
            if (std.mem.eql(u8, rule.token, "ident") and rule.pattern.len > 0 and rule.pattern[0] == '[') {
                hasIdent = true;
            }
        }

        // String token types
        for (stringInfos[0..stringInfoCount]) |si| {
            const lit = charToZigLiteral(si.openChar);
            const litStr = lit.buf[0..lit.len];

            try self.print(
                \\        if (c == '{s}') {{
            , .{litStr});

            // One escape strategy per string rule: doubled-delimiter or backslash.
            // Grammars needing both should use a lang module Lexer wrapper.
            if (si.useDoubledEscape) {
                // Doubled-quote escape (e.g. '' or ""), stop on \n
                try self.print(
                    \\            self.pos += 1;
                    \\            while (self.pos < self.source.len) {{
                    \\                const ch = self.source[self.pos];
                    \\                if (ch == '{s}') {{
                    \\                    self.pos += 1;
                    \\                    if (self.pos < self.source.len and self.source[self.pos] == '{s}') {{ self.pos += 1; continue; }}
                    \\                    return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\                }}
                    \\                if (ch == '\n') break;
                    \\                self.pos += 1;
                    \\            }}
                    \\            return Token{{ .cat = .@"err", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\        }}
                    \\
                , .{ litStr, litStr, si.token });
            } else {
                // Backslash escape, stop on \n
                try self.print(
                    \\            self.pos += 1;
                    \\            while (self.pos < self.source.len) {{
                    \\                const ch = self.source[self.pos];
                    \\                if (ch == '{s}') {{
                    \\                    self.pos += 1;
                    \\                    return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\                }}
                    \\                if (ch == '\\') {{ self.pos += 2; continue; }}
                    \\                if (ch == '\n') break;
                    \\                self.pos += 1;
                    \\            }}
                    \\            return Token{{ .cat = .@"err", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\        }}
                    \\
                , .{ litStr, si.token });
            }
        }

        // Compound-literal rules like Slash's `flag` (`'-' '-'? [a-zA-Z]...`).
        // The leading literal overlaps with a single-char operator (`-` =>
        // minus), so these must dispatch first and restore pos on no-match.
        try self.generateCompoundLiteralDispatch();

        // Punctuation-start ident rules (paths, globs) — must dispatch BEFORE
        // the number/ident/operator layers so the start char doesn't get
        // consumed by a single-char operator arm. Each rule has its own start
        // class, continuation class, and guards. Falls through cleanly when
        // guards fail or the continuation doesn't match.
        try self.generatePunctIdentDispatch();

        if (hasNumber) {
            // Detect digits that also start multi-char operator rules (e.g. '2>' in slash).
            // Without this, the digit fast-path consumes '2' into scanNumber before the
            // operator switch gets a chance to dispatch the '2>' family.
            var digitHasOpArm: [10]bool = @splat(false);
            var anyDigitOpArm = false;
            for (self.spec.rules.items) |rule| {
                const info = parseLiteralPattern(rule.pattern) orelse continue;
                if (info.len <= 1) continue; // single-char digit token is fine; fast-path handles it
                const fc = info.chars[0];
                if (fc >= '0' and fc <= '9') {
                    digitHasOpArm[fc - '0'] = true;
                    anyDigitOpArm = true;
                }
            }

            // Header comment
            if (numberHasLeadingDot) {
                try self.write("        // Number (digit or leading dot followed by digit)\n");
            } else {
                try self.write("        // Number\n");
            }

            // Fast-path guard. If any digit is also the start of a multi-char
            // operator rule (e.g. '2>' in slash), exclude those digits from
            // the fast-path so the operator switch's arm gets to dispatch.
            // The switch's digit arm has a `self.pos -= 1; scanNumber()`
            // fallback, so a bare digit still reaches number scanning.
            try self.write("        if (");
            if (anyDigitOpArm) try self.write("(");
            try self.write("isDigit(c)");
            if (anyDigitOpArm) {
                for (0..10) |i| {
                    if (digitHasOpArm[i]) {
                        try self.print(" and c != '{d}'", .{i});
                    }
                }
                try self.write(")");
            }
            if (numberHasLeadingDot) {
                try self.write(" or (c == '.' and self.pos + 1 < self.source.len and isDigit(self.source[self.pos + 1]))");
            }
            const nsr = try collectNumericSuffixRules(self.spec);
            if (nsr.count > 0) {
                try self.write(
                    \\) {
                    \\            const tok = self.scanNumber(start, wsCount);
                    \\
                );
                try self.emitNumericSuffixReclassify("            ");
                try self.write(
                    \\            return tok;
                    \\        }
                    \\
                );
            } else {
                try self.write(
                    \\) {
                    \\            return self.scanNumber(start, wsCount);
                    \\        }
                    \\
                );
            }
        }

        if (hasIdent) {
            try self.write(
                \\        // Identifier
                \\        if (isLetter(c)) {
                \\            return self.scanIdent(start, wsCount);
                \\        }
                \\
            );
        }

        // Generate inline prefix scanners for complex patterns that start with a
        // literal character followed by a character class (e.g., '$' [a-zA-Z_]... → variable).
        // These must dispatch before the operator switch to avoid the prefix char being
        // consumed as a standalone operator token.
        try self.generatePrefixScanners();
    }

    const NumericSuffixRule = struct {
        firstClass: [256]bool,      // Consumed by scanNumber
        middle: [8]u8,
        middleLen: u8,
        hasSuffix: bool,            // Optional [class]+ after the middle
        suffixClass: [256]bool,
        token: []const u8,
    };

    /// Detect rules of shape `[class1]+ 'X'... ( [class2]+ )? → token` where
    /// class1 is consumed by scanNumber (e.g. `[0-9]+`). Examples from slash:
    ///   `[0-9]+ '>' → redir_fd_out`
    ///   `[0-9]+ '<' → redir_fd_in`
    ///   `[0-9]+ '>' '&' [0-9]+ → redir_fd_dup`
    /// After scanNumber consumes the digit run, the emitter peeks for the
    /// literal middle (and optional class-suffix), extending the token and
    /// reclassifying its category when the suffix matches.
    fn collectNumericSuffixRules(spec: *const LexerSpec) !struct {
        rules: [8]NumericSuffixRule,
        count: usize,
    } {
        var result: [8]NumericSuffixRule = undefined;
        var count: usize = 0;

        for (spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.actions.len > 0) continue;
            if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;

            const firstCC = parseCharClass(rule.pattern) orelse continue;
            var pos = firstCC.endPos;
            if (pos >= rule.pattern.len or rule.pattern[pos] != '+') continue;
            pos += 1;
            while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;

            // Must be digit-like: first class contains a digit, no alpha.
            var hasAlpha = false;
            var hasDigit = false;
            for (0..256) |c| {
                if (!firstCC.chars[c]) continue;
                if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') hasAlpha = true;
                if (c >= '0' and c <= '9') hasDigit = true;
            }
            if (hasAlpha or !hasDigit) continue;

            // Literal middle: one or more `'X'` chars.
            var middle: [8]u8 = undefined;
            var middleLen: u8 = 0;
            while (pos < rule.pattern.len and rule.pattern[pos] == '\'') {
                if (pos + 2 >= rule.pattern.len or rule.pattern[pos + 2] != '\'') break;
                if (middleLen >= middle.len) break;
                middle[middleLen] = rule.pattern[pos + 1];
                middleLen += 1;
                pos += 3;
                while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
            }
            if (middleLen == 0) continue;

            // Optional suffix: [class]+
            var hasSuffix = false;
            var suffixClass: [256]bool = @splat(false);
            if (pos < rule.pattern.len and rule.pattern[pos] == '[') {
                const sc = parseCharClass(rule.pattern[pos..]) orelse continue;
                pos += sc.endPos;
                if (pos >= rule.pattern.len or rule.pattern[pos] != '+') continue;
                pos += 1;
                suffixClass = sc.chars;
                hasSuffix = true;
                while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
            }
            if (pos != rule.pattern.len) continue;

            if (count >= result.len) {
                std.debug.print("error: too many numeric-suffix rules (max {d})\n", .{result.len});
                return error.Overflow;
            }
            result[count] = .{
                .firstClass = firstCC.chars,
                .middle = middle,
                .middleLen = middleLen,
                .hasSuffix = hasSuffix,
                .suffixClass = suffixClass,
                .token = rule.token,
            };
            count += 1;
        }
        return .{ .rules = result, .count = count };
    }

    /// Emit post-scanNumber peek-and-reclassify for numeric-suffix rules.
    /// Placed at the number fast-path call site: if scanNumber returns an
    /// integer token and the following chars match the literal middle
    /// (and optional class suffix) of a rule, extend pos and reclassify.
    /// Longest-first so `[0-9]+ '>' '&' [0-9]+` beats `[0-9]+ '>'`.
    fn emitNumericSuffixReclassify(self: *LexerGenerator, indent: []const u8) !void {
        const nsr = try collectNumericSuffixRules(self.spec);
        if (nsr.count == 0) return;

        // Sort: longer middle first, with-suffix before without at same length
        const sortFn = struct {
            fn lt(_: void, a: NumericSuffixRule, b: NumericSuffixRule) bool {
                if (a.middleLen != b.middleLen) return a.middleLen > b.middleLen;
                if (a.hasSuffix != b.hasSuffix) return a.hasSuffix and !b.hasSuffix;
                return false;
            }
        }.lt;

        var sorted = nsr.rules;
        std.mem.sort(NumericSuffixRule, sorted[0..nsr.count], {}, sortFn);

        try self.print("{s}if (tok.cat == .@\"integer\") {{\n", .{indent});
        for (sorted[0..nsr.count]) |r| {
            const middleLen: u32 = r.middleLen;
            const minLen: u32 = middleLen + (if (r.hasSuffix) @as(u32, 1) else @as(u32, 0));

            try self.print("{s}    if (self.pos + {d} <= self.source.len", .{ indent, minLen });
            for (0..r.middleLen) |mi| {
                const ml = charToZigLiteral(r.middle[mi]);
                try self.print(" and self.source[self.pos + {d}] == '{s}'", .{ mi, ml.buf[0..ml.len] });
            }
            if (r.hasSuffix) {
                var ix: [64]u8 = undefined;
                const ixStr = try std.fmt.bufPrint(&ix, "self.source[self.pos + {d}]", .{r.middleLen});
                try self.write(" and (");
                try emitCharSetCondition(self, r.suffixClass, ixStr);
                try self.write(")");
            }
            try self.print(") {{\n{s}        self.pos += {d};\n", .{ indent, minLen });
            if (r.hasSuffix) {
                try self.print("{s}        while (self.pos < self.source.len and (", .{indent});
                try emitCharSetCondition(self, r.suffixClass, "self.source[self.pos]");
                try self.write(")) self.pos += 1;\n");
            }
            try self.print(
                "{s}        return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n{s}    }}\n",
                .{ indent, r.token, indent },
            );
        }
        try self.print("{s}}}\n", .{indent});
    }

    /// Top-of-matchRules preemption for rules whose pattern begins with a
    /// multi-char literal (optionally followed by a class-suffix continuation).
    /// Runs BEFORE string scanners, punct-ident, compound-literal, number/ident
    /// fast-paths, and the operator switch.
    ///
    /// Resolves two shadowing bugs surfaced by slash:
    ///   - `"'''" → heredoc_sq` was silently dropped because the sq-string
    ///     scanner (triggered by leader `'`) fired first and consumed the
    ///     triple quotes as an escape-and-unterminated error.
    ///   - `"???" → missing` was preempted by the `[*?]...` punct-ident
    ///     dispatch consuming `?` as a len-1 ident.
    ///
    /// Also fills the shape gap left by `generatePrefixScanners` (single-char
    /// literal prefix + class) for multi-char literal prefix + class:
    /// e.g. `"```" [a-zA-Z][a-zA-Z0-9]* → heredoc_bt`.
    ///
    /// Emission rules:
    ///   - Pattern must start with a literal of length >= 2.
    ///   - Optional suffix: `[class]` (single char) or `[class1][class2]*` or
    ///     `[class1][class2]+`. Single literal chars after the prefix are NOT
    ///     supported here (those are operator-switch territory).
    ///   - Per first-byte bucket: rules emitted longest-first (longer prefix
    ///     wins; with-suffix wins over without at same prefix length; then
    ///     source order). Matches the standard maximal-munch + source-order
    ///     tiebreak rule for lexer alternatives.
    ///   - Guards (if any) are emitted as an inner `if`; on guard-false,
    ///     control falls through to the next candidate / next leader.
    ///   - No match: pos is untouched; control falls through to the rest of
    ///     matchRules.
    fn generateMultiCharLiteralPreemption(self: *LexerGenerator) !void {
        const Suffix = struct {
            startChars: [256]bool,
            contChars: [256]bool,
            hasCont: bool,
            contQuantPlus: bool, // true for +, false for *
        };
        const Rule = struct {
            prefix: [8]u8,
            prefixLen: u8,
            hasSuffix: bool,
            suffix: Suffix,
            token: []const u8,
            guards: []const Guard,
        };

        // Compute the set of leaders whose multi-char literal rules would be
        // shadowed by a non-operator-switch dispatch that runs earlier in
        // matchRules. For these leaders, ALL multi-char literal rules must
        // be hoisted into the preemption block — otherwise the shadowing
        // dispatch consumes the leader before the switch sees it.
        //
        // Sources of shadowing:
        //   - String scanner (delimiter-led open-ended loop)
        //   - Punct-ident dispatch (paths, globs)
        //   - Compound-literal dispatch (`'X' 'X'? [class]...`)
        //
        // Note: class-suffix rules (e.g. `"```" [a-zA-Z]...`) are handled
        // separately — those are emitted in preemption regardless of
        // shadowing because the operator switch can't emit class-suffix
        // consumption. Marking their LEADER as globally shadowed would
        // over-preempt sibling pure-literal rules on that leader (the MUMPS
        // bug em flagged).
        var trulyShadowed: [256]bool = @splat(false);
        for (self.spec.rules.items) |gr| {
            if (!std.mem.startsWith(u8, gr.token, "string")) continue;
            if (gr.guards.len > 0) continue;
            if (gr.pattern.len >= 3 and (gr.pattern[0] == '\'' or gr.pattern[0] == '"')) {
                trulyShadowed[gr.pattern[1]] = true;
            }
        }
        {
            var pir = try collectPunctIdentRules(self.spec);
            const pirSlice = pir.rules[0..pir.count];
            for (pirSlice) |*r| {
                for (0..256) |c| {
                    if (r.startChars[c]) trulyShadowed[c] = true;
                }
            }
        }
        for (self.spec.rules.items) |gr| {
            // Compound-literal leader: pattern starts with `'X' 'X'?`
            if (gr.pattern.len < 7) continue;
            if (gr.pattern[0] != '\'' or gr.pattern[2] != '\'') continue;
            var p: usize = 3;
            while (p < gr.pattern.len and gr.pattern[p] == ' ') p += 1;
            if (p + 3 < gr.pattern.len and gr.pattern[p] == '\'' and
                gr.pattern[p + 2] == '\'' and gr.pattern[p + 3] == '?')
            {
                trulyShadowed[gr.pattern[1]] = true;
            }
        }

        const Collected = struct { rule: Rule, ruleIndex: usize };
        var rules: std.ArrayListUnmanaged(Collected) = .empty;
        defer rules.deinit(self.allocator);

        for (self.spec.rules.items, 0..) |gr, gi| {
            // Parse literal prefix using the same rules as parseLiteralPattern,
            // but accept trailing non-empty pattern content (a class suffix).
            if (gr.pattern.len < 4) continue; // need at least delim + 2 prefix chars + delim
            if (gr.pattern[0] != '\'' and gr.pattern[0] != '"') continue;
            const delim = gr.pattern[0];

            var prefixChars: [8]u8 = undefined;
            var prefixLen: u8 = 0;
            var i: usize = 1;
            var closed = false;
            while (i < gr.pattern.len) : (i += 1) {
                if (gr.pattern[i] == delim) {
                    closed = true;
                    i += 1;
                    break;
                }
                if (prefixLen >= 8) break;
                if (gr.pattern[i] == '\\' and i + 1 < gr.pattern.len) {
                    prefixChars[prefixLen] = switch (gr.pattern[i + 1]) {
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        '\\' => '\\',
                        '\'' => '\'',
                        '"' => '"',
                        else => gr.pattern[i + 1],
                    };
                    i += 1; // consume second char; loop's +=1 handles the escape char
                } else {
                    prefixChars[prefixLen] = gr.pattern[i];
                }
                prefixLen += 1;
            }
            if (!closed or prefixLen < 2) continue;

            // Skip rules with dedicated earlier dispatches or with actions
            // that the preemption block wouldn't reproduce:
            //   - "string"-token rules: delimiter-scan loops, not literals.
            //   - "newline" / "skip" tokens: handled by generateNewlineHandling
            //     and the operator-switch `\\` arm respectively, both of
            //     which also execute state mutations.
            //   - Rules with actions (state mutations) beyond token return:
            //     preemption only emits the return, so action-bearing rules
            //     must stay in their original dispatch.
            if (std.mem.startsWith(u8, gr.token, "string")) continue;
            if (std.mem.eql(u8, gr.token, "newline")) continue;
            if (std.mem.eql(u8, gr.token, "skip")) continue;
            if (gr.actions.len > 0) continue;

            // Optional suffix: [class] (single required) or [class1][class2]* etc.
            var rest = gr.pattern[i..];
            rest = std.mem.trimStart(u8, rest, " ");
            var suffix: Suffix = .{
                .startChars = @splat(false),
                .contChars = @splat(false),
                .hasCont = false,
                .contQuantPlus = false,
            };
            var hasSuffix = false;
            if (rest.len > 0) {
                if (rest[0] != '[') continue; // unsupported suffix shape
                const sc = parseCharClass(rest) orelse continue;
                suffix.startChars = sc.chars;
                hasSuffix = true;
                var p: usize = sc.endPos;
                while (p < rest.len and rest[p] == ' ') p += 1;
                // Optional continuation class with * or +
                if (p < rest.len and rest[p] == '[') {
                    const cc = parseCharClass(rest[p..]) orelse continue;
                    p += cc.endPos;
                    if (p >= rest.len or (rest[p] != '*' and rest[p] != '+')) continue;
                    suffix.contChars = cc.chars;
                    suffix.hasCont = true;
                    suffix.contQuantPlus = rest[p] == '+';
                    p += 1;
                }
                const trailing = std.mem.trimStart(u8, rest[p..], " ");
                if (trailing.len != 0) continue; // disallow more elements
            }

            // Per-rule preemption decision: a rule goes into preemption iff
            //   - Its leader is truly shadowed by an earlier dispatch, OR
            //   - It has a class suffix (operator switch can't emit that shape)
            // Pure multi-char literals on non-shadowed leaders continue to
            // flow through the operator switch where they're already handled
            // correctly — avoids the MUMPS-style duplication em flagged.
            const needsPreemption = trulyShadowed[prefixChars[0]] or hasSuffix;
            if (!needsPreemption) continue;

            try rules.append(self.allocator, .{
                .rule = .{
                    .prefix = prefixChars,
                    .prefixLen = prefixLen,
                    .hasSuffix = hasSuffix,
                    .suffix = suffix,
                    .token = gr.token,
                    .guards = gr.guards,
                },
                .ruleIndex = gi,
            });
            try self.preemptedRules.append(self.allocator, gi);
        }

        if (rules.items.len == 0) return;

        // Group by first byte
        var groups: [256]std.ArrayListUnmanaged(Rule) = @splat(.empty);
        defer for (&groups) |*g| g.deinit(self.allocator);
        for (rules.items) |c| try groups[c.rule.prefix[0]].append(self.allocator, c.rule);

        // Sort each group: longer prefix first, with-suffix before without at
        // same prefix length, then stable (source) order.
        const sortFn = struct {
            fn lt(_: void, a: Rule, b: Rule) bool {
                if (a.prefixLen != b.prefixLen) return a.prefixLen > b.prefixLen;
                if (a.hasSuffix != b.hasSuffix) return a.hasSuffix and !b.hasSuffix;
                return false; // preserve source order
            }
        }.lt;

        try self.write(
            \\        // Multi-char literal preemption (heredoc delimiters,
            \\        // triple-bang operators, etc.) — longest-first; falls
            \\        // through on no match.
            \\
        );

        for (0..256) |bi| {
            const b: u8 = @intCast(bi);
            const grp = &groups[b];
            if (grp.items.len == 0) continue;

            // Zig's std.sort.block is stable-ish; use insertion for tiny groups.
            std.mem.sort(Rule, grp.items, {}, sortFn);

            const lit = charToZigLiteral(b);
            try self.print("        if (c == '{s}') {{\n", .{lit.buf[0..lit.len]});

            for (grp.items) |r| {
                // Build the full match condition. The leader (pos 0) is
                // already c == first char; we need the remaining prefix chars
                // to match at pos+1..pos+prefixLen-1, and (if suffix) the
                // suffix start class to match at pos+prefixLen.
                const minLen: u32 = @as(u32, r.prefixLen) + (if (r.hasSuffix) @as(u32, 1) else @as(u32, 0));

                try self.print("            if (self.pos + {d} <= self.source.len", .{minLen});
                for (1..r.prefixLen) |pi| {
                    const pl = charToZigLiteral(r.prefix[pi]);
                    try self.print(" and self.source[self.pos + {d}] == '{s}'", .{ pi, pl.buf[0..pl.len] });
                }
                if (r.hasSuffix) {
                    // Single-required-char suffix start class.
                    var ix: [64]u8 = undefined;
                    const ixStr = try std.fmt.bufPrint(&ix, "self.source[self.pos + {d}]", .{r.prefixLen});
                    try self.write(" and (");
                    try emitCharSetCondition(self, r.suffix.startChars, ixStr);
                    try self.write(")");
                }
                try self.write(") {\n");

                const bodyIndent = if (r.guards.len > 0) "                " else "                ";
                if (r.guards.len > 0) {
                    try self.write("                if (");
                    try self.emitAllGuards(r.guards);
                    try self.write(") {\n");
                }

                try self.print("{s}self.pos += {d};\n", .{ bodyIndent, minLen });
                if (r.hasSuffix and r.suffix.hasCont) {
                    try self.print("{s}while (self.pos < self.source.len and (", .{bodyIndent});
                    try emitCharSetCondition(self, r.suffix.contChars, "self.source[self.pos]");
                    try self.write(")) self.pos += 1;\n");
                }
                try self.print("{s}return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n", .{ bodyIndent, r.token });

                if (r.guards.len > 0) try self.write("                }\n");
                try self.write("            }\n");
            }

            try self.write("        }\n");
        }
    }

    /// Emit pre-switch dispatch for rules of shape:
    ///     'X' 'X'? [class] [class]* ('=' [class]*)?  → token
    /// Example: Slash's flag rule `'-' '-'? [a-zA-Z][a-zA-Z0-9_-]* ('=' [\w./:@,+-]*)?`.
    /// The leading literal is required; the second literal is optional;
    /// what follows must be an alpha-class char then a continuation class;
    /// the tail `('=' [class]*)?` is optional. On no-match, pos is restored
    /// and control falls through cleanly.
    fn generateCompoundLiteralDispatch(self: *LexerGenerator) !void {
        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue; // only unguarded for now
            const p = rule.pattern;
            if (p.len < 11) continue; // minimum: 'X' 'X'? [A][B]*
            if (p[0] != '\'' or p[2] != '\'') continue;
            const firstChar = p[1];

            // Skip chars handled elsewhere (string delimiters, comment, etc).
            if (firstChar == '\'' or firstChar == '"') continue;
            if ((firstChar >= '0' and firstChar <= '9')) continue;
            if ((firstChar >= 'a' and firstChar <= 'z') or
                (firstChar >= 'A' and firstChar <= 'Z') or firstChar == '_') continue;

            var pos: usize = 3;
            while (pos < p.len and p[pos] == ' ') pos += 1;

            // Optional second literal: 'X'?
            var hasSecondLit = false;
            var secondChar: u8 = 0;
            if (pos + 3 < p.len and p[pos] == '\'' and p[pos + 2] == '\'' and p[pos + 3] == '?') {
                secondChar = p[pos + 1];
                hasSecondLit = true;
                pos += 4;
                while (pos < p.len and p[pos] == ' ') pos += 1;
            }
            if (!hasSecondLit) continue; // this function handles compound-literal only

            // First char class [alpha_class]
            if (pos >= p.len or p[pos] != '[') continue;
            const startCC = parseCharClass(p[pos..]) orelse continue;
            pos += startCC.endPos;
            while (pos < p.len and p[pos] == ' ') pos += 1;

            // Continuation class [cont_class]* or [cont_class]+
            if (pos >= p.len or p[pos] != '[') continue;
            const contCC = parseCharClass(p[pos..]) orelse continue;
            pos += contCC.endPos;
            if (pos >= p.len or (p[pos] != '*' and p[pos] != '+')) continue;
            pos += 1;
            while (pos < p.len and p[pos] == ' ') pos += 1;

            // Optional tail group: ('=' [val_class]*)?
            var hasTail = false;
            var tailSep: u8 = 0;
            var tailCC: ?struct { chars: [256]bool, endPos: usize } = null;
            if (pos < p.len and p[pos] == '(') {
                pos += 1;
                while (pos < p.len and p[pos] == ' ') pos += 1;
                if (pos + 2 < p.len and p[pos] == '\'' and p[pos + 2] == '\'') {
                    tailSep = p[pos + 1];
                    pos += 3;
                    while (pos < p.len and p[pos] == ' ') pos += 1;
                    if (pos < p.len and p[pos] == '[') {
                        if (parseCharClass(p[pos..])) |tcc| {
                            pos += tcc.endPos;
                            if (pos < p.len and (p[pos] == '*' or p[pos] == '+')) {
                                pos += 1;
                                while (pos < p.len and p[pos] == ' ') pos += 1;
                                if (pos < p.len and p[pos] == ')') {
                                    pos += 1;
                                    if (pos < p.len and p[pos] == '?') {
                                        hasTail = true;
                                        tailCC = .{ .chars = tcc.chars, .endPos = 0 };
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Emit the dispatch
            const lit = charToZigLiteral(firstChar);
            const litStr = lit.buf[0..lit.len];
            try self.print(
                \\        // Compound-literal rule for .@"{s}"
                \\        if (c == '{s}') {{
                \\            const save = self.pos;
                \\            self.pos += 1;
                \\
            , .{ rule.token, litStr });

            if (hasSecondLit) {
                const sl = charToZigLiteral(secondChar);
                try self.print(
                    \\            if (self.pos < self.source.len and self.source[self.pos] == '{s}') self.pos += 1;
                    \\
                , .{sl.buf[0..sl.len]});
            }

            // Require at least one char from the start class
            try self.write("            if (self.pos < self.source.len and (");
            try emitCharSetCondition(self, startCC.chars, "self.source[self.pos]");
            try self.write(")) {\n");
            try self.write("                self.pos += 1;\n");
            try self.write("                while (self.pos < self.source.len and (");
            try emitCharSetCondition(self, contCC.chars, "self.source[self.pos]");
            try self.write(")) self.pos += 1;\n");

            if (hasTail) {
                const ts = charToZigLiteral(tailSep);
                try self.print(
                    \\                if (self.pos < self.source.len and self.source[self.pos] == '{s}') {{
                    \\                    self.pos += 1;
                    \\                    while (self.pos < self.source.len and (
                , .{ts.buf[0..ts.len]});
                try emitCharSetCondition(self, tailCC.?.chars, "self.source[self.pos]");
                try self.write(
                    \\)) self.pos += 1;
                    \\                }
                    \\
                );
            }

            try self.print(
                \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\            }}
                \\            self.pos = save;
                \\        }}
                \\
            , .{rule.token});
        }
    }

    /// Emit pre-switch dispatch for punct-start ident rules. Each rule peeks
    /// the next char for continuation-class membership before committing. If
    /// guards or continuation check fails, control falls through to the
    /// remaining scanner stages without consuming any input.
    fn generatePunctIdentDispatch(self: *LexerGenerator) !void {
        const punct = try collectPunctIdentRules(self.spec);
        if (punct.count == 0) return;

        try self.write(
            \\        // Punct-start ident rules (paths, globs)
            \\
        );

        for (punct.rules[0..punct.count]) |r| {
            // Emit start-char test: `if (c == x or c == y or ...)`
            try self.write("        if (");
            var first = true;
            for (0..256) |c| {
                if (!r.startChars[c]) continue;
                if (!first) try self.write(" or ");
                const lit = charToZigLiteral(@intCast(c));
                try self.print("c == '{s}'", .{lit.buf[0..lit.len]});
                first = false;
            }
            try self.write(") {\n");

            // Optional guards. Emitted as a nested `if` that falls through
            // (does nothing, no consumption) when the guard evaluates false.
            if (r.guards.len > 0) {
                try self.write("            if (");
                try self.emitAllGuards(r.guards);
                try self.write(") {\n");
            }

            const inner = if (r.guards.len > 0) "                " else "            ";

            // For `+` quantifier: require at least one continuation char
            // before committing. Emit a pre-commit peek gate; if it fails,
            // control falls through without consuming the leader.
            // For `*` quantifier: commit unconditionally — the start-char
            // match plus any guard is sufficient; the while-loop naturally
            // handles zero-or-more continuation.
            //
            // We emit literal membership checks rather than using the shared
            // isIdentChar helper, so guarded rules with rare continuation
            // chars (e.g. globs with '*', '?') don't pollute the shared
            // continuation set.
            if (r.requireOne) {
                try self.print("{s}const nc = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;\n", .{inner});
                try self.print("{s}if (", .{inner});
                try emitCharSetCondition(self, r.contChars, "nc");
                try self.print(") {{\n", .{});
            }

            const body = if (r.requireOne)
                (if (r.guards.len > 0) "                    " else "                ")
            else
                inner;
            try self.print("{s}self.pos += 1;\n{s}while (self.pos < self.source.len and (", .{ body, body });
            try emitCharSetCondition(self, r.contChars, "self.source[self.pos]");
            try self.print(")) self.pos += 1;\n{s}return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n", .{ body, r.token });

            if (r.requireOne) try self.print("{s}}}\n", .{inner});

            // Close guard block if present
            if (r.guards.len > 0) try self.write("            }\n");
            // Close outer start-char block
            try self.write("        }\n");
        }
    }

    fn generatePrefixScanners(self: *LexerGenerator) !void {
        // Find rules like: '$' [a-zA-Z_]... → variable, '$' '{' ... → var_braced
        // Group by prefix character
        var emittedPrefixes: [256]bool = @splat(false);

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len < 5) continue;

            // Match pattern: 'X' followed by character class or literal
            if (rule.pattern[0] != '\'') continue;
            if (rule.pattern[2] != '\'') continue;
            const prefixChar = rule.pattern[1];

            // Skip if this prefix is handled by string/number/ident/comment scanners
            if (prefixChar == '"' or prefixChar == '\'') continue;
            if (prefixChar >= '0' and prefixChar <= '9') continue;
            if ((prefixChar >= 'a' and prefixChar <= 'z') or
                (prefixChar >= 'A' and prefixChar <= 'Z') or prefixChar == '_' or prefixChar == '%') continue;
            // Skip comment start chars and flag chars (handled elsewhere)
            if (std.mem.eql(u8, rule.token, "comment")) continue;
            if (std.mem.eql(u8, rule.token, "skip")) continue;

            // Must have a 2nd part that's a character class or literal (not just [^\n]*)
            const rest = rule.pattern[3..];
            const trimmed = std.mem.trimStart(u8, rest, " ");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '[' and trimmed.len > 1 and trimmed[1] == '^') continue; // negated class like [^\n]

            if (emittedPrefixes[prefixChar]) continue;

            // Collect all rules with this prefix
            const PrefixRule = struct { pattern: []const u8, token: []const u8, actions: []const Action };
            var prefixRules: [32]PrefixRule = undefined;
            var prefixCount: usize = 0;

            for (self.spec.rules.items) |r| {
                if (r.guards.len > 0) continue;
                if (r.pattern.len < 5) continue;
                if (r.pattern[0] != '\'' or r.pattern[2] != '\'') continue;
                if (r.pattern[1] != prefixChar) continue;
                if (prefixCount < prefixRules.len) {
                    prefixRules[prefixCount] = .{ .pattern = r.pattern, .token = r.token, .actions = r.actions };
                    prefixCount += 1;
                }
            }

            if (prefixCount == 0) continue;
            emittedPrefixes[prefixChar] = true;

            const lit = charToZigLiteral(prefixChar);
            const litStr = lit.buf[0..lit.len];

            // Pre-scan: determine if any prefix rule will emit code that references nc
            var needsNc = false;
            for (prefixRules[0..prefixCount]) |pr| {
                const prSuffix = std.mem.trimStart(u8, pr.pattern[3..], " ");
                if (prSuffix.len > 3 and prSuffix[0] == '\'') {
                    // Literal second char: only emits nc if followed by [^ (scan-to-close pattern)
                    if (std.mem.indexOf(u8, prSuffix[3..], "'")) |closeIdx| {
                        const endPat = prSuffix[3..][0..closeIdx];
                        if (endPat.len >= 3 and endPat[0] == ' ' and endPat[1] == '[' and endPat[2] == '^') {
                            needsNc = true;
                            break;
                        }
                    }
                } else if (prSuffix.len >= 1 and prSuffix[0] == '[') {
                    needsNc = true;
                    break;
                }
            }

            if (!needsNc) continue; // no checks would be emitted for this prefix

            try self.print("        if (c == '{s}') {{\n", .{litStr});
            try self.write("            const nc = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;\n");

            // Emit checks for each rule's second character condition
            for (prefixRules[0..prefixCount]) |pr| {
                // Parse what follows the prefix literal in the pattern
                const prRest = pr.pattern[3..]; // after 'X'
                const prTrimmed = std.mem.trimStart(u8, prRest, " ");

                if (prTrimmed.len >= 3 and prTrimmed[0] == '\'') {
                    // Second literal: '$' '{' → scan until matching close
                    const secondChar = prTrimmed[1];
                    const scLit = charToZigLiteral(secondChar);
                    const scStr = scLit.buf[0..scLit.len];

                    // Find the closing delimiter
                    if (std.mem.indexOf(u8, prTrimmed[3..], "'")) |closeIdx| {
                        const endPattern = prTrimmed[3..][0..closeIdx];
                        if (endPattern.len >= 3 and endPattern[0] == ' ' and endPattern[1] == '[' and endPattern[2] == '^') {
                            // Pattern: '$' '{' [^}\n]+ '}' → scan to closing char
                            if (std.mem.indexOf(u8, endPattern[3..], "]") == null) continue;
                            // Find the close delimiter from the end of the pattern
                            if (std.mem.lastIndexOf(u8, pr.pattern, "'")) |li| {
                                if (li > 3) {
                                    const closeCh = pr.pattern[li - 1];
                                    const clLit = charToZigLiteral(closeCh);
                                    const clStr = clLit.buf[0..clLit.len];
                                    try self.print(
                                        \\            if (nc == '{s}') {{
                                        \\                self.pos += 2;
                                        \\                while (self.pos < self.source.len and self.source[self.pos] != '{s}' and self.source[self.pos] != '\n') self.pos += 1;
                                        \\                if (self.pos < self.source.len and self.source[self.pos] == '{s}') self.pos += 1;
                                        \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                                        \\            }}
                                        \\
                                    , .{ scStr, clStr, clStr, pr.token });
                                }
                            }
                        }
                    }
                } else if (prTrimmed.len >= 1 and prTrimmed[0] == '[') {
                    // Character class: '$' [a-zA-Z_] → scan identifier-like
                    // Check what chars are in the class
                    const hasAlpha = std.mem.indexOf(u8, prTrimmed, "a-z") != null or
                        std.mem.indexOf(u8, prTrimmed, "A-Z") != null;
                    const hasDigit = std.mem.indexOf(u8, prTrimmed, "0-9") != null;
                    const hasSpecial = std.mem.indexOf(u8, prTrimmed, "?$!#*") != null;

                    if (hasAlpha) {
                        // $name pattern: letter/underscore followed by alphanum
                        try self.print(
                            \\            if ((nc >= 'a' and nc <= 'z') or (nc >= 'A' and nc <= 'Z') or nc == '_') {{
                            \\                self.pos += 1;
                            \\                while (self.pos < self.source.len) {{
                            \\                    const vc = self.source[self.pos];
                            \\                    if (!((vc >= 'a' and vc <= 'z') or (vc >= 'A' and vc <= 'Z') or (vc >= '0' and vc <= '9') or vc == '_')) break;
                            \\                    self.pos += 1;
                            \\                }}
                            \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                            \\            }}
                            \\
                        , .{pr.token});
                    } else if (hasDigit) {
                        // $0-$9 pattern
                        try self.print(
                            \\            if (nc >= '0' and nc <= '9') {{
                            \\                self.pos += 2;
                            \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = 2 }};
                            \\            }}
                            \\
                        , .{pr.token});
                    } else if (hasSpecial) {
                        // $?, $$, $!, $#, $*
                        try self.print(
                            \\            if (nc == '?' or nc == '$' or nc == '!' or nc == '#' or nc == '*') {{
                            \\                self.pos += 2;
                            \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = 2 }};
                            \\            }}
                            \\
                        , .{pr.token});
                    }
                }
            }

            try self.write("        }\n");
        }
    }

    fn generateScanners(self: *LexerGenerator) !void {
        try self.generateNumberScanner();
        try self.generateIdentScanner();
    }

    fn generateNumberScanner(self: *LexerGenerator) !void {
        // Analyze number patterns to detect features
        var hasDecimal = false;
        var hasExponent = false;
        var hasLeadingDot = false;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "real")) {
                if (std.mem.indexOf(u8, rule.pattern, "'.'") != null) hasDecimal = true;
                if (std.mem.indexOf(u8, rule.pattern, "[Ee]") != null) hasExponent = true;
                if (rule.pattern.len > 0 and rule.pattern[0] == '[') {
                    const cc = parseCharClass(rule.pattern);
                    if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.endPos..], "* '.'"))
                        hasLeadingDot = true;
                }
            }
        }

        // Check if any number patterns exist
        var hasAny = false;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real"))
            {
                hasAny = true;
                break;
            }
        }
        if (!hasAny) return;

        try self.write(
            \\
            \\    /// Scan number (generated from grammar)
            \\    fn scanNumber(self: *Self, start: u32, ws: u8) Token {
        );

        if (hasDecimal) {
            try self.write(
                \\        var hasDecimal = false;
            );
        }
        if (hasExponent) {
            try self.write(
                \\        var hasExponent = false;
            );
        }
        if (hasLeadingDot) {
            try self.write(
                \\        const startsWithDot = self.source[self.pos] == '.';
            );
        }

        // Check for grammar-defined number prefix patterns (e.g., 0x hex, 0b binary, 0o octal)
        const hasPrefixed = self.hasNumberPrefixPatterns();
        if (hasPrefixed) {
            try self.write(
                \\
                \\        // Number prefix patterns (from grammar)
                \\        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
                \\            const prefix = self.source[self.pos + 1];
                \\
            );
            try self.emitNumberPrefixBranches();
            try self.write(
                \\        }
                \\
            );
        }

        // Integer part
        try self.write(
            \\        // Decimal integer
            \\        if (isDigit(self.source[self.pos])) {
            \\            while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
            \\                self.pos += 1;
            \\            }
            \\        }
            \\
        );

        // Decimal part
        if (hasDecimal) {
            try self.write(
                \\        // Decimal part
                \\        if (self.pos < self.source.len and self.source[self.pos] == '.') {
                \\            const nextC = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;
                \\            if (isDigit(nextC)) {
                \\                hasDecimal = true;
                \\                self.pos += 1;
                \\                while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
                \\                    self.pos += 1;
                \\                }
                \\            }
                \\        }
                \\
            );
        }

        // Exponent part
        if (hasExponent) {
            try self.write(
                \\        // Exponent part
                \\        if (self.pos < self.source.len) {
                \\            const e = self.source[self.pos];
                \\            if (e == 'E' or e == 'e') {
                \\                var expPos = self.pos + 1;
                \\                if (expPos < self.source.len and (self.source[expPos] == '+' or self.source[expPos] == '-')) {
                \\                    expPos += 1;
                \\                }
                \\                if (expPos < self.source.len and isDigit(self.source[expPos])) {
                \\                    hasExponent = true;
                \\                    self.pos = expPos;
                \\                    while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
                \\                        self.pos += 1;
                \\                    }
                \\                }
                \\            }
                \\        }
                \\
            );
        }

        // Classification
        if (hasDecimal or hasExponent or hasLeadingDot) {
            try self.write("        // Classify\n");
            try self.write("        const tokenCat: TokenCat = ");

            if (hasDecimal or hasExponent or hasLeadingDot) {
                try self.write("if (");
                var firstCond = true;
                if (hasDecimal) {
                    try self.write("hasDecimal");
                    firstCond = false;
                }
                if (hasExponent) {
                    if (!firstCond) try self.write(" or ");
                    try self.write("hasExponent");
                    firstCond = false;
                }
                if (hasLeadingDot) {
                    if (!firstCond) try self.write(" or ");
                    try self.write("startsWithDot");
                }
                try self.write(")\n            .@\"real\"\n");
                try self.write("        else\n            .@\"integer\";\n");
            }

            try self.write(
                \\
                \\        return Token{ .cat = tokenCat, .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
                \\    }
                \\
            );
        } else {
            try self.write(
                \\        return Token{ .cat = .@"integer", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
                \\    }
                \\
            );
        }
    }

    /// Check if grammar defines number prefix patterns like '0' [xX] ...
    fn hasNumberPrefixPatterns(self: *LexerGenerator) bool {
        for (self.spec.rules.items) |rule| {
            if (!std.mem.eql(u8, rule.token, "integer")) continue;
            if (rule.pattern.len >= 5 and rule.pattern[0] == '\'' and
                rule.pattern[1] == '0' and rule.pattern[2] == '\'')
                return true;
        }
        return false;
    }

    /// Emit prefix branches for grammar-defined patterns like '0' [xX] [0-9a-fA-F]+
    fn emitNumberPrefixBranches(self: *LexerGenerator) !void {
        var first = true;
        for (self.spec.rules.items) |rule| {
            if (!std.mem.eql(u8, rule.token, "integer")) continue;
            if (rule.pattern.len < 5 or rule.pattern[0] != '\'' or
                rule.pattern[1] != '0' or rule.pattern[2] != '\'') continue;

            // Parse: '0' [xXbBoO] [digit-class]+
            const rest = std.mem.trimStart(u8, rule.pattern[3..], " ");
            if (rest.len < 3 or rest[0] != '[') continue;
            const close = std.mem.indexOfScalar(u8, rest, ']') orelse continue;
            const charClass = rest[1..close];
            const digitPart = std.mem.trimStart(u8, rest[close + 1 ..], " ");

            // Build condition for prefix char
            if (!first) {
                try self.write("            else ");
            } else {
                try self.write("            ");
                first = false;
            }
            try self.write("if (");
            var firstCond = true;
            var i: usize = 0;
            while (i < charClass.len) {
                if (!firstCond) try self.write(" or ");
                firstCond = false;
                try self.print("prefix == '{c}'", .{charClass[i]});
                i += 1;
            }
            try self.write(") {\n");
            try self.write("                self.pos += 2;\n");

            // Build digit scanning loop from the digit class pattern
            if (digitPart.len > 0 and digitPart[0] == '[') {
                const dclose = std.mem.indexOfScalar(u8, digitPart, ']') orelse continue;
                const dclass = digitPart[1..dclose];
                try self.write("                while (self.pos < self.source.len) {\n");
                try self.write("                    const dc = self.source[self.pos];\n");
                try self.write("                    if (");
                // Parse ranges in digit class
                var di: usize = 0;
                var firstDc = true;
                while (di < dclass.len) {
                    if (di + 2 < dclass.len and dclass[di + 1] == '-') {
                        if (!firstDc) try self.write(" or ");
                        firstDc = false;
                        try self.print("(dc >= '{c}' and dc <= '{c}')", .{ dclass[di], dclass[di + 2] });
                        di += 3;
                    } else {
                        if (!firstDc) try self.write(" or ");
                        firstDc = false;
                        try self.print("dc == '{c}'", .{dclass[di]});
                        di += 1;
                    }
                }
                try self.write(" or dc == '_'");
                try self.write(") {\n");
                try self.write("                        self.pos += 1;\n");
                try self.write("                    } else break;\n");
                try self.write("                }\n");
            }

            try self.write("                return Token{ .cat = .@\"integer\", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };\n");
            try self.write("            }\n");
        }
    }

    fn generateIdentScanner(self: *LexerGenerator) !void {
        const ident = try collectIdentRules(self.spec);
        const identRules = ident.rules;
        const identCount = ident.count;

        // Emit body loop
        try self.write(
            \\
            \\    /// Scan identifier (generated from grammar)
            \\    fn scanIdent(self: *Self, start: u32, ws: u8) Token {
            \\        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
            \\            self.pos += 1;
            \\        }
            \\
        );

        // Check for non-ident tokens that need first-char discrimination
        var hasAltTokens = false;
        for (identRules[0..identCount]) |r| {
            if (!std.mem.eql(u8, r.token, "ident")) {
                hasAltTokens = true;
                break;
            }
        }

        if (hasAltTokens) {
            try self.write("        const first = self.source[start];\n");
            for (identRules[0..identCount]) |r| {
                if (std.mem.eql(u8, r.token, "ident")) continue;

                try self.write("        if (");
                try emitCharSetCondition(self, r.startChars, "first");

                try self.write(") {\n");
                if (r.hasSuffix) try self.emitIdentSuffix(r.suffixChars, "            ");

                try self.print("            return Token{{ .cat = .@\"{s}\", .pre = ws, .pos = start, .len = @intCast(self.pos - start) }};\n", .{r.token});
                try self.write("        }\n");
            }
        }

        // Suffix handling for the ident rule
        for (identRules[0..identCount]) |r| {
            if (std.mem.eql(u8, r.token, "ident") and r.hasSuffix) {
                try self.emitIdentSuffix(r.suffixChars, "        ");
                break;
            }
        }

        try self.write(
            \\        return Token{ .cat = .@"ident", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
            \\    }
            \\
        );
    }

    fn emitIdentSuffix(self: *LexerGenerator, suffixChars: [256]bool, indent: []const u8) !void {
        var chars: [8]u8 = undefined;
        var n: usize = 0;
        for (0..256) |c| {
            if (suffixChars[c]) {
                if (n >= chars.len) {
                    std.debug.print("error: too many suffix characters (max {d})\n", .{chars.len});
                    return error.Overflow;
                }
                chars[n] = @intCast(c);
                n += 1;
            }
        }
        if (n == 0) return;

        try self.print("{s}if (self.pos < self.source.len and ", .{indent});
        if (n == 1) {
            const lit = charToZigLiteral(chars[0]);
            try self.print("self.source[self.pos] == '{s}')\n", .{lit.buf[0..lit.len]});
        } else {
            try self.write("(");
            for (0..n) |i| {
                if (i > 0) try self.write(" or ");
                const lit = charToZigLiteral(chars[i]);
                try self.print("self.source[self.pos] == '{s}'", .{lit.buf[0..lit.len]});
            }
            try self.write("))\n");
        }
        try self.print("{s}    self.pos += 1;\n", .{indent});
    }

    fn emitCharSetCondition(self: *LexerGenerator, chars: [256]bool, varName: []const u8) !void {
        var ranges: [128]struct { lo: u8, hi: u8 } = undefined;
        var rangeCount: usize = 0;
        var i: u16 = 0;
        while (i < 256) {
            if (chars[i]) {
                const lo: u8 = @intCast(i);
                while (i < 256 and chars[i]) i += 1;
                const hi: u8 = @intCast(i - 1);
                ranges[rangeCount] = .{ .lo = lo, .hi = hi };
                rangeCount += 1;
            } else {
                i += 1;
            }
        }
        if (rangeCount == 0) {
            try self.write("false");
            return;
        }
        for (ranges[0..rangeCount], 0..) |rng, ri| {
            if (ri > 0) try self.write(" or ");
            if (rng.lo == rng.hi) {
                const lit = charToZigLiteral(rng.lo);
                try self.print("{s} == '{s}'", .{ varName, lit.buf[0..lit.len] });
            } else {
                const loLit = charToZigLiteral(rng.lo);
                const hiLit = charToZigLiteral(rng.hi);
                try self.print("({s} >= '{s}' and {s} <= '{s}')", .{ varName, loLit.buf[0..loLit.len], varName, hiLit.buf[0..hiLit.len] });
            }
        }
    }

    fn generateCommentHandling(self: *LexerGenerator) !void {
        for (self.spec.rules.items) |rule| {
            if (!std.mem.eql(u8, rule.token, "comment")) continue;

            // Extract the leading literal char from the pattern (e.g., ';' or '#')
            const startChar = blk: {
                if (rule.pattern.len >= 3 and rule.pattern[0] == '\'') {
                    if (rule.pattern[1] == '\\' and rule.pattern.len >= 4)
                        break :blk switch (rule.pattern[2]) {
                            'n' => @as(u8, '\n'),
                            'r' => '\r',
                            't' => '\t',
                            '\\' => '\\',
                            '\'' => '\'',
                            else => rule.pattern[2],
                        }
                    else
                        break :blk rule.pattern[1];
                }
                continue;
            };

            const startLit = charToZigLiteral(startChar);
            const startStr = startLit.buf[0..startLit.len];

            if (rule.isSimd and rule.simdChar != null) {
                const stopLit = charToZigLiteral(rule.simdChar.?);
                const stopStr = stopLit.buf[0..stopLit.len];

                try self.print(
                    \\        // Comment (SIMD accelerated, generated from grammar)
                    \\        if (c == '{s}') {{
                    \\            self.pos += 1;
                    \\            const remaining = self.source[self.pos..];
                    \\            const offset = simd.findByte(remaining, '{s}');
                    \\            self.pos += @intCast(offset);
                    \\            return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\        }}
                    \\
                , .{ startStr, stopStr, rule.token });
            } else {
                try self.print(
                    \\        // Comment (scan to end of line)
                    \\        if (c == '{s}') {{
                    \\            while (self.pos < self.source.len and self.source[self.pos] != '\n') {{
                    \\                self.pos += 1;
                    \\            }}
                    \\            return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                    \\        }}
                    \\
                , .{ startStr, rule.token });
            }
        }
    }

    fn generate(self: *LexerGenerator) ![]const u8 {
        // Header
        try self.print("//! Generated by nexus v{s} — do not edit\n", .{version});
        try self.write(
            \\
            \\const std = @import("std");
            \\
            \\
        );

        // Generate TokenCat enum
        try self.generateTokenCat();

        // Generate Token struct
        try self.generateTokenStruct();

        // Generate Lexer struct
        try self.generateLexerStruct();

        return self.output.toOwnedSlice();
    }

    fn generateTokenCat(self: *LexerGenerator) !void {
        try self.write(
            \\// =============================================================================
            \\// TOKEN CATEGORIES
            \\// =============================================================================
            \\
            \\pub const TokenCat = enum(u8) {
            \\
        );

        for (self.spec.tokens.items) |tok| {
            try self.print("    @\"{s}\",\n", .{tok.name});
        }

        // Add internal skip token
        try self.write(
            \\
            \\    // Internal (used by generator)
            \\    @"skip",
            \\};
            \\
            \\
        );
    }

    fn generateTokenStruct(self: *LexerGenerator) !void {
        try self.write(
            \\// =============================================================================
            \\// TOKEN STRUCT (8 bytes)
            \\// =============================================================================
            \\
            \\pub const Token = struct {
            \\    pos: u32,         // Byte position in source (4 bytes)
            \\    len: u16,         // Token length in bytes (2 bytes)
            \\    cat: TokenCat,    // Token category (1 byte)
            \\    pre: u8,          // Preceding whitespace count (1 byte)
            \\
            \\    comptime {
            \\        std.debug.assert(@sizeOf(Token) == 8);
            \\    }
            \\};
            \\
            \\
        );
    }

    fn generateLexerStruct(self: *LexerGenerator) !void {
        // When @lang is set, generate BaseLexer (lang module may wrap it).
        // When not set, generate Lexer directly (self-contained).
        const sname = if (self.spec.langName != null) "BaseLexer" else "Lexer";

        try self.write(
            \\// =============================================================================
            \\// LEXER
            \\// =============================================================================
            \\
        );
        try self.print("pub const {s} = struct {{\n", .{sname});

        // Internal self-type alias so generated methods work regardless
        // of whether the struct is named Lexer or BaseLexer.
        try self.write("    const Self = @This();\n\n");

        try self.write(
            \\    source: []const u8,
            \\    pos: u32,
            \\
        );

        try self.write("    aux: u16 = 0,\n");

        // State variables
        try self.write("    // State variables\n");
        for (self.spec.states.items) |state| {
            try self.print("    {s}: i8,\n", .{state.name});
        }

        // Init function
        try self.write(
            \\
            \\    pub fn init(source: []const u8) Self {
            \\        return .{
            \\            .source = source,
            \\            .pos = 0,
            \\
        );
        for (self.spec.states.items) |state| {
            try self.print("            .{s} = {d},\n", .{ state.name, state.initialValue });
        }
        try self.write(
            \\        };
            \\    }
            \\
            \\
        );

        // Text function
        try self.write(
            \\    /// Get the text slice for a token (zero-copy into source)
            \\    pub fn text(self: *const Self, tok: Token) []const u8 {
            \\        const start: usize = tok.pos;
            \\        const end: usize = @min(start + tok.len, self.source.len);
            \\        if (start >= self.source.len) return "";
            \\        return self.source[start..end];
            \\    }
            \\
            \\
        );

        // Reset function
        try self.write("    /// Reset lexer to beginning\n");
        try self.write("    pub fn reset(self: *Self) void {\n");
        try self.write("        self.pos = 0;\n");
        for (self.spec.states.items) |state| {
            try self.print("        self.{s} = {d};\n", .{ state.name, state.initialValue });
        }
        try self.write("    }\n\n");

        // Peek function
        try self.write(
            \\    /// Peek at current character (0 if at end)
            \\    inline fn peek(self: *const Self) u8 {
            \\        return if (self.pos < self.source.len) self.source[self.pos] else 0;
            \\    }
            \\
            \\    /// Peek at character at offset (0 if at end)
            \\    inline fn peekAt(self: *const Self, offset: u32) u8 {
            \\        const p = self.pos + offset;
            \\        return if (p < self.source.len) self.source[p] else 0;
            \\    }
            \\
            \\
        );

        // Next function (simple - matchRules handles everything)
        try self.write(
            \\    /// Get next token
            \\    pub fn next(self: *Self) Token {
            \\        return self.matchRules();
            \\    }
            \\
            \\
        );

        try self.generateMatchRules();

        try self.write("};\n");

        // When @lang is set, alias Lexer from the lang module (if it provides one)
        // or fall back to BaseLexer. This lets lang modules wrap the generated lexer.
        if (self.spec.langName) |lang| {
            try self.print(
                \\
                \\pub const Lexer = if (@hasDecl({s}, "Lexer")) {s}.Lexer else BaseLexer;
                \\
            , .{ lang, lang });
        }
    }

    fn generateMatchRules(self: *LexerGenerator) !void {
        try self.generateCharClassification();

        // Generate @code function wrappers (imported from @lang module)
        for (self.spec.codeFunctions.items) |funcName| {
            if (self.spec.langName) |lang| {
                const stateVar = self.findCodeFnStateVar('?') orelse "pat";
                try self.print(
                    \\    fn {s}(self: *Self) void {{
                    \\        if ({s}.{s}(self.source, self.pos)) self.{s} = 1;
                    \\    }}
                    \\
                , .{ funcName, lang, funcName, stateVar });
            }
        }

        // Determine if any rule action assigns to wsCount (the grammar's "pre" variable)
        var wsCountMutable = false;
        outer: for (self.spec.rules.items) |rule| {
            for (rule.actions) |action| {
                if ((action.kind == .set or action.kind == .counted) and
                    action.variable != null and std.mem.eql(u8, action.variable.?, "pre"))
                {
                    wsCountMutable = true;
                    break :outer;
                }
            }
        }

        try self.write(
            \\    /// Match lexer rules
            \\    pub fn matchRules(self: *Self) Token {
            \\        // Count whitespace first
            \\        const wsStart = self.pos;
            \\        while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) {
            \\            self.pos += 1;
            \\        }
            \\
        );
        try self.print("        {s} wsCount: u8 = @intCast(@min(self.pos - wsStart, 255));\n", .{if (wsCountMutable) "var" else "const"});
        try self.write(
            \\        // EOF check
            \\        if (self.pos >= self.source.len) {
        );
        try self.write(
            \\            return Token{ .cat = .@"eof", .pre = wsCount, .pos = self.pos, .len = 0 };
            \\        }
            \\
            \\        const start = self.pos;
            \\        const c = self.source[self.pos];
            \\
        );

        try self.generateNewlineHandling();

        // Generate empty-pattern guard rules (zero-width tokens based on state)
        try self.generateEmptyPatternGuards();

        const hasBegState = for (self.spec.states.items) |s| {
            if (std.mem.eql(u8, s.name, "beg")) break true;
        } else false;
        if (hasBegState) {
            try self.write(
                \\        // From here, clear line-start flag
                \\        self.beg = 0;
                \\
            );
        }

        // Top-of-matchRules preemption for multi-char literal rules that
        // would otherwise be shadowed by string scanners, punct-ident
        // dispatches, etc. Handles `"'''"`, `"???"`, `` "```"[alpha]...``,
        // and similar maximal-munch cases. Falls through cleanly when no
        // literal matches at the current position.
        try self.generateMultiCharLiteralPreemption();

        try self.generateScannerDispatch();

        try self.generateCommentHandling();

        try self.generateOperatorSwitch();

        try self.generateScanners();
    }
};

// =============================================================================
// Parser DSL Data Structures
// =============================================================================

/// Terminal or nonterminal symbol
const ParseMode = enum { lalr, slr };

const ParserSymbol = struct {
    id: u16,
    name: []const u8,
    kind: Kind,

    // For nonterminals only
    nullable: bool = false,
    firsts: ParserSymbolSet = .empty,
    follows: ParserSymbolSet = .empty,
    rules: std.ArrayListUnmanaged(u16) = .empty, // Rule IDs that define this nonterminal

    const Kind = enum { terminal, nonterminal };

    fn init(id: u16, name: []const u8, kind: Kind) ParserSymbol {
        return .{ .id = id, .name = name, .kind = kind };
    }

    fn deinit(self: *ParserSymbol, allocator: Allocator) void {
        self.rules.deinit(allocator);
        self.firsts.deinit(allocator);
        self.follows.deinit(allocator);
    }
};

/// A set of symbol IDs (for FIRST/FOLLOW sets)
const ParserSymbolSet = struct {
    items: std.ArrayListUnmanaged(u16) = .empty,

    pub const empty: ParserSymbolSet = .{};

    fn deinit(self: *ParserSymbolSet, allocator: Allocator) void {
        self.items.deinit(allocator);
    }

    fn add(self: *ParserSymbolSet, allocator: Allocator, id: u16) !void {
        for (self.items.items) |existing| {
            if (existing == id) return;
        }
        try self.items.append(allocator, id);
    }

    fn contains(self: *const ParserSymbolSet, id: u16) bool {
        for (self.items.items) |existing| {
            if (existing == id) return true;
        }
        return false;
    }

    fn addAll(self: *ParserSymbolSet, allocator: Allocator, other: *const ParserSymbolSet) !bool {
        const oldCount = self.items.items.len;
        for (other.items.items) |id| {
            try self.add(allocator, id);
        }
        return self.items.items.len > oldCount;
    }

    fn count(self: *const ParserSymbolSet) usize {
        return self.items.items.len;
    }

    fn slice(self: *const ParserSymbolSet) []const u16 {
        return self.items.items;
    }
};

/// Production rule: lhs → rhs with optional action
const ParserRule = struct {
    id: u16,
    lhs: u16, // Nonterminal symbol ID
    rhs: []const u16, // Sequence of symbol IDs
    action: ?ParserAction, // Semantic action
    actionOffset: u8 = 0, // Position offset for start rules with marker tokens
    nullable: bool = false,
    firsts: ParserSymbolSet = .empty,
    excludeChar: u8 = 0, // X "c" - exclude rule when next char matches
    preferReduce: bool = false, // < hint - prefer reduce on S/R conflict
    preferShift: bool = false, // > hint - prefer shift on S/R conflict

    const ParserAction = struct {
        template: []const u8, // Original action string like (set 2? ...3)
        kind: Kind,

        const Kind = enum { sexp, passthrough, nil, spread };
    };
};

/// LR Item: rule with dot position (A → α • β)
const ParserItem = struct {
    ruleId: u16,
    dot: u8,

    fn id(self: ParserItem) u32 {
        return (@as(u32, self.ruleId) << 8) | self.dot;
    }

    fn eql(a: ParserItem, b: ParserItem) bool {
        return a.ruleId == b.ruleId and a.dot == b.dot;
    }
};

/// LR State: set of items with transitions
const ParserState = struct {
    id: u16,
    kernel: []const ParserItem, // Kernel items (from shifts/gotos)
    items: []const ParserItem, // All items (kernel + closure)
    transitions: []const ParserTransition,
    reductions: []const ParserItem, // Items with dot at end
};

/// Transition from one state to another on a symbol
const ParserTransition = struct {
    symbol: u16,
    target: u16,
};

/// @as directive for token-to-rule mapping (uses @lang module)
const AsDirective = struct {
    token: []const u8, // "ident"
    rule: []const u8, // "cmd" -> CmdId, cmdAs, cmdToSymbol
    permissive: bool = false, // "cmd!" -> reduce-aware matching (action != 0)
};

/// Capitalize first letter of a rule name for building compound identifiers.
/// Assumes input is [a-z][a-z0-9]* (grammar @as rule names).
fn capitalized(name: []const u8) [64]u8 {
    var buf: [64]u8 = .{0} ** 64;
    if (name.len > 0 and name.len <= 64) {
        @memcpy(buf[0..name.len], name);
        if (buf[0] >= 'a' and buf[0] <= 'z') buf[0] -= 32;
    }
    return buf;
}

/// @op directive for operator literal-to-token mappings
const OpMapping = struct {
    lit: []const u8, // "'=" (the literal in the grammar)
    tok: []const u8, // "noteq" (the lexer token type)
};

/// @lang directive specifies the language helper module
// @lang directive: specifies the language helper module (e.g., "zag" -> imports zag.zig)

/// @errors directive for human-readable rule names in diagnostics
const ErrorName = struct {
    rule: []const u8, // "expr"
    name: []const u8, // "expression"
};

/// @infix directive for automatic precedence-climbing expression grammar
const InfixOp = struct {
    op: []const u8, // "+" or "||"
    assoc: Assoc,
    prec: u32,

    const Assoc = enum { left, right, none };
};

/// @code directive for injecting code at specific locations
const CodeBlock = struct {
    location: []const u8, // "imports", "sexp", "parser", "bottom"
    code: []const u8, // raw Zig code to inject
};

// =============================================================================
// GrammarIR — Semantic IR for grammar files (consumed by processGrammar)
//
// The self-hosted frontend (src/parser.zig + GrammarLowerer) produces this
// IR from .grammar files. processGrammar() is the sole consumer.
// =============================================================================

const GrammarIR = struct {
    rules: []const ParsedRule,
    startSymbols: []const []const u8,
    asDirectives: []const AsDirective,
    opMappings: []const OpMapping,
    errorNames: []const ErrorName,
    infix: ?InfixDecl = null,
    lang: ?[]const u8 = null,
    codeBlocks: []const CodeBlock,
    expectConflicts: ?u32 = null,
};

const ParsedRule = struct {
    name: []const u8,
    isStart: bool,
    alternatives: []const ParsedAlternative,
};

const ParsedAlternative = struct {
    elements: []const ParsedElement,
    action: ?[]const u8 = null,
    excludeChar: u8 = 0,
    preferReduce: bool = false,
    preferShift: bool = false,
};

const ParsedElement = struct {
    kind: Kind,
    value: []const u8 = "",
    quantifier: Quantifier = .one,
    optionalItems: bool = false,
    listSeparator: ?[]const u8 = null,
    subElements: []const ParsedElement = &[_]ParsedElement{},
    skip: bool = false,

    const Kind = enum {
        ident,
        token,
        string,
        group,
        optGroup,
        reqList,
        optList,
    };

    const Quantifier = enum { one, optional, zeroPlus, onePlus };
};

const InfixDecl = struct {
    baseRule: []const u8,
    ops: []const InfixOp,
};

// =============================================================================
// Grammar Lowerer — schema-driven Sexp → GrammarIR conversion
//
// Consumes the canonical S-expression tree produced by the generated
// nexus.grammar frontend (see the schema block at the top of nexus.grammar)
// and builds the same GrammarIR that processGrammar expects.
//
// Every lowering entry point receives exactly the documented shape or raises
// error.ShapeError with a byte offset into the parser section. There are no
// silent fall-throughs, no permissive default cases, and no heuristic shape
// unwrapping. Tag dispatch is exhaustive by construction.
// =============================================================================

const GrammarLowerer = struct {
    allocator: Allocator,
    source: []const u8, // The @parser section body — positions in .src nodes are offsets into this slice.

    rules: std.ArrayListUnmanaged(ParsedRule) = .empty,
    startSymbols: std.ArrayListUnmanaged([]const u8) = .empty,
    asDirectives: std.ArrayListUnmanaged(AsDirective) = .empty,
    opMappings: std.ArrayListUnmanaged(OpMapping) = .empty,
    errorNames: std.ArrayListUnmanaged(ErrorName) = .empty,
    infixOps: std.ArrayListUnmanaged(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    codeBlocks: std.ArrayListUnmanaged(CodeBlock) = .empty,
    expectConflicts: ?u32 = null,

    const LoweringError = error{ ShapeError, OutOfMemory };

    fn lower(allocator: Allocator, sexp: ngp.Sexp, source: []const u8) LoweringError!GrammarIR {
        var self = GrammarLowerer{ .allocator = allocator, .source = source };
        try self.lowerRoot(sexp);
        return GrammarIR{
            .rules = try self.rules.toOwnedSlice(allocator),
            .startSymbols = try self.startSymbols.toOwnedSlice(allocator),
            .asDirectives = try self.asDirectives.toOwnedSlice(allocator),
            .opMappings = try self.opMappings.toOwnedSlice(allocator),
            .errorNames = try self.errorNames.toOwnedSlice(allocator),
            .infix = if (self.infixBase) |base| InfixDecl{
                .baseRule = base,
                .ops = try self.infixOps.toOwnedSlice(allocator),
            } else null,
            .lang = self.lang,
            .codeBlocks = try self.codeBlocks.toOwnedSlice(allocator),
            .expectConflicts = self.expectConflicts,
        };
    }

    // --- Shape helpers ---

    fn listItems(node: ngp.Sexp) ?[]const ngp.Sexp {
        return switch (node) {
            .list => |items| items,
            else => null,
        };
    }

    fn taggedItems(node: ngp.Sexp) ?struct { tag: ngp.Tag, items: []const ngp.Sexp } {
        const items = listItems(node) orelse return null;
        if (items.len == 0) return null;
        const tag = switch (items[0]) {
            .tag => |t| t,
            else => return null,
        };
        return .{ .tag = tag, .items = items };
    }

    fn srcText(self: *const GrammarLowerer, node: ngp.Sexp) []const u8 {
        return switch (node) {
            .src => |s| self.source[s.pos..][0..s.len],
            else => "",
        };
    }

    fn stripQuotes(s: []const u8) []const u8 {
        if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
        return s;
    }

    fn nodeOffset(node: ngp.Sexp) u32 {
        return switch (node) {
            .src => |s| s.pos,
            .list => |items| if (items.len > 0) nodeOffset(items[0]) else 0,
            else => 0,
        };
    }

    fn shapeError(self: *const GrammarLowerer, node: ngp.Sexp, expected: []const u8) LoweringError {
        // The negative-test suite fires this path by design; silencing the
        // diagnostic during `zig test` keeps the test runner's output clean
        // without losing real diagnostics in production runs.
        if (!@import("builtin").is_test) {
            const off = nodeOffset(node);
            var line: u32 = 1;
            var col: u32 = 1;
            var i: usize = 0;
            while (i < off and i < self.source.len) : (i += 1) {
                if (self.source[i] == '\n') {
                    line += 1;
                    col = 1;
                } else col += 1;
            }
            std.debug.print("❌ shape error at line {d}, col {d}: expected {s}\n", .{ line, col, expected });
        }
        return error.ShapeError;
    }

    fn requireTag(self: *const GrammarLowerer, node: ngp.Sexp, expected: ngp.Tag) LoweringError![]const ngp.Sexp {
        const t = taggedItems(node) orelse return self.shapeError(node, @tagName(expected));
        if (t.tag != expected) return self.shapeError(node, @tagName(expected));
        return t.items;
    }

    fn requireSrc(self: *const GrammarLowerer, node: ngp.Sexp, what: []const u8) LoweringError![]const u8 {
        return switch (node) {
            .src => |s| self.source[s.pos..][0..s.len],
            else => self.shapeError(node, what),
        };
    }

    fn requireList(self: *const GrammarLowerer, node: ngp.Sexp, what: []const u8) LoweringError![]const ngp.Sexp {
        return listItems(node) orelse self.shapeError(node, what);
    }

    // --- Root ---

    fn lowerRoot(self: *GrammarLowerer, sexp: ngp.Sexp) LoweringError!void {
        const items = try self.requireTag(sexp, .grammar);
        for (items[1..]) |entry| try self.lowerEntry(entry);
    }

    fn lowerEntry(self: *GrammarLowerer, entry: ngp.Sexp) LoweringError!void {
        const t = taggedItems(entry) orelse return self.shapeError(entry, "directive or rule");
        switch (t.tag) {
            .lang => try self.lowerLang(entry, t.items),
            .conflicts => try self.lowerConflicts(entry, t.items),
            .code => try self.lowerCode(entry, t.items),
            .as => try self.lowerAs(entry, t.items),
            .op => try self.lowerOp(entry, t.items),
            .errors => try self.lowerErrors(entry, t.items),
            .infix => try self.lowerInfix(entry, t.items),
            .rule => try self.lowerRule(entry, t.items),
            else => return self.shapeError(entry, "directive or rule"),
        }
    }

    // --- Directives ---

    fn lowerLang(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len != 2) return self.shapeError(node, "(lang STRING)");
        const raw = try self.requireSrc(items[1], "language-name string");
        self.lang = stripQuotes(raw);
    }

    fn lowerConflicts(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len != 2) return self.shapeError(node, "(conflicts INTEGER)");
        const text = try self.requireSrc(items[1], "conflict count");
        self.expectConflicts = std.fmt.parseInt(u32, text, 10) catch
            return self.shapeError(items[1], "integer");
    }

    fn lowerCode(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len != 3) return self.shapeError(node, "(code IDENT CODE_BLOCK)");
        const location = try self.requireSrc(items[1], "@code location ident");
        const body = try self.requireSrc(items[2], "@code body");
        try self.codeBlocks.append(self.allocator, .{
            .location = location,
            .code = std.mem.trim(u8, body, " \t\n\r"),
        });
    }

    fn lowerAs(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len < 3) return self.shapeError(node, "(as IDENT AS_ENTRY+)");
        const token = try self.requireSrc(items[1], "@as source-token ident");
        for (items[2..]) |entry| {
            const et = taggedItems(entry) orelse return self.shapeError(entry, "as_strict or as_perm");
            const rule = switch (et.tag) {
                .as_strict, .as_perm => blk: {
                    if (et.items.len != 2) return self.shapeError(entry, "(as_strict|as_perm IDENT)");
                    break :blk try self.requireSrc(et.items[1], "candidate ident");
                },
                else => return self.shapeError(entry, "as_strict or as_perm"),
            };
            try self.asDirectives.append(self.allocator, .{
                .token = token,
                .rule = rule,
                .permissive = (et.tag == .as_perm),
            });
        }
    }

    fn lowerOp(self: *GrammarLowerer, _: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .op_map);
            if (et.len != 3) return self.shapeError(entry, "(op_map STRING STRING)");
            const lit = stripQuotes(try self.requireSrc(et[1], "op literal"));
            const tok = stripQuotes(try self.requireSrc(et[2], "op target token"));
            try self.opMappings.append(self.allocator, .{ .lit = lit, .tok = tok });
        }
    }

    fn lowerErrors(self: *GrammarLowerer, _: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .error_name);
            if (et.len != 3) return self.shapeError(entry, "(error_name RULE STRING)");
            const rule = try self.requireSrc(et[1], "rule name");
            const name = stripQuotes(try self.requireSrc(et[2], "display string"));
            try self.errorNames.append(self.allocator, .{ .rule = rule, .name = name });
        }
    }

    fn lowerInfix(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len < 2) return self.shapeError(node, "(infix IDENT LEVEL+)");
        self.infixBase = try self.requireSrc(items[1], "@infix base expression");
        var prec: u32 = 1;
        for (items[2..]) |level| {
            const lt = try self.requireTag(level, .level);
            for (lt[1..]) |opNode| {
                const ot = try self.requireTag(opNode, .infix_op);
                if (ot.len != 3) return self.shapeError(opNode, "(infix_op STRING assoc)");
                const op = stripQuotes(try self.requireSrc(ot[1], "operator literal"));
                const assocName = try self.requireSrc(ot[2], "associativity keyword");
                const assoc: InfixOp.Assoc = if (std.mem.eql(u8, assocName, "left"))
                    .left
                else if (std.mem.eql(u8, assocName, "right"))
                    .right
                else if (std.mem.eql(u8, assocName, "none"))
                    .none
                else
                    return self.shapeError(ot[2], "left|right|none");
                try self.infixOps.append(self.allocator, .{ .op = op, .assoc = assoc, .prec = prec });
            }
            prec += 1;
        }
    }

    // --- Rules ---

    fn lowerRule(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!void {
        if (items.len < 3) return self.shapeError(node, "(rule RULE_NAME ALT+)");

        const nameInfo = try self.lowerRuleName(items[1]);
        if (nameInfo.isStart) try self.startSymbols.append(self.allocator, nameInfo.name);

        var alts: std.ArrayListUnmanaged(ParsedAlternative) = .empty;
        for (items[2..]) |altNode| try alts.append(self.allocator, try self.lowerAlt(altNode));

        try self.rules.append(self.allocator, .{
            .name = nameInfo.name,
            .isStart = nameInfo.isStart,
            .alternatives = try alts.toOwnedSlice(self.allocator),
        });
    }

    fn lowerRuleName(self: *GrammarLowerer, node: ngp.Sexp) LoweringError!struct { name: []const u8, isStart: bool } {
        const t = taggedItems(node) orelse return self.shapeError(node, "(start ...) or (name ...)");
        return switch (t.tag) {
            .start => .{
                .name = try self.extractSingleIdent(node, t.items, "(start IDENT-or-TOKEN)"),
                .isStart = true,
            },
            .name => .{
                .name = try self.extractSingleIdent(node, t.items, "(name IDENT-or-TOKEN)"),
                .isStart = false,
            },
            else => self.shapeError(node, "(start ...) or (name ...)"),
        };
    }

    fn extractSingleIdent(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp, expected: []const u8) LoweringError![]const u8 {
        if (items.len != 2) return self.shapeError(node, expected);
        return self.requireSrc(items[1], expected);
    }

    fn lowerAlt(self: *GrammarLowerer, altNode: ngp.Sexp) LoweringError!ParsedAlternative {
        const t = taggedItems(altNode) orelse return self.shapeError(altNode, "alt | alt_reduce | alt_shift");
        const preferReduce = (t.tag == .alt_reduce);
        const preferShift = (t.tag == .alt_shift);
        if (t.tag != .alt and !preferReduce and !preferShift) {
            return self.shapeError(altNode, "alt | alt_reduce | alt_shift");
        }
        if (t.items.len < 2 or t.items.len > 3) return self.shapeError(altNode, "(alt ELEMENT-list ACTION?)");

        // Children of the element list are either regular ELEMENT sexps or
        // (exclude STRING) hints. Exclude elements are consumed here: they
        // set the alternative's excludeChar (last-seen wins, matching
        // legacy semantics) and never reach the element list that
        // processGrammar sees.
        const rawChildren = try self.requireList(t.items[1], "element list");
        var elements: std.ArrayListUnmanaged(ParsedElement) = .empty;
        var excludeChar: u8 = 0;
        for (rawChildren) |child| {
            if (taggedItems(child)) |ct| if (ct.tag == .exclude) {
                if (ct.items.len != 2) return self.shapeError(child, "(exclude STRING)");
                const raw = try self.requireSrc(ct.items[1], "exclusion literal");
                const inner = stripQuotes(raw);
                if (inner.len != 1) return self.shapeError(child, "exclude \"c\" — c must be a one-char literal");
                excludeChar = inner[0];
                continue;
            };
            try elements.append(self.allocator, try self.lowerElement(child));
        }

        var action: ?[]const u8 = null;
        if (t.items.len == 3) action = try self.requireSrc(t.items[2], "action text");

        return ParsedAlternative{
            .elements = try elements.toOwnedSlice(self.allocator),
            .action = action,
            .excludeChar = excludeChar,
            .preferReduce = preferReduce,
            .preferShift = preferShift,
        };
    }

    // Lowers a list of element sexps. Used only for group bodies (inside
    // parenthesized groups and bracket groups) where (exclude ...) is not
    // legal — an exclude there will fall through lowerElement's switch and
    // emit a shape error, which is the correct behavior.
    fn lowerAltBody(self: *GrammarLowerer, node: ngp.Sexp) LoweringError!std.ArrayListUnmanaged(ParsedElement) {
        const items = try self.requireList(node, "element list");
        var out: std.ArrayListUnmanaged(ParsedElement) = .empty;
        for (items) |child| try out.append(self.allocator, try self.lowerElement(child));
        return out;
    }

    // --- Elements ---

    fn lowerElement(self: *GrammarLowerer, node: ngp.Sexp) LoweringError!ParsedElement {
        const t = taggedItems(node) orelse return self.shapeError(node, "tagged element sexp");
        return switch (t.tag) {
            .ref => try self.lowerScalarElement(node, t.items, .ident),
            .tok => try self.lowerScalarElement(node, t.items, .token),
            .lit => try self.lowerScalarElement(node, t.items, .string),
            .at_ref => try self.lowerScalarElement(node, t.items, .ident),
            .list_req => try self.lowerListElement(node, t.items, .reqList),
            .group => try self.lowerGroupElement(node, t.items, .group, false),
            .group_many => try self.lowerGroupElement(node, t.items, .optList, true),
            .group_opt => try self.lowerGroupElement(node, t.items, .optGroup, false),
            .quantified => try self.lowerQuantifiedElement(node, t.items),
            .skip => try self.lowerSkipElement(node, t.items, false),
            .skip_q => try self.lowerSkipElement(node, t.items, true),
            else => self.shapeError(node, "element"),
        };
    }

    fn lowerScalarElement(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp, kind: ParsedElement.Kind) LoweringError!ParsedElement {
        if (items.len != 2) return self.shapeError(node, "(ref|tok|lit|at_ref SRC)");
        return ParsedElement{
            .kind = kind,
            .value = try self.requireSrc(items[1], "identifier/token/string"),
        };
    }

    fn lowerListElement(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp, kind: ParsedElement.Kind) LoweringError!ParsedElement {
        if (items.len != 3) return self.shapeError(node, "(list_req TOKEN LIST_INNER)");
        const listTok = try self.requireSrc(items[1], "list head token");
        _ = listTok; // The leading TOKEN is always `L`; the surface syntax gives no other choice.
        const inner = taggedItems(items[2]) orelse return self.shapeError(items[2], "LIST_INNER");
        var elem = ParsedElement{ .kind = kind, .value = "" };
        switch (inner.tag) {
            .plain => {
                if (inner.items.len != 2) return self.shapeError(items[2], "(plain IDENT)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
            },
            .opt_items => {
                if (inner.items.len != 3) return self.shapeError(items[2], "(opt_items IDENT SEP)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.optionalItems = true;
                elem.listSeparator = try self.requireSrc(inner.items[2], "separator");
            },
            .sep_items => {
                if (inner.items.len != 3) return self.shapeError(items[2], "(sep_items IDENT SEP)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.listSeparator = try self.requireSrc(inner.items[2], "separator");
            },
            .opt_items_nosep => {
                if (inner.items.len != 2) return self.shapeError(items[2], "(opt_items_nosep IDENT)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.optionalItems = true;
            },
            else => return self.shapeError(items[2], "plain|opt_items|sep_items|opt_items_nosep"),
        }
        return elem;
    }

    fn lowerGroupElement(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp, kind: ParsedElement.Kind, asMany: bool) LoweringError!ParsedElement {
        if (items.len < 2) return self.shapeError(node, "group with ≥1 ALT_BODY");

        if (items.len == 2) {
            var bodyElements = try self.lowerAltBody(items[1]);
            defer bodyElements.deinit(self.allocator);

            if (asMany) {
                // [X, ...] with a single simple element collapses to an optList
                // carrying the item name directly; the parser generator emits a
                // comma-separated list rule for it.
                if (isSingleSimpleElem(bodyElements.items)) {
                    return ParsedElement{
                        .kind = .optList,
                        .value = bodyElements.items[0].value,
                    };
                }
                return ParsedElement{
                    .kind = .optList,
                    .value = if (bodyElements.items.len > 0) bodyElements.items[0].value else "",
                    .subElements = try self.allocator.dupe(ParsedElement, bodyElements.items),
                };
            }

            // [L(X)]: single alt body containing exactly one required-list
            // element collapses to an optional-list element carrying the same
            // list fields (item name, separator, per-item optionality).
            if (kind == .optGroup and bodyElements.items.len == 1 and bodyElements.items[0].kind == .reqList and bodyElements.items[0].quantifier == .one and !bodyElements.items[0].skip) {
                const inner = bodyElements.items[0];
                return ParsedElement{
                    .kind = .optList,
                    .value = inner.value,
                    .optionalItems = inner.optionalItems,
                    .listSeparator = inner.listSeparator,
                };
            }

            // [X] with a single simple element collapses to the base element with
            // an optional quantifier. Multiple elements or complex bodies keep
            // the optGroup shape, which is expanded into explicit alternatives
            // downstream by expandOptionalGroups.
            if (kind == .optGroup and isSingleSimpleElem(bodyElements.items)) {
                return ParsedElement{
                    .kind = bodyElements.items[0].kind,
                    .value = bodyElements.items[0].value,
                    .quantifier = .optional,
                };
            }

            // For optGroup, downstream expansion labels the generated
            // alternatives with the first sub-element's text; mirror the
            // hand-written frontend by carrying it in `value`. Plain groups
            // don't need it.
            const firstValue: []const u8 = if (kind == .optGroup and bodyElements.items.len > 0)
                bodyElements.items[0].value
            else
                "";

            return ParsedElement{
                .kind = kind,
                .value = firstValue,
                .subElements = try self.allocator.dupe(ParsedElement, bodyElements.items),
            };
        }

        // Multi-alt group. Each alternative contributes a sub-group element so
        // that downstream emitters see a list of distinct alternatives.
        var subElems: std.ArrayListUnmanaged(ParsedElement) = .empty;
        for (items[1..]) |altBody| {
            var body = try self.lowerAltBody(altBody);
            defer body.deinit(self.allocator);
            if (body.items.len == 0) continue;
            try subElems.append(self.allocator, .{
                .kind = .group,
                .subElements = try self.allocator.dupe(ParsedElement, body.items),
            });
        }

        return ParsedElement{
            .kind = if (asMany) .optList else kind,
            .subElements = try subElems.toOwnedSlice(self.allocator),
        };
    }

    fn isSingleSimpleElem(elements: []const ParsedElement) bool {
        if (elements.len != 1) return false;
        const e = elements[0];
        if (e.skip) return false;
        if (e.quantifier != .one) return false;
        return e.kind == .ident or e.kind == .token;
    }

    fn lowerQuantifiedElement(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp) LoweringError!ParsedElement {
        if (items.len != 3) return self.shapeError(node, "(quantified ELEMENT QUANT)");
        var inner = try self.lowerElement(items[1]);
        inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerSkipElement(self: *GrammarLowerer, node: ngp.Sexp, items: []const ngp.Sexp, withQuant: bool) LoweringError!ParsedElement {
        const expected = if (withQuant) "(skip_q ELEMENT QUANT)" else "(skip ELEMENT)";
        const need: usize = if (withQuant) 3 else 2;
        if (items.len != need) return self.shapeError(node, expected);
        var inner = try self.lowerElement(items[1]);
        inner.skip = true;
        if (withQuant) inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerQuantifier(self: *const GrammarLowerer, node: ngp.Sexp) LoweringError!ParsedElement.Quantifier {
        const t = taggedItems(node) orelse return self.shapeError(node, "(opt|zero_plus|one_plus)");
        if (t.items.len != 1) return self.shapeError(node, "(opt|zero_plus|one_plus)");
        return switch (t.tag) {
            .opt => .optional,
            .zero_plus => .zeroPlus,
            .one_plus => .onePlus,
            else => self.shapeError(node, "(opt|zero_plus|one_plus)"),
        };
    }
};

// =============================================================================
// LALR(1) Parser Generator
// =============================================================================

const ConflictDetail = struct {
    kind: enum { shiftReduce, reduceReduce },
    nameA: []const u8,
    nameB: []const u8,
};

const ParserGenerator = struct {
    allocator: Allocator,

    // Symbol management
    symbols: std.ArrayListUnmanaged(ParserSymbol) = .empty,
    symbolMap: std.StringHashMapUnmanaged(u16) = .empty,
    aliases: std.StringHashMapUnmanaged([]const u8) = .empty,
    nextSymbolId: u16 = 0,

    // Rules
    rules: std.ArrayListUnmanaged(ParserRule) = .empty,

    // LR automaton
    states: std.ArrayListUnmanaged(ParserState) = .empty,

    // Special symbol IDs
    acceptId: u16 = 0,
    endId: u16 = 0,
    errorId: u16 = 0,

    // Multiple start symbol support
    startSymbols: std.ArrayListUnmanaged(u16) = .empty,
    startStates: std.ArrayListUnmanaged(u16) = .empty,
    acceptRules: std.ArrayListUnmanaged(u16) = .empty,

    parseMode: ParseMode = .lalr,
    conflicts: u32 = 0,
    expectConflicts: ?u32 = null,
    conflictDetails: std.ArrayListUnmanaged(ConflictDetail) = .empty,
    emitComments: bool = false,

    // Directives
    asDirectives: std.ArrayListUnmanaged(AsDirective) = .empty,
    opMappings: std.ArrayListUnmanaged(OpMapping) = .empty,
    errorNames: std.ArrayListUnmanaged(ErrorName) = .empty,
    infixOps: std.ArrayListUnmanaged(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    lexerSpec: ?*const LexerSpec = null,
    codeBlocks: std.ArrayListUnmanaged(CodeBlock) = .empty,

    // LALR(1) per-item lookaheads (indexed by [state.id][reductionIndex])
    lalrLookaheads: []const []const ParserSymbolSet = &[_][]const ParserSymbolSet{},

    // Tags for enum generation
    collectedTags: std.StringHashMapUnmanaged(u16) = .empty,
    tagList: std.ArrayListUnmanaged([]const u8) = .empty,

    // X "c" exclusions
    xExcludes: std.ArrayListUnmanaged(struct { state: u16, char: u8, shift: u16 }) = .empty,

    fn init(allocator: Allocator) ParserGenerator {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ParserGenerator) void {
        for (self.symbols.items) |*sym| sym.deinit(self.allocator);
        self.symbols.deinit(self.allocator);
        self.symbolMap.deinit(self.allocator);
        self.aliases.deinit(self.allocator);

        for (self.rules.items) |*rule| {
            self.allocator.free(rule.rhs);
            rule.firsts.deinit(self.allocator);
        }
        self.rules.deinit(self.allocator);

        for (self.states.items) |*state| {
            self.allocator.free(state.kernel);
            self.allocator.free(state.items);
            self.allocator.free(state.transitions);
            self.allocator.free(state.reductions);
        }
        self.states.deinit(self.allocator);

        if (self.lalrLookaheads.len > 0) {
            for (self.lalrLookaheads) |stateRow| {
                for (stateRow) |*set| {
                    @constCast(set).deinit(self.allocator);
                }
                self.allocator.free(stateRow);
            }
            self.allocator.free(self.lalrLookaheads);
        }

        self.startSymbols.deinit(self.allocator);
        self.startStates.deinit(self.allocator);
        self.acceptRules.deinit(self.allocator);
        self.asDirectives.deinit(self.allocator);
        self.opMappings.deinit(self.allocator);
        self.errorNames.deinit(self.allocator);
        self.infixOps.deinit(self.allocator);
        self.codeBlocks.deinit(self.allocator);
        self.collectedTags.deinit(self.allocator);
        self.tagList.deinit(self.allocator);
        self.xExcludes.deinit(self.allocator);
    }

    fn addSymbol(self: *ParserGenerator, name: []const u8, kind: ParserSymbol.Kind) !u16 {
        if (self.symbolMap.get(name)) |id| return id;

        const id = self.nextSymbolId;
        self.nextSymbolId += 1;

        try self.symbols.append(self.allocator, ParserSymbol.init(id, name, kind));
        try self.symbolMap.put(self.allocator, name, id);

        return id;
    }

    fn getSymbol(self: *ParserGenerator, name: []const u8) ?u16 {
        var resolved = name;
        var count: usize = 0;
        while (self.aliases.get(resolved)) |target| {
            count += 1;
            if (count > 100 or std.mem.eql(u8, resolved, target)) return null;
            resolved = target;
        }
        return self.symbolMap.get(resolved);
    }

    fn isAcceptRuleId(self: *ParserGenerator, ruleId: u16) bool {
        for (self.acceptRules.items) |ar| {
            if (ruleId == ar) return true;
        }
        return false;
    }

    fn isAliasRule(rule: ParsedRule) ?[]const u8 {
        if (rule.alternatives.len != 1) return null;
        const alt = rule.alternatives[0];
        if (alt.elements.len != 1) return null;
        const elem = alt.elements[0];
        if (elem.kind != .token and elem.kind != .ident) return null;
        if (elem.quantifier != .one) return null;
        if (alt.action != null) return null;
        return elem.value;
    }

    /// Info about an optional group for expansion
    const OptGroupInfo = struct {
        index: usize, // Index in elements array
        startPos: usize, // Starting position number (1-based)
        elemCount: usize, // Number of elements in this optional
    };

    /// Expand an alternative with consecutive opt_groups into multiple explicit alternatives.
    /// This avoids LALR shift-reduce conflicts caused by epsilon productions.
    /// Example: A [B C] [D E] → action  becomes:
    ///   A B C D E → adjusted_action
    ///   A B C     → adjusted_action
    ///   A D E     → adjusted_action
    ///   A         → adjusted_action
    fn expandOptionalGroups(self: *ParserGenerator, alt: ParsedAlternative) ![]ParsedAlternative {
        // Find all bracket-optionals ([X] or [A B C]) - these need expansion for stable positions.
        // Note: X? quantifiers (like SPACES?) don't need expansion - they're typically not in actions.
        var optGroups: std.ArrayListUnmanaged(OptGroupInfo) = .empty;
        defer optGroups.deinit(self.allocator);

        var pos: usize = 1;
        for (alt.elements, 0..) |elem, idx| {
            if (elem.kind == .optGroup) {
                // Multi-element optional: [A B C]
                try optGroups.append(self.allocator, .{
                    .index = idx,
                    .startPos = pos,
                    .elemCount = elem.subElements.len,
                });
                pos += elem.subElements.len;
            } else if (elem.quantifier == .optional and (elem.kind == .ident or elem.kind == .optList)) {
                // Single-element bracket-optional: [X] parsed as X with .optional quantifier
                // Only include nonterminals (ident) and optional lists, not token quantifiers (SPACES?)
                try optGroups.append(self.allocator, .{
                    .index = idx,
                    .startPos = pos,
                    .elemCount = 1,
                });
                pos += 1;
            } else {
                pos += 1;
            }
        }

        // If no opt_groups, no expansion needed
        // Note: Even single opt_groups need expansion for positionally stable output
        if (optGroups.items.len == 0) {
            var result: std.ArrayListUnmanaged(ParsedAlternative) = .empty;
            try result.append(self.allocator, alt);
            return result.toOwnedSlice(self.allocator);
        }

        // Generate 2^n combinations
        const n = optGroups.items.len;
        const combinations: usize = @as(usize, 1) << @intCast(n);

        var expanded: std.ArrayListUnmanaged(ParsedAlternative) = .empty;

        var combo: usize = 0;
        while (combo < combinations) : (combo += 1) {
            // Build elements for this combination
            var newParsedElements: std.ArrayListUnmanaged(ParsedElement) = .empty;

            for (alt.elements, 0..) |elem, idx| {
                // Check if this element is an optional (opt_group or single-element)
                const optIdx: ?usize = for (optGroups.items, 0..) |og, oi| {
                    if (og.index == idx) break oi;
                } else null;

                if (optIdx) |oi| {
                    // Check if this optional is present in this combination
                    const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;
                    if (present) {
                        if (elem.kind == .optGroup) {
                            // Multi-element optional: add sub-elements directly
                            for (elem.subElements) |sub| {
                                try newParsedElements.append(self.allocator, sub);
                            }
                        } else {
                            // Single-element optional: add element without optional quantifier
                            var nonOpt = elem;
                            nonOpt.quantifier = .one;
                            try newParsedElements.append(self.allocator, nonOpt);
                        }
                    }
                    // If not present, skip this optional entirely
                } else {
                    try newParsedElements.append(self.allocator, elem);
                }
            }

            // Transform action with stable positions (use original elements for position mapping)
            const finalParsedElements = try newParsedElements.toOwnedSlice(self.allocator);
            var newAction: ?[]const u8 = alt.action;
            if (alt.action) |action| {
                newAction = try self.transformActionStable(action, alt.elements, optGroups.items, combo);
            }

            try expanded.append(self.allocator, .{
                .elements = finalParsedElements,
                .action = newAction,
                .excludeChar = alt.excludeChar,
                .preferReduce = alt.preferReduce,
            });
        }

        return expanded.toOwnedSlice(self.allocator);
    }

    // Position map: 255 means nil/absent, otherwise it's the actual RHS position
    const nilPos: u8 = 255;
    const maxPositions: usize = 64;

    /// Parsed position reference from action template
    const PosRef = struct {
        kind: enum { bare, keyed, spread },
        posNum: usize,
        endIdx: usize, // Index after this reference in the action string
    };

    /// Tracks position references for trailing-nil stripping
    const PosRefInfo = struct { start: usize, isNil: bool };

    /// Build logical-to-actual position map for stable positions.
    /// Maps logical positions (1-based) to actual RHS positions, or NIL_POS for absent optionals.
    fn buildPositionMap(
        altParsedElements: []const ParsedElement,
        optGroups: []const OptGroupInfo,
        combo: usize,
    ) [maxPositions]u8 {
        var posMap: [maxPositions]u8 = [_]u8{nilPos} ** maxPositions;
        var logicalPos: usize = 1;
        var actualPos: usize = 0;

        for (altParsedElements, 0..) |_, elemIdx| {
            // Find if this element is an opt_group
            const optIdx = for (optGroups, 0..) |og, oi| {
                if (og.index == elemIdx) break oi;
            } else null;

            if (optIdx) |oi| {
                const og = optGroups[oi];
                const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;

                for (0..og.elemCount) |_| {
                    if (logicalPos < maxPositions) {
                        posMap[logicalPos] = if (present) @intCast(actualPos) else nilPos;
                    }
                    logicalPos += 1;
                    if (present) actualPos += 1;
                }
            } else {
                if (logicalPos < maxPositions) {
                    posMap[logicalPos] = @intCast(actualPos);
                }
                logicalPos += 1;
                actualPos += 1;
            }
        }

        return posMap;
    }

    /// Parse a position reference at the given index in the action string.
    /// Returns null if no position reference found at this location.
    fn parsePositionRef(action: []const u8, start: usize) ?PosRef {
        if (start >= action.len) return null;

        // key:N (key prefix is for documentation, stripped from output)
        if (action[start] >= 'a' and action[start] <= 'z') {
            var keyEnd = start;
            while (keyEnd < action.len and action[keyEnd] != ':' and action[keyEnd] != ' ' and action[keyEnd] != ')') {
                keyEnd += 1;
            }
            if (keyEnd < action.len and action[keyEnd] == ':') {
                const numStart = keyEnd + 1;
                var numEnd = numStart;
                while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
                    numEnd += 1;
                }
                if (numEnd > numStart) {
                    const posNum = std.fmt.parseInt(usize, action[numStart..numEnd], 10) catch return null;
                    return .{ .kind = .keyed, .posNum = posNum, .endIdx = numEnd };
                }
            }
            return null;
        }

        // Bare number N
        if (action[start] >= '1' and action[start] <= '9') {
            var numEnd = start;
            while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
                numEnd += 1;
            }
            const posNum = std.fmt.parseInt(usize, action[start..numEnd], 10) catch return null;
            return .{ .kind = .bare, .posNum = posNum, .endIdx = numEnd };
        }

        // ...N (spread)
        if (start + 3 < action.len and action[start] == '.' and action[start + 1] == '.' and action[start + 2] == '.') {
            var numEnd = start + 3;
            while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
                numEnd += 1;
            }
            if (numEnd > start + 3) {
                const posNum = std.fmt.parseInt(usize, action[start + 3 .. numEnd], 10) catch return null;
                return .{ .kind = .spread, .posNum = posNum, .endIdx = numEnd };
            }
        }

        return null;
    }

    /// Strip trailing nil references from the result buffer.
    fn stripTrailingNils(result: *std.ArrayListUnmanaged(u8), posRefs: []const PosRefInfo) void {
        // Find last non-nil position reference
        var lastNonNil: ?usize = null;
        for (posRefs, 0..) |pr, idx| {
            if (!pr.isNil) lastNonNil = idx;
        }

        const truncateStart = if (lastNonNil) |lnn|
            if (lnn + 1 < posRefs.len) posRefs[lnn + 1].start else return
        else if (posRefs.len > 0)
            posRefs[0].start
        else
            return;

        // Also remove preceding spaces
        var actualStart = truncateStart;
        while (actualStart > 0 and result.items[actualStart - 1] == ' ') {
            actualStart -= 1;
        }
        result.items.len = actualStart;
    }

    /// Transform action template for stable positions.
    /// Keeps logical positions stable, maps to actual RHS positions, inserts nil for absent optionals.
    /// Strips trailing nils from the output.
    fn transformActionStable(
        self: *ParserGenerator,
        action: []const u8,
        altParsedElements: []const ParsedElement,
        optGroups: []const OptGroupInfo,
        combo: usize,
    ) ![]const u8 {
        const posMap = buildPositionMap(altParsedElements, optGroups, combo);

        var result: std.ArrayListUnmanaged(u8) = .empty;
        var posRefs: std.ArrayListUnmanaged(PosRefInfo) = .empty;
        defer posRefs.deinit(self.allocator);

        var i: usize = 0;
        while (i < action.len) {
            if (parsePositionRef(action, i)) |ref| {
                const mapped = if (ref.posNum < maxPositions) posMap[ref.posNum] else nilPos;
                const isNil = (mapped == nilPos);

                try posRefs.append(self.allocator, .{ .start = result.items.len, .isNil = isNil });

                if (isNil) {
                    try result.appendSlice(self.allocator, "nil");
                } else {
                    // Output prefix (...) then mapped position
                    if (ref.kind == .spread) {
                        try result.appendSlice(self.allocator, "...");
                    }
                    var buf: [16]u8 = undefined;
                    const posStr = std.fmt.bufPrint(&buf, "{d}", .{mapped + 1}) catch unreachable;
                    try result.appendSlice(self.allocator, posStr);
                }
                i = ref.endIdx;
            } else {
                try result.append(self.allocator, action[i]);
                i += 1;
            }
        }

        stripTrailingNils(&result, posRefs.items);
        return result.toOwnedSlice(self.allocator);
    }

    /// Process parsed grammar into internal representation
    fn processGrammar(self: *ParserGenerator, ir: *const GrammarIR) !void {
        // Add special symbols
        self.acceptId = try self.addSymbol("$accept", .nonterminal);
        self.endId = try self.addSymbol("$end", .terminal);
        self.errorId = try self.addSymbol("error", .terminal);

        // Pre-pass: detect aliases
        for (ir.rules) |rule| {
            if (isAliasRule(rule)) |target| {
                try self.aliases.put(self.allocator, rule.name, target);
            }
        }

        // First pass: add all nonterminal names (skip aliases)
        for (ir.rules) |rule| {
            if (self.aliases.contains(rule.name)) continue;
            _ = try self.addSymbol(rule.name, .nonterminal);
        }

        // Second pass: process rules and add terminals
        // Expands consecutive optional groups to avoid LALR conflicts
        for (ir.rules) |rule| {
            if (self.aliases.contains(rule.name)) continue;

            const lhsId = self.getSymbol(rule.name).?;

            for (rule.alternatives) |alt| {
                // Expand consecutive opt_groups into explicit alternatives
                const expandedAlts = try self.expandOptionalGroups(alt);

                for (expandedAlts) |expandedAlt| {
                    var rhs: std.ArrayListUnmanaged(u16) = .empty;

                    for (expandedAlt.elements) |elem| {
                        const symId = try self.processElement(elem);
                        try rhs.append(self.allocator, symId);
                    }

                    const ruleId: u16 = @intCast(self.rules.items.len);
                    try self.rules.append(self.allocator, .{
                        .id = ruleId,
                        .lhs = lhsId,
                        .rhs = try rhs.toOwnedSlice(self.allocator),
                        .action = if (expandedAlt.action) |a| .{ .template = a, .kind = .sexp } else null,
                        .excludeChar = expandedAlt.excludeChar,
                        .preferReduce = expandedAlt.preferReduce,
                        .preferShift = expandedAlt.preferShift,
                    });
                    try self.symbols.items[lhsId].rules.append(self.allocator, ruleId);
                }
            }
        }

        // Use EOF as $end if defined
        if (self.symbolMap.get("EOF")) |eofId| {
            self.endId = eofId;
        }

        // Create augmented rules for EACH start symbol
        if (ir.startSymbols.len > 0) {
            for (ir.startSymbols) |startName| {
                if (self.getSymbol(startName)) |startId| {
                    // Create marker terminal "X!"
                    const markerName = try std.fmt.allocPrint(self.allocator, "{s}!", .{startName});
                    const markerId = try self.addSymbol(markerName, .terminal);

                    // Prepend marker to start rule
                    for (self.rules.items) |*rule| {
                        if (rule.lhs == startId) {
                            var newRhs: std.ArrayListUnmanaged(u16) = .empty;
                            try newRhs.append(self.allocator, markerId);
                            for (rule.rhs) |sym| {
                                try newRhs.append(self.allocator, sym);
                            }
                            rule.rhs = try newRhs.toOwnedSlice(self.allocator);
                            rule.actionOffset = 1;
                            break;
                        }
                    }

                    // Create unique accept symbol
                    const acceptName = try std.fmt.allocPrint(self.allocator, "$accept_{s}", .{startName});
                    const uniqueAcceptId = try self.addSymbol(acceptName, .nonterminal);

                    // Create augmented rule: $accept_X → startSymbol EOF
                    var acceptRhs: std.ArrayListUnmanaged(u16) = .empty;
                    try acceptRhs.append(self.allocator, startId);
                    try acceptRhs.append(self.allocator, self.endId);

                    const acceptRuleId: u16 = @intCast(self.rules.items.len);
                    try self.rules.append(self.allocator, .{
                        .id = acceptRuleId,
                        .lhs = uniqueAcceptId,
                        .rhs = try acceptRhs.toOwnedSlice(self.allocator),
                        .action = null,
                    });
                    try self.symbols.items[uniqueAcceptId].rules.append(self.allocator, acceptRuleId);

                    try self.startSymbols.append(self.allocator, startId);
                    try self.acceptRules.append(self.allocator, acceptRuleId);
                }
            }
        } else if (self.rules.items.len > 0) {
            // Fallback: use first rule as start symbol
            const startSymbol = self.rules.items[0].lhs;

            var acceptRhs: std.ArrayListUnmanaged(u16) = .empty;
            try acceptRhs.append(self.allocator, startSymbol);
            try acceptRhs.append(self.allocator, self.endId);

            const acceptRuleId: u16 = @intCast(self.rules.items.len);
            try self.rules.append(self.allocator, .{
                .id = acceptRuleId,
                .lhs = self.acceptId,
                .rhs = try acceptRhs.toOwnedSlice(self.allocator),
                .action = null,
            });
            try self.symbols.items[self.acceptId].rules.append(self.allocator, acceptRuleId);

            try self.startSymbols.append(self.allocator, startSymbol);
            try self.acceptRules.append(self.allocator, acceptRuleId);
        }

        // Copy directives from IR
        for (ir.asDirectives) |d| try self.asDirectives.append(self.allocator, d);
        for (ir.opMappings) |m| try self.opMappings.append(self.allocator, m);
        for (ir.errorNames) |e| try self.errorNames.append(self.allocator, e);
        if (ir.infix) |infix| {
            for (infix.ops) |op| try self.infixOps.append(self.allocator, op);
            self.infixBase = infix.baseRule;
        }
        self.lang = ir.lang;
        self.expectConflicts = ir.expectConflicts;

        // Generate infix expression chain if @infix was declared
        if (self.infixOps.items.len > 0 and self.infixBase != null) {
            try self.generateInfixChain();
        }
        for (ir.codeBlocks) |b| try self.codeBlocks.append(self.allocator, b);
    }

    /// Validate that all referenced symbols are defined.
    /// Returns error count (0 = all valid).
    pub fn validateSymbols(self: *ParserGenerator, lexerSpec: *const LexerSpec) u32 {
        var errors: u32 = 0;

        for (self.symbols.items) |sym| {
            // Skip special/generated symbols
            if (sym.name.len == 0) continue;
            if (sym.name[0] == '$' or sym.name[0] == '_' or sym.name[0] == '"') continue;

            // Check nonterminals have at least one rule
            if (sym.kind == .nonterminal) {
                if (sym.rules.items.len == 0) {
                    std.debug.print("  ❌ Undefined rule: '{s}'\n", .{sym.name});
                    errors += 1;
                }
            }
            // Check uppercase identifiers exist in lexer tokens (case-insensitive)
            else if (sym.kind == .terminal and sym.name[0] >= 'A' and sym.name[0] <= 'Z') {
                // Skip if it's a start symbol marker (ends with !)
                if (sym.name[sym.name.len - 1] == '!') continue;

                // Skip if there's a matching lowercase nonterminal (@as keyword)
                // e.g., SET terminal has a matching 'set' nonterminal rule
                var isAsKeyword = false;
                for (self.symbols.items) |other| {
                    if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                        isAsKeyword = true;
                        break;
                    }
                }
                if (isAsKeyword) continue;

                // Skip if it matches an @as directive rule name (e.g., SYSVAR from @as=[ident,sysvar])
                for (self.asDirectives.items) |directive| {
                    if (std.ascii.eqlIgnoreCase(directive.rule, sym.name)) {
                        isAsKeyword = true;
                        break;
                    }
                }
                if (isAsKeyword) continue;

                // When @lang is set, keyword terminals are resolved by the
                // lang module's keyword matcher at compile time. Trust the
                // Zig compiler to catch mismatches.
                if (self.lang != null and self.asDirectives.items.len > 0) continue;

                var found = false;

                // Check tokens block (case-insensitive since lexer uses lowercase)
                for (lexerSpec.tokens.items) |tok| {
                    if (std.ascii.eqlIgnoreCase(tok.name, sym.name)) {
                        found = true;
                        break;
                    }
                }

                // Check lexer rules (case-insensitive)
                if (!found) {
                    for (lexerSpec.rules.items) |rule| {
                        if (std.ascii.eqlIgnoreCase(rule.token, sym.name)) {
                            found = true;
                            break;
                        }
                    }
                }

                if (!found) {
                    std.debug.print("  ❌ Undefined token: '{s}'\n", .{sym.name});
                    errors += 1;
                }
            }
        }

        return errors;
    }

    fn processElement(self: *ParserGenerator, elem: ParsedElement) error{OutOfMemory}!u16 {
        const baseId = try self.processBaseElement(elem);

        return switch (elem.quantifier) {
            .one => baseId,
            .optional => try self.createOptionalRule(baseId),
            .zeroPlus => try self.createZeroPlusRule(baseId),
            .onePlus => try self.createOnePlusRule(baseId),
        };
    }

    fn processBaseElement(self: *ParserGenerator, elem: ParsedElement) error{OutOfMemory}!u16 {
        return switch (elem.kind) {
            .ident => blk: {
                if (self.getSymbol(elem.value)) |symId| break :blk symId;
                var resolved = elem.value;
                while (self.aliases.get(resolved)) |target| resolved = target;
                const kind: ParserSymbol.Kind = if (resolved.len > 0 and resolved[0] >= 'A' and resolved[0] <= 'Z')
                    .terminal
                else
                    .nonterminal;
                break :blk try self.addSymbol(resolved, kind);
            },
            .token => blk: {
                if (self.getSymbol(elem.value)) |symId| break :blk symId;
                var resolved = elem.value;
                while (self.aliases.get(resolved)) |target| resolved = target;
                break :blk try self.addSymbol(resolved, .terminal);
            },
            .string => try self.addSymbol(elem.value, .terminal),
            .group => blk: {
                if (elem.subElements.len == 0) break :blk self.errorId;

                const grpName = try std.fmt.allocPrint(self.allocator, "_grp_{d}", .{self.rules.items.len});
                const grpId = try self.addSymbol(grpName, .nonterminal);

                var rhs: std.ArrayListUnmanaged(u16) = .empty;
                for (elem.subElements) |sub| {
                    try rhs.append(self.allocator, try self.processElement(sub));
                }

                // Build action that excludes skipped elements
                // If element has skip=true, don't include its position in the action
                var actionTemplate: ?[]const u8 = null;
                var nonSkipped: std.ArrayListUnmanaged(u8) = .empty;
                defer nonSkipped.deinit(self.allocator);

                for (elem.subElements, 0..) |sub, i| {
                    if (!sub.skip) {
                        try nonSkipped.append(self.allocator, @intCast(i + 1)); // 1-based positions
                    }
                }

                // Generate action based on non-skipped count
                if (nonSkipped.items.len == 0) {
                    actionTemplate = "nil";
                } else if (nonSkipped.items.len == 1) {
                    // Single non-skipped: just return that position
                    actionTemplate = try std.fmt.allocPrint(self.allocator, "{d}", .{nonSkipped.items[0]});
                } else if (nonSkipped.items.len < elem.subElements.len) {
                    // Multiple non-skipped but some skipped: build explicit list
                    var buf: std.ArrayListUnmanaged(u8) = .empty;
                    defer buf.deinit(self.allocator);
                    try buf.append(self.allocator, '(');
                    for (nonSkipped.items, 0..) |pos, j| {
                        if (j > 0) try buf.append(self.allocator, ' ');
                        try buf.append(self.allocator, '0' + pos);
                    }
                    try buf.append(self.allocator, ')');
                    actionTemplate = try self.allocator.dupe(u8, buf.items);
                }
                // else: all elements included, action stays null (default list behavior)

                const ruleId: u16 = @intCast(self.rules.items.len);
                try self.rules.append(self.allocator, .{
                    .id = ruleId,
                    .lhs = grpId,
                    .rhs = try rhs.toOwnedSlice(self.allocator),
                    .action = if (actionTemplate) |t| .{ .template = t, .kind = .sexp } else null,
                });
                try self.symbols.items[grpId].rules.append(self.allocator, ruleId);

                break :blk grpId;
            },
            .optGroup => self.errorId, // Should be expanded
            .reqList => blk: {
                const itemName = elem.value;
                break :blk try self.createRequiredList(itemName, elem.optionalItems, elem.listSeparator);
            },
            .optList => blk: {
                const itemName = elem.value;
                const reqList = try self.createRequiredList(itemName, elem.optionalItems, elem.listSeparator);
                break :blk try self.createOptionalRule(reqList);
            },
        };
    }

    fn createRequiredList(self: *ParserGenerator, itemName: []const u8, optionalItems: bool, customSep: ?[]const u8) !u16 {
        const itemId = self.getSymbol(itemName) orelse blk: {
            const kind: ParserSymbol.Kind = if (itemName.len > 0 and itemName[0] >= 'A' and itemName[0] <= 'Z')
                .terminal
            else
                .nonterminal;
            break :blk try self.addSymbol(itemName, kind);
        };

        const effectiveItemId = if (optionalItems)
            try self.createOptionalRule(itemId)
        else
            itemId;

        const sepStr = customSep orelse "\",\"";
        const sepId = try self.addSymbol(sepStr, .terminal);

        const suffix: []const u8 = if (optionalItems) "opt" else "";
        const sepSuffix: []const u8 = if (customSep != null) "s" else "";
        const listName = try std.fmt.allocPrint(self.allocator, "_list_{d}{s}{s}", .{ itemId, suffix, sepSuffix });
        const tailName = try std.fmt.allocPrint(self.allocator, "_tail_{d}{s}{s}", .{ itemId, suffix, sepSuffix });

        if (self.getSymbol(listName)) |existing| return existing;

        const listId = try self.addSymbol(listName, .nonterminal);
        const tailId = try self.addSymbol(tailName, .nonterminal);

        // Rule: _list → item _tail → (!1 ...2)
        const listRuleId: u16 = @intCast(self.rules.items.len);
        var listRhs: std.ArrayListUnmanaged(u16) = .empty;
        try listRhs.append(self.allocator, effectiveItemId);
        try listRhs.append(self.allocator, tailId);
        try self.rules.append(self.allocator, .{
            .id = listRuleId,
            .lhs = listId,
            .rhs = try listRhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[listId].rules.append(self.allocator, listRuleId);

        // Rule: _tail → sep item _tail → (!2 ...3)
        const tailRule1Id: u16 = @intCast(self.rules.items.len);
        var tailRhs1: std.ArrayListUnmanaged(u16) = .empty;
        try tailRhs1.append(self.allocator, sepId);
        try tailRhs1.append(self.allocator, effectiveItemId);
        try tailRhs1.append(self.allocator, tailId);
        try self.rules.append(self.allocator, .{
            .id = tailRule1Id,
            .lhs = tailId,
            .rhs = try tailRhs1.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!2 ...3)", .kind = .sexp },
        });
        try self.symbols.items[tailId].rules.append(self.allocator, tailRule1Id);

        // Rule: _tail → ε → ()
        const tailRule2Id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = tailRule2Id,
            .lhs = tailId,
            .rhs = &[_]u16{},
            .action = .{ .template = "()", .kind = .sexp },
            .nullable = true,
            .preferShift = true,
        });
        try self.symbols.items[tailId].rules.append(self.allocator, tailRule2Id);
        self.symbols.items[tailId].nullable = true;

        return listId;
    }

    fn generateInfixChain(self: *ParserGenerator) !void {
        const baseName = self.infixBase orelse return;
        const baseId = self.getSymbol(baseName) orelse blk: {
            break :blk try self.addSymbol(baseName, .nonterminal);
        };

        // Collect unique precedence levels and sort them
        var levelsSeen: [64]u32 = undefined;
        var levelCount: usize = 0;

        for (self.infixOps.items) |op| {
            var found = false;
            for (levelsSeen[0..levelCount]) |l| {
                if (l == op.prec) {
                    found = true;
                    break;
                }
            }
            if (!found and levelCount < 64) {
                levelsSeen[levelCount] = op.prec;
                levelCount += 1;
            }
        }

        // Sort levels ascending (level 1 = loosest binding)
        for (0..levelCount) |i| {
            for (i + 1..levelCount) |j| {
                if (levelsSeen[j] < levelsSeen[i]) {
                    const tmp = levelsSeen[i];
                    levelsSeen[i] = levelsSeen[j];
                    levelsSeen[j] = tmp;
                }
            }
        }

        // Create a nonterminal for each level
        var levelIds: [64]u16 = undefined;
        for (0..levelCount) |i| {
            const name = try std.fmt.allocPrint(self.allocator, "_infix_{d}", .{levelsSeen[i]});
            levelIds[i] = try self.addSymbol(name, .nonterminal);
        }

        // For each level, generate rules
        for (0..levelCount) |i| {
            const level = levelsSeen[i];
            const thisId = levelIds[i];
            const nextId = if (i + 1 < levelCount) levelIds[i + 1] else baseId;

            // Find all operators at this level
            for (self.infixOps.items) |op| {
                if (op.prec != level) continue;

                const opStr = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{op.op});
                const opId = try self.addSymbol(opStr, .terminal);

                const actionStr = try std.fmt.allocPrint(self.allocator, "({s} 1 3)", .{op.op});

                var rhs: std.ArrayListUnmanaged(u16) = .empty;
                switch (op.assoc) {
                    .left => {
                        try rhs.append(self.allocator, thisId);
                        try rhs.append(self.allocator, opId);
                        try rhs.append(self.allocator, nextId);
                    },
                    .right => {
                        try rhs.append(self.allocator, nextId);
                        try rhs.append(self.allocator, opId);
                        try rhs.append(self.allocator, thisId);
                    },
                    .none => {
                        try rhs.append(self.allocator, nextId);
                        try rhs.append(self.allocator, opId);
                        try rhs.append(self.allocator, nextId);
                    },
                }

                const ruleId: u16 = @intCast(self.rules.items.len);
                try self.rules.append(self.allocator, .{
                    .id = ruleId,
                    .lhs = thisId,
                    .rhs = try rhs.toOwnedSlice(self.allocator),
                    .action = .{ .template = actionStr, .kind = .sexp },
                });
                try self.symbols.items[thisId].rules.append(self.allocator, ruleId);
            }

            // Passthrough rule: this_level → next_level
            const passthroughId: u16 = @intCast(self.rules.items.len);
            var passRhs: std.ArrayListUnmanaged(u16) = .empty;
            try passRhs.append(self.allocator, nextId);
            try self.rules.append(self.allocator, .{
                .id = passthroughId,
                .lhs = thisId,
                .rhs = try passRhs.toOwnedSlice(self.allocator),
                .action = .{ .template = "1", .kind = .passthrough },
            });
            try self.symbols.items[thisId].rules.append(self.allocator, passthroughId);
        }

        // Create the `infix` entry point that aliases to the lowest-precedence level
        const infixId = try self.addSymbol("infix", .nonterminal);
        const infixRuleId: u16 = @intCast(self.rules.items.len);
        var infixRhs: std.ArrayListUnmanaged(u16) = .empty;
        try infixRhs.append(self.allocator, levelIds[0]);
        try self.rules.append(self.allocator, .{
            .id = infixRuleId,
            .lhs = infixId,
            .rhs = try infixRhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "1", .kind = .passthrough },
        });
        try self.symbols.items[infixId].rules.append(self.allocator, infixRuleId);
    }

    fn createOptionalRule(self: *ParserGenerator, symId: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_opt_{d}", .{symId});
        if (self.getSymbol(name)) |existing| return existing;

        const optId = try self.addSymbol(name, .nonterminal);

        // Rule 1: opt → sym
        const rule1Id: u16 = @intCast(self.rules.items.len);
        var rhs1: std.ArrayListUnmanaged(u16) = .empty;
        try rhs1.append(self.allocator, symId);
        try self.rules.append(self.allocator, .{
            .id = rule1Id,
            .lhs = optId,
            .rhs = try rhs1.toOwnedSlice(self.allocator),
            .action = null,
        });
        try self.symbols.items[optId].rules.append(self.allocator, rule1Id);

        // Rule 2: opt → ε
        const rule2Id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = rule2Id,
            .lhs = optId,
            .rhs = &[_]u16{},
            .action = null,
            .nullable = true,
        });
        try self.symbols.items[optId].rules.append(self.allocator, rule2Id);
        self.symbols.items[optId].nullable = true;

        return optId;
    }

    fn createZeroPlusRule(self: *ParserGenerator, symId: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_star_{d}", .{symId});
        if (self.getSymbol(name)) |existing| return existing;

        const starId = try self.addSymbol(name, .nonterminal);

        // Rule 1: star → sym star → (!1 ...2)
        const rule1Id: u16 = @intCast(self.rules.items.len);
        var rhs1: std.ArrayListUnmanaged(u16) = .empty;
        try rhs1.append(self.allocator, symId);
        try rhs1.append(self.allocator, starId);
        try self.rules.append(self.allocator, .{
            .id = rule1Id,
            .lhs = starId,
            .rhs = try rhs1.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[starId].rules.append(self.allocator, rule1Id);

        // Rule 2: star → ε → ()
        const rule2Id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = rule2Id,
            .lhs = starId,
            .rhs = &[_]u16{},
            .action = .{ .template = "()", .kind = .sexp },
            .nullable = true,
        });
        try self.symbols.items[starId].rules.append(self.allocator, rule2Id);
        self.symbols.items[starId].nullable = true;

        return starId;
    }

    fn createOnePlusRule(self: *ParserGenerator, symId: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_plus_{d}", .{symId});
        if (self.getSymbol(name)) |existing| return existing;

        const starId = try self.createZeroPlusRule(symId);
        const plusId = try self.addSymbol(name, .nonterminal);

        // Rule: plus → sym star → (!1 ...2)
        const ruleId: u16 = @intCast(self.rules.items.len);
        var rhs: std.ArrayListUnmanaged(u16) = .empty;
        try rhs.append(self.allocator, symId);
        try rhs.append(self.allocator, starId);
        try self.rules.append(self.allocator, .{
            .id = ruleId,
            .lhs = plusId,
            .rhs = try rhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[plusId].rules.append(self.allocator, ruleId);

        return plusId;
    }

    // =========================================================================
    // LR Automaton Construction
    // =========================================================================
    //
    // LR parsing uses a deterministic finite automaton (DFA) where:
    //   - States are sets of "items" (rules with a dot showing parse progress)
    //   - Transitions occur on terminals (shift) or nonterminals (goto)
    //   - The automaton recognizes viable prefixes of the grammar
    //
    // An LR item looks like: A → α • β
    //   - The dot (•) shows how much of the rule we've seen
    //   - α is what we've matched, β is what we expect
    //   - When dot is at end (A → α •), we can reduce
    //
    // Construction algorithm:
    //   1. Start with item S' → • S $ (augmented start rule)
    //   2. Compute closure of initial items
    //   3. For each symbol X, compute GOTO(state, X) = closure of shifted items
    //   4. Repeat until no new states are created
    //
    // =========================================================================

    /// Build the LR(0) automaton from the processed grammar.
    /// Creates states and transitions for the shift-reduce parser.
    fn buildAutomaton(self: *ParserGenerator) !void {
        if (self.acceptRules.items.len == 0) return error.NoAcceptRule;

        var stateMap = std.StringHashMapUnmanaged(u16){};
        defer stateMap.deinit(self.allocator);

        // Create initial state for EACH accept rule
        for (self.acceptRules.items) |acceptRuleId| {
            var initialItems: std.ArrayListUnmanaged(ParserItem) = .empty;
            try initialItems.append(self.allocator, .{ .ruleId = acceptRuleId, .dot = 0 });

            const kernel = try initialItems.toOwnedSlice(self.allocator);
            const sig = try self.kernelSignature(kernel);

            if (stateMap.get(sig)) |existingId| {
                try self.startStates.append(self.allocator, existingId);
            } else {
                const initialState = try self.closure(kernel);
                const stateId: u16 = @intCast(self.states.items.len);
                try self.states.append(self.allocator, initialState);
                try stateMap.put(self.allocator, sig, stateId);
                try self.startStates.append(self.allocator, stateId);
            }
        }

        // Process states until no new ones
        var i: usize = 0;
        while (i < self.states.items.len) : (i += 1) {
            try self.processTransitions(i, &stateMap);
        }
    }

    /// Compute the closure of a set of LR items.
    ///
    /// Closure adds items for nonterminals that appear after the dot.
    /// If we have A → α • B β, we add B → • γ for all productions of B.
    ///
    /// Intuition: If we're waiting to see B, we need to recognize what B
    /// looks like, so we add all ways B can start.
    ///
    /// Example:
    ///   Kernel: { E → • T }
    ///   If T → F | T * F, closure adds: { T → • F, T → • T * F }
    ///   If F → id, closure adds: { F → • id }
    ///   Result: { E → • T, T → • F, T → • T * F, F → • id }
    fn closure(self: *ParserGenerator, kernel: []const ParserItem) !ParserState {
        var allItems: std.ArrayListUnmanaged(ParserItem) = .empty;
        var reductions: std.ArrayListUnmanaged(ParserItem) = .empty;
        var seen = std.AutoHashMap(u32, void).init(self.allocator);
        defer seen.deinit();

        // Start with kernel items
        for (kernel) |item| {
            try allItems.append(self.allocator, item);
            try seen.put(item.id(), {});
        }

        // Process items, adding closure items as we go
        var workIdx: usize = 0;
        while (workIdx < allItems.items.len) : (workIdx += 1) {
            const item = allItems.items[workIdx];
            const rule = self.rules.items[item.ruleId];

            // Item with dot at end → reduction item
            if (item.dot >= rule.rhs.len) {
                try reductions.append(self.allocator, item);
                continue;
            }

            // If next symbol after dot is nonterminal, add its productions
            const nextSym = rule.rhs[item.dot];
            const symbol = self.symbols.items[nextSym];

            if (symbol.kind == .nonterminal) {
                for (symbol.rules.items) |ruleId| {
                    const newItem = ParserItem{ .ruleId = ruleId, .dot = 0 };
                    if (!seen.contains(newItem.id())) {
                        try seen.put(newItem.id(), {});
                        try allItems.append(self.allocator, newItem);
                    }
                }
            }
        }

        return ParserState{
            .id = @intCast(self.states.items.len),
            .kernel = kernel,
            .items = try allItems.toOwnedSlice(self.allocator),
            .transitions = &[_]ParserTransition{},
            .reductions = try reductions.toOwnedSlice(self.allocator),
        };
    }

    /// Compute GOTO transitions for a state.
    ///
    /// GOTO(I, X) = closure({ A → α X • β | A → α • X β ∈ I })
    ///
    /// For each symbol X that appears after a dot in state I:
    ///   1. Collect all items with X after the dot
    ///   2. Advance the dot past X in each item (shift the dot)
    ///   3. Compute closure of the resulting items
    ///   4. This closure is the target state for transition on X
    ///
    /// If the target state already exists (same kernel), reuse it.
    fn processTransitions(self: *ParserGenerator, stateIdx: usize, stateMap: *std.StringHashMapUnmanaged(u16)) !void {
        const state = &self.states.items[stateIdx];
        var transitions: std.ArrayListUnmanaged(ParserTransition) = .empty;

        // Group items by the symbol after the dot
        var symbolItems = std.AutoHashMap(u16, std.ArrayListUnmanaged(ParserItem)).init(self.allocator);
        defer {
            var iter = symbolItems.valueIterator();
            while (iter.next()) |list| list.deinit(self.allocator);
            symbolItems.deinit();
        }

        for (state.items) |item| {
            const rule = self.rules.items[item.ruleId];
            if (item.dot >= rule.rhs.len) continue; // No symbol after dot

            const nextSym = rule.rhs[item.dot];
            const entry = try symbolItems.getOrPut(nextSym);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            // Advance dot: A → α • X β becomes A → α X • β
            try entry.value_ptr.append(self.allocator, .{ .ruleId = item.ruleId, .dot = item.dot + 1 });
        }

        // Create transitions and target states
        var iter = symbolItems.iterator();
        while (iter.next()) |entry| {
            const sym = entry.key_ptr.*;
            const itemsList = entry.value_ptr;

            const kernel = try self.allocator.dupe(ParserItem, itemsList.items);
            const sig = try self.kernelSignature(kernel);

            // Reuse existing state with same kernel, or create new one
            const target = if (stateMap.get(sig)) |existing| existing else blk: {
                const newState = try self.closure(kernel);
                const newId: u16 = @intCast(self.states.items.len);
                try self.states.append(self.allocator, newState);
                try stateMap.put(self.allocator, sig, newId);
                break :blk newId;
            };

            try transitions.append(self.allocator, .{ .symbol = sym, .target = target });
        }

        self.states.items[stateIdx].transitions = try transitions.toOwnedSlice(self.allocator);
    }

    /// Generate a unique signature for a kernel (set of items).
    /// States with identical kernels are merged to avoid duplication.
    fn kernelSignature(self: *ParserGenerator, kernel: []const ParserItem) ![]const u8 {
        var sig: std.ArrayListUnmanaged(u8) = .empty;

        const sorted = try self.allocator.dupe(ParserItem, kernel);
        defer self.allocator.free(sorted);

        std.mem.sort(ParserItem, sorted, {}, struct {
            fn lessThan(_: void, a: ParserItem, b: ParserItem) bool {
                if (a.ruleId != b.ruleId) return a.ruleId < b.ruleId;
                return a.dot < b.dot;
            }
        }.lessThan);

        for (sorted, 0..) |item, i| {
            if (i > 0) try sig.append(self.allocator, '|');
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}.{d}", .{ item.ruleId, item.dot }) catch "";
            try sig.appendSlice(self.allocator, slice);
        }

        return try sig.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // FIRST/FOLLOW Set Computation
    // =========================================================================
    //
    // FIRST and FOLLOW sets are used in parse table construction.
    // FIRST sets are always needed (for LALR(1) closure and SLR(1) alike).
    // FOLLOW sets are only needed in SLR(1) mode.
    //
    // FIRST(α) = set of terminals that can begin strings derived from α
    //   - FIRST(terminal) = { terminal }
    //   - FIRST(A) = union of FIRST(rhs) for all productions A → rhs
    //   - FIRST(αβ) = FIRST(α) ∪ (FIRST(β) if α is nullable)
    //
    // FOLLOW(A) = set of terminals that can appear immediately after A
    //   - If S → αAβ, then FIRST(β) ⊆ FOLLOW(A)
    //   - If S → αA or S → αAβ where β is nullable, then FOLLOW(S) ⊆ FOLLOW(A)
    //
    // =========================================================================

    fn computeLookaheads(self: *ParserGenerator) !void {
        try self.computeNullable();
        try self.computeFirst();
        switch (self.parseMode) {
            .slr => try self.computeFollow(),
            .lalr => try self.computeLalrLookaheads(),
        }
    }

    /// Compute which symbols can derive the empty string (ε).
    ///
    /// A symbol is nullable if:
    ///   - It has a production with empty RHS: A → ε
    ///   - All symbols in some production's RHS are nullable: A → B C where B, C nullable
    ///
    /// Uses fixed-point iteration until no changes.
    fn computeNullable(self: *ParserGenerator) !void {
        var changed = true;
        while (changed) {
            changed = false;

            for (self.rules.items) |*rule| {
                if (rule.nullable) continue;

                var allNullable = true;
                for (rule.rhs) |symId| {
                    if (!self.symbols.items[symId].nullable) {
                        allNullable = false;
                        break;
                    }
                }

                if (allNullable or rule.rhs.len == 0) {
                    rule.nullable = true;
                    changed = true;
                }
            }

            for (self.symbols.items) |*sym| {
                if (sym.nullable or sym.kind != .nonterminal) continue;

                for (sym.rules.items) |ruleId| {
                    if (self.rules.items[ruleId].nullable) {
                        sym.nullable = true;
                        changed = true;
                        break;
                    }
                }
            }
        }
    }

    /// Compute FIRST sets for all symbols.
    ///
    /// FIRST(X) = terminals that can begin strings derived from X.
    ///
    /// Algorithm (fixed-point iteration):
    ///   1. For each rule A → X₁ X₂ ... Xₙ:
    ///      - Add FIRST(X₁) to FIRST(A)
    ///      - If X₁ nullable, add FIRST(X₂), etc.
    ///   2. Repeat until no changes
    fn computeFirst(self: *ParserGenerator) !void {
        var changed = true;
        while (changed) {
            changed = false;

            // Compute FIRST for each rule's RHS
            for (self.rules.items) |*rule| {
                const oldCount = rule.firsts.count();
                try self.computeFirstOfSequence(&rule.firsts, rule.rhs);
                if (rule.firsts.count() > oldCount) changed = true;
            }

            // Propagate to nonterminals (union of all their rules' FIRST sets)
            for (self.symbols.items) |*sym| {
                if (sym.kind != .nonterminal) continue;

                for (sym.rules.items) |ruleId| {
                    if (try sym.firsts.addAll(self.allocator, &self.rules.items[ruleId].firsts)) {
                        changed = true;
                    }
                }
            }
        }
    }

    /// Compute FIRST of a sequence of symbols (X₁ X₂ ... Xₙ).
    ///
    /// Add FIRST(X₁). If X₁ nullable, add FIRST(X₂). Continue while nullable.
    fn computeFirstOfSequence(self: *ParserGenerator, result: *ParserSymbolSet, symbols: []const u16) !void {
        for (symbols) |symId| {
            const sym = &self.symbols.items[symId];

            if (sym.kind == .terminal) {
                try result.add(self.allocator, symId);
                break;
            } else {
                _ = try result.addAll(self.allocator, &sym.firsts);
                if (!sym.nullable) break;
            }
        }
    }

    /// Compute FOLLOW sets for all nonterminals.
    ///
    /// FOLLOW(A) = terminals that can appear immediately after A in a derivation.
    ///
    /// Algorithm (fixed-point iteration):
    ///   For each production B → α A β:
    ///     1. Add FIRST(β) to FOLLOW(A)
    ///     2. If β is nullable (or empty), add FOLLOW(B) to FOLLOW(A)
    ///
    /// The FOLLOW set determines when to reduce: if we're in a state with
    /// A → γ • and lookahead ∈ FOLLOW(A), we reduce.
    fn computeFollow(self: *ParserGenerator) !void {
        var changed = true;
        while (changed) {
            changed = false;

            for (self.rules.items) |rule| {
                for (rule.rhs, 0..) |symId, i| {
                    const sym = &self.symbols.items[symId];
                    if (sym.kind != .nonterminal) continue;

                    const oldCount = sym.follows.count();

                    if (i == rule.rhs.len - 1) {
                        // A is at end: FOLLOW(LHS) ⊆ FOLLOW(A)
                        if (try sym.follows.addAll(self.allocator, &self.symbols.items[rule.lhs].follows)) {
                            changed = true;
                        }
                    } else {
                        // A has symbols after it: add FIRST(β) to FOLLOW(A)
                        const beta = rule.rhs[i + 1 ..];
                        try self.computeFirstOfSequence(&sym.follows, beta);

                        var betaNullable = true;
                        for (beta) |b| {
                            if (!self.symbols.items[b].nullable) {
                                betaNullable = false;
                                break;
                            }
                        }
                        if (betaNullable) {
                            _ = try sym.follows.addAll(self.allocator, &self.symbols.items[rule.lhs].follows);
                        }
                    }

                    if (sym.follows.count() > oldCount) changed = true;
                }
            }
        }
    }

    // =========================================================================
    // LALR(1) Construction — DeRemer & Pennello Lookahead Propagation
    // =========================================================================
    //
    // LALR(1) computes per-item per-state lookahead sets for reductions,
    // eliminating spurious conflicts that arise from SLR(1)'s global FOLLOW.
    //
    // Algorithm (works directly from the LR(0) automaton):
    //   1. For each kernel item occurrence (state, item), probe with a
    //      sentinel lookahead and compute LR(1) closure
    //   2. From the closure, extract:
    //      - Spontaneous lookaheads: real terminals for reductions/successors
    //      - Propagation edges: sentinel survived → inherits source lookaheads
    //   3. Fixed-point: seed spontaneous, propagate along edges until stable
    //
    // This avoids building the canonical LR(1) automaton (which can have
    // exponentially more states) and runs in time proportional to the
    // LR(0) automaton size.
    //
    // =========================================================================

    const Lr1Item = struct {
        ruleId: u16,
        dot: u8,
        lookahead: u16,

        fn key(self: Lr1Item) u64 {
            return (@as(u64, self.ruleId) << 24) |
                (@as(u64, self.dot) << 16) |
                self.lookahead;
        }
    };

    fn firstOfSuffix(self: *ParserGenerator, rhs: []const u16, startDot: usize, lookahead: u16) !ParserSymbolSet {
        var result = ParserSymbolSet{};
        var allNullable = true;

        for (rhs[startDot..]) |symId| {
            const sym = &self.symbols.items[symId];
            if (sym.kind == .terminal) {
                try result.add(self.allocator, symId);
                allNullable = false;
                break;
            } else {
                _ = try result.addAll(self.allocator, &sym.firsts);
                if (!sym.nullable) {
                    allNullable = false;
                    break;
                }
            }
        }

        if (allNullable) {
            try result.add(self.allocator, lookahead);
        }

        return result;
    }

    fn probeClosure(self: *ParserGenerator, seedItem: Lr1Item, items: *std.ArrayListUnmanaged(Lr1Item), seen: *std.AutoHashMap(u64, void)) !void {
        seen.clearRetainingCapacity();

        items.clearRetainingCapacity();
        try items.append(self.allocator, seedItem);
        try seen.put(seedItem.key(), {});

        var workIdx: usize = 0;
        while (workIdx < items.items.len) : (workIdx += 1) {
            const item = items.items[workIdx];
            const rule = self.rules.items[item.ruleId];

            if (item.dot >= rule.rhs.len) continue;

            const nextSym = rule.rhs[item.dot];
            const symbol = self.symbols.items[nextSym];

            if (symbol.kind == .nonterminal) {
                var firstSet = try self.firstOfSuffix(rule.rhs, item.dot + 1, item.lookahead);
                defer firstSet.deinit(self.allocator);

                for (symbol.rules.items) |ruleId| {
                    for (firstSet.slice()) |la| {
                        const newItem = Lr1Item{ .ruleId = ruleId, .dot = 0, .lookahead = la };
                        if (!seen.contains(newItem.key())) {
                            try seen.put(newItem.key(), {});
                            try items.append(self.allocator, newItem);
                        }
                    }
                }
            }
        }
    }

    fn computeLalrLookaheads(self: *ParserGenerator) !void {
        const a = self.allocator;
        const numStates = self.states.items.len;
        const sentinel: u16 = std.math.maxInt(u16);
        std.debug.assert(self.symbols.items.len < sentinel);

        // Build offset tables for flat node indexing
        const kernelOffsets = try a.alloc(u32, numStates + 1);
        defer a.free(kernelOffsets);
        const reductionOffsets = try a.alloc(u32, numStates + 1);
        defer a.free(reductionOffsets);

        kernelOffsets[0] = 0;
        reductionOffsets[0] = 0;
        for (0..numStates) |s| {
            kernelOffsets[s + 1] = kernelOffsets[s] + @as(u32, @intCast(self.states.items[s].kernel.len));
            reductionOffsets[s + 1] = reductionOffsets[s] + @as(u32, @intCast(self.states.items[s].reductions.len));
        }

        const totalKernelNodes = kernelOffsets[numStates];
        const totalReductionNodes = reductionOffsets[numStates];
        const totalNodes = totalKernelNodes + totalReductionNodes;

        // Lookahead sets for each node (kernel nodes first, then reduction nodes)
        const nodeSets = try a.alloc(ParserSymbolSet, totalNodes);
        errdefer {
            for (nodeSets) |*s| s.deinit(a);
            a.free(nodeSets);
        }
        for (nodeSets) |*s| s.* = .empty;

        // Propagation edges
        const Edge = struct { source: u32, target: u32 };
        var edges: std.ArrayListUnmanaged(Edge) = .empty;
        defer edges.deinit(a);

        // Reusable buffers for probing
        var closureItems: std.ArrayListUnmanaged(Lr1Item) = .empty;
        defer closureItems.deinit(a);
        var seen = std.AutoHashMap(u64, void).init(a);
        defer seen.deinit();

        // Phase 1: Probe each kernel item, discover spontaneous + propagation
        for (self.states.items, 0..) |state, si| {
            for (state.kernel, 0..) |kernelItem, ki| {
                const sourceNode: u32 = kernelOffsets[si] + @as(u32, @intCast(ki));

                const seed = Lr1Item{
                    .ruleId = kernelItem.ruleId,
                    .dot = kernelItem.dot,
                    .lookahead = sentinel,
                };
                try self.probeClosure(seed, &closureItems, &seen);

                for (closureItems.items) |cItem| {
                    const rule = self.rules.items[cItem.ruleId];

                    if (cItem.dot >= rule.rhs.len) {
                        // Completed item → contributes to a reduction in this state
                        const ri = for (state.reductions, 0..) |red, ri| {
                            if (red.ruleId == cItem.ruleId) break @as(u32, @intCast(ri));
                        } else unreachable;
                        const targetNode: u32 = totalKernelNodes + reductionOffsets[si] + ri;
                        if (cItem.lookahead == sentinel) {
                            try edges.append(a, .{ .source = sourceNode, .target = targetNode });
                        } else {
                            try nodeSets[targetNode].add(a, cItem.lookahead);
                        }
                    } else {
                        // Item with symbol after dot → contributes to kernel item in successor
                        const nextSym = rule.rhs[cItem.dot];
                        const transTarget = for (state.transitions) |trans| {
                            if (trans.symbol == nextSym) break trans.target;
                        } else unreachable;
                        const advancedItem = ParserItem{ .ruleId = cItem.ruleId, .dot = cItem.dot + 1 };
                        const targetKernel = &self.states.items[transTarget];
                        const tkiIdx = for (targetKernel.kernel, 0..) |tki, idx| {
                            if (tki.eql(advancedItem)) break @as(u32, @intCast(idx));
                        } else unreachable;
                        const targetNode: u32 = kernelOffsets[transTarget] + tkiIdx;
                        if (cItem.lookahead == sentinel) {
                            try edges.append(a, .{ .source = sourceNode, .target = targetNode });
                        } else {
                            try nodeSets[targetNode].add(a, cItem.lookahead);
                        }
                    }
                }
            }
        }

        // Phase 2: Fixed-point propagation
        var changed = true;
        while (changed) {
            changed = false;
            for (edges.items) |edge| {
                if (try nodeSets[edge.target].addAll(a, &nodeSets[edge.source])) {
                    changed = true;
                }
            }
        }

        // Phase 3: Extract reduction lookaheads into lalrLookaheads
        const lalrLookaheads = try a.alloc([]const ParserSymbolSet, numStates);
        for (0..numStates) |si| {
            const nr = self.states.items[si].reductions.len;
            const sets = try a.alloc(ParserSymbolSet, nr);
            for (0..nr) |ri| {
                const nodeId = totalKernelNodes + reductionOffsets[si] + @as(u32, @intCast(ri));
                sets[ri] = nodeSets[nodeId];
                nodeSets[nodeId] = .empty; // moved, prevent double-free
            }
            lalrLookaheads[si] = sets;
        }

        // Clean up kernel node sets
        for (0..totalKernelNodes) |n| nodeSets[n].deinit(a);
        a.free(nodeSets);

        self.lalrLookaheads = lalrLookaheads;
    }

    // =========================================================================
    // Parse Table Generation
    // =========================================================================
    //
    // The parse table encodes parser decisions as ACTION and GOTO:
    //
    //   ACTION[state, terminal] = shift s  | reduce r | accept | error
    //   GOTO[state, nonterminal] = state s | error
    //
    // LALR(1) / SLR(1) table construction:
    //   1. SHIFT: If state has A → α • a β (a = terminal), ACTION[state, a] = shift
    //   2. REDUCE: If state has A → α • and a ∈ lookahead(state, item), reduce
    //      - LALR: lookahead = per-item set from merged LR(1) states
    //      - SLR:  lookahead = FOLLOW(A)
    //   3. GOTO: If GOTO(state, A) = s for nonterminal A, GOTO[state, A] = s
    //   4. ACCEPT: If state has S' → S • $, ACTION[state, $] = accept
    //
    // Conflicts:
    //   - Shift/Reduce: Both shift and reduce valid for same (state, terminal)
    //   - Reduce/Reduce: Multiple reductions valid for same (state, terminal)
    //
    // Conflict resolution:
    //   - `<` hint: Prefer reduce (tight binding)
    //   - `>` hint: Prefer shift
    //   - `X "c"` hint: Reduce in table, shift at runtime when pre==0
    //   - Default: Shift wins (standard LR behavior)
    //
    // =========================================================================

    const ParseAction = union(enum) {
        shift: u16,
        reduce: u16,
        gotoState: u16,
        accept: void,
        err: void,
    };

    fn buildParseTable(self: *ParserGenerator) ![][]ParseAction {
        const numStates = self.states.items.len;
        const numSymbols = self.symbols.items.len;

        const table = try self.allocator.alloc([]ParseAction, numStates);
        for (table, 0..) |*row, i| {
            row.* = try self.allocator.alloc(ParseAction, numSymbols);
            for (row.*) |*cell| cell.* = .err;

            const state = &self.states.items[i];

            // Shift/goto actions
            for (state.transitions) |trans| {
                const sym = &self.symbols.items[trans.symbol];
                if (sym.kind == .nonterminal) {
                    row.*[trans.symbol] = .{ .gotoState = trans.target };
                } else {
                    row.*[trans.symbol] = .{ .shift = trans.target };
                }
            }

            // Accept action
            for (state.items) |item| {
                const rule = &self.rules.items[item.ruleId];
                if (item.dot < rule.rhs.len and rule.rhs[item.dot] == self.endId) {
                    if (self.isAcceptRuleId(item.ruleId)) {
                        row.*[self.endId] = .accept;
                    }
                }
            }

            // Reduce actions
            for (state.reductions, 0..) |item, ri| {
                const rule = &self.rules.items[item.ruleId];

                if (self.isAcceptRuleId(item.ruleId)) {
                    row.*[self.endId] = .accept;
                    continue;
                }

                const lhsSym = &self.symbols.items[rule.lhs];

                const reduceTerminals = switch (self.parseMode) {
                    .slr => lhsSym.follows.slice(),
                    .lalr => self.lalrLookaheads[i][ri].slice(),
                };

                for (reduceTerminals) |followId| {
                    const current = &row.*[followId];
                    const fname = self.symbols.items[followId].name;
                    const xChar = if (fname.len == 3) fname[1] else 0;

                    switch (current.*) {
                        .err => current.* = .{ .reduce = item.ruleId },
                        .shift => |s| {
                            if (rule.excludeChar != 0 and xChar == rule.excludeChar) {
                                current.* = .{ .reduce = item.ruleId };
                                try self.xExcludes.append(self.allocator, .{
                                    .state = @intCast(i),
                                    .char = xChar,
                                    .shift = s,
                                });
                            } else if (rule.preferReduce) {
                                current.* = .{ .reduce = item.ruleId };
                            } else if (rule.preferShift) {
                                // > hint: keep shift
                            } else {
                                self.conflicts += 1;
                                try self.conflictDetails.append(self.allocator, .{
                                    .kind = .shiftReduce,
                                    .nameA = lhsSym.name,
                                    .nameB = fname,
                                });
                            }
                        },
                        .reduce => |existing| {
                            if (item.ruleId < existing) {
                                current.* = .{ .reduce = item.ruleId };
                            }
                            self.conflicts += 1;
                            const existingRule = &self.rules.items[existing];
                            try self.conflictDetails.append(self.allocator, .{
                                .kind = .reduceReduce,
                                .nameA = lhsSym.name,
                                .nameB = self.symbols.items[existingRule.lhs].name,
                            });
                        },
                        else => {},
                    }
                }
            }
        }

        return table;
    }

    // =========================================================================
    // Code Generation
    // =========================================================================

    fn generateParserCode(self: *ParserGenerator, lexerCode: []const u8) ![]const u8 {
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &output.writer;

        // Build parse table
        const table = try self.buildParseTable();
        defer {
            for (table) |row| self.allocator.free(row);
            self.allocator.free(table);
        }

        // Collect tags from actions
        try self.collectAllTags();

        // Strip the header from lexer code (it already has std import)
        // The lexer code starts with //! Parser...
        const lexerBody = if (std.mem.indexOf(u8, lexerCode, "// =============================================================================")) |pos|
            lexerCode[pos..]
        else
            lexerCode;

        // Write header
        try writer.print("//! Generated by nexus v{s} — do not edit\n", .{version});
        try writer.writeAll(
            \\
            \\const std = @import("std");
            \\const maxArgs: usize = 32;
            \\
        );

        // Import @lang module (for Tag re-export and @as directives)
        if (self.lang) |name| {
            try writer.print("const {s} = @import(\"{s}.zig\");\n", .{ name, name });
        }

        // Inject @code imports blocks
        for (self.codeBlocks.items) |block| {
            if (std.mem.eql(u8, block.location, "imports")) {
                try writer.writeAll("\n// === @code imports ===\n");
                try writer.writeAll(block.code);
                try writer.writeAll("\n");
            }
        }

        try writer.writeAll(
            \\
            \\// SIMD helpers (fallback if simd.zig not available)
            \\const simd = struct {
            \\    fn findByte(haystack: []const u8, needle: u8) usize {
            \\        for (haystack, 0..) |c, i| if (c == needle) return i;
            \\        return haystack.len;
            \\    }
            \\};
            \\
            \\
        );

        // Write lexer code (body only)
        try writer.writeAll(lexerBody);

        // Generate Tag enum (re-export from language module if @lang specified)
        if (self.lang) |name| {
            try writer.writeAll(
                \\
                \\// =============================================================================
                \\// Tag Enum (re-exported from language module)
                \\// =============================================================================
                \\
            );
            try writer.print("pub const Tag = {s}.Tag;\n", .{name});
        } else {
            try writer.writeAll(
                \\
                \\// =============================================================================
                \\// Tag Enum (auto-extracted from grammar actions)
                \\// =============================================================================
                \\
                \\pub const Tag = enum(u8) {
                \\
            );
            for (self.tagList.items) |tag| {
                try writer.writeAll("    @\"");
                try writer.writeAll(tag);
                try writer.writeAll("\",\n");
            }
            try writer.writeAll("    _,\n};\n");
        }

        // Generate Sexp type (5 clean variants)
        try writer.writeAll(
            \\
            \\// =============================================================================
            \\// S-Expression (AST Node) - 5 Clean Variants
            \\// =============================================================================
            \\
            \\pub const Sexp = union(enum) {
            \\    nil:  void,                                        // Empty (nothing)
            \\    tag:  Tag,                                         // Semantic type (1 byte)
            \\    src:  struct { pos: u32, len: u16, id: u16 },      // Source ref + identity (8 bytes)
            \\    str:  []const u8,                                  // Embedded string (16 bytes)
            \\    list: []const Sexp,                                // Compound: (tag child1 ...)
            \\
            \\    /// Get token text from source
            \\    pub fn getText(self: Sexp, source: []const u8) []const u8 {
            \\        return switch (self) {
            \\            .src => |s| source[s.pos..][0..s.len],
            \\            .str => |s| s,
            \\            else => "",
            \\        };
            \\    }
            \\
            \\    /// Format for debug output
            \\    pub fn write(self: Sexp, source: []const u8, w: anytype) !void {
            \\        switch (self) {
            \\            .nil => try w.writeAll("_"),
            \\            .tag => |t| try w.print("{s}", .{@tagName(t)}),
            \\            .src => |s| try w.print("{s}", .{source[s.pos..][0..s.len]}),
            \\            .str => |s| try w.print("\"{s}\"", .{s}),
            \\            .list => |items| {
            \\                try w.writeAll("(");
            \\                for (items, 0..) |item, i| {
            \\                    if (i > 0) try w.writeAll(" ");
            \\                    try item.write(source, w);
            \\                }
            \\                try w.writeAll(")");
            \\            },
            \\        }
            \\    }
            \\
        );

        // Inject @code sexp blocks
        for (self.codeBlocks.items) |block| {
            if (std.mem.eql(u8, block.location, "sexp")) {
                try writer.writeAll("\n    // === @code sexp ===\n");
                // Indent each line by 4 spaces
                var lines = std.mem.splitScalar(u8, block.code, '\n');
                while (lines.next()) |line| {
                    if (line.len > 0) {
                        try writer.writeAll("    ");
                        try writer.writeAll(line);
                    }
                    try writer.writeAll("\n");
                }
            }
        }

        try writer.writeAll(
            \\};
            \\
            \\// =============================================================================
            \\// BaseSexer (raw parser: tokens → S-expressions)
            \\// =============================================================================
            \\
            \\pub const BaseSexer = struct {
            \\    arena: std.heap.ArenaAllocator,
            \\    lexer: Lexer,
            \\    source: []const u8,
            \\    current: Token,
            \\    injectedToken: ?u16 = null,
            \\    lastMatchedId: u16 = 0,
            \\
            \\    stateStack: std.ArrayListUnmanaged(u16) = .empty,
            \\    valueStack: std.ArrayListUnmanaged(Sexp) = .empty,
            \\
            \\    pub fn init(backingAllocator: std.mem.Allocator, source: []const u8) BaseSexer {
            \\        var p = BaseSexer{
            \\            .arena = std.heap.ArenaAllocator.init(backingAllocator),
            \\            .lexer = Lexer.init(source),
            \\            .source = source,
            \\            .current = undefined,
            \\        };
            \\        p.current = p.lexer.next();
            \\        return p;
            \\    }
            \\
            \\    pub fn deinit(self: *BaseSexer) void {
            \\        self.arena.deinit();
            \\    }
            \\
            \\    fn allocator(self: *BaseSexer) std.mem.Allocator {
            \\        return self.arena.allocator();
            \\    }
            \\
            \\    pub fn printError(self: *BaseSexer) void {
            \\        const pos: usize = @min(self.current.pos, self.source.len);
            \\        var line: usize = 1;
            \\        var col: usize = 1;
            \\        var i: usize = 0;
            \\        while (i < pos) : (i += 1) {
            \\            if (self.source[i] == '\n') {
            \\                line += 1;
            \\                col = 1;
            \\            } else {
            \\                col += 1;
            \\            }
            \\        }
            \\        std.debug.print("Parse error at line {d}, column {d}: unexpected {s}\n", .{
            \\            line,
            \\            col,
            \\            @tagName(self.current.cat),
            \\        });
            \\    }
            \\
            \\    fn doParse(self: *BaseSexer, startSym: u16) !Sexp {
            \\        const startState = getStartState(startSym);
            \\        self.stateStack.clearRetainingCapacity();
            \\        self.valueStack.clearRetainingCapacity();
            \\        try self.stateStack.append(self.allocator(), startState);
            \\
            \\        while (true) {
            \\            const state = self.stateStack.getLast();
            \\            const sym = if (self.injectedToken) |inj| inj else self.tokenToSymbol(self.current);
            \\            var action = getAction(state, sym);
            \\
            \\            // X "c" check: if reducing and next char matches with pre==0, shift instead
            \\            if (action < -1 and self.current.pre == 0 and self.current.pos < self.source.len) {
            \\                if (getImmediateShift(state, self.source[self.current.pos])) |shiftTarget| {
            \\                    action = shiftTarget;
            \\                }
            \\            }
            \\
            \\            if (action == 0) {
            \\                return error.ParseError;
            \\            } else if (action == -1) {
            \\                return self.valueStack.getLast();
            \\            } else if (action > 0) {
            \\                // Shift
            \\                if (self.injectedToken != null) {
            \\                    try self.valueStack.append(self.allocator(), .nil);
            \\                    self.injectedToken = null;
            \\                } else {
            \\                    try self.valueStack.append(self.allocator(), .{ .src = .{
            \\                        .pos = self.current.pos,
            \\                        .len = self.current.len,
            \\                        .id  = if (self.lastMatchedId != 0) self.lastMatchedId else self.lexer.base.aux,
            \\                    } });
            \\                    self.lastMatchedId = 0;
            \\                    self.lexer.base.aux = 0;
            \\                    self.current = self.lexer.next();
            \\                }
            \\                try self.stateStack.append(self.allocator(), @intCast(action));
            \\            } else {
            \\                // Reduce
            \\                const ruleId: u16 = @intCast(-action - 2);
            \\                var pass: [maxArgs]Sexp = undefined;
            \\                const len = ruleLen[ruleId];
            \\                for (0..len) |i| {
            \\                    pass[len - 1 - i] = self.valueStack.pop().?;
            \\                    _ = self.stateStack.pop();
            \\                }
            \\
            \\                const result = self.executeAction(ruleId, pass[0..len]);
            \\
            \\                if (isAcceptRule(ruleId)) return result;
            \\
            \\                try self.valueStack.append(self.allocator(), result);
            \\
            \\                const gotoState = self.stateStack.getLast();
            \\                const next = getAction(gotoState, ruleLhs[ruleId]);
            \\                if (next <= 0) return error.ParseError;
            \\                try self.stateStack.append(self.allocator(), @intCast(next));
            \\            }
            \\        }
            \\    }
            \\
            \\    /// Spread list helper: [head, ...tail]
            \\    fn spreadList(self: *BaseSexer, head: Sexp, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        out.append(self.allocator(), head) catch return .nil;
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Spread only: [...tail]
            \\    fn spreadOnly(self: *BaseSexer, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Default list handler
            \\    fn list(self: *BaseSexer, pass: []Sexp) Sexp {
            \\        if (pass.len == 0) return .nil;
            \\        if (pass.len == 1) return pass[0];
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        for (pass) |v| out.append(self.allocator(), v) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Build S-expression: (tag items...) with trailing nil trimming
            \\    inline fn sexp(self: *BaseSexer, comptime tag: Tag, items: []const Sexp) Sexp {
            \\        if (items.len == 0) {
            \\            const result = self.allocator().alloc(Sexp, 1) catch return .nil;
            \\            result[0] = .{ .tag = tag };
            \\            return .{ .list = result };
            \\        }
            \\        var len = items.len;
            \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
            \\        const result = self.allocator().alloc(Sexp, len + 1) catch return .nil;
            \\        result[0] = .{ .tag = tag };
            \\        if (len > 0) @memcpy(result[1..][0..len], items[0..len]);
            \\        return .{ .list = result };
            \\    }
            \\
            \\    /// Build S-expression: (tag ...spread) - tag + spread items
            \\    inline fn sexpSpread(self: *BaseSexer, comptime tag: Tag, spread: Sexp) Sexp {
            \\        const items = if (spread == .list) spread.list else &[_]Sexp{};
            \\        var len = items.len;
            \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
            \\        const result = self.allocator().alloc(Sexp, len + 1) catch return .nil;
            \\        result[0] = .{ .tag = tag };
            \\        if (len > 0) @memcpy(result[1..][0..len], items[0..len]);
            \\        return .{ .list = result };
            \\    }
            \\
            \\    /// Build S-expression: (tag pos ...spread) - tag + position + spread items
            \\    inline fn sexpPosSpread(self: *BaseSexer, comptime tag: Tag, pos: Sexp, spread: Sexp) Sexp {
            \\        const items = if (spread == .list) spread.list else &[_]Sexp{};
            \\        var len = items.len;
            \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
            \\        const skipPos = (pos == .nil and len == 0);
            \\        const total = if (skipPos) 1 else len + 2;
            \\        const result = self.allocator().alloc(Sexp, total) catch return .nil;
            \\        result[0] = .{ .tag = tag };
            \\        if (!skipPos) {
            \\            result[1] = pos;
            \\            if (len > 0) @memcpy(result[2..][0..len], items[0..len]);
            \\        }
            \\        return .{ .list = result };
            \\    }
            \\
            \\    fn executeAction(self: *BaseSexer, ruleId: u16, pass: []Sexp) Sexp {
            \\        return switch (ruleId) {
            \\
        );

        // Generate per-rule semantic actions
        for (self.rules.items, 0..) |rule, ruleIdx| {
            if (self.emitComments) {
                try writer.print("            // {s} =", .{self.symbols.items[rule.lhs].name});
                for (rule.rhs) |symId| {
                    try writer.print(" {s}", .{self.symbols.items[symId].name});
                }
                if (rule.action) |action| {
                    try writer.print(" \xe2\x86\x92 {s}", .{action.template});
                }
                try writer.writeAll("\n");
            }
            try writer.print("            {d} => ", .{ruleIdx});
            try self.generateRuleAction(writer, rule);
            try writer.writeAll(",\n");
        }

        try writer.writeAll(
            \\            else => .nil,
            \\        };
            \\    }
            \\
        );

        // Check if we have @as directives for "ident" - if so, route through identToSymbol
        var hasIdentAs = false;
        for (self.asDirectives.items) |directive| {
            if (std.mem.eql(u8, directive.token, "ident")) {
                hasIdentAs = true;
                break;
            }
        }

        if (hasIdentAs) {
            try writer.writeAll("\n    fn tokenToSymbol(self: *BaseSexer, token: Token) u16 {\n");
        } else {
            try writer.writeAll("\n    fn tokenToSymbol(_: *BaseSexer, token: Token) u16 {\n");
        }
        try writer.writeAll("        return switch (token.cat) {\n");

        // Generate token to symbol mapping
        try writer.print("            .@\"eof\" => {d},\n", .{self.endId});
        var emittedCats: std.StringHashMapUnmanaged(void) = .empty;
        defer {
            var it = emittedCats.keyIterator();
            while (it.next()) |key| self.allocator.free(key.*);
            emittedCats.deinit(self.allocator);
        }

        if (hasIdentAs) {
            try writer.writeAll("            .@\"ident\" => self.identToSymbol(token),\n");
        }

        for (self.symbols.items) |sym| {
            if (sym.kind == .terminal and sym.name.len > 0) {
                // Skip special symbols
                if (sym.name[0] == '$' or sym.name[0] == '"') continue;
                // Skip marker tokens (end with !)
                if (std.mem.endsWith(u8, sym.name, "!")) continue;
                // Skip "error" - it's the fallback
                if (std.mem.eql(u8, sym.name, "error")) continue;

                // Convert to lowercase for TokenCat matching
                var lowerBuf: [64]u8 = undefined;
                var len: usize = 0;
                for (sym.name) |c| {
                    if (len >= lowerBuf.len) break;
                    lowerBuf[len] = if (c >= 'A' and c <= 'Z') c + 32 else c;
                    len += 1;
                }
                const lowerName = lowerBuf[0..len];

                // Skip ident if we're routing through identToSymbol
                if (hasIdentAs and std.mem.eql(u8, lowerName, "ident")) continue;

                // Determine if this terminal is an @as keyword (handled by identToSymbol)
                // vs a real lexer token (needs tokenToSymbol mapping).
                //
                // A terminal is keyword-only if it has no declared lexer token.
                // Terminals declared in the tokens block (including rewriter-classified
                // tokens like if_mod, then_sep) always get direct tokenToSymbol entries,
                // even if a nonterminal shares the same name (case-insensitive).
                var isAsKeyword = false;
                if (sym.name.len > 0 and sym.name[0] >= 'A' and sym.name[0] <= 'Z') {
                    // Check if it matches an @as directive rule name (e.g., CMD↔cmd)
                    for (self.asDirectives.items) |directive| {
                        if (std.ascii.eqlIgnoreCase(sym.name, directive.rule)) {
                            isAsKeyword = true;
                            break;
                        }
                    }
                    // Check if there's a corresponding lowercase nonterminal (e.g., IF↔if)
                    // but only if the terminal is NOT a declared lexer token.
                    if (!isAsKeyword) {
                        var hasLexerToken = false;
                        if (self.lexerSpec) |spec| {
                            for (spec.tokens.items) |tok| {
                                if (std.ascii.eqlIgnoreCase(tok.name, sym.name)) {
                                    hasLexerToken = true;
                                    break;
                                }
                            }
                            if (!hasLexerToken) {
                                for (spec.rules.items) |rule| {
                                    if (std.ascii.eqlIgnoreCase(rule.token, sym.name)) {
                                        hasLexerToken = true;
                                        break;
                                    }
                                }
                            }
                        }
                        if (!hasLexerToken) {
                            // No lexer token: check nonterminal name match
                            for (self.symbols.items) |other| {
                                if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                                    isAsKeyword = true;
                                    break;
                                }
                            }
                            // Final fallback: if @as exists and no lexer token, it's a keyword
                            if (!isAsKeyword and hasIdentAs) {
                                isAsKeyword = true;
                            }
                        }
                    }
                }

                // Skip @as keywords - they're handled by identToSymbol
                if (isAsKeyword) continue;

                // Only generate for tokens that look like lexer token types (start with letter, no special chars)
                var valid = len > 0 and lowerName[0] >= 'a' and lowerName[0] <= 'z';
                if (valid) {
                    for (lowerName) |ch| {
                        if (!((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_')) {
                            valid = false;
                            break;
                        }
                    }
                }
                if (valid and !emittedCats.contains(lowerName)) {
                    try writer.print("            .@\"{s}\" => {d},\n", .{ lowerName, sym.id });
                    try emittedCats.put(self.allocator, try self.allocator.dupe(u8, lowerName), {});
                }
            }
        }

        // Generate @op mappings for operator literals (e.g., "'=" => noteq)
        for (self.symbols.items) |sym| {
            if (sym.kind == .terminal and sym.name.len >= 2 and sym.name[0] == '"') {
                const rawLiteral = sym.name[1 .. sym.name.len - 1];
                // Unescape the literal (handle \\ -> \)
                var literalBuf: [256]u8 = undefined;
                var literalLen: usize = 0;
                var i: usize = 0;
                while (i < rawLiteral.len) : (i += 1) {
                    if (rawLiteral[i] == '\\' and i + 1 < rawLiteral.len) {
                        i += 1;
                        literalBuf[literalLen] = rawLiteral[i];
                    } else {
                        literalBuf[literalLen] = rawLiteral[i];
                    }
                    literalLen += 1;
                }
                const literal = literalBuf[0..literalLen];
                // Look up in @op mappings
                for (self.opMappings.items) |m| {
                    if (std.mem.eql(u8, literal, m.lit) and !emittedCats.contains(m.tok)) {
                        try writer.print("            .@\"{s}\" => {d},\n", .{ m.tok, sym.id });
                        try emittedCats.put(self.allocator, try self.allocator.dupe(u8, m.tok), {});
                        break;
                    }
                }
            }
        }

        // Map single-character terminals to the token names declared in the lexer spec.
        for (self.symbols.items) |sym| {
            if (sym.kind != .terminal or sym.name.len < 3 or sym.name[0] != '"') continue;

            const char: ?u8 = if (sym.name.len == 3 and sym.name[2] == '"')
                sym.name[1]
            else if (sym.name.len == 4 and sym.name[1] == '\\' and sym.name[3] == '"')
                sym.name[2]
            else
                null;

            if (char) |c| {
                if (self.lexerSpec) |spec| {
                    if (findTokenForChar(spec, c)) |tokName| {
                        if (!emittedCats.contains(tokName)) {
                            try writer.print("            .@\"{s}\" => {d},\n", .{ tokName, sym.id });
                            try emittedCats.put(self.allocator, try self.allocator.dupe(u8, tokName), {});
                        }
                        continue;
                    }
                }
            }
        }

        // Map multi-character literals to lexer token names when possible.
        for (self.symbols.items) |sym| {
            if (sym.kind != .terminal or sym.name.len < 4 or sym.name[0] != '"') continue;
            const raw = sym.name[1 .. sym.name.len - 1];
            if (raw.len < 2) continue;
            if (self.lexerSpec) |spec| {
                if (findTokenForLiteral(spec, raw)) |tokName| {
                    if (!emittedCats.contains(tokName)) {
                        try writer.print("            .@\"{s}\" => {d},\n", .{ tokName, sym.id });
                        try emittedCats.put(self.allocator, try self.allocator.dupe(u8, tokName), {});
                    }
                }
            }
        }

        try writer.print(
            \\            else => {d}, // error
            \\        }};
            \\    }}
            \\
        , .{self.errorId});

        // Generate identToSymbol based on @as directives
        if (self.asDirectives.items.len > 0) {
            try writer.writeAll(
                \\
                \\    fn identToSymbol(self: *BaseSexer, token: Token) u16 {
                \\        const text = self.source[token.pos..][0..token.len];
                \\        if (text.len == 0) return symIdent;
                \\
            );

            // Ordered resolution: try @as candidates in declared order.
            // "self" means check if plain IDENT is valid before continuing.
            for (self.asDirectives.items) |directive| {
                if (!std.mem.eql(u8, directive.token, "ident")) continue;
                if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) {
                    try writer.writeAll("        if (getAction(self.stateStack.getLast(), symIdent) != 0) return symIdent;\n");
                } else {
                    const cap = capitalized(directive.rule);
                    const capName = cap[0..directive.rule.len];
                    try writer.print("        if (self.tryIdentAs{s}(token, text)) |sym| return sym;\n", .{capName});
                }
            }

            try writer.writeAll(
                \\        return symIdent;
                \\    }
                \\
            );

            // Generate tryIdentAs* functions for each @as directive (skip "self" entries)
            // Matching mode per group:
            //   - Explicit "!" suffix (keyword!) -> permissive: action != 0 (reduce-aware)
            //   - After "self" checkpoint       -> permissive: action != 0
            //   - Before "self" (default)       -> strict: action > 0 (shift only)
            if (self.lang) |langName| {
                var seenSelf = false;
                for (self.asDirectives.items) |directive| {
                    if (!std.mem.eql(u8, directive.token, "ident")) continue;
                    if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) {
                        seenSelf = true;
                        continue;
                    }
                    const actionCheck: []const u8 = if (directive.permissive or seenSelf) "!= 0" else "> 0";

                    const cap = capitalized(directive.rule);
                    const capName = cap[0..directive.rule.len];
                    try writer.print(
                        \\
                        \\    fn tryIdentAs{s}(self: *BaseSexer, token: Token, text: []const u8) ?u16 {{
                        \\        _ = token;
                        \\        const state = self.stateStack.getLast();
                        \\        if ({s}.{s}As(text)) |id| {{
                                                    \\            const idIdx = @intFromEnum(id);
                        \\            const sym = {s}ToSymbol[idIdx];
                        \\            if (sym != 0 and getAction(state, sym) {s}) {{
                        \\                self.lastMatchedId = @intCast(idIdx);
                        \\                return sym;
                        \\            }}
                        \\            const fallback = {s}FallbackSymbol;
                        \\            if (fallback != 0 and getAction(state, fallback) {s}) {{
                        \\                self.lastMatchedId = @intCast(idIdx);
                        \\                return fallback;
                        \\            }}
                        \\        }}
                        \\        return null;
                        \\    }}
                        \\
                    , .{ capName, langName, directive.rule, directive.rule, actionCheck, directive.rule, actionCheck });
                }
            } else {
                // Inline: generate simple exact-match keyword functions
                var seenSelf2 = false;
                for (self.asDirectives.items) |directive| {
                    if (!std.mem.eql(u8, directive.token, "ident")) continue;
                    if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) {
                        seenSelf2 = true;
                        continue;
                    }
                    const actionCheck: []const u8 = if (directive.permissive or seenSelf2) "!= 0" else "> 0";

                    const cap = capitalized(directive.rule);
                    const capName = cap[0..directive.rule.len];
                    try writer.print(
                        \\
                        \\    fn tryIdentAs{s}(self: *BaseSexer, token: Token, text: []const u8) ?u16 {{
                        \\        _ = token;
                        \\        const state = self.stateStack.getLast();
                        \\        if ({s}As(text)) |id| {{
                        \\            const sym = {s}ToSymbol[@intFromEnum(id)];
                        \\            if (sym != 0 and getAction(state, sym) {s}) {{
                        \\                self.lastMatchedId = @intFromEnum(id);
                        \\                return sym;
                        \\            }}
                        \\        }}
                        \\        return null;
                        \\    }}
                        \\
                    , .{ capName, directive.rule, directive.rule, actionCheck });
                }
            }
        } else {
            // No @as directives - simple passthrough
            try writer.writeAll(
                \\
                \\    fn identToSymbol(_: *BaseSexer, _: Token) u16 {
                \\        return symIdent;
                \\    }
                \\
            );
        }

        // Generate parse functions for each start symbol
        for (self.startSymbols.items) |symId| {
            const name = self.symbols.items[symId].name;
            var fnameBuf: [64]u8 = undefined;
            fnameBuf[0] = if (name[0] >= 'a' and name[0] <= 'z') name[0] - 32 else name[0];
            @memcpy(fnameBuf[1..name.len], name[1..]);
            const fname = fnameBuf[0..name.len];

            var markerBuf: [128]u8 = undefined;
            const markerName = std.fmt.bufPrint(&markerBuf, "{s}!", .{name}) catch continue;
            if (self.getSymbol(markerName) != null) {
                try writer.print(
                    \\
                    \\    pub fn parse{s}(self: *BaseSexer) !Sexp {{
                    \\        self.injectedToken = SYM_{s}_START;
                    \\        return self.doParse(SYM_{s});
                    \\    }}
                , .{ fname, name, name });
            }
        }

        // Inject @code parser blocks
        for (self.codeBlocks.items) |block| {
            if (std.mem.eql(u8, block.location, "parser")) {
                try writer.writeAll("\n    // === @code parser ===\n");
                // Indent each line by 4 spaces
                var lines = std.mem.splitScalar(u8, block.code, '\n');
                while (lines.next()) |line| {
                    if (line.len > 0) {
                        try writer.writeAll("    ");
                        try writer.writeAll(line);
                    }
                    try writer.writeAll("\n");
                }
            }
        }

        try writer.writeAll("\n};\n\n");

        // Sexer auto-wire: when @lang is set, allow the lang module to wrap
        // BaseSexer with semantic rewriting. Mirrors the Lexer auto-wire.
        if (self.lang) |langName| {
            try writer.print(
                \\// =============================================================================
                \\// Sexer (sexp rewriter)
                \\//
                \\// Optional wrapper supplied by the @lang module. When `{s}.zig` exports a
                \\// `pub const Sexer = struct {{ ... }}` whose surface matches BaseSexer
                \\// (`init(allocator, source) -> Self`, `deinit`, `parse{{Start}}() !Sexp`),
                \\// the generated parser routes through it. Otherwise Sexer aliases
                \\// BaseSexer directly and there is no behavioral change.
                \\// =============================================================================
                \\
                \\pub const Sexer = if (@hasDecl({s}, "Sexer")) {s}.Sexer else BaseSexer;
                \\
                \\
            , .{ langName, langName, langName });
        }

        // Top-level parse{Start}(allocator, source) convenience helpers.
        //
        // The returned Sexp references arena-allocated memory owned by the
        // returned `sexer`; the caller must keep the sexer alive for the
        // lifetime of the tree and call `result.sexer.deinit()` when done.
        // This mirrors the convention already used inside the generator
        // (`parseGrammarSexp` in src/nexus.zig).
        var hasTopLevelHelpers = false;
        for (self.startSymbols.items) |symId| {
            const name = self.symbols.items[symId].name;
            var markerBuf: [128]u8 = undefined;
            const markerName = std.fmt.bufPrint(&markerBuf, "{s}!", .{name}) catch continue;
            if (self.getSymbol(markerName) == null) continue;

            if (!hasTopLevelHelpers) {
                hasTopLevelHelpers = true;
                try writer.writeAll(
                    \\// =============================================================================
                    \\// Top-level convenience helpers (one per start symbol)
                    \\// =============================================================================
                    \\
                );
            }

            var fnameBuf: [64]u8 = undefined;
            fnameBuf[0] = if (name[0] >= 'a' and name[0] <= 'z') name[0] - 32 else name[0];
            @memcpy(fnameBuf[1..name.len], name[1..]);
            const fname = fnameBuf[0..name.len];

            const sexerType: []const u8 = if (self.lang != null) "Sexer" else "BaseSexer";

            try writer.print(
                \\
                \\/// Convenience: instantiate the (lang-extended) sexer and parse a whole
                \\/// {s}. Caller owns `result.sexer` and must call `result.sexer.deinit()`
                \\/// when done with the returned tree (the tree references arena-allocated
                \\/// memory owned by the sexer).
                \\pub fn parse{s}(allocator: std.mem.Allocator, source: []const u8) !struct {{ sexer: {s}, sexp: Sexp }} {{
                \\    var s = {s}.init(allocator, source);
                \\    errdefer s.deinit();
                \\    const sexp = try s.parse{s}();
                \\    return .{{ .sexer = s, .sexp = sexp }};
                \\}}
                \\
            , .{ name, fname, sexerType, sexerType, fname });
        }
        if (hasTopLevelHelpers) try writer.writeAll("\n");

        // Generate symbol constants
        try writer.writeAll("// Symbol IDs\n");
        for (self.startSymbols.items) |symId| {
            const name = self.symbols.items[symId].name;
            try writer.print("const SYM_{s}: u16 = {d};\n", .{ name, symId });
            // Marker token
            const markerName = try std.fmt.allocPrint(self.allocator, "{s}!", .{name});
            defer self.allocator.free(markerName);
            if (self.getSymbol(markerName)) |markerId| {
                try writer.print("const SYM_{s}_START: u16 = {d};\n", .{ name, markerId });
            }
        }

        // Generate SYM_IDENT for identToSymbol fallback
        if (self.getSymbol("IDENT")) |identId| {
            try writer.print("const symIdent: u16 = {d};\n", .{identId});
        } else {
            // Fallback to error symbol if IDENT not defined
            try writer.print("const symIdent: u16 = {d};\n", .{self.errorId});
        }

        // Generate *ToSymbol mapping arrays and keyword matchers for @as directives
        if (self.lang) |langName| {
            for (self.asDirectives.items) |directive| {
                if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) continue;
                var specificTerminals: std.ArrayListUnmanaged(struct { name: []const u8, id: u16 }) = .empty;
                defer specificTerminals.deinit(self.allocator);

                // Collect ALL uppercase terminals as potential keyword targets.
                // @hasField at comptime filters to those in the lang module's enum.
                for (self.symbols.items) |sym| {
                    if (sym.kind != .terminal or sym.name.len == 0) continue;
                    if (sym.name[0] < 'A' or sym.name[0] > 'Z') continue;
                    if (sym.name[0] == '"') continue;
                    if (std.mem.endsWith(u8, sym.name, "!")) continue;
                    try specificTerminals.append(self.allocator, .{ .name = sym.name, .id = sym.id });
                }

                var fallbackNameBuf: [64]u8 = undefined;
                const fallbackName = std.ascii.upperString(fallbackNameBuf[0..directive.rule.len], directive.rule);
                var fallbackId: ?u16 = null;
                for (self.symbols.items) |sym| {
                    if (sym.kind == .terminal and std.mem.eql(u8, sym.name, fallbackName)) {
                        fallbackId = sym.id;
                        break;
                    }
                }

                const hasMappings = specificTerminals.items.len > 0;
                const hasFallback = fallbackId != null;
                const needsVar = hasMappings or hasFallback;

                const cap = capitalized(directive.rule);
                const capName = cap[0..directive.rule.len];
                try writer.print(
                    \\
                    \\// Mapping from {s}.{s}Id to grammar symbol IDs (computed at comptime)
                    \\const {s}ToSymbol = blk: {{
                    \\
                , .{ langName, capName, directive.rule });

                if (needsVar) {
                    try writer.writeAll("    var arr: [512]u16 = .{0} ** 512;\n");
                } else {
                    try writer.writeAll("    const arr: [512]u16 = .{0} ** 512;\n");
                }

                for (specificTerminals.items) |term| {
                    try writer.print("    if (@hasField({s}.{s}Id, \"{s}\")) arr[@intFromEnum({s}.{s}Id.{s})] = {d};\n", .{ langName, capName, term.name, langName, capName, term.name, term.id });
                }

                if (fallbackId) |fid| {
                    try writer.print(
                        \\    for (@typeInfo({s}.{s}Id).@"enum".fields) |field| {{
                        \\        if (arr[field.value] == 0) arr[field.value] = {d};
                        \\    }}
                        \\
                    , .{ langName, capName, fid });
                }

                try writer.writeAll("    break :blk arr;\n};\n");
                try writer.print("const {s}FallbackSymbol: u16 = {d};\n", .{ directive.rule, fallbackId orelse 0 });
            }
        } else {
            // Inline: generate Id enums, As functions, and ToSymbol mappings
            var emittedRules = std.StringHashMap(void).init(self.allocator);
            defer emittedRules.deinit();

            for (self.asDirectives.items) |directive| {
                if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) continue;
                if (emittedRules.contains(directive.rule)) continue;
                emittedRules.put(directive.rule, {}) catch {};

                var upperBuf: [64]u8 = undefined;
                const upper = std.ascii.upperString(upperBuf[0..directive.rule.len], directive.rule);
                const cap = capitalized(directive.rule);
                const capName = cap[0..directive.rule.len];
                try writer.print("\nconst {s}Id = enum(u16) {{ {s} = 0 }};\n", .{ capName, upper });
                try writer.print("fn {s}As(name: []const u8) ?{s}Id {{ return if (std.mem.eql(u8, name, \"{s}\")) .{s} else null; }}\n", .{ directive.rule, capName, directive.rule, upper });
            }

            for (self.asDirectives.items) |directive| {
                if (std.mem.eql(u8, directive.rule, "self") or std.mem.eql(u8, directive.rule, directive.token)) continue;
                var specificTerminals: std.ArrayListUnmanaged(struct { name: []const u8, id: u16 }) = .empty;
                defer specificTerminals.deinit(self.allocator);

                for (self.symbols.items) |sym| {
                    if (sym.kind != .terminal or sym.name.len == 0) continue;
                    if (sym.name[0] < 'A' or sym.name[0] > 'Z') continue;
                    if (sym.name[0] == '"') continue;
                    for (self.symbols.items) |other| {
                        if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                            try specificTerminals.append(self.allocator, .{ .name = sym.name, .id = sym.id });
                            break;
                        }
                    }
                }

                var fallbackNameBuf: [64]u8 = undefined;
                const fallbackName = std.ascii.upperString(fallbackNameBuf[0..directive.rule.len], directive.rule);
                var fallbackId: ?u16 = null;
                for (self.symbols.items) |sym| {
                    if (sym.kind == .terminal and std.mem.eql(u8, sym.name, fallbackName)) {
                        fallbackId = sym.id;
                        break;
                    }
                }

                const hasMappings = specificTerminals.items.len > 0;
                const hasFallback = fallbackId != null;
                const needsVar = hasMappings or hasFallback;

                const cap2 = capitalized(directive.rule);
                const capName2 = cap2[0..directive.rule.len];
                try writer.print(
                    \\
                    \\const {s}ToSymbol = blk: {{
                    \\
                , .{directive.rule});

                if (needsVar) {
                    try writer.writeAll("    var arr: [512]u16 = .{0} ** 512;\n");
                } else {
                    try writer.writeAll("    const arr: [512]u16 = .{0} ** 512;\n");
                }

                for (specificTerminals.items) |term| {
                    try writer.print("    if (@hasField({s}Id, \"{s}\")) arr[@intFromEnum({s}Id.{s})] = {d};\n", .{ capName2, term.name, capName2, term.name, term.id });
                }

                if (fallbackId) |fid| {
                    try writer.print(
                        \\    for (@typeInfo({s}Id).@"enum".fields) |field| {{
                        \\        if (arr[field.value] == 0) arr[field.value] = {d};
                        \\    }}
                        \\
                    , .{ capName2, fid });
                }

                try writer.writeAll("    break :blk arr;\n};\n");
            }
        }

        // Generate rule tables
        try writer.writeAll("\nconst ruleLhs = [_]u16{ ");
        for (self.rules.items, 0..) |rule, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{rule.lhs});
        }
        try writer.writeAll(" };\n");

        try writer.writeAll("const ruleLen = [_]u8{ ");
        for (self.rules.items, 0..) |rule, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{rule.rhs.len});
        }
        try writer.writeAll(" };\n");

        // Generate parse table
        const numStates = table.len;
        const numSymbols = self.symbols.items.len;

        try writer.print(
            \\
            \\// Parse Table: {d} states × {d} symbols
            \\const numStates = {d};
            \\const numSymbols = {d};
            \\
            \\const sparse = [numStates][]const i16{{
            \\
        , .{ numStates, numSymbols, numStates, numSymbols });

        for (table) |row| {
            try writer.writeAll("    &.{");
            var first = true;
            for (row, 0..) |action, sym| {
                const value: i16 = switch (action) {
                    .shift => |s| @as(i16, @intCast(s)),
                    .reduce => |r| -@as(i16, @intCast(r)) - 2,
                    .gotoState => |g| @as(i16, @intCast(g)),
                    .accept => -1,
                    .err => continue,
                };
                if (!first) try writer.writeAll(",");
                try writer.print("{d},{d}", .{ sym, value });
                first = false;
            }
            try writer.writeAll("},\n");
        }
        try writer.writeAll("};\n\n");

        try writer.writeAll(
            \\const parseTable = blk: {
            \\    @setEvalBranchQuota(100000);
            \\    var t: [numStates][numSymbols]i16 = .{.{0} ** numSymbols} ** numStates;
            \\    for (sparse, 0..) |row, state| {
            \\        var i: usize = 0;
            \\        while (i < row.len) : (i += 2) {
            \\            t[state][@intCast(row[i])] = row[i + 1];
            \\        }
            \\    }
            \\    break :blk t;
            \\};
            \\
            \\fn getAction(state: u16, sym: u16) i16 {
            \\    return parseTable[state][sym];
            \\}
            \\
        );

        // Generate X "c" exclude table - shift when pre==0 and char matches
        try writer.writeAll("// X \"c\" excludes: shift instead of reduce when pre==0 and char matches\n");
        try writer.writeAll("const xExcludes = [_]struct { state: u16, char: u8, shift: u16 }{\n");
        for (self.xExcludes.items) |x| {
            try writer.print("    .{{ .state = {d}, .char = '{c}', .shift = {d} }},\n", .{ x.state, x.char, x.shift });
        }
        try writer.writeAll("};\n\n");

        try writer.writeAll(
            \\fn getImmediateShift(state: u16, char: u8) ?i16 {
            \\    for (xExcludes) |x| {
            \\        if (x.state == state and x.char == char) return @intCast(x.shift);
            \\    }
            \\    return null;
            \\}
            \\
        );

        // Generate start state lookup
        try writer.writeAll("const startStates = [_]struct { sym: u16, state: u16 }{\n");
        for (self.startSymbols.items, self.startStates.items) |sym, state| {
            try writer.print("    .{{ .sym = {d}, .state = {d} }},\n", .{ sym, state });
        }
        try writer.writeAll("};\n\n");

        try writer.writeAll(
            \\fn getStartState(startSym: u16) u16 {
            \\    for (startStates) |entry| {
            \\        if (entry.sym == startSym) return entry.state;
            \\    }
            \\    return 0;
            \\}
            \\
        );

        // Generate accept rules
        try writer.writeAll("\nconst acceptRules = [_]u16{ ");
        for (self.acceptRules.items, 0..) |ruleId, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{ruleId});
        }
        try writer.writeAll(" };\n\n");

        try writer.writeAll(
            \\fn isAcceptRule(ruleId: u16) bool {
            \\    for (acceptRules) |ar| if (ruleId == ar) return true;
            \\    return false;
            \\}
            \\
        );

        // Inject @code bottom blocks
        for (self.codeBlocks.items) |block| {
            if (std.mem.eql(u8, block.location, "bottom")) {
                try writer.writeAll("\n// === @code bottom ===\n");
                try writer.writeAll(block.code);
                try writer.writeAll("\n");
            }
        }

        return try output.toOwnedSlice();
    }

    fn generateRuleAction(self: *ParserGenerator, writer: anytype, rule: ParserRule) !void {
        if (rule.action == null) {
            try writer.writeAll("self.list(pass)");
            return;
        }

        const template = rule.action.?.template;
        const offset = rule.actionOffset;

        // Handle simple cases
        if (std.mem.eql(u8, template, "nil") or std.mem.eql(u8, template, "_")) {
            try writer.writeAll(".nil");
            return;
        }

        if (std.mem.eql(u8, template, "()")) {
            try writer.writeAll(".{ .list = &[_]Sexp{} }");
            return;
        }

        // Handle spread patterns: (!1 ...2)
        if (std.mem.eql(u8, template, "(!1 ...2)")) {
            try writer.writeAll("self.spreadList(pass[0], pass[1])");
            return;
        }
        if (std.mem.eql(u8, template, "(!2 ...3)")) {
            try writer.writeAll("self.spreadList(pass[1], pass[2])");
            return;
        }

        // Handle simple passthrough: 1, 2, etc.
        if (template.len == 1 and template[0] >= '1' and template[0] <= '9') {
            const pos = template[0] - '1' + offset;
            try writer.print("pass[{d}]", .{pos});
            return;
        }

        // Handle paren-style S-expressions: (tag 1 2 3)
        if (template.len > 0 and template[0] == '(') {
            try self.generateParenAction(writer, template, offset);
            return;
        }

        // Fallback
        try writer.writeAll("self.list(pass)");
    }

    fn generateParenAction(self: *ParserGenerator, writer: anytype, template: []const u8, offset: u8) !void {
        // Parse (tag elem1 elem2 ...) and generate build code
        var i: usize = 1; // Skip opening paren
        var elements: std.ArrayListUnmanaged([]const u8) = .empty;
        defer elements.deinit(self.allocator);

        // Skip whitespace and parse elements
        while (i < template.len and template[i] != ')') {
            while (i < template.len and (template[i] == ' ' or template[i] == '\t')) i += 1;
            if (i >= template.len or template[i] == ')') break;
            const start = i;
            while (i < template.len and template[i] != ' ' and template[i] != '\t' and template[i] != ')') i += 1;
            if (i > start) try elements.append(self.allocator, template[start..i]);
        }

        if (elements.items.len == 0) {
            try writer.writeAll(".{ .list = &[_]Sexp{} }");
            return;
        }

        // Analyze elements
        const tag = elements.items[0];
        var tagName = tag;

        // Strip key:value from tag if present (e.g., "dots:2?" -> "dots")
        if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
            const after = tag[colonPos + 1 ..];
            if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                after[0] == '.' or after[0] == '~' or after[0] == '_'))
            {
                tagName = tag[0..colonPos];
            }
        }

        const firstIsTag = self.isTagLiteral(tagName);

        // Count element types
        var spreadCount: usize = 0;
        var spreadPos: u8 = 0;
        var posCount: usize = 0;
        var firstPos: u8 = 0;
        var hasTilde = false;
        var hasOther = false;
        var hasNil = false;

        for (elements.items[1..]) |elem| {
            const work = self.stripKeyAndSuffix(elem);
            if (work.len == 0) continue;
            if (work[0] == '.' and work.len >= 4 and work[1] == '.' and work[2] == '.') {
                spreadCount += 1;
                spreadPos = work[3] - '1' + offset;
            } else if (work[0] == '~') {
                hasTilde = true;
            } else if (work[0] >= '1' and work[0] <= '9') {
                if (posCount == 0) firstPos = work[0] - '1' + offset;
                posCount += 1;
            } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
                hasNil = true; // track nil separately for pattern matching
            } else if (!self.isTagLiteral(work)) {
                hasOther = true;
            }
        }

        // Pattern: (tag ...N) - use sexpSpread (only if no nil elements)
        if (firstIsTag and spreadCount == 1 and posCount == 0 and !hasTilde and !hasOther and !hasNil) {
            try writer.print("self.sexpSpread(.@\"{s}\", pass[{d}])", .{ tagName, spreadPos });
            return;
        }

        // Pattern: (tag N ...M) - use sexpPosSpread (only if no nil elements)
        if (firstIsTag and spreadCount == 1 and posCount == 1 and !hasTilde and !hasOther and !hasNil) {
            try writer.print("self.sexpPosSpread(.@\"{s}\", pass[{d}], pass[{d}])", .{ tagName, firstPos, spreadPos });
            return;
        }

        // Simple case: self.sexp(.@"tag", &.{pass[0], pass[1], ...})
        // Only if first element is a tag and no spreads/tilde
        var tagHasValue = false;
        var tagValue: []const u8 = "";

        // Check if tag has key:value format (like "dots:2?", "type:_")
        if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
            const after = tag[colonPos + 1 ..];
            if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                after[0] == '.' or after[0] == '~' or after[0] == '_'))
            {
                tagHasValue = true;
                tagValue = self.stripKeyAndSuffix(tag);
            }
        }

        if (firstIsTag and spreadCount == 0 and !hasTilde and !hasOther) {
            try writer.print("self.sexp(.@\"{s}\", &.{{", .{tagName});
            var first = true;

            // Add tag's value if it had key:value format
            if (tagHasValue and tagValue.len > 0) {
                if (tagValue[0] >= '1' and tagValue[0] <= '9') {
                    try writer.print("pass[{d}]", .{tagValue[0] - '1' + offset});
                    first = false;
                }
            }

            for (elements.items[1..]) |elem| {
                const work = self.stripKeyAndSuffix(elem);
                if (work.len == 0) continue;
                if (!first) try writer.writeAll(", ");
                first = false;
                if (work[0] >= '1' and work[0] <= '9') {
                    try writer.print("pass[{d}]", .{work[0] - '1' + offset});
                } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
                    try writer.writeAll(".nil");
                } else {
                    // Must be a tag literal - skip (already have main tag)
                }
            }
            try writer.writeAll("})");
            return;
        }

        // Complex case: inline list building (spreads, tilde transforms)
        try writer.writeAll("blk: { var out: std.ArrayListUnmanaged(Sexp) = .empty; ");
        for (elements.items) |elem| {
            if (elem.len == 0) continue;
            const work = self.stripKeyAndSuffix(elem);
            if (work.len == 0) continue;

            if (work[0] >= '1' and work[0] <= '9') {
                const pos = work[0] - '1' + offset;
                try writer.print("out.append(self.allocator(), pass[{d}]) catch break :blk .nil; ", .{pos});
            } else if (work[0] == '~' and work.len > 1 and work[1] >= '1' and work[1] <= '9') {
                const pos = work[1] - '1' + offset;
                try writer.print("out.append(self.allocator(), if (pass[{d}] == .src) pass[{d}] else .{{ .src = .{{ .pos = 0, .len = 0, .id = 0 }} }}) catch break :blk .nil; ", .{ pos, pos });
            } else if (work[0] == '.' and work.len >= 4 and work[1] == '.' and work[2] == '.') {
                const pos = work[3] - '1' + offset;
                try writer.print("if (pass[{d}] == .list) for (pass[{d}].list) |item| out.append(self.allocator(), item) catch break :blk .nil; ", .{ pos, pos });
            } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
                try writer.writeAll("out.append(self.allocator(), .nil) catch break :blk .nil; ");
            } else {
                try writer.print("out.append(self.allocator(), .{{ .tag = .@\"{s}\" }}) catch break :blk .nil; ", .{elem});
            }
        }
        try writer.writeAll("while (out.items.len > 0 and out.items[out.items.len - 1] == .nil) _ = out.pop(); ");
        try writer.writeAll("break :blk .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} }; }");
    }

    fn stripKeyAndSuffix(self: *ParserGenerator, elem: []const u8) []const u8 {
        _ = self;
        var work = elem;
        // Strip key: prefix (e.g., "offset:3" -> "3", "type:_" -> "_")
        if (std.mem.indexOfScalar(u8, work, ':')) |colonPos| {
            const after = work[colonPos + 1 ..];
            if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                after[0] == '.' or after[0] == '~' or after[0] == '_'))
            {
                work = after;
            }
        }
        return work;
    }

    fn isTagLiteral(self: *ParserGenerator, work: []const u8) bool {
        _ = self;
        if (work.len == 0) return false;
        if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) return false;
        const c = work[0];
        // Tag literals start with letter or special char like !, #, ?, @, $
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            c == '!' or c == '#' or c == '?' or c == '@' or c == '$' or c == '*' or c == '/';
    }

    fn registerTag(self: *ParserGenerator, tag: []const u8) !void {
        if (!self.collectedTags.contains(tag)) {
            const owned = try self.allocator.dupe(u8, tag);
            try self.collectedTags.put(self.allocator, owned, @intCast(self.tagList.items.len));
            try self.tagList.append(self.allocator, owned);
        }
    }

    fn collectTagsFromAction(self: *ParserGenerator, template: []const u8) !void {
        // For paren-style: (tag ...) - first element after ( is the tag
        if (template.len > 1 and template[0] == '(') {
            var i: usize = 1;
            while (i < template.len and (template[i] == ' ' or template[i] == '\t')) i += 1;
            const start = i;
            while (i < template.len and template[i] != ' ' and template[i] != '\t' and template[i] != ')') i += 1;
            if (i > start) {
                var tag = template[start..i];
                // Strip key:value suffix (key:N? -> key)
                if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
                    const after = tag[colonPos + 1 ..];
                    if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                        after[0] == '.' or after[0] == '~'))
                    {
                        tag = tag[0..colonPos];
                    }
                }
                // Register tags - includes letters and special chars like ?, !, #
                // Skip numeric refs (1, 2), spreads (...1), and nil/_
                if (tag.len > 0 and !(tag[0] >= '0' and tag[0] <= '9') and tag[0] != '.' and
                    !std.mem.eql(u8, tag, "nil") and !std.mem.eql(u8, tag, "_"))
                {
                    try self.registerTag(tag);
                }
            }
        }
    }

    fn collectAllTags(self: *ParserGenerator) !void {
        for (self.rules.items) |rule| {
            if (rule.action) |action| {
                try self.collectTagsFromAction(action.template);
            }
        }
    }
};

// =============================================================================
// Main
// =============================================================================

fn reportConflicts(pg: *ParserGenerator) void {
    if (pg.conflictDetails.items.len == 0) {
        if (pg.expectConflicts) |expected| {
            if (expected != 0)
                std.debug.print("   ✅ 0 conflicts (expected {d} — consider updating @conflicts)\n", .{expected});
        }
        return;
    }

    const isAutoGen = struct {
        fn f(name: []const u8) bool {
            return std.mem.startsWith(u8, name, "_opt_") or
                std.mem.startsWith(u8, name, "_star_") or
                std.mem.startsWith(u8, name, "_tail_");
        }
    }.f;

    // Deduplicate and classify conflicts
    var benign: u32 = 0;
    var seen = std.StringHashMap(u32).init(pg.allocator);
    defer seen.deinit();

    for (pg.conflictDetails.items) |c| {
        const a = c.nameA;
        const b = c.nameB;
        const isBenign = (c.kind == .reduceReduce and isAutoGen(a) and isAutoGen(b)) or
            (c.kind == .shiftReduce and isAutoGen(a));
        if (isBenign) {
            benign += 1;
        } else {
            var buf: [256]u8 = undefined;
            const keyTag: []const u8 = if (c.kind == .shiftReduce) "S/R" else "R/R";
            const key = std.fmt.bufPrint(&buf, "{s}: {s} vs {s}", .{ keyTag, a, b }) catch continue;
            const owned = pg.allocator.dupe(u8, key) catch continue;
            const gop = seen.getOrPut(owned) catch continue;
            if (gop.found_existing) {
                gop.value_ptr.* += 1;
                pg.allocator.free(owned);
            } else {
                gop.value_ptr.* = 1;
            }
        }
    }

    // Print unique real conflicts with counts
    var iter = seen.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            std.debug.print("  {s} (x{d}) [REVIEW]\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        } else {
            std.debug.print("  {s} [REVIEW]\n", .{entry.key_ptr.*});
        }
        pg.allocator.free(entry.key_ptr.*);
    }

    // Print benign summary
    if (benign > 0)
        std.debug.print("  {d} benign (auto-generated list/optional) [safe]\n", .{benign});

    // Check against @conflicts
    const total = pg.conflicts;
    if (pg.expectConflicts) |expected| {
        if (total == expected) {
            std.debug.print("   ✅ {d} conflicts (as expected)\n", .{total});
        } else {
            std.debug.print("   ⚠️  {d} conflicts (expected {d} — update @conflicts)\n", .{ total, expected });
        }
    } else if (total > 0) {
        std.debug.print("   ⚠️  {d} conflicts detected (add @conflicts = {d} to suppress if ok)\n", .{ total, total });
    }
}

fn findSection(text: []const u8, marker: []const u8) ?usize {
    var pos: usize = 0;
    while (pos < text.len) {
        if ((pos == 0 or text[pos - 1] == '\n') and
            pos + marker.len <= text.len and
            std.mem.eql(u8, text[pos..][0..marker.len], marker))
        {
            return pos;
        }
        pos = std.mem.indexOfScalarPos(u8, text, pos, '\n') orelse text.len;
        if (pos < text.len) pos += 1;
    }
    return null;
}

fn checkGrammar(allocator: Allocator, ir: *const GrammarIR) u32 {
    var errors: u32 = 0;
    var warnings: u32 = 0;

    // Build known rule name set (allow duplicate entries — grammar DSL merges alternatives)
    var ruleNames = std.StringHashMap(void).init(allocator);
    defer ruleNames.deinit();
    for (ir.rules) |rule| {
        ruleNames.put(rule.name, {}) catch {};
    }
    if (ir.infix != null) ruleNames.put("infix", {}) catch {};

    // Check for undefined rule references
    for (ir.rules) |rule| {
        for (rule.alternatives) |alt| {
            checkUndefinedRefs(alt.elements, rule.name, &ruleNames, &errors);
        }
    }

    // Check for unreachable rules (skipped when @as directives are present
    // because keyword expansion creates reachability edges not visible in the IR)
    if (ir.startSymbols.len > 0 and ir.asDirectives.len == 0) {
        var reachable = std.StringHashMap(void).init(allocator);
        defer reachable.deinit();
        for (ir.startSymbols) |s| markReachable(s, ir, &reachable);
        if (ir.infix) |infix| markReachable(infix.baseRule, ir, &reachable);
        for (ir.asDirectives) |d| markReachable(d.rule, ir, &reachable);

        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();
        for (ir.rules) |rule| {
            if (seen.contains(rule.name)) continue;
            seen.put(rule.name, {}) catch {};
            if (!rule.isStart and !reachable.contains(rule.name)) {
                std.debug.print("  warning: unreachable rule '{s}'\n", .{rule.name});
                warnings += 1;
            }
        }
    }

    if (errors > 0 or warnings > 0) {
        std.debug.print("\n  {d} error(s), {d} warning(s)\n", .{ errors, warnings });
    } else {
        std.debug.print("  ✅ No issues found\n", .{});
    }

    return errors;
}

fn checkUndefinedRefs(elements: []const ParsedElement, ruleName: []const u8, ruleNames: *std.StringHashMap(void), errors: *u32) void {
    for (elements) |elem| {
        if (elem.kind == .ident and elem.value.len > 0 and !ruleNames.contains(elem.value)) {
            std.debug.print("  error: undefined rule '{s}' referenced in '{s}'\n", .{ elem.value, ruleName });
            errors.* += 1;
        }
        if (elem.subElements.len > 0) checkUndefinedRefs(elem.subElements, ruleName, ruleNames, errors);
    }
}

fn markReachable(name: []const u8, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    if (reachable.contains(name)) return;
    reachable.put(name, {}) catch return;
    for (ir.rules) |rule| {
        if (!std.mem.eql(u8, rule.name, name)) continue;
        for (rule.alternatives) |alt| {
            for (alt.elements) |elem| {
                if (elem.kind == .ident or elem.kind == .reqList or elem.kind == .optList) {
                    markReachable(elem.value, ir, reachable);
                }
                markReachableElements(elem.subElements, ir, reachable);
            }
        }
    }
}

// =============================================================================
// S-expression pretty-printer
//
// Renders the output of the generated frontend parser in a canonical textual
// form suitable for golden-file comparison. Lists that contain no nested lists
// stay on a single line; any list with a nested list child breaks across
// lines with two-space indentation per level.
//
// Syntactic forms — each Sexp variant prints in an unmistakable wrapper:
//   .nil        → _
//   .tag        → bare tagName  (only ever appears as the first child of a
//                 non-empty list, so it never collides with src content)
//   .src        → `text`        backticks with `\\` and `` \` `` escaping
//   .str        → "text"        double-quoted
//   .list       → (child child ...)
// =============================================================================

fn dumpSexp(writer: anytype, sexp: ngp.Sexp, source: []const u8, indent: usize) !void {
    switch (sexp) {
        .nil => try writer.writeAll("_"),
        .tag => |t| try writer.writeAll(@tagName(t)),
        .src => |s| try dumpSrcText(writer, source[s.pos..][0..s.len]),
        .str => |s| try writer.print("\"{s}\"", .{s}),
        .list => |items| {
            if (items.len == 0) {
                try writer.writeAll("()");
                return;
            }

            var hasNestedList = false;
            for (items) |item| switch (item) {
                .list => |sub| if (sub.len > 0) {
                    hasNestedList = true;
                    break;
                },
                else => {},
            };

            try writer.writeAll("(");
            if (!hasNestedList) {
                for (items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(" ");
                    try dumpSexp(writer, item, source, 0);
                }
            } else {
                try dumpSexp(writer, items[0], source, indent + 2);
                for (items[1..]) |item| {
                    try writer.writeAll("\n");
                    try writer.splatByteAll(' ', indent + 2);
                    try dumpSexp(writer, item, source, indent + 2);
                }
            }
            try writer.writeAll(")");
        },
    }
}

fn dumpSrcText(writer: anytype, text: []const u8) !void {
    try writer.writeByte('`');
    for (text) |c| {
        if (c == '`' or c == '\\') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeByte('`');
}

// Parse the @parser section of a grammar file through the generated frontend
// and return the S-expression tree. Callers own the sexer's arena lifetime
// via the returned BaseSexer; deinit it when finished with the tree.
fn parseGrammarSexp(allocator: Allocator, sourceText: []const u8) !struct {
    sexer: ngp.BaseSexer,
    sexp: ngp.Sexp,
    parserBody: []const u8,
} {
    const parserStart = findSection(sourceText, "@parser") orelse {
        return error.MissingParserSection;
    };
    const parserBody = sourceText[parserStart + 7 ..];
    var sexer = ngp.BaseSexer.init(allocator, parserBody);
    errdefer sexer.deinit();
    const sexp = try sexer.parseGrammar();
    return .{ .sexer = sexer, .sexp = sexp, .parserBody = parserBody };
}

// =============================================================================
// Negative shape tests for the lowerer
//
// Each `test` block constructs a deliberately malformed S-expression tree by
// hand and asserts that GrammarLowerer.lower rejects it with
// error.ShapeError. The goal is to mechanically prove the lowerer's "exact
// shape or hard error" contract — the downstream parser cannot produce
// malformed Sexps by construction, so these shapes can only be built
// directly.
//
// The suite covers every lowering entry point: root dispatch, each
// directive, rule/alt structure, every element variant, list inner shapes,
// quantifiers, and the exclude hint. Collectively they pin down every
// dispatch site in GrammarLowerer against a known-bad shape.
//
// These `test` blocks are compiled only when Zig's test runner is invoked
// (`zig build test-lowerer` or `zig test src/nexus.zig`). They add zero
// bytes to the shipped binary.
// =============================================================================

const testing = std.testing;

// Shared source buffer used by every negative-shape test. Byte layout:
//   0..1  -> "x"         (harmless one-char src for most cases)
//   1..5  -> "\"ab\""    (a multi-char string literal for the exclude-too-long case)
const negSource = "x\"ab\"";
const negSrc0: ngp.Sexp = .{ .src = .{ .pos = 0, .len = 1, .id = 0 } };
const negSrcMulti: ngp.Sexp = .{ .src = .{ .pos = 1, .len = 4, .id = 0 } };

// Wrap an element list as (grammar (rule (name SRC) (alt (elems...)))) so
// the lowerer reaches the element dispatch. Must be comptime so the nested
// `&[_]Sexp{...}` literals resolve into static memory.
fn negRule(comptime elems: []const ngp.Sexp) ngp.Sexp {
    return comptime .{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .name }, negSrc0 } },
            .{ .list = &[_]ngp.Sexp{
                .{ .tag = .alt },
                .{ .list = elems },
            } },
        } },
    } };
}

// Every test below creates its own arena so shape-error bailouts from the
// lowerer don't trip std.testing.allocator's leak detector — the lowerer
// doesn't clean up partially-built IR on early return (processGrammar
// owns the final IR in production).
fn expectShapeError(sexp: ngp.Sexp) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.ShapeError, GrammarLowerer.lower(arena.allocator(), sexp, negSource));
}

test "lowerer rejects non-list root" {
    try expectShapeError(negSrc0);
}

test "lowerer rejects root list with wrong tag" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{.{ .tag = .alt }} });
}

test "lowerer rejects entry that is not a tagged list" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{ .{ .tag = .grammar }, negSrc0 } });
}

test "lowerer rejects entry with unknown tag" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{.{ .tag = .opt }} },
    } });
}

test "lowerer rejects (lang) with no STRING" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{.{ .tag = .lang }} },
    } });
}

test "lowerer rejects (conflicts) with non-numeric src" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .conflicts }, negSrc0 } },
    } });
}

test "lowerer rejects (as) with no entries" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .as }, negSrc0 } },
    } });
}

test "lowerer rejects (as) entry with wrong tag" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .as },
            negSrc0,
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects (op_map) with wrong arity" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .op },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .op_map }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects (level) containing non-infix_op child" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .infix },
            negSrc0,
            .{ .list = &[_]ngp.Sexp{
                .{ .tag = .level },
                .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
            } },
        } },
    } });
}

test "lowerer rejects (rule) with no alts" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .name }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects rule_name tag that is neither start nor name" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .alt }, .{ .list = &[_]ngp.Sexp{} } } },
        } },
    } });
}

test "lowerer rejects alt child that is not list" {
    try expectShapeError(.{ .list = &[_]ngp.Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]ngp.Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .name }, negSrc0 } },
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .alt }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects bare src as an element" {
    try expectShapeError(negRule(&.{negSrc0}));
}

test "lowerer rejects (ref) with wrong arity" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{.{ .tag = .ref }} }}));
}

test "lowerer rejects (list_req) missing inner" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{ .{ .tag = .list_req }, negSrc0 } }}));
}

test "lowerer rejects (list_req) inner with unknown tag" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{
        .{ .tag = .list_req },
        negSrc0,
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (group) with no ALT_BODY" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{.{ .tag = .group }} }}));
}

test "lowerer rejects (quantified) missing quant" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{
        .{ .tag = .quantified },
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (quantified) quant child with wrong tag" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{
        .{ .tag = .quantified },
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
        .{ .list = &[_]ngp.Sexp{.{ .tag = .skip }} },
    } }}));
}

test "lowerer rejects (skip_q) missing quant" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{
        .{ .tag = .skip_q },
        .{ .list = &[_]ngp.Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (exclude) with wrong arity" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{.{ .tag = .exclude }} }}));
}

test "lowerer rejects (exclude) with multi-char literal" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{ .{ .tag = .exclude }, negSrcMulti } }}));
}

test "lowerer rejects (exclude) appearing inside a group body" {
    try expectShapeError(negRule(&.{.{ .list = &[_]ngp.Sexp{
        .{ .tag = .group },
        .{ .list = &[_]ngp.Sexp{
            .{ .list = &[_]ngp.Sexp{ .{ .tag = .exclude }, negSrc0 } },
        } },
    } }}));
}

fn markReachableElements(elements: []const ParsedElement, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    for (elements) |elem| {
        if (elem.kind == .ident or elem.kind == .reqList or elem.kind == .optList) {
            markReachable(elem.value, ir, reachable);
        }
        markReachableElements(elem.subElements, ir, reachable);
    }
}

pub fn main(init: std.process.Init) !void {
    // Nexus is a short-lived CLI: read one grammar, emit one parser, exit.
    // The process-wide arena is the idiomatic allocator for this shape:
    //
    //   - Avoids `std.heap.DebugAllocator`'s O(n) per-alloc tracking overhead,
    //     which made MUMPS generation ~700x slower in Debug (23s vs 33ms).
    //   - Keeps stderr clean (arena doesn't leak-check; previous `init.gpa` usage
    //     surfaced ~400 pre-existing "leaks" that only matter if nexus is ever
    //     embedded in a long-running process — not the current use case).
    //   - Individual `.free()` / `.deinit()` calls become harmless no-ops.
    //
    // If you ever need to hunt allocation bugs (e.g., before refactoring nexus
    // into a library), swap `init.arena.allocator()` → `init.gpa` below.
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        std.debug.print("Usage: nexus <grammar-file> [output-file]\n", .{});
        std.debug.print("       nexus check <grammar-file>\n", .{});
        std.debug.print("       nexus --help\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        std.debug.print(
            \\nexus — Universal Parser Generator
            \\
            \\Reads a .grammar file with @lexer and @parser sections and generates
            \\a combined parser.zig module containing both lexer and parser.
            \\
            \\Usage: nexus <grammar-file> [output-file]
            \\       nexus check <grammar-file>
            \\       nexus --dump-sexp <grammar-file> [output-file]
            \\
            \\Options:
            \\  -c, --comments  Include grammar-rule comments in generated code
            \\      --slr       Use SLR(1) instead of LALR(1) for parse tables
            \\      --dump-sexp Parse the @parser section via the self-hosted
            \\                  frontend and write its canonical S-expression
            \\                  tree to the output file (or stdout)
            \\  -h, --help      Show this help
            \\
            \\Examples:
            \\  nexus lang.grammar src/parser.zig
            \\  nexus --dump-sexp nexus.grammar test/golden/nexus.sexp
            \\
        , .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--dump-sexp")) {
        if (args.len < 3) {
            std.debug.print("Usage: nexus --dump-sexp <grammar-file> [output-file]\n", .{});
            return;
        }
        const grammarFile = args[2];
        const outputPath: ?[]const u8 = if (args.len >= 4) args[3] else null;

        const sourceText = std.Io.Dir.cwd().readFileAlloc(io, grammarFile, allocator, .limited(max_grammar_bytes)) catch |err| {
            std.debug.print("Error reading {s}: {any}\n", .{ grammarFile, err });
            return err;
        };

        var parsed = parseGrammarSexp(allocator, sourceText) catch |err| {
            std.debug.print("❌ Failed to parse {s}: {any}\n", .{ grammarFile, err });
            if (err == error.ParseError) {
                std.debug.print("  (hint: run `./bin/nexus {s} /tmp/out.zig` for parser-generator diagnostics)\n", .{grammarFile});
            }
            return;
        };
        defer parsed.sexer.deinit();

        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        const writer = &output.writer;
        try dumpSexp(writer, parsed.sexp, parsed.parserBody, 0);
        try writer.writeByte('\n');
        const bytes = writer.buffered();

        if (outputPath) |path| {
            const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
                std.debug.print("Error creating {s}: {any}\n", .{ path, err });
                return err;
            };
            defer file.close(io);
            try file.writeStreamingAll(io, bytes);
            std.debug.print("✅ Wrote S-expression dump to {s} ({d} bytes)\n", .{ path, bytes.len });
        } else {
            std.debug.print("{s}", .{bytes});
        }
        return;
    }

    const checkMode = std.mem.eql(u8, args[1], "check") or std.mem.eql(u8, args[1], "--check");

    // Parse option flags from remaining args
    var comments = false;
    var parseMode: ParseMode = .lalr;
    var positionalStart: usize = if (checkMode) 2 else 1;
    for (args[positionalStart..]) |arg| {
        if (std.mem.eql(u8, arg, "--comments") or std.mem.eql(u8, arg, "-c")) {
            comments = true;
            positionalStart += 1;
        } else if (std.mem.eql(u8, arg, "--slr")) {
            parseMode = .slr;
            positionalStart += 1;
        } else break;
    }

    const grammarFile = if (positionalStart < args.len) args[positionalStart] else {
        std.debug.print("Usage: nexus <grammar-file> [output-file]\n", .{});
        return;
    };
    const outputFile = if (positionalStart + 1 < args.len) args[positionalStart + 1] else "src/parser.zig";

    // Read grammar file
    const sourceText = std.Io.Dir.cwd().readFileAlloc(io, grammarFile, allocator, .limited(max_grammar_bytes)) catch |err| {
        std.debug.print("Error reading {s}: {any}\n", .{ grammarFile, err });
        return err;
    };
    defer allocator.free(sourceText);

    const source = Source.init(allocator, grammarFile, sourceText) catch {
        std.debug.print("Error indexing source for {s}\n", .{grammarFile});
        return;
    };
    defer source.deinit(allocator);

    std.debug.print("📖 Reading grammar from {s}\n", .{grammarFile});

    // Find @lexer section
    const lexerStart = findSection(sourceText, "@lexer");
    if (lexerStart == null) {
        std.debug.print("❌ No @lexer section found in {s}\n", .{grammarFile});
        return;
    }

    // Parse lexer section
    var lexerParser = LexerParser.init(allocator, sourceText[lexerStart.? + 6 ..]);
    defer lexerParser.deinit();

    lexerParser.parseLexerSection() catch |err| {
        std.debug.print("❌ Lexer parse error at line {d}: {any}\n", .{ lexerParser.line, err });
        return;
    };

    std.debug.print("   Lexer: {d} states, {d} tokens, {d} rules\n", .{
        lexerParser.spec.states.items.len,
        lexerParser.spec.tokens.items.len,
        lexerParser.spec.rules.items.len,
    });

    // Pre-scan for @lang directive (needed by lexer generator for @code imports)
    // Matches @lang at start of file or after a newline
    const langPos = findSection(sourceText, "@lang");
    if (langPos) |pos| {
        var i = pos + 5;
        while (i < sourceText.len and (sourceText[i] == ' ' or sourceText[i] == '=' or sourceText[i] == '\t')) : (i += 1) {}
        if (i < sourceText.len and sourceText[i] == '"') {
            i += 1;
            const nameStart = i;
            while (i < sourceText.len and sourceText[i] != '"') : (i += 1) {}
            if (i < sourceText.len) lexerParser.spec.langName = sourceText[nameStart..i];
        }
    }

    // Generate lexer code
    var lexerGen = LexerGenerator.init(allocator, &lexerParser.spec);
    defer lexerGen.deinit();

    const lexerCode = lexerGen.generate() catch |err| {
        std.debug.print("❌ Lexer generation error: {any}\n", .{err});
        return;
    };
    defer allocator.free(lexerCode);

    // Find @parser section
    const parserStart = findSection(sourceText, "@parser");
    if (parserStart == null) {
        std.debug.print("❌ No @parser section found in {s}\n", .{grammarFile});
        return;
    }
    var finalCode: []const u8 = lexerCode;
    var parserGen: ?ParserGenerator = null;

    if (parserStart) |ps| {
        _ = ps;
        std.debug.print("   Parsing @parser section...\n", .{});

        // Parse the @parser section through the self-hosted frontend and
        // lower the resulting S-expression tree into GrammarIR. The lowerer
        // extracts text from .src nodes into slices backed by sourceText
        // (which outlives main), so the sexer's arena is freed as soon as
        // lowering returns.
        var parsed = parseGrammarSexp(allocator, sourceText) catch |err| {
            std.debug.print("❌ Failed to parse @parser section: {any}\n", .{err});
            return;
        };
        defer parsed.sexer.deinit();

        var ir = GrammarLowerer.lower(allocator, parsed.sexp, parsed.parserBody) catch |err| {
            std.debug.print("❌ Lowerer error: {any}\n", .{err});
            return;
        };

        if (ir.lang == null) ir.lang = lexerParser.spec.langName;

        std.debug.print("   Parser: {d} rules, {d} start symbols\n", .{
            ir.rules.len,
            ir.startSymbols.len,
        });

        // Run semantic checks
        if (checkMode) {
            std.debug.print("\n🔍 Checking grammar...\n", .{});
            const checkErrors = checkGrammar(allocator, &ir);
            if (checkErrors > 0) return;
            return;
        }

        // Only generate parser if there are rules
        if (ir.rules.len > 0) {
            parserGen = ParserGenerator.init(allocator);
            parserGen.?.lexerSpec = &lexerParser.spec;
            parserGen.?.emitComments = comments;
            parserGen.?.parseMode = parseMode;

            parserGen.?.processGrammar(&ir) catch |err| {
                std.debug.print("❌ Grammar processing error: {any}\n", .{err});
                return;
            };

            // Validate all referenced symbols are defined
            const validationErrors = parserGen.?.validateSymbols(&lexerParser.spec);
            if (validationErrors > 0) {
                std.debug.print("❌ Found {d} undefined symbol(s)\n", .{validationErrors});
                return;
            }

            parserGen.?.buildAutomaton() catch |err| {
                std.debug.print("❌ Automaton build error: {any}\n", .{err});
                return;
            };

            parserGen.?.computeLookaheads() catch |err| {
                std.debug.print("❌ Lookahead computation error: {any}\n", .{err});
                return;
            };

            std.debug.print("   Generated: {d} symbols, {d} rules, {d} states\n", .{
                parserGen.?.symbols.items.len,
                parserGen.?.rules.items.len,
                parserGen.?.states.items.len,
            });

            // Generate combined code (builds parse table, detects conflicts)
            finalCode = parserGen.?.generateParserCode(lexerCode) catch |err| {
                std.debug.print("❌ Parser generation error: {any}\n", .{err});
                return;
            };

            reportConflicts(&parserGen.?);
        }
    }

    defer if (parserGen) |*pg| {
        pg.deinit();
        if (finalCode.ptr != lexerCode.ptr) {
            allocator.free(finalCode);
        }
    };

    // Write output
    const file = std.Io.Dir.cwd().createFile(io, outputFile, .{}) catch |err| {
        std.debug.print("Error creating {s}: {any}\n", .{ outputFile, err });
        return err;
    };
    defer file.close(io);

    try file.writeStreamingAll(io, finalCode);

    std.debug.print("✅ Generated: {s}\n", .{outputFile});
}
