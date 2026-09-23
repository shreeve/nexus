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
    expectConflicts: ?u32 = null, // legacy `@conflicts = N`; replaced by `conflicts`
    /// `@schema`: present means the grammar is in schema mode.
    schema: ?Schema = null,
    /// `@conflicts` manifest; empty means the grammar must be conflict-free.
    conflicts: []const ConflictEntry = &.{},
    /// `@display`: reader-facing names for tokens in diagnostics.
    displayNames: []const DisplayName = &.{},
    /// `@trivia`: tokens moved to the trivia channel.
    trivia: []const []const u8 = &.{},
    /// `@repair`: the tolerant-repair alphabet; null = no tolerant driver.
    repair: ?RepairSpec = null,
};

pub const ParsedRule = struct {
    name: []const u8,
    isStart: bool,
    alternatives: []const ParsedAlternative,
    line: u32 = 0,
};

pub const ParsedAlternative = struct {
    elements: []const ParsedElement,
    action: ?[]const u8 = null, // legacy template text; replaced by actionTree
    actionTree: ?ActionTree = null,
    /// `~ "reason"`: exempt from the schema coverage gate.
    optOut: ?[]const u8 = null,
    excludeChar: u8 = 0, // legacy; replaced by excludeChars
    excludeChars: []const u8 = &.{},
    preferReduce: bool = false,
    preferShift: bool = false,
    line: u32 = 0,
};

pub const ParsedElement = struct {
    kind: Kind,
    value: []const u8 = "",
    quantifier: Quantifier = .one,
    optionalItems: bool = false,
    listSeparator: ?[]const u8 = null,
    subElements: []const ParsedElement = &[_]ParsedElement{},
    /// `choice` elements: one alternative sequence per `|` branch.
    choices: []const []const ParsedElement = &.{},
    skip: bool = false,
    /// `role:element` pattern label.
    label: ?[]const u8 = null,

    pub const Kind = enum {
        ident,
        token,
        string,
        group,
        optGroup,
        reqList,
        optList,
        /// `(A | B | C)`: exactly one of the choices (optional with `?`).
        choice,
    };

    pub const Quantifier = enum { one, optional, zeroPlus, onePlus };
};

// =============================================================================
// Semantic layer (schema mode)
// =============================================================================

/// `@schema`: every node kind and its roles.
pub const Schema = struct {
    kinds: []const Kind,
    /// `@tags`: extra tags the Tag enum must contain (used by lang wrappers).
    extraTags: []const []const u8 = &.{},

    /// One node kind: a tag, its slot roles in order, and side-band roles.
    pub const Kind = struct {
        tag: []const u8,
        roles: []const Role,
        /// Side-band roles: spans recorded in the role store, not in the tree.
        side: []const []const u8 = &.{},
        /// Produced by a lang Parser wrapper, not by any rule.
        wrapper: bool = false,
        line: u32 = 0,
    };

    pub const Role = struct {
        name: []const u8,
        type: RoleType = .any,
        optional: bool = false,
        /// `...name`: zero or more trailing children; always the last role.
        rest: bool = false,
    };

    pub const RoleType = union(enum) {
        any,
        node,
        leaf,
        /// A marker tag; an empty list allows any tag.
        tag: []const []const u8,
        group,
        /// A node whose head is one of these kinds.
        kinds: []const []const u8,
    };
};

/// A parsed action template. Built by the frontend; consumed by the
/// semantic checks (semantics.zig) and by parser codegen.
pub const ActionTree = union(enum) {
    /// `→ N`: pass element N through unchanged.
    pass: u16,
    /// `→ _`: nil.
    nil,
    /// `→ (…)`: construct a list.
    list: ActionList,
};

pub const ActionList = struct {
    head: Head,
    items: []const ActionItem,

    pub const Head = union(enum) {
        /// `(tag …)`: a tag-headed list (a schema kind in schema mode).
        tag: []const u8,
        /// `(~N …)` / `(N …)`: a list headed by an element's value.
        ref: ActionElem,
        /// `(…)` with no head: an untagged list (plumbing or a group).
        none,
    };
};

pub const ActionItem = struct {
    /// `role:elem`; null for a positional element.
    role: ?[]const u8 = null,
    elem: ActionElem,
};

pub const ActionElem = union(enum) {
    /// `N`: element N (1-based pattern position).
    ref: u16,
    /// `...N`: spread element N's children.
    spread: u16,
    /// `~N`: element N's resolved symbol id.
    symId: u16,
    /// `_`
    nil,
    /// A tag literal in child position (`op:+=`, `move`).
    tagLit: []const u8,
    /// A nested `(kind …)` node.
    node: *const ActionList,
    /// `@name` / a pattern label reference, resolved to a position by expand.zig.
    label: []const u8,
};

/// One `@conflicts` manifest entry.
pub const ConflictEntry = struct {
    kind: enum { shift, reduce },
    /// The rule a default shift beat (`shift`) or the reduction kept (`reduce`), as `lhs → rhs`.
    rule: []const u8,
    /// For `reduce`: the reduction dropped.
    over: ?[]const u8 = null,
    count: u32,
    reason: []const u8,
    line: u32 = 0,
};

pub const DisplayName = struct {
    token: []const u8,
    name: []const u8,
};

pub const RepairSpec = struct {
    /// Tokens that may be minted as zero-width holes (value-carrying, e.g. IDENT).
    holes: []const []const u8,
    /// Structural tokens that may be minted (NEWLINE, INDENT, OUTDENT).
    structure: []const []const u8,
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
    /// Explicit lang lookup function; null = the `<rule>As` convention.
    via: ?[]const u8 = null,
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
pub const Symbol = struct {
    id: u16,
    name: []const u8,
    kind: Kind,

    // For nonterminals only
    nullable: bool = false,
    firsts: SymbolSet = .empty,
    follows: SymbolSet = .empty,
    rules: std.ArrayListUnmanaged(u16) = .empty, // Rule IDs that define this nonterminal

    pub const Kind = enum { terminal, nonterminal };

    pub fn init(id: u16, name: []const u8, kind: Kind) Symbol {
        return .{ .id = id, .name = name, .kind = kind };
    }

    pub fn deinit(self: *Symbol, allocator: Allocator) void {
        self.rules.deinit(allocator);
        self.firsts.deinit(allocator);
        self.follows.deinit(allocator);
    }
};

/// A set of symbol IDs (for FIRST/FOLLOW sets)
pub const SymbolSet = struct {
    items: std.ArrayListUnmanaged(u16) = .empty,

    pub const empty: SymbolSet = .{};

    pub fn deinit(self: *SymbolSet, allocator: Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn add(self: *SymbolSet, allocator: Allocator, id: u16) !void {
        for (self.items.items) |existing| {
            if (existing == id) return;
        }
        try self.items.append(allocator, id);
    }

    pub fn contains(self: *const SymbolSet, id: u16) bool {
        for (self.items.items) |existing| {
            if (existing == id) return true;
        }
        return false;
    }

    pub fn addAll(self: *SymbolSet, allocator: Allocator, other: *const SymbolSet) !bool {
        const oldCount = self.items.items.len;
        for (other.items.items) |id| {
            try self.add(allocator, id);
        }
        return self.items.items.len > oldCount;
    }

    pub fn count(self: *const SymbolSet) usize {
        return self.items.items.len;
    }

    pub fn slice(self: *const SymbolSet) []const u16 {
        return self.items.items;
    }
};

/// Production rule: lhs → rhs with optional action
pub const Rule = struct {
    id: u16,
    lhs: u16, // Nonterminal symbol ID
    rhs: []const u16, // Sequence of symbol IDs
    action: ?[]const u8, // Action template text (legacy; replaced by actionTree)
    /// Action with every label resolved to a position and, in schema mode,
    /// every role placed in its slot (nils filled). Null = pass through 1.
    actionTree: ?ActionTree = null,
    actionOffset: u8 = 0, // Position offset for start rules with marker tokens
    nullable: bool = false,
    firsts: SymbolSet = .empty,
    excludeChar: u8 = 0, // X "c" (legacy; replaced by excludeChars)
    excludeChars: []const u8 = &.{}, // X "c" - chars that force shift when adjacent
    preferReduce: bool = false, // < hint - prefer reduce on S/R conflict
    preferShift: bool = false, // > hint - prefer shift on S/R conflict
    /// Schema kind index this rule constructs (schema mode), for the node store.
    kind: ?u16 = null,
    /// Side-band labels: (role, 1-based position) recorded in the role store.
    sideLabels: []const SideLabel = &.{},
    /// Source line of the alternative this rule came from (diagnostics).
    line: u32 = 0,

    pub const SideLabel = struct { role: []const u8, pos: u16 };
};

/// The desugared grammar: symbols, BNF rules, start/accept bookkeeping, and
/// the directives later stages need. Built from a GrammarIR by expand.zig.
pub const Grammar = struct {
    allocator: Allocator,

    // Symbols
    symbols: std.ArrayListUnmanaged(Symbol) = .empty,
    symbolMap: std.StringHashMapUnmanaged(u16) = .empty,
    aliases: std.StringHashMapUnmanaged([]const u8) = .empty,
    nextSymbolId: u16 = 0,

    // Rules
    rules: std.ArrayListUnmanaged(Rule) = .empty,

    // Special symbol IDs
    acceptId: u16 = 0,
    endId: u16 = 0,
    errorId: u16 = 0,

    // One entry per start symbol (parallel arrays)
    startSymbols: std.ArrayListUnmanaged(u16) = .empty,
    acceptRules: std.ArrayListUnmanaged(u16) = .empty,

    // Directives carried over from the IR
    asDirectives: []const AsDirective = &.{},
    opMappings: []const OpMapping = &.{},
    errorNames: []const ErrorName = &.{},
    displayNames: []const DisplayName = &.{},
    lang: ?[]const u8 = null,
    expectConflicts: ?u32 = null, // legacy; replaced by `conflicts`
    schema: ?Schema = null,
    conflicts: []const ConflictEntry = &.{},
    trivia: []const []const u8 = &.{},
    repair: ?RepairSpec = null,

    pub fn init(allocator: Allocator) Grammar {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Grammar) void {
        for (self.symbols.items) |*sym| sym.deinit(self.allocator);
        self.symbols.deinit(self.allocator);
        self.symbolMap.deinit(self.allocator);
        self.aliases.deinit(self.allocator);

        for (self.rules.items) |*rule| {
            self.allocator.free(rule.rhs);
            rule.firsts.deinit(self.allocator);
        }
        self.rules.deinit(self.allocator);

        self.startSymbols.deinit(self.allocator);
        self.acceptRules.deinit(self.allocator);
    }

    pub fn addSymbol(self: *Grammar, name: []const u8, kind: Symbol.Kind) !u16 {
        if (self.symbolMap.get(name)) |id| return id;

        const id = self.nextSymbolId;
        self.nextSymbolId += 1;

        try self.symbols.append(self.allocator, Symbol.init(id, name, kind));
        try self.symbolMap.put(self.allocator, name, id);

        return id;
    }

    pub fn getSymbol(self: *const Grammar, name: []const u8) ?u16 {
        var resolved = name;
        var count: usize = 0;
        while (self.aliases.get(resolved)) |target| {
            count += 1;
            if (count > 100 or std.mem.eql(u8, resolved, target)) return null;
            resolved = target;
        }
        return self.symbolMap.get(resolved);
    }

    pub fn isAcceptRule(self: *const Grammar, ruleId: u16) bool {
        for (self.acceptRules.items) |ar| {
            if (ruleId == ar) return true;
        }
        return false;
    }
};
