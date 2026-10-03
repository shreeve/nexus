//! Lexer code generation: turns a grammar.LexerSpec into the Zig source of
//! `TokenCat`, `Token`, and the `Lexer`/`BaseLexer` struct.
//!
//! Every rule pattern is compiled (regex.zig) into one minimized DFA
//! (automaton.zig) with a start state per guard configuration, and emitted
//! as a direct-coded scanner: a labeled `switch` with one prong per DFA
//! state that jumps between states with `continue`. Fast paths are derived
//! from the automaton, not from token names: self-loops become tight loops
//! (a range test, a comptime byte table, or a SIMD scan for `[^x]*`-style
//! runs), and transitions into final states return the token in place.
//!
//! Token semantics (per `matchRules` call):
//!   1. Spaces and tabs are skipped; their count (saturating at 255) is the
//!      token's `pre`.
//!   2. Zero-width rules (empty pattern, guards only) are tried in order.
//!   3. At end of input the `eof` token is returned.
//!   4. The longest match among the rules whose guards hold wins; ties go
//!      to the earlier rule. No match: one byte becomes an `err` token.
//!   5. The `after` assignments run, then the rule's actions; `hold`,
//!      `rewind(n)` and trailing context `r1 / r2` shorten the token; a
//!      `skip` action discards it (its bytes count toward `pre`).

const std = @import("std");
const diag = @import("../diag.zig");
const grammar = @import("../grammar.zig");
const LexerSpec = grammar.LexerSpec;
const LexerRule = grammar.LexerRule;
const Guard = grammar.Guard;
const Action = grammar.Action;
const Allocator = std.mem.Allocator;
const regex = @import("regex.zig");
const automaton = @import("automaton.zig");
const ByteSet = regex.ByteSet;

test {
    _ = regex;
    _ = automaton;
}

/// Most distinct guard conditions over consuming rules (2^n start configurations).
const maxGuardAtoms = 10;

/// A self-loop that excludes at most this many bytes is scanned with SIMD.
const maxSimdStops = 3;

/// The implicit whitespace, skipped before every token into `pre`.
const blanks: ByteSet = blk: {
    var s: ByteSet = .{};
    s.add(' ');
    s.add('\t');
    break :blk s;
};

/// A transition class this wide into a looping state is tested before the
/// state's switch.
const hotClassMin = 16;

pub const LexerGenerator = struct {
    allocator: Allocator,
    spec: *const LexerSpec,
    output: std.Io.Writer.Allocating,
    /// Where emission goes (the output, or a scratch buffer).
    w: *std.Io.Writer = undefined,
    arena: std.heap.ArenaAllocator,
    simdUsed: bool = false,

    // Analysis results
    /// Spec indices of the rules in the DFA (consuming rules), in priority order.
    consuming: []u32 = &.{},
    atoms: []Atom = &.{},
    /// Start state for each configuration mask (2^atoms.len entries).
    startOfMask: []u32 = &.{},
    dfa: automaton.Dfa = undefined,
    /// Token end for each consuming rule.
    ends: []TokenEnd = &.{},
    /// Byte tables emitted as `cls<N>` constants.
    tables: std.ArrayList(ByteSet) = .empty,
    /// States whose accepting rule must be saved before leaving them.
    saves: []bool = &.{},

    const Atom = struct {
        variable: []const u8,
        op: Guard.Op,
        value: i32,

        fn eql(x: Atom, y: Atom) bool {
            return std.mem.eql(u8, x.variable, y.variable) and x.op == y.op and x.value == y.value;
        }
    };

    /// Where a consuming rule's token ends, relative to its match.
    const TokenEnd = union(enum) {
        whole,
        /// Zero-width at the match start (`hold`).
        start,
        /// `start + n` (`rewind(n)`, or trailing context after a fixed-length head).
        fromStart: u32,
        /// `matchEnd - n` (trailing context of fixed length n).
        fromEnd: u32,
    };

    pub fn init(allocator: Allocator, spec: *const LexerSpec) LexerGenerator {
        return .{
            .allocator = allocator,
            .spec = spec,
            .output = .init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *LexerGenerator) void {
        self.output.deinit();
        self.arena.deinit();
    }

    fn write(self: *LexerGenerator, s: []const u8) !void {
        try self.w.writeAll(s);
    }

    fn print(self: *LexerGenerator, comptime fmt: []const u8, args: anytype) !void {
        try self.w.print(fmt, args);
    }

    fn fail(self: *LexerGenerator, rule: *const LexerRule, offset: usize, comptime fmt: []const u8, args: anytype) error{LexerGenerationError} {
        diag.errLine(self.spec.fileName, rule.line, rule.col + @as(u32, @intCast(offset)), fmt, args);
        return error.LexerGenerationError;
    }

    /// The lexer's declarations (TokenCat, Token, BaseLexer) without the
    /// file header and imports, for composing into a generated parser module.
    pub fn generateDecls(self: *LexerGenerator) ![]const u8 {
        self.w = &self.output.writer;
        try self.analyze();
        try self.emitTokenCat();
        try self.emitTokenStruct();
        try self.emitLexerStruct();
        return self.output.toOwnedSlice();
    }

    // =========================================================================
    // Analysis
    // =========================================================================

    fn analyze(self: *LexerGenerator) !void {
        const a = self.arena.allocator();
        const rules = self.spec.rules.items;

        var consuming: std.ArrayList(u32) = .empty;
        var ends: std.ArrayList(TokenEnd) = .empty;
        var fulls: std.ArrayList(*const regex.Node) = .empty;
        for (rules, 0..) |*r, i| {
            if (r.pattern.len == 0) {
                try self.checkZeroWidth(r);
                continue;
            }
            var d: regex.Diagnostic = .{};
            const p = regex.parse(a, r.pattern, &d) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidPattern => return self.fail(r, d.offset, "{s}", .{d.message}),
            };
            const full = try p.full(a);
            try ends.append(a, try self.checkConsuming(r, p, full));
            try consuming.append(a, @intCast(i));
            try fulls.append(a, full);
        }
        self.consuming = consuming.items;
        self.ends = ends.items;
        try self.checkZeroWidthLoops();

        // Guard atoms of consuming rules, and the live rules per configuration.
        var atoms: std.ArrayList(Atom) = .empty;
        for (self.consuming) |ri| {
            for (rules[ri].guards) |g| {
                const at = atomOf(g);
                for (atoms.items) |x| {
                    if (x.eql(at)) break;
                } else {
                    if (atoms.items.len == maxGuardAtoms) {
                        return self.fail(&rules[ri], 0, "the rules test more than {d} distinct guard conditions (this rule adds one more); at most {d} are supported", .{ maxGuardAtoms, maxGuardAtoms });
                    }
                    try atoms.append(a, at);
                }
            }
        }
        self.atoms = atoms.items;

        // The live rules of each realizable configuration; the others (m == 1
        // and m == 2 both true, m == 300) get no start state.
        const realizable = try self.realizableMasks();
        const masks = realizable.len;
        var liveSets: std.ArrayList([]const u32) = .empty;
        self.startOfMask = try a.alloc(u32, masks);
        var live: std.ArrayList(u32) = .empty;
        for (0..masks) |mask| {
            if (!realizable[mask]) {
                self.startOfMask[mask] = automaton.none;
                continue;
            }
            live.clearRetainingCapacity();
            for (self.consuming, 0..) |ri, k| {
                if (self.guardsHold(rules[ri].guards, mask)) try live.append(a, @intCast(k));
            }
            const idx = for (liveSets.items, 0..) |ls, j| {
                if (std.mem.eql(u32, ls, live.items)) break j;
            } else blk: {
                try liveSets.append(a, try a.dupe(u32, live.items));
                break :blk liveSets.items.len - 1;
            };
            self.startOfMask[mask] = @intCast(idx);
        }

        self.dfa = try self.buildDfa(fulls.items, liveSets.items);
        if (self.dfa.numStates > std.math.maxInt(u16)) {
            return self.fail(&rules[self.consuming[0]], 0, "the lexer DFA has {d} states; at most 65535 are supported", .{self.dfa.numStates});
        }
        for (self.startOfMask) |*s| {
            if (s.* != automaton.none) s.* = self.dfa.starts[s.*];
        }

        // A rule whose pattern cannot win anywhere is reported: every rule
        // must be able to produce its token in some configuration.
        try self.checkReachable(fulls.items);

        self.saves = try a.alloc(bool, self.dfa.numStates);
        for (0..self.dfa.numStates) |s| self.saves[s] = self.needsSave(@intCast(s));
    }

    /// The minimized DFA of `patterns`, with a start state per live set.
    /// The lexer skips blanks before it runs the DFA, so the start states
    /// have no transition on them: a match that needs a leading blank is
    /// not in the automaton, and the dead-rule check sees exactly what
    /// can win. A size limit is reported at the first consuming rule.
    fn buildDfa(self: *LexerGenerator, patterns: []const *const regex.Node, starts: []const []const u32) !automaton.Dfa {
        const first = &self.spec.rules.items[self.consuming[0]];
        return automaton.build(self.arena.allocator(), .{ .patterns = patterns, .starts = starts, .startSkip = blanks }) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NfaTooLarge => return self.fail(first, 0, "the lexer NFA has more than {d} states (bounded repeats expand, and nesting multiplies them; reduce {{n,m}} counts)", .{automaton.maxNfaStates}),
            error.DfaTooLarge => return self.fail(first, 0, "the lexer DFA is too large: subset construction passed {d} states, and at most 65535 are supported", .{automaton.maxRawDfaStates}),
        };
    }

    fn atomOf(g: Guard) Atom {
        return switch (g.op) {
            .truthy => .{ .variable = g.variable, .op = .ne, .value = 0 },
            else => .{ .variable = g.variable, .op = g.op, .value = g.value },
        };
    }

    fn atomIndex(self: *const LexerGenerator, at: Atom) usize {
        for (self.atoms, 0..) |x, i| if (x.eql(at)) return i;
        unreachable;
    }

    /// The configurations the variables can be in: entry `mask` is true when
    /// some values make exactly the atoms in `mask` true. Each variable is
    /// tried over its whole range (`pre` 0..255, a state variable -128..127).
    fn realizableMasks(self: *LexerGenerator) ![]bool {
        const a = self.arena.allocator();
        const masks = @as(usize, 1) << @intCast(self.atoms.len);
        const out = try a.alloc(bool, masks);
        @memset(out, true);
        const seen = try a.alloc(bool, masks);
        for (self.atoms, 0..) |v, i| {
            const counted = for (self.atoms[0..i]) |x| {
                if (std.mem.eql(u8, x.variable, v.variable)) break true;
            } else false;
            if (counted) continue;
            // The atoms on this variable, and the outcomes its values give them.
            var own: usize = 0;
            for (self.atoms, 0..) |at, j| {
                if (std.mem.eql(u8, at.variable, v.variable)) own |= @as(usize, 1) << @intCast(j);
            }
            @memset(seen, false);
            const lo, const hi = range(v.variable);
            var x = lo;
            while (x <= hi) : (x += 1) {
                var bits: usize = 0;
                for (self.atoms, 0..) |at, j| {
                    if ((own >> @intCast(j)) & 1 != 0 and guardHoldsAt(.{ .variable = at.variable, .op = at.op, .value = at.value }, x)) bits |= @as(usize, 1) << @intCast(j);
                }
                seen[bits] = true;
            }
            for (out, 0..) |*ok, mask| {
                if (!seen[mask & own]) ok.* = false;
            }
        }
        return out;
    }

    /// The values a guarded variable takes: `pre` is a u8, a state variable an i8.
    fn range(variable: []const u8) struct { i32, i32 } {
        return if (std.mem.eql(u8, variable, "pre")) .{ 0, 255 } else .{ -128, 127 };
    }

    /// Can all of `guards` hold at once?
    fn satisfiable(guards: []const Guard) bool {
        for (guards) |g| {
            const lo, const hi = range(g.variable);
            var x = lo;
            while (x <= hi) : (x += 1) {
                if (holdsAll(guards, g.variable, x)) break;
            } else return false;
        }
        return true;
    }

    /// The start state of the first realizable configuration.
    fn firstStart(self: *const LexerGenerator) u32 {
        for (self.startOfMask) |s| if (s != automaton.none) return s;
        unreachable;
    }

    fn guardsHold(self: *const LexerGenerator, guards: []const Guard, mask: usize) bool {
        for (guards) |g| {
            const bit = (mask >> @intCast(self.atomIndex(atomOf(g)))) & 1 != 0;
            if (bit == g.negated) return false;
        }
        return true;
    }

    /// Does an action assign a state variable that one of the guards tests?
    fn changesGuardedState(r: *const LexerRule) bool {
        for (r.actions) |act| {
            const v = act.variable orelse continue;
            if (std.mem.eql(u8, v, "pre")) continue;
            for (r.guards) |g| if (std.mem.eql(u8, g.variable, v)) return true;
        }
        return false;
    }

    /// Rules that return a token without advancing: zero-width rules (no
    /// pattern) and consuming rules that end at their start (`hold`,
    /// `rewind(0)`, an empty head before `/`). The lexer would return such
    /// tokens forever at one position if they could fire one after another
    /// without end. A rule that does so fires at (rule, value) steps that
    /// repeat, for every variable its guards test, so `pruneLoops` keeps
    /// only the rules on such cycles; whatever survives is an error. Each
    /// variable is followed on its own, so the check errs only on the safe
    /// side.
    fn checkZeroWidthLoops(self: *LexerGenerator) !void {
        const a = self.arena.allocator();
        var nodes: std.ArrayList(*const LexerRule) = .empty;
        for (self.spec.rules.items, 0..) |*r, i| {
            if (r.pattern.len == 0) {
                try nodes.append(a, r);
                continue;
            }
            const k = std.mem.findScalar(u32, self.consuming, @intCast(i)) orelse continue;
            const e = self.ends[k];
            if (e == .start or (e == .fromStart and e.fromStart == 0)) try nodes.append(a, r);
        }
        const n = nodes.items.len;
        const alive = try a.alloc(bool, n);
        @memset(alive, true);
        try self.pruneLoops(nodes.items, alive);
        const first = std.mem.findScalar(bool, alive, true) orelse return;

        // A rule that loops on its own gets the more precise message.
        const one = try a.alloc(bool, n);
        for (nodes.items, 0..) |r, i| {
            if (!alive[i]) continue;
            @memset(one, false);
            one[i] = true;
            try self.pruneLoops(nodes.items, one);
            if (!one[i]) continue;
            if (!changesGuardedState(r)) {
                const again = if (r.pattern.len == 0 and r.hold) " (a held rule without a pattern sees the same whitespace again)" else "";
                return self.fail(r, 0, "this zero-width rule would match forever: it must assign a state variable its guards test, or need whitespace (a guard false at pre = 0){s}", .{again});
            }
            return self.fail(r, 0, "this zero-width rule would match forever: after its actions its guards still hold; an action must make one of them false", .{});
        }
        var lines: std.Io.Writer.Allocating = .init(a);
        for (nodes.items, alive) |r, live| {
            if (!live) continue;
            if (lines.written().len > 0) try lines.writer.writeAll(", ");
            try lines.writer.print("{d}", .{r.line});
        }
        return self.fail(nodes.items[first], 0, "zero-width rules could fire one after another forever at one position (the rules on lines {s}): make an action set a variable so that the next one's guards fail", .{lines.written()});
    }

    /// Narrow `alive` to the rules that lie on a cycle of steps among alive
    /// rules, for every variable some rule's guards test.
    fn pruneLoops(self: *LexerGenerator, nodes: []const *const LexerRule, alive: []bool) !void {
        const a = self.arena.allocator();
        var vars: std.ArrayList([]const u8) = .empty;
        for (nodes) |r| for (r.guards) |g| {
            for (vars.items) |v| {
                if (std.mem.eql(u8, v, g.variable)) break;
            } else try vars.append(a, g.variable);
        };
        var changed = true;
        while (changed) {
            changed = false;
            for (vars.items) |v| {
                const keep = try self.cyclicRules(nodes, alive, v);
                for (alive, keep) |*live, k| {
                    if (live.* and !k) {
                        live.* = false;
                        changed = true;
                    }
                }
            }
        }
    }

    /// The alive rules on a cycle of steps (r, x) -> (s, y): r's guards on
    /// `variable` hold at x, firing r leaves it at y, and s's guards hold
    /// at y. A step is on a cycle when its strongly connected component has
    /// another step or it steps to itself.
    fn cyclicRules(self: *LexerGenerator, nodes: []const *const LexerRule, alive: []const bool, variable: []const u8) ![]bool {
        const a = self.arena.allocator();
        const lo, const hi = range(variable);
        const w: usize = @intCast(hi - lo + 1);
        const n = nodes.len;
        // Step (i, x) is node i * w + (x - lo); node `any` stands for every
        // value (after a count), with an edge to each step.
        const any: u32 = @intCast(n * w);
        const total = any + 1;
        const live = try a.alloc(bool, total);
        for (0..n) |i| for (0..w) |k| {
            live[i * w + k] = alive[i] and holdsAll(nodes[i].guards, variable, lo + @as(i32, @intCast(k)));
        };
        live[any] = true;

        // Successors of node u: succ[start[u]..start[u + 1]].
        const start = try a.alloc(u32, total + 1);
        var succ: std.ArrayList(u32) = .empty;
        for (0..total) |u| {
            start[u] = @intCast(succ.items.len);
            if (!live[u]) continue;
            if (u == any) {
                for (0..any) |t| if (live[t]) try succ.append(a, @intCast(t));
                continue;
            }
            const y = self.step(nodes[u / w], variable, lo + @as(i32, @intCast(u % w))) orelse {
                try succ.append(a, any);
                continue;
            };
            for (0..n) |j| {
                const t = j * w + @as(usize, @intCast(y - lo));
                if (live[t]) try succ.append(a, @intCast(t));
            }
        }
        start[total] = @intCast(succ.items.len);

        // Tarjan's strongly connected components, without recursion.
        const unvisited = std.math.maxInt(u32);
        const index = try a.alloc(u32, total);
        const low = try a.alloc(u32, total);
        const onStack = try a.alloc(bool, total);
        const onCycle = try a.alloc(bool, total);
        @memset(index, unvisited);
        @memset(onStack, false);
        @memset(onCycle, false);
        var stack: std.ArrayList(u32) = .empty;
        const Frame = struct { u: u32, next: u32 };
        var calls: std.ArrayList(Frame) = .empty;
        var counter: u32 = 0;
        for (0..total) |root| {
            if (!live[root] or index[root] != unvisited) continue;
            var visit: ?u32 = @intCast(root);
            while (true) {
                if (visit) |v| {
                    index[v] = counter;
                    low[v] = counter;
                    counter += 1;
                    try stack.append(a, v);
                    onStack[v] = true;
                    try calls.append(a, .{ .u = v, .next = start[v] });
                    visit = null;
                }
                const f = &calls.items[calls.items.len - 1];
                const u = f.u;
                if (f.next < start[u + 1]) {
                    const v = succ.items[f.next];
                    f.next += 1;
                    if (index[v] == unvisited) {
                        visit = v;
                    } else if (onStack[v]) {
                        low[u] = @min(low[u], index[v]);
                    }
                    continue;
                }
                _ = calls.pop();
                if (low[u] == index[u]) {
                    const top = stack.items.len;
                    const at = std.mem.findScalarLast(u32, stack.items, u).?;
                    const selfLoop = std.mem.findScalar(u32, succ.items[start[u]..start[u + 1]], u) != null;
                    for (stack.items[at..top]) |s| {
                        onStack[s] = false;
                        onCycle[s] = top - at > 1 or selfLoop;
                    }
                    stack.shrinkRetainingCapacity(at);
                }
                if (calls.items.len == 0) break;
                const p = calls.items[calls.items.len - 1].u;
                low[p] = @min(low[p], low[u]);
            }
        }

        const keep = try a.alloc(bool, n);
        for (keep, 0..) |*k, i| k.* = std.mem.findScalar(bool, onCycle[i * w ..][0..w], true) != null;
        return keep;
    }

    /// The value `variable` has for the next token after rule `r` fired
    /// with it at `x`; null when any value is possible (a count). `pre` is
    /// counted again from the next token's blanks, so it stays only after a
    /// held rule without a pattern (the blanks are scanned again) and is 0
    /// after anything else.
    fn step(self: *const LexerGenerator, r: *const LexerRule, variable: []const u8, x: i32) ?i32 {
        if (std.mem.eql(u8, variable, "pre")) return if (r.pattern.len == 0 and r.hold) x else 0;
        return self.effect(r, variable, x);
    }

    /// The value of `variable` after rule `r` fires with it at `x` (null:
    /// unknown, a count).
    fn effect(self: *const LexerGenerator, r: *const LexerRule, variable: []const u8, x: i32) ?i32 {
        var v = x;
        if (r.pattern.len != 0) for (self.spec.afterActions.items) |act| {
            if (std.mem.eql(u8, act.variable.?, variable) and afterApplies(act, r.actions)) v = act.value.?;
        };
        for (r.actions) |act| {
            const name = act.variable orelse continue;
            if (!std.mem.eql(u8, name, variable)) continue;
            switch (act.kind) {
                .set => v = act.value.?,
                .inc => v = @min(v + 1, 127),
                .dec => v = @max(v - 1, -128),
                .counted => return null,
            }
        }
        return v;
    }

    fn holdsAll(guards: []const Guard, variable: []const u8, x: i32) bool {
        for (guards) |g| {
            if (std.mem.eql(u8, g.variable, variable) and !guardHoldsAt(g, x)) return false;
        }
        return true;
    }

    fn guardHoldsAt(g: Guard, x: i32) bool {
        const holds = switch (g.op) {
            .eq => x == g.value,
            .ne => x != g.value,
            .gt => x > g.value,
            .lt => x < g.value,
            .ge => x >= g.value,
            .le => x <= g.value,
            .truthy => x != 0,
        };
        return holds != g.negated;
    }

    fn hasCounted(r: *const LexerRule) bool {
        for (r.actions) |act| if (act.kind == .counted) return true;
        return false;
    }

    fn checkZeroWidth(self: *LexerGenerator, r: *const LexerRule) !void {
        if (r.rewind != null) return self.fail(r, 0, "rewind(n) needs a pattern; a rule without one is already zero-width", .{});
        if (r.isSkip) return self.fail(r, 0, "a zero-width rule cannot skip", .{});
        if (r.hold and hasCounted(r)) return self.fail(r, 0, "a held rule consumes nothing, so counted() has nothing to count", .{});
        if (!satisfiable(r.guards)) return self.fail(r, 0, "this rule can never match: its guards are never all true together", .{});
    }

    fn checkConsuming(self: *LexerGenerator, r: *const LexerRule, p: regex.Pattern, full: *const regex.Node) !TokenEnd {
        if (regex.firstSet(full).subsetOf(blanks)) {
            return self.fail(r, 0, "this pattern can only start with a space or tab, which the lexer always consumes first as leading whitespace (pre); use a zero-width rule guarded by pre instead", .{});
        }
        if (p.trail == null and regex.nullable(p.main)) {
            return self.fail(r, 0, "this pattern matches the empty string; a token must consume at least one byte (use + rather than *, or a zero-width rule)", .{});
        }
        var end: TokenEnd = .whole;
        if (p.trail) |t| {
            if (r.rewind != null) return self.fail(r, 0, "use either trailing context '/' or rewind(n), not both", .{});
            if (regex.nullable(p.main) and regex.fixedLen(p.main) != 0) {
                return self.fail(r, 0, "the token before '/' can be empty; write it so it always consumes a byte (or use hold for a zero-width token)", .{});
            }
            if (regex.fixedLen(p.main)) |k| {
                end = if (k == 0) .start else .{ .fromStart = k };
            } else if (regex.fixedLen(t)) |k| {
                end = .{ .fromEnd = k };
            } else {
                return self.fail(r, 0, "trailing context needs a fixed-length token or a fixed-length context after '/'", .{});
            }
        }
        if (r.rewind) |n| {
            const minLen = regex.minLen(full);
            if (n > minLen) return self.fail(r, 0, "rewind({d}) exceeds the shortest match of the pattern ({d} bytes)", .{ n, minLen });
            end = if (n == 0) .start else .{ .fromStart = n };
        }
        if (r.hold) end = .start;
        if (hasCounted(r)) return self.fail(r, 0, "counted() belongs on a zero-width rule (no pattern), where it counts the bytes after the leading whitespace", .{});
        if (r.isSkip and (end == .start or (end == .fromStart and end.fromStart == 0))) {
            return self.fail(r, 0, "a zero-width token cannot be skipped", .{});
        }
        return end;
    }

    /// Every consuming rule must win for some input in some configuration;
    /// a rule shadowed everywhere is dead code in the grammar.
    fn checkReachable(self: *LexerGenerator, fulls: []const *const regex.Node) !void {
        const a = self.arena.allocator();
        const winners = try a.alloc(bool, self.consuming.len);
        @memset(winners, false);
        for (self.dfa.accept) |acc| {
            if (acc != automaton.none) winners[acc] = true;
        }
        for (winners, 0..) |w, k| {
            if (w) continue;
            const r = &self.spec.rules.items[self.consuming[k]];
            // Name the rule that wins a shortest text this one matches, in a
            // configuration where this one is live.
            const mask = for (self.startOfMask, 0..) |s, m| {
                if (s != automaton.none and self.guardsHold(r.guards, m)) break m;
            } else return self.fail(r, 0, "this rule can never match: its guards are never all true together", .{});
            var single = try self.buildDfa(fulls[k .. k + 1], &.{&[_]u32{0}});
            const text = (try single.shortestAccepted(a, 0)).?;
            const m = self.dfa.longestMatchFrom(self.startOfMask[mask], text).?;
            const winner = &self.spec.rules.items[self.consuming[m.rule]];
            return self.fail(r, 0, "this rule can never match: on every text it matches, an earlier rule matches as much (e.g. \"{f}\" goes to the rule on line {d}; longest match, ties to the earlier rule)", .{ std.zig.fmtString(text), winner.line });
        }
    }

    /// An accepting state must record its rule before moving on only if it
    /// can step into a non-accepting state (where scanning may then fail).
    fn needsSave(self: *const LexerGenerator, s: u32) bool {
        if (self.dfa.accept[s] == automaton.none) return false;
        const nc = self.dfa.classes.count;
        for (0..nc) |c| {
            const t = self.dfa.trans[s * nc + c];
            if (t != automaton.none and t != s and self.dfa.accept[t] == automaton.none) return true;
        }
        return false;
    }

    // =========================================================================
    // Emission: types
    // =========================================================================

    fn declaresSkip(self: *const LexerGenerator) bool {
        for (self.spec.tokens.items) |t| if (std.mem.eql(u8, t.name, "skip")) return true;
        return false;
    }

    fn emitTokenCat(self: *LexerGenerator) !void {
        try self.write(
            \\// =============================================================================
            \\// TOKEN CATEGORIES
            \\// =============================================================================
            \\
            \\pub const TokenCat = enum(u8) {
            \\
        );
        for (self.spec.tokens.items) |tok| try self.print("    @\"{s}\",\n", .{tok.name});
        if (!self.declaresSkip()) {
            try self.write(
                \\
                \\    // Built in: the token of `→ skip` rules (returned to the lang Lexer)
                \\    @"skip",
                \\
            );
        }
        try self.write("};\n\n");
    }

    fn emitTokenStruct(self: *LexerGenerator) !void {
        try self.write(
            \\// =============================================================================
            \\// TOKEN STRUCT (8 bytes)
            \\// =============================================================================
            \\
            \\pub const Token = struct {
            \\    pos: u32, // Byte position in source (4 bytes)
            \\    len: u16, // Token length in bytes (2 bytes)
            \\    cat: TokenCat, // Token category (1 byte)
            \\    pre: u8, // Preceding whitespace count (1 byte)
            \\
            \\    comptime {
            \\        std.debug.assert(@sizeOf(Token) == 8);
            \\    }
            \\};
            \\
            \\
        );
    }

    fn emitLexerStruct(self: *LexerGenerator) !void {
        const sname = if (self.spec.langName != null) "BaseLexer" else "Lexer";
        try self.write(
            \\// =============================================================================
            \\// LEXER
            \\// =============================================================================
            \\
            \\
        );
        try self.print("pub const {s} = struct {{\n", .{sname});
        try self.write(
            \\    const Self = @This();
            \\
            \\    source: []const u8,
            \\    pos: u32,
            \\    /// Side channel a lang Lexer wrapper may set per token; the parser
            \\    /// copies it into the shifted leaf's `src.id` and clears it.
            \\    aux: u16 = 0,
            \\
        );
        if (self.spec.states.items.len > 0) try self.write("    // State variables\n");
        for (self.spec.states.items) |s| try self.print("    {s}: i8,\n", .{s.name});

        try self.write(
            \\
            \\    pub fn init(source: []const u8) Self {
            \\        return .{
            \\            .source = source,
            \\            .pos = 0,
            \\
        );
        for (self.spec.states.items) |s| try self.print("            .{s} = {d},\n", .{ s.name, s.initialValue });
        try self.write(
            \\        };
            \\    }
            \\
            \\    /// Get the text slice for a token (zero-copy into source)
            \\    pub fn text(self: *const Self, tok: Token) []const u8 {
            \\        const start: usize = tok.pos;
            \\        const end: usize = @min(start + tok.len, self.source.len);
            \\        if (start >= self.source.len) return "";
            \\        return self.source[start..end];
            \\    }
            \\
            \\    /// Reset lexer to beginning
            \\    pub fn reset(self: *Self) void {
            \\        self.pos = 0;
            \\
        );
        for (self.spec.states.items) |s| try self.print("        self.{s} = {d};\n", .{ s.name, s.initialValue });
        try self.write(
            \\    }
            \\
            \\    /// Get next token
            \\    pub fn next(self: *Self) Token {
            \\        return self.matchRules();
            \\    }
            \\
            \\    /// The token of `cat` from `start` to `end`. A match longer than a
            \\    /// Token can hold (65535 bytes) is an `err` token of that length;
            \\    /// the scan goes on after the whole match.
            \\    inline fn token(cat: TokenCat, pre: u8, start: usize, end: usize) Token {
            \\        if (end - start > std.math.maxInt(u16)) return .{ .cat = .@"err", .pre = pre, .pos = @intCast(start), .len = std.math.maxInt(u16) };
            \\        return .{ .cat = cat, .pre = pre, .pos = @intCast(start), .len = @intCast(end - start) };
            \\    }
            \\
        );

        for (self.spec.codeFunctions.items) |name| {
            const lang = self.spec.langName orelse {
                diag.errLine(self.spec.fileName, 1, 1, "@code = {s} needs @lang (the function is imported from the lang module)", .{name});
                return error.LexerGenerationError;
            };
            try self.print(
                \\
                \\    /// `@code = {s}`: `{s}.{s}(source, pos)` at the current position.
                \\    pub fn {s}(self: *const Self) bool {{
                \\        return lang.{s}(self.source, self.pos);
                \\    }}
                \\
            , .{ name, lang, name, name, name });
        }

        try self.emitMatchRules();
        try self.write("};\n");

        if (self.spec.langName != null) {
            try self.write(
                \\
                \\pub const Lexer = if (@hasDecl(lang, "Lexer")) lang.Lexer else BaseLexer;
                \\
            );
        }
    }

    // =========================================================================
    // Emission: byte tests
    // =========================================================================

    fn byteLit(buf: *[8]u8, b: u8) []const u8 {
        return switch (b) {
            '\n' => "'\\n'",
            '\r' => "'\\r'",
            '\t' => "'\\t'",
            '\\' => "'\\\\'",
            '\'' => "'\\''",
            0x20...0x26, 0x28...0x5b, 0x5d...0x7e => std.mem.print(buf, "'{c}'", .{b}) catch unreachable,
            else => std.mem.print(buf, "0x{X:0>2}", .{b}) catch unreachable,
        };
    }

    const Range = struct { lo: u8, hi: u8 };

    fn ranges(set: ByteSet, out: *[128]Range) []Range {
        var n: usize = 0;
        var b: u16 = 0;
        while (b < 256) {
            if (!set.has(@intCast(b))) {
                b += 1;
                continue;
            }
            const lo: u8 = @intCast(b);
            while (b < 256 and set.has(@intCast(b))) b += 1;
            out[n] = .{ .lo = lo, .hi = @intCast(b - 1) };
            n += 1;
        }
        return out[0..n];
    }

    /// Switch-prong items for a byte set: `'a'...'z', '_'`.
    fn emitSwitchItems(self: *LexerGenerator, set: ByteSet) !void {
        var rbuf: [128]Range = undefined;
        var b1: [8]u8 = undefined;
        var b2: [8]u8 = undefined;
        for (ranges(set, &rbuf), 0..) |r, i| {
            if (i > 0) try self.write(", ");
            if (r.lo == r.hi) {
                try self.write(byteLit(&b1, r.lo));
            } else {
                try self.print("{s}...{s}", .{ byteLit(&b1, r.lo), byteLit(&b2, r.hi) });
            }
        }
    }

    fn tableIndex(self: *LexerGenerator, set: ByteSet) !usize {
        for (self.tables.items, 0..) |t, i| if (t.eql(set)) return i;
        try self.tables.append(self.arena.allocator(), set);
        return self.tables.items.len - 1;
    }

    /// A boolean expression testing `expr` (a u8) for membership in `set`.
    fn emitMembership(self: *LexerGenerator, set: ByteSet, expr: []const u8) !void {
        var rbuf: [128]Range = undefined;
        const rs = ranges(set, &rbuf);
        var b1: [8]u8 = undefined;
        var b2: [8]u8 = undefined;
        if (rs.len == 1) {
            const r = rs[0];
            if (r.lo == r.hi) {
                try self.print("{s} == {s}", .{ expr, byteLit(&b1, r.lo) });
            } else if (r.lo == 0) {
                try self.print("{s} <= {s}", .{ expr, byteLit(&b1, r.hi) });
            } else if (r.hi == 255) {
                try self.print("{s} >= {s}", .{ expr, byteLit(&b1, r.lo) });
            } else {
                try self.print("{s} -% {s} <= {d}", .{ expr, byteLit(&b1, r.lo), r.hi - r.lo });
            }
            return;
        }
        if (rs.len == 2 and rs[0].lo == rs[0].hi and rs[1].lo == rs[1].hi) {
            try self.print("({s} == {s} or {s} == {s})", .{ expr, byteLit(&b1, rs[0].lo), expr, byteLit(&b2, rs[1].lo) });
            return;
        }
        const idx = try self.tableIndex(set);
        try self.print("cls{d}[{s}]", .{ idx, expr });
    }

    fn emitTableDecls(self: *LexerGenerator, w: *std.Io.Writer) !void {
        for (self.tables.items, 0..) |set, i| {
            try w.print("\n    const cls{d} = blk: {{\n        var t: [256]bool = @splat(false);\n", .{i});
            var rbuf: [128]Range = undefined;
            var b1: [8]u8 = undefined;
            for (ranges(set, &rbuf)) |r| {
                if (r.lo == r.hi) {
                    try w.print("        t[{s}] = true;\n", .{byteLit(&b1, r.lo)});
                } else {
                    try w.print("        for ({s}..{d}) |c| t[c] = true;\n", .{ byteLit(&b1, r.lo), @as(u16, r.hi) + 1 });
                }
            }
            try w.writeAll("        break :blk t;\n    };\n");
        }
    }

    // =========================================================================
    // Emission: matchRules
    // =========================================================================

    fn hasSkipRule(self: *const LexerGenerator) bool {
        for (self.spec.rules.items) |r| if (r.isSkip) return true;
        return false;
    }

    fn preMutable(self: *const LexerGenerator) bool {
        for (self.spec.rules.items) |r| {
            for (r.actions) |act| {
                if (std.mem.eql(u8, act.variable.?, "pre")) return true;
            }
        }
        return false;
    }

    fn emitMatchRules(self: *LexerGenerator) !void {
        // matchRules goes to its own buffer first: the byte tables and the
        // SIMD helper it turns out to need are declared ahead of it.
        var body: std.Io.Writer.Allocating = .init(self.allocator);
        defer body.deinit();
        const main = self.w;
        self.w = &body.writer;
        try self.emitMatchRulesBody();
        self.w = main;
        try self.emitTableDecls(self.w);
        if (self.simdUsed) try self.write(simdHelper);
        try self.write(body.written());
    }

    fn emitMatchRulesBody(self: *LexerGenerator) !void {
        const skipLoop = self.hasSkipRule();
        try self.write(
            \\
            \\    /// Match the next token.
            \\    pub fn matchRules(self: *Self) Token {
            \\        const src = self.source;
            \\        const n = src.len;
            \\        var p: usize = self.pos;
            \\        const wsStart = p;
            \\
        );
        const ind = if (skipLoop) "            " else "        ";
        if (skipLoop) try self.write("        scan: while (true) {\n");
        try self.print(
            \\{s}while (p < n and (src[p] == ' ' or src[p] == '\t')) p += 1;
            \\{s}{s} pre: u8 = @intCast(@min(p - wsStart, 255));
            \\
        , .{ ind, ind, if (self.preMutable()) "var" else "const" });

        try self.emitZeroWidthRules(ind);

        try self.print(
            \\{s}if (p >= n) {{
            \\{s}    self.pos = @intCast(p);
            \\{s}    return .{{ .cat = .@"eof", .pre = pre, .pos = @intCast(p), .len = 0 }};
            \\{s}}}
            \\{s}const start = p;
            \\
        , .{ ind, ind, ind, ind, ind });

        if (self.consuming.len > 0) {
            try self.emitDfa(ind);
        }

        // No rule matched: one byte becomes an error token.
        try self.emitAfter(ind, &.{});
        try self.print(
            \\{s}self.pos = @intCast(start + 1);
            \\{s}return .{{ .cat = .@"err", .pre = pre, .pos = @intCast(start), .len = 1 }};
            \\
        , .{ ind, ind });
        if (skipLoop) try self.write("        }\n");
        try self.write("    }\n");
    }

    fn emitGuardExpr(self: *LexerGenerator, g: Guard) !void {
        const lhs = if (std.mem.eql(u8, g.variable, "pre")) "pre" else g.variable;
        const prefix = if (std.mem.eql(u8, g.variable, "pre")) "" else "self.";
        const at = atomOf(g);
        const op: []const u8 = switch (at.op) {
            .eq => if (g.negated) "!=" else "==",
            .ne => if (g.negated) "==" else "!=",
            .gt => if (g.negated) "<=" else ">",
            .lt => if (g.negated) ">=" else "<",
            .ge => if (g.negated) "<" else ">=",
            .le => if (g.negated) ">" else "<=",
            .truthy => unreachable,
        };
        try self.print("{s}{s} {s} {d}", .{ prefix, lhs, op, at.value });
    }

    fn emitGuards(self: *LexerGenerator, guards: []const Guard) !void {
        for (guards, 0..) |g, i| {
            if (i > 0) try self.write(" and ");
            try self.emitGuardExpr(g);
        }
    }

    /// State-variable and `pre` assignments; `counted` consumes from `p`.
    fn emitActions(self: *LexerGenerator, actions: []const Action, ind: []const u8, cursor: []const u8) !void {
        for (actions) |act| {
            const v = act.variable.?;
            const isPre = std.mem.eql(u8, v, "pre");
            const lhsPrefix = if (isPre) "" else "self.";
            switch (act.kind) {
                .set => try self.print("{s}{s}{s} = {d};\n", .{ ind, lhsPrefix, v, act.value.? }),
                .inc => try self.print("{s}self.{s} +|= 1;\n", .{ ind, v }),
                .dec => try self.print("{s}self.{s} -|= 1;\n", .{ ind, v }),
                .counted => {
                    var b1: [8]u8 = undefined;
                    const cl = byteLit(&b1, act.char.?);
                    const conv = if (isPre) "count" else "@bitCast(count)";
                    try self.print(
                        \\{s}{{
                        \\{s}    var count: u8 = 0;
                        \\{s}    while ({s} < n and src[{s}] == {s}) {{
                        \\{s}        {s} += 1;
                        \\{s}        count +|= 1;
                        \\{s}        while ({s} < n and (src[{s}] == ' ' or src[{s}] == '\t')) {s} += 1;
                        \\{s}    }}
                        \\{s}    {s}{s} = {s};
                        \\{s}}}
                        \\
                    , .{ ind, ind, ind, cursor, cursor, cl, ind, cursor, ind, ind, cursor, cursor, cursor, cursor, ind, ind, lhsPrefix, v, conv, ind });
                },
            }
        }
    }

    /// Does the `after` assignment `act` run for a rule with `actions`? Not
    /// when one of them sets (or counts into) the same variable.
    fn afterApplies(act: Action, actions: []const Action) bool {
        for (actions) |o| {
            if (std.mem.eql(u8, o.variable.?, act.variable.?) and (o.kind == .set or o.kind == .counted)) return false;
        }
        return true;
    }

    /// The `after` assignments that run for a rule with `actions`.
    fn emitAfter(self: *LexerGenerator, ind: []const u8, actions: []const Action) !void {
        for (self.spec.afterActions.items) |act| {
            if (afterApplies(act, actions)) try self.print("{s}self.{s} = {d};\n", .{ ind, act.variable.?, act.value.? });
        }
    }

    fn emitZeroWidthRules(self: *LexerGenerator, ind: []const u8) !void {
        for (self.spec.rules.items) |*r| {
            if (r.pattern.len != 0) continue;
            try self.print("{s}if (", .{ind});
            try self.emitGuards(r.guards);
            try self.write(") {\n");
            const inner = try self.arena.allocator().print("{s}    ", .{ind});
            try self.emitActions(r.actions, inner, "p");
            if (r.hold) {
                try self.print(
                    \\{s}self.pos = @intCast(wsStart);
                    \\{s}return .{{ .cat = .@"{s}", .pre = pre, .pos = @intCast(wsStart), .len = 0 }};
                    \\
                , .{ inner, inner, r.token });
            } else {
                try self.print(
                    \\{s}self.pos = @intCast(p);
                    \\{s}return token(.@"{s}", pre, wsStart, p);
                    \\
                , .{ inner, inner, r.token });
            }
            try self.print("{s}}}\n", .{ind});
        }
    }

    /// Code that finishes consuming rule `k` whose match ends at `endExpr`
    /// (a usize expression): after-block, token end, actions, return.
    fn emitFinish(self: *LexerGenerator, k: usize, endExpr: []const u8, ind: []const u8) !void {
        const r = &self.spec.rules.items[self.consuming[k]];
        try self.emitAfter(ind, r.actions);
        switch (self.ends[k]) {
            .whole => if (!std.mem.eql(u8, endExpr, "p")) try self.print("{s}p = {s};\n", .{ ind, endExpr }),
            .start => try self.print("{s}p = start;\n", .{ind}),
            .fromStart => |m| try self.print("{s}p = start + {d};\n", .{ ind, m }),
            .fromEnd => |m| try self.print("{s}p = {s} - {d};\n", .{ ind, endExpr, m }),
        }
        try self.emitActions(r.actions, ind, "p");
        if (r.isSkip) {
            try self.print("{s}continue :scan;\n", .{ind});
            return;
        }
        try self.print(
            \\{s}self.pos = @intCast(p);
            \\{s}return token(.@"{s}", pre, start, p);
            \\
        , .{ ind, ind, r.token });
    }

    fn hasSelfLoop(self: *const LexerGenerator, s: u32) bool {
        const nc = self.dfa.classes.count;
        for (0..nc) |c| if (self.dfa.trans[s * nc + c] == s) return true;
        return false;
    }

    fn isTerminal(self: *const LexerGenerator, s: u32) bool {
        if (self.dfa.accept[s] == automaton.none) return false;
        const nc = self.dfa.classes.count;
        for (0..nc) |c| if (self.dfa.trans[s * nc + c] != automaton.none) return false;
        return true;
    }

    fn emitDfa(self: *LexerGenerator, ind: []const u8) !void {
        const a = self.arena.allocator();
        const dfa = &self.dfa;
        const nc = dfa.classes.count;

        // Configuration mask from the guard atoms.
        const start0 = self.firstStart();
        const multi = for (self.startOfMask) |s| {
            if (s != automaton.none and s != start0) break true;
        } else false;
        var anySave = false;
        for (self.saves) |sv| anySave = anySave or sv;
        if (anySave) {
            try self.print("{s}var acc: u16 = {d};\n{s}var accEnd: usize = start;\n", .{ ind, noRule, ind });
        }
        // With several start states, a `select` prong (entered first, so the
        // initial dispatch is a direct jump) branches on the guard conditions
        // and continues into the start state of the configuration that holds.
        const select: u32 = dfa.numStates;
        try self.print("{s}dfa: switch (@as(u16, {d})) {{\n", .{ ind, if (multi) select else start0 });
        if (multi) {
            const selInd = try a.print("{s}    ", .{ind});
            try self.print("{s}{d} => {{\n", .{ selInd, select });
            try self.emitSelect(0, 0, try a.print("{s}    ", .{selInd}));
            try self.print("{s}}},\n", .{selInd});
        }

        const inner = try a.print("{s}    ", .{ind});
        const inner2 = try a.print("{s}        ", .{ind});
        const inner3 = try a.print("{s}            ", .{ind});

        // States that are only entered by in-place finishes need no prong.
        var s: u32 = 0;
        while (s < dfa.numStates) : (s += 1) {
            const isStart = for (dfa.starts) |st| {
                if (st == s) break true;
            } else false;
            if (self.isTerminal(s) and !isStart) continue;
            try self.print("{s}{d} => {{\n", .{ inner, s });

            // Group transitions by target.
            var loop: ByteSet = .{};
            var targets: std.ArrayList(struct { t: u32, set: ByteSet }) = .empty;
            for (0..nc) |c| {
                const t = dfa.trans[s * nc + c];
                if (t == automaton.none) continue;
                const bytes = dfa.classes.bytes(@intCast(c));
                if (t == s) {
                    loop.merge(bytes);
                    continue;
                }
                for (targets.items) |*x| {
                    if (x.t == t) {
                        x.set.merge(bytes);
                        break;
                    }
                } else try targets.append(a, .{ .t = t, .set = bytes });
            }

            if (!loop.isEmpty()) try self.emitLoop(loop, inner2);
            const acc = dfa.accept[s];
            if (self.saves[s]) try self.print("{s}acc = {d};\n{s}accEnd = p;\n", .{ inner2, acc, inner2 });
            // The widest transition into a looping state (identifier-like
            // runs) is tested before the switch: a predictable branch on the
            // common path instead of an indirect jump through the table.
            var hot: ?usize = null;
            if (targets.items.len > 1) {
                for (targets.items, 0..) |x, i| {
                    if (x.set.count() < hotClassMin or self.isTerminal(x.t) or !self.hasSelfLoop(x.t)) continue;
                    if (hot == null or x.set.count() > targets.items[hot.?].set.count()) hot = i;
                }
            }
            if (hot) |h| {
                try self.print("{s}if (p < n and ", .{inner2});
                try self.emitMembership(targets.items[h].set, "src[p]");
                try self.print(") {{\n{s}    p += 1;\n{s}    continue :dfa {d};\n{s}}}\n", .{ inner2, inner2, targets.items[h].t, inner2 });
                _ = targets.orderedRemove(h);
            }
            if (targets.items.len > 0) {
                try self.print("{s}if (p < n) switch (src[p]) {{\n", .{inner2});
                var covered: ByteSet = .{};
                for (targets.items) |x| covered.merge(x.set);
                for (targets.items) |x| {
                    try self.write(inner3);
                    try self.emitSwitchItems(x.set);
                    if (self.isTerminal(x.t)) {
                        // The finish, on one line when it is at most three simple statements.
                        var body: std.Io.Writer.Allocating = .init(a);
                        const outer = self.w;
                        self.w = &body.writer;
                        try self.emitFinish(dfa.accept[x.t], "p", "");
                        self.w = outer;
                        const text = std.mem.trimEnd(u8, body.written(), "\n");
                        if (std.mem.count(u8, text, "\n") <= 2 and std.mem.count(u8, text, "{") == std.mem.count(u8, text, ".{")) {
                            const joined = try std.mem.replaceOwned(u8, a, text, "\n", " ");
                            try self.print(" => {{ p += 1; {s} }},\n", .{joined});
                        } else {
                            try self.write(" => {\n");
                            const deep = try a.print("{s}    ", .{inner3});
                            try self.print("{s}p += 1;\n", .{deep});
                            try self.emitFinish(dfa.accept[x.t], "p", deep);
                            try self.print("{s}}},\n", .{inner3});
                        }
                    } else {
                        try self.print(" => {{ p += 1; continue :dfa {d}; }},\n", .{x.t});
                    }
                }
                if (covered.count() < 256) try self.print("{s}else => {{}},\n", .{inner3});
                try self.print("{s}}};\n", .{inner2});
            }
            if (acc != automaton.none) {
                try self.emitFinish(acc, "p", inner2);
            } else {
                try self.print("{s}break :dfa;\n", .{inner2});
            }
            try self.print("{s}}},\n", .{inner});
        }
        try self.print("{s}else => unreachable,\n{s}}}\n", .{ inner, ind });

        // Fallback: the scan died after passing an accepting state.
        if (anySave) {
            var saved = std.array_hash_map.Auto(u32, void).empty;
            for (self.saves, 0..) |sv, st| {
                if (sv) try saved.put(a, dfa.accept[st], {});
            }
            try self.print("{s}switch (acc) {{\n", .{ind});
            for (saved.keys()) |k| {
                try self.print("{s}{d} => {{\n", .{ inner, k });
                try self.emitFinish(k, "accEnd", inner2);
                try self.print("{s}}},\n", .{inner});
            }
            try self.print("{s}else => {{}},\n{s}}}\n", .{ inner, ind });
        }
    }

    const noRule: u16 = std.math.maxInt(u16);

    /// A decision tree over the guard atoms that continues into the start
    /// state of the configuration that holds. `fixed` marks atoms already
    /// tested on this path, with their outcomes in `bits`; only atoms that
    /// still change the start state are tested, and configurations no
    /// values produce do not count.
    fn emitSelect(self: *LexerGenerator, fixed: usize, bits: usize, ind: []const u8) !void {
        const starts = self.startOfMask;
        const none = automaton.none;
        var first: ?u32 = null;
        var uniform = true;
        for (starts, 0..) |st, mask| {
            if (mask & fixed != bits or st == none) continue;
            if (first == null) first = st else if (first.? != st) uniform = false;
        }
        if (uniform) {
            try self.print("{s}continue :dfa {d};\n", .{ ind, first.? });
            return;
        }
        // The first untested atom the start state depends on. When no single
        // atom flips it (the configurations in between are impossible), the
        // first atom that tells two possible configurations apart.
        const atom = for (0..self.atoms.len) |i| {
            const bit = @as(usize, 1) << @intCast(i);
            if (fixed & bit != 0) continue;
            for (starts, 0..) |st, mask| {
                if (mask & fixed == bits and st != none and starts[mask ^ bit] != none and starts[mask ^ bit] != st) break;
            } else continue;
            break i;
        } else for (0..self.atoms.len) |i| {
            const bit = @as(usize, 1) << @intCast(i);
            if (fixed & bit != 0) continue;
            var on = false;
            var off = false;
            for (starts, 0..) |st, mask| {
                if (mask & fixed != bits or st == none) continue;
                if (mask & bit != 0) on = true else off = true;
            }
            if (on and off) break i;
        } else unreachable;
        const bit = @as(usize, 1) << @intCast(atom);
        const at = self.atoms[atom];
        try self.print("{s}if (", .{ind});
        try self.emitGuardExpr(.{ .variable = at.variable, .op = at.op, .value = at.value });
        try self.write(") {\n");
        const deeper = try self.arena.allocator().print("{s}    ", .{ind});
        try self.emitSelect(fixed | bit, bits | bit, deeper);
        try self.print("{s}}} else {{\n", .{ind});
        try self.emitSelect(fixed | bit, bits, deeper);
        try self.print("{s}}}\n", .{ind});
    }

    fn emitLoop(self: *LexerGenerator, loop: ByteSet, ind: []const u8) !void {
        const stops = loop.invert();
        const nstops = stops.count();
        if (nstops >= 1 and nstops <= maxSimdStops) {
            self.simdUsed = true;
            var buf: [maxSimdStops]u8 = undefined;
            var k: usize = 0;
            for (0..256) |b| {
                if (stops.has(@intCast(b))) {
                    buf[k] = @intCast(b);
                    k += 1;
                }
            }
            var b1: [8]u8 = undefined;
            try self.print("{s}p = scanUntil(src, p, &.{{", .{ind});
            for (buf[0..k], 0..) |b, i| {
                if (i > 0) try self.write(", ");
                try self.write(byteLit(&b1, b));
            }
            try self.write("});\n");
            return;
        }
        try self.print("{s}while (p < n and ", .{ind});
        try self.emitMembership(loop, "src[p]");
        try self.write(") p += 1;\n");
    }
};

/// Emitted when a self-loop excludes only a few bytes: finds the first byte
/// at or after `from` that is one of `stops` (or the end of input), 16 bytes
/// at a time.
const simdHelper =
    \\
    \\    /// First index at or after `from` whose byte is in `stops` (or src.len).
    \\    inline fn scanUntil(src: []const u8, from: usize, comptime stops: []const u8) usize {
    \\        const V = @Vector(16, u8);
    \\        var p = from;
    \\        while (p + 16 <= src.len) : (p += 16) {
    \\            const v: V = src[p..][0..16].*;
    \\            var hits: u16 = 0;
    \\            inline for (stops) |c| hits |= @bitCast(v == @as(V, @splat(c)));
    \\            if (hits != 0) return p + @ctz(hits);
    \\        }
    \\        while (p < src.len) : (p += 1) {
    \\            inline for (stops) |c| if (src[p] == c) return p;
    \\        }
    \\        return p;
    \\    }
    \\
;
