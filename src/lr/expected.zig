//! Expected-symbol sets per state, for syntax-error messages ("expected an
//! expression or ")", got newline").
//!
//! A state's expectation list names, in order:
//!   1. the nonterminals with an `@errors` name that the state is directly
//!      waiting for (reached from the symbols after the dot of the kernel
//!      items, through nullable prefixes and unnamed nonterminals only, in
//!      discovery order), then
//!   2. every terminal with an action in the state that none of those named
//!      nonterminals can begin with, ascending by symbol id.
//! Start markers and the `error` symbol never appear. Identical lists are
//! stored once.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const Automaton = @import("automaton.zig").Automaton;
const Lookaheads = @import("lookahead.zig").Lookaheads;
const table = @import("table.zig");
const ParseAction = table.ParseAction;
const bitset = @import("bitset.zig");
const SetArray = bitset.SetArray;

pub const Expected = struct {
    /// Distinct lists of symbol ids, concatenated: list i is
    /// `symbols[offsets[i]..offsets[i + 1]]`. Nonterminals (named via
    /// `@errors`) come first, then terminals.
    symbols: []const u16,
    offsets: []const u32,
    /// Index of each state's list.
    ofState: []const u16,

    pub fn forState(self: Expected, state: usize) []const u16 {
        const i = self.ofState[state];
        return self.symbols[self.offsets[i]..self.offsets[i + 1]];
    }

    pub fn numLists(self: Expected) usize {
        return self.offsets.len - 1;
    }
};

pub fn compute(g: *const Grammar, auto: *const Automaton, la: Lookaheads, rows: []const []const ParseAction) !Expected {
    const a = g.allocator;
    const numSymbols = g.symbols.items.len;

    // Nonterminals with an @errors name.
    const named = try a.alloc(bool, numSymbols);
    defer a.free(named);
    @memset(named, false);
    for (g.errorNames) |en| {
        if (g.getSymbol(en.rule)) |s| {
            if (g.symbols.items[s].kind == .nonterminal) named[s] = true;
        }
    }

    var symbols: std.ArrayListUnmanaged(u16) = .empty;
    var offsets: std.ArrayListUnmanaged(u32) = .empty;
    try offsets.append(a, 0);
    const ofState = try a.alloc(u16, auto.states.items.len);

    // Dedup: list contents → list index.
    var index = std.StringHashMapUnmanaged(u16){};
    defer index.deinit(a);

    var scratch = try SetArray.init(a, 1, numSymbols);
    defer scratch.deinit(a);
    const covered = scratch.get(0);
    const visited = try a.alloc(bool, numSymbols);
    defer a.free(visited);
    var list: std.ArrayListUnmanaged(u16) = .empty;
    defer list.deinit(a);
    var work: std.ArrayListUnmanaged(u16) = .empty;
    defer work.deinit(a);

    for (auto.states.items, 0..) |state, si| {
        list.clearRetainingCapacity();
        covered.clear();
        @memset(visited, false);

        // Named nonterminals the state waits for, found by expanding unnamed
        // nonterminals after the dot, starting from the kernel.
        work.clearRetainingCapacity();
        for (state.kernel) |item| try pushHeads(a, &work, la, g.rules.items[item.ruleId].rhs[item.dot..]);
        var w: usize = 0;
        while (w < work.items.len) : (w += 1) {
            const s = work.items[w];
            if (g.symbols.items[s].kind != .nonterminal or visited[s]) continue;
            visited[s] = true;
            if (named[s]) {
                try list.append(a, s);
                _ = covered.unionWith(la.first.get(s));
                continue;
            }
            for (g.symbols.items[s].rules.items) |r| try pushHeads(a, &work, la, g.rules.items[r].rhs);
        }

        for (rows[si], 0..) |action, t| {
            if (action == .err or g.symbols.items[t].kind != .terminal) continue;
            if (t == g.errorId or table.isStartMarker(g, @intCast(t))) continue;
            if (covered.isSet(t)) continue;
            try list.append(a, @intCast(t));
        }

        const key = std.mem.sliceAsBytes(list.items);
        const gop = try index.getOrPut(a, key);
        if (!gop.found_existing) {
            gop.key_ptr.* = std.mem.sliceAsBytes(try a.dupe(u16, list.items));
            gop.value_ptr.* = @intCast(offsets.items.len - 1);
            try symbols.appendSlice(a, list.items);
            try offsets.append(a, @intCast(symbols.items.len));
        }
        ofState[si] = gop.value_ptr.*;
    }

    return .{
        .symbols = try symbols.toOwnedSlice(a),
        .offsets = try offsets.toOwnedSlice(a),
        .ofState = ofState,
    };
}

/// Push the symbols a sequence can begin with: its first symbol, and the
/// next one for as long as the symbols before it are nullable.
fn pushHeads(a: Allocator, work: *std.ArrayListUnmanaged(u16), la: Lookaheads, seq: []const u16) !void {
    for (seq) |s| {
        try work.append(a, s);
        if (!la.nullable[s]) break;
    }
}
