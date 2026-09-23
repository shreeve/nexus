//! Row-compressed ACTION/GOTO (row displacement, the "comb vector" of yacc
//! and bison, without default reductions): every state's non-error entries
//! are stored in one shared array at an offset chosen so that no two states
//! collide. A lookup is two loads and a compare:
//!
//!     i = base[state] + symbol
//!     action = if (check[i] == state) value[i] else 0   // 0 = error
//!
//! `value` uses the generated parser's action encoding: 0 error, > 0 shift
//! or goto target state, -1 accept, <= -2 reduce by rule (-v - 2). Error
//! entries are exact (no default reductions), so any test of "is there an
//! action here" (expected sets, `@as` promotion) sees the same table as the
//! dense form.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseAction = @import("table.zig").ParseAction;

pub const Compact = struct {
    /// Offset of each state's row in `check`/`value`.
    base: []const u32,
    /// Owning state of each slot; `empty` when unused.
    check: []const u16,
    value: []const i16,

    pub const empty = std.math.maxInt(u16);

    pub fn get(self: Compact, state: u16, symbol: u16) i16 {
        const i = self.base[state] + symbol;
        return if (self.check[i] == state) self.value[i] else 0;
    }
};

/// The generated-parser encoding of one action.
pub fn encode(action: ParseAction) i16 {
    return switch (action) {
        .shift => |s| @intCast(s),
        .gotoState => |s| @intCast(s),
        .reduce => |r| -@as(i16, @intCast(r)) - 2,
        .accept => -1,
        .err => 0,
    };
}

pub fn compress(a: Allocator, rows: []const []const ParseAction) !Compact {
    const numStates = rows.len;
    const numSymbols = if (numStates > 0) rows[0].len else 0;
    std.debug.assert(numStates < Compact.empty);

    // Place the densest rows first: they are the hardest to fit.
    const order = try a.alloc(u16, numStates);
    defer a.free(order);
    const density = try a.alloc(u32, numStates);
    defer a.free(density);
    for (rows, 0..) |row, s| {
        order[s] = @intCast(s);
        var n: u32 = 0;
        for (row) |cell| {
            if (cell != .err) n += 1;
        }
        density[s] = n;
    }
    std.mem.sort(u16, order, density, struct {
        fn lessThan(d: []const u32, x: u16, y: u16) bool {
            if (d[x] != d[y]) return d[x] > d[y];
            return x < y;
        }
    }.lessThan);

    var check: std.ArrayListUnmanaged(u16) = .empty;
    var value: std.ArrayListUnmanaged(i16) = .empty;
    const base = try a.alloc(u32, numStates);
    var cols: std.ArrayListUnmanaged(u16) = .empty;
    defer cols.deinit(a);
    // Lowest slot that may still be free (slots below it are all used).
    var firstFree: usize = 0;

    for (order) |s| {
        cols.clearRetainingCapacity();
        for (rows[s], 0..) |cell, sym| {
            if (cell != .err) try cols.append(a, @intCast(sym));
        }
        while (firstFree < check.items.len and check.items[firstFree] != Compact.empty) firstFree += 1;

        // First offset where every entry lands on a free slot.
        const lead: usize = if (cols.items.len > 0) cols.items[0] else 0;
        var offset: usize = if (firstFree >= lead) firstFree - lead else 0;
        search: while (true) : (offset += 1) {
            for (cols.items) |c| {
                const i = offset + c;
                if (i < check.items.len and check.items[i] != Compact.empty) continue :search;
            }
            break;
        }

        // Every lookup base[s] + sym (sym < numSymbols) must stay in bounds.
        const need = offset + numSymbols;
        if (need > check.items.len) {
            const old = check.items.len;
            try check.resize(a, need);
            try value.resize(a, need);
            @memset(check.items[old..], Compact.empty);
            @memset(value.items[old..], 0);
        }
        for (cols.items) |c| {
            check.items[offset + c] = s;
            value.items[offset + c] = encode(rows[s][c]);
        }
        base[s] = @intCast(offset);
    }

    return .{
        .base = base,
        .check = try check.toOwnedSlice(a),
        .value = try value.toOwnedSlice(a),
    };
}

test "compressed lookups equal the dense table" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();

    var prng = std.Random.DefaultPrng.init(7);
    const rand = prng.random();
    const numStates = 60;
    const numSymbols = 40;
    const rows = try aa.alloc([]ParseAction, numStates);
    for (rows) |*row| {
        row.* = try aa.alloc(ParseAction, numSymbols);
        for (row.*) |*cell| {
            cell.* = switch (rand.uintLessThan(u8, 10)) {
                0 => .{ .shift = rand.uintLessThan(u16, numStates) },
                1 => .{ .reduce = rand.uintLessThan(u16, 30) },
                2 => .accept,
                else => .err,
            };
        }
    }
    const c = try compress(aa, rows);
    for (rows, 0..) |row, s| {
        for (row, 0..) |cell, sym| {
            try std.testing.expectEqual(encode(cell), c.get(@intCast(s), @intCast(sym)));
        }
    }
}
