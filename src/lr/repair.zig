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

pub const Error = error{ OutOfMemory, InvalidRepairToken };

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
/// finite string (fixed point).
pub fn insertCosts(a: Allocator, g: *const Grammar) ![]u32 {
    const costs = try a.alloc(u32, g.symbols.items.len);
    for (g.symbols.items, 0..) |sym, i| costs[i] = if (sym.kind == .terminal) 1 else infinite;
    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            const total = seqCost(costs, rule.rhs);
            if (total < costs[rule.lhs]) {
                costs[rule.lhs] = total;
                changed = true;
            }
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
pub fn costAt(g: *const Grammar, la: Lookaheads, costs: []const u32, state: State, token: u16) u32 {
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

pub fn compute(g: *const Grammar, auto: *const Automaton, la: Lookaheads, rows: []const []const ParseAction, spec: RepairSpec) Error!Repair {
    const a = g.allocator;
    if (validate(g, spec) != null) return error.InvalidRepairToken;
    const costs = try insertCosts(a, g);
    defer a.free(costs);

    const Candidate = struct { id: u16, class: u8, cost: u32 };
    var candidates: std.ArrayListUnmanaged(Candidate) = .empty;
    defer candidates.deinit(a);
    var tokens: std.ArrayListUnmanaged(u16) = .empty;
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
                try candidates.append(a, .{ .id = id, .class = c[1], .cost = costAt(g, la, costs, state, id) });
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
