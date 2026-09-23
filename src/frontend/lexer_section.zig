//! Hand-written parser for the `@lexer` section of a .grammar file.
//!
//! Line-oriented scanner that fills a grammar.LexerSpec: `state`, `after`
//! and `tokens` blocks, lexer-section `@code`, and rules of the form
//! `pattern [@ guards] -> token[, action]*`. Patterns are kept as raw text.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const LexerSpec = grammar.LexerSpec;
const Guard = grammar.Guard;
const Action = grammar.Action;

pub const LexerParser = struct {
    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    spec: LexerSpec,

    pub fn init(allocator: Allocator, source: []const u8) LexerParser {
        return .{
            .allocator = allocator,
            .source = source,
            .spec = LexerSpec.init(allocator),
        };
    }

    pub fn deinit(self: *LexerParser) void {
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
    pub fn parseLexerSection(self: *LexerParser) !void {
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

            // `after` block: parsed for syntax only; the generated lexer
            // clears a `beg` state variable itself (see generateMatchRules).
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
            _ = name;
            _ = self.parseInt() orelse return error.ExpectedValue;
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
