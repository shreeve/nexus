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

// =============================================================================
// Lexer DSL Data Structures
// =============================================================================

/// State variable declaration
const StateVar = struct {
    name: []const u8,
    initial_value: i32,
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
        simd_to, // simd_to 'x'
    };
};

/// Lexer rule
const LexerRule = struct {
    pattern: []const u8,
    guards: []const Guard,
    token: []const u8,
    actions: []const Action,
    is_simd: bool = false,
    simd_char: ?u8 = null,
    is_skip: bool = false,
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
    code_functions: std.ArrayListUnmanaged([]const u8),
    lang_name: ?[]const u8 = null,

    fn init(allocator: Allocator) LexerSpec {
        return .{
            .allocator = allocator,
            .states = .{},
            .defaults = .{},
            .tokens = .{},
            .rules = .{},
            .code_functions = .{},
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
        self.code_functions.deinit(self.allocator);
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
            if (self.source[p] == '\n') { p += 1; continue; }
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
        if (self.pos < self.source.len) { self.line += 1; self.pos += 1; }
    }

    /// Skip blank lines and comment-only lines at column 0.
    fn skipBlankLines(self: *LexerParser) void {
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') { self.line += 1; self.pos += 1; continue; }
            if (self.source[self.pos] == '#') { self.skipToNextLine(); continue; }
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
                try self.spec.code_functions.append(self.spec.allocator, name);
                continue;
            }

            // Parse lexer rule (starts with pattern, including empty-pattern @ guards)
            if (self.peek() == '\'' or self.peek() == '"' or self.peek() == '[' or self.peek() == '.' or self.peek() == '@') {
                try self.parseLexerRule();
                continue;
            }

            // Skip unknown lines
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
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

        try self.spec.states.append(self.allocator, .{ .name = name, .initial_value = value });
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
        var guards: std.ArrayListUnmanaged(Guard) = .{};
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
        var actions: std.ArrayListUnmanaged(Action) = .{};
        defer actions.deinit(self.allocator);

        var is_simd = false;
        var simd_char: ?u8 = null;
        var is_skip = false;

        self.skipWhitespace();
        while (self.expect(',')) {
            self.skipWhitespace();

            if (self.expectStr("simd_to")) {
                is_simd = true;
                self.skipWhitespace();
                if (!self.expect('\'')) return error.ExpectedQuote;
                simd_char = self.parseEscapedChar();
                if (!self.expect('\'')) return error.ExpectedQuote;
                continue;
            }

            if (self.expectStr("skip")) {
                is_skip = true;
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
            .is_simd = is_simd,
            .simd_char = simd_char,
            .is_skip = is_skip,
        });
    }

    fn parsePattern(self: *LexerParser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;

        // Scan until we hit unquoted @ or => or end of line
        var in_single_quote = false;
        var in_double_quote = false;
        var in_bracket = false;
        var paren_depth: u32 = 0;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\n') break;

            // Track quote/bracket/paren state
            if (!in_single_quote and !in_double_quote and !in_bracket) {
                if (c == '\'') {
                    in_single_quote = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '"') {
                    in_double_quote = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '[') {
                    in_bracket = true;
                    self.pos += 1;
                    continue;
                }
                if (c == '(') {
                    paren_depth += 1;
                    self.pos += 1;
                    continue;
                }
                if (c == ')' and paren_depth > 0) {
                    paren_depth -= 1;
                    self.pos += 1;
                    continue;
                }
            }

            // Handle closing quotes/brackets
            if (in_single_quote and c == '\'') {
                in_single_quote = false;
                self.pos += 1;
                continue;
            }
            if (in_double_quote and c == '"') {
                in_double_quote = false;
                self.pos += 1;
                continue;
            }
            if (in_bracket and c == ']') {
                in_bracket = false;
                self.pos += 1;
                continue;
            }

            // Only check for @ and arrows when not inside quotes/brackets/parens
            if (!in_single_quote and !in_double_quote and !in_bracket and paren_depth == 0) {
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
    var guarded_match: ?[]const u8 = null;
    for (spec.rules.items) |rule| {
        if (rule.is_skip) continue;

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
                    if (guarded_match == null) guarded_match = rule.token;
                }
            }
        }

        // Double-quoted single char: "X" (used when the char itself is a quote)
        if (rule.pattern.len == 3 and rule.pattern[0] == '"' and rule.pattern[2] == '"') {
            if (rule.pattern[1] == ch) {
                if (rule.guards.len == 0) return rule.token;
                if (guarded_match == null) guarded_match = rule.token;
            }
        }
    }
    return guarded_match;
}

fn findTokenForLiteral(spec: *const LexerSpec, literal: []const u8) ?[]const u8 {
    for (spec.rules.items) |rule| {
        if (rule.is_skip) continue;
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
    output: std.ArrayListUnmanaged(u8),

    fn structName(self: *const LexerGenerator) []const u8 {
        return if (self.spec.lang_name != null) "BaseLexer" else "Lexer";
    }

    fn init(allocator: Allocator, spec: *const LexerSpec) LexerGenerator {
        return .{
            .allocator = allocator,
            .spec = spec,
            .output = .{},
        };
    }

    fn deinit(self: *LexerGenerator) void {
        self.output.deinit(self.allocator);
    }

    fn write(self: *LexerGenerator, s: []const u8) !void {
        try self.output.appendSlice(self.allocator, s);
    }

    fn print(self: *LexerGenerator, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(s);
        try self.output.appendSlice(self.allocator, s);
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
        const is_pre = std.mem.eql(u8, guard.variable, "pre");
        const lhs = if (is_pre) "wsCount" else guard.variable;
        const prefix = if (is_pre) "" else "self.";

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

    fn emitTokenReturn(self: *LexerGenerator, keyword: []const u8, token: []const u8, char_count: u8) !void {
        try self.print("                    {s} Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ keyword, token, char_count });
    }

    /// Find the state variable that complex rules set for a given character.
    /// Used to determine which state variable an @code function affects.
    fn findCodeFnStateVar(self: *LexerGenerator, first_char: u8) ?[]const u8 {
        for (self.spec.rules.items) |rule| {
            if (parseLiteralPattern(rule.pattern) != null) continue;
            if (rule.pattern.len == 0) continue;
            var starts_with: ?u8 = null;
            if (rule.pattern.len >= 3 and (rule.pattern[0] == '\'' or rule.pattern[0] == '"')) {
                starts_with = rule.pattern[1];
            }
            if (starts_with) |sw| {
                if (sw != first_char) continue;
            } else continue;
            for (rule.actions) |action| {
                if (action.kind == .set and action.variable != null) return action.variable;
            }
        }
        return null;
    }

    const OpRule = struct {
        chars: [8]u8,
        char_count: u8,
        token: []const u8,
        guards: []const Guard,
        actions: []const Action,
    };

    fn generateOperatorSwitch(self: *LexerGenerator) !void {
        var groups: [256]std.ArrayListUnmanaged(OpRule) = @splat(.{});
        defer for (&groups) |*g| g.deinit(self.allocator);

        // Build set of characters that start string literal patterns
        // (these are handled by the string scanner, not the operator switch)
        var string_start_chars: [256]bool = @splat(false);
        for (self.spec.rules.items) |rule| {
            const is_string_tok = std.mem.startsWith(u8, rule.token, "string");
            if (!is_string_tok) continue;
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len >= 3) {
                const delim = rule.pattern[0];
                if (delim == '\'' or delim == '"') {
                    string_start_chars[rule.pattern[1]] = true;
                }
            }
        }

        // Find the comment start character from the grammar
        var comment_start_char: u8 = 0;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "comment")) {
                const info = parseLiteralPattern(rule.pattern) orelse continue;
                if (info.len > 0) comment_start_char = info.chars[0];
                break;
            }
        }

        for (self.spec.rules.items) |rule| {
            const info = parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len == 0) continue;
            const fc = info.chars[0];
            if (fc == '\n' or fc == '\r') continue;
            if (fc == comment_start_char) continue;
            if (string_start_chars[fc]) continue;

            try groups[fc].append(self.allocator, .{
                .chars = info.chars,
                .char_count = info.len,
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

    fn emitSwitchArm(self: *LexerGenerator, first_char: u8, rules: []const OpRule, code_fn: ?[]const u8) !void {
        var single_rules = std.ArrayListUnmanaged(OpRule){};
        defer single_rules.deinit(self.allocator);
        var multi_rules = std.ArrayListUnmanaged(OpRule){};
        defer multi_rules.deinit(self.allocator);

        for (rules) |rule| {
            if (rule.char_count > 1)
                try multi_rules.append(self.allocator, rule)
            else
                try single_rules.append(self.allocator, rule);
        }

        const lit = charToZigLiteral(first_char);
        const lit_str = lit.buf[0..lit.len];

        const has_guards = blk: {
            for (single_rules.items) |r| if (r.guards.len > 0) break :blk true;
            break :blk false;
        };
        const has_actions = blk: {
            for (single_rules.items) |r| if (r.actions.len > 0) break :blk true;
            break :blk false;
        };
        const needs_blk = multi_rules.items.len > 0 or has_guards or has_actions;

        if (!needs_blk) {
            const r = single_rules.items[0];
            try self.print("            '{s}' => Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ lit_str, r.token });
            return;
        }

        // Pre-guard shortcut: two rules for same char differing only by pre guard,
        // both producing single-char tokens with no actions.
        // Skip shortcut if pattern-exit logic is needed (requires a block).
        if (multi_rules.items.len == 0 and single_rules.items.len == 2 and !has_actions) {
            var guarded: ?[]const u8 = null;
            var default: ?[]const u8 = null;
            for (single_rules.items) |r| {
                if (r.guards.len > 0) {
                    var is_pre = false;
                    for (r.guards) |g| {
                        if (std.mem.eql(u8, g.variable, "pre") and !g.negated and
                            (g.op == .truthy or (g.op == .gt and g.value == 0)))
                            is_pre = true;
                    }
                    if (is_pre) guarded = r.token;
                } else {
                    default = r.token;
                }
            }
            if (guarded != null and default != null) {
                try self.print("            '{s}' => Token{{ .cat = if (wsCount > 0) .@\"{s}\" else .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ lit_str, guarded.?, default.? });
                return;
            }
        }

        try self.print("            '{s}' => blk: {{\n", .{lit_str});

        // Multi-char rules: group by second char, longest first
        if (multi_rules.items.len > 0) {
            try self.emitMultiCharPeekAhead(multi_rules.items, 1, code_fn);
        }

        // Single-char rules with guards
        try self.emitGuardedSingleCharRules(single_rules.items);

        // If multi-char rules exist but no unguarded single-char fallback,
        // the blk: may not return. Add a fallback: rewind pos and route to
        // the appropriate scanner, or emit an error token.
        // Skip if guarded rules form an exhaustive chain (2+ guards, no unguarded).
        if (multi_rules.items.len > 0) {
            const has_unguarded = blk: {
                for (single_rules.items) |r| {
                    if (r.guards.len == 0) break :blk true;
                }
                break :blk false;
            };
            var guarded_count: usize = 0;
            for (single_rules.items) |r| {
                if (r.guards.len > 0) guarded_count += 1;
            }
            const exhaustive = !has_unguarded and guarded_count >= 2;
            if (!has_unguarded and !exhaustive) {
                // Determine fallback based on what this character starts
                const is_string_start = (first_char == '\'' or first_char == '"');
                const is_digit = (first_char >= '0' and first_char <= '9');

                try self.write("                self.pos -= 1;\n");
                if (is_string_start) {
                    try self.write("                break :blk self.scanString(start, wsCount);\n");
                } else if (is_digit) {
                    try self.write("                break :blk self.scanNumber(start, wsCount);\n");
                } else {
                    try self.write("                break :blk Token{ .cat = .@\"err\", .pre = wsCount, .pos = start, .len = 1 };\n");
                }
            }
        }

        try self.write("            },\n");
    }

    fn emitMultiCharPeekAhead(self: *LexerGenerator, rules: []const OpRule, depth: u8, code_fn: ?[]const u8) !void {
        const base_indent = "                ";
        var indent_buf: [64]u8 = undefined;
        const extra: usize = (@as(usize, depth) - 1) * 4;
        const indent = blk: {
            @memset(&indent_buf, ' ');
            break :blk indent_buf[0 .. base_indent.len + extra];
        };

        var seen_second: [256]bool = @splat(false);
        var second_chars: [256]u8 = undefined;
        var second_count: usize = 0;

        for (rules) |r| {
            if (r.char_count <= depth) continue;
            const sc = r.chars[depth];
            if (!seen_second[sc]) {
                seen_second[sc] = true;
                second_chars[second_count] = sc;
                second_count += 1;
            }
        }

        for (second_chars[0..second_count]) |sc| {
            var matching = std.ArrayListUnmanaged(OpRule){};
            defer matching.deinit(self.allocator);
            for (rules) |r| {
                if (r.char_count > depth and r.chars[depth] == sc)
                    try matching.append(self.allocator, r);
            }

            const sc_lit = charToZigLiteral(sc);
            const sc_str = sc_lit.buf[0..sc_lit.len];

            // Check if ALL matching rules share the same guard
            const all_same_guard = blk: {
                if (matching.items.len == 0) break :blk false;
                const first_guards = matching.items[0].guards;
                for (matching.items[1..]) |r| {
                    if (r.guards.len != first_guards.len) break :blk false;
                }
                break :blk first_guards.len > 0;
            };

            if (all_same_guard) {
                try self.write(indent);
                try self.write("if (");
                try self.emitAllGuards(matching.items[0].guards);
                try self.print(" and self.peek() == '{s}') {{\n", .{sc_str});
            } else {
                try self.write(indent);
                try self.print("if (self.peek() == '{s}') {{\n", .{sc_str});
            }
            try self.write(indent);
            try self.write("    self.pos += 1;\n");

            // Check for deeper (3-char) rules
            var has_deeper = false;
            for (matching.items) |r| {
                if (r.char_count > depth + 1) {
                    has_deeper = true;
                    break;
                }
            }
            if (has_deeper) {
                try self.emitMultiCharPeekAhead(matching.items, depth + 1, code_fn);
            }

            // Emit terminating rules at this depth
            var terminated = false;
            for (matching.items) |r| {
                if (r.char_count == depth + 1) {
                    if (!all_same_guard and r.guards.len > 0) {
                        try self.write(indent);
                        try self.write("    if (");
                        try self.emitAllGuards(r.guards);
                        try self.write(") {\n");
                        try self.emitActions(r.actions, indent);
                        try self.emitTokenReturn("break :blk", r.token, r.char_count);
                        try self.write(indent);
                        try self.write("    }\n");
                    } else if (!terminated) {
                        try self.emitActions(r.actions, indent);
                        try self.emitTokenReturn("break :blk", r.token, r.char_count);
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
        var guarded = std.ArrayListUnmanaged(OpRule){};
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
            const is_last = (i == guarded.items.len - 1);
            if (i == 0) {
                try self.write("                if (");
                try self.emitAllGuards(r.guards);
                try self.write(") {\n");
            } else if (is_last and unguarded == null) {
                try self.write(" else {\n");
            } else {
                try self.write(" else if (");
                try self.emitAllGuards(r.guards);
                try self.write(") {\n");
            }
            try self.emitActions(r.actions, "                    ");
            try self.emitTokenReturn("break :blk", r.token, r.char_count);
            try self.write("                }");
        }

        // Emit unguarded fallback
        if (unguarded) |r| {
            if (guarded.items.len > 0) {
                try self.write("\n");
            }
            try self.emitActions(r.actions, "                ");
            try self.emitTokenReturn("break :blk", r.token, r.char_count);
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
        var has_any = false;
        for (self.spec.rules.items) |rule| {
            if (rule.pattern.len > 0) continue;
            if (rule.guards.len == 0) continue;
            has_any = true;
            break;
        }
        if (!has_any) return;

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
            char_count: u8,
            token: []const u8,
            guards: []const Guard,
            actions: []const Action,
        };

        var crlf_rules = std.ArrayListUnmanaged(NlRule){};
        defer crlf_rules.deinit(self.allocator);
        var lf_rules = std.ArrayListUnmanaged(NlRule){};
        defer lf_rules.deinit(self.allocator);
        var cr_rules = std.ArrayListUnmanaged(NlRule){};
        defer cr_rules.deinit(self.allocator);

        for (self.spec.rules.items) |rule| {
            const info = parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len == 2 and info.chars[0] == '\r' and info.chars[1] == '\n') {
                try crlf_rules.append(self.allocator, .{
                    .chars = .{ '\r', '\n' },
                    .char_count = 2,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            } else if (info.len == 1 and info.chars[0] == '\n') {
                try lf_rules.append(self.allocator, .{
                    .chars = .{ '\n', 0 },
                    .char_count = 1,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            } else if (info.len == 1 and info.chars[0] == '\r') {
                try cr_rules.append(self.allocator, .{
                    .chars = .{ '\r', 0 },
                    .char_count = 1,
                    .token = rule.token,
                    .guards = rule.guards,
                    .actions = rule.actions,
                });
            }
        }

        if (lf_rules.items.len == 0 and cr_rules.items.len == 0) return;

        try self.write(
            \\        // Newline handling (generated from grammar rules)
            \\        if (c == '\n' or c == '\r') {
            \\
        );

        // CRLF check first (longest match)
        if (crlf_rules.items.len > 0) {
            try self.write("            if (c == '\\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\\n') {\n");
            try self.emitNewlineRules(crlf_rules.items, 2);
            try self.write("            }\n");
        }

        // Single-char newline rules (\n and standalone \r)
        // After CRLF is excluded, \n and \r have identical handling — use \n rules
        const single_rules = if (lf_rules.items.len > 0) lf_rules.items else cr_rules.items;
        if (single_rules.len > 0) {
            try self.emitNewlineRules(single_rules, 1);
        }

        try self.write(
            \\        }
            \\
        );
    }

    fn emitNewlineRules(self: *LexerGenerator, rules: anytype, char_count: u8) !void {
        var guarded = std.ArrayListUnmanaged(@TypeOf(rules[0])){};
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
        if (char_count == 2) {
            try self.write("                self.pos += 2;\n");
        } else {
            try self.write("                self.pos += 1;\n");
        }

        for (guarded.items) |r| {
            try self.write("                if (");
            try self.emitAllGuards(r.guards);
            try self.write(") {\n");
            try self.emitActions(r.actions, "                    ");
            try self.print("                    return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, char_count });
            try self.write("                }\n");
        }

        if (unguarded) |r| {
            try self.emitActions(r.actions, "                ");
            try self.print("                return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, char_count });
        }
    }

    fn parseCharClass(pattern: []const u8) ?struct { chars: [256]bool, end_pos: usize } {
        if (pattern.len == 0 or pattern[0] != '[') return null;
        var chars: [256]bool = @splat(false);
        var i: usize = 1;
        if (i < pattern.len and pattern[i] == '^') i += 1;
        while (i < pattern.len and pattern[i] != ']') {
            if (i + 2 < pattern.len and pattern[i + 1] == '-') {
                var c: u16 = pattern[i];
                while (c <= pattern[i + 2]) : (c += 1) chars[@intCast(c)] = true;
                i += 3;
            } else {
                chars[pattern[i]] = true;
                i += 1;
            }
        }
        if (i < pattern.len and pattern[i] == ']') return .{ .chars = chars, .end_pos = i + 1 };
        return null;
    }

    fn generateCharClassification(self: *LexerGenerator) !void {
        // Derive LETTER and DIGIT sets from grammar patterns
        var letter_chars: [256]bool = @splat(false);
        var digit_chars: [256]bool = @splat(false);

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;

            if (std.mem.eql(u8, rule.token, "ident")) {
                if (parseCharClass(rule.pattern)) |cc| {
                    for (0..256) |c| {
                        if (cc.chars[c]) letter_chars[c] = true;
                    }
                }
            } else if (std.mem.eql(u8, rule.token, "integer")) {
                if (parseCharClass(rule.pattern)) |cc| {
                    for (0..256) |c| {
                        if (cc.chars[c]) digit_chars[c] = true;
                    }
                }
            }
        }

        // Emit the char_flags table
        try self.write(
            \\    // Character classification flags (generated from grammar patterns)
            \\    const DIGIT: u8 = 1 << 0;
            \\    const LETTER: u8 = 1 << 1;
            \\    const WHITESPACE: u8 = 1 << 2;
            \\
            \\    const charFlags: [256]u8 = blk: {
            \\        var table: [256]u8 = [_]u8{0} ** 256;
            \\
        );

        // Emit DIGIT entries
        var has_digit_range = true;
        for ('0'..('9' + 1)) |c| {
            if (!digit_chars[c]) {
                has_digit_range = false;
                break;
            }
        }
        if (has_digit_range) {
            try self.write("        for ('0'..'9' + 1) |c| table[c] = DIGIT;\n");
        } else {
            for (0..256) |c| {
                if (digit_chars[c]) {
                    const lit = charToZigLiteral(@intCast(c));
                    try self.print("        table['{s}'] = DIGIT;\n", .{lit.buf[0..lit.len]});
                }
            }
        }

        // Emit LETTER entries — check for standard ranges first
        var has_upper = true;
        var has_lower = true;
        for ('A'..('Z' + 1)) |c| {
            if (!letter_chars[c]) {
                has_upper = false;
                break;
            }
        }
        for ('a'..('z' + 1)) |c| {
            if (!letter_chars[c]) {
                has_lower = false;
                break;
            }
        }

        if (has_upper) try self.write("        for ('A'..'Z' + 1) |c| table[c] = LETTER;\n");
        if (has_lower) try self.write("        for ('a'..'z' + 1) |c| table[c] = LETTER;\n");

        // Emit individual LETTER chars outside standard ranges
        for (0..256) |c| {
            if (!letter_chars[c]) continue;
            if (has_upper and c >= 'A' and c <= 'Z') continue;
            if (has_lower and c >= 'a' and c <= 'z') continue;
            const lit = charToZigLiteral(@intCast(c));
            try self.print("        table['{s}'] = LETTER;\n", .{lit.buf[0..lit.len]});
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
            \\    inline fn isIdentChar(c: u8) bool {
            \\        return isLetter(c) or isDigit(c);
            \\    }
            \\
        );
    }

    fn generateScannerDispatch(self: *LexerGenerator) !void {
        // Derive dispatch conditions from grammar patterns
        var has_number = false;
        var number_has_leading_dot = false;
        var has_ident = false;

        // Collect string patterns (heredocs are handled by the language wrapper, not the engine)
        const StringInfo = struct { open_char: u8, token: []const u8 };
        var string_infos: [4]StringInfo = undefined;
        var string_info_count: usize = 0;

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;

            const is_string_tok = std.mem.eql(u8, rule.token, "string") or
                std.mem.startsWith(u8, rule.token, "string_");
            if (is_string_tok) {
                if (rule.pattern.len >= 3 and (rule.pattern[0] == '\'' or rule.pattern[0] == '"')) {
                    const delim = rule.pattern[0];
                    if (rule.pattern[1] != delim) {
                        if (string_info_count < string_infos.len) {
                            string_infos[string_info_count] = .{
                                .open_char = rule.pattern[1],
                                .token = rule.token,
                            };
                            string_info_count += 1;
                        }
                    }
                }
            }
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real"))
            {
                has_number = true;
                if (std.mem.indexOf(u8, rule.pattern, "'.'") != null and
                    rule.pattern.len > 0 and rule.pattern[0] == '[')
                {
                    const cc = parseCharClass(rule.pattern);
                    if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.end_pos..], "* '.'"))
                        number_has_leading_dot = true;
                }
            }
            if (std.mem.eql(u8, rule.token, "ident") and rule.pattern.len > 0 and rule.pattern[0] == '[') {
                has_ident = true;
            }
        }

        // String token types
        for (string_infos[0..string_info_count]) |si| {
            const lit = charToZigLiteral(si.open_char);
            const lit_str = lit.buf[0..lit.len];

            try self.print(
                \\        if (c == '{s}') {{
            , .{lit_str});

            // Detect escape mechanism from the grammar pattern
            const is_sq = (si.open_char == '\'');
            if (is_sq) {
                // Single-quote: '' escape, stop on \n
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
                , .{ lit_str, lit_str, si.token });
            } else {
                // Double-quote: backslash escape, stop on \n
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
                , .{ lit_str, si.token });
            }
        }

        if (has_number) {
            if (number_has_leading_dot) {
                try self.write(
                    \\        // Number (digit or leading dot followed by digit)
                    \\        if (isDigit(c) or (c == '.' and self.pos + 1 < self.source.len and isDigit(self.source[self.pos + 1]))) {
                    \\            return self.scanNumber(start, wsCount);
                    \\        }
                    \\
                );
            } else {
                try self.write(
                    \\        // Number
                    \\        if (isDigit(c)) {
                    \\            return self.scanNumber(start, wsCount);
                    \\        }
                    \\
                );
            }
        }

        if (has_ident) {
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

    fn generatePrefixScanners(self: *LexerGenerator) !void {
        // Find rules like: '$' [a-zA-Z_]... → variable, '$' '{' ... → var_braced
        // Group by prefix character
        var emitted_prefixes: [256]bool = @splat(false);

        for (self.spec.rules.items) |rule| {
            if (rule.guards.len > 0) continue;
            if (rule.pattern.len < 5) continue;

            // Match pattern: 'X' followed by character class or literal
            if (rule.pattern[0] != '\'') continue;
            if (rule.pattern[2] != '\'') continue;
            const prefix_char = rule.pattern[1];

            // Skip if this prefix is handled by string/number/ident/comment scanners
            if (prefix_char == '"' or prefix_char == '\'') continue;
            if (prefix_char >= '0' and prefix_char <= '9') continue;
            if ((prefix_char >= 'a' and prefix_char <= 'z') or
                (prefix_char >= 'A' and prefix_char <= 'Z') or prefix_char == '_' or prefix_char == '%') continue;
            // Skip comment start chars and flag chars (handled elsewhere)
            if (std.mem.eql(u8, rule.token, "comment")) continue;
            if (std.mem.eql(u8, rule.token, "skip")) continue;

            // Must have a 2nd part that's a character class or literal (not just [^\n]*)
            const rest = rule.pattern[3..];
            const trimmed = std.mem.trimLeft(u8, rest, " ");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '[' and trimmed.len > 1 and trimmed[1] == '^') continue; // negated class like [^\n]

            if (emitted_prefixes[prefix_char]) continue;

            // Collect all rules with this prefix
            const PrefixRule = struct { pattern: []const u8, token: []const u8, actions: []const Action };
            var prefix_rules: [32]PrefixRule = undefined;
            var prefix_count: usize = 0;

            for (self.spec.rules.items) |r| {
                if (r.guards.len > 0) continue;
                if (r.pattern.len < 5) continue;
                if (r.pattern[0] != '\'' or r.pattern[2] != '\'') continue;
                if (r.pattern[1] != prefix_char) continue;
                if (prefix_count < prefix_rules.len) {
                    prefix_rules[prefix_count] = .{ .pattern = r.pattern, .token = r.token, .actions = r.actions };
                    prefix_count += 1;
                }
            }

            if (prefix_count == 0) continue;
            emitted_prefixes[prefix_char] = true;

            const lit = charToZigLiteral(prefix_char);
            const lit_str = lit.buf[0..lit.len];

            try self.print("        if (c == '{s}') {{\n", .{lit_str});
            try self.write("            const nc = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;\n");

            // Sort rules: longer patterns first for priority (literal sequences before classes)
            // Emit checks for each rule's second character condition
            for (prefix_rules[0..prefix_count]) |pr| {
                // Parse what follows the prefix literal in the pattern
                const pr_rest = pr.pattern[3..]; // after 'X'
                const pr_trimmed = std.mem.trimLeft(u8, pr_rest, " ");

                if (pr_trimmed.len >= 3 and pr_trimmed[0] == '\'') {
                    // Second literal: '$' '{' → scan until matching close
                    const second_char = pr_trimmed[1];
                    const sc_lit = charToZigLiteral(second_char);
                    const sc_str = sc_lit.buf[0..sc_lit.len];

                    // Find the closing delimiter
                    if (std.mem.indexOf(u8, pr_trimmed[3..], "'")) |close_idx| {
                        const end_pattern = pr_trimmed[3..][0..close_idx];
                        if (end_pattern.len >= 3 and end_pattern[0] == ' ' and end_pattern[1] == '[' and end_pattern[2] == '^') {
                            // Pattern: '$' '{' [^}\n]+ '}' → scan to closing char
                            if (std.mem.indexOf(u8, end_pattern[3..], "]") == null) continue;
                            // Find the close delimiter from the end of the pattern
                            if (std.mem.lastIndexOf(u8, pr.pattern, "'")) |li| {
                                if (li > 3) {
                                    const close_ch = pr.pattern[li - 1];
                                    const cl_lit = charToZigLiteral(close_ch);
                                    const cl_str = cl_lit.buf[0..cl_lit.len];
                                    try self.print(
                                        \\            if (nc == '{s}') {{
                                        \\                self.pos += 2;
                                        \\                while (self.pos < self.source.len and self.source[self.pos] != '{s}' and self.source[self.pos] != '\n') self.pos += 1;
                                        \\                if (self.pos < self.source.len and self.source[self.pos] == '{s}') self.pos += 1;
                                        \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                                        \\            }}
                                        \\
                                    , .{ sc_str, cl_str, cl_str, pr.token });
                                }
                            }
                        }
                    }
                } else if (pr_trimmed.len >= 1 and pr_trimmed[0] == '[') {
                    // Character class: '$' [a-zA-Z_] → scan identifier-like
                    // Check what chars are in the class
                    const has_alpha = std.mem.indexOf(u8, pr_trimmed, "a-z") != null or
                        std.mem.indexOf(u8, pr_trimmed, "A-Z") != null;
                    const has_digit = std.mem.indexOf(u8, pr_trimmed, "0-9") != null;
                    const has_special = std.mem.indexOf(u8, pr_trimmed, "?$!#*") != null;

                    if (has_alpha) {
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
                    } else if (has_digit) {
                        // $0-$9 pattern
                        try self.print(
                            \\            if (nc >= '0' and nc <= '9') {{
                            \\                self.pos += 2;
                            \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = 2 }};
                            \\            }}
                            \\
                        , .{pr.token});
                    } else if (has_special) {
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
        var has_decimal = false;
        var has_exponent = false;
        var has_leading_dot = false;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "real")) {
                if (std.mem.indexOf(u8, rule.pattern, "'.'") != null) has_decimal = true;
                if (std.mem.indexOf(u8, rule.pattern, "[Ee]") != null) has_exponent = true;
                if (rule.pattern.len > 0 and rule.pattern[0] == '[') {
                    const cc = parseCharClass(rule.pattern);
                    if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.end_pos..], "* '.'"))
                        has_leading_dot = true;
                }
            }
        }

        // Check if any number patterns exist
        var has_any = false;
        for (self.spec.rules.items) |rule| {
            if (std.mem.eql(u8, rule.token, "integer") or
                std.mem.eql(u8, rule.token, "real"))
            {
                has_any = true;
                break;
            }
        }
        if (!has_any) return;

        try self.write(
            \\
            \\    /// Scan number (generated from grammar)
            \\    fn scanNumber(self: *Self, start: u32, ws: u8) Token {
        );

        if (has_decimal) {
            try self.write(
                \\        var hasDecimal = false;
            );
        }
        if (has_exponent) {
            try self.write(
                \\        var hasExponent = false;
            );
        }
        if (has_leading_dot) {
            try self.write(
                \\        const startsWithDot = self.source[self.pos] == '.';
            );
        }

        // Check for grammar-defined number prefix patterns (e.g., 0x hex, 0b binary, 0o octal)
        const has_prefixed = self.hasNumberPrefixPatterns();
        if (has_prefixed) {
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
        if (has_decimal) {
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
        if (has_exponent) {
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
        if (has_decimal or has_exponent or has_leading_dot) {
            try self.write("        // Classify\n");
            try self.write("        const tokenCat: TokenCat = ");

            if (has_decimal or has_exponent or has_leading_dot) {
                try self.write("if (");
                var first_cond = true;
                if (has_decimal) {
                    try self.write("hasDecimal");
                    first_cond = false;
                }
                if (has_exponent) {
                    if (!first_cond) try self.write(" or ");
                    try self.write("hasExponent");
                    first_cond = false;
                }
                if (has_leading_dot) {
                    if (!first_cond) try self.write(" or ");
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
            const rest = std.mem.trimLeft(u8, rule.pattern[3..], " ");
            if (rest.len < 3 or rest[0] != '[') continue;
            const close = std.mem.indexOfScalar(u8, rest, ']') orelse continue;
            const char_class = rest[1..close];
            const digit_part = std.mem.trimLeft(u8, rest[close + 1 ..], " ");

            // Build condition for prefix char
            if (!first) {
                try self.write("            else ");
            } else {
                try self.write("            ");
                first = false;
            }
            try self.write("if (");
            var first_cond = true;
            var i: usize = 0;
            while (i < char_class.len) {
                if (!first_cond) try self.write(" or ");
                first_cond = false;
                try self.print("prefix == '{c}'", .{char_class[i]});
                i += 1;
            }
            try self.write(") {\n");
            try self.write("                self.pos += 2;\n");

            // Build digit scanning loop from the digit class pattern
            if (digit_part.len > 0 and digit_part[0] == '[') {
                const dclose = std.mem.indexOfScalar(u8, digit_part, ']') orelse continue;
                const dclass = digit_part[1..dclose];
                try self.write("                while (self.pos < self.source.len) {\n");
                try self.write("                    const dc = self.source[self.pos];\n");
                try self.write("                    if (");
                // Parse ranges in digit class
                var di: usize = 0;
                var first_dc = true;
                while (di < dclass.len) {
                    if (di + 2 < dclass.len and dclass[di + 1] == '-') {
                        if (!first_dc) try self.write(" or ");
                        first_dc = false;
                        try self.print("(dc >= '{c}' and dc <= '{c}')", .{ dclass[di], dclass[di + 2] });
                        di += 3;
                    } else {
                        if (!first_dc) try self.write(" or ");
                        first_dc = false;
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
        try self.write(
            \\
            \\    /// Scan identifier (generated from grammar)
            \\    fn scanIdent(self: *Self, start: u32, ws: u8) Token {
            \\        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
            \\            self.pos += 1;
            \\        }
            \\        return Token{ .cat = .@"ident", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
            \\    }
            \\
        );
    }

    fn generateCommentHandling(self: *LexerGenerator) !void {
        for (self.spec.rules.items) |rule| {
            if (!std.mem.eql(u8, rule.token, "comment")) continue;

            // Extract the leading literal char from the pattern (e.g., ';' or '#')
            const start_char = blk: {
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

            const start_lit = charToZigLiteral(start_char);
            const start_str = start_lit.buf[0..start_lit.len];

            if (rule.is_simd and rule.simd_char != null) {
                const stop_lit = charToZigLiteral(rule.simd_char.?);
                const stop_str = stop_lit.buf[0..stop_lit.len];

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
                , .{ start_str, stop_str, rule.token });
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
                , .{ start_str, rule.token });
            }
        }
    }

    fn generate(self: *LexerGenerator) ![]const u8 {
        // Header
        try self.write(
            \\//! Parser (Auto-generated)
            \\//!
            \\//! Generated by nexus from a .grammar file.
            \\//! Contains both lexer and parser.
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

        return self.output.toOwnedSlice(self.allocator);
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
        const sname = if (self.spec.lang_name != null) "BaseLexer" else "Lexer";

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

        // State variables
        try self.write("    // State variables\n");
        for (self.spec.states.items) |state| {
            try self.print("    {s}: i32,\n", .{state.name});
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
            try self.print("            .{s} = {d},\n", .{ state.name, state.initial_value });
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
            try self.print("        self.{s} = {d};\n", .{ state.name, state.initial_value });
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
        if (self.spec.lang_name) |lang| {
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
        for (self.spec.code_functions.items) |func_name| {
            if (self.spec.lang_name) |lang| {
                const state_var = self.findCodeFnStateVar('?') orelse "pat";
                try self.print(
                    \\    fn {s}(self: *Self) void {{
                    \\        if ({s}.{s}(self.source, self.pos)) self.{s} = 1;
                    \\    }}
                    \\
                , .{ func_name, lang, func_name, state_var });
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
            \\        var wsCount: u8 = @intCast(@min(self.pos - wsStart, 255));
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

        const has_beg_state = for (self.spec.states.items) |s| {
            if (std.mem.eql(u8, s.name, "beg")) break true;
        } else false;
        if (has_beg_state) {
            try self.write(
                \\        // From here, clear line-start flag
                \\        self.beg = 0;
                \\
            );
        }

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
const ParserSymbol = struct {
    id: u16,
    name: []const u8,
    kind: Kind,

    // For nonterminals only
    nullable: bool = false,
    firsts: ParserSymbolSet = .{},
    follows: ParserSymbolSet = .{},
    rules: std.ArrayListUnmanaged(u16) = .{}, // Rule IDs that define this nonterminal

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
    items: std.ArrayListUnmanaged(u16) = .{},

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
        const old_count = self.items.items.len;
        for (other.items.items) |id| {
            try self.add(allocator, id);
        }
        return self.items.items.len > old_count;
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
    action_offset: u8 = 0, // Position offset for start rules with marker tokens
    nullable: bool = false,
    firsts: ParserSymbolSet = .{},
    exclude_char: u8 = 0, // X "c" - exclude rule when next char matches
    prefer_reduce: bool = false, // < hint - prefer reduce on S/R conflict
    prefer_shift: bool = false, // > hint - prefer shift on S/R conflict

    const ParserAction = struct {
        template: []const u8, // Original action string like (set 2? ...3)
        kind: Kind,

        const Kind = enum { sexp, passthrough, nil, spread };
    };
};

/// LR Item: rule with dot position (A → α • β)
const ParserItem = struct {
    rule_id: u16,
    dot: u8,

    fn id(self: ParserItem) u32 {
        return (@as(u32, self.rule_id) << 8) | self.dot;
    }

    fn eql(a: ParserItem, b: ParserItem) bool {
        return a.rule_id == b.rule_id and a.dot == b.dot;
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

/// Parsed rule from grammar
const ParsedRule = struct {
    name: []const u8,
    is_start: bool,
    alternatives: []const ParsedAlternative,
};

/// Parsed alternative within a rule
const ParsedAlternative = struct {
    elements: []const ParsedElement,
    action: ?[]const u8,
    exclude_char: u8 = 0, // X "c" hint
    prefer_reduce: bool = false, // < hint - prefer reduce on S/R conflict
    prefer_shift: bool = false, // > hint - prefer shift on S/R conflict
};

/// Parsed element within an alternative
const ParsedElement = struct {
    kind: Kind,
    value: []const u8,
    quantifier: Quantifier = .one,
    optional_items: bool = false, // For L(X?): items can be empty
    list_separator: ?[]const u8 = null, // For L(X, sep): custom separator
    sub_elements: []const ParsedElement = &[_]ParsedElement{}, // For groups
    skip: bool = false, // For !element: parse but don't assign position

    const Kind = enum {
        ident, // rule reference
        token, // UPPERCASE token
        string, // "literal"
        group, // (...)
        opt_group, // [...] optional group
        req_list, // L(X)
        opt_list, // [L(X)]
    };

    const Quantifier = enum { one, optional, zero_plus, one_plus };
};

// =============================================================================
// Grammar Token (for parsing .grammar files)
// =============================================================================

const GrammarToken = struct {
    kind: Kind,
    text: []const u8,
    line: u32,

    const Kind = enum {
        ident, // lowercase identifier
        token, // UPPERCASE identifier
        string, // "literal"
        number, // numeric literal
        eq, // =
        pipe, // |
        arrow, // → or ->
        larrow, // ← (V annotation alias)
        question, // ?
        star, // *
        plus, // +
        lparen, // (
        rparen, // )
        lbracket, // [
        rbracket, // ]
        langle, // <
        rangle, // >
        comma, // ,
        colon, // :
        bang, // !
        tilde, // ~
        dots, // ...
        at, // @
        lbrace, // {
        rbrace, // }
        semicolon, // ; (inline comment start)
        newline,
        comment,
        eof,
        err,
    };
};

// =============================================================================
// Grammar Lexer (for parsing .grammar files)
// =============================================================================

const GrammarLexer = struct {
    source: []const u8,
    pos: u32 = 0,
    line: u32 = 1,

    fn init(source: []const u8) GrammarLexer {
        return .{ .source = source };
    }

    fn next(self: *GrammarLexer) GrammarToken {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            return self.makeToken(.eof, "");
        }

        const start_line = self.line;
        const start = self.pos;
        const c = self.source[self.pos];

        // Single character tokens
        const single: ?GrammarToken.Kind = switch (c) {
            '=' => .eq,
            '|' => .pipe,
            '?' => .question,
            '*' => .star,
            '+' => .plus,
            '(' => .lparen,
            ')' => .rparen,
            '[' => .lbracket,
            ']' => .rbracket,
            '<' => .langle,
            '>' => .rangle,
            '{' => .lbrace,
            '}' => .rbrace,
            ',' => .comma,
            ':' => .colon,
            '!' => .bang,
            '~' => .tilde,
            '@' => .at,
            ';' => .semicolon,
            '\n' => .newline,
            else => null,
        };

        if (single) |kind| {
            self.advance();
            if (kind == .newline) self.line += 1;
            return .{ .kind = kind, .text = self.source[start..self.pos], .line = start_line };
        }

        // Multi-character tokens
        switch (c) {
            '#' => {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
                return .{ .kind = .comment, .text = self.source[start..self.pos], .line = start_line };
            },
            '-' => {
                if (self.peek(1) == '>') {
                    self.advance();
                    self.advance();
                    return .{ .kind = .arrow, .text = self.source[start..self.pos], .line = start_line };
                }
                self.advance();
                return .{ .kind = .err, .text = self.source[start..self.pos], .line = start_line };
            },
            0xE2 => {
                // UTF-8 arrows: → (0xE2 0x86 0x92) and ← (0xE2 0x86 0x90)
                const kind: GrammarToken.Kind = if (self.peek(1) != 0x86) .err else switch (self.peek(2)) {
                    0x92 => .arrow,
                    0x90 => .larrow,
                    else => .err,
                };
                self.advance();
                self.advance();
                if (kind != .err) self.advance();
                return .{ .kind = kind, .text = self.source[start..self.pos], .line = start_line };
            },
            '.' => {
                if (self.peek(1) == '.' and self.peek(2) == '.') {
                    self.advance();
                    self.advance();
                    self.advance();
                    return .{ .kind = .dots, .text = self.source[start..self.pos], .line = start_line };
                }
                self.advance();
                return .{ .kind = .err, .text = self.source[start..self.pos], .line = start_line };
            },
            '"' => {
                self.advance();
                while (self.pos < self.source.len and self.source[self.pos] != '"') {
                    if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                        self.advance();
                    }
                    self.advance();
                }
                if (self.pos < self.source.len) self.advance();
                return .{ .kind = .string, .text = self.source[start..self.pos], .line = start_line };
            },
            'a'...'z' => {
                while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
                    self.advance();
                }
                return .{ .kind = .ident, .text = self.source[start..self.pos], .line = start_line };
            },
            'A'...'Z' => {
                while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
                    self.advance();
                }
                return .{ .kind = .token, .text = self.source[start..self.pos], .line = start_line };
            },
            '0'...'9' => {
                while (self.pos < self.source.len and self.source[self.pos] >= '0' and self.source[self.pos] <= '9') {
                    self.advance();
                }
                return .{ .kind = .number, .text = self.source[start..self.pos], .line = start_line };
            },
            else => {
                self.advance();
                return .{ .kind = .err, .text = self.source[start..self.pos], .line = start_line };
            },
        }
    }

    fn makeToken(self: *GrammarLexer, kind: GrammarToken.Kind, text: []const u8) GrammarToken {
        return .{ .kind = kind, .text = text, .line = self.line };
    }

    fn advance(self: *GrammarLexer) void {
        if (self.pos < self.source.len) self.pos += 1;
    }

    fn peek(self: *GrammarLexer, offset: u32) u8 {
        const idx = self.pos + offset;
        return if (idx < self.source.len) self.source[idx] else 0;
    }

    fn skipWhitespace(self: *GrammarLexer) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn isIdentChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '_';
    }
};

// =============================================================================
// Parser DSL Parser (parses @parser section of .grammar files)
// =============================================================================

const ParserDSLParser = struct {
    lexer: GrammarLexer,
    allocator: Allocator,
    current: GrammarToken,

    rules: std.ArrayListUnmanaged(ParsedRule) = .{},
    start_symbols: std.ArrayListUnmanaged([]const u8) = .{},
    as_directives: std.ArrayListUnmanaged(AsDirective) = .{},
    op_mappings: std.ArrayListUnmanaged(OpMapping) = .{},
    error_names: std.ArrayListUnmanaged(ErrorName) = .{},
    infix_ops: std.ArrayListUnmanaged(InfixOp) = .{},
    infix_base: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    code_blocks: std.ArrayListUnmanaged(CodeBlock) = .{},
    expect_conflicts: ?u32 = null,

    fn init(allocator: Allocator, source: []const u8) ParserDSLParser {
        var p = ParserDSLParser{
            .lexer = GrammarLexer.init(source),
            .allocator = allocator,
            .current = undefined,
        };
        p.current = p.lexer.next();
        return p;
    }

    fn deinit(self: *ParserDSLParser) void {
        for (self.rules.items) |*rule| {
            for (rule.alternatives) |*alt| {
                self.freeElements(alt.elements);
                self.allocator.free(alt.elements);
            }
            self.allocator.free(rule.alternatives);
        }
        self.rules.deinit(self.allocator);
        self.start_symbols.deinit(self.allocator);
        self.as_directives.deinit(self.allocator);
        self.op_mappings.deinit(self.allocator);
        self.error_names.deinit(self.allocator);
        self.infix_ops.deinit(self.allocator);
        self.code_blocks.deinit(self.allocator);
    }

    fn freeElements(self: *ParserDSLParser, elements: []const ParsedElement) void {
        for (elements) |elem| {
            if (elem.sub_elements.len > 0) {
                self.freeElements(elem.sub_elements);
                self.allocator.free(elem.sub_elements);
            }
        }
    }

    fn parse(self: *ParserDSLParser) !void {
        while (self.current.kind != .eof) {
            self.skipTrivia();
            if (self.current.kind == .eof) break;

            if (self.current.kind == .at) {
                try self.parseDirective();
            } else {
                try self.parseRule();
            }
        }
    }

    fn parseDirective(self: *ParserDSLParser) !void {
        self.advance(); // skip '@'
        const directive_name = try self.expectIdent("directive name after @");

        if (std.mem.eql(u8, directive_name, "as")) {
            try self.parseAsDirective();
        } else if (std.mem.eql(u8, directive_name, "op")) {
            try self.parseOpDirective();
        } else if (std.mem.eql(u8, directive_name, "lang")) {
            try self.parseLangDirective();
        } else if (std.mem.eql(u8, directive_name, "code")) {
            try self.parseCodeDirective();
        } else if (std.mem.eql(u8, directive_name, "errors")) {
            try self.parseErrorsDirective();
        } else if (std.mem.eql(u8, directive_name, "infix")) {
            try self.parseInfixDirective();
        } else if (std.mem.eql(u8, directive_name, "conflicts")) {
            try self.expect(.eq, "Expected '=' after @conflicts");
            if (self.current.kind != .number) {
                std.debug.print("Expected number after @conflicts = at line {d}\n", .{self.current.line});
                return error.ParseError;
            }
            self.expect_conflicts = std.fmt.parseInt(u32, self.current.text, 10) catch {
                std.debug.print("Invalid @conflicts value: {s}\n", .{self.current.text});
                return error.ParseError;
            };
            self.advance();
        } else {
            std.debug.print("Unknown directive @{s} at line {d}\n", .{ directive_name, self.current.line });
            return error.ParseError;
        }
    }

    fn parseAsDirective(self: *ParserDSLParser) !void {
        try self.expect(.eq, "Expected '=' after @as");
        try self.expect(.lbracket, "Expected '[' in @as directive");

        const tok = try self.expectIdent("token type");
        try self.expect(.comma, "Expected ',' after token");
        const rule = try self.expectIdent("rule name");
        try self.expect(.rbracket, "Expected ']' to close @as directive");

        if (self.current.kind == .newline) self.advance();

        try self.as_directives.append(self.allocator, .{ .token = tok, .rule = rule });
    }

    fn parseOpDirective(self: *ParserDSLParser) !void {
        try self.expect(.eq, "Expected '=' after @op");
        try self.expect(.lbracket, "Expected '[' in @op directive");

        while (self.current.kind != .rbracket and self.current.kind != .eof) {
            self.skipTrivia();
            if (self.current.kind == .rbracket) break;

            const lit = try self.expectString("operator literal");
            try self.expect(.arrow, "Expected '->' after literal");
            const tok = try self.expectString("token type");

            try self.op_mappings.append(self.allocator, .{ .lit = lit, .tok = tok });
            if (self.current.kind == .comma) self.advance();
        }

        try self.expect(.rbracket, "Expected ']' to close @op directive");
        if (self.current.kind == .newline) self.advance();
    }

    fn parseLangDirective(self: *ParserDSLParser) !void {
        try self.expect(.eq, "Expected '=' after @lang");
        const name = try self.expectString("language name");
        self.lang = name;
        if (self.current.kind == .newline) self.advance();
    }

    fn parseCodeDirective(self: *ParserDSLParser) !void {
        // Parse location identifier
        const location = try self.expectIdent("code location (imports, sexp, parser, bottom)");

        // Expect opening brace
        if (self.current.kind != .lbrace) {
            std.debug.print("Expected '{{' after @code {s} at line {d}\n", .{ location, self.current.line });
            return error.ParseError;
        }
        self.advance();

        // Find matching closing brace, counting nested braces while ignoring
        // braces inside strings and comments.
        const start = self.lexer.pos;
        var depth: usize = 1;
        var in_string: u8 = 0;
        var escaped = false;
        var in_line_comment = false;
        var in_block_comment = false;
        while (depth > 0 and self.lexer.pos < self.lexer.source.len) {
            const c = self.lexer.source[self.lexer.pos];
            const next = if (self.lexer.pos + 1 < self.lexer.source.len) self.lexer.source[self.lexer.pos + 1] else 0;

            if (in_line_comment) {
                if (c == '\n') in_line_comment = false;
                self.lexer.pos += 1;
                continue;
            }
            if (in_block_comment) {
                if (c == '*' and next == '/') {
                    in_block_comment = false;
                    self.lexer.pos += 2;
                    continue;
                }
                self.lexer.pos += 1;
                continue;
            }
            if (in_string != 0) {
                if (escaped) {
                    escaped = false;
                    self.lexer.pos += 1;
                    continue;
                }
                if (c == '\\') {
                    escaped = true;
                    self.lexer.pos += 1;
                    continue;
                }
                if (c == in_string) {
                    in_string = 0;
                    self.lexer.pos += 1;
                    continue;
                }
                self.lexer.pos += 1;
                continue;
            }

            if (c == '/' and next == '/') {
                in_line_comment = true;
                self.lexer.pos += 2;
                continue;
            }
            if (c == '/' and next == '*') {
                in_block_comment = true;
                self.lexer.pos += 2;
                continue;
            }
            if (c == '"' or c == '\'') {
                in_string = c;
                self.lexer.pos += 1;
                continue;
            }

            if (c == '{') {
                depth += 1;
            } else if (c == '}') {
                depth -= 1;
            }
            if (depth > 0) self.lexer.pos += 1;
        }

        if (depth != 0) {
            std.debug.print("Unclosed @code block at line {d}\n", .{self.current.line});
            return error.ParseError;
        }

        const code = std.mem.trim(u8, self.lexer.source[start..self.lexer.pos], " \t\n\r");
        self.lexer.pos += 1; // skip closing brace

        try self.code_blocks.append(self.allocator, .{ .location = location, .code = code });

        // Advance to next token
        self.current = self.lexer.next();
        if (self.current.kind == .newline) self.advance();
    }

    fn parseErrorsDirective(self: *ParserDSLParser) !void {
        if (self.current.kind == .newline) self.advance();
        self.skipTrivia();

        while ((self.current.kind == .ident or self.current.kind == .token) and self.peekKind() == .colon) {
            const rule = self.current.text;
            self.advance();
            self.advance(); // skip :
            const name = try self.expectString("error display name");
            try self.error_names.append(self.allocator, .{ .rule = rule, .name = name });
            if (self.current.kind == .comma) self.advance();
            if (self.current.kind == .newline) self.advance();
            self.skipTrivia();
        }
    }

    fn parseInfixDirective(self: *ParserDSLParser) !void {
        // Syntax: @precedence base_expr
        //   "op" assoc
        //   "op" assoc, "op" assoc     (same precedence)
        //   ...
        // Line order determines precedence (first = lowest).
        if (self.current.kind == .eq) self.advance();

        const base = try self.expectIdent("base expression name for @precedence");
        self.infix_base = base;

        if (self.current.kind == .newline) self.advance();
        self.skipTrivia();

        var prec: u32 = 1;
        while (self.current.kind == .string) {
            const op = try self.expectString("operator literal");

            const assoc_name = try self.expectIdent("associativity (left, right, none)");
            const assoc: InfixOp.Assoc = if (std.mem.eql(u8, assoc_name, "left"))
                .left
            else if (std.mem.eql(u8, assoc_name, "right"))
                .right
            else if (std.mem.eql(u8, assoc_name, "none"))
                .none
            else {
                std.debug.print("Invalid associativity '{s}' at line {d} (expected left, right, none)\n", .{ assoc_name, self.current.line });
                return error.ParseError;
            };

            // Skip explicit precedence number if present (backward compat)
            if (self.current.kind == .number) self.advance();

            try self.infix_ops.append(self.allocator, .{ .op = op, .assoc = assoc, .prec = prec });

            if (self.current.kind == .comma) {
                self.advance(); // same-line comma = same precedence level
            } else if (self.current.kind == .newline) {
                self.advance(); // newline = next precedence level
                self.skipTrivia();
                prec += 1;
            }
        }
    }

    fn parseRule(self: *ParserDSLParser) !void {
        self.skipTrivia();
        if (self.current.kind == .eof) return;

        if (self.current.kind != .ident and self.current.kind != .token) {
            std.debug.print("Expected rule name at line {d}, got {s}\n", .{ self.current.line, @tagName(self.current.kind) });
            return error.ParseError;
        }

        const name = self.current.text;
        self.advance();

        const is_start = self.current.kind == .bang;
        if (is_start) {
            self.advance();
            try self.start_symbols.append(self.allocator, name);
        }

        if (self.current.kind != .eq) {
            std.debug.print("Expected '=' at line {d}\n", .{self.current.line});
            return error.ParseError;
        }
        self.advance();

        var alternatives: std.ArrayListUnmanaged(ParsedAlternative) = .{};
        try self.parseAlternatives(&alternatives);

        try self.rules.append(self.allocator, .{
            .name = name,
            .is_start = is_start,
            .alternatives = try alternatives.toOwnedSlice(self.allocator),
        });
    }

    fn parseAlternatives(self: *ParserDSLParser, alternatives: *std.ArrayListUnmanaged(ParsedAlternative)) !void {
        try self.parseAlternative(alternatives);
        while (self.current.kind == .pipe) {
            self.advance();
            try self.parseAlternative(alternatives);
        }
    }

    fn parseAlternative(self: *ParserDSLParser, alternatives: *std.ArrayListUnmanaged(ParsedAlternative)) !void {
        var elements: std.ArrayListUnmanaged(ParsedElement) = .{};
        var action: ?[]const u8 = null;
        var exclude_char: u8 = 0;
        var prefer_reduce: bool = false;
        var prefer_shift: bool = false;

        while (true) {
            if (self.current.kind == .comment) {
                self.advance();
                continue;
            }

            // Check for < (tight binding / prefer reduce) hint
            if (self.current.kind == .langle) {
                prefer_reduce = true;
                self.advance();
                continue;
            }

            // Check for > (prefer shift) hint
            if (self.current.kind == .rangle) {
                prefer_shift = true;
                self.advance();
                continue;
            }

            // Check for X "c" (exclude) hint
            if (self.current.kind == .token and std.mem.eql(u8, self.current.text, "X")) {
                self.advance();
                if (self.current.kind == .string and self.current.text.len >= 2) {
                    exclude_char = self.current.text[1];
                    self.advance();
                }
                continue;
            }

            // Skip V annotation (documentation only)
            const is_v_annotation = (self.current.kind == .token and std.mem.eql(u8, self.current.text, "V")) or
                self.current.kind == .larrow;
            if (is_v_annotation) {
                while (self.current.kind != .arrow and
                    self.current.kind != .pipe and
                    self.current.kind != .newline and
                    self.current.kind != .eof)
                {
                    self.advance();
                }
                continue;
            }

            // Skip inline comments: ; to → or end of line
            if (self.current.kind == .semicolon) {
                while (self.current.kind != .arrow and
                    self.current.kind != .pipe and
                    self.current.kind != .newline and
                    self.current.kind != .eof)
                {
                    self.advance();
                }
                continue;
            }

            if (self.current.kind == .newline or self.current.kind == .pipe or self.current.kind == .eof) {
                break;
            }

            if (self.current.kind == .arrow) {
                self.advance();
                action = try self.parseAction();
                break;
            }

            const skip_element = self.current.kind == .bang;
            if (skip_element) self.advance();

            var element = try self.parseElement();
            element.skip = skip_element;
            try elements.append(self.allocator, element);
        }

        if (self.current.kind == .newline) self.advance();

        try alternatives.append(self.allocator, .{
            .elements = try elements.toOwnedSlice(self.allocator),
            .action = action,
            .exclude_char = exclude_char,
            .prefer_reduce = prefer_reduce,
            .prefer_shift = prefer_shift,
        });
    }

    fn parseElement(self: *ParserDSLParser) !ParsedElement {
        var element: ParsedElement = .{ .kind = undefined, .value = undefined };

        switch (self.current.kind) {
            .at => {
                // @infix reference — resolves to generated nonterminal
                self.advance(); // skip @
                const name = self.current.text;
                self.advance();
                element.kind = .ident;
                element.value = name;
            },
            .ident => {
                element.kind = .ident;
                element.value = self.current.text;
                self.advance();
            },
            .token => {
                // Check for L(X) or L(X, sep) syntax (required list)
                if (std.mem.eql(u8, self.current.text, "L") and self.peekKind() == .lparen) {
                    self.advance(); // skip L
                    self.advance(); // skip (
                    if (self.current.kind == .ident or self.current.kind == .token) {
                        element.kind = .req_list;
                        element.value = self.current.text;
                        self.advance();
                        if (self.current.kind == .question) {
                            element.optional_items = true;
                            self.advance();
                        }
                        // Check for custom separator: L(X, sep)
                        if (self.current.kind == .comma) {
                            self.advance(); // skip comma
                            if (self.current.kind == .string or self.current.kind == .token) {
                                element.list_separator = self.current.text;
                                self.advance();
                            }
                        }
                        while (self.current.kind != .rparen and self.current.kind != .eof) {
                            self.advance();
                        }
                        if (self.current.kind == .rparen) self.advance();
                    } else {
                        return error.ParseError;
                    }
                } else {
                    element.kind = .token;
                    element.value = self.current.text;
                    self.advance();
                }
            },
            .string => {
                element.kind = .string;
                element.value = self.current.text;
                self.advance();
            },
            .lparen => {
                self.advance();
                var sub_elements: std.ArrayListUnmanaged(ParsedElement) = .{};

                while (self.current.kind != .rparen and self.current.kind != .eof) {
                    if (self.current.kind == .comma or self.current.kind == .pipe) {
                        self.advance();
                        continue;
                    }
                    const skip_sub = self.current.kind == .bang;
                    if (skip_sub) self.advance();

                    if (self.current.kind == .ident or self.current.kind == .token or
                        self.current.kind == .string or self.current.kind == .lparen or
                        self.current.kind == .lbracket)
                    {
                        var sub = try self.parseElement();
                        sub.skip = skip_sub;
                        try sub_elements.append(self.allocator, sub);
                    } else {
                        self.advance();
                    }
                }
                if (self.current.kind == .rparen) self.advance();

                element.kind = .group;
                element.value = "";
                element.sub_elements = try sub_elements.toOwnedSlice(self.allocator);
            },
            .lbracket => {
                self.advance();
                const first_token = self.current.text;
                const first_kind = self.current.kind;

                // Check for [L(X)] or [L(X, sep)] syntax
                if (std.mem.eql(u8, first_token, "L") and first_kind == .token and self.peekKind() == .lparen) {
                    self.advance(); // skip L
                    self.advance(); // skip (
                    if (self.current.kind == .ident or self.current.kind == .token) {
                        element.kind = .opt_list;
                        element.value = self.current.text;
                        self.advance();
                        if (self.current.kind == .question) {
                            element.optional_items = true;
                            self.advance();
                        }
                        // Check for custom separator: [L(X, sep)]
                        if (self.current.kind == .comma) {
                            self.advance(); // skip comma
                            if (self.current.kind == .string or self.current.kind == .token) {
                                element.list_separator = self.current.text;
                                self.advance();
                            }
                        }
                        while (self.current.kind != .rbracket and self.current.kind != .eof) {
                            self.advance();
                        }
                        if (self.current.kind == .rbracket) self.advance();
                    } else {
                        return error.ParseError;
                    }
                } else {
                    // Parse bracket contents
                    var has_dots = false;
                    var sub_elements: std.ArrayListUnmanaged(ParsedElement) = .{};

                    var first_elem = ParsedElement{
                        .kind = if (first_kind == .string) .string else if (first_kind == .ident) .ident else .token,
                        .value = first_token,
                    };
                    self.advance();
                    if (self.current.kind == .question) {
                        first_elem.quantifier = .optional;
                        self.advance();
                    } else if (self.current.kind == .star) {
                        first_elem.quantifier = .zero_plus;
                        self.advance();
                    } else if (self.current.kind == .plus) {
                        first_elem.quantifier = .one_plus;
                        self.advance();
                    }
                    try sub_elements.append(self.allocator, first_elem);

                    while (self.current.kind != .rbracket and self.current.kind != .eof) {
                        if (self.current.kind == .dots) {
                            has_dots = true;
                            self.advance();
                            continue;
                        }
                        if (self.current.kind == .comma) {
                            self.advance();
                            continue;
                        }
                        if (self.current.kind == .ident or self.current.kind == .token or self.current.kind == .string) {
                            const sub = try self.parseElement();
                            try sub_elements.append(self.allocator, sub);
                        } else {
                            self.advance();
                        }
                    }
                    if (self.current.kind == .rbracket) self.advance();

                    if (has_dots) {
                        element.kind = .opt_list;
                        element.value = first_token;
                    } else if (sub_elements.items.len == 1 and (first_kind == .ident or first_kind == .token)) {
                        element.kind = if (first_kind == .ident) .ident else .token;
                        element.value = first_token;
                        element.quantifier = .optional;
                    } else {
                        element.kind = .opt_group;
                        element.value = first_token;
                        element.sub_elements = try sub_elements.toOwnedSlice(self.allocator);
                    }
                }
            },
            else => {
                std.debug.print("Unexpected token {s} at line {d}\n", .{ @tagName(self.current.kind), self.current.line });
                return error.ParseError;
            },
        }

        // Check for quantifier
        if (self.current.kind == .question) {
            element.quantifier = .optional;
            self.advance();
        } else if (self.current.kind == .star) {
            element.quantifier = .zero_plus;
            self.advance();
        } else if (self.current.kind == .plus or self.current.kind == .dots) {
            element.quantifier = .one_plus;
            self.advance();
        }

        return element;
    }

    fn parseAction(self: *ParserDSLParser) ![]const u8 {
        // Capture everything from current token to end of line
        const text_ptr = self.current.text.ptr;
        const source_ptr = self.lexer.source.ptr;
        const start = @intFromPtr(text_ptr) - @intFromPtr(source_ptr);

        while (self.current.kind != .newline and self.current.kind != .eof) {
            self.advance();
        }

        const end_ptr = self.current.text.ptr;
        const end = @intFromPtr(end_ptr) - @intFromPtr(source_ptr);

        return self.lexer.source[start..end];
    }

    fn advance(self: *ParserDSLParser) void {
        self.current = self.lexer.next();
    }

    fn peekKind(self: *ParserDSLParser) GrammarToken.Kind {
        const saved_pos = self.lexer.pos;
        const saved_line = self.lexer.line;
        const tok = self.lexer.next();
        self.lexer.pos = saved_pos;
        self.lexer.line = saved_line;
        return tok.kind;
    }

    fn skipTrivia(self: *ParserDSLParser) void {
        while (self.current.kind == .comment or self.current.kind == .newline) {
            self.advance();
        }
    }

    fn expect(self: *ParserDSLParser, kind: GrammarToken.Kind, msg: []const u8) !void {
        if (self.current.kind != kind) {
            std.debug.print("{s} at line {d}, got {s}\n", .{ msg, self.current.line, @tagName(self.current.kind) });
            return error.ParseError;
        }
        self.advance();
    }

    fn expectIdent(self: *ParserDSLParser, what: []const u8) ![]const u8 {
        if (self.current.kind != .ident) {
            std.debug.print("Expected {s} at line {d}, got {s}\n", .{ what, self.current.line, @tagName(self.current.kind) });
            return error.ParseError;
        }
        const text = self.current.text;
        self.advance();
        return text;
    }

    fn expectString(self: *ParserDSLParser, what: []const u8) ![]const u8 {
        if (self.current.kind != .string) {
            std.debug.print("Expected {s} at line {d}, got {s}\n", .{ what, self.current.line, @tagName(self.current.kind) });
            return error.ParseError;
        }
        const raw = self.current.text;
        const text = if (raw.len >= 2 and raw[0] == '"') raw[1 .. raw.len - 1] else raw;
        self.advance();
        return text;
    }
};

// =============================================================================
// SLR(1) Parser Generator
// =============================================================================

const ConflictDetail = struct {
    kind: enum { shift_reduce, reduce_reduce },
    name_a: []const u8,
    name_b: []const u8,
};

const ParserGenerator = struct {
    allocator: Allocator,

    // Symbol management
    symbols: std.ArrayListUnmanaged(ParserSymbol) = .{},
    symbol_map: std.StringHashMapUnmanaged(u16) = .{},
    aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    next_symbol_id: u16 = 0,

    // Rules
    rules: std.ArrayListUnmanaged(ParserRule) = .{},

    // LR automaton
    states: std.ArrayListUnmanaged(ParserState) = .{},

    // Special symbol IDs
    accept_id: u16 = 0,
    end_id: u16 = 0,
    error_id: u16 = 0,

    // Multiple start symbol support
    start_symbols: std.ArrayListUnmanaged(u16) = .{},
    start_states: std.ArrayListUnmanaged(u16) = .{},
    accept_rules: std.ArrayListUnmanaged(u16) = .{},

    conflicts: u32 = 0,
    expect_conflicts: ?u32 = null,
    conflict_details: std.ArrayListUnmanaged(ConflictDetail) = .{},

    // Directives
    as_directives: std.ArrayListUnmanaged(AsDirective) = .{},
    op_mappings: std.ArrayListUnmanaged(OpMapping) = .{},
    error_names: std.ArrayListUnmanaged(ErrorName) = .{},
    infix_ops: std.ArrayListUnmanaged(InfixOp) = .{},
    infix_base: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    lexer_spec: ?*const LexerSpec = null,
    code_blocks: std.ArrayListUnmanaged(CodeBlock) = .{},

    // Tags for enum generation
    collected_tags: std.StringHashMapUnmanaged(u16) = .{},
    tag_list: std.ArrayListUnmanaged([]const u8) = .{},

    // X "c" exclusions
    x_excludes: std.ArrayListUnmanaged(struct { state: u16, char: u8, shift: u16 }) = .{},

    fn init(allocator: Allocator) ParserGenerator {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ParserGenerator) void {
        for (self.symbols.items) |*sym| sym.deinit(self.allocator);
        self.symbols.deinit(self.allocator);
        self.symbol_map.deinit(self.allocator);
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

        self.start_symbols.deinit(self.allocator);
        self.start_states.deinit(self.allocator);
        self.accept_rules.deinit(self.allocator);
        self.as_directives.deinit(self.allocator);
        self.op_mappings.deinit(self.allocator);
        self.error_names.deinit(self.allocator);
        self.infix_ops.deinit(self.allocator);
        self.code_blocks.deinit(self.allocator);
        self.collected_tags.deinit(self.allocator);
        self.tag_list.deinit(self.allocator);
        self.x_excludes.deinit(self.allocator);
    }

    fn addSymbol(self: *ParserGenerator, name: []const u8, kind: ParserSymbol.Kind) !u16 {
        if (self.symbol_map.get(name)) |id| return id;

        const id = self.next_symbol_id;
        self.next_symbol_id += 1;

        try self.symbols.append(self.allocator, ParserSymbol.init(id, name, kind));
        try self.symbol_map.put(self.allocator, name, id);

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
        return self.symbol_map.get(resolved);
    }

    fn isAcceptRuleId(self: *ParserGenerator, rule_id: u16) bool {
        for (self.accept_rules.items) |ar| {
            if (rule_id == ar) return true;
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
        start_pos: usize, // Starting position number (1-based)
        elem_count: usize, // Number of elements in this optional
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
        var opt_groups: std.ArrayListUnmanaged(OptGroupInfo) = .{};
        defer opt_groups.deinit(self.allocator);

        var pos: usize = 1;
        for (alt.elements, 0..) |elem, idx| {
            if (elem.kind == .opt_group) {
                // Multi-element optional: [A B C]
                try opt_groups.append(self.allocator, .{
                    .index = idx,
                    .start_pos = pos,
                    .elem_count = elem.sub_elements.len,
                });
                pos += elem.sub_elements.len;
            } else if (elem.quantifier == .optional and (elem.kind == .ident or elem.kind == .opt_list)) {
                // Single-element bracket-optional: [X] parsed as X with .optional quantifier
                // Only include nonterminals (ident) and optional lists, not token quantifiers (SPACES?)
                try opt_groups.append(self.allocator, .{
                    .index = idx,
                    .start_pos = pos,
                    .elem_count = 1,
                });
                pos += 1;
            } else {
                pos += 1;
            }
        }

        // If no opt_groups, no expansion needed
        // Note: Even single opt_groups need expansion for positionally stable output
        if (opt_groups.items.len == 0) {
            var result: std.ArrayListUnmanaged(ParsedAlternative) = .{};
            try result.append(self.allocator, alt);
            return result.toOwnedSlice(self.allocator);
        }

        // Generate 2^n combinations
        const n = opt_groups.items.len;
        const combinations: usize = @as(usize, 1) << @intCast(n);

        var expanded: std.ArrayListUnmanaged(ParsedAlternative) = .{};

        var combo: usize = 0;
        while (combo < combinations) : (combo += 1) {
            // Build elements for this combination
            var new_elements: std.ArrayListUnmanaged(ParsedElement) = .{};

            for (alt.elements, 0..) |elem, idx| {
                // Check if this element is an optional (opt_group or single-element)
                const opt_idx: ?usize = for (opt_groups.items, 0..) |og, oi| {
                    if (og.index == idx) break oi;
                } else null;

                if (opt_idx) |oi| {
                    // Check if this optional is present in this combination
                    const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;
                    if (present) {
                        if (elem.kind == .opt_group) {
                            // Multi-element optional: add sub-elements directly
                            for (elem.sub_elements) |sub| {
                                try new_elements.append(self.allocator, sub);
                            }
                        } else {
                            // Single-element optional: add element without optional quantifier
                            var non_opt = elem;
                            non_opt.quantifier = .one;
                            try new_elements.append(self.allocator, non_opt);
                        }
                    }
                    // If not present, skip this optional entirely
                } else {
                    try new_elements.append(self.allocator, elem);
                }
            }

            // Transform action with stable positions (use original elements for position mapping)
            const final_elements = try new_elements.toOwnedSlice(self.allocator);
            var new_action: ?[]const u8 = alt.action;
            if (alt.action) |action| {
                new_action = try self.transformActionStable(action, alt.elements, opt_groups.items, combo);
            }

            try expanded.append(self.allocator, .{
                .elements = final_elements,
                .action = new_action,
                .exclude_char = alt.exclude_char,
                .prefer_reduce = alt.prefer_reduce,
            });
        }

        return expanded.toOwnedSlice(self.allocator);
    }

    // Position map: 255 means nil/absent, otherwise it's the actual RHS position
    const NIL_POS: u8 = 255;
    const MAX_POSITIONS: usize = 64;

    /// Parsed position reference from action template
    const PosRef = struct {
        kind: enum { bare, keyed, spread },
        pos_num: usize,
        end_idx: usize, // Index after this reference in the action string
    };

    /// Tracks position references for trailing-nil stripping
    const PosRefInfo = struct { start: usize, is_nil: bool };

    /// Build logical-to-actual position map for stable positions.
    /// Maps logical positions (1-based) to actual RHS positions, or NIL_POS for absent optionals.
    fn buildPositionMap(
        alt_elements: []const ParsedElement,
        opt_groups: []const OptGroupInfo,
        combo: usize,
    ) [MAX_POSITIONS]u8 {
        var pos_map: [MAX_POSITIONS]u8 = [_]u8{NIL_POS} ** MAX_POSITIONS;
        var logical_pos: usize = 1;
        var actual_pos: usize = 0;

        for (alt_elements, 0..) |_, elem_idx| {
            // Find if this element is an opt_group
            const opt_idx = for (opt_groups, 0..) |og, oi| {
                if (og.index == elem_idx) break oi;
            } else null;

            if (opt_idx) |oi| {
                const og = opt_groups[oi];
                const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;

                for (0..og.elem_count) |_| {
                    if (logical_pos < MAX_POSITIONS) {
                        pos_map[logical_pos] = if (present) @intCast(actual_pos) else NIL_POS;
                    }
                    logical_pos += 1;
                    if (present) actual_pos += 1;
                }
            } else {
                if (logical_pos < MAX_POSITIONS) {
                    pos_map[logical_pos] = @intCast(actual_pos);
                }
                logical_pos += 1;
                actual_pos += 1;
            }
        }

        return pos_map;
    }

    /// Parse a position reference at the given index in the action string.
    /// Returns null if no position reference found at this location.
    fn parsePositionRef(action: []const u8, start: usize) ?PosRef {
        if (start >= action.len) return null;

        // key:N (key prefix is for documentation, stripped from output)
        if (action[start] >= 'a' and action[start] <= 'z') {
            var key_end = start;
            while (key_end < action.len and action[key_end] != ':' and action[key_end] != ' ' and action[key_end] != ')') {
                key_end += 1;
            }
            if (key_end < action.len and action[key_end] == ':') {
                const num_start = key_end + 1;
                var num_end = num_start;
                while (num_end < action.len and action[num_end] >= '0' and action[num_end] <= '9') {
                    num_end += 1;
                }
                if (num_end > num_start) {
                    const pos_num = std.fmt.parseInt(usize, action[num_start..num_end], 10) catch return null;
                    return .{ .kind = .keyed, .pos_num = pos_num, .end_idx = num_end };
                }
            }
            return null;
        }

        // Bare number N
        if (action[start] >= '1' and action[start] <= '9') {
            var num_end = start;
            while (num_end < action.len and action[num_end] >= '0' and action[num_end] <= '9') {
                num_end += 1;
            }
            const pos_num = std.fmt.parseInt(usize, action[start..num_end], 10) catch return null;
            return .{ .kind = .bare, .pos_num = pos_num, .end_idx = num_end };
        }

        // ...N (spread)
        if (start + 3 < action.len and action[start] == '.' and action[start + 1] == '.' and action[start + 2] == '.') {
            var num_end = start + 3;
            while (num_end < action.len and action[num_end] >= '0' and action[num_end] <= '9') {
                num_end += 1;
            }
            if (num_end > start + 3) {
                const pos_num = std.fmt.parseInt(usize, action[start + 3 .. num_end], 10) catch return null;
                return .{ .kind = .spread, .pos_num = pos_num, .end_idx = num_end };
            }
        }

        return null;
    }

    /// Strip trailing nil references from the result buffer.
    fn stripTrailingNils(result: *std.ArrayListUnmanaged(u8), pos_refs: []const PosRefInfo) void {
        // Find last non-nil position reference
        var last_non_nil: ?usize = null;
        for (pos_refs, 0..) |pr, idx| {
            if (!pr.is_nil) last_non_nil = idx;
        }

        const truncate_start = if (last_non_nil) |lnn|
            if (lnn + 1 < pos_refs.len) pos_refs[lnn + 1].start else return
        else if (pos_refs.len > 0)
            pos_refs[0].start
        else
            return;

        // Also remove preceding spaces
        var actual_start = truncate_start;
        while (actual_start > 0 and result.items[actual_start - 1] == ' ') {
            actual_start -= 1;
        }
        result.items.len = actual_start;
    }

    /// Transform action template for stable positions.
    /// Keeps logical positions stable, maps to actual RHS positions, inserts nil for absent optionals.
    /// Strips trailing nils from the output.
    fn transformActionStable(
        self: *ParserGenerator,
        action: []const u8,
        alt_elements: []const ParsedElement,
        opt_groups: []const OptGroupInfo,
        combo: usize,
    ) ![]const u8 {
        const pos_map = buildPositionMap(alt_elements, opt_groups, combo);

        var result: std.ArrayListUnmanaged(u8) = .{};
        var pos_refs: std.ArrayListUnmanaged(PosRefInfo) = .{};
        defer pos_refs.deinit(self.allocator);

        var i: usize = 0;
        while (i < action.len) {
            if (parsePositionRef(action, i)) |ref| {
                const mapped = if (ref.pos_num < MAX_POSITIONS) pos_map[ref.pos_num] else NIL_POS;
                const is_nil = (mapped == NIL_POS);

                try pos_refs.append(self.allocator, .{ .start = result.items.len, .is_nil = is_nil });

                if (is_nil) {
                    try result.appendSlice(self.allocator, "nil");
                } else {
                    // Output prefix (...) then mapped position
                    if (ref.kind == .spread) {
                        try result.appendSlice(self.allocator, "...");
                    }
                    var buf: [16]u8 = undefined;
                    const pos_str = std.fmt.bufPrint(&buf, "{d}", .{mapped + 1}) catch unreachable;
                    try result.appendSlice(self.allocator, pos_str);
                }
                i = ref.end_idx;
            } else {
                try result.append(self.allocator, action[i]);
                i += 1;
            }
        }

        stripTrailingNils(&result, pos_refs.items);
        return result.toOwnedSlice(self.allocator);
    }

    /// Process parsed grammar into internal representation
    fn processGrammar(self: *ParserGenerator, parser: *ParserDSLParser) !void {
        // Add special symbols
        self.accept_id = try self.addSymbol("$accept", .nonterminal);
        self.end_id = try self.addSymbol("$end", .terminal);
        self.error_id = try self.addSymbol("error", .terminal);

        // Pre-pass: detect aliases
        for (parser.rules.items) |rule| {
            if (isAliasRule(rule)) |target| {
                try self.aliases.put(self.allocator, rule.name, target);
            }
        }

        // First pass: add all nonterminal names (skip aliases)
        for (parser.rules.items) |rule| {
            if (self.aliases.contains(rule.name)) continue;
            _ = try self.addSymbol(rule.name, .nonterminal);
        }

        // Second pass: process rules and add terminals
        // Expands consecutive optional groups to avoid LALR conflicts
        for (parser.rules.items) |rule| {
            if (self.aliases.contains(rule.name)) continue;

            const lhs_id = self.getSymbol(rule.name).?;

            for (rule.alternatives) |alt| {
                // Expand consecutive opt_groups into explicit alternatives
                const expanded_alts = try self.expandOptionalGroups(alt);

                for (expanded_alts) |expanded_alt| {
                    var rhs: std.ArrayListUnmanaged(u16) = .{};

                    for (expanded_alt.elements) |elem| {
                        const sym_id = try self.processElement(elem);
                        try rhs.append(self.allocator, sym_id);
                    }

                    const rule_id: u16 = @intCast(self.rules.items.len);
                    try self.rules.append(self.allocator, .{
                        .id = rule_id,
                        .lhs = lhs_id,
                        .rhs = try rhs.toOwnedSlice(self.allocator),
                        .action = if (expanded_alt.action) |a| .{ .template = a, .kind = .sexp } else null,
                        .exclude_char = expanded_alt.exclude_char,
                        .prefer_reduce = expanded_alt.prefer_reduce,
                        .prefer_shift = expanded_alt.prefer_shift,
                    });
                    try self.symbols.items[lhs_id].rules.append(self.allocator, rule_id);
                }
            }
        }

        // Use EOF as $end if defined
        if (self.symbol_map.get("EOF")) |eof_id| {
            self.end_id = eof_id;
        }

        // Create augmented rules for EACH start symbol
        if (parser.start_symbols.items.len > 0) {
            for (parser.start_symbols.items) |start_name| {
                if (self.getSymbol(start_name)) |start_id| {
                    // Create marker terminal "X!"
                    const marker_name = try std.fmt.allocPrint(self.allocator, "{s}!", .{start_name});
                    const marker_id = try self.addSymbol(marker_name, .terminal);

                    // Prepend marker to start rule
                    for (self.rules.items) |*rule| {
                        if (rule.lhs == start_id) {
                            var new_rhs: std.ArrayListUnmanaged(u16) = .{};
                            try new_rhs.append(self.allocator, marker_id);
                            for (rule.rhs) |sym| {
                                try new_rhs.append(self.allocator, sym);
                            }
                            rule.rhs = try new_rhs.toOwnedSlice(self.allocator);
                            rule.action_offset = 1;
                            break;
                        }
                    }

                    // Create unique accept symbol
                    const accept_name = try std.fmt.allocPrint(self.allocator, "$accept_{s}", .{start_name});
                    const unique_accept_id = try self.addSymbol(accept_name, .nonterminal);

                    // Create augmented rule: $accept_X → startSymbol EOF
                    var accept_rhs: std.ArrayListUnmanaged(u16) = .{};
                    try accept_rhs.append(self.allocator, start_id);
                    try accept_rhs.append(self.allocator, self.end_id);

                    const accept_rule_id: u16 = @intCast(self.rules.items.len);
                    try self.rules.append(self.allocator, .{
                        .id = accept_rule_id,
                        .lhs = unique_accept_id,
                        .rhs = try accept_rhs.toOwnedSlice(self.allocator),
                        .action = null,
                    });
                    try self.symbols.items[unique_accept_id].rules.append(self.allocator, accept_rule_id);

                    try self.start_symbols.append(self.allocator, start_id);
                    try self.accept_rules.append(self.allocator, accept_rule_id);
                }
            }
        } else if (self.rules.items.len > 0) {
            // Fallback: use first rule as start symbol
            const start_symbol = self.rules.items[0].lhs;

            var accept_rhs: std.ArrayListUnmanaged(u16) = .{};
            try accept_rhs.append(self.allocator, start_symbol);
            try accept_rhs.append(self.allocator, self.end_id);

            const accept_rule_id: u16 = @intCast(self.rules.items.len);
            try self.rules.append(self.allocator, .{
                .id = accept_rule_id,
                .lhs = self.accept_id,
                .rhs = try accept_rhs.toOwnedSlice(self.allocator),
                .action = null,
            });
            try self.symbols.items[self.accept_id].rules.append(self.allocator, accept_rule_id);

            try self.start_symbols.append(self.allocator, start_symbol);
            try self.accept_rules.append(self.allocator, accept_rule_id);
        }

        // Copy directives
        for (parser.as_directives.items) |d| try self.as_directives.append(self.allocator, d);
        for (parser.op_mappings.items) |m| try self.op_mappings.append(self.allocator, m);
        for (parser.error_names.items) |e| try self.error_names.append(self.allocator, e);
        for (parser.infix_ops.items) |op| try self.infix_ops.append(self.allocator, op);
        self.infix_base = parser.infix_base;
        self.lang = parser.lang;
        self.expect_conflicts = parser.expect_conflicts;

        // Generate infix expression chain if @infix was declared
        if (self.infix_ops.items.len > 0 and self.infix_base != null) {
            try self.generateInfixChain();
        }
        for (parser.code_blocks.items) |b| try self.code_blocks.append(self.allocator, b);
    }

    /// Validate that all referenced symbols are defined.
    /// Returns error count (0 = all valid).
    pub fn validateSymbols(self: *ParserGenerator, lexer_spec: *const LexerSpec) u32 {
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
                var is_as_keyword = false;
                for (self.symbols.items) |other| {
                    if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                        is_as_keyword = true;
                        break;
                    }
                }
                if (is_as_keyword) continue;

                // Skip if it matches an @as directive rule name (e.g., SYSVAR from @as=[ident,sysvar])
                for (self.as_directives.items) |directive| {
                    if (std.ascii.eqlIgnoreCase(directive.rule, sym.name)) {
                        is_as_keyword = true;
                        break;
                    }
                }
                if (is_as_keyword) continue;

                // When @lang is set, keyword terminals are resolved by the
                // lang module's keyword matcher at compile time. Trust the
                // Zig compiler to catch mismatches.
                if (self.lang != null and self.as_directives.items.len > 0) continue;

                var found = false;

                // Check tokens block (case-insensitive since lexer uses lowercase)
                for (lexer_spec.tokens.items) |tok| {
                    if (std.ascii.eqlIgnoreCase(tok.name, sym.name)) {
                        found = true;
                        break;
                    }
                }

                // Check lexer rules (case-insensitive)
                if (!found) {
                    for (lexer_spec.rules.items) |rule| {
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
        const base_id = try self.processBaseElement(elem);

        return switch (elem.quantifier) {
            .one => base_id,
            .optional => try self.createOptionalRule(base_id),
            .zero_plus => try self.createZeroPlusRule(base_id),
            .one_plus => try self.createOnePlusRule(base_id),
        };
    }

    fn processBaseElement(self: *ParserGenerator, elem: ParsedElement) error{OutOfMemory}!u16 {
        return switch (elem.kind) {
            .ident => blk: {
                if (self.getSymbol(elem.value)) |sym_id| break :blk sym_id;
                var resolved = elem.value;
                while (self.aliases.get(resolved)) |target| resolved = target;
                const kind: ParserSymbol.Kind = if (resolved.len > 0 and resolved[0] >= 'A' and resolved[0] <= 'Z')
                    .terminal
                else
                    .nonterminal;
                break :blk try self.addSymbol(resolved, kind);
            },
            .token => blk: {
                if (self.getSymbol(elem.value)) |sym_id| break :blk sym_id;
                var resolved = elem.value;
                while (self.aliases.get(resolved)) |target| resolved = target;
                break :blk try self.addSymbol(resolved, .terminal);
            },
            .string => try self.addSymbol(elem.value, .terminal),
            .group => blk: {
                if (elem.sub_elements.len == 0) break :blk self.error_id;

                const grp_name = try std.fmt.allocPrint(self.allocator, "_grp_{d}", .{self.rules.items.len});
                const grp_id = try self.addSymbol(grp_name, .nonterminal);

                var rhs: std.ArrayListUnmanaged(u16) = .{};
                for (elem.sub_elements) |sub| {
                    try rhs.append(self.allocator, try self.processElement(sub));
                }

                // Build action that excludes skipped elements
                // If element has skip=true, don't include its position in the action
                var action_template: ?[]const u8 = null;
                var non_skipped: std.ArrayListUnmanaged(u8) = .{};
                defer non_skipped.deinit(self.allocator);

                for (elem.sub_elements, 0..) |sub, i| {
                    if (!sub.skip) {
                        try non_skipped.append(self.allocator, @intCast(i + 1)); // 1-based positions
                    }
                }

                // Generate action based on non-skipped count
                if (non_skipped.items.len == 0) {
                    action_template = "nil";
                } else if (non_skipped.items.len == 1) {
                    // Single non-skipped: just return that position
                    action_template = try std.fmt.allocPrint(self.allocator, "{d}", .{non_skipped.items[0]});
                } else if (non_skipped.items.len < elem.sub_elements.len) {
                    // Multiple non-skipped but some skipped: build explicit list
                    var buf: std.ArrayListUnmanaged(u8) = .{};
                    defer buf.deinit(self.allocator);
                    try buf.append(self.allocator, '(');
                    for (non_skipped.items, 0..) |pos, j| {
                        if (j > 0) try buf.append(self.allocator, ' ');
                        try buf.append(self.allocator, '0' + pos);
                    }
                    try buf.append(self.allocator, ')');
                    action_template = try self.allocator.dupe(u8, buf.items);
                }
                // else: all elements included, action stays null (default list behavior)

                const rule_id: u16 = @intCast(self.rules.items.len);
                try self.rules.append(self.allocator, .{
                    .id = rule_id,
                    .lhs = grp_id,
                    .rhs = try rhs.toOwnedSlice(self.allocator),
                    .action = if (action_template) |t| .{ .template = t, .kind = .sexp } else null,
                });
                try self.symbols.items[grp_id].rules.append(self.allocator, rule_id);

                break :blk grp_id;
            },
            .opt_group => self.error_id, // Should be expanded
            .req_list => blk: {
                const item_name = elem.value;
                break :blk try self.createRequiredList(item_name, elem.optional_items, elem.list_separator);
            },
            .opt_list => blk: {
                const item_name = elem.value;
                const req_list = try self.createRequiredList(item_name, elem.optional_items, elem.list_separator);
                break :blk try self.createOptionalRule(req_list);
            },
        };
    }

    fn createRequiredList(self: *ParserGenerator, item_name: []const u8, optional_items: bool, custom_sep: ?[]const u8) !u16 {
        const item_id = self.getSymbol(item_name) orelse blk: {
            const kind: ParserSymbol.Kind = if (item_name.len > 0 and item_name[0] >= 'A' and item_name[0] <= 'Z')
                .terminal
            else
                .nonterminal;
            break :blk try self.addSymbol(item_name, kind);
        };

        const effective_item_id = if (optional_items)
            try self.createOptionalRule(item_id)
        else
            item_id;

        const sep_str = custom_sep orelse "\",\"";
        const sep_id = try self.addSymbol(sep_str, .terminal);

        const suffix: []const u8 = if (optional_items) "opt" else "";
        const sep_suffix: []const u8 = if (custom_sep != null) "s" else "";
        const list_name = try std.fmt.allocPrint(self.allocator, "_list_{d}{s}{s}", .{ item_id, suffix, sep_suffix });
        const tail_name = try std.fmt.allocPrint(self.allocator, "_tail_{d}{s}{s}", .{ item_id, suffix, sep_suffix });

        if (self.getSymbol(list_name)) |existing| return existing;

        const list_id = try self.addSymbol(list_name, .nonterminal);
        const tail_id = try self.addSymbol(tail_name, .nonterminal);

        // Rule: _list → item _tail → (!1 ...2)
        const list_rule_id: u16 = @intCast(self.rules.items.len);
        var list_rhs: std.ArrayListUnmanaged(u16) = .{};
        try list_rhs.append(self.allocator, effective_item_id);
        try list_rhs.append(self.allocator, tail_id);
        try self.rules.append(self.allocator, .{
            .id = list_rule_id,
            .lhs = list_id,
            .rhs = try list_rhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[list_id].rules.append(self.allocator, list_rule_id);

        // Rule: _tail → sep item _tail → (!2 ...3)
        const tail_rule1_id: u16 = @intCast(self.rules.items.len);
        var tail_rhs1: std.ArrayListUnmanaged(u16) = .{};
        try tail_rhs1.append(self.allocator, sep_id);
        try tail_rhs1.append(self.allocator, effective_item_id);
        try tail_rhs1.append(self.allocator, tail_id);
        try self.rules.append(self.allocator, .{
            .id = tail_rule1_id,
            .lhs = tail_id,
            .rhs = try tail_rhs1.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!2 ...3)", .kind = .sexp },
        });
        try self.symbols.items[tail_id].rules.append(self.allocator, tail_rule1_id);

        // Rule: _tail → ε → ()
        const tail_rule2_id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = tail_rule2_id,
            .lhs = tail_id,
            .rhs = &[_]u16{},
            .action = .{ .template = "()", .kind = .sexp },
            .nullable = true,
            .prefer_shift = true,
        });
        try self.symbols.items[tail_id].rules.append(self.allocator, tail_rule2_id);
        self.symbols.items[tail_id].nullable = true;

        return list_id;
    }

    fn generateInfixChain(self: *ParserGenerator) !void {
        const base_name = self.infix_base orelse return;
        const base_id = self.getSymbol(base_name) orelse blk: {
            break :blk try self.addSymbol(base_name, .nonterminal);
        };

        // Collect unique precedence levels and sort them
        var levels_seen: [64]u32 = undefined;
        var level_count: usize = 0;

        for (self.infix_ops.items) |op| {
            var found = false;
            for (levels_seen[0..level_count]) |l| {
                if (l == op.prec) {
                    found = true;
                    break;
                }
            }
            if (!found and level_count < 64) {
                levels_seen[level_count] = op.prec;
                level_count += 1;
            }
        }

        // Sort levels ascending (level 1 = loosest binding)
        for (0..level_count) |i| {
            for (i + 1..level_count) |j| {
                if (levels_seen[j] < levels_seen[i]) {
                    const tmp = levels_seen[i];
                    levels_seen[i] = levels_seen[j];
                    levels_seen[j] = tmp;
                }
            }
        }

        // Create a nonterminal for each level
        var level_ids: [64]u16 = undefined;
        for (0..level_count) |i| {
            const name = try std.fmt.allocPrint(self.allocator, "_infix_{d}", .{levels_seen[i]});
            level_ids[i] = try self.addSymbol(name, .nonterminal);
        }

        // For each level, generate rules
        for (0..level_count) |i| {
            const level = levels_seen[i];
            const this_id = level_ids[i];
            const next_id = if (i + 1 < level_count) level_ids[i + 1] else base_id;

            // Find all operators at this level
            for (self.infix_ops.items) |op| {
                if (op.prec != level) continue;

                const op_str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{op.op});
                const op_id = try self.addSymbol(op_str, .terminal);

                const action_str = try std.fmt.allocPrint(self.allocator, "({s} 1 3)", .{op.op});

                var rhs: std.ArrayListUnmanaged(u16) = .{};
                switch (op.assoc) {
                    .left => {
                        try rhs.append(self.allocator, this_id);
                        try rhs.append(self.allocator, op_id);
                        try rhs.append(self.allocator, next_id);
                    },
                    .right => {
                        try rhs.append(self.allocator, next_id);
                        try rhs.append(self.allocator, op_id);
                        try rhs.append(self.allocator, this_id);
                    },
                    .none => {
                        try rhs.append(self.allocator, next_id);
                        try rhs.append(self.allocator, op_id);
                        try rhs.append(self.allocator, next_id);
                    },
                }

                const rule_id: u16 = @intCast(self.rules.items.len);
                try self.rules.append(self.allocator, .{
                    .id = rule_id,
                    .lhs = this_id,
                    .rhs = try rhs.toOwnedSlice(self.allocator),
                    .action = .{ .template = action_str, .kind = .sexp },
                });
                try self.symbols.items[this_id].rules.append(self.allocator, rule_id);
            }

            // Passthrough rule: this_level → next_level
            const passthrough_id: u16 = @intCast(self.rules.items.len);
            var pass_rhs: std.ArrayListUnmanaged(u16) = .{};
            try pass_rhs.append(self.allocator, next_id);
            try self.rules.append(self.allocator, .{
                .id = passthrough_id,
                .lhs = this_id,
                .rhs = try pass_rhs.toOwnedSlice(self.allocator),
                .action = .{ .template = "1", .kind = .passthrough },
            });
            try self.symbols.items[this_id].rules.append(self.allocator, passthrough_id);
        }

        // Create the `infix` entry point that aliases to the lowest-precedence level
        const infix_id = try self.addSymbol("infix", .nonterminal);
        const infix_rule_id: u16 = @intCast(self.rules.items.len);
        var infix_rhs: std.ArrayListUnmanaged(u16) = .{};
        try infix_rhs.append(self.allocator, level_ids[0]);
        try self.rules.append(self.allocator, .{
            .id = infix_rule_id,
            .lhs = infix_id,
            .rhs = try infix_rhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "1", .kind = .passthrough },
        });
        try self.symbols.items[infix_id].rules.append(self.allocator, infix_rule_id);
    }

    fn createOptionalRule(self: *ParserGenerator, sym_id: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_opt_{d}", .{sym_id});
        if (self.getSymbol(name)) |existing| return existing;

        const opt_id = try self.addSymbol(name, .nonterminal);

        // Rule 1: opt → sym
        const rule1_id: u16 = @intCast(self.rules.items.len);
        var rhs1: std.ArrayListUnmanaged(u16) = .{};
        try rhs1.append(self.allocator, sym_id);
        try self.rules.append(self.allocator, .{
            .id = rule1_id,
            .lhs = opt_id,
            .rhs = try rhs1.toOwnedSlice(self.allocator),
            .action = null,
        });
        try self.symbols.items[opt_id].rules.append(self.allocator, rule1_id);

        // Rule 2: opt → ε
        const rule2_id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = rule2_id,
            .lhs = opt_id,
            .rhs = &[_]u16{},
            .action = null,
            .nullable = true,
        });
        try self.symbols.items[opt_id].rules.append(self.allocator, rule2_id);
        self.symbols.items[opt_id].nullable = true;

        return opt_id;
    }

    fn createZeroPlusRule(self: *ParserGenerator, sym_id: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_star_{d}", .{sym_id});
        if (self.getSymbol(name)) |existing| return existing;

        const star_id = try self.addSymbol(name, .nonterminal);

        // Rule 1: star → sym star → (!1 ...2)
        const rule1_id: u16 = @intCast(self.rules.items.len);
        var rhs1: std.ArrayListUnmanaged(u16) = .{};
        try rhs1.append(self.allocator, sym_id);
        try rhs1.append(self.allocator, star_id);
        try self.rules.append(self.allocator, .{
            .id = rule1_id,
            .lhs = star_id,
            .rhs = try rhs1.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[star_id].rules.append(self.allocator, rule1_id);

        // Rule 2: star → ε → ()
        const rule2_id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = rule2_id,
            .lhs = star_id,
            .rhs = &[_]u16{},
            .action = .{ .template = "()", .kind = .sexp },
            .nullable = true,
        });
        try self.symbols.items[star_id].rules.append(self.allocator, rule2_id);
        self.symbols.items[star_id].nullable = true;

        return star_id;
    }

    fn createOnePlusRule(self: *ParserGenerator, sym_id: u16) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "_plus_{d}", .{sym_id});
        if (self.getSymbol(name)) |existing| return existing;

        const star_id = try self.createZeroPlusRule(sym_id);
        const plus_id = try self.addSymbol(name, .nonterminal);

        // Rule: plus → sym star → (!1 ...2)
        const rule_id: u16 = @intCast(self.rules.items.len);
        var rhs: std.ArrayListUnmanaged(u16) = .{};
        try rhs.append(self.allocator, sym_id);
        try rhs.append(self.allocator, star_id);
        try self.rules.append(self.allocator, .{
            .id = rule_id,
            .lhs = plus_id,
            .rhs = try rhs.toOwnedSlice(self.allocator),
            .action = .{ .template = "(!1 ...2)", .kind = .sexp },
        });
        try self.symbols.items[plus_id].rules.append(self.allocator, rule_id);

        return plus_id;
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
        if (self.accept_rules.items.len == 0) return error.NoAcceptRule;

        var state_map = std.StringHashMapUnmanaged(u16){};
        defer state_map.deinit(self.allocator);

        // Create initial state for EACH accept rule
        for (self.accept_rules.items) |accept_rule_id| {
            var initial_items: std.ArrayListUnmanaged(ParserItem) = .{};
            try initial_items.append(self.allocator, .{ .rule_id = accept_rule_id, .dot = 0 });

            const kernel = try initial_items.toOwnedSlice(self.allocator);
            const sig = try self.kernelSignature(kernel);

            if (state_map.get(sig)) |existing_id| {
                try self.start_states.append(self.allocator, existing_id);
            } else {
                const initial_state = try self.closure(kernel);
                const state_id: u16 = @intCast(self.states.items.len);
                try self.states.append(self.allocator, initial_state);
                try state_map.put(self.allocator, sig, state_id);
                try self.start_states.append(self.allocator, state_id);
            }
        }

        // Process states until no new ones
        var i: usize = 0;
        while (i < self.states.items.len) : (i += 1) {
            try self.processTransitions(i, &state_map);
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
        var all_items: std.ArrayListUnmanaged(ParserItem) = .{};
        var reductions: std.ArrayListUnmanaged(ParserItem) = .{};
        var seen = std.AutoHashMap(u32, void).init(self.allocator);
        defer seen.deinit();

        // Start with kernel items
        for (kernel) |item| {
            try all_items.append(self.allocator, item);
            try seen.put(item.id(), {});
        }

        // Process items, adding closure items as we go
        var work_idx: usize = 0;
        while (work_idx < all_items.items.len) : (work_idx += 1) {
            const item = all_items.items[work_idx];
            const rule = self.rules.items[item.rule_id];

            // Item with dot at end → reduction item
            if (item.dot >= rule.rhs.len) {
                try reductions.append(self.allocator, item);
                continue;
            }

            // If next symbol after dot is nonterminal, add its productions
            const next_sym = rule.rhs[item.dot];
            const symbol = self.symbols.items[next_sym];

            if (symbol.kind == .nonterminal) {
                for (symbol.rules.items) |rule_id| {
                    const new_item = ParserItem{ .rule_id = rule_id, .dot = 0 };
                    if (!seen.contains(new_item.id())) {
                        try seen.put(new_item.id(), {});
                        try all_items.append(self.allocator, new_item);
                    }
                }
            }
        }

        return ParserState{
            .id = @intCast(self.states.items.len),
            .kernel = kernel,
            .items = try all_items.toOwnedSlice(self.allocator),
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
    fn processTransitions(self: *ParserGenerator, state_idx: usize, state_map: *std.StringHashMapUnmanaged(u16)) !void {
        const state = &self.states.items[state_idx];
        var transitions: std.ArrayListUnmanaged(ParserTransition) = .{};

        // Group items by the symbol after the dot
        var symbol_items = std.AutoHashMap(u16, std.ArrayListUnmanaged(ParserItem)).init(self.allocator);
        defer {
            var iter = symbol_items.valueIterator();
            while (iter.next()) |list| list.deinit(self.allocator);
            symbol_items.deinit();
        }

        for (state.items) |item| {
            const rule = self.rules.items[item.rule_id];
            if (item.dot >= rule.rhs.len) continue; // No symbol after dot

            const next_sym = rule.rhs[item.dot];
            const entry = try symbol_items.getOrPut(next_sym);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            // Advance dot: A → α • X β becomes A → α X • β
            try entry.value_ptr.append(self.allocator, .{ .rule_id = item.rule_id, .dot = item.dot + 1 });
        }

        // Create transitions and target states
        var iter = symbol_items.iterator();
        while (iter.next()) |entry| {
            const sym = entry.key_ptr.*;
            const items_list = entry.value_ptr;

            const kernel = try self.allocator.dupe(ParserItem, items_list.items);
            const sig = try self.kernelSignature(kernel);

            // Reuse existing state with same kernel, or create new one
            const target = if (state_map.get(sig)) |existing| existing else blk: {
                const new_state = try self.closure(kernel);
                const new_id: u16 = @intCast(self.states.items.len);
                try self.states.append(self.allocator, new_state);
                try state_map.put(self.allocator, sig, new_id);
                break :blk new_id;
            };

            try transitions.append(self.allocator, .{ .symbol = sym, .target = target });
        }

        self.states.items[state_idx].transitions = try transitions.toOwnedSlice(self.allocator);
    }

    /// Generate a unique signature for a kernel (set of items).
    /// States with identical kernels are merged to avoid duplication.
    fn kernelSignature(self: *ParserGenerator, kernel: []const ParserItem) ![]const u8 {
        var sig: std.ArrayListUnmanaged(u8) = .{};

        const sorted = try self.allocator.dupe(ParserItem, kernel);
        defer self.allocator.free(sorted);

        std.mem.sort(ParserItem, sorted, {}, struct {
            fn lessThan(_: void, a: ParserItem, b: ParserItem) bool {
                if (a.rule_id != b.rule_id) return a.rule_id < b.rule_id;
                return a.dot < b.dot;
            }
        }.lessThan);

        for (sorted, 0..) |item, i| {
            if (i > 0) try sig.append(self.allocator, '|');
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}.{d}", .{ item.rule_id, item.dot }) catch "";
            try sig.appendSlice(self.allocator, slice);
        }

        return try sig.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // FIRST/FOLLOW Set Computation
    // =========================================================================
    //
    // FIRST and FOLLOW sets determine when to reduce in SLR(1) parsing.
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
    // SLR(1) reduces A → α when lookahead ∈ FOLLOW(A).
    //
    // =========================================================================

    fn computeLookaheads(self: *ParserGenerator) !void {
        try self.computeNullable();
        try self.computeFirst();
        try self.computeFollow();
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

                var all_nullable = true;
                for (rule.rhs) |sym_id| {
                    if (!self.symbols.items[sym_id].nullable) {
                        all_nullable = false;
                        break;
                    }
                }

                if (all_nullable or rule.rhs.len == 0) {
                    rule.nullable = true;
                    changed = true;
                }
            }

            for (self.symbols.items) |*sym| {
                if (sym.nullable or sym.kind != .nonterminal) continue;

                for (sym.rules.items) |rule_id| {
                    if (self.rules.items[rule_id].nullable) {
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
                const old_count = rule.firsts.count();
                try self.computeFirstOfSequence(&rule.firsts, rule.rhs);
                if (rule.firsts.count() > old_count) changed = true;
            }

            // Propagate to nonterminals (union of all their rules' FIRST sets)
            for (self.symbols.items) |*sym| {
                if (sym.kind != .nonterminal) continue;

                for (sym.rules.items) |rule_id| {
                    if (try sym.firsts.addAll(self.allocator, &self.rules.items[rule_id].firsts)) {
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
        for (symbols) |sym_id| {
            const sym = &self.symbols.items[sym_id];

            if (sym.kind == .terminal) {
                try result.add(self.allocator, sym_id);
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
                for (rule.rhs, 0..) |sym_id, i| {
                    const sym = &self.symbols.items[sym_id];
                    if (sym.kind != .nonterminal) continue;

                    const old_count = sym.follows.count();

                    if (i == rule.rhs.len - 1) {
                        // A is at end: FOLLOW(LHS) ⊆ FOLLOW(A)
                        if (try sym.follows.addAll(self.allocator, &self.symbols.items[rule.lhs].follows)) {
                            changed = true;
                        }
                    } else {
                        // A has symbols after it: add FIRST(β) to FOLLOW(A)
                        const beta = rule.rhs[i + 1 ..];
                        try self.computeFirstOfSequence(&sym.follows, beta);

                        var beta_nullable = true;
                        for (beta) |b| {
                            if (!self.symbols.items[b].nullable) {
                                beta_nullable = false;
                                break;
                            }
                        }
                        if (beta_nullable) {
                            _ = try sym.follows.addAll(self.allocator, &self.symbols.items[rule.lhs].follows);
                        }
                    }

                    if (sym.follows.count() > old_count) changed = true;
                }
            }
        }
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
    // SLR(1) table construction:
    //   1. SHIFT: If state has A → α • a β (a = terminal), ACTION[state, a] = shift
    //   2. REDUCE: If state has A → α • and a ∈ FOLLOW(A), ACTION[state, a] = reduce
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
        goto_state: u16,
        accept: void,
        err: void,
    };

    /// Build the SLR(1) parse table from the LR(0) automaton and FOLLOW sets.
    fn buildParseTable(self: *ParserGenerator) ![][]ParseAction {
        const num_states = self.states.items.len;
        const num_symbols = self.symbols.items.len;

        const table = try self.allocator.alloc([]ParseAction, num_states);
        for (table, 0..) |*row, i| {
            row.* = try self.allocator.alloc(ParseAction, num_symbols);
            for (row.*) |*cell| cell.* = .err;

            const state = &self.states.items[i];

            // Shift/goto actions
            for (state.transitions) |trans| {
                const sym = &self.symbols.items[trans.symbol];
                if (sym.kind == .nonterminal) {
                    row.*[trans.symbol] = .{ .goto_state = trans.target };
                } else {
                    row.*[trans.symbol] = .{ .shift = trans.target };
                }
            }

            // Accept action
            for (state.items) |item| {
                const rule = &self.rules.items[item.rule_id];
                if (item.dot < rule.rhs.len and rule.rhs[item.dot] == self.end_id) {
                    if (self.isAcceptRuleId(item.rule_id)) {
                        row.*[self.end_id] = .accept;
                    }
                }
            }

            // Reduce actions
            for (state.reductions) |item| {
                const rule = &self.rules.items[item.rule_id];

                if (self.isAcceptRuleId(item.rule_id)) {
                    row.*[self.end_id] = .accept;
                    continue;
                }

                const lhs_sym = &self.symbols.items[rule.lhs];

                for (lhs_sym.follows.slice()) |follow_id| {
                    const current = &row.*[follow_id];
                    const fname = self.symbols.items[follow_id].name;
                    const x_char = if (fname.len == 3) fname[1] else 0;

                    switch (current.*) {
                        .err => current.* = .{ .reduce = item.rule_id },
                        .shift => |s| {
                            if (rule.exclude_char != 0 and x_char == rule.exclude_char) {
                                // X "c": reduce in table, shift at runtime when pre==0
                                current.* = .{ .reduce = item.rule_id };
                                try self.x_excludes.append(self.allocator, .{
                                    .state = @intCast(i),
                                    .char = x_char,
                                    .shift = s,
                                });
                            } else if (rule.prefer_reduce) {
                                // < hint: prefer reduce (tight binding)
                                current.* = .{ .reduce = item.rule_id };
                            } else if (rule.prefer_shift) {
                                // > hint: keep shift
                            } else {
                                // Default: shift wins
                                self.conflicts += 1;
                                try self.conflict_details.append(self.allocator, .{
                                    .kind = .shift_reduce,
                                    .name_a = lhs_sym.name,
                                    .name_b = fname,
                                });
                            }
                        },
                        .reduce => |existing| {
                            if (item.rule_id < existing) {
                                current.* = .{ .reduce = item.rule_id };
                            }
                            self.conflicts += 1;
                            const existing_rule = &self.rules.items[existing];
                            try self.conflict_details.append(self.allocator, .{
                                .kind = .reduce_reduce,
                                .name_a = lhs_sym.name,
                                .name_b = self.symbols.items[existing_rule.lhs].name,
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

    fn generateParserCode(self: *ParserGenerator, lexer_code: []const u8) ![]const u8 {
        var output: std.ArrayListUnmanaged(u8) = .{};
        const writer = output.writer(self.allocator);

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
        const lexer_body = if (std.mem.indexOf(u8, lexer_code, "// =============================================================================")) |pos|
            lexer_code[pos..]
        else
            lexer_code;

        // Write header
        try writer.writeAll(
            \\//! Parser (Auto-generated)
            \\//!
            \\//! Generated by nexus from a .grammar file.
            \\//! Contains both lexer and parser.
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
        for (self.code_blocks.items) |block| {
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
        try writer.writeAll(lexer_body);

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
            for (self.tag_list.items) |tag| {
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
        for (self.code_blocks.items) |block| {
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
            \\// Parser
            \\// =============================================================================
            \\
            \\pub const Parser = struct {
            \\    arena: std.heap.ArenaAllocator,
            \\    lexer: Lexer,
            \\    source: []const u8,
            \\    current: Token,
            \\    injectedToken: ?u16 = null,
            \\    lastMatchedId: u16 = 0,
            \\
            \\    stateStack: std.ArrayListUnmanaged(u16) = .{},
            \\    valueStack: std.ArrayListUnmanaged(Sexp) = .{},
            \\
            \\    pub fn init(backingAllocator: std.mem.Allocator, source: []const u8) Parser {
            \\        var p = Parser{
            \\            .arena = std.heap.ArenaAllocator.init(backingAllocator),
            \\            .lexer = Lexer.init(source),
            \\            .source = source,
            \\            .current = undefined,
            \\        };
            \\        p.current = p.lexer.next();
            \\        return p;
            \\    }
            \\
            \\    pub fn deinit(self: *Parser) void {
            \\        self.arena.deinit();
            \\    }
            \\
            \\    fn allocator(self: *Parser) std.mem.Allocator {
            \\        return self.arena.allocator();
            \\    }
            \\
            \\    pub fn printError(self: *Parser) void {
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
            \\    fn doParse(self: *Parser, startSym: u16) !Sexp {
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
            \\                        .id  = self.lastMatchedId,
            \\                    } });
            \\                    self.lastMatchedId = 0;
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
            \\    fn spreadList(self: *Parser, head: Sexp, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .{};
            \\        out.append(self.allocator(), head) catch return .nil;
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Spread only: [...tail]
            \\    fn spreadOnly(self: *Parser, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .{};
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Default list handler
            \\    fn list(self: *Parser, pass: []Sexp) Sexp {
            \\        if (pass.len == 0) return .nil;
            \\        if (pass.len == 1) return pass[0];
            \\        var out: std.ArrayListUnmanaged(Sexp) = .{};
            \\        for (pass) |v| out.append(self.allocator(), v) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Build S-expression: (tag items...) with trailing nil trimming
            \\    inline fn sexp(self: *Parser, comptime tag: Tag, items: []const Sexp) Sexp {
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
            \\    inline fn sexpSpread(self: *Parser, comptime tag: Tag, spread: Sexp) Sexp {
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
            \\    inline fn sexpPosSpread(self: *Parser, comptime tag: Tag, pos: Sexp, spread: Sexp) Sexp {
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
            \\    fn executeAction(self: *Parser, ruleId: u16, pass: []Sexp) Sexp {
            \\        return switch (ruleId) {
            \\
        );

        // Generate per-rule semantic actions
        for (self.rules.items, 0..) |rule, rule_idx| {
            try writer.print("            {d} => ", .{rule_idx});
            try self.generateRuleAction(writer, rule);
            try writer.writeAll(",\n");
        }

        try writer.writeAll(
            \\            else => .nil,
            \\        };
            \\    }
            \\
            \\    fn tokenToSymbol(self: *Parser, token: Token) u16 {
            \\        return switch (token.cat) {
            \\
        );

        // Generate token to symbol mapping
        try writer.print("            .@\"eof\" => {d},\n", .{self.end_id});
        var emitted_cats: std.StringHashMapUnmanaged(void) = .{};
        defer {
            var it = emitted_cats.keyIterator();
            while (it.next()) |key| self.allocator.free(key.*);
            emitted_cats.deinit(self.allocator);
        }

        // Check if we have @as directives for "ident" - if so, route through identToSymbol
        var has_ident_as = false;
        for (self.as_directives.items) |directive| {
            if (std.mem.eql(u8, directive.token, "ident")) {
                has_ident_as = true;
                break;
            }
        }
        if (has_ident_as) {
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
                var lower_buf: [64]u8 = undefined;
                var len: usize = 0;
                for (sym.name) |c| {
                    if (len >= lower_buf.len) break;
                    lower_buf[len] = if (c >= 'A' and c <= 'Z') c + 32 else c;
                    len += 1;
                }
                const lower_name = lower_buf[0..len];

                // Skip ident if we're routing through identToSymbol
                if (has_ident_as and std.mem.eql(u8, lower_name, "ident")) continue;

                // Determine if this terminal is an @as keyword (handled by identToSymbol)
                // vs a real lexer token (needs tokenToSymbol mapping).
                var is_as_keyword = false;
                if (sym.name[0] >= 'A' and sym.name[0] <= 'Z') {
                    // Check if there's a corresponding lowercase nonterminal (e.g., IF↔if)
                    for (self.symbols.items) |other| {
                        if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                            is_as_keyword = true;
                            break;
                        }
                    }
                    // Check if it matches an @as directive rule name (e.g., CMD↔cmd)
                    if (!is_as_keyword) {
                        for (self.as_directives.items) |directive| {
                            var upper_buf: [64]u8 = undefined;
                            const upper_rule = std.ascii.upperString(upper_buf[0..directive.rule.len], directive.rule);
                            if (std.mem.eql(u8, sym.name, upper_rule)) {
                                is_as_keyword = true;
                                break;
                            }
                        }
                    }
                    // When @as directives exist: if this terminal has no matching
                    // lexer token, it must be a keyword terminal (e.g., IF, UNLESS)
                    if (!is_as_keyword and has_ident_as) {
                        if (self.lexer_spec) |spec| {
                            var has_lexer_token = false;
                            for (spec.tokens.items) |tok| {
                                if (std.ascii.eqlIgnoreCase(tok.name, sym.name)) {
                                    has_lexer_token = true;
                                    break;
                                }
                            }
                            if (!has_lexer_token) {
                                for (spec.rules.items) |rule| {
                                    if (std.ascii.eqlIgnoreCase(rule.token, sym.name)) {
                                        has_lexer_token = true;
                                        break;
                                    }
                                }
                            }
                            if (!has_lexer_token) is_as_keyword = true;
                        }
                    }
                }

                // Skip @as keywords - they're handled by identToSymbol
                if (is_as_keyword) continue;

                // Only generate for tokens that look like lexer token types (start with letter, no special chars)
                var valid = len > 0 and lower_name[0] >= 'a' and lower_name[0] <= 'z';
                if (valid) {
                    for (lower_name) |ch| {
                        if (!((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_')) {
                            valid = false;
                            break;
                        }
                    }
                }
                if (valid and !emitted_cats.contains(lower_name)) {
                    try writer.print("            .@\"{s}\" => {d},\n", .{ lower_name, sym.id });
                    try emitted_cats.put(self.allocator, try self.allocator.dupe(u8, lower_name), {});
                }
            }
        }

        // Generate @op mappings for operator literals (e.g., "'=" => noteq)
        for (self.symbols.items) |sym| {
            if (sym.kind == .terminal and sym.name.len >= 2 and sym.name[0] == '"') {
                const raw_literal = sym.name[1 .. sym.name.len - 1];
                // Unescape the literal (handle \\ -> \)
                var literal_buf: [256]u8 = undefined;
                var literal_len: usize = 0;
                var i: usize = 0;
                while (i < raw_literal.len) : (i += 1) {
                    if (raw_literal[i] == '\\' and i + 1 < raw_literal.len) {
                        i += 1;
                        literal_buf[literal_len] = raw_literal[i];
                    } else {
                        literal_buf[literal_len] = raw_literal[i];
                    }
                    literal_len += 1;
                }
                const literal = literal_buf[0..literal_len];
                // Look up in @op mappings
                for (self.op_mappings.items) |m| {
                    if (std.mem.eql(u8, literal, m.lit) and !emitted_cats.contains(m.tok)) {
                        try writer.print("            .@\"{s}\" => {d},\n", .{ m.tok, sym.id });
                        try emitted_cats.put(self.allocator, try self.allocator.dupe(u8, m.tok), {});
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
                if (self.lexer_spec) |spec| {
                    if (findTokenForChar(spec, c)) |tok_name| {
                        if (!emitted_cats.contains(tok_name)) {
                            try writer.print("            .@\"{s}\" => {d},\n", .{ tok_name, sym.id });
                            try emitted_cats.put(self.allocator, try self.allocator.dupe(u8, tok_name), {});
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
            if (self.lexer_spec) |spec| {
                if (findTokenForLiteral(spec, raw)) |tok_name| {
                    if (!emitted_cats.contains(tok_name)) {
                        try writer.print("            .@\"{s}\" => {d},\n", .{ tok_name, sym.id });
                        try emitted_cats.put(self.allocator, try self.allocator.dupe(u8, tok_name), {});
                    }
                }
            }
        }

        try writer.print(
            \\            else => {d}, // error
            \\        }};
            \\    }}
            \\
        , .{self.error_id});

        // Generate identToSymbol based on @as directives
        if (self.as_directives.items.len > 0) {
            try writer.writeAll(
                \\
                \\    fn identToSymbol(self: *Parser, token: Token) u16 {
                \\        const text = self.source[token.pos..][0..token.len];
                \\        if (text.len == 0) return symIdent;
                \\
            );

            // Eager promotion: try all @as directives uniformly.
            // Parser action table disambiguates (keyword only promoted when
            // the parser state has a valid action for it).
            for (self.as_directives.items) |directive| {
                if (std.mem.eql(u8, directive.token, "ident")) {
                    const cap = capitalized(directive.rule);
                    const cap_name = cap[0..directive.rule.len];
                    try writer.print("        if (self.tryIdentAs{s}(token, text)) |sym| return sym;\n", .{cap_name});
                }
            }

            try writer.writeAll(
                \\        return symIdent;
                \\    }
                \\
            );

            // Generate try_ident_as_* functions for each @as directive
            if (self.lang) |lang_name| {
                // External module: reference lang.{rule}As(), lang.{Rule}Id, etc.
                for (self.as_directives.items) |directive| {
                    if (!std.mem.eql(u8, directive.token, "ident")) continue;

                    const cap = capitalized(directive.rule);
                    const cap_name = cap[0..directive.rule.len];
                    try writer.print(
                        \\
                        \\    fn tryIdentAs{s}(self: *Parser, token: Token, text: []const u8) ?u16 {{
                        \\        _ = token;
                        \\        const state = self.stateStack.getLast();
                        \\        if ({s}.{s}As(text)) |id| {{
                        \\            const idIdx = @intFromEnum(id);
                        \\            const sym = {s}ToSymbol[idIdx];
                        \\            if (sym != 0 and getAction(state, sym) != 0) {{
                        \\                self.lastMatchedId = @intCast(idIdx);
                        \\                return sym;
                        \\            }}
                        \\            const fallback = {s}FallbackSymbol;
                        \\            if (fallback != 0 and getAction(state, fallback) != 0) {{
                        \\                self.lastMatchedId = @intCast(idIdx);
                        \\                return fallback;
                        \\            }}
                        \\        }}
                        \\        return null;
                        \\    }}
                        \\
                    , .{ cap_name, lang_name, directive.rule, directive.rule, directive.rule });
                }
            } else {
                // Inline: generate simple exact-match keyword functions
                for (self.as_directives.items) |directive| {
                    if (!std.mem.eql(u8, directive.token, "ident")) continue;

                    const cap = capitalized(directive.rule);
                    const cap_name = cap[0..directive.rule.len];
                    try writer.print(
                        \\
                        \\    fn tryIdentAs{s}(self: *Parser, token: Token, text: []const u8) ?u16 {{
                        \\        _ = token;
                        \\        const state = self.stateStack.getLast();
                        \\        if ({s}As(text)) |id| {{
                        \\            const sym = {s}ToSymbol[@intFromEnum(id)];
                        \\            if (sym != 0 and getAction(state, sym) != 0) {{
                        \\                self.lastMatchedId = @intFromEnum(id);
                        \\                return sym;
                        \\            }}
                        \\        }}
                        \\        return null;
                        \\    }}
                        \\
                    , .{ cap_name, directive.rule, directive.rule });
                }
            }
        } else {
            // No @as directives - simple passthrough
            try writer.writeAll(
                \\
                \\    fn identToSymbol(_: *Parser, _: Token) u16 {
                \\        return symIdent;
                \\    }
                \\
            );
        }

        // Generate parse functions for each start symbol
        for (self.start_symbols.items) |sym_id| {
            const name = self.symbols.items[sym_id].name;
            var fname_buf: [64]u8 = undefined;
            fname_buf[0] = if (name[0] >= 'a' and name[0] <= 'z') name[0] - 32 else name[0];
            @memcpy(fname_buf[1..name.len], name[1..]);
            const fname = fname_buf[0..name.len];

            try writer.print(
                \\
                \\    pub fn parse{s}(self: *Parser) !Sexp {{
                \\        self.injectedToken = SYM_{s}_START;
                \\        return self.doParse(SYM_{s});
                \\    }}
            , .{ fname, name, name });
        }

        // Inject @code parser blocks
        for (self.code_blocks.items) |block| {
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

        // Generate symbol constants
        try writer.writeAll("// Symbol IDs\n");
        for (self.start_symbols.items) |sym_id| {
            const name = self.symbols.items[sym_id].name;
            try writer.print("const SYM_{s}: u16 = {d};\n", .{ name, sym_id });
            // Marker token
            const marker_name = try std.fmt.allocPrint(self.allocator, "{s}!", .{name});
            defer self.allocator.free(marker_name);
            if (self.getSymbol(marker_name)) |marker_id| {
                try writer.print("const SYM_{s}_START: u16 = {d};\n", .{ name, marker_id });
            }
        }

        // Generate SYM_IDENT for identToSymbol fallback
        if (self.getSymbol("IDENT")) |ident_id| {
            try writer.print("const symIdent: u16 = {d};\n", .{ident_id});
        } else {
            // Fallback to error symbol if IDENT not defined
            try writer.print("const symIdent: u16 = {d};\n", .{self.error_id});
        }

        // Generate *_to_symbol mapping arrays and keyword matchers for @as directives
        if (self.lang) |lang_name| {
            // External module: reference lang.{Rule}Id, lang.{rule}As, etc.
            for (self.as_directives.items) |directive| {
                var specific_terminals: std.ArrayListUnmanaged(struct { name: []const u8, id: u16 }) = .{};
                defer specific_terminals.deinit(self.allocator);

                // Collect ALL uppercase terminals as potential keyword targets.
                // @hasField at comptime filters to those in the lang module's enum.
                for (self.symbols.items) |sym| {
                    if (sym.kind != .terminal or sym.name.len == 0) continue;
                    if (sym.name[0] < 'A' or sym.name[0] > 'Z') continue;
                    if (sym.name[0] == '"') continue;
                    if (std.mem.endsWith(u8, sym.name, "!")) continue;
                    try specific_terminals.append(self.allocator, .{ .name = sym.name, .id = sym.id });
                }

                var fallback_name_buf: [64]u8 = undefined;
                const fallback_name = std.ascii.upperString(fallback_name_buf[0..directive.rule.len], directive.rule);
                var fallback_id: ?u16 = null;
                for (self.symbols.items) |sym| {
                    if (sym.kind == .terminal and std.mem.eql(u8, sym.name, fallback_name)) {
                        fallback_id = sym.id;
                        break;
                    }
                }

                const has_mappings = specific_terminals.items.len > 0;
                const has_fallback = fallback_id != null;
                const needs_var = has_mappings or has_fallback;

                const cap = capitalized(directive.rule);
                const cap_name = cap[0..directive.rule.len];
                try writer.print(
                    \\
                    \\// Mapping from {s}.{s}Id to grammar symbol IDs (computed at comptime)
                    \\const {s}ToSymbol = blk: {{
                    \\
                , .{ lang_name, cap_name, directive.rule });

                if (needs_var) {
                    try writer.writeAll("    var arr: [512]u16 = .{0} ** 512;\n");
                } else {
                    try writer.writeAll("    const arr: [512]u16 = .{0} ** 512;\n");
                }

                for (specific_terminals.items) |term| {
                    try writer.print("    if (@hasField({s}.{s}Id, \"{s}\")) arr[@intFromEnum({s}.{s}Id.{s})] = {d};\n", .{ lang_name, cap_name, term.name, lang_name, cap_name, term.name, term.id });
                }

                if (fallback_id) |fid| {
                    try writer.print(
                        \\    for (@typeInfo({s}.{s}Id).@"enum".fields) |field| {{
                        \\        if (arr[field.value] == 0) arr[field.value] = {d};
                        \\    }}
                        \\
                    , .{ lang_name, cap_name, fid });
                }

                try writer.writeAll("    break :blk arr;\n};\n");
                try writer.print("const {s}FallbackSymbol: u16 = {d};\n", .{ directive.rule, fallback_id orelse 0 });
            }
        } else {
            // Inline: generate Id enums, As functions, and ToSymbol mappings
            var emitted_rules = std.StringHashMap(void).init(self.allocator);
            defer emitted_rules.deinit();

            for (self.as_directives.items) |directive| {
                if (emitted_rules.contains(directive.rule)) continue;
                emitted_rules.put(directive.rule, {}) catch {};

                var upper_buf: [64]u8 = undefined;
                const upper = std.ascii.upperString(upper_buf[0..directive.rule.len], directive.rule);
                const cap = capitalized(directive.rule);
                const cap_name = cap[0..directive.rule.len];
                try writer.print("\nconst {s}Id = enum(u16) {{ {s} = 0 }};\n", .{ cap_name, upper });
                try writer.print("fn {s}As(name: []const u8) ?{s}Id {{ return if (std.mem.eql(u8, name, \"{s}\")) .{s} else null; }}\n", .{ directive.rule, cap_name, directive.rule, upper });
            }

            for (self.as_directives.items) |directive| {
                var specific_terminals: std.ArrayListUnmanaged(struct { name: []const u8, id: u16 }) = .{};
                defer specific_terminals.deinit(self.allocator);

                for (self.symbols.items) |sym| {
                    if (sym.kind != .terminal or sym.name.len == 0) continue;
                    if (sym.name[0] < 'A' or sym.name[0] > 'Z') continue;
                    if (sym.name[0] == '"') continue;
                    for (self.symbols.items) |other| {
                        if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                            try specific_terminals.append(self.allocator, .{ .name = sym.name, .id = sym.id });
                            break;
                        }
                    }
                }

                var fallback_name_buf: [64]u8 = undefined;
                const fallback_name = std.ascii.upperString(fallback_name_buf[0..directive.rule.len], directive.rule);
                var fallback_id: ?u16 = null;
                for (self.symbols.items) |sym| {
                    if (sym.kind == .terminal and std.mem.eql(u8, sym.name, fallback_name)) {
                        fallback_id = sym.id;
                        break;
                    }
                }

                const has_mappings = specific_terminals.items.len > 0;
                const has_fallback = fallback_id != null;
                const needs_var = has_mappings or has_fallback;

                const cap2 = capitalized(directive.rule);
                const cap_name2 = cap2[0..directive.rule.len];
                try writer.print(
                    \\
                    \\const {s}ToSymbol = blk: {{
                    \\
                , .{directive.rule});

                if (needs_var) {
                    try writer.writeAll("    var arr: [512]u16 = .{0} ** 512;\n");
                } else {
                    try writer.writeAll("    const arr: [512]u16 = .{0} ** 512;\n");
                }

                for (specific_terminals.items) |term| {
                    try writer.print("    if (@hasField({s}Id, \"{s}\")) arr[@intFromEnum({s}Id.{s})] = {d};\n", .{ cap_name2, term.name, cap_name2, term.name, term.id });
                }

                if (fallback_id) |fid| {
                    try writer.print(
                        \\    for (@typeInfo({s}Id).@"enum".fields) |field| {{
                        \\        if (arr[field.value] == 0) arr[field.value] = {d};
                        \\    }}
                        \\
                    , .{ cap_name2, fid });
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
        const num_states = table.len;
        const num_symbols = self.symbols.items.len;

        try writer.print(
            \\
            \\// Parse Table: {d} states × {d} symbols
            \\const numStates = {d};
            \\const numSymbols = {d};
            \\
            \\const sparse = [numStates][]const i16{{
            \\
        , .{ num_states, num_symbols, num_states, num_symbols });

        for (table) |row| {
            try writer.writeAll("    &.{");
            var first = true;
            for (row, 0..) |action, sym| {
                const value: i16 = switch (action) {
                    .shift => |s| @as(i16, @intCast(s)),
                    .reduce => |r| -@as(i16, @intCast(r)) - 2,
                    .goto_state => |g| @as(i16, @intCast(g)),
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
        for (self.x_excludes.items) |x| {
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
        for (self.start_symbols.items, self.start_states.items) |sym, state| {
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
        for (self.accept_rules.items, 0..) |rule_id, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{rule_id});
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
        for (self.code_blocks.items) |block| {
            if (std.mem.eql(u8, block.location, "bottom")) {
                try writer.writeAll("\n// === @code bottom ===\n");
                try writer.writeAll(block.code);
                try writer.writeAll("\n");
            }
        }

        return try output.toOwnedSlice(self.allocator);
    }

    fn generateRuleAction(self: *ParserGenerator, writer: anytype, rule: ParserRule) !void {
        if (rule.action == null) {
            try writer.writeAll("self.list(pass)");
            return;
        }

        const template = rule.action.?.template;
        const offset = rule.action_offset;

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
        var elements: std.ArrayListUnmanaged([]const u8) = .{};
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
        var tag_name = tag;

        // Strip key:value from tag if present (e.g., "dots:2?" -> "dots")
        if (std.mem.indexOfScalar(u8, tag, ':')) |colon_pos| {
            const after = tag[colon_pos + 1 ..];
            if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                after[0] == '.' or after[0] == '~' or after[0] == '_'))
            {
                tag_name = tag[0..colon_pos];
            }
        }

        const first_is_tag = self.isTagLiteral(tag_name);

        // Count element types
        var spread_count: usize = 0;
        var spread_pos: u8 = 0;
        var pos_count: usize = 0;
        var first_pos: u8 = 0;
        var has_tilde = false;
        var has_other = false;
        var has_nil = false;

        for (elements.items[1..]) |elem| {
            const work = self.stripKeyAndSuffix(elem);
            if (work.len == 0) continue;
            if (work[0] == '.' and work.len >= 4 and work[1] == '.' and work[2] == '.') {
                spread_count += 1;
                spread_pos = work[3] - '1' + offset;
            } else if (work[0] == '~') {
                has_tilde = true;
            } else if (work[0] >= '1' and work[0] <= '9') {
                if (pos_count == 0) first_pos = work[0] - '1' + offset;
                pos_count += 1;
            } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
                has_nil = true; // track nil separately for pattern matching
            } else if (!self.isTagLiteral(work)) {
                has_other = true;
            }
        }

        // Pattern: (tag ...N) - use sexpSpread (only if no nil elements)
        if (first_is_tag and spread_count == 1 and pos_count == 0 and !has_tilde and !has_other and !has_nil) {
            try writer.print("self.sexpSpread(.@\"{s}\", pass[{d}])", .{ tag_name, spread_pos });
            return;
        }

        // Pattern: (tag N ...M) - use sexpPosSpread (only if no nil elements)
        if (first_is_tag and spread_count == 1 and pos_count == 1 and !has_tilde and !has_other and !has_nil) {
            try writer.print("self.sexpPosSpread(.@\"{s}\", pass[{d}], pass[{d}])", .{ tag_name, first_pos, spread_pos });
            return;
        }

        // Simple case: self.sexp(.@"tag", &.{pass[0], pass[1], ...})
        // Only if first element is a tag and no spreads/tilde
        var tag_has_value = false;
        var tag_value: []const u8 = "";

        // Check if tag has key:value format (like "dots:2?", "type:_")
        if (std.mem.indexOfScalar(u8, tag, ':')) |colon_pos| {
            const after = tag[colon_pos + 1 ..];
            if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                after[0] == '.' or after[0] == '~' or after[0] == '_'))
            {
                tag_has_value = true;
                tag_value = self.stripKeyAndSuffix(tag);
            }
        }

        if (first_is_tag and spread_count == 0 and !has_tilde and !has_other) {
            try writer.print("self.sexp(.@\"{s}\", &.{{", .{tag_name});
            var first = true;

            // Add tag's value if it had key:value format
            if (tag_has_value and tag_value.len > 0) {
                if (tag_value[0] >= '1' and tag_value[0] <= '9') {
                    try writer.print("pass[{d}]", .{tag_value[0] - '1' + offset});
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
        try writer.writeAll("blk: { var out: std.ArrayListUnmanaged(Sexp) = .{}; ");
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
        if (std.mem.indexOfScalar(u8, work, ':')) |colon_pos| {
            const after = work[colon_pos + 1 ..];
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
        if (!self.collected_tags.contains(tag)) {
            const owned = try self.allocator.dupe(u8, tag);
            try self.collected_tags.put(self.allocator, owned, @intCast(self.tag_list.items.len));
            try self.tag_list.append(self.allocator, owned);
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
                if (std.mem.indexOfScalar(u8, tag, ':')) |colon_pos| {
                    const after = tag[colon_pos + 1 ..];
                    if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                        after[0] == '.' or after[0] == '~'))
                    {
                        tag = tag[0..colon_pos];
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
    if (pg.conflict_details.items.len == 0) {
        if (pg.expect_conflicts) |expected| {
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

    for (pg.conflict_details.items) |c| {
        const a = c.name_a;
        const b = c.name_b;
        const is_benign = (c.kind == .reduce_reduce and isAutoGen(a) and isAutoGen(b)) or
            (c.kind == .shift_reduce and isAutoGen(a));
        if (is_benign) {
            benign += 1;
        } else {
            var buf: [256]u8 = undefined;
            const key_tag: []const u8 = if (c.kind == .shift_reduce) "S/R" else "R/R";
            const key = std.fmt.bufPrint(&buf, "{s}: {s} vs {s}", .{ key_tag, a, b }) catch continue;
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
    if (pg.expect_conflicts) |expected| {
        if (total == expected) {
            std.debug.print("   ✅ {d} conflicts (as expected)\n", .{total});
        } else {
            std.debug.print("   ⚠️  {d} conflicts (expected {d} — update @conflicts)\n", .{ total, expected });
        }
    } else if (total > 0) {
        std.debug.print("   ⚠️  {d} conflicts detected (add @conflicts = {d} to suppress if ok)\n", .{ total, total });
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: grammar <grammar-file> [output-file]\n", .{});
        std.debug.print("       grammar --help\n", .{});
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
            \\
            \\Options:
            \\  -h, --help     Show this help
            \\
            \\Examples:
            \\  grammar lang.grammar src/parser.zig
            \\
        , .{});
        return;
    }

    const grammar_file = args[1];
    const output_file = if (args.len > 2) args[2] else "src/parser.zig";

    // Read grammar file
    const source = std.fs.cwd().readFileAlloc(allocator, grammar_file, 1024 * 1024) catch |err| {
        std.debug.print("Error reading {s}: {any}\n", .{ grammar_file, err });
        return;
    };
    defer allocator.free(source);

    std.debug.print("📖 Reading grammar from {s}\n", .{grammar_file});

    // Find @lexer section
    const lexer_start = std.mem.indexOf(u8, source, "@lexer");
    if (lexer_start == null) {
        std.debug.print("❌ No @lexer section found in {s}\n", .{grammar_file});
        return;
    }

    // Parse lexer section
    var lexer_parser = LexerParser.init(allocator, source[lexer_start.? + 6 ..]);
    defer lexer_parser.deinit();

    lexer_parser.parseLexerSection() catch |err| {
        std.debug.print("❌ Lexer parse error at line {d}: {any}\n", .{ lexer_parser.line, err });
        return;
    };

    std.debug.print("   Lexer: {d} states, {d} tokens, {d} rules\n", .{
        lexer_parser.spec.states.items.len,
        lexer_parser.spec.tokens.items.len,
        lexer_parser.spec.rules.items.len,
    });

    // Pre-scan for @lang directive (needed by lexer generator for @code imports)
    // Matches @lang at start of file or after a newline
    const lang_pos = std.mem.indexOf(u8, source, "\n@lang") orelse
        if (source.len >= 5 and std.mem.eql(u8, source[0..5], "@lang")) @as(?usize, 0) else null;
    if (lang_pos) |pos| {
        var i = pos + if (pos == 0) @as(usize, 5) else @as(usize, 6);
        while (i < source.len and (source[i] == ' ' or source[i] == '=' or source[i] == '\t')) : (i += 1) {}
        if (i < source.len and source[i] == '"') {
            i += 1;
            const name_start = i;
            while (i < source.len and source[i] != '"') : (i += 1) {}
            if (i < source.len) lexer_parser.spec.lang_name = source[name_start..i];
        }
    }

    // Generate lexer code
    var lexer_gen = LexerGenerator.init(allocator, &lexer_parser.spec);
    defer lexer_gen.deinit();

    const lexer_code = lexer_gen.generate() catch |err| {
        std.debug.print("❌ Lexer generation error: {any}\n", .{err});
        return;
    };
    defer allocator.free(lexer_code);

    // Find @parser section
    const parser_start = std.mem.indexOf(u8, source, "@parser");
    var final_code: []const u8 = lexer_code;
    var parser_gen: ?ParserGenerator = null;

    if (parser_start) |ps| {
        std.debug.print("   Parsing @parser section...\n", .{});

        // Parse parser section
        var parser_dsl = ParserDSLParser.init(allocator, source[ps + 7 ..]);
        defer parser_dsl.deinit();

        parser_dsl.parse() catch |err| {
            std.debug.print("❌ Parser parse error: {any}\n", .{err});
            return;
        };

        // Propagate @lang from pre-scan if not set in @parser section
        if (parser_dsl.lang == null) {
            parser_dsl.lang = lexer_parser.spec.lang_name;
        }

        std.debug.print("   Parser: {d} rules, {d} start symbols\n", .{
            parser_dsl.rules.items.len,
            parser_dsl.start_symbols.items.len,
        });

        // Only generate parser if there are rules
        if (parser_dsl.rules.items.len > 0) {
            // Generate parser
            parser_gen = ParserGenerator.init(allocator);
            parser_gen.?.lexer_spec = &lexer_parser.spec;

            parser_gen.?.processGrammar(&parser_dsl) catch |err| {
                std.debug.print("❌ Grammar processing error: {any}\n", .{err});
                return;
            };

            // Validate all referenced symbols are defined
            const validation_errors = parser_gen.?.validateSymbols(&lexer_parser.spec);
            if (validation_errors > 0) {
                std.debug.print("❌ Found {d} undefined symbol(s)\n", .{validation_errors});
                return;
            }

            parser_gen.?.buildAutomaton() catch |err| {
                std.debug.print("❌ Automaton build error: {any}\n", .{err});
                return;
            };

            parser_gen.?.computeLookaheads() catch |err| {
                std.debug.print("❌ Lookahead computation error: {any}\n", .{err});
                return;
            };

            std.debug.print("   Generated: {d} symbols, {d} rules, {d} states\n", .{
                parser_gen.?.symbols.items.len,
                parser_gen.?.rules.items.len,
                parser_gen.?.states.items.len,
            });

            // Generate combined code (builds parse table, detects conflicts)
            final_code = parser_gen.?.generateParserCode(lexer_code) catch |err| {
                std.debug.print("❌ Parser generation error: {any}\n", .{err});
                return;
            };

            reportConflicts(&parser_gen.?);
        }
    }

    defer if (parser_gen) |*pg| {
        pg.deinit();
        if (final_code.ptr != lexer_code.ptr) {
            allocator.free(final_code);
        }
    };

    // Write output
    const file = std.fs.cwd().createFile(output_file, .{}) catch |err| {
        std.debug.print("Error creating {s}: {any}\n", .{ output_file, err });
        return;
    };
    defer file.close();

    try file.writeAll(final_code);

    std.debug.print("✅ Generated: {s}\n", .{output_file});
}
