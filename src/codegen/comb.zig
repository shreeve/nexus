//! The parse table as generated parsers hold it: compressed by row
//! displacement (a comb) with a check per cell, and gotos also as a default
//! per nonterminal with exceptions.
//!
//! A state's actions (its cells in terminal columns) and its gotos (its
//! cells in nonterminal columns) are two rows. Identical rows are stored
//! once. Every distinct row is placed in one array of cells at a base of
//! its own, so that its nonempty cells land on free slots: the cell of
//! symbol `sym` in the row at `base` is `cells[base + sym]`. A cell is
//! `check << 16 | value`, where `check` is the row's base mod 65536 and
//! `value` the table's i16 action (0 = error). A lookup that lands on a
//! slot another row filled, or on an empty one, finds a different check (or
//! the value 0) and reads error. Bases are distinct, so a check of `base
//! mod 65536` tells rows apart: two rows whose bases agree mod 65536 are at
//! least 65536 slots apart, farther than any symbol id reaches.
//!
//! No default reductions: every cell keeps its own action, so the errors,
//! expected sets and tolerant repairs a parser derives from the table are
//! those of the dense table.
//!
//! The parse loop reads a goto, which always exists there, as the
//! nonterminal's most common target unless the state is an exception:
//! `exceptions[exceptionBase[lhs] + state]` holds `state << 16 | target`
//! for each state whose goto differs. Every other lookup reads the exact
//! goto row.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Comb = struct {
    /// Per state: the base of its action row, and of its goto row.
    actionBase: []const u32,
    gotoBase: []const u32,
    /// Every row's cells; it reaches `numSymbols` slots past the last base.
    cells: []const u32,
    /// Per symbol (0 for a terminal): a nonterminal's most common goto.
    gotoDefault: []const u16,
    /// Per symbol: the base of a nonterminal's column of exceptions.
    exceptionBase: []const u32,
    /// The exceptions, `state << 16 | target`; it reaches `numStates`
    /// slots past the last base.
    exceptions: []const u32,

    /// The action (or goto) for `sym` in `state`, as the dense table holds
    /// it.
    pub fn at(self: Comb, state: usize, sym: usize) i16 {
        const action = cellAt(self.cells, self.actionBase[state], sym);
        return if (action != 0) action else cellAt(self.cells, self.gotoBase[state], sym);
    }

    /// The goto on nonterminal `lhs` from `state`, which has one.
    pub fn gotoOn(self: Comb, state: usize, lhs: usize) u16 {
        const cell = self.exceptions[self.exceptionBase[lhs] + state];
        return if (cell >> 16 == state) @truncate(cell) else self.gotoDefault[lhs];
    }

    fn cellAt(cells: []const u32, base: u32, sym: usize) i16 {
        const cell = cells[base + sym];
        return if (cell >> 16 == @as(u16, @truncate(base))) @bitCast(@as(u16, @truncate(cell))) else 0;
    }

    /// Whether every cell decodes to `dense`'s, and the parse loop's goto
    /// path gives every goto of `dense`.
    pub fn matches(self: Comb, dense: []const []const i16, nonterminal: []const bool) bool {
        for (dense, 0..) |row, state| {
            for (row, 0..) |want, sym| {
                if (self.at(state, sym) != want) return false;
                if (nonterminal[sym] and want != 0 and self.gotoOn(state, sym) != @as(u16, @intCast(want))) return false;
            }
        }
        return true;
    }
};

/// A nonempty cell of a row: its column and value.
const Entry = extern struct { col: u16, value: i16 };

/// The slots of a comb being filled, for first-fit placement.
const Slots = struct {
    /// `slot[i]` leads to the first free slot at or after `i`, and
    /// `base[i]` to the first base no row has taken at or after `i` (an
    /// index in use points past itself; a lookup points every index of
    /// the path it follows at its end).
    slot: []u32,
    base: []u32,
    /// The length and base of the row placed last.
    lastLen: usize = 0,
    lastBase: usize = 0,

    /// A row of at least this many cells, after a row of its length,
    /// searches from that row's base on: the slots before it are as full
    /// for it, and a first fit from the start costs a scan of the whole
    /// comb per row.
    const resumeLen = 4;

    fn init(a: Allocator, len: usize) !Slots {
        const slot = try a.alloc(u32, len + 1);
        for (slot, 0..) |*n, i| n.* = @intCast(i);
        return .{ .slot = slot, .base = try a.dupe(u32, slot) };
    }

    fn firstFrom(next: []u32, i: usize) usize {
        var root = i;
        while (next[root] != root) root = next[root];
        var j = i;
        while (next[j] != root and j != root) {
            const after = next[j];
            next[j] = @intCast(root);
            j = after;
        }
        return root;
    }

    /// The first base no row has taken where every column of `cols`
    /// (ascending) meets a free slot (from the last row's base on, after a
    /// row of the same length of `resumeLen` or more); the base and the
    /// row's slots are then in use.
    fn place(self: *Slots, cols: []const u16) usize {
        const first: usize = if (cols.len > 0) cols[0] else 0;
        const start = firstFrom(self.slot, 0);
        var from: usize = if (start > first) start - first else 0;
        if (cols.len >= resumeLen and cols.len == self.lastLen) from = @max(from, self.lastBase);
        var d = firstFrom(self.base, from);
        // A column that meets a slot in use moves the base on to the next
        // free slot for that column: no base in between can take the row.
        search: while (true) {
            for (cols) |c| {
                const free = firstFrom(self.slot, d + c);
                if (free != d + c) {
                    d = firstFrom(self.base, free - c);
                    continue :search;
                }
            }
            break;
        }
        self.base[d] = @intCast(d + 1);
        for (cols) |c| self.slot[d + c] = @intCast(d + c + 1);
        self.lastLen = cols.len;
        self.lastBase = d;
        return d;
    }
};

/// Encode `dense` (`[state][symbol]`, the generated i16 actions; symbols
/// with `nonterminal` set are goto columns). Deterministic: the same table
/// gives the same comb.
pub fn encode(a: Allocator, dense: []const []const i16, nonterminal: []const bool) !Comb {
    const numStates = dense.len;
    const numSymbols = nonterminal.len;

    // The distinct rows, in order of first appearance: actions of state 0,
    // gotos of state 0, actions of state 1, ...
    var rows: std.ArrayList([]const Entry) = .empty;
    var rowOf: std.StringHashMapUnmanaged(u32) = .empty;
    const rowIndex = try a.alloc(u32, 2 * numStates);
    for (dense, 0..) |cells, state| {
        for ([_]bool{ false, true }, 0..) |goto, k| {
            var entries: std.ArrayList(Entry) = .empty;
            for (cells, 0..) |value, sym| {
                if (value != 0 and nonterminal[sym] == goto) try entries.append(a, .{ .col = @intCast(sym), .value = value });
            }
            const found = try rowOf.getOrPut(a, std.mem.sliceAsBytes(entries.items));
            if (!found.found_existing) {
                found.value_ptr.* = @intCast(rows.items.len);
                try rows.append(a, entries.items);
            }
            rowIndex[2 * state + k] = found.value_ptr.*;
        }
    }

    // Densest rows first (then first appearance), each at the first base
    // that no row has taken where its cells meet free slots.
    const order = try a.alloc(u32, rows.items.len);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, order, rows.items, struct {
        fn less(r: [][]const Entry, x: u32, y: u32) bool {
            if (r[x].len != r[y].len) return r[x].len > r[y].len;
            return x < y;
        }
    }.less);
    var slots: Slots = try .init(a, rows.items.len * numSymbols + numSymbols);
    const base = try a.alloc(u32, rows.items.len);
    var top: usize = 0;
    var cols: std.ArrayList(u16) = .empty;
    for (order) |r| {
        cols.clearRetainingCapacity();
        for (rows.items[r]) |e| try cols.append(a, e.col);
        const d = slots.place(cols.items);
        base[r] = @intCast(d);
        top = @max(top, d + numSymbols);
    }
    const cells = try a.alloc(u32, top);
    @memset(cells, 0);
    for (rows.items, base) |entries, d| {
        for (entries) |e| cells[d + e.col] = @as(u32, @as(u16, @truncate(d))) << 16 | @as(u16, @bitCast(e.value));
    }
    const actionBase = try a.alloc(u32, numStates);
    const gotoBase = try a.alloc(u32, numStates);
    for (actionBase, gotoBase, 0..) |*ab, *gb, state| {
        ab.* = base[rowIndex[2 * state]];
        gb.* = base[rowIndex[2 * state + 1]];
    }

    // Gotos: a default per nonterminal, and its column of exceptions.
    const gotoDefault = try a.alloc(u16, numSymbols);
    @memset(gotoDefault, 0);
    var columns: std.ArrayList([]const u16) = .empty; // per nonterminal: the exception states
    var columnSym: std.ArrayList(u16) = .empty;
    var counts: std.AutoArrayHashMapUnmanaged(i16, u32) = .empty;
    for (nonterminal, 0..) |isNt, sym| {
        if (!isNt) continue;
        counts.clearRetainingCapacity();
        for (dense) |row| {
            if (row[sym] != 0) (try counts.getOrPutValue(a, row[sym], 0)).value_ptr.* += 1;
        }
        var best: i16 = 0;
        var bestCount: u32 = 0;
        // Ties go to the lower target.
        for (counts.keys(), counts.values()) |target, n| {
            if (n > bestCount or (n == bestCount and target < best)) {
                best = target;
                bestCount = n;
            }
        }
        gotoDefault[sym] = @intCast(best);
        var states: std.ArrayList(u16) = .empty;
        for (dense, 0..) |row, state| {
            if (row[sym] != 0 and row[sym] != best) try states.append(a, @intCast(state));
        }
        try columns.append(a, states.items);
        try columnSym.append(a, @intCast(sym));
    }
    const corder = try a.alloc(u32, columns.items.len);
    for (corder, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, corder, columns.items, struct {
        fn less(c: [][]const u16, x: u32, y: u32) bool {
            if (c[x].len != c[y].len) return c[x].len > c[y].len;
            return x < y;
        }
    }.less);
    var xslots: Slots = try .init(a, columns.items.len * numStates + numStates);
    const exceptionBase = try a.alloc(u32, numSymbols);
    @memset(exceptionBase, 0);
    var xtop: usize = numStates;
    for (corder) |c| {
        const d = xslots.place(columns.items[c]);
        exceptionBase[columnSym.items[c]] = @intCast(d);
        xtop = @max(xtop, d + numStates);
    }
    const exceptions = try a.alloc(u32, xtop);
    // An empty slot's check is no state's: the column lookup reads the
    // default there.
    @memset(exceptions, std.math.maxInt(u32));
    for (columns.items, columnSym.items) |states, sym| {
        for (states) |s| {
            const target: u16 = @intCast(dense[s][sym]);
            exceptions[exceptionBase[sym] + s] = @as(u32, s) << 16 | target;
        }
    }
    return .{
        .actionBase = actionBase,
        .gotoBase = gotoBase,
        .cells = cells,
        .gotoDefault = gotoDefault,
        .exceptionBase = exceptionBase,
        .exceptions = exceptions,
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

/// A table of `states` rows over `symbols` columns (every `ntEvery`-th a
/// nonterminal), each row drawn from `distinct` patterns so that rows
/// repeat; cells are nonzero with probability `fill`/16.
fn randomTable(a: Allocator, seed: u64, states: usize, symbols: usize, ntEvery: usize, distinct: usize, fill: u4) !struct { dense: [][]i16, nonterminal: []bool } {
    var prng: std.Random.DefaultPrng = .init(seed);
    const rand = prng.random();
    const nonterminal = try a.alloc(bool, symbols);
    for (nonterminal, 0..) |*n, i| n.* = i % ntEvery == ntEvery - 1;
    const patterns = try a.alloc([]i16, distinct);
    for (patterns) |*p| {
        p.* = try a.alloc(i16, symbols);
        for (p.*, nonterminal) |*cell, isNt| {
            cell.* = if (rand.uintLessThan(u8, 16) >= fill) 0 else if (isNt)
                @intCast(rand.intRangeAtMost(u16, 1, @intCast(states - 1)))
            else switch (rand.uintLessThan(u8, 8)) {
                0 => -1, // accept
                1 => std.math.minInt(i16), // a hinted cell
                2, 3, 4 => @intCast(rand.intRangeAtMost(u16, 1, @intCast(states - 1))), // shift
                else => -2 - @as(i16, @intCast(rand.uintLessThan(u16, 500))), // reduce
            };
        }
    }
    const dense = try a.alloc([]i16, states);
    for (dense) |*row| row.* = patterns[rand.uintLessThan(usize, distinct)];
    return .{ .dense = dense, .nonterminal = nonterminal };
}

fn expectRoundTrip(dense: []const []const i16, nonterminal: []const bool) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const comb = try encode(arena.allocator(), dense, nonterminal);
    try testing.expect(comb.matches(dense, nonterminal));
    const last = @max(std.mem.max(u32, comb.actionBase), std.mem.max(u32, comb.gotoBase));
    try testing.expectEqual(last + nonterminal.len, comb.cells.len);
}

test "a comb decodes to the dense table, cell for cell" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Sparse and dense rows, repeated rows, hinted and accept cells.
    for ([_]u64{ 1, 2, 3 }) |seed| {
        const t = try randomTable(a, seed, 300, 120, 3, 90, 3);
        try expectRoundTrip(t.dense, t.nonterminal);
    }
    const full = try randomTable(a, 4, 200, 60, 4, 200, 15);
    try expectRoundTrip(full.dense, full.nonterminal);
}

test "rows whose bases agree mod 65536 stay apart" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Dense distinct rows: over 65536 cells, so the checks wrap.
    const t = try randomTable(a, 5, 3000, 40, 5, 3000, 14);
    const comb = try encode(a, t.dense, t.nonterminal);
    try testing.expect(comb.cells.len > 65536);
    try testing.expect(comb.matches(t.dense, t.nonterminal));
}

test "empty rows, an all-error table and equal rows share one base" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nonterminal = [_]bool{ false, false, true, false, true };
    const row0 = [_]i16{ 0, 3, 2, 0, 0 };
    const row1 = [_]i16{ 0, 0, 0, 0, 0 };
    const row2 = [_]i16{ -1, 3, 2, -5, 4 };
    const dense = [_][]const i16{ &row0, &row1, &row2, &row0, &row1 };
    const comb = try encode(a, &dense, &nonterminal);
    try testing.expect(comb.matches(&dense, &nonterminal));
    try testing.expectEqual(comb.actionBase[0], comb.actionBase[3]);
    try testing.expectEqual(comb.gotoBase[1], comb.gotoBase[4]);
    try testing.expect(comb.actionBase[1] != comb.actionBase[0]);
    const none = [_][]const i16{ &row1, &row1 };
    try expectRoundTrip(&none, &nonterminal);
}

test "the same table gives the same comb" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = try randomTable(a, 6, 400, 90, 3, 100, 5);
    const x = try encode(a, t.dense, t.nonterminal);
    const y = try encode(a, t.dense, t.nonterminal);
    try testing.expectEqualSlices(u32, x.cells, y.cells);
    try testing.expectEqualSlices(u32, x.actionBase, y.actionBase);
    try testing.expectEqualSlices(u32, x.exceptions, y.exceptions);
}
