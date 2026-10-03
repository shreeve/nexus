//! Grammar data shared by every stage of the generator.
//!
//!   - Lexer spec: the lowered `@lexer` section (state vars, tokens, rules).
//!   - Grammar IR: the lowered grammar file (rules, alternatives, elements,
//!     directives, and the lexer spec), produced by frontend/lower.zig.
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
    /// Pattern text (see lexgen/regex.zig); empty for a zero-width guard rule.
    pattern: []const u8,
    guards: []const Guard,
    token: []const u8,
    actions: []const Action,
    /// `skip` action: the match is discarded and scanning continues.
    isSkip: bool = false,
    /// `hold`: the token is zero-width; the pattern is lookahead only.
    hold: bool = false,
    /// `rewind(n)`: the token is the first n bytes of the match.
    rewind: ?u16 = null,
    /// The one string the pattern matches, when it is a plain literal with
    /// no trailing context (drives literal-to-token resolution).
    literal: ?[]const u8 = null,
    /// 1-based location of the pattern (or of the `@` of a zero-width rule).
    line: u32 = 0,
    col: u32 = 0,
};

/// Complete lexer specification. Like every generator structure, it lives
/// in the run's arena and is never freed on its own.
pub const LexerSpec = struct {
    states: std.ArrayList(StateVar) = .empty,
    tokens: std.ArrayList(TokenDef) = .empty,
    rules: std.ArrayList(LexerRule) = .empty,
    codeFunctions: std.ArrayList([]const u8) = .empty,
    /// `@lang`: the module the generated lexer imports.
    langName: ?[]const u8 = null,
    /// `after` block: assignments applied whenever a token consumes input.
    afterActions: std.ArrayList(Action) = .empty,
    /// Grammar file name, for diagnostics.
    fileName: []const u8 = "",
};

// =============================================================================
// Lexer spec queries (used by parser code generation)
// =============================================================================

/// The token the lexer produces for exactly the one-byte text `ch`
/// (see findTokenForLiteral).
pub fn findTokenForChar(spec: *const LexerSpec, ch: u8) ?[]const u8 {
    return findTokenForLiteral(spec, &[_]u8{ch});
}

/// The token of the rule whose pattern is exactly the literal `text`: the
/// first unguarded such rule, else the first guarded one. `text` is the
/// body of a string literal, escapes undecoded. Rules whose token is not
/// the matched text (hold, rewind, trailing context, skip) never qualify.
pub fn findTokenForLiteral(spec: *const LexerSpec, text: []const u8) ?[]const u8 {
    var guarded: ?[]const u8 = null;
    for (spec.rules.items) |rule| {
        const rl = rule.literal orelse continue;
        if (rule.isSkip or rule.hold or rule.rewind != null) continue;
        if (!decodesTo(text, rl)) continue;
        if (rule.guards.len == 0) return rule.token;
        if (guarded == null) guarded = rule.token;
    }
    return guarded;
}

/// One backslash escape of a grammar-file string, the same in patterns
/// and in parser literals: `\n \r \t \0 \\ \' \"` and `\xHH`.
pub const Escape = struct { byte: u8, len: usize };

/// The escape that starts with the backslash at `s[i]`, or null when it is
/// none of the above (or a `\x` without two hex digits).
pub fn escapeAt(s: []const u8, i: usize) ?Escape {
    if (i + 1 >= s.len) return null;
    const byte: u8 = switch (s[i + 1]) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        '0' => 0,
        '\\', '\'', '"' => s[i + 1],
        'x' => {
            if (i + 4 > s.len) return null;
            const v = std.fmt.parseInt(u8, s[i + 2 ..][0..2], 16) catch return null;
            return .{ .byte = v, .len = 4 };
        },
        else => return null,
    };
    return .{ .byte = byte, .len = 2 };
}

/// Whether the string body `text`, its escapes decoded, is `bytes`.
fn decodesTo(text: []const u8, bytes: []const u8) bool {
    var i: usize = 0;
    var n: usize = 0;
    while (i < text.len) : (n += 1) {
        const e = (if (text[i] == '\\') escapeAt(text, i) else null) orelse Escape{ .byte = text[i], .len = 1 };
        if (n == bytes.len or bytes[n] != e.byte) return false;
        i += e.len;
    }
    return n == bytes.len;
}

test "a literal names a lexer literal through its escapes" {
    try std.testing.expect(decodesTo("a\\n\\x41\\\"", "a\nA\""));
    try std.testing.expect(!decodesTo("ab", "abc"));
    try std.testing.expect(!decodesTo("abc", "ab"));
    try std.testing.expect(escapeAt("\\q", 0) == null);
    try std.testing.expect(escapeAt("\\x4", 0) == null);
}

// =============================================================================
// Grammar IR (the lowered grammar file)
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
    /// The @lexer section; null when the file has none.
    lexer: ?LexerSpec = null,
    /// Whether the file has a @parser section (text without section
    /// markers is @parser-section text).
    hasParser: bool = true,
};

pub const ParsedRule = struct {
    name: []const u8,
    isStart: bool,
    alternatives: []const ParsedAlternative,
    line: u32 = 0,
    col: u32 = 0,
};

pub const ParsedAlternative = struct {
    /// Most positions an alternative may have (its elements, those of its
    /// `[A B]` groups, and those inside its choices): positions are u16,
    /// and expand reserves maxInt(u16) as a marker.
    pub const maxPositions = std.math.maxInt(u16) - 1;

    elements: []const ParsedElement,
    actionTree: ?ActionTree = null,
    /// `~ "reason"`: exempt from the schema coverage gate.
    optOut: ?[]const u8 = null,
    /// `X "c"` hints: characters that force a shift when adjacent.
    excludeChars: []const u8 = &.{},
    preferReduce: bool = false,
    preferShift: bool = false,
    line: u32 = 0,
    col: u32 = 0,
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
    /// `role:element` pattern label (`_` = explicitly dropped).
    label: ?[]const u8 = null,
    /// Source position of the element (diagnostics).
    line: u32 = 0,
    col: u32 = 0,

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
        col: u32 = 0,
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
    /// Keep every item, trailing nils included (the default action of an
    /// expanded alternative: absent optional elements are nil, as they are
    /// for an optional element that is not expanded).
    keepNils: bool = false,

    pub const Head = union(enum) {
        /// `(tag …)`: a tag-headed list (a schema kind in schema mode).
        tag: []const u8,
        /// `(!N …)`: a list headed by element N's value (a src-headed list).
        /// The frontend produces only `.ref`; lists whose first item is a
        /// plain `N` or `~N` are untagged (`.none`).
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
    /// The tag named by the text of the string literal matched at
    /// position N (a `tag` role labeling `"+="` or `("+=" | "-=")`).
    litTag: u16,
    /// A nested `(kind …)` node.
    node: *const ActionList,
};

/// The canonical text of an action: `N`, `_`, or `(head item ...)` with
/// items `N`, `...N`, `~N`, `_`, tags, nested lists, each optionally
/// prefixed by `role:`. Used in generated-code comments and diagnostics.
pub fn renderAction(allocator: Allocator, tree: ActionTree) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    switch (tree) {
        .pass => |n| try out.print(allocator, "{d}", .{n}),
        .nil => try out.append(allocator, '_'),
        .list => |list| try renderList(allocator, &out, list),
    }
    return out.toOwnedSlice(allocator);
}

fn renderList(allocator: Allocator, out: *std.ArrayList(u8), list: ActionList) Allocator.Error!void {
    try out.append(allocator, '(');
    var sep = false;
    switch (list.head) {
        .tag => |t| {
            try out.appendSlice(allocator, t);
            sep = true;
        },
        .ref => |e| {
            try out.append(allocator, '!');
            try renderElem(allocator, out, e);
            sep = true;
        },
        .none => {},
    }
    for (list.items) |item| {
        if (sep) try out.append(allocator, ' ');
        sep = true;
        if (item.role) |r| {
            try out.appendSlice(allocator, r);
            try out.append(allocator, ':');
        }
        try renderElem(allocator, out, item.elem);
    }
    try out.append(allocator, ')');
}

fn renderElem(allocator: Allocator, out: *std.ArrayList(u8), elem: ActionElem) Allocator.Error!void {
    switch (elem) {
        .ref => |n| try out.print(allocator, "{d}", .{n}),
        .spread => |n| try out.print(allocator, "...{d}", .{n}),
        .symId => |n| try out.print(allocator, "~{d}", .{n}),
        .nil => try out.append(allocator, '_'),
        .tagLit => |t| try out.appendSlice(allocator, t),
        .litTag => |n| try out.print(allocator, "tag({d})", .{n}),
        .node => |l| try renderList(allocator, out, l.*),
    }
}

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
    col: u32 = 0,
};

pub const DisplayName = struct {
    token: []const u8,
    name: []const u8,
    /// Where the key is written (diagnostics).
    line: u32 = 0,
    col: u32 = 0,
};

pub const RepairSpec = struct {
    /// Tokens that may be minted as zero-width holes (value-carrying, e.g. IDENT).
    holes: []const []const u8,
    /// Structural tokens that may be minted (INDENT, OUTDENT).
    structure: []const []const u8,
    /// Structural tokens that end a statement (NEWLINE): the only tokens
    /// the tolerant driver inserts in front of real input.
    terminators: []const []const u8 = &.{},
    /// Where each name is written (diagnostics): `holes`, then `structure`,
    /// then `terminators`, in order. Empty when unknown.
    locs: []const Loc = &.{},

    pub const Loc = struct { line: u32, col: u32 };

    /// The location of name `i` of the three lists taken in order.
    pub fn locOf(self: RepairSpec, i: usize) ?Loc {
        return if (i < self.locs.len) self.locs[i] else null;
    }
};

pub const InfixDecl = struct {
    baseRule: []const u8,
    ops: []const InfixOp,
    /// Source position of the `@infix` directive (diagnostics).
    line: u32 = 0,
    col: u32 = 0,
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
    /// Where the target token is written (diagnostics).
    line: u32 = 0,
    col: u32 = 0,
};

/// @errors directive for human-readable rule names in diagnostics
pub const ErrorName = struct {
    rule: []const u8, // "expr"
    name: []const u8, // "expression"
    /// Where the rule name is written (diagnostics).
    line: u32 = 0,
    col: u32 = 0,
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
    /// Nonterminals: the ids of the rules that define it.
    rules: std.ArrayList(u16) = .empty,

    pub const Kind = enum { terminal, nonterminal };

    pub fn init(id: u16, name: []const u8, kind: Kind) Symbol {
        return .{ .id = id, .name = name, .kind = kind };
    }
};

/// Production rule: lhs → rhs with optional action
pub const Rule = struct {
    id: u16,
    lhs: u16, // Nonterminal symbol ID
    rhs: []const u16, // Sequence of symbol IDs
    /// Action with every label resolved to a position and, in schema mode,
    /// every role placed in its slot (nils filled). Null = the default:
    /// nothing, the one element, or an untagged list of the elements.
    actionTree: ?ActionTree = null,
    /// `X "c"` hints: characters that force a shift when adjacent.
    excludeChars: []const u8 = &.{},
    /// `<` / `>` hints: prefer reduce / shift on a shift/reduce conflict.
    preferReduce: bool = false,
    preferShift: bool = false,
    /// Schema kind index this rule constructs (schema mode), for the node store.
    kind: ?u16 = null,
    /// Side-band labels: (role, 1-based position) recorded in the role store.
    sideLabels: []const SideLabel = &.{},
    /// Source line and column of the alternative this rule came from
    /// (0 for synthesized rules).
    line: u32 = 0,
    col: u32 = 0,

    /// `pos` is 1-based like action positions.
    pub const SideLabel = struct { role: []const u8, pos: u16 };
};

/// The desugared grammar: symbols, BNF rules, start/accept bookkeeping, and
/// the directives later stages need. Built from a GrammarIR by expand.zig,
/// in the run's arena (`allocator`).
pub const Grammar = struct {
    allocator: Allocator,

    // Symbols
    symbols: std.ArrayList(Symbol) = .empty,
    symbolMap: std.StringHashMapUnmanaged(u16) = .empty,
    aliases: std.StringHashMapUnmanaged([]const u8) = .empty,

    // Rules
    rules: std.ArrayList(Rule) = .empty,

    // Special symbol IDs
    acceptId: u16 = 0,
    endId: u16 = 0,
    errorId: u16 = 0,

    // One entry per start symbol (parallel arrays)
    startSymbols: std.ArrayList(u16) = .empty,
    acceptRules: std.ArrayList(u16) = .empty,

    // Directives carried over from the IR
    asDirectives: []const AsDirective = &.{},
    opMappings: []const OpMapping = &.{},
    errorNames: []const ErrorName = &.{},
    displayNames: []const DisplayName = &.{},
    lang: ?[]const u8 = null,
    schema: ?Schema = null,
    conflicts: []const ConflictEntry = &.{},
    trivia: []const []const u8 = &.{},
    repair: ?RepairSpec = null,

    pub fn init(allocator: Allocator) Grammar {
        return .{ .allocator = allocator };
    }

    /// Most symbols a grammar may have: ids are u16, and so is the count.
    pub const maxSymbols = std.math.maxInt(u16);

    /// The id of the symbol `name`, added with `kind` if it is new.
    pub fn addSymbol(self: *Grammar, name: []const u8, kind: Symbol.Kind) error{ TooManySymbols, OutOfMemory }!u16 {
        if (self.symbolMap.get(name)) |id| return id;
        if (self.symbols.items.len == maxSymbols) return error.TooManySymbols;

        const id: u16 = @intCast(self.symbols.items.len);
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

test "a grammar has at most maxSymbols symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var g = Grammar.init(a);
    for (0..Grammar.maxSymbols) |i| {
        const id = try g.addSymbol(try a.print("s{d}", .{i}), .terminal);
        try std.testing.expectEqual(i, id);
    }
    try std.testing.expectEqual(0, try g.addSymbol("s0", .terminal));
    try std.testing.expectError(error.TooManySymbols, g.addSymbol("one more", .terminal));
}
