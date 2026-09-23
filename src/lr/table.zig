//! Parse table construction: ACTION/GOTO from the automaton and lookaheads,
//! conflict resolution (`X "c"` hints, `<`/`>` hints, default shift, lowest
//! rule wins reduce/reduce), and the derived tables codegen emits: expected
//! sets for diagnostics and tolerant-repair candidates.
//!
//! Generated parsers index ACTION/GOTO densely ([state][symbol]). A
//! row-displacement (comb vector) form was measured and rejected: it made
//! the MUMPS parser 256 KB smaller but parsed 5-10% slower (MUMPS and Rig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const Rule = grammar.Rule;
const Automaton = @import("automaton.zig").Automaton;
const Lookaheads = @import("lookahead.zig").Lookaheads;
const bitset = @import("bitset.zig");
const SetArray = bitset.SetArray;
const expected = @import("expected.zig");
const repair = @import("repair.zig");

// =============================================================================
// Parse Table Generation
// =============================================================================
//
// The parse table encodes parser decisions as ACTION and GOTO:
//
//   ACTION[state, terminal] = shift s  | reduce r | accept | error
//   GOTO[state, nonterminal] = state s | error
//
//   1. SHIFT: If state has A → α • a β (a = terminal), ACTION[state, a] = shift
//   2. REDUCE: If state has A → α • and a ∈ lookahead(state, item), reduce
//   3. GOTO: If GOTO(state, A) = s for nonterminal A, GOTO[state, A] = s
//   4. ACCEPT: If state has S' → S • $ (or S' → S $ •), ACTION[state, $] = accept
//
// Each cell is resolved once, from everything that wants it: the shift (or
// accept) and the set R of reductions whose lookahead contains the terminal.
//
//   - No shift: the lowest-numbered rule of R reduces; every other rule of R
//     is a reduce/reduce conflict ("winner over loser").
//   - Shift: the rules of R that beat a shift are those with `<` and those
//     with an `X "c"` hint for this terminal's character. If there are none,
//     the shift stays and every rule of R without `>` is a shift/reduce
//     conflict. Otherwise the lowest such rule reduces (an `X "c"` win also
//     records the runtime shift override) and the rest of R are
//     reduce/reduce conflicts.
//   - Accept: always kept; every rule of R without `>` is a conflict.
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

/// One unresolved conflict in one cell (state, terminal).
pub const Conflict = struct {
    state: u16,
    terminal: u16,
    kind: Kind,
    /// `.shift`: the rule whose reduction lost to the default shift (or to
    /// accept). `.reduce`: the rule that reduces (the lowest-numbered).
    rule: u16,
    /// `.reduce`: the rule whose reduction was dropped.
    over: u16 = 0,

    pub const Kind = enum { shift, reduce };
};

/// An `X "c"` hint: whether it decided any cell.
pub const HintUse = struct {
    rule: u16,
    char: u8,
    used: bool,
};

pub const Table = struct {
    /// ACTION/GOTO, indexed [state][symbol].
    rows: [][]ParseAction,
    /// Sorted by state (then by terminal id). State s's overrides are
    /// `xExcludes.items[xExcludeStart[s]..xExcludeStart[s + 1]]`.
    xExcludes: std.ArrayListUnmanaged(XExclude) = .empty,
    xExcludeStart: []const u32,
    /// Number of unresolved conflicts (= conflictList.len).
    conflicts: u32 = 0,
    /// Every unresolved conflict, by state, then terminal.
    conflictList: []const Conflict = &.{},
    /// Every `X "c"` hint of every rule, in rule order.
    hints: []const HintUse = &.{},
    /// Expected symbols per state, for syntax-error messages.
    expected: expected.Expected,
    /// Tolerant-repair insertion candidates per state (grammars with `@repair`).
    repair: ?repair.Repair = null,
};

/// The characters of a rule's `X "c"` hints.
pub fn hintChars(rule: *const Rule) []const u8 {
    return rule.excludeChars;
}

/// The character of a one-character literal terminal (`"("`), else null.
pub fn literalChar(g: *const Grammar, sym: u16) ?u8 {
    const name = g.symbols.items[sym].name;
    if (name.len == 3 and name[0] == '"' and name[2] == '"') return name[1];
    return null;
}

/// Whether `sym` is the synthetic marker terminal (`name!`) that selects a
/// start symbol; markers never appear in reports or expected sets.
pub fn isStartMarker(g: *const Grammar, sym: u16) bool {
    const name = g.symbols.items[sym].name;
    if (name.len < 2 or name[name.len - 1] != '!') return false;
    for (g.startSymbols.items) |s| {
        if (std.mem.eql(u8, g.symbols.items[s].name, name[0 .. name.len - 1])) return true;
    }
    return false;
}

pub fn build(g: *const Grammar, auto: *const Automaton, la: Lookaheads) !Table {
    const a = g.allocator;
    const numStates = auto.states.items.len;
    const numSymbols = g.symbols.items.len;

    const rows = try a.alloc([]ParseAction, numStates);
    var xExcludes: std.ArrayListUnmanaged(XExclude) = .empty;
    var conflictList: std.ArrayListUnmanaged(Conflict) = .empty;

    // Hint bookkeeping: hints[hintStart[r]..][0..hintChars(r).len] are rule r's.
    const hintStart = try a.alloc(u32, g.rules.items.len);
    defer a.free(hintStart);
    var hints: std.ArrayListUnmanaged(HintUse) = .empty;
    for (g.rules.items, 0..) |*rule, r| {
        hintStart[r] = @intCast(hints.items.len);
        for (hintChars(rule)) |c| try hints.append(a, .{ .rule = @intCast(r), .char = c, .used = false });
    }

    var reduceUnion = try SetArray.init(a, 1, numSymbols);
    defer reduceUnion.deinit(a);
    const cellTerminals = reduceUnion.get(0);
    var cellRules: std.ArrayListUnmanaged(u16) = .empty;
    defer cellRules.deinit(a);

    for (rows, 0..) |*rowSlot, si| {
        const row = try a.alloc(ParseAction, numSymbols);
        rowSlot.* = row;
        @memset(row, .err);
        const state = &auto.states.items[si];

        for (state.transitions) |trans| {
            row[trans.symbol] = if (g.symbols.items[trans.symbol].kind == .nonterminal)
                .{ .gotoState = trans.target }
            else
                .{ .shift = trans.target };
        }
        for (state.items) |item| {
            const rule = &g.rules.items[item.ruleId];
            if (g.isAcceptRule(item.ruleId) and
                (item.dot == rule.rhs.len or rule.rhs[item.dot] == g.endId))
                row[g.endId] = .accept;
        }

        // Terminals some (non-accept) reduction wants in this state.
        cellTerminals.clear();
        for (state.reductions, 0..) |item, ri| {
            if (g.isAcceptRule(item.ruleId)) continue;
            _ = cellTerminals.unionWith(la.sets[si][ri]);
        }

        var it = cellTerminals.iterator();
        while (it.next()) |t| {
            cellRules.clearRetainingCapacity();
            for (state.reductions, 0..) |item, ri| {
                if (g.isAcceptRule(item.ruleId)) continue;
                if (la.sets[si][ri].isSet(t)) try cellRules.append(a, item.ruleId);
            }
            std.mem.sort(u16, cellRules.items, {}, std.sort.asc(u16));
            const cell = &row[t];
            const ch = literalChar(g, t);

            switch (cell.*) {
                .err => {
                    const winner = cellRules.items[0];
                    cell.* = .{ .reduce = winner };
                    for (cellRules.items[1..]) |r| try conflictList.append(a, .{
                        .state = @intCast(si),
                        .terminal = t,
                        .kind = .reduce,
                        .rule = winner,
                        .over = r,
                    });
                },
                .shift => |target| {
                    // The lowest rule that beats the shift, and whether by X "c".
                    var winner: ?u16 = null;
                    var byHint = false;
                    for (cellRules.items) |r| {
                        const rule = &g.rules.items[r];
                        var hinted = false;
                        if (ch) |c| {
                            for (hintChars(rule), 0..) |hc, k| {
                                if (hc == c) {
                                    hints.items[hintStart[r] + k].used = true;
                                    hinted = true;
                                }
                            }
                        }
                        if (winner == null and (hinted or rule.preferReduce)) {
                            winner = r;
                            byHint = hinted;
                        }
                    }
                    if (winner) |w| {
                        cell.* = .{ .reduce = w };
                        if (byHint) try xExcludes.append(a, .{ .state = @intCast(si), .char = ch.?, .shift = target });
                        for (cellRules.items) |r| {
                            if (r != w) try conflictList.append(a, .{
                                .state = @intCast(si),
                                .terminal = t,
                                .kind = .reduce,
                                .rule = w,
                                .over = r,
                            });
                        }
                    } else {
                        for (cellRules.items) |r| {
                            if (!g.rules.items[r].preferShift) try conflictList.append(a, .{
                                .state = @intCast(si),
                                .terminal = t,
                                .kind = .shift,
                                .rule = r,
                            });
                        }
                    }
                },
                .accept => {
                    for (cellRules.items) |r| {
                        if (!g.rules.items[r].preferShift) try conflictList.append(a, .{
                            .state = @intCast(si),
                            .terminal = t,
                            .kind = .shift,
                            .rule = r,
                        });
                    }
                },
                .reduce, .gotoState => unreachable,
            }
        }
    }

    const xExcludeStart = try a.alloc(u32, numStates + 1);
    @memset(xExcludeStart, 0);
    for (xExcludes.items) |x| xExcludeStart[x.state + 1] += 1;
    for (1..numStates + 1) |s| xExcludeStart[s] += xExcludeStart[s - 1];

    const exp = try expected.compute(g, auto, la, rows);
    const rep: ?repair.Repair = if (g.repair) |spec| try repair.compute(g, auto, la, rows, spec) else null;

    return .{
        .rows = rows,
        .xExcludes = xExcludes,
        .xExcludeStart = xExcludeStart,
        .conflicts = @intCast(conflictList.items.len),
        .conflictList = try conflictList.toOwnedSlice(a),
        .hints = try hints.toOwnedSlice(a),
        .expected = exp,
        .repair = rep,
    };
}
