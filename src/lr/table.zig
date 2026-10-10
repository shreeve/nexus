//! Parse table construction: ACTION/GOTO from the automaton and lookaheads,
//! conflict resolution (`X "c"` hints, `<`/`>` hints, default shift, lowest
//! rule wins reduce/reduce), and the derived tables codegen emits: expected
//! sets for diagnostics and tolerant-repair candidates.
//!
//! Generated parsers index ACTION/GOTO densely ([state][symbol]): a
//! row-displacement form makes the MUMPS parser smaller and parsing slower.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
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
//     with an `X "c"` hint naming this terminal (check.resolveHints). If none,
//     the shift stays and every rule of R without `>` is a shift/reduce
//     conflict. Otherwise the lowest such rule reduces (an `X "c"` win also
//     records the runtime shift override) and the rest of R are
//     reduce/reduce conflicts.
//   - Accept: always kept; every rule of R without `>` is a conflict.
//   - Folded `@infix`: a shift of an operator against the reduction of one
//     operator rule of the same table goes by their precedence (yacc's
//     %left / %right / %nonassoc); it is not a conflict.
//
// =============================================================================

pub const ParseAction = union(enum) {
    shift: u16,
    reduce: u16,
    gotoState: u16,
    accept: void,
    err: void,
};

/// `X "c"` exclusion: in `state`, the table reduces on terminal `sym`, but the
/// runtime shifts to `shift` instead when no whitespace precedes the token.
pub const XExclude = struct { state: u16, sym: u16, shift: u16 };

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

/// An `X "c"` hint: the terminal it names, and whether it decided any cell.
pub const HintUse = struct {
    rule: u16,
    char: u8,
    terminal: u16,
    used: bool = false,
};

pub const Table = struct {
    /// ACTION/GOTO, indexed [state][symbol].
    rows: [][]ParseAction,
    /// Sorted by state (then by terminal id). State s's overrides are
    /// `xExcludes.items[xExcludeStart[s]..xExcludeStart[s + 1]]`.
    xExcludes: std.ArrayList(XExclude) = .empty,
    xExcludeStart: []const u32,
    /// Every unresolved conflict, by state, then terminal.
    conflictList: []const Conflict = &.{},
    /// Every `X "c"` hint of every rule, in rule order.
    hints: []const HintUse = &.{},
    /// Expected symbols per state, for syntax-error messages.
    expected: expected.Expected,
    /// Tolerant-repair insertion candidates per state (grammars with `@repair`).
    repair: ?repair.Repair = null,
};

/// Whether `sym` is the marker terminal (`x!`) that selects a start symbol:
/// the first symbol of an accept rule `$accept_x → x! x $end`. Markers never
/// appear in reports or expected sets.
pub fn isStartMarker(g: *const Grammar, sym: u16) bool {
    for (g.acceptRules.items) |r| {
        const rhs = g.rules.items[r].rhs;
        if (rhs.len == 3 and rhs[0] == sym) return true;
    }
    return false;
}

pub fn build(g: *const Grammar, auto: *const Automaton, la: Lookaheads) !Table {
    const a = g.allocator;
    const numStates = auto.states.items.len;
    const numSymbols = g.symbols.items.len;

    const rows = try a.alloc([]ParseAction, numStates);
    var xExcludes: std.ArrayList(XExclude) = .empty;
    var conflictList: std.ArrayList(Conflict) = .empty;

    // Every hint and its terminal: rule r's hints are
    // hints[hintStart[r]..hintStart[r + 1]].
    const hintStart = try a.alloc(u32, g.rules.items.len + 1);
    defer a.free(hintStart);
    var hints: std.ArrayList(HintUse) = .empty;
    for (g.rules.items, 0..) |rule, r| {
        hintStart[r] = @intCast(hints.items.len);
        for (rule.excludeChars, rule.hintTerminals) |c, t| try hints.append(a, .{ .rule = @intCast(r), .char = c, .terminal = t });
    }
    hintStart[g.rules.items.len] = @intCast(hints.items.len);

    // The operator terminals of a folded `@infix` table: their level and
    // associativity, from the operator rules.
    const opPrec = try a.alloc(?grammar.Rule.Precedence, numSymbols);
    defer a.free(opPrec);
    @memset(opPrec, null);
    for (g.rules.items) |rule| {
        if (rule.infix) |p| opPrec[rule.rhs[1]] = p;
    }

    var reduceUnion = try SetArray.init(a, 1, numSymbols);
    defer reduceUnion.deinit(a);
    const cellTerminals = reduceUnion.get(0);
    var cellRules: std.ArrayList(u16) = .empty;
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
                    // A folded `@infix` operator rule against an operator
                    // of its table: a tighter operator shifts, a looser one
                    // reduces, and one of the same level goes by its
                    // associativity (`none`: an error, so chains reject).
                    if (cellRules.items.len == 1) if (g.rules.items[cellRules.items[0]].infix) |rp| if (opPrec[t]) |tp| {
                        if (tp.level < rp.level or (tp.level == rp.level and rp.assoc == .left)) {
                            cell.* = .{ .reduce = cellRules.items[0] };
                        } else if (tp.level == rp.level and rp.assoc == .none) {
                            cell.* = .err;
                        }
                        continue;
                    };
                    // The lowest rule that beats the shift: by `<`, or by an
                    // X "c" hint naming this terminal (that hint is used).
                    const winner: ?u16 = for (cellRules.items) |r| {
                        const hint = for (hints.items[hintStart[r]..hintStart[r + 1]]) |*h| {
                            if (h.terminal == t) break h;
                        } else null;
                        if (hint) |h| {
                            h.used = true;
                            try xExcludes.append(a, .{ .state = @intCast(si), .sym = @intCast(t), .shift = target });
                            break r;
                        }
                        if (g.rules.items[r].preferReduce) break r;
                    } else null;
                    if (winner) |w| {
                        cell.* = .{ .reduce = w };
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
        .conflictList = try conflictList.toOwnedSlice(a),
        .hints = try hints.toOwnedSlice(a),
        .expected = exp,
        .repair = rep,
    };
}
