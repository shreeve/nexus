//! Lookahead computation for reductions: nullable, FIRST, and either FOLLOW
//! (SLR(1)) or per-state LALR(1) lookaheads by spontaneous generation and
//! propagation over the LR(0) automaton.

const std = @import("std");
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const SymbolSet = grammar.SymbolSet;
const automaton = @import("automaton.zig");
const Automaton = automaton.Automaton;
const Item = automaton.Item;

pub const ParseMode = enum { lalr, slr };

/// Where each reduction's lookahead set lives: in LALR mode, `lalr[state][i]`
/// is the set for the i-th reduction item of `state`; in SLR mode the sets
/// are FOLLOW(lhs), stored on the grammar's symbols.
pub const Lookaheads = struct {
    mode: ParseMode,
    lalr: []const []const SymbolSet = &.{},
};

// =============================================================================
// FIRST/FOLLOW Set Computation
// =============================================================================
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
// =============================================================================

pub fn compute(g: *Grammar, auto: *const Automaton, mode: ParseMode) !Lookaheads {
    try computeNullable(g);
    try computeFirst(g);
    return switch (mode) {
        .slr => blk: {
            try computeFollow(g);
            break :blk .{ .mode = .slr };
        },
        .lalr => .{ .mode = .lalr, .lalr = try computeLalrLookaheads(g, auto) },
    };
}

/// Compute which symbols can derive the empty string (ε).
///
/// A symbol is nullable if:
///   - It has a production with empty RHS: A → ε
///   - All symbols in some production's RHS are nullable: A → B C where B, C nullable
///
/// Uses fixed-point iteration until no changes.
fn computeNullable(g: *Grammar) !void {
    var changed = true;
    while (changed) {
        changed = false;

        for (g.rules.items) |*rule| {
            if (rule.nullable) continue;

            var allNullable = true;
            for (rule.rhs) |symId| {
                if (!g.symbols.items[symId].nullable) {
                    allNullable = false;
                    break;
                }
            }

            if (allNullable or rule.rhs.len == 0) {
                rule.nullable = true;
                changed = true;
            }
        }

        for (g.symbols.items) |*sym| {
            if (sym.nullable or sym.kind != .nonterminal) continue;

            for (sym.rules.items) |ruleId| {
                if (g.rules.items[ruleId].nullable) {
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
fn computeFirst(g: *Grammar) !void {
    var changed = true;
    while (changed) {
        changed = false;

        // Compute FIRST for each rule's RHS
        for (g.rules.items) |*rule| {
            const oldCount = rule.firsts.count();
            try computeFirstOfSequence(g, &rule.firsts, rule.rhs);
            if (rule.firsts.count() > oldCount) changed = true;
        }

        // Propagate to nonterminals (union of all their rules' FIRST sets)
        for (g.symbols.items) |*sym| {
            if (sym.kind != .nonterminal) continue;

            for (sym.rules.items) |ruleId| {
                if (try sym.firsts.addAll(g.allocator, &g.rules.items[ruleId].firsts)) {
                    changed = true;
                }
            }
        }
    }
}

/// Compute FIRST of a sequence of symbols (X₁ X₂ ... Xₙ).
///
/// Add FIRST(X₁). If X₁ nullable, add FIRST(X₂). Continue while nullable.
fn computeFirstOfSequence(g: *const Grammar, result: *SymbolSet, symbols: []const u16) !void {
    for (symbols) |symId| {
        const sym = &g.symbols.items[symId];

        if (sym.kind == .terminal) {
            try result.add(g.allocator, symId);
            break;
        } else {
            _ = try result.addAll(g.allocator, &sym.firsts);
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
fn computeFollow(g: *Grammar) !void {
    var changed = true;
    while (changed) {
        changed = false;

        for (g.rules.items) |rule| {
            for (rule.rhs, 0..) |symId, i| {
                const sym = &g.symbols.items[symId];
                if (sym.kind != .nonterminal) continue;

                const oldCount = sym.follows.count();

                if (i == rule.rhs.len - 1) {
                    // A is at end: FOLLOW(LHS) ⊆ FOLLOW(A)
                    if (try sym.follows.addAll(g.allocator, &g.symbols.items[rule.lhs].follows)) {
                        changed = true;
                    }
                } else {
                    // A has symbols after it: add FIRST(β) to FOLLOW(A)
                    const beta = rule.rhs[i + 1 ..];
                    try computeFirstOfSequence(g, &sym.follows, beta);

                    var betaNullable = true;
                    for (beta) |b| {
                        if (!g.symbols.items[b].nullable) {
                            betaNullable = false;
                            break;
                        }
                    }
                    if (betaNullable) {
                        _ = try sym.follows.addAll(g.allocator, &g.symbols.items[rule.lhs].follows);
                    }
                }

                if (sym.follows.count() > oldCount) changed = true;
            }
        }
    }
}

// =============================================================================
// LALR(1) Construction — spontaneous generation + propagation
// (Aho et al., "Compilers", 4.7.5)
// =============================================================================
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
// =============================================================================

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

fn firstOfSuffix(g: *const Grammar, rhs: []const u16, startDot: usize, lookahead: u16) !SymbolSet {
    var result = SymbolSet{};
    var allNullable = true;

    for (rhs[startDot..]) |symId| {
        const sym = &g.symbols.items[symId];
        if (sym.kind == .terminal) {
            try result.add(g.allocator, symId);
            allNullable = false;
            break;
        } else {
            _ = try result.addAll(g.allocator, &sym.firsts);
            if (!sym.nullable) {
                allNullable = false;
                break;
            }
        }
    }

    if (allNullable) {
        try result.add(g.allocator, lookahead);
    }

    return result;
}

fn probeClosure(g: *const Grammar, seedItem: Lr1Item, items: *std.ArrayListUnmanaged(Lr1Item), seen: *std.AutoHashMap(u64, void)) !void {
    seen.clearRetainingCapacity();

    items.clearRetainingCapacity();
    try items.append(g.allocator, seedItem);
    try seen.put(seedItem.key(), {});

    var workIdx: usize = 0;
    while (workIdx < items.items.len) : (workIdx += 1) {
        const item = items.items[workIdx];
        const rule = g.rules.items[item.ruleId];

        if (item.dot >= rule.rhs.len) continue;

        const nextSym = rule.rhs[item.dot];
        const symbol = g.symbols.items[nextSym];

        if (symbol.kind == .nonterminal) {
            var firstSet = try firstOfSuffix(g, rule.rhs, item.dot + 1, item.lookahead);
            defer firstSet.deinit(g.allocator);

            for (symbol.rules.items) |ruleId| {
                for (firstSet.slice()) |la| {
                    const newItem = Lr1Item{ .ruleId = ruleId, .dot = 0, .lookahead = la };
                    if (!seen.contains(newItem.key())) {
                        try seen.put(newItem.key(), {});
                        try items.append(g.allocator, newItem);
                    }
                }
            }
        }
    }
}

fn computeLalrLookaheads(g: *const Grammar, auto: *const Automaton) ![]const []const SymbolSet {
    const a = g.allocator;
    const numStates = auto.states.items.len;
    const sentinel: u16 = std.math.maxInt(u16);
    std.debug.assert(g.symbols.items.len < sentinel);

    // Build offset tables for flat node indexing
    const kernelOffsets = try a.alloc(u32, numStates + 1);
    defer a.free(kernelOffsets);
    const reductionOffsets = try a.alloc(u32, numStates + 1);
    defer a.free(reductionOffsets);

    kernelOffsets[0] = 0;
    reductionOffsets[0] = 0;
    for (0..numStates) |s| {
        kernelOffsets[s + 1] = kernelOffsets[s] + @as(u32, @intCast(auto.states.items[s].kernel.len));
        reductionOffsets[s + 1] = reductionOffsets[s] + @as(u32, @intCast(auto.states.items[s].reductions.len));
    }

    const totalKernelNodes = kernelOffsets[numStates];
    const totalReductionNodes = reductionOffsets[numStates];
    const totalNodes = totalKernelNodes + totalReductionNodes;

    // Lookahead sets for each node (kernel nodes first, then reduction nodes)
    const nodeSets = try a.alloc(SymbolSet, totalNodes);
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
    for (auto.states.items, 0..) |state, si| {
        for (state.kernel, 0..) |kernelItem, ki| {
            const sourceNode: u32 = kernelOffsets[si] + @as(u32, @intCast(ki));

            const seed = Lr1Item{
                .ruleId = kernelItem.ruleId,
                .dot = kernelItem.dot,
                .lookahead = sentinel,
            };
            try probeClosure(g, seed, &closureItems, &seen);

            for (closureItems.items) |cItem| {
                const rule = g.rules.items[cItem.ruleId];

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
                    const advancedItem = Item{ .ruleId = cItem.ruleId, .dot = cItem.dot + 1 };
                    const targetKernel = &auto.states.items[transTarget];
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
    const lalrLookaheads = try a.alloc([]const SymbolSet, numStates);
    for (0..numStates) |si| {
        const nr = auto.states.items[si].reductions.len;
        const sets = try a.alloc(SymbolSet, nr);
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

    return lalrLookaheads;
}
