//! The LR stage: LR(0) automaton, lookaheads, parse table, and the checks
//! on them (`@repair` names, `X "c"` hints, the conflict manifest). Every
//! failure prints a located diagnostic and returns `error.GenerationFailed`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const diag = @import("../diag.zig");
pub const automaton = @import("automaton.zig");
pub const lookahead = @import("lookahead.zig");
pub const table = @import("table.zig");
pub const conflicts = @import("conflicts.zig");
pub const expected = @import("expected.zig");
pub const repair = @import("repair.zig");

pub const Options = struct {
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
        error.TooManyStates => {
            const at = conflicts.ruleLoc(g, 0);
            diag.errLine(opts.path, at.line, at.col, "the grammar needs more than {d} parser states, the parse table's limit", .{automaton.maxStates});
            return error.GenerationFailed;
        },
    };

    // LALR lookaheads (and any parse) assume every rule can complete.
    const costs = try repair.insertCosts(a, g);
    const roots = try unproductiveRoots(a, g, costs);
    a.free(costs);
    if (roots.len > 0) {
        for (roots) |s| {
            const at = conflicts.ruleLoc(g, g.symbols.items[s].rules.items[0]);
            diag.errLine(opts.path, at.line, at.col, "rule {s} derives no finite input (each of its alternatives needs a rule that never completes)", .{g.symbols.items[s].name});
        }
        return error.GenerationFailed;
    }
    try checkCycles(a, g, opts.path);

    const la = try lookahead.compute(g, &auto);

    if (g.repair) |spec| {
        if (repair.validate(g, spec)) |bad| {
            const at = spec.locOf(bad.index) orelse grammar.RepairSpec.Loc{ .line = 1, .col = 1 };
            diag.errLine(opts.path, at.line, at.col, "@repair: {s} {s}", .{ bad.name, bad.reason });
            return error.GenerationFailed;
        }
    }

    const tbl = table.build(g, &auto, la) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRepairToken => unreachable, // validated above
    };

    if (try emptyLoop(a, g, &tbl)) |loop| {
        const at = conflicts.ruleLoc(g, loop.rule);
        diag.errLine(opts.path, at.line, at.col, "reducing the empty rule {s} on {s} leads back to the same state, so the parser would push forever on that token (a `<` hint or a conflict resolved toward an empty rule)", .{ g.symbols.items[g.rules.items[loop.rule].lhs].name, g.symbols.items[loop.terminal].name });
        return error.GenerationFailed;
    }

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

/// The unproductive nonterminals to report (those that derive no finite
/// input: `costs` infinite), ascending: the members of each bottom strongly
/// connected component of "a rule of A uses B" among unproductive
/// nonterminals. Every other unproductive nonterminal (helpers such as
/// `b+`, the rules using them, the accept rules) fails only through one of
/// these, so reporting it too would only repeat the cause.
pub fn unproductiveRoots(a: Allocator, g: *const Grammar, costs: []const u32) Allocator.Error![]const u16 {
    const n = g.symbols.items.len;
    const none = std.math.maxInt(u32);
    const index = try a.alloc(u32, n);
    defer a.free(index);
    @memset(index, none);
    const low = try a.alloc(u32, n);
    defer a.free(low);
    const flags = try a.alloc(packed struct { onStack: bool, exits: bool }, n);
    defer a.free(flags);
    @memset(flags, .{ .onStack = false, .exits = false });
    var stack: std.ArrayList(u16) = .empty;
    defer stack.deinit(a);
    // Tarjan's algorithm, iterative: a frame walks its symbol's rules.
    const Frame = struct { sym: u16, rule: u32 = 0, pos: u32 = 0 };
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(a);
    var roots: std.ArrayList(u16) = .empty;
    var next: u32 = 0;

    for (0..n) |s0| {
        if (costs[s0] != repair.infinite or g.symbols.items[s0].rules.items.len == 0 or index[s0] != none) continue;
        var push: ?u16 = @intCast(s0);
        while (true) {
            if (push) |v| {
                index[v] = next;
                low[v] = next;
                next += 1;
                flags[v].onStack = true;
                try stack.append(a, v);
                try frames.append(a, .{ .sym = v });
                push = null;
            }
            const f = frames.lastPtr() orelse break;
            const rules = g.symbols.items[f.sym].rules.items;
            if (f.rule < rules.len) {
                const rhs = g.rules.items[rules[f.rule]].rhs;
                if (f.pos == rhs.len) {
                    f.rule += 1;
                    f.pos = 0;
                    continue;
                }
                const w = rhs[f.pos];
                f.pos += 1;
                if (costs[w] != repair.infinite or g.symbols.items[w].rules.items.len == 0) continue;
                if (index[w] == none) {
                    push = w;
                } else if (flags[w].onStack) {
                    low[f.sym] = @min(low[f.sym], index[w]);
                } else flags[f.sym].exits = true;
                continue;
            }
            const v = frames.pop().?.sym;
            if (low[v] == index[v]) {
                const from = std.mem.findScalarLast(u16, stack.items, v).?;
                const members = stack.items[from..];
                const bottom = for (members) |m| {
                    if (flags[m].exits) break false;
                } else true;
                if (bottom) try roots.appendSlice(a, members);
                for (members) |m| flags[m].onStack = false;
                stack.shrinkRetainingCapacity(from);
            }
            if (frames.last()) |parent| {
                if (flags[v].onStack) {
                    low[parent.sym] = @min(low[parent.sym], low[v]);
                } else flags[parent.sym].exits = true;
            }
        }
    }
    std.mem.sort(u16, roots.items, {}, std.sort.asc(u16));
    return roots.toOwnedSlice(a);
}

/// A reduce chain that never ends; reducing the empty rule `rule` on
/// `terminal` starts it.
pub const EmptyLoop = struct { rule: u16, terminal: u16 };

/// Find a table cell from which the parser reduces forever on one
/// lookahead. A run of reductions on terminal t loops exactly when it
/// pushes a state that is still on the stack: from that state's first
/// visit the run reached it again without looking below it, so it repeats.
/// An endless run has a lowest stack entry it never pops. That entry was
/// pushed during the run (a run that keeps popping back to one older entry
/// derives a nonterminal from itself, a cyclic grammar `checkCycles`
/// rejects first), and its first action was an empty reduction (any other
/// pops it). So simulating the chain on an explicit stack from every
/// (state, t) whose action is an empty reduction, until a shift, accept,
/// error, or a pop below the start, finds every loop, and every simulation
/// ends. (A `<` hint, or a conflict resolved toward an empty rule, can
/// build such a table.)
pub fn emptyLoop(a: Allocator, g: *const Grammar, tbl: *const table.Table) Allocator.Error!?EmptyLoop {
    const onStack = try a.alloc(bool, tbl.rows.len);
    defer a.free(onStack);
    @memset(onStack, false);
    var stack: std.ArrayList(u16) = .empty;
    defer stack.deinit(a);
    for (tbl.rows, 0..) |row, q| {
        for (row, 0..) |cell, t| {
            if (g.symbols.items[t].kind != .terminal) continue;
            if (cell != .reduce or g.rules.items[cell.reduce].rhs.len != 0) continue;
            for (stack.items) |s| onStack[s] = false;
            stack.clearRetainingCapacity();
            try stack.append(a, @intCast(q));
            onStack[q] = true;
            while (true) {
                const act = tbl.rows[stack.last().?][t];
                if (act != .reduce) break;
                const rule = &g.rules.items[act.reduce];
                if (rule.rhs.len >= stack.items.len) break;
                for (stack.items[stack.items.len - rule.rhs.len ..]) |s| onStack[s] = false;
                stack.shrinkRetainingCapacity(stack.items.len - rule.rhs.len);
                const next = tbl.rows[stack.last().?][rule.lhs];
                if (next != .gotoState) break;
                if (onStack[next.gotoState]) return .{ .rule = cell.reduce, .terminal = @intCast(t) };
                try stack.append(a, next.gotoState);
                onStack[next.gotoState] = true;
            }
        }
    }
    return null;
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
    var path_: std.ArrayList(u16) = .empty; // rules on the path
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
            const loc = conflicts.ruleLoc(g, rules[0]);
            diag.errLine(path, loc.line, loc.col, "the grammar is cyclic ({s}): a rule that derives itself gives some input infinitely many parses", .{text.written()});
            return error.GenerationFailed;
        }
    }
}

/// Depth-first search along unit derivations from `sym`; returns the index
/// in `path` where a cycle starts.
fn cycleFrom(a: Allocator, g: *const Grammar, nullable: []const bool, state: []u8, path: *std.ArrayList(u16), sym: u16) Error!?usize {
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
