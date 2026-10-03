//! The canonical LR(0) automaton: item sets (states) and their transitions,
//! one initial state per start symbol.
//!
//! An item `A → α • β` is a rule with a dot: α has been seen, β is expected,
//! and a dot at the end means the rule can reduce. A state is the closure
//! of its kernel (the items its incoming transition advanced): for every
//! `A → α • B β` it holds `B → • γ` for each rule of B. GOTO(I, X) is the
//! closure of the items of I with the dot advanced over X; states with the
//! same kernel are one state. All memory comes from the grammar's allocator
//! (the generator's arena).
//!
//! Construction is breadth-first from the initial states. A state's
//! transitions follow the order in which its items first name a symbol
//! after the dot, and a new state takes the next number when a transition
//! first reaches its kernel. State numbering therefore depends only on the
//! grammar, never on hashing or the host.

const std = @import("std");
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;

/// LR Item: rule with dot position (A → α • β)
pub const Item = struct {
    ruleId: u16,
    dot: u16,

    pub fn id(self: Item) u32 {
        return (@as(u32, self.ruleId) << 16) | self.dot;
    }

    pub fn eql(a: Item, b: Item) bool {
        return a.ruleId == b.ruleId and a.dot == b.dot;
    }
};

/// LR State: set of items with transitions
pub const State = struct {
    kernel: []const Item, // Kernel items (from shifts/gotos), in discovery order
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
    states: std.ArrayList(State) = .empty,
    /// Initial state of each start symbol (parallel to Grammar.startSymbols).
    startStates: std.ArrayList(u16) = .empty,
};

/// Most parser states: the parse table encodes a shift to state s as the
/// i16 s.
pub const maxStates = 32767;

/// Build the LR(0) automaton of the desugared grammar (which has at least
/// one accept rule).
pub fn build(g: *const Grammar) error{ OutOfMemory, TooManyStates }!Automaton {
    std.debug.assert(g.acceptRules.items.len > 0);
    const a = g.allocator;
    var auto: Automaton = .{};
    var b: Builder = .{
        .g = g,
        .auto = &auto,
        .ruleStamp = try a.alloc(u32, g.rules.items.len),
        .buckets = try a.alloc(std.ArrayList(Item), g.symbols.items.len),
    };
    @memset(b.ruleStamp, 0);
    @memset(b.buckets, .empty);
    for (g.acceptRules.items) |r| {
        const kernel = [_]Item{.{ .ruleId = r, .dot = 0 }};
        try auto.startStates.append(a, try b.intern(&kernel));
    }
    var i: usize = 0;
    while (i < auto.states.items.len) : (i += 1) try b.transitions(i);
    return auto;
}

/// Kernels are interned by their items in ascending order, hashed as
/// little-endian item ids.
const KernelContext = struct {
    pub fn hash(_: KernelContext, k: []const Item) u64 {
        var h = std.hash.Wyhash.init(0);
        for (k) |it| h.update(&std.mem.toBytes(std.mem.nativeToLittle(u32, it.id())));
        return h.final();
    }
    pub fn eql(_: KernelContext, x: []const Item, y: []const Item) bool {
        if (x.len != y.len) return false;
        for (x, y) |p, q| if (!p.eql(q)) return false;
        return true;
    }
};

const Builder = struct {
    g: *const Grammar,
    auto: *Automaton,
    /// Sorted kernel → state.
    map: std.HashMapUnmanaged([]const Item, u16, KernelContext, 80) = .empty,
    sorted: std.ArrayList(Item) = .empty,
    /// Closure: ruleStamp[r] == stamp when `r → • ...` is in the current closure.
    ruleStamp: []u32,
    stamp: u32 = 0,
    /// Transitions: the advanced items per symbol of the current state, and
    /// the symbols in first-seen order.
    buckets: []std.ArrayList(Item),
    order: std.ArrayList(u16) = .empty,

    fn lessItem(_: void, x: Item, y: Item) bool {
        return x.id() < y.id();
    }

    /// The state with this kernel, created (and closed) if new.
    fn intern(b: *Builder, kernel: []const Item) !u16 {
        const a = b.g.allocator;
        b.sorted.clearRetainingCapacity();
        try b.sorted.appendSlice(a, kernel);
        std.mem.sort(Item, b.sorted.items, {}, lessItem);
        const gop = try b.map.getOrPut(a, b.sorted.items);
        if (gop.found_existing) return gop.value_ptr.*;
        if (b.auto.states.items.len >= maxStates) {
            _ = b.map.remove(b.sorted.items);
            return error.TooManyStates;
        }
        gop.key_ptr.* = try a.dupe(Item, b.sorted.items);
        const id: u16 = @intCast(b.auto.states.items.len);
        gop.value_ptr.* = id;
        try b.auto.states.append(a, try b.closure(try a.dupe(Item, kernel)));
        return id;
    }

    /// The kernel's state: the kernel, then for each item with a
    /// nonterminal B after the dot every `B → • γ` not yet present.
    fn closure(b: *Builder, kernel: []const Item) !State {
        const g = b.g;
        const a = g.allocator;
        b.stamp += 1;
        var all: std.ArrayList(Item) = .empty;
        var reductions: std.ArrayList(Item) = .empty;
        try all.appendSlice(a, kernel);
        for (kernel) |it| {
            if (it.dot == 0) b.ruleStamp[it.ruleId] = b.stamp;
        }
        var w: usize = 0;
        while (w < all.items.len) : (w += 1) {
            const item = all.items[w];
            const rhs = g.rules.items[item.ruleId].rhs;
            if (item.dot >= rhs.len) {
                try reductions.append(a, item);
                continue;
            }
            const sym = &g.symbols.items[rhs[item.dot]];
            if (sym.kind != .nonterminal) continue;
            for (sym.rules.items) |r| {
                if (b.ruleStamp[r] == b.stamp) continue;
                b.ruleStamp[r] = b.stamp;
                try all.append(a, .{ .ruleId = r, .dot = 0 });
            }
        }
        return .{
            .kernel = kernel,
            .items = try all.toOwnedSlice(a),
            .transitions = &.{},
            .reductions = try reductions.toOwnedSlice(a),
        };
    }

    /// State si's transitions: GOTO on each symbol after a dot, in the order
    /// the state's items first name them.
    fn transitions(b: *Builder, si: usize) !void {
        const g = b.g;
        const a = g.allocator;
        b.order.clearRetainingCapacity();
        for (b.auto.states.items[si].items) |item| {
            const rhs = g.rules.items[item.ruleId].rhs;
            if (item.dot >= rhs.len) continue;
            const x = rhs[item.dot];
            if (b.buckets[x].items.len == 0) try b.order.append(a, x);
            try b.buckets[x].append(a, .{ .ruleId = item.ruleId, .dot = item.dot + 1 });
        }
        const trans = try a.alloc(Transition, b.order.items.len);
        for (b.order.items, trans) |x, *t| {
            t.* = .{ .symbol = x, .target = try b.intern(b.buckets[x].items) };
            b.buckets[x].clearRetainingCapacity();
        }
        b.auto.states.items[si].transitions = trans;
    }
};
