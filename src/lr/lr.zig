//! The LR stage: LR(0) automaton, lookaheads, parse table, and the checks
//! on them (`@repair` names, `X "c"` hints, the conflict manifest). Every
//! failure prints a located diagnostic and returns `error.GenerationFailed`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
pub const automaton = @import("automaton.zig");
pub const lookahead = @import("lookahead.zig");
pub const table = @import("table.zig");
pub const conflicts = @import("conflicts.zig");
pub const expected = @import("expected.zig");
pub const repair = @import("repair.zig");

pub const ParseMode = lookahead.ParseMode;

pub const Options = struct {
    mode: ParseMode = .lalr,
    /// The grammar file, for located messages.
    path: []const u8,
};

pub const Result = struct {
    automaton: automaton.Automaton,
    lookaheads: lookahead.Lookaheads,
    table: table.Table,
};

pub const Error = error{ GenerationFailed, OutOfMemory };

pub fn run(g: *Grammar, opts: Options) Error!Result {
    const a = g.allocator;
    var auto = automaton.build(g) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.NoAcceptRule => {
            std.debug.print("{s}:1:1: error: the grammar has no start symbol\n", .{opts.path});
            return error.GenerationFailed;
        },
        error.TooManyStates => {
            const first = if (g.rules.items.len > 0) g.rules.items[0] else null;
            std.debug.print("{s}:{d}:{d}: error: the grammar needs more than {d} parser states, the parse table's limit\n", .{ opts.path, if (first) |r| @max(r.line, 1) else 1, if (first) |r| @max(r.col, 1) else 1, automaton.maxStates });
            return error.GenerationFailed;
        },
    };
    errdefer auto.deinit(a);

    // LALR lookaheads (and any parse) assume every rule can complete.
    const costs = try repair.insertCosts(a, g);
    var unproductive = false;
    for (g.symbols.items, 0..) |sym, i| {
        if (sym.kind != .nonterminal or sym.rules.items.len == 0 or costs[i] != repair.infinite) continue;
        unproductive = true;
        const line = g.rules.items[sym.rules.items[0]].line;
        if (line > 0) std.debug.print("{s}:{d}:1: ", .{ opts.path, line }) else std.debug.print("{s}: ", .{opts.path});
        var name: std.Io.Writer.Allocating = .init(a);
        defer name.deinit();
        conflicts.writeSymbol(&name.writer, g, @intCast(i)) catch return error.OutOfMemory;
        std.debug.print("error: rule {s} derives no finite input (each of its alternatives needs a rule that never completes)\n", .{name.written()});
    }
    a.free(costs);
    if (unproductive) return error.GenerationFailed;
    try checkCycles(a, g, opts.path);

    const la = try lookahead.compute(g, &auto, opts.mode);

    if (g.repair) |spec| {
        if (repair.validate(g, spec)) |bad| {
            const at = spec.locOf(bad.index) orelse grammar.RepairSpec.Loc{ .line = 1, .col = 1 };
            std.debug.print("{s}:{d}:{d}: error: @repair: {s} {s}\n", .{ opts.path, at.line, at.col, bad.name, bad.reason });
            return error.GenerationFailed;
        }
    }

    const tbl = table.build(g, &auto, la) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRepairToken => unreachable, // validated above
    };

    try checkEmptyLoops(a, g, &tbl, opts.path);

    const copts: conflicts.Options = .{ .path = opts.path };
    conflicts.checkHints(a, g, &tbl, copts) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GenerationFailed,
    };
    conflicts.check(a, g, &auto, &tbl, copts) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GenerationFailed,
    };

    return .{ .automaton = auto, .lookaheads = la, .table = tbl };
}

/// Reductions of empty rules on one lookahead only push states. If a chain
/// of them returns to a state it has passed, the parser pushes forever on
/// that lookahead (a `<` hint, or a conflict resolved toward the empty
/// rule, can build such a table).
fn checkEmptyLoops(a: Allocator, g: *const Grammar, tbl: *const table.Table, path: []const u8) Error!void {
    const seen = try a.alloc(u32, tbl.rows.len);
    defer a.free(seen);
    @memset(seen, 0);
    var stamp: u32 = 0;
    for (tbl.rows, 0..) |row, s0| {
        for (row, 0..) |cell, t| {
            if (g.symbols.items[t].kind != .terminal) continue;
            if (cell != .reduce or g.rules.items[cell.reduce].rhs.len != 0) continue;
            stamp += 1;
            var s = s0;
            while (true) {
                if (seen[s] == stamp) {
                    const rule = g.rules.items[cell.reduce];
                    var name: std.Io.Writer.Allocating = .init(a);
                    defer name.deinit();
                    conflicts.writeSymbol(&name.writer, g, rule.lhs) catch return error.OutOfMemory;
                    name.writer.writeAll(" on ") catch return error.OutOfMemory;
                    conflicts.writeSymbol(&name.writer, g, @intCast(t)) catch return error.OutOfMemory;
                    std.debug.print("{s}:{d}:{d}: error: reducing the empty rule {s} leads back to the same state, so the parser would push forever on that token (a `<` hint or a conflict resolved toward an empty rule)\n", .{ path, @max(rule.line, 1), @max(rule.col, 1), name.written() });
                    return error.GenerationFailed;
                }
                seen[s] = stamp;
                const act = tbl.rows[s][t];
                if (act != .reduce) break;
                const rule = g.rules.items[act.reduce];
                if (rule.rhs.len != 0) break;
                const next = tbl.rows[s][rule.lhs];
                if (next != .gotoState) break;
                s = next.gotoState;
            }
        }
    }
}

/// Reject a cyclic grammar: a rule that derives itself (a ⇒+ a, through
/// rules whose other elements can be empty). Such a grammar is infinitely
/// ambiguous, and when a declared conflict resolves the cycle's way the
/// parser reduces around it forever.
fn checkCycles(a: Allocator, g: *const Grammar, path: []const u8) Error!void {
    const nsym = g.symbols.items.len;
    const nullable = try a.alloc(bool, nsym);
    defer a.free(nullable);
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
    // unit[r] = the nonterminal rule r derives alone (the rest nullable).
    const state = try a.alloc(u8, nsym); // 0 new, 1 on the path, 2 done
    defer a.free(state);
    @memset(state, 0);
    var path_: std.ArrayListUnmanaged(u16) = .empty; // rules on the path
    defer path_.deinit(a);
    for (g.symbols.items, 0..) |sym, i| {
        if (sym.kind != .nonterminal or state[i] != 0) continue;
        if (try cycleFrom(a, g, nullable, state, &path_, @intCast(i))) |at| {
            const rules = path_.items[at..];
            const first = g.rules.items[rules[0]];
            var text: std.Io.Writer.Allocating = .init(a);
            defer text.deinit();
            for (rules, 0..) |r, k| {
                if (k > 0) text.writer.writeAll(" ⇒ ") catch return error.OutOfMemory;
                conflicts.writeSymbol(&text.writer, g, g.rules.items[r].lhs) catch return error.OutOfMemory;
            }
            text.writer.writeAll(" ⇒ ") catch return error.OutOfMemory;
            conflicts.writeSymbol(&text.writer, g, first.lhs) catch return error.OutOfMemory;
            if (first.line > 0) std.debug.print("{s}:{d}:{d}: ", .{ path, first.line, @max(first.col, 1) }) else std.debug.print("{s}:1:1: ", .{path});
            std.debug.print("error: the grammar is cyclic ({s}): a rule that derives itself gives some input infinitely many parses\n", .{text.written()});
            return error.GenerationFailed;
        }
    }
}

/// Depth-first search along unit derivations from `sym`; returns the index
/// in `path` where a cycle starts.
fn cycleFrom(a: Allocator, g: *const Grammar, nullable: []const bool, state: []u8, path: *std.ArrayListUnmanaged(u16), sym: u16) Error!?usize {
    state[sym] = 1;
    for (g.symbols.items[sym].rules.items) |ri| {
        const rule = g.rules.items[ri];
        for (rule.rhs, 0..) |b, k| {
            if (g.symbols.items[b].kind != .nonterminal) continue;
            const rest = for (rule.rhs, 0..) |s, j| {
                if (j != k and !nullable[s]) break false;
            } else true;
            if (!rest) continue;
            try path.append(a, ri);
            if (state[b] == 1) {
                // The cycle starts at the first path rule whose lhs is b.
                for (path.items, 0..) |r, at| if (g.rules.items[r].lhs == b) return at;
            }
            if (state[b] == 0) if (try cycleFrom(a, g, nullable, state, path, b)) |at| return at;
            _ = path.pop();
        }
    }
    state[sym] = 2;
    return null;
}

test {
    _ = @import("bitset.zig");
    _ = @import("tests.zig");
}
