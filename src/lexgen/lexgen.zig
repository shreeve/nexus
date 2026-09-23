//! Lexer code generation: turns a grammar.LexerSpec into the Zig source of
//! `TokenCat`, `Token`, and the `Lexer`/`BaseLexer` struct with its
//! `matchRules()` dispatch. Rule behavior is recognized from pattern shapes
//! (see patterns.zig); emission is split across operators.zig and
//! scanners.zig.

const std = @import("std");
const grammar = @import("../grammar.zig");
const LexerSpec = grammar.LexerSpec;
const Guard = grammar.Guard;
const Action = grammar.Action;
const Allocator = std.mem.Allocator;
const patterns = @import("patterns.zig");
const operators = @import("operators.zig");
const scanners = @import("scanners.zig");

pub const LexerGenerator = struct {
    allocator: Allocator,
    spec: *const LexerSpec,
    output: std.Io.Writer.Allocating,

    // Rules whose tokenization is emitted at the top of matchRules by
    // generateMultiCharLiteralPreemption. generateOperatorSwitch skips
    // these so the same multi-char literal isn't handled twice.
    preemptedRules: std.ArrayListUnmanaged(usize) = .empty,

    pub fn init(allocator: Allocator, spec: *const LexerSpec) LexerGenerator {
        return .{
            .allocator = allocator,
            .spec = spec,
            .output = .init(allocator),
        };
    }

    pub fn deinit(self: *LexerGenerator) void {
        self.output.deinit();
        self.preemptedRules.deinit(self.allocator);
    }

    pub fn isRulePreempted(self: *const LexerGenerator, ruleIndex: usize) bool {
        for (self.preemptedRules.items) |idx| {
            if (idx == ruleIndex) return true;
        }
        return false;
    }

    pub fn write(self: *LexerGenerator, s: []const u8) !void {
        try self.output.writer.writeAll(s);
    }

    pub fn print(self: *LexerGenerator, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer.print(fmt, args);
    }

    pub fn emitGuardCondition(self: *LexerGenerator, guard: Guard) !void {
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

    pub fn emitAllGuards(self: *LexerGenerator, guards: []const Guard) !void {
        for (guards, 0..) |guard, i| {
            if (i > 0) try self.write(" and ");
            try self.emitGuardCondition(guard);
        }
    }

    pub fn emitActions(self: *LexerGenerator, actions: []const Action, indent: []const u8) !void {
        for (actions) |action| {
            try self.write(indent);
            switch (action.kind) {
                .set => try self.print("self.{s} = {d};\n", .{ action.variable.?, action.value.? }),
                .inc => try self.print("self.{s} += 1;\n", .{action.variable.?}),
                .dec => try self.print("self.{s} -= 1;\n", .{action.variable.?}),
                .counted => {
                    const ch = patterns.charToZigLiteral(action.char.?);
                    try self.print("{{ var count: u8 = 0; while (self.pos < self.source.len and self.source[self.pos] == {s}) {{ self.pos += 1; count +|= 1; while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) self.pos += 1; }} self.{s} = count; }}\n", .{ ch.buf[0..ch.len], action.variable.? });
                },
            }
        }
    }

    pub fn emitTokenReturn(self: *LexerGenerator, keyword: []const u8, token: []const u8, charCount: u8) !void {
        try self.print("                    {s} Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ keyword, token, charCount });
    }

    /// Find the state variable that complex rules set for a given character.
    /// Used to determine which state variable an @code function affects.
    fn findCodeFnStateVar(self: *LexerGenerator, firstChar: u8) ?[]const u8 {
        for (self.spec.rules.items) |rule| {
            if (patterns.parseLiteralPattern(rule.pattern) != null) continue;
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

    pub fn emitCharSetCondition(self: *LexerGenerator, chars: [256]bool, varName: []const u8) !void {
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
                const lit = patterns.charToZigLiteral(rng.lo);
                try self.print("{s} == '{s}'", .{ varName, lit.buf[0..lit.len] });
            } else {
                const loLit = patterns.charToZigLiteral(rng.lo);
                const hiLit = patterns.charToZigLiteral(rng.hi);
                try self.print("({s} >= '{s}' and {s} <= '{s}')", .{ varName, loLit.buf[0..loLit.len], varName, hiLit.buf[0..hiLit.len] });
            }
        }
    }

    /// The lexer's declarations: TokenCat, Token, the lexer struct, and the
    /// Lexer alias, with no module header or imports (codegen.zig composes
    /// them into the generated module).
    pub fn generateDecls(self: *LexerGenerator) ![]const u8 {
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
        try scanners.generateCharClassification(self);

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

        try scanners.generateNewlineHandling(self);

        // Generate empty-pattern guard rules (zero-width tokens based on state)
        try scanners.generateEmptyPatternGuards(self);

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
        try operators.generateMultiCharLiteralPreemption(self);

        try scanners.generateScannerDispatch(self);

        try scanners.generateCommentHandling(self);

        try operators.generateOperatorSwitch(self);

        try scanners.generateScanners(self);
    }
};
