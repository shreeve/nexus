//! The tolerant-repair table (`@repair`): per state, the tokens the tolerant
//! driver may insert as zero-width tokens at a syntax error, best first.
//!
//! Only tokens the grammar declares fabricable are candidates: `holes`
//! (value-carrying tokens such as IDENT, whose empty value adds no meaning),
//! `structure` (layout tokens such as INDENT, OUTDENT) and `terminator`
//! (structure that ends a statement, such as NEWLINE; the tolerant driver
//! inserts only terminators in front of real input). A token is a
//! candidate in a state when the state has an action for it. Ranking:
//!
//!   1. holes before structure: a hole keeps the construct under the cursor
//!      alive (an editor can resolve into it), even when structure would be
//!      a shorter repair;
//!   2. fewer further fabrications: the minimum, over the state's items that
//!      the token advances, of the terminals the rest of that item still
//!      needs (min-yield costs); a token that only triggers reductions ranks
//!      last within its class;
//!   3. symbol id, for determinism.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const RepairSpec = grammar.RepairSpec;
const Automaton = @import("automaton.zig").Automaton;
const State = @import("automaton.zig").State;
const Lookaheads = @import("lookahead.zig").Lookaheads;
const ParseAction = @import("table.zig").ParseAction;

pub const Repair = struct {
    /// Candidates of state s: `tokens[offsets[s]..offsets[s + 1]]`, best first.
    tokens: []const u16,
    offsets: []const u32,

    pub fn forState(self: Repair, state: usize) []const u16 {
        return self.tokens[self.offsets[state]..self.offsets[state + 1]];
    }
};

/// Cost of a symbol no finite string derives (or of an item nothing advances).
pub const infinite = std.math.maxInt(u32);

/// A `@repair` name that is not a terminal of the parser grammar; `index`
/// counts the names of the three lists in order (see `RepairSpec.locOf`).
pub const BadToken = struct { name: []const u8, reason: []const u8, index: usize };

/// Check the `@repair` names: each must be a terminal the parser grammar
/// uses, and appear once. Returns the first offending name.
pub fn validate(g: *const Grammar, spec: RepairSpec) ?BadToken {
    const lists = [_][]const []const u8{ spec.holes, spec.structure, spec.terminators };
    var index: usize = 0;
    for (lists, 0..) |list, li| {
        for (list, 0..) |name, i| {
            defer index += 1;
            const sym = g.getSymbol(name) orelse
                return .{ .name = name, .reason = "is not a token the parser grammar uses", .index = index };
            if (g.symbols.items[sym].kind != .terminal)
                return .{ .name = name, .reason = "is a rule, not a token", .index = index };
            if (sym == g.endId or sym == g.errorId)
                return .{ .name = name, .reason = "can never be inserted", .index = index };
            for (lists[0 .. li + 1], 0..) |earlier, lj| {
                const upto = if (lj == li) i else earlier.len;
                for (earlier[0..upto]) |other| {
                    if (g.getSymbol(other) == sym)
                        return .{ .name = name, .reason = "is listed twice", .index = index };
                }
            }
        }
    }
    return null;
}

/// Minimal number of terminals each symbol derives: 1 for a terminal, the
/// cheapest rule for a nonterminal (0 for ε), `infinite` if it derives no
/// finite string. Knuth's generalization of Dijkstra's algorithm: symbols
/// settle cheapest first, and a rule offers its lhs a cost once every
/// symbol of its right-hand side has settled, so the time is linear in the
/// grammar's size (times a heap's log), whatever its depth.
pub fn insertCosts(a: Allocator, g: *const Grammar) ![]u32 {
    const n = g.symbols.items.len;
    const rules = g.rules.items;
    // Every occurrence of a symbol in a right-hand side, by symbol:
    // the rules of sym's occurrences are users[start[sym]..start[sym + 1]].
    const start = try a.alloc(u32, n + 1);
    defer a.free(start);
    @memset(start, 0);
    for (rules) |rule| for (rule.rhs) |s| {
        start[s + 1] += 1;
    };
    for (1..n + 1) |i| start[i] += start[i - 1];
    const users = try a.alloc(u16, start[n]);
    defer a.free(users);
    const fill = try a.dupe(u32, start[0..n]);
    defer a.free(fill);
    for (rules, 0..) |rule, r| for (rule.rhs) |s| {
        users[fill[s]] = @intCast(r);
        fill[s] += 1;
    };
    // Per rule: right-hand-side occurrences not yet settled, and the cost so far.
    const pending = try a.alloc(u32, rules.len);
    defer a.free(pending);
    const sum = try a.alloc(u32, rules.len);
    defer a.free(sum);

    const Offer = struct { cost: u32, sym: u16 };
    var heap: std.PriorityQueue(Offer, void, struct {
        fn order(_: void, x: Offer, y: Offer) std.math.Order {
            return std.math.order(x.cost, y.cost);
        }
    }.order) = .empty;
    defer heap.deinit(a);
    for (rules, 0..) |rule, r| {
        pending[r] = @intCast(rule.rhs.len);
        sum[r] = 0;
        if (rule.rhs.len == 0) try heap.push(a, .{ .cost = 0, .sym = rule.lhs });
    }
    for (g.symbols.items, 0..) |sym, i| {
        if (sym.kind == .terminal) try heap.push(a, .{ .cost = 1, .sym = @intCast(i) });
    }

    const costs = try a.alloc(u32, n);
    @memset(costs, infinite);
    while (heap.pop()) |offer| {
        if (costs[offer.sym] != infinite) continue;
        costs[offer.sym] = offer.cost;
        for (users[start[offer.sym]..start[offer.sym + 1]]) |r| {
            sum[r] +|= offer.cost;
            pending[r] -= 1;
            if (pending[r] == 0) try heap.push(a, .{ .cost = sum[r], .sym = rules[r].lhs });
        }
    }
    return costs;
}

fn seqCost(costs: []const u32, seq: []const u16) u32 {
    var total: u32 = 0;
    for (seq) |s| total +|= costs[s];
    return total;
}

/// How many more fabrications inserting `token` in `state` commits to: the
/// minimum over the items `token` advances (directly, or as the first
/// terminal of the nonterminal after the dot) of the rest of that item. For
/// the nonterminal case this is a lower bound (the nonterminal's cheapest
/// yield less the inserted token itself).
pub fn costAt(g: *const Grammar, la: Lookaheads, state: State, token: u16) u32 {
    const costs = la.costs;
    var best: u32 = infinite;
    for (state.items) |item| {
        const rhs = g.rules.items[item.ruleId].rhs;
        if (item.dot >= rhs.len) continue;
        const head = rhs[item.dot];
        const rest = seqCost(costs, rhs[item.dot + 1 ..]);
        if (head == token) {
            best = @min(best, rest);
        } else if (g.symbols.items[head].kind == .nonterminal and la.first.get(head).isSet(token)) {
            best = @min(best, (costs[head] -| 1) +| rest);
        }
    }
    return best;
}

/// The candidates of every state; `spec` has passed `validate`.
pub fn compute(g: *const Grammar, auto: *const Automaton, la: Lookaheads, rows: []const []const ParseAction, spec: RepairSpec) Allocator.Error!Repair {
    const a = g.allocator;

    const Candidate = struct { id: u16, class: u8, cost: u32 };
    var candidates: std.ArrayList(Candidate) = .empty;
    defer candidates.deinit(a);
    var tokens: std.ArrayList(u16) = .empty;
    const offsets = try a.alloc(u32, auto.states.items.len + 1);
    offsets[0] = 0;

    for (auto.states.items, 0..) |state, si| {
        candidates.clearRetainingCapacity();
        // Terminators rank as structure.
        const classes = [_]struct { []const []const u8, u8 }{ .{ spec.holes, 0 }, .{ spec.structure, 1 }, .{ spec.terminators, 1 } };
        for (classes) |c| {
            for (c[0]) |name| {
                const id = g.getSymbol(name).?;
                if (rows[si][id] == .err) continue;
                try candidates.append(a, .{ .id = id, .class = c[1], .cost = costAt(g, la, state, id) });
            }
        }
        std.mem.sort(Candidate, candidates.items, {}, struct {
            fn lessThan(_: void, x: Candidate, y: Candidate) bool {
                if (x.class != y.class) return x.class < y.class;
                if (x.cost != y.cost) return x.cost < y.cost;
                return x.id < y.id;
            }
        }.lessThan);
        for (candidates.items) |c| try tokens.append(a, c.id);
        offsets[si + 1] = @intCast(tokens.items.len);
    }
    return .{ .tokens = try tokens.toOwnedSlice(a), .offsets = offsets };
}
