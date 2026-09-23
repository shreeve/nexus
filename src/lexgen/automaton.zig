//! Lexer automaton: Thompson NFA over byte classes, subset construction into
//! a DFA with one start state per guard configuration, and Moore-style
//! minimization.
//!
//! Matching semantics: from a start state, the lexer follows transitions
//! byte by byte and remembers the last accepting state it passed; the token
//! is the longest match, and when several rules accept the same longest
//! match the earliest rule (lowest index) wins. A DFA state's `accept` is
//! therefore the lowest rule index among the NFA accept states it contains.
//! The start states never accept: every token consumes at least one byte.

const std = @import("std");
const Allocator = std.mem.Allocator;
const regex = @import("regex.zig");
const ByteSet = regex.ByteSet;
const Node = regex.Node;

/// No transition / no accepting rule.
pub const none: u32 = std.math.maxInt(u32);

/// Upper bound on NFA size (bounded repeats are expanded).
pub const maxNfaStates: usize = 200_000;

pub const Error = error{ OutOfMemory, AutomatonTooLarge };

// =============================================================================
// Byte classes
// =============================================================================

/// A partition of the 256 byte values into classes that no pattern can
/// tell apart. Transition tables are indexed by class.
pub const ByteClasses = struct {
    classOf: [256]u8,
    count: u16,
    /// One representative byte per class.
    rep: [256]u8,

    pub fn compute(sets: []const ByteSet) ByteClasses {
        var bc: ByteClasses = .{ .classOf = @splat(0), .count = 1, .rep = undefined };
        for (sets) |s| {
            // Split every class that `s` cuts.
            var newId: [256]u16 = @splat(0xFFFF);
            var remapCount: u16 = bc.count;
            var b: usize = 0;
            while (b < 256) : (b += 1) {
                if (!s.has(@intCast(b))) continue;
                const c = bc.classOf[b];
                // Does class c contain a byte outside s? Then the bytes of c inside s move to a new class.
                if (newId[c] == 0xFFFF) {
                    var split = false;
                    for (0..256) |x| {
                        if (bc.classOf[x] == c and !s.has(@intCast(x))) {
                            split = true;
                            break;
                        }
                    }
                    newId[c] = if (split) blk: {
                        remapCount += 1;
                        break :blk remapCount - 1;
                    } else c;
                }
            }
            for (0..256) |x| {
                if (s.has(@intCast(x))) {
                    const c = bc.classOf[x];
                    bc.classOf[x] = @intCast(newId[c]);
                }
            }
            bc.count = remapCount;
        }
        // Renumber classes in order of first byte so output is canonical.
        var order: [256]u16 = @splat(0xFFFF);
        var next: u16 = 0;
        for (0..256) |x| {
            const c = bc.classOf[x];
            if (order[c] == 0xFFFF) {
                order[c] = next;
                bc.rep[next] = @intCast(x);
                next += 1;
            }
            bc.classOf[x] = @intCast(order[c]);
        }
        bc.count = next;
        return bc;
    }

    /// The bytes of class `c`.
    pub fn bytes(self: *const ByteClasses, c: u16) ByteSet {
        var s: ByteSet = .{};
        for (0..256) |x| {
            if (self.classOf[x] == c) s.add(@intCast(x));
        }
        return s;
    }
};

// =============================================================================
// NFA
// =============================================================================

pub const Nfa = struct {
    states: std.ArrayListUnmanaged(State) = .empty,

    pub const State = struct {
        /// Byte-consuming edge (when `set` is non-null) to `out`.
        set: ?ByteSet = null,
        out: u32 = none,
        /// Epsilon edges.
        eps1: u32 = none,
        eps2: u32 = none,
        /// Accepting state of this rule.
        accept: u32 = none,
    };

    const Frag = struct { start: u32, end: u32 };

    fn add(self: *Nfa, gpa: Allocator, s: State) Error!u32 {
        if (self.states.items.len >= maxNfaStates) return error.AutomatonTooLarge;
        try self.states.append(gpa, s);
        return @intCast(self.states.items.len - 1);
    }

    /// Build a fragment for `n`: `start` and a dangling `end` (an epsilon
    /// state whose eps1 the caller patches).
    fn build(self: *Nfa, gpa: Allocator, n: *const Node) Error!Frag {
        switch (n.*) {
            .empty => {
                const s = try self.add(gpa, .{});
                return .{ .start = s, .end = s };
            },
            .set => |b| {
                const end = try self.add(gpa, .{});
                const s = try self.add(gpa, .{ .set = b, .out = end });
                return .{ .start = s, .end = end };
            },
            .concat => |kids| {
                var first = try self.build(gpa, kids[0]);
                for (kids[1..]) |k| {
                    const f = try self.build(gpa, k);
                    self.states.items[first.end].eps1 = f.start;
                    first.end = f.end;
                }
                return first;
            },
            .alt => |kids| {
                const end = try self.add(gpa, .{});
                // Chain of split states: s0 -> k0 | s1, s1 -> k1 | s2, ...
                var start: u32 = none;
                var prevSplit: u32 = none;
                for (kids, 0..) |k, i| {
                    const f = try self.build(gpa, k);
                    self.states.items[f.end].eps1 = end;
                    if (i == kids.len - 1) {
                        if (prevSplit == none) {
                            start = f.start;
                        } else {
                            self.states.items[prevSplit].eps2 = f.start;
                        }
                    } else {
                        const split = try self.add(gpa, .{ .eps1 = f.start });
                        if (prevSplit == none) start = split else self.states.items[prevSplit].eps2 = split;
                        prevSplit = split;
                    }
                }
                return .{ .start = start, .end = end };
            },
            .repeat => |r| {
                const start = try self.add(gpa, .{});
                var cur = start;
                var i: u32 = 0;
                while (i < r.min) : (i += 1) {
                    const f = try self.build(gpa, r.sub);
                    self.states.items[cur].eps1 = f.start;
                    cur = f.end;
                }
                if (r.max) |mx| {
                    // (max - min) optional copies: each may be skipped to the end.
                    const end = try self.add(gpa, .{});
                    var j: u32 = r.min;
                    while (j < mx) : (j += 1) {
                        const f = try self.build(gpa, r.sub);
                        self.states.items[cur].eps1 = f.start;
                        self.states.items[cur].eps2 = end;
                        cur = f.end;
                    }
                    self.states.items[cur].eps1 = end;
                    return .{ .start = start, .end = end };
                }
                // Unbounded: loop state -> sub -> loop, loop -> end.
                const loop = try self.add(gpa, .{});
                const end = try self.add(gpa, .{});
                self.states.items[cur].eps1 = loop;
                const f = try self.build(gpa, r.sub);
                self.states.items[loop].eps1 = f.start;
                self.states.items[loop].eps2 = end;
                self.states.items[f.end].eps1 = loop;
                return .{ .start = start, .end = end };
            },
        }
    }

    /// Add a rule: returns its start state; its end state accepts `rule`.
    pub fn addRule(self: *Nfa, gpa: Allocator, pattern: *const Node, rule: u32) Error!u32 {
        const f = try self.build(gpa, pattern);
        const acc = try self.add(gpa, .{ .accept = rule });
        self.states.items[f.end].eps1 = acc;
        return f.start;
    }
};

// =============================================================================
// DFA
// =============================================================================

/// A match: the winning rule and the token length.
pub const Match = struct { rule: u32, len: usize };

pub const Dfa = struct {
    classes: ByteClasses,
    /// `trans[state * classes.count + class]`, `none` = no transition.
    trans: []u32,
    /// Accepting rule per state, `none` if not accepting.
    accept: []u32,
    /// Start state per start configuration (parallel to the `starts` input).
    starts: []u32,
    numStates: u32,

    pub fn next(self: *const Dfa, state: u32, byte: u8) u32 {
        return self.trans[state * self.classes.count + self.classes.classOf[byte]];
    }

    /// A shortest input accepted from start configuration `start` (breadth
    /// first over states), or null if none is.
    pub fn shortestAccepted(self: *const Dfa, gpa: Allocator, start: u32) !?[]u8 {
        const nc = self.classes.count;
        const prev = try gpa.alloc(u32, self.numStates);
        defer gpa.free(prev);
        const via = try gpa.alloc(u8, self.numStates);
        defer gpa.free(via);
        @memset(prev, none);
        const s0 = self.starts[start];
        var queue: std.ArrayListUnmanaged(u32) = .empty;
        defer queue.deinit(gpa);
        try queue.append(gpa, s0);
        prev[s0] = s0;
        var qi: usize = 0;
        while (qi < queue.items.len) : (qi += 1) {
            const s = queue.items[qi];
            if (self.accept[s] != none and s != s0) {
                var bytes: std.ArrayListUnmanaged(u8) = .empty;
                var t = s;
                while (t != s0) : (t = prev[t]) try bytes.append(gpa, via[t]);
                std.mem.reverse(u8, bytes.items);
                return try bytes.toOwnedSlice(gpa);
            }
            for (0..nc) |c| {
                const t = self.trans[s * nc + c];
                if (t == none or prev[t] != none) continue;
                prev[t] = s;
                via[t] = self.classes.rep[c];
                try queue.append(gpa, t);
            }
        }
        return null;
    }

    pub fn deinit(self: *Dfa, gpa: Allocator) void {
        gpa.free(self.trans);
        gpa.free(self.accept);
        gpa.free(self.starts);
    }

    /// Longest match from start configuration `start` over `input`.
    pub fn longestMatch(self: *const Dfa, start: u32, input: []const u8) ?Match {
        return self.longestMatchFrom(self.starts[start], input);
    }

    /// Longest match from DFA state `state` over `input`: (rule, length), or null.
    pub fn longestMatchFrom(self: *const Dfa, state: u32, input: []const u8) ?Match {
        var s = state;
        var best: ?Match = null;
        for (input, 0..) |b, i| {
            s = self.next(s, b);
            if (s == none) break;
            if (self.accept[s] != none) best = .{ .rule = self.accept[s], .len = i + 1 };
        }
        return best;
    }
};

/// Input to `build`: every rule's pattern (the full text the automaton must
/// match, trailing context included), and per start configuration the
/// indices of the rules live in it.
pub const Spec = struct {
    patterns: []const *const Node,
    starts: []const []const u32,
};

/// Build the minimized DFA.
pub fn build(gpa: Allocator, spec: Spec) Error!Dfa {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Byte classes from every set in every pattern.
    var sets: std.ArrayListUnmanaged(ByteSet) = .empty;
    for (spec.patterns) |p| try collectSets(a, p, &sets);
    const classes = ByteClasses.compute(sets.items);

    var nfa: Nfa = .{};
    const ruleStart = try a.alloc(u32, spec.patterns.len);
    for (spec.patterns, 0..) |p, i| ruleStart[i] = try nfa.addRule(a, p, @intCast(i));

    const raw = try subsetConstruct(a, &nfa, classes, ruleStart, spec.starts);
    return minimize(gpa, raw, classes);
}

fn collectSets(a: Allocator, n: *const Node, out: *std.ArrayListUnmanaged(ByteSet)) Error!void {
    switch (n.*) {
        .empty => {},
        .set => |b| {
            for (out.items) |s| if (s.eql(b)) return;
            try out.append(a, b);
        },
        .concat, .alt => |kids| for (kids) |k| try collectSets(a, k, out),
        .repeat => |r| try collectSets(a, r.sub, out),
    }
}

const RawDfa = struct {
    trans: []u32,
    accept: []u32,
    starts: []u32,
    numStates: u32,
};

/// Epsilon closure of `seed` into a sorted list of "important" NFA states
/// (byte-consuming or accepting).
fn closure(a: Allocator, nfa: *const Nfa, seed: []const u32, mark: []u32, stamp: u32, out: *std.ArrayListUnmanaged(u32)) Error!void {
    out.clearRetainingCapacity();
    var stack: std.ArrayListUnmanaged(u32) = .empty;
    for (seed) |s| {
        if (mark[s] != stamp) {
            mark[s] = stamp;
            try stack.append(a, s);
        }
    }
    while (stack.pop()) |s| {
        const st = nfa.states.items[s];
        if (st.set != null or st.accept != none) try out.append(a, s);
        for ([2]u32{ st.eps1, st.eps2 }) |e| {
            if (e != none and mark[e] != stamp) {
                mark[e] = stamp;
                try stack.append(a, e);
            }
        }
    }
    std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
}

fn subsetConstruct(a: Allocator, nfa: *const Nfa, classes: ByteClasses, ruleStart: []const u32, starts: []const []const u32) Error!RawDfa {
    const nc = classes.count;
    const mark = try a.alloc(u32, nfa.states.items.len);
    @memset(mark, 0);
    var stamp: u32 = 0;

    var keys: std.ArrayListUnmanaged([]const u32) = .empty;
    var map: std.HashMapUnmanaged([]const u32, u32, SliceContext, 80) = .empty;
    var trans: std.ArrayListUnmanaged(u32) = .empty;
    var accept: std.ArrayListUnmanaged(u32) = .empty;
    var set: std.ArrayListUnmanaged(u32) = .empty;
    var seed: std.ArrayListUnmanaged(u32) = .empty;

    const startIds = try a.alloc(u32, starts.len);
    for (starts, 0..) |live, si| {
        seed.clearRetainingCapacity();
        for (live) |r| try seed.append(a, ruleStart[r]);
        stamp += 1;
        try closure(a, nfa, seed.items, mark, stamp, &set);
        // Start states never accept (a token is at least one byte), so drop
        // accept states from the start set; they cannot be extended anyway.
        var k: usize = 0;
        for (set.items) |s| {
            if (nfa.states.items[s].set != null) {
                set.items[k] = s;
                k += 1;
            }
        }
        set.shrinkRetainingCapacity(k);
        startIds[si] = try intern(a, &keys, &map, &trans, &accept, set.items, nfa, nc, true);
    }

    var work: u32 = 0;
    while (work < keys.items.len) : (work += 1) {
        const key = keys.items[work];
        var c: u16 = 0;
        while (c < nc) : (c += 1) {
            const byte = classes.rep[c];
            seed.clearRetainingCapacity();
            for (key) |s| {
                const st = nfa.states.items[s];
                if (st.set) |b| {
                    if (b.has(byte)) try seed.append(a, st.out);
                }
            }
            if (seed.items.len == 0) continue;
            stamp += 1;
            try closure(a, nfa, seed.items, mark, stamp, &set);
            const id = try intern(a, &keys, &map, &trans, &accept, set.items, nfa, nc, false);
            trans.items[work * nc + c] = id;
        }
    }

    return .{
        .trans = trans.items,
        .accept = accept.items,
        .starts = startIds,
        .numStates = @intCast(keys.items.len),
    };
}

const SliceContext = struct {
    pub fn hash(_: SliceContext, k: []const u32) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(k));
    }
    pub fn eql(_: SliceContext, x: []const u32, y: []const u32) bool {
        return std.mem.eql(u32, x, y);
    }
};

fn intern(
    a: Allocator,
    keys: *std.ArrayListUnmanaged([]const u32),
    map: *std.HashMapUnmanaged([]const u32, u32, SliceContext, 80),
    trans: *std.ArrayListUnmanaged(u32),
    accept: *std.ArrayListUnmanaged(u32),
    set: []const u32,
    nfa: *const Nfa,
    nc: u16,
    isStart: bool,
) Error!u32 {
    // Start states are kept distinct from equal non-start sets only through
    // their (non-accepting) content; a start set never contains accept states.
    _ = isStart;
    if (map.get(set)) |id| return id;
    const key = try a.dupe(u32, set);
    const id: u32 = @intCast(keys.items.len);
    try keys.append(a, key);
    try map.put(a, key, id);
    try trans.appendNTimes(a, none, nc);
    var acc: u32 = none;
    for (key) |s| {
        const r = nfa.states.items[s].accept;
        if (r != none and (acc == none or r < acc)) acc = r;
    }
    try accept.append(a, acc);
    return id;
}

/// Moore partition refinement; states are then renumbered in breadth-first
/// order from the start states so the result is canonical.
fn minimize(gpa: Allocator, raw: RawDfa, classes: ByteClasses) Error!Dfa {
    const n = raw.numStates;
    const nc = classes.count;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Initial partition: by accepting rule.
    var block = try a.alloc(u32, n);
    {
        var byAccept: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        var next: u32 = 0;
        for (0..n) |s| {
            const gop = try byAccept.getOrPut(a, raw.accept[s]);
            if (!gop.found_existing) {
                gop.value_ptr.* = next;
                next += 1;
            }
            block[s] = gop.value_ptr.*;
        }
    }
    var numBlocks: u32 = blk: {
        var m: u32 = 0;
        for (block) |b| m = @max(m, b + 1);
        break :blk m;
    };

    const sig = try a.alloc(u32, nc + 1);
    var newBlock = try a.alloc(u32, n);
    while (true) {
        var map: std.HashMapUnmanaged([]const u32, u32, SliceContext, 80) = .empty;
        var next: u32 = 0;
        for (0..n) |s| {
            sig[0] = block[s];
            for (0..nc) |c| {
                const t = raw.trans[s * nc + c];
                sig[c + 1] = if (t == none) none else block[t];
            }
            const gop = try map.getOrPut(a, sig);
            if (!gop.found_existing) {
                gop.key_ptr.* = try a.dupe(u32, sig);
                gop.value_ptr.* = next;
                next += 1;
            }
            newBlock[s] = gop.value_ptr.*;
        }
        const stable = next == numBlocks;
        std.mem.swap([]u32, &block, &newBlock);
        numBlocks = next;
        if (stable) break;
    }

    // Representative raw state per block, and BFS renumbering from the starts.
    const repOf = try a.alloc(u32, numBlocks);
    @memset(repOf, none);
    for (0..n) |s| {
        if (repOf[block[s]] == none) repOf[block[s]] = @intCast(s);
    }
    const order = try a.alloc(u32, numBlocks);
    @memset(order, none);
    var queue: std.ArrayListUnmanaged(u32) = .empty;
    for (raw.starts) |s| {
        const b = block[s];
        if (order[b] == none) {
            order[b] = @intCast(queue.items.len);
            try queue.append(a, b);
        }
    }
    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const b = queue.items[qi];
        const r = repOf[b];
        for (0..nc) |c| {
            const t = raw.trans[r * nc + c];
            if (t == none) continue;
            const tb = block[t];
            if (order[tb] == none) {
                order[tb] = @intCast(queue.items.len);
                try queue.append(a, tb);
            }
        }
    }

    const m: u32 = @intCast(queue.items.len);
    const trans = try gpa.alloc(u32, m * nc);
    const accept = try gpa.alloc(u32, m);
    const starts = try gpa.alloc(u32, raw.starts.len);
    for (queue.items, 0..) |b, i| {
        const r = repOf[b];
        accept[i] = raw.accept[r];
        for (0..nc) |c| {
            const t = raw.trans[r * nc + c];
            trans[i * nc + c] = if (t == none) none else order[block[t]];
        }
    }
    for (raw.starts, 0..) |s, i| starts[i] = order[block[s]];

    return .{ .classes = classes, .trans = trans, .accept = accept, .starts = starts, .numStates = m };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn buildFrom(arena: Allocator, pats: []const []const u8, starts: []const []const u32) !Dfa {
    var nodes = try arena.alloc(*const Node, pats.len);
    for (pats, 0..) |p, i| {
        var d: regex.Diagnostic = .{};
        const pat = try regex.parse(arena, p, &d);
        nodes[i] = try pat.full(arena);
    }
    return build(arena, .{ .patterns = nodes, .starts = starts });
}

test "automaton: byte classes" {
    const sets = [_]ByteSet{ ByteSet.range('a', 'z'), ByteSet.range('0', '9'), ByteSet.single('x') };
    const bc = ByteClasses.compute(&sets);
    try testing.expectEqual(@as(u16, 4), bc.count);
    try testing.expect(bc.classOf['a'] == bc.classOf['q']);
    try testing.expect(bc.classOf['a'] != bc.classOf['x']);
    try testing.expect(bc.classOf['0'] == bc.classOf['9']);
    try testing.expect(bc.classOf['-'] == bc.classOf[0]);
}

test "automaton: longest match and rule priority" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const all = [_]u32{ 0, 1, 2, 3 };
    const dfa = try buildFrom(a, &.{ "\"if\"", "[a-z]+", "'='", "\"==\"" }, &.{&all});
    try testing.expectEqual(@as(u32, 0), dfa.longestMatch(0, "if").?.rule);
    try testing.expectEqual(@as(u32, 1), dfa.longestMatch(0, "iff").?.rule);
    try testing.expectEqual(@as(usize, 3), dfa.longestMatch(0, "iff").?.len);
    try testing.expectEqual(@as(u32, 3), dfa.longestMatch(0, "==").?.rule);
    try testing.expectEqual(@as(u32, 2), dfa.longestMatch(0, "=x").?.rule);
    try testing.expect(dfa.longestMatch(0, "+") == null);
}

test "automaton: start configurations select live rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const normal = [_]u32{ 0, 2 };
    const pat = [_]u32{ 1, 2 };
    const dfa = try buildFrom(a, &.{ "[0-9]+ ('.' [0-9]+)?", "[0-9]+", "'.'" }, &.{ &normal, &pat });
    try testing.expectEqual(@as(usize, 3), dfa.longestMatch(0, "1.5").?.len);
    try testing.expectEqual(@as(usize, 1), dfa.longestMatch(1, "1.5").?.len);
    try testing.expectEqual(@as(u32, 1), dfa.longestMatch(1, "1.5").?.rule);
}

test "automaton: minimization merges equivalent states" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const all = [_]u32{0};
    // (a|b)* c written redundantly: the minimal DFA has 2 states.
    const dfa = try buildFrom(a, &.{"('a' | 'b' | 'a' 'a')* 'c'"}, &.{&all});
    try testing.expectEqual(@as(u32, 2), dfa.numStates);
    // [0-9]{2,4}: start, 1, 2(acc), 3(acc), 4(acc, no out) = 5 states.
    const rep = try buildFrom(a, &.{"[0-9]{2,4}"}, &.{&all});
    try testing.expectEqual(@as(u32, 5), rep.numStates);
}

test "automaton: deterministic output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const all = [_]u32{ 0, 1, 2 };
    const d1 = try buildFrom(a, &.{ "'\"' ([^\"\\n] | '\"\"')* '\"'", "[a-z]+", "." }, &.{&all});
    const d2 = try buildFrom(a, &.{ "'\"' ([^\"\\n] | '\"\"')* '\"'", "[a-z]+", "." }, &.{&all});
    try testing.expectEqualSlices(u32, d1.trans, d2.trans);
    try testing.expectEqualSlices(u32, d1.accept, d2.accept);
}

// -----------------------------------------------------------------------------
// Differential property test: random regexes x random strings, DFA vs the
// backtracking reference matcher in regex.zig.
// -----------------------------------------------------------------------------

const Gen = struct {
    rng: std.Random,
    arena: Allocator,

    fn node(self: *Gen, n: Node) !*const Node {
        const p = try self.arena.create(Node);
        p.* = n;
        return p;
    }

    fn set(self: *Gen) ByteSet {
        var s: ByteSet = .{};
        const alphabet = "abc";
        switch (self.rng.uintLessThan(u8, 4)) {
            0, 1 => s.add(alphabet[self.rng.uintLessThan(usize, 3)]),
            2 => {
                s.add(alphabet[self.rng.uintLessThan(usize, 3)]);
                s.add(alphabet[self.rng.uintLessThan(usize, 3)]);
            },
            else => s = ByteSet.full.intersect(ByteSet.single(alphabet[self.rng.uintLessThan(usize, 3)]).invert()),
        }
        return s;
    }

    fn gen(self: *Gen, depth: u32) !*const Node {
        const pick = if (depth >= 4) 0 else self.rng.uintLessThan(u8, 8);
        switch (pick) {
            0, 1, 2 => return self.node(.{ .set = self.set() }),
            3 => {
                const k = 2 + self.rng.uintLessThan(usize, 2);
                const kids = try self.arena.alloc(*const Node, k);
                for (kids) |*kd| kd.* = try self.gen(depth + 1);
                return self.node(.{ .concat = kids });
            },
            4 => {
                const k = 2 + self.rng.uintLessThan(usize, 2);
                const kids = try self.arena.alloc(*const Node, k);
                for (kids) |*kd| kd.* = try self.gen(depth + 1);
                return self.node(.{ .alt = kids });
            },
            5 => return self.node(.{ .repeat = .{ .sub = try self.gen(depth + 1), .min = 0, .max = null } }),
            6 => {
                const lo = self.rng.uintLessThan(u32, 3);
                const hi: ?u32 = if (self.rng.boolean()) null else lo + self.rng.uintLessThan(u32, 3);
                return self.node(.{ .repeat = .{ .sub = try self.gen(depth + 1), .min = lo, .max = if (hi != null and hi.? == 0) 1 else hi } });
            },
            else => return self.node(.empty),
        }
    }
};

/// Reference: longest match of the rule set at position 0 with rule-order
/// tie-break, using the backtracking matcher.
fn refLongest(pats: []const *const Node, live: []const u32, input: []const u8) ?Match {
    var best: ?Match = null;
    for (live) |r| {
        const ends = regex.matchEnds(pats[r], input, 0) & ~@as(u64, 1); // non-empty matches only
        if (ends == 0) continue;
        const len: usize = 63 - @clz(ends);
        if (best == null or len > best.?.len or (len == best.?.len and r < best.?.rule)) best = .{ .rule = r, .len = len };
    }
    return best;
}

test "automaton: differential property test vs backtracking matcher" {
    var prng = std.Random.DefaultPrng.init(0x5eed_1e8e);
    const rng = prng.random();
    var cases: usize = 0;
    var round: usize = 0;
    while (round < 400) : (round += 1) {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var g: Gen = .{ .rng = rng, .arena = a };
        const nr = 1 + rng.uintLessThan(usize, 4);
        const pats = try a.alloc(*const Node, nr);
        for (pats) |*p| p.* = try g.gen(0);
        const all = try a.alloc(u32, nr);
        for (all, 0..) |*x, i| x.* = @intCast(i);
        // Second configuration: every other rule.
        var some: std.ArrayListUnmanaged(u32) = .empty;
        for (all) |r| if (r % 2 == 0) try some.append(a, r);
        const starts = [_][]const u32{ all, some.items };
        var dfa = try build(testing.allocator, .{ .patterns = pats, .starts = &starts });
        defer dfa.deinit(testing.allocator);

        var t: usize = 0;
        while (t < 60) : (t += 1) {
            var buf: [12]u8 = undefined;
            const len = rng.uintLessThan(usize, buf.len + 1);
            for (buf[0..len]) |*ch| ch.* = "abcd"[rng.uintLessThan(usize, 4)];
            const input = buf[0..len];
            for (starts, 0..) |live, si| {
                const want = refLongest(pats, live, input);
                const got = dfa.longestMatch(@intCast(si), input);
                if ((want == null) != (got == null) or
                    (want != null and (want.?.rule != got.?.rule or want.?.len != got.?.len)))
                {
                    std.debug.print("mismatch on input '{s}' config {d}\n", .{ input, si });
                    return error.TestUnexpectedResult;
                }
                cases += 1;
            }
        }
    }
    try testing.expect(cases == 400 * 60 * 2);
}
