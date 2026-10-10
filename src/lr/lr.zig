//! The LR stage. First the checks on the grammar alone (every rule derives
//! some finite input, no rule derives itself, `@repair` names), from insert
//! costs computed once; then the LR(0) automaton, lookaheads and parse
//! table, and the checks on them (endless reduce chains, `X "c"` hints, the
//! conflict manifest). Every failure prints a located diagnostic and
//! returns `error.GenerationFailed`.

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
    table: table.Table,
};

pub const Error = error{ GenerationFailed, OutOfMemory };

pub fn run(g: *Grammar, opts: Options) Error!Result {
    const a = g.allocator;

    // Checks on the grammar alone. LALR lookaheads (and any parse) assume
    // every rule can complete.
    const costs = try repair.insertCosts(a, g);
    const roots = try unproductiveRoots(a, g, costs);
    if (roots.len > 0) {
        for (roots) |s| {
            const at = conflicts.ruleLoc(g, g.symbols.items[s].rules.items[0]);
            diag.errLine(opts.path, at.line, at.col, "rule {s} derives no finite input (each of its alternatives needs a rule that never completes)", .{g.symbols.items[s].name});
        }
        return error.GenerationFailed;
    }
    try checkCycles(a, g, costs, opts.path);
    if (g.repair) |spec| {
        if (repair.validate(g, spec)) |bad| {
            const at = spec.locOf(bad.index) orelse grammar.RepairSpec.Loc{ .line = 1, .col = 1 };
            diag.errLine(opts.path, at.line, at.col, "@repair: {s} {s}", .{ bad.name, bad.reason });
            return error.GenerationFailed;
        }
    }

    const auto = automaton.build(g) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TooManyStates => {
            const at = conflicts.ruleLoc(g, 0);
            diag.errLine(opts.path, at.line, at.col, "the grammar needs more than {d} parser states, the parse table's limit", .{automaton.maxStates});
            return error.GenerationFailed;
        },
    };
    const la = try lookahead.compute(g, &auto, costs);
    const tbl = try table.build(g, &auto, la);

    // Checks on the table.
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

    return .{ .automaton = auto, .table = tbl };
}

/// Whether the `@infix` table `decl` of the checked chain grammar `g`
/// (table `tbl`) parses the same when folded (`expand.Options.foldInfix`):
/// each level has one associativity, no operator repeats, and no conflict
/// involves a rule of the chain. An operator that can also follow a whole
/// `infix` from outside the table is such a conflict (the chain both
/// reduces an operand to the operator's level and shifts the operator),
/// so every operator after an operand belongs to the table's own
/// structure, which precedence decides as the chain does. (A level mixing
/// `none` with `left` is conflict-free as a chain, `a n b l c` parsing and
/// `a l b n c` not, which no precedence order reproduces.)
pub fn foldable(g: *const Grammar, tbl: *const table.Table, decl: grammar.InfixDecl) bool {
    for (decl.ops, 0..) |op, i| for (decl.ops[0..i]) |o| {
        if (o.prec == op.prec and o.assoc != op.assoc) return false;
        if (std.mem.eql(u8, o.op, op.op)) return false;
    };
    const infixId = g.getSymbol("infix") orelse return false;
    for (tbl.conflictList) |c| {
        if (isChainRule(g, infixId, c.rule) or (c.kind == .reduce and isChainRule(g, infixId, c.over))) return false;
    }
    return true;
}

/// A rule of the `@infix` chain: its lhs is `infix` or a level.
fn isChainRule(g: *const Grammar, infixId: u16, rule: u16) bool {
    const lhs = g.rules.items[rule].lhs;
    return lhs == infixId or std.mem.startsWith(u8, g.symbols.items[lhs].name, "infix(");
}

/// The automaton and table of `folded`, the folded form of the checked
/// grammar `chain` (table `chainTbl`, which `foldable` accepts), or null
/// when they differ in anything but the `@infix` table: its conflicts
/// (by rule text and cell count), its `X "c"` hints used, or a reduce
/// loop.
pub fn runFolded(folded: *Grammar, chain: *const Grammar, chainTbl: *const table.Table) Error!?Result {
    const a = folded.allocator;
    const costs = try repair.insertCosts(a, folded);
    const auto = automaton.build(folded) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TooManyStates => return null,
    };
    const la = try lookahead.compute(folded, &auto, costs);
    const tbl = try table.build(folded, &auto, la);
    if (try emptyLoop(a, folded, &tbl) != null) return null;
    if (tbl.hints.len != chainTbl.hints.len) return null;
    for (tbl.hints, chainTbl.hints) |x, y| if (x.used != y.used) return null;
    const mine = try conflicts.entries(a, &tbl);
    const theirs = try conflicts.entries(a, chainTbl);
    if (mine.len != theirs.len) return null;
    for (mine, theirs) |x, y| {
        if (x.kind != y.kind or x.count != y.count) return null;
        if (!try sameRule(a, folded, x.rule, chain, y.rule)) return null;
        if (x.kind == .reduce and !try sameRule(a, folded, x.over, chain, y.over)) return null;
    }
    return .{ .automaton = auto, .table = tbl };
}

fn sameRule(a: Allocator, g1: *const Grammar, r1: u16, g2: *const Grammar, r2: u16) Allocator.Error!bool {
    const x = conflicts.ruleText(a, g1, r1) catch return error.OutOfMemory;
    const y = conflicts.ruleText(a, g2, r2) catch return error.OutOfMemory;
    return std.mem.eql(u8, x, y);
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
/// error, or a pop below the start, finds every loop. Every simulation
/// ends: one that never repeats a state would repeat a whole stack, so
/// some α ⇒+ α would derive nothing, which a grammar without cycles whose
/// rules all derive finite input cannot do; both are checked before this.
/// (A `<` hint, or a conflict resolved toward an empty rule, can build
/// such a table.)
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
fn checkCycles(a: Allocator, g: *const Grammar, costs: []const u32, path: []const u8) Error!void {
    const rules = try findCycle(a, g, costs) orelse return;
    var text: std.Io.Writer.Allocating = .init(a);
    defer text.deinit();
    for (rules) |r| {
        text.writer.print("{s} ⇒ ", .{g.symbols.items[g.rules.items[r].lhs].name}) catch return error.OutOfMemory;
    }
    text.writer.writeAll(g.symbols.items[g.rules.items[rules[0]].lhs].name) catch return error.OutOfMemory;
    const at = conflicts.ruleLoc(g, rules[0]);
    diag.errLine(path, at.line, at.col, "the grammar is cyclic ({s}): a rule that derives itself gives some input infinitely many parses", .{text.written()});
    return error.GenerationFailed;
}

/// The rules of a cycle of unit derivations (each rule's lhs derives the
/// next rule's lhs alone, the rest of the rule being nullable, and the last
/// derives the first), found by an iterative depth-first search; null if
/// the grammar has none. `costs` from `repair.insertCosts` (0 = nullable).
pub fn findCycle(a: Allocator, g: *const Grammar, costs: []const u32) Allocator.Error!?[]const u16 {
    const state = try a.alloc(enum(u8) { new, onPath, done }, g.symbols.items.len);
    defer a.free(state);
    @memset(state, .new);
    // A frame walks its symbol's rules and their positions; the `rule` of
    // every frame below the top is the rule the path takes.
    const Frame = struct { sym: u16, rule: u32 = 0, pos: u32 = 0 };
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(a);
    for (g.symbols.items, 0..) |sym, s0| {
        if (sym.kind != .nonterminal or state[s0] != .new) continue;
        state[s0] = .onPath;
        try frames.append(a, .{ .sym = @intCast(s0) });
        while (frames.lastPtr()) |f| {
            const rules = g.symbols.items[f.sym].rules.items;
            if (f.rule == rules.len) {
                state[f.sym] = .done;
                _ = frames.pop();
                continue;
            }
            const rhs = g.rules.items[rules[f.rule]].rhs;
            if (f.pos == rhs.len) {
                f.rule += 1;
                f.pos = 0;
                continue;
            }
            const k = f.pos;
            f.pos += 1;
            const b = rhs[k];
            if (g.symbols.items[b].kind != .nonterminal or state[b] == .done) continue;
            const alone = for (rhs, 0..) |x, j| {
                if (j != k and costs[x] != 0) break false;
            } else true;
            if (!alone) continue;
            if (state[b] == .onPath) {
                const from = for (frames.items, 0..) |fr, i| {
                    if (fr.sym == b) break i;
                } else unreachable;
                const cycle = try a.alloc(u16, frames.items.len - from);
                for (cycle, frames.items[from..]) |*r, fr| r.* = g.symbols.items[fr.sym].rules.items[fr.rule];
                return cycle;
            }
            state[b] = .onPath;
            try frames.append(a, .{ .sym = b });
        }
    }
    return null;
}

test {
    _ = @import("bitset.zig");
    _ = @import("tests.zig");
}
