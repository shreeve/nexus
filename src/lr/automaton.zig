//! The canonical LR(0) automaton: item sets (states) and their transitions,
//! one initial state per start symbol.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;

/// LR Item: rule with dot position (A → α • β)
pub const Item = struct {
    ruleId: u16,
    dot: u8,

    pub fn id(self: Item) u32 {
        return (@as(u32, self.ruleId) << 8) | self.dot;
    }

    pub fn eql(a: Item, b: Item) bool {
        return a.ruleId == b.ruleId and a.dot == b.dot;
    }
};

/// LR State: set of items with transitions
pub const State = struct {
    id: u16,
    kernel: []const Item, // Kernel items (from shifts/gotos)
    items: []const Item, // All items (kernel + closure)
    transitions: []const Transition,
    reductions: []const Item, // Items with dot at end
};

/// Transition from one state to another on a symbol
pub const Transition = struct {
    symbol: u16,
    target: u16,
};

pub const Automaton = struct {
    states: std.ArrayListUnmanaged(State) = .empty,
    /// Initial state of each start symbol (parallel to Grammar.startSymbols).
    startStates: std.ArrayListUnmanaged(u16) = .empty,

    pub fn deinit(self: *Automaton, allocator: Allocator) void {
        for (self.states.items) |*state| {
            allocator.free(state.kernel);
            allocator.free(state.items);
            allocator.free(state.transitions);
            allocator.free(state.reductions);
        }
        self.states.deinit(allocator);
        self.startStates.deinit(allocator);
    }
};

// =============================================================================
// LR Automaton Construction
// =============================================================================
//
// LR parsing uses a deterministic finite automaton (DFA) where:
//   - States are sets of "items" (rules with a dot showing parse progress)
//   - Transitions occur on terminals (shift) or nonterminals (goto)
//   - The automaton recognizes viable prefixes of the grammar
//
// An LR item looks like: A → α • β
//   - The dot (•) shows how much of the rule we've seen
//   - α is what we've matched, β is what we expect
//   - When dot is at end (A → α •), we can reduce
//
// Construction algorithm:
//   1. Start with item S' → • S $ (augmented start rule)
//   2. Compute closure of initial items
//   3. For each symbol X, compute GOTO(state, X) = closure of shifted items
//   4. Repeat until no new states are created
//
// =============================================================================

/// Build the LR(0) automaton from the processed grammar.
/// Creates states and transitions for the shift-reduce parser.
/// Most parser states: the parse table encodes a shift to state s as the
/// i16 s.
pub const maxStates = 32767;

pub fn build(g: *const Grammar) !Automaton {
    var automaton: Automaton = .{};
    const auto = &automaton;
    if (g.acceptRules.items.len == 0) return error.NoAcceptRule;

    var stateMap = std.StringHashMapUnmanaged(u16){};
    defer stateMap.deinit(g.allocator);

    // Create initial state for EACH accept rule
    for (g.acceptRules.items) |acceptRuleId| {
        var initialItems: std.ArrayListUnmanaged(Item) = .empty;
        try initialItems.append(g.allocator, .{ .ruleId = acceptRuleId, .dot = 0 });

        const kernel = try initialItems.toOwnedSlice(g.allocator);
        const sig = try kernelSignature(g.allocator, kernel);

        if (stateMap.get(sig)) |existingId| {
            try auto.startStates.append(g.allocator, existingId);
        } else {
            const initialState = try closure(g, auto, kernel);
            const stateId: u16 = @intCast(auto.states.items.len);
            try auto.states.append(g.allocator, initialState);
            try stateMap.put(g.allocator, sig, stateId);
            try auto.startStates.append(g.allocator, stateId);
        }
    }

    // Process states until no new ones
    var i: usize = 0;
    while (i < auto.states.items.len) : (i += 1) {
        try processTransitions(g, auto, i, &stateMap);
    }
    return automaton;
}

/// Compute the closure of a set of LR items.
///
/// Closure adds items for nonterminals that appear after the dot.
/// If we have A → α • B β, we add B → • γ for all productions of B.
///
/// Intuition: If we're waiting to see B, we need to recognize what B
/// looks like, so we add all ways B can start.
///
/// Example:
///   Kernel: { E → • T }
///   If T → F | T * F, closure adds: { T → • F, T → • T * F }
///   If F → id, closure adds: { F → • id }
///   Result: { E → • T, T → • F, T → • T * F, F → • id }
fn closure(g: *const Grammar, auto: *const Automaton, kernel: []const Item) !State {
    var allItems: std.ArrayListUnmanaged(Item) = .empty;
    var reductions: std.ArrayListUnmanaged(Item) = .empty;
    var seen = std.AutoHashMap(u32, void).init(g.allocator);
    defer seen.deinit();

    // Start with kernel items
    for (kernel) |item| {
        try allItems.append(g.allocator, item);
        try seen.put(item.id(), {});
    }

    // Process items, adding closure items as we go
    var workIdx: usize = 0;
    while (workIdx < allItems.items.len) : (workIdx += 1) {
        const item = allItems.items[workIdx];
        const rule = g.rules.items[item.ruleId];

        // Item with dot at end → reduction item
        if (item.dot >= rule.rhs.len) {
            try reductions.append(g.allocator, item);
            continue;
        }

        // If next symbol after dot is nonterminal, add its productions
        const nextSym = rule.rhs[item.dot];
        const symbol = g.symbols.items[nextSym];

        if (symbol.kind == .nonterminal) {
            for (symbol.rules.items) |ruleId| {
                const newItem = Item{ .ruleId = ruleId, .dot = 0 };
                if (!seen.contains(newItem.id())) {
                    try seen.put(newItem.id(), {});
                    try allItems.append(g.allocator, newItem);
                }
            }
        }
    }

    return State{
        .id = @intCast(auto.states.items.len),
        .kernel = kernel,
        .items = try allItems.toOwnedSlice(g.allocator),
        .transitions = &[_]Transition{},
        .reductions = try reductions.toOwnedSlice(g.allocator),
    };
}

/// Compute GOTO transitions for a state.
///
/// GOTO(I, X) = closure({ A → α X • β | A → α • X β ∈ I })
///
/// For each symbol X that appears after a dot in state I:
///   1. Collect all items with X after the dot
///   2. Advance the dot past X in each item (shift the dot)
///   3. Compute closure of the resulting items
///   4. This closure is the target state for transition on X
///
/// If the target state already exists (same kernel), reuse it.
fn processTransitions(g: *const Grammar, auto: *Automaton, stateIdx: usize, stateMap: *std.StringHashMapUnmanaged(u16)) !void {
    const state = &auto.states.items[stateIdx];
    var transitions: std.ArrayListUnmanaged(Transition) = .empty;

    // Group items by the symbol after the dot
    var symbolItems = std.AutoHashMap(u16, std.ArrayListUnmanaged(Item)).init(g.allocator);
    defer {
        var iter = symbolItems.valueIterator();
        while (iter.next()) |list| list.deinit(g.allocator);
        symbolItems.deinit();
    }

    for (state.items) |item| {
        const rule = g.rules.items[item.ruleId];
        if (item.dot >= rule.rhs.len) continue; // No symbol after dot

        const nextSym = rule.rhs[item.dot];
        const entry = try symbolItems.getOrPut(nextSym);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        // Advance dot: A → α • X β becomes A → α X • β
        try entry.value_ptr.append(g.allocator, .{ .ruleId = item.ruleId, .dot = item.dot + 1 });
    }

    // Create transitions and target states
    var iter = symbolItems.iterator();
    while (iter.next()) |entry| {
        const sym = entry.key_ptr.*;
        const itemsList = entry.value_ptr;

        const kernel = try g.allocator.dupe(Item, itemsList.items);
        const sig = try kernelSignature(g.allocator, kernel);

        // Reuse existing state with same kernel, or create new one
        const target = if (stateMap.get(sig)) |existing| existing else blk: {
            if (auto.states.items.len >= maxStates) return error.TooManyStates;
            const newState = try closure(g, auto, kernel);
            const newId: u16 = @intCast(auto.states.items.len);
            try auto.states.append(g.allocator, newState);
            try stateMap.put(g.allocator, sig, newId);
            break :blk newId;
        };

        try transitions.append(g.allocator, .{ .symbol = sym, .target = target });
    }

    auto.states.items[stateIdx].transitions = try transitions.toOwnedSlice(g.allocator);
}

/// Generate a unique signature for a kernel (set of items).
/// States with identical kernels are merged to avoid duplication.
fn kernelSignature(allocator: Allocator, kernel: []const Item) ![]const u8 {
    var sig: std.ArrayListUnmanaged(u8) = .empty;

    const sorted = try allocator.dupe(Item, kernel);
    defer allocator.free(sorted);

    std.mem.sort(Item, sorted, {}, struct {
        fn lessThan(_: void, a: Item, b: Item) bool {
            if (a.ruleId != b.ruleId) return a.ruleId < b.ruleId;
            return a.dot < b.dot;
        }
    }.lessThan);

    for (sorted, 0..) |item, i| {
        if (i > 0) try sig.append(allocator, '|');
        var buf: [32]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}.{d}", .{ item.ruleId, item.dot }) catch "";
        try sig.appendSlice(allocator, slice);
    }

    return try sig.toOwnedSlice(allocator);
}
