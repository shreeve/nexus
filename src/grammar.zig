//! Grammar data shared by every stage of the generator.
//!
//!   - Lexer spec: the parsed `@lexer` section (state vars, tokens, rules).
//!   - Grammar IR: the lowered `@parser` section (rules, alternatives,
//!     elements, directives), produced by frontend/lower.zig.
//!   - Symbols and rules: the desugared BNF grammar the LR stages consume.

const std = @import("std");
const Allocator = std.mem.Allocator;

// =============================================================================
// Lexer spec (the @lexer section)
// =============================================================================

/// State variable declaration
pub const StateVar = struct {
    name: []const u8,
    initialValue: i32,
};

/// Token type name
pub const TokenDef = struct {
    name: []const u8,
};

/// Guard condition
pub const Guard = struct {
    variable: []const u8,
    op: Op,
    value: i32,
    negated: bool = false,

    pub const Op = enum {
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
pub const Action = struct {
    kind: Kind,
    variable: ?[]const u8 = null,
    value: ?i32 = null,
    char: ?u8 = null,

    pub const Kind = enum {
        set, // {var = val}
        inc, // {var++}
        dec, // {var--}
        counted, // {var = counted('x')}
    };
};

/// Lexer rule
pub const LexerRule = struct {
    pattern: []const u8,
    guards: []const Guard,
    token: []const u8,
    actions: []const Action,
    isSimd: bool = false,
    simdChar: ?u8 = null,
    isSkip: bool = false,
};

/// Complete lexer specification
pub const LexerSpec = struct {
    allocator: Allocator,
    states: std.ArrayListUnmanaged(StateVar),
    tokens: std.ArrayListUnmanaged(TokenDef),
    rules: std.ArrayListUnmanaged(LexerRule),
    codeFunctions: std.ArrayListUnmanaged([]const u8),
    langName: ?[]const u8 = null,

    pub fn init(allocator: Allocator) LexerSpec {
        return .{
            .allocator = allocator,
            .states = .empty,
            .tokens = .empty,
            .rules = .empty,
            .codeFunctions = .empty,
        };
    }

    pub fn deinit(self: *LexerSpec) void {
        for (self.rules.items) |rule| {
            self.allocator.free(rule.guards);
            self.allocator.free(rule.actions);
        }
        self.states.deinit(self.allocator);
        self.tokens.deinit(self.allocator);
        self.rules.deinit(self.allocator);
        self.codeFunctions.deinit(self.allocator);
    }
};

// =============================================================================
// Lexer spec queries (used by parser code generation)
// =============================================================================

pub fn findTokenForChar(spec: *const LexerSpec, ch: u8) ?[]const u8 {
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

pub fn findTokenForLiteral(spec: *const LexerSpec, literal: []const u8) ?[]const u8 {
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
// Grammar IR (the lowered @parser section)
//
// The self-hosted frontend (frontend/parser.zig + frontend/lower.zig)
// produces this IR from .grammar files; expand.zig consumes it.
// =============================================================================

pub const GrammarIR = struct {
    rules: []const ParsedRule,
    startSymbols: []const []const u8,
    asDirectives: []const AsDirective,
    opMappings: []const OpMapping,
    errorNames: []const ErrorName,
    infix: ?InfixDecl = null,
    lang: ?[]const u8 = null,
    expectConflicts: ?u32 = null,
};

pub const ParsedRule = struct {
    name: []const u8,
    isStart: bool,
    alternatives: []const ParsedAlternative,
};

pub const ParsedAlternative = struct {
    elements: []const ParsedElement,
    action: ?[]const u8 = null,
    excludeChar: u8 = 0,
    preferReduce: bool = false,
    preferShift: bool = false,
};

pub const ParsedElement = struct {
    kind: Kind,
    value: []const u8 = "",
    quantifier: Quantifier = .one,
    optionalItems: bool = false,
    listSeparator: ?[]const u8 = null,
    subElements: []const ParsedElement = &[_]ParsedElement{},
    skip: bool = false,

    pub const Kind = enum {
        ident,
        token,
        string,
        group,
        optGroup,
        reqList,
        optList,
    };

    pub const Quantifier = enum { one, optional, zeroPlus, onePlus };
};

pub const InfixDecl = struct {
    baseRule: []const u8,
    ops: []const InfixOp,
};

/// @as directive for token-to-rule mapping (uses @lang module)
pub const AsDirective = struct {
    token: []const u8, // "ident"
    rule: []const u8, // "cmd" -> CmdId, cmdAs, cmdToSymbol
    permissive: bool = false, // "cmd!" -> reduce-aware matching (action != 0)
};

/// @op directive for operator literal-to-token mappings
pub const OpMapping = struct {
    lit: []const u8, // "'=" (the literal in the grammar)
    tok: []const u8, // "noteq" (the lexer token type)
};

/// @errors directive for human-readable rule names in diagnostics
pub const ErrorName = struct {
    rule: []const u8, // "expr"
    name: []const u8, // "expression"
};

/// @infix directive for automatic precedence-climbing expression grammar
pub const InfixOp = struct {
    op: []const u8, // "+" or "||"
    assoc: Assoc,
    prec: u32,

    pub const Assoc = enum { left, right, none };
};

// =============================================================================
// Symbols and rules (the desugared grammar)
// =============================================================================

/// Terminal or nonterminal symbol
pub const ParserSymbol = struct {
    id: u16,
    name: []const u8,
    kind: Kind,

    // For nonterminals only
    nullable: bool = false,
    firsts: ParserSymbolSet = .empty,
    follows: ParserSymbolSet = .empty,
    rules: std.ArrayListUnmanaged(u16) = .empty, // Rule IDs that define this nonterminal

    pub const Kind = enum { terminal, nonterminal };

    pub fn init(id: u16, name: []const u8, kind: Kind) ParserSymbol {
        return .{ .id = id, .name = name, .kind = kind };
    }

    pub fn deinit(self: *ParserSymbol, allocator: Allocator) void {
        self.rules.deinit(allocator);
        self.firsts.deinit(allocator);
        self.follows.deinit(allocator);
    }
};

/// A set of symbol IDs (for FIRST/FOLLOW sets)
pub const ParserSymbolSet = struct {
    items: std.ArrayListUnmanaged(u16) = .empty,

    pub const empty: ParserSymbolSet = .{};

    pub fn deinit(self: *ParserSymbolSet, allocator: Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn add(self: *ParserSymbolSet, allocator: Allocator, id: u16) !void {
        for (self.items.items) |existing| {
            if (existing == id) return;
        }
        try self.items.append(allocator, id);
    }

    pub fn contains(self: *const ParserSymbolSet, id: u16) bool {
        for (self.items.items) |existing| {
            if (existing == id) return true;
        }
        return false;
    }

    pub fn addAll(self: *ParserSymbolSet, allocator: Allocator, other: *const ParserSymbolSet) !bool {
        const oldCount = self.items.items.len;
        for (other.items.items) |id| {
            try self.add(allocator, id);
        }
        return self.items.items.len > oldCount;
    }

    pub fn count(self: *const ParserSymbolSet) usize {
        return self.items.items.len;
    }

    pub fn slice(self: *const ParserSymbolSet) []const u16 {
        return self.items.items;
    }
};

/// Production rule: lhs → rhs with optional action
pub const ParserRule = struct {
    id: u16,
    lhs: u16, // Nonterminal symbol ID
    rhs: []const u16, // Sequence of symbol IDs
    action: ?[]const u8, // Action template text, e.g. (set 2 ...3)
    actionOffset: u8 = 0, // Position offset for start rules with marker tokens
    nullable: bool = false,
    firsts: ParserSymbolSet = .empty,
    excludeChar: u8 = 0, // X "c" - exclude rule when next char matches
    preferReduce: bool = false, // < hint - prefer reduce on S/R conflict
    preferShift: bool = false, // > hint - prefer shift on S/R conflict
};
