//! Parse table construction with conflict resolution (`X "c"` exclusions,
//! `<`/`>` hints, default shift, lowest rule wins reduce/reduce).

const std = @import("std");
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const Automaton = @import("automaton.zig").Automaton;
const Lookaheads = @import("lookahead.zig").Lookaheads;
const ConflictDetail = @import("conflicts.zig").ConflictDetail;

// =============================================================================
// Parse Table Generation
// =============================================================================
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
// =============================================================================

pub const ParseAction = union(enum) {
    shift: u16,
    reduce: u16,
    gotoState: u16,
    accept: void,
    err: void,
};

/// `X "c"` exclusion: in `state`, the table reduces, but the runtime shifts to
/// `shift` instead when no whitespace precedes and the next byte is `char`.
pub const XExclude = struct { state: u16, char: u8, shift: u16 };

pub const Table = struct {
    /// ACTION/GOTO, indexed [state][symbol].
    rows: [][]ParseAction,
    xExcludes: std.ArrayListUnmanaged(XExclude) = .empty,
    /// Unresolved conflicts (default shift, or lowest rule for reduce/reduce).
    conflicts: u32 = 0,
    conflictDetails: std.ArrayListUnmanaged(ConflictDetail) = .empty,
};

pub fn build(g: *const Grammar, auto: *const Automaton, la: Lookaheads) !Table {
    const numStates = auto.states.items.len;
    const numSymbols = g.symbols.items.len;

    var t: Table = .{ .rows = try g.allocator.alloc([]ParseAction, numStates) };
    const table = t.rows;
    for (table, 0..) |*row, i| {
        row.* = try g.allocator.alloc(ParseAction, numSymbols);
        for (row.*) |*cell| cell.* = .err;

        const state = &auto.states.items[i];

        // Shift/goto actions
        for (state.transitions) |trans| {
            const sym = &g.symbols.items[trans.symbol];
            if (sym.kind == .nonterminal) {
                row.*[trans.symbol] = .{ .gotoState = trans.target };
            } else {
                row.*[trans.symbol] = .{ .shift = trans.target };
            }
        }

        // Accept action
        for (state.items) |item| {
            const rule = &g.rules.items[item.ruleId];
            if (item.dot < rule.rhs.len and rule.rhs[item.dot] == g.endId) {
                if (g.isAcceptRule(item.ruleId)) {
                    row.*[g.endId] = .accept;
                }
            }
        }

        // Reduce actions
        for (state.reductions, 0..) |item, ri| {
            const rule = &g.rules.items[item.ruleId];

            if (g.isAcceptRule(item.ruleId)) {
                row.*[g.endId] = .accept;
                continue;
            }

            const lhsSym = &g.symbols.items[rule.lhs];

            const reduceTerminals = switch (la.mode) {
                .slr => lhsSym.follows.slice(),
                .lalr => la.lalr[i][ri].slice(),
            };

            for (reduceTerminals) |followId| {
                const current = &row.*[followId];
                const fname = g.symbols.items[followId].name;
                const xChar = if (fname.len == 3) fname[1] else 0;

                switch (current.*) {
                    .err => current.* = .{ .reduce = item.ruleId },
                    .shift => |s| {
                        if (rule.excludeChar != 0 and xChar == rule.excludeChar) {
                            current.* = .{ .reduce = item.ruleId };
                            try t.xExcludes.append(g.allocator, .{
                                .state = @intCast(i),
                                .char = xChar,
                                .shift = s,
                            });
                        } else if (rule.preferReduce) {
                            current.* = .{ .reduce = item.ruleId };
                        } else if (rule.preferShift) {
                            // > hint: keep shift
                        } else {
                            t.conflicts += 1;
                            try t.conflictDetails.append(g.allocator, .{
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
                        t.conflicts += 1;
                        const existingRule = &g.rules.items[existing];
                        try t.conflictDetails.append(g.allocator, .{
                            .kind = .reduceReduce,
                            .nameA = lhsSym.name,
                            .nameB = g.symbols.items[existingRule.lhs].name,
                        });
                    },
                    else => {},
                }
            }
        }
    }

    return t;
}
