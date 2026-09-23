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

const frontend = @import("frontend/frontend.zig");
const LexerParser = frontend.LexerParser;
const GrammarLowerer = frontend.GrammarLowerer;
const findSection = frontend.findSection;
const parseGrammarSexp = frontend.parseGrammarSexp;
const dumpSexp = frontend.dumpSexp;
const checkGrammar = @import("check.zig").checkGrammar;
const LexerGenerator = @import("lexgen/lexgen.zig").LexerGenerator;

const grammar = @import("grammar.zig");
const StateVar = grammar.StateVar;
const TokenDef = grammar.TokenDef;
const Guard = grammar.Guard;
const Action = grammar.Action;
const LexerRule = grammar.LexerRule;
const LexerSpec = grammar.LexerSpec;
const findTokenForChar = grammar.findTokenForChar;
const findTokenForLiteral = grammar.findTokenForLiteral;
const GrammarIR = grammar.GrammarIR;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const InfixDecl = grammar.InfixDecl;
const AsDirective = grammar.AsDirective;
const OpMapping = grammar.OpMapping;
const ErrorName = grammar.ErrorName;
const InfixOp = grammar.InfixOp;
const ParserSymbol = grammar.ParserSymbol;
const ParserSymbolSet = grammar.ParserSymbolSet;
const ParserRule = grammar.ParserRule;

test {
    _ = @import("frontend/lower.zig");
}

const version = @import("version.zig").version;
const max_grammar_bytes: usize = 1 << 20; // 1 MiB cap for .grammar file reads

// =============================================================================
// Parser DSL Data Structures
// =============================================================================

const ParseMode = enum { lalr, slr };

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
    infixOps: std.ArrayListUnmanaged(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    lexerSpec: ?*const LexerSpec = null,

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
        self.infixOps.deinit(self.allocator);
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
                        .action = expandedAlt.action,
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
                    .action = actionTemplate,
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
            .action = "(!1 ...2)",
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
            .action = "(!2 ...3)",
        });
        try self.symbols.items[tailId].rules.append(self.allocator, tailRule1Id);

        // Rule: _tail → ε → ()
        const tailRule2Id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = tailRule2Id,
            .lhs = tailId,
            .rhs = &[_]u16{},
            .action = "()",
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
                    .action = actionStr,
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
                .action = "1",
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
            .action = "1",
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
            .action = "(!1 ...2)",
        });
        try self.symbols.items[starId].rules.append(self.allocator, rule1Id);

        // Rule 2: star → ε → ()
        const rule2Id: u16 = @intCast(self.rules.items.len);
        try self.rules.append(self.allocator, .{
            .id = rule2Id,
            .lhs = starId,
            .rhs = &[_]u16{},
            .action = "()",
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
            .action = "(!1 ...2)",
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

        try writer.writeAll(
            \\};
            \\
            \\// =============================================================================
            \\// PARSER
            \\// =============================================================================
            \\
            \\pub const BaseParser = struct {
            \\    arena: std.heap.ArenaAllocator,
            \\    lexer: Lexer,
            \\    source: []const u8,
            \\    current: Token,
            \\    injectedToken: ?u16 = null,
            \\    lastMatchedId: u16 = 0,
            \\
            \\    stateStack: std.ArrayListUnmanaged(u16) = .empty,
            \\    valueStack: std.ArrayListUnmanaged(Sexp) = .empty,
            \\    /// Spare capacity of the lists `keepList` returned, by address.
            \\    listSpare: std.AutoHashMapUnmanaged(usize, ListSpare) = .empty,
            \\
            \\    const ListSpare = struct { len: usize, capacity: usize };
            \\
            \\    pub fn init(backingAllocator: std.mem.Allocator, source: []const u8) BaseParser {
            \\        var p = BaseParser{
            \\            .arena = std.heap.ArenaAllocator.init(backingAllocator),
            \\            .lexer = Lexer.init(source),
            \\            .source = source,
            \\            .current = undefined,
            \\        };
            \\        p.current = p.lexer.next();
            \\        return p;
            \\    }
            \\
            \\    pub fn deinit(self: *BaseParser) void {
            \\        self.arena.deinit();
            \\    }
            \\
            \\    fn allocator(self: *BaseParser) std.mem.Allocator {
            \\        return self.arena.allocator();
            \\    }
            \\
            \\    pub fn printError(self: *BaseParser) void {
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
            \\    fn doParse(self: *BaseParser, startSym: u16) !Sexp {
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
            \\    fn spreadList(self: *BaseParser, head: Sexp, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        out.append(self.allocator(), head) catch return .nil;
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Spread only: [...tail]
            \\    fn spreadOnly(self: *BaseParser, tail: Sexp) Sexp {
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Default list handler
            \\    fn list(self: *BaseParser, pass: []Sexp) Sexp {
            \\        if (pass.len == 0) return .nil;
            \\        if (pass.len == 1) return pass[0];
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        for (pass) |v| out.append(self.allocator(), v) catch return .nil;
            \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
            \\    }
            \\
            \\    /// Start a list holding the items of `base` (a list, else
            \\    /// nothing) for an action that appends to it. A list from
            \\    /// `keepList` is reused with its spare capacity, so a
            \\    /// left-recursive list grows in amortized O(1) per element.
            \\    fn extendList(self: *BaseParser, base: Sexp) !std.ArrayListUnmanaged(Sexp) {
            \\        if (base != .list) return .empty;
            \\        const items = base.list;
            \\        if (items.len > 0) if (self.listSpare.get(@intFromPtr(items.ptr))) |spare| {
            \\            if (spare.len == items.len) {
            \\                _ = self.listSpare.remove(@intFromPtr(items.ptr));
            \\                return .{ .items = @constCast(items), .capacity = spare.capacity };
            \\            }
            \\        };
            \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
            \\        try out.appendSlice(self.allocator(), items);
            \\        return out;
            \\    }
            \\
            \\    /// Finish a list from `extendList`, recording its spare capacity.
            \\    fn keepList(self: *BaseParser, out: *std.ArrayListUnmanaged(Sexp)) Sexp {
            \\        if (out.items.len > 0 and out.capacity > out.items.len) {
            \\            self.listSpare.put(self.allocator(), @intFromPtr(out.items.ptr), .{
            \\                .len = out.items.len,
            \\                .capacity = out.capacity,
            \\            }) catch {};
            \\        }
            \\        return .{ .list = out.items };
            \\    }
            \\
            \\    /// Build S-expression: (tag items...) with trailing nil trimming
            \\    inline fn sexp(self: *BaseParser, comptime tag: Tag, items: []const Sexp) Sexp {
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
            \\    inline fn sexpSpread(self: *BaseParser, comptime tag: Tag, spread: Sexp) Sexp {
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
            \\    inline fn sexpPosSpread(self: *BaseParser, comptime tag: Tag, pos: Sexp, spread: Sexp) Sexp {
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
            \\    fn executeAction(self: *BaseParser, ruleId: u16, pass: []Sexp) Sexp {
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
                    try writer.print(" \xe2\x86\x92 {s}", .{action});
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
            try writer.writeAll("\n    fn tokenToSymbol(self: *BaseParser, token: Token) u16 {\n");
        } else {
            try writer.writeAll("\n    fn tokenToSymbol(_: *BaseParser, token: Token) u16 {\n");
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
                \\    fn identToSymbol(self: *BaseParser, token: Token) u16 {
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
                        \\    fn tryIdentAs{s}(self: *BaseParser, token: Token, text: []const u8) ?u16 {{
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
                        \\    fn tryIdentAs{s}(self: *BaseParser, token: Token, text: []const u8) ?u16 {{
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
                \\    fn identToSymbol(_: *BaseParser, _: Token) u16 {
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
                    \\    pub fn parse{s}(self: *BaseParser) !Sexp {{
                    \\        self.injectedToken = SYM_{s}_START;
                    \\        return self.doParse(SYM_{s});
                    \\    }}
                , .{ fname, name, name });
            }
        }

        try writer.writeAll("\n};\n\n");

        // Parser auto-wire: when @lang is set, allow the lang module to wrap
        // BaseParser with semantic rewriting. Mirrors the Lexer auto-wire.
        if (self.lang) |langName| {
            try writer.print(
                \\pub const Parser = if (@hasDecl({s}, "Parser")) {s}.Parser else BaseParser;
                \\
                \\
            , .{ langName, langName });
        }

        // Top-level parse{Start}(allocator, source) convenience helpers.
        //
        // The returned Sexp references arena-allocated memory owned by the
        // returned `parser`; the caller must keep the parser alive for the
        // lifetime of the tree and call `result.parser.deinit()` when done.
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

            const parserType: []const u8 = if (self.lang != null) "Parser" else "BaseParser";

            try writer.print(
                \\
                \\/// Convenience: instantiate the (lang-extended) parser and parse a whole
                \\/// {s}. Caller owns `result.parser` and must call `result.parser.deinit()`
                \\/// when done with the returned tree (the tree references arena-allocated
                \\/// memory owned by the parser).
                \\///
                \\/// The parser is returned by value, so the underlying type
                \\/// must be safely movable (no self-referential storage).
                \\/// `BaseParser` is movable by construction; custom `lang.Parser`
                \\/// wrappers must preserve this invariant.
                \\pub fn parse{s}(allocator: std.mem.Allocator, source: []const u8) !struct {{ parser: {s}, sexp: Sexp }} {{
                \\    var p = {s}.init(allocator, source);
                \\    errdefer p.deinit();
                \\    const sexp = try p.parse{s}();
                \\    return .{{ .parser = p, .sexp = sexp }};
                \\}}
                \\
            , .{ name, fname, parserType, parserType, fname });
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

        return try output.toOwnedSlice();
    }

    fn generateRuleAction(self: *ParserGenerator, writer: anytype, rule: ParserRule) !void {
        if (rule.action == null) {
            try writer.writeAll("self.list(pass)");
            return;
        }

        const template = rule.action.?;
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
        // Track child-position Tag literals separately. The dispatcher's
        // sexpSpread / sexpPosSpread fast paths emit (tag ...spread) and
        // (tag pos ...spread) shapes, neither of which has a slot for a
        // kind-discriminator child Tag — so routing a mixed (Tag + spread)
        // template through either would silently drop the Tag. Force such
        // templates to the complex case, which can place tag literals at
        // arbitrary positions.
        var hasChildTagLiteral = false;

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
            } else if (self.isTagLiteral(work)) {
                hasChildTagLiteral = true;
            } else {
                hasOther = true;
            }
        }

        // Pattern: (tag ...N) - use sexpSpread (only if no nil elements and no child tag literals)
        if (firstIsTag and spreadCount == 1 and posCount == 0 and !hasTilde and !hasOther and !hasNil and !hasChildTagLiteral) {
            try writer.print("self.sexpSpread(.@\"{s}\", pass[{d}])", .{ tagName, spreadPos });
            return;
        }

        // Pattern: (tag N ...M) - use sexpPosSpread (only if no nil elements and no child tag literals)
        if (firstIsTag and spreadCount == 1 and posCount == 1 and !hasTilde and !hasOther and !hasNil and !hasChildTagLiteral) {
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
                } else if (self.isTagLiteral(work)) {
                    // Tag literal at child position — kind-discriminator
                    // pattern used by Rig and any grammar that wants the
                    // grammar action to emit normalized shapes directly
                    // (e.g., `(set move 1 _ 3)` puts the Tag `.move` in
                    // slot 2). Previously silent-dropped; now emitted as
                    // a literal-Tag Sexp.
                    try writer.print(".{{ .tag = .@\"{s}\" }}", .{work});
                } else {
                    std.debug.print(
                        "❌ Unknown action element '{s}' in template: {s}\n" ++
                        "   (expected position ref like `1`, `_`, `...N`, `~N`, `key:N`, or a tag literal)\n",
                        .{ work, template },
                    );
                    return error.UnknownActionElement;
                }
            }
            try writer.writeAll("})");
            return;
        }

        // Complex case: inline list building (spreads, tilde transforms).
        //
        // A template that starts with a spread, `(...N more...)`, extends
        // the list at N: that is how a left-recursive list rule adds one
        // element. Copying the whole list on every reduction would make
        // parsing an n-element list O(n^2) in time and arena memory, so
        // the list grows in place instead (`extendList` / `keepList`,
        // amortized O(1) per element). This is safe because each reduced
        // value is consumed exactly once, unless the template names N
        // again, in which case the list is copied as before.
        var extendElem: ?usize = null;
        for (elements.items, 0..) |elem, idx| {
            const work = self.stripKeyAndSuffix(elem);
            if (work.len == 0) continue;
            if (isSpread(work)) extendElem = idx;
            break;
        }
        if (extendElem) |first| {
            const digit = self.stripKeyAndSuffix(elements.items[first])[3];
            for (elements.items[first + 1 ..]) |elem| {
                if (positionDigit(self.stripKeyAndSuffix(elem)) == digit) extendElem = null;
            }
        }
        if (extendElem) |first| {
            const pos = self.stripKeyAndSuffix(elements.items[first])[3] - '1' + offset;
            try writer.print("blk: {{ var out = self.extendList(pass[{d}]) catch break :blk .nil; ", .{pos});
        } else {
            try writer.writeAll("blk: { var out: std.ArrayListUnmanaged(Sexp) = .empty; ");
        }
        for (elements.items, 0..) |elem, idx| {
            if (elem.len == 0) continue;
            if (extendElem == idx) continue;
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
            } else if (self.isLikelyTagName(work)) {
                // Tag literal at child position. The complex-case path
                // already emitted this for unrecognized elements, but
                // (a) using `elem` instead of `work` let `key:` prefixes
                // leak into the emitted Tag name, and (b) any garbage
                // element silently became a (broken) Tag literal. Both
                // are tightened here: strip via `work`, validate via
                // `isLikelyTagName`, error on anything else.
                try writer.print("out.append(self.allocator(), .{{ .tag = .@\"{s}\" }}) catch break :blk .nil; ", .{work});
            } else {
                std.debug.print(
                    "❌ Unknown action element '{s}' in template: {s}\n" ++
                    "   (expected position ref like `1`, `_`, `...N`, `~N`, `key:N`, or a tag literal)\n",
                    .{ work, template },
                );
                return error.UnknownActionElement;
            }
        }
        try writer.writeAll("while (out.items.len > 0 and out.items[out.items.len - 1] == .nil) _ = out.pop(); ");
        if (extendElem != null) {
            try writer.writeAll("break :blk self.keepList(&out); }");
        } else {
            try writer.writeAll("break :blk .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} }; }");
        }
    }

    /// `...N` in an action template.
    fn isSpread(work: []const u8) bool {
        return work.len >= 4 and work[0] == '.' and work[1] == '.' and work[2] == '.';
    }

    /// The position digit an action element refers to (`N`, `~N`, `...N`).
    fn positionDigit(work: []const u8) ?u8 {
        if (work.len == 0) return null;
        const digit = if (isSpread(work)) work[3] else if (work[0] == '~' and work.len > 1) work[1] else work[0];
        return if (digit >= '1' and digit <= '9') digit else null;
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

    // Permissive recognizer for action elements that look like a Tag-enum
    // member name. Used at child positions (where the dispatcher routes
    // letter-start tags through the simple case and operator-name tags
    // through the complex case). Rejects only the forms the action
    // language has dedicated syntax for: position refs (digit-start),
    // symbol-id refs (`~`-start), spreads (`...`), nil/`_`, and the
    // `key:value` annotation sugar (`:` strictly between two non-empty
    // halves — a bare `:` or leading-colon operator like `:=` is a
    // valid Tag name and passes through).
    fn isLikelyTagName(self: *ParserGenerator, name: []const u8) bool {
        _ = self;
        if (name.len == 0) return false;
        if (std.mem.eql(u8, name, "nil") or std.mem.eql(u8, name, "_")) return false;
        const c = name[0];
        // Single-digit position ref `1`-`9`. (Multi-digit names and `0`
        // are valid Tag names and pass through.)
        if (c >= '1' and c <= '9' and name.len == 1) return false;
        // Symbol-id ref `~N` (tilde + digit). A bare `~` is a valid Tag.
        if (c == '~' and name.len >= 2 and name[1] >= '1' and name[1] <= '9') return false;
        // Spread `...N` (3 dots + digit). Shorter dot-starts like `.`, `..`,
        // `.member` are valid Tag names.
        if (c == '.' and name.len >= 4 and name[1] == '.' and name[2] == '.'
            and name[3] >= '1' and name[3] <= '9') return false;
        // `key:value` annotation sugar requires content on BOTH sides of the
        // colon. A bare `:` or leading-colon operator (`:=`) passes through.
        if (std.mem.indexOfScalar(u8, name, ':')) |colonPos| {
            if (colonPos > 0 and colonPos + 1 < name.len) return false;
        }
        return true;
    }

    fn registerTag(self: *ParserGenerator, tag: []const u8) !void {
        if (!self.collectedTags.contains(tag)) {
            const owned = try self.allocator.dupe(u8, tag);
            try self.collectedTags.put(self.allocator, owned, @intCast(self.tagList.items.len));
            try self.tagList.append(self.allocator, owned);
        }
    }

    fn collectTagsFromAction(self: *ParserGenerator, template: []const u8) !void {
        // For paren-style: (tag elem1 elem2 ...) — register the head as
        // a Tag, AND walk every child element to register any tag literal
        // found at a child position (e.g., `(set move 1 _ 3)` registers
        // both `set` and `move`). The head and child semantics differ
        // in how `key:value` sugar is interpreted:
        //   * head `tag:N` registers `tag` (key part)
        //   * child `key:val` registers `val` (value part, via stripKeyAndSuffix)
        if (template.len <= 1 or template[0] != '(') return;

        var i: usize = 1;
        var first_element = true;
        while (i < template.len and template[i] != ')') {
            while (i < template.len and (template[i] == ' ' or template[i] == '\t')) i += 1;
            if (i >= template.len or template[i] == ')') break;
            const start = i;
            while (i < template.len and template[i] != ' ' and template[i] != '\t' and template[i] != ')') i += 1;
            if (i <= start) break;
            const raw = template[start..i];

            var tag: []const u8 = "";
            if (first_element) {
                // Head: strip `:value` suffix, keep the `key` part as the tag.
                tag = raw;
                if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
                    const after = tag[colonPos + 1 ..];
                    if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                        after[0] == '.' or after[0] == '~'))
                    {
                        tag = tag[0..colonPos];
                    }
                }
            } else {
                // Child: strip `key:` prefix, keep the value part.
                tag = self.stripKeyAndSuffix(raw);
            }

            if (self.isLikelyTagName(tag)) {
                try self.registerTag(tag);
            }
            first_element = false;
        }
    }

    fn collectAllTags(self: *ParserGenerator) !void {
        for (self.rules.items) |rule| {
            if (rule.action) |action| {
                try self.collectTagsFromAction(action);
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
        defer parsed.parser.deinit();

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
        // (which outlives main), so the parser's arena is freed as soon as
        // lowering returns.
        var parsed = parseGrammarSexp(allocator, sourceText) catch |err| {
            std.debug.print("❌ Failed to parse @parser section: {any}\n", .{err});
            return;
        };
        defer parsed.parser.deinit();

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
