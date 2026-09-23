//! The previous lookahead and table algorithms (spontaneous generation and
//! propagation, Aho et al. 4.7.5; per-cell conflict resolution in reduction
//! order), kept only as the reference for `--verify-lalr`, which checks that
//! the DeRemer–Pennello tables are identical.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const SymbolSet = grammar.SymbolSet;
const automaton = @import("automaton.zig");
const Automaton = automaton.Automaton;
const Item = automaton.Item;
const table = @import("table.zig");
const ParseAction = table.ParseAction;
const XExclude = table.XExclude;
const ParseMode = @import("lookahead.zig").ParseMode;

pub const Result = struct {
    rows: [][]ParseAction,
    xExcludes: []XExclude,
    conflicts: u32,
};

const Sets = struct {
    nullable: []bool,
    firsts: []SymbolSet,
    follows: []SymbolSet,
};

pub fn build(g: *const Grammar, auto: *const Automaton, mode: ParseMode) !Result {
    const a = g.allocator;
    const n = g.symbols.items.len;
    var sets: Sets = .{
        .nullable = try a.alloc(bool, n),
        .firsts = try a.alloc(SymbolSet, n),
        .follows = try a.alloc(SymbolSet, n),
    };
    for (0..n) |i| {
        sets.nullable[i] = g.symbols.items[i].kind == .nonterminal and g.symbols.items[i].nullable;
        sets.firsts[i] = .empty;
        sets.follows[i] = .empty;
    }
    try computeNullable(g, &sets);
    try computeFirst(g, &sets);
    var lalr: []const []const SymbolSet = &.{};
    switch (mode) {
        .slr => try computeFollow(g, &sets),
        .lalr => lalr = try computeLalrLookaheads(g, auto, &sets),
    }
    return buildTable(g, auto, mode, &sets, lalr);
}

fn computeNullable(g: *const Grammar, sets: *Sets) !void {
    const ruleNullable = try g.allocator.alloc(bool, g.rules.items.len);
    for (g.rules.items, 0..) |r, i| ruleNullable[i] = r.rhs.len == 0;
    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items, 0..) |rule, ri| {
            if (ruleNullable[ri]) continue;
            var allNullable = true;
            for (rule.rhs) |symId| {
                if (!sets.nullable[symId]) {
                    allNullable = false;
                    break;
                }
            }
            if (allNullable) {
                ruleNullable[ri] = true;
                changed = true;
            }
        }
        for (g.symbols.items, 0..) |sym, si| {
            if (sets.nullable[si] or sym.kind != .nonterminal) continue;
            for (sym.rules.items) |ruleId| {
                if (ruleNullable[ruleId]) {
                    sets.nullable[si] = true;
                    changed = true;
                    break;
                }
            }
        }
    }
}

fn computeFirst(g: *const Grammar, sets: *Sets) !void {
    const ruleFirsts = try g.allocator.alloc(SymbolSet, g.rules.items.len);
    for (ruleFirsts) |*s| s.* = .empty;
    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items, 0..) |rule, ri| {
            const oldCount = ruleFirsts[ri].count();
            try firstOfSequence(g, sets, &ruleFirsts[ri], rule.rhs);
            if (ruleFirsts[ri].count() > oldCount) changed = true;
        }
        for (g.symbols.items, 0..) |sym, si| {
            if (sym.kind != .nonterminal) continue;
            for (sym.rules.items) |ruleId| {
                if (try sets.firsts[si].addAll(g.allocator, &ruleFirsts[ruleId])) changed = true;
            }
        }
    }
}

fn firstOfSequence(g: *const Grammar, sets: *const Sets, result: *SymbolSet, symbols: []const u16) !void {
    for (symbols) |symId| {
        if (g.symbols.items[symId].kind == .terminal) {
            try result.add(g.allocator, symId);
            break;
        } else {
            _ = try result.addAll(g.allocator, &sets.firsts[symId]);
            if (!sets.nullable[symId]) break;
        }
    }
}

fn computeFollow(g: *const Grammar, sets: *Sets) !void {
    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            for (rule.rhs, 0..) |symId, i| {
                if (g.symbols.items[symId].kind != .nonterminal) continue;
                const follows = &sets.follows[symId];
                const oldCount = follows.count();
                if (i == rule.rhs.len - 1) {
                    if (try follows.addAll(g.allocator, &sets.follows[rule.lhs])) changed = true;
                } else {
                    const beta = rule.rhs[i + 1 ..];
                    try firstOfSequence(g, sets, follows, beta);
                    var betaNullable = true;
                    for (beta) |b| {
                        if (!sets.nullable[b]) {
                            betaNullable = false;
                            break;
                        }
                    }
                    if (betaNullable) _ = try follows.addAll(g.allocator, &sets.follows[rule.lhs]);
                }
                if (follows.count() > oldCount) changed = true;
            }
        }
    }
}

const Lr1Item = struct {
    ruleId: u16,
    dot: u8,
    lookahead: u16,

    fn key(self: Lr1Item) u64 {
        return (@as(u64, self.ruleId) << 24) | (@as(u64, self.dot) << 16) | self.lookahead;
    }
};

fn firstOfSuffix(g: *const Grammar, sets: *const Sets, rhs: []const u16, startDot: usize, lookahead: u16) !SymbolSet {
    var result = SymbolSet{};
    var allNullable = true;
    for (rhs[startDot..]) |symId| {
        if (g.symbols.items[symId].kind == .terminal) {
            try result.add(g.allocator, symId);
            allNullable = false;
            break;
        } else {
            _ = try result.addAll(g.allocator, &sets.firsts[symId]);
            if (!sets.nullable[symId]) {
                allNullable = false;
                break;
            }
        }
    }
    if (allNullable) try result.add(g.allocator, lookahead);
    return result;
}

fn probeClosure(g: *const Grammar, sets: *const Sets, seedItem: Lr1Item, items: *std.ArrayListUnmanaged(Lr1Item), seen: *std.AutoHashMap(u64, void)) !void {
    seen.clearRetainingCapacity();
    items.clearRetainingCapacity();
    try items.append(g.allocator, seedItem);
    try seen.put(seedItem.key(), {});
    var workIdx: usize = 0;
    while (workIdx < items.items.len) : (workIdx += 1) {
        const item = items.items[workIdx];
        const rule = g.rules.items[item.ruleId];
        if (item.dot >= rule.rhs.len) continue;
        const nextSym = rule.rhs[item.dot];
        const symbol = g.symbols.items[nextSym];
        if (symbol.kind == .nonterminal) {
            var firstSet = try firstOfSuffix(g, sets, rule.rhs, item.dot + 1, item.lookahead);
            defer firstSet.deinit(g.allocator);
            for (symbol.rules.items) |ruleId| {
                for (firstSet.slice()) |la| {
                    const newItem = Lr1Item{ .ruleId = ruleId, .dot = 0, .lookahead = la };
                    if (!seen.contains(newItem.key())) {
                        try seen.put(newItem.key(), {});
                        try items.append(g.allocator, newItem);
                    }
                }
            }
        }
    }
}

fn computeLalrLookaheads(g: *const Grammar, auto: *const Automaton, sets: *const Sets) ![]const []const SymbolSet {
    const a = g.allocator;
    const numStates = auto.states.items.len;
    const sentinel: u16 = std.math.maxInt(u16);
    const kernelOffsets = try a.alloc(u32, numStates + 1);
    const reductionOffsets = try a.alloc(u32, numStates + 1);
    kernelOffsets[0] = 0;
    reductionOffsets[0] = 0;
    for (0..numStates) |s| {
        kernelOffsets[s + 1] = kernelOffsets[s] + @as(u32, @intCast(auto.states.items[s].kernel.len));
        reductionOffsets[s + 1] = reductionOffsets[s] + @as(u32, @intCast(auto.states.items[s].reductions.len));
    }
    const totalKernelNodes = kernelOffsets[numStates];
    const totalNodes = totalKernelNodes + reductionOffsets[numStates];
    const nodeSets = try a.alloc(SymbolSet, totalNodes);
    for (nodeSets) |*s| s.* = .empty;

    const Edge = struct { source: u32, target: u32 };
    var edges: std.ArrayListUnmanaged(Edge) = .empty;
    var closureItems: std.ArrayListUnmanaged(Lr1Item) = .empty;
    var seen = std.AutoHashMap(u64, void).init(a);

    for (auto.states.items, 0..) |state, si| {
        for (state.kernel, 0..) |kernelItem, ki| {
            const sourceNode: u32 = kernelOffsets[si] + @as(u32, @intCast(ki));
            const seed = Lr1Item{ .ruleId = kernelItem.ruleId, .dot = kernelItem.dot, .lookahead = sentinel };
            try probeClosure(g, sets, seed, &closureItems, &seen);
            for (closureItems.items) |cItem| {
                const rule = g.rules.items[cItem.ruleId];
                if (cItem.dot >= rule.rhs.len) {
                    const ri = for (state.reductions, 0..) |red, ri| {
                        if (red.ruleId == cItem.ruleId) break @as(u32, @intCast(ri));
                    } else unreachable;
                    const targetNode: u32 = totalKernelNodes + reductionOffsets[si] + ri;
                    if (cItem.lookahead == sentinel) {
                        try edges.append(a, .{ .source = sourceNode, .target = targetNode });
                    } else {
                        try nodeSets[targetNode].add(a, cItem.lookahead);
                    }
                } else {
                    const nextSym = rule.rhs[cItem.dot];
                    const transTarget = for (state.transitions) |trans| {
                        if (trans.symbol == nextSym) break trans.target;
                    } else unreachable;
                    const advancedItem = Item{ .ruleId = cItem.ruleId, .dot = cItem.dot + 1 };
                    const targetKernel = &auto.states.items[transTarget];
                    const tkiIdx = for (targetKernel.kernel, 0..) |tki, idx| {
                        if (tki.eql(advancedItem)) break @as(u32, @intCast(idx));
                    } else unreachable;
                    const targetNode: u32 = kernelOffsets[transTarget] + tkiIdx;
                    if (cItem.lookahead == sentinel) {
                        try edges.append(a, .{ .source = sourceNode, .target = targetNode });
                    } else {
                        try nodeSets[targetNode].add(a, cItem.lookahead);
                    }
                }
            }
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (edges.items) |edge| {
            if (try nodeSets[edge.target].addAll(a, &nodeSets[edge.source])) changed = true;
        }
    }

    const lalrLookaheads = try a.alloc([]const SymbolSet, numStates);
    for (0..numStates) |si| {
        const nr = auto.states.items[si].reductions.len;
        const out = try a.alloc(SymbolSet, nr);
        for (0..nr) |ri| out[ri] = nodeSets[totalKernelNodes + reductionOffsets[si] + ri];
        lalrLookaheads[si] = out;
    }
    return lalrLookaheads;
}

fn buildTable(g: *const Grammar, auto: *const Automaton, mode: ParseMode, sets: *const Sets, lalr: []const []const SymbolSet) !Result {
    const a = g.allocator;
    const numSymbols = g.symbols.items.len;
    const rows = try a.alloc([]ParseAction, auto.states.items.len);
    var xExcludes: std.ArrayListUnmanaged(XExclude) = .empty;
    var conflicts: u32 = 0;
    for (rows, 0..) |*row, i| {
        row.* = try a.alloc(ParseAction, numSymbols);
        for (row.*) |*cell| cell.* = .err;
        const state = &auto.states.items[i];
        for (state.transitions) |trans| {
            row.*[trans.symbol] = if (g.symbols.items[trans.symbol].kind == .nonterminal)
                .{ .gotoState = trans.target }
            else
                .{ .shift = trans.target };
        }
        for (state.items) |item| {
            const rule = &g.rules.items[item.ruleId];
            if (item.dot < rule.rhs.len and rule.rhs[item.dot] == g.endId and g.isAcceptRule(item.ruleId))
                row.*[g.endId] = .accept;
        }
        for (state.reductions, 0..) |item, ri| {
            const rule = &g.rules.items[item.ruleId];
            if (g.isAcceptRule(item.ruleId)) {
                row.*[g.endId] = .accept;
                continue;
            }
            const reduceTerminals = switch (mode) {
                .slr => sets.follows[rule.lhs].slice(),
                .lalr => lalr[i][ri].slice(),
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
                            try xExcludes.append(a, .{ .state = @intCast(i), .char = xChar, .shift = s });
                        } else if (rule.preferReduce) {
                            current.* = .{ .reduce = item.ruleId };
                        } else if (rule.preferShift) {} else {
                            conflicts += 1;
                        }
                    },
                    .reduce => |existing| {
                        if (item.ruleId < existing) current.* = .{ .reduce = item.ruleId };
                        conflicts += 1;
                    },
                    else => {},
                }
            }
        }
    }
    return .{ .rows = rows, .xExcludes = try xExcludes.toOwnedSlice(a), .conflicts = conflicts };
}
