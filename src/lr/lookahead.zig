//! Lookahead sets for reductions: nullable and FIRST for every symbol, then
//! either FOLLOW(lhs) (SLR(1)) or the LALR(1) lookaheads computed by the
//! DeRemer–Pennello relations over the LR(0) automaton.
//!
//! Every set is a bit set over symbol ids (only terminal bits are ever set).

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const automaton = @import("automaton.zig");
const Automaton = automaton.Automaton;
const bitset = @import("bitset.zig");
const BitSet = bitset.BitSet;
const SetArray = bitset.SetArray;

pub const ParseMode = enum { lalr, slr };

/// The lookahead set of every reduction: `sets[state][i]` belongs to the i-th
/// reduction item of `state` (`State.reductions[i]`). In SLR mode the sets
/// of reductions with the same lhs are the same FOLLOW set. `first[sym]` is
/// FIRST(sym) (for a terminal, the terminal itself); `nullable[sym]` says
/// whether sym derives the empty string.
pub const Lookaheads = struct {
    mode: ParseMode,
    sets: []const []const BitSet,
    first: SetArray,
    nullable: []const bool,
};

pub fn compute(g: *const Grammar, auto: *const Automaton, mode: ParseMode) !Lookaheads {
    const a = g.allocator;
    const nullable = try computeNullable(g);
    const first = try computeFirst(g, nullable);

    const sets = switch (mode) {
        .slr => try slrSets(g, auto, nullable, first),
        .lalr => try lalrSets(a, g, auto, nullable),
    };
    return .{ .mode = mode, .sets = sets, .first = first, .nullable = nullable };
}

// =============================================================================
// Nullable and FIRST
// =============================================================================
//
// FIRST(X) = the terminals that can begin a string derived from X:
//   FIRST(t) = { t } for a terminal t;
//   FIRST(A) = the union of FIRST(rhs) over A's rules, where
//   FIRST(X1 X2 ... Xn) = FIRST(X1) ∪ (FIRST(X2 ... Xn) if X1 is nullable).
//
// =============================================================================

/// Which symbols derive ε (fixed point).
fn computeNullable(g: *const Grammar) ![]bool {
    const nullable = try g.allocator.alloc(bool, g.symbols.items.len);
    @memset(nullable, false);

    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            if (nullable[rule.lhs]) continue;
            const all = for (rule.rhs) |s| {
                if (!nullable[s]) break false;
            } else true;
            if (all) {
                nullable[rule.lhs] = true;
                changed = true;
            }
        }
    }
    return nullable;
}

fn computeFirst(g: *const Grammar, nullable: []const bool) !SetArray {
    const n = g.symbols.items.len;
    const first = try SetArray.init(g.allocator, n, n);
    for (g.symbols.items, 0..) |sym, i| {
        if (sym.kind == .terminal) first.get(i).set(i);
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            const lhs = first.get(rule.lhs);
            for (rule.rhs) |s| {
                if (lhs.unionWith(first.get(s))) changed = true;
                if (!nullable[s]) break;
            }
        }
    }
    return first;
}

// =============================================================================
// SLR(1): FOLLOW sets
// =============================================================================
//
// FOLLOW(A) = the terminals that can appear right after A:
//   for every rule B → α A β: FIRST(β) ⊆ FOLLOW(A), and
//   FOLLOW(B) ⊆ FOLLOW(A) when β is nullable.
//
// =============================================================================

fn slrSets(g: *const Grammar, auto: *const Automaton, nullable: []const bool, first: SetArray) ![]const []const BitSet {
    const a = g.allocator;
    const n = g.symbols.items.len;
    const follow = try SetArray.init(a, n, n);

    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            // Walk right to left, carrying "FIRST of the rest, plus FOLLOW(lhs)
            // while the rest is nullable".
            var restNullable = true;
            var i = rule.rhs.len;
            while (i > 0) {
                i -= 1;
                const s = rule.rhs[i];
                if (g.symbols.items[s].kind == .nonterminal) {
                    const f = follow.get(s);
                    if (restNullable and f.unionWith(follow.get(rule.lhs))) changed = true;
                    var j = i + 1;
                    while (j < rule.rhs.len) : (j += 1) {
                        if (f.unionWith(first.get(rule.rhs[j]))) changed = true;
                        if (!nullable[rule.rhs[j]]) break;
                    }
                }
                if (!nullable[s]) restNullable = false;
            }
        }
    }

    const sets = try a.alloc([]const BitSet, auto.states.items.len);
    for (auto.states.items, 0..) |state, si| {
        const row = try a.alloc(BitSet, state.reductions.len);
        for (state.reductions, 0..) |item, ri| row[ri] = follow.get(g.rules.items[item.ruleId].lhs);
        sets[si] = row;
    }
    return sets;
}

// =============================================================================
// LALR(1): DeRemer & Pennello, "Efficient Computation of LALR(1) Look-Ahead
// Sets" (TOPLAS 1982)
// =============================================================================
//
// Work over the nonterminal transitions (p, A) of the LR(0) automaton:
//
//   DR(p, A)     = terminals t with a transition on t out of goto(p, A)
//   (p, A) reads (r, C)       iff  r = goto(p, A), C nullable, r has a C transition
//   Read(p, A)   = DR(p, A) ∪ ⋃ { Read(r, C) | (p, A) reads (r, C) }
//   (p, A) includes (p', B)   iff  B → β A γ, γ nullable, p = goto*(p', β)
//   Follow(p, A) = Read(p, A) ∪ ⋃ { Follow(p', B) | (p, A) includes (p', B) }
//   (q, A → ω) lookback (p, A) iff q = goto*(p, ω)
//   LA(q, A → ω) = ⋃ { Follow(p, A) | (q, A → ω) lookback (p, A) }
//
// Read and Follow are unions over a relation; `digraph` computes them in one
// pass, collapsing strongly connected components (every member of an SCC
// gets the same set).
//
// =============================================================================

const none = std.math.maxInt(u32);

/// A relation over transition indices as adjacency lists (CSR form).
const Relation = struct {
    offsets: []u32,
    targets: []u32,

    fn build(a: Allocator, n: usize, edges: []const [2]u32) !Relation {
        const offsets = try a.alloc(u32, n + 1);
        @memset(offsets, 0);
        for (edges) |e| offsets[e[0] + 1] += 1;
        for (1..n + 1) |i| offsets[i] += offsets[i - 1];
        const targets = try a.alloc(u32, edges.len);
        const fill = try a.dupe(u32, offsets[0..n]);
        defer a.free(fill);
        for (edges) |e| {
            targets[fill[e[0]]] = e[1];
            fill[e[0]] += 1;
        }
        return .{ .offsets = offsets, .targets = targets };
    }
};

/// F(x) := F(x) ∪ ⋃ { F(y) | x R y }, for every x, in place (the digraph
/// algorithm, iterative).
fn digraph(a: Allocator, rel: Relation, sets: SetArray) !void {
    const n = sets.len;
    const depth = try a.alloc(u32, n); // 0 = unvisited, none = done
    defer a.free(depth);
    @memset(depth, 0);
    var stack: std.ArrayListUnmanaged(u32) = .empty;
    defer stack.deinit(a);
    // A traversal frame: node, next edge to visit, and x's stack depth.
    const Frame = struct { x: u32, edge: u32, d: u32 };
    var frames: std.ArrayListUnmanaged(Frame) = .empty;
    defer frames.deinit(a);

    for (0..n) |start| {
        if (depth[start] != 0) continue;
        try stack.append(a, @intCast(start));
        depth[start] = @intCast(stack.items.len);
        try frames.append(a, .{ .x = @intCast(start), .edge = rel.offsets[start], .d = depth[start] });

        while (frames.items.len > 0) {
            const top = &frames.items[frames.items.len - 1];
            const x = top.x;
            if (top.edge < rel.offsets[x + 1]) {
                const y = rel.targets[top.edge];
                top.edge += 1;
                if (depth[y] == 0) {
                    try stack.append(a, y);
                    depth[y] = @intCast(stack.items.len);
                    try frames.append(a, .{ .x = y, .edge = rel.offsets[y], .d = depth[y] });
                } else {
                    // y is done or on the stack: fold it in now.
                    depth[x] = @min(depth[x], depth[y]);
                    _ = sets.get(x).unionWith(sets.get(y));
                }
                continue;
            }

            // All successors of x visited.
            const d = frames.pop().?.d;
            if (depth[x] == d) {
                // x is the root of an SCC: every member gets x's set.
                while (true) {
                    const m = stack.pop().?;
                    depth[m] = none;
                    if (m == x) break;
                    sets.get(m).copyFrom(sets.get(x));
                }
            }
            if (frames.items.len > 0) {
                const parent = frames.items[frames.items.len - 1].x;
                depth[parent] = @min(depth[parent], depth[x]);
                _ = sets.get(parent).unionWith(sets.get(x));
            }
        }
    }
}

fn lalrSets(a: Allocator, g: *const Grammar, auto: *const Automaton, nullable: []const bool) ![]const []const BitSet {
    const numStates = auto.states.items.len;
    const numSymbols = g.symbols.items.len;
    const states = auto.states.items;

    // Dense goto table and the index of every nonterminal transition.
    const gotoOf = try a.alloc(u32, numStates * numSymbols);
    defer a.free(gotoOf);
    @memset(gotoOf, none);
    const ntIndex = try a.alloc(u32, numStates * numSymbols);
    defer a.free(ntIndex);
    @memset(ntIndex, none);

    var ntFrom: std.ArrayListUnmanaged(u32) = .empty; // source state per transition
    defer ntFrom.deinit(a);
    var ntSym: std.ArrayListUnmanaged(u16) = .empty;
    defer ntSym.deinit(a);
    for (states, 0..) |state, p| {
        for (state.transitions) |t| {
            gotoOf[p * numSymbols + t.symbol] = t.target;
            if (g.symbols.items[t.symbol].kind == .nonterminal) {
                ntIndex[p * numSymbols + t.symbol] = @intCast(ntFrom.items.len);
                try ntFrom.append(a, @intCast(p));
                try ntSym.append(a, t.symbol);
            }
        }
    }
    const numNt = ntFrom.items.len;

    // DR and reads.
    const follow = try SetArray.init(a, numNt, numSymbols);
    var edges: std.ArrayListUnmanaged([2]u32) = .empty;
    defer edges.deinit(a);
    for (0..numNt) |x| {
        const r = gotoOf[ntFrom.items[x] * numSymbols + ntSym.items[x]];
        for (states[r].transitions) |t| {
            if (g.symbols.items[t.symbol].kind == .terminal) {
                follow.get(x).set(t.symbol);
            } else if (nullable[t.symbol]) {
                try edges.append(a, .{ @intCast(x), ntIndex[r * numSymbols + t.symbol] });
            }
        }
    }
    const reads = try Relation.build(a, numNt, edges.items);
    try digraph(a, reads, follow);

    // includes and lookback, by walking every rule of every transition's
    // nonterminal from the transition's source state.
    edges.clearRetainingCapacity();
    const Lookback = struct { state: u32, rule: u16, nt: u32 };
    var lookbacks: std.ArrayListUnmanaged(Lookback) = .empty;
    defer lookbacks.deinit(a);
    for (0..numNt) |x| {
        const p0 = ntFrom.items[x];
        const lhs = ntSym.items[x];
        for (g.symbols.items[lhs].rules.items) |ruleId| {
            const rhs = g.rules.items[ruleId].rhs;
            // rhs[nullableFrom..] is the longest nullable suffix.
            var nullableFrom = rhs.len;
            while (nullableFrom > 0 and nullable[rhs[nullableFrom - 1]]) nullableFrom -= 1;

            var p = p0;
            for (rhs, 0..) |s, i| {
                if (g.symbols.items[s].kind == .nonterminal and i + 1 >= nullableFrom) {
                    try edges.append(a, .{ ntIndex[p * numSymbols + s], @intCast(x) });
                }
                p = gotoOf[p * numSymbols + s];
                std.debug.assert(p != none);
            }
            try lookbacks.append(a, .{ .state = p, .rule = ruleId, .nt = @intCast(x) });
        }
    }
    const includes = try Relation.build(a, numNt, edges.items);
    try digraph(a, includes, follow);

    // LA(q, A → ω) = ⋃ Follow(p, A) over lookback.
    var total: usize = 0;
    for (states) |state| total += state.reductions.len;
    const laSets = try SetArray.init(a, total, numSymbols);
    const sets = try a.alloc([]const BitSet, numStates);
    const firstReduction = try a.alloc(u32, numStates);
    defer a.free(firstReduction);
    var next: usize = 0;
    for (states, 0..) |state, q| {
        firstReduction[q] = @intCast(next);
        const row = try a.alloc(BitSet, state.reductions.len);
        for (row, 0..) |*s, i| s.* = laSets.get(next + i);
        sets[q] = row;
        next += state.reductions.len;
    }
    for (lookbacks.items) |lb| {
        const reductions = states[lb.state].reductions;
        const ri = for (reductions, 0..) |item, i| {
            if (item.ruleId == lb.rule) break i;
        } else unreachable;
        _ = laSets.get(firstReduction[lb.state] + ri).unionWith(follow.get(lb.nt));
    }
    return sets;
}
