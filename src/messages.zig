//! `@messages`: example mistakes, each with the message a syntax error
//! there gets instead of the automatic one.
//!
//! An example is a sentence of grammar symbols, written as rules write
//! them, whose last element is the token the parser cannot take. It runs
//! through the parse table as the generated parser runs input: from the
//! start state, past the start marker, each token after the reductions the
//! table makes on it, and each rule name by its goto (after the
//! reductions the parser makes on a token that can begin the rule, when
//! the state has no goto on it). On the last token the reductions are
//! made, and the state that rejects it is the failure state. The key of
//! an entry is
//!
//!   at     (failure state, token, guard)
//!   after  (anchor, token, guard)
//!
//! where the anchor is the first state of the reduction chain the
//! generated parser follows at that failure (BaseParser.recordFailure,
//! mirrored here step for step). Every mistake is a located error: an
//! unknown symbol or start symbol, a guard text the lexer never gives
//! that token, an example the parser takes whole, one it rejects before
//! its last token, and two entries with one key. The entries become a
//! sorted table in the generated module (codegen), which `writeFailure`
//! reads.
//!
//! `nexus check --messages` prints the coverage (`writeCoverage`): each
//! place an `after` entry can key on that has none, with the shortest
//! example that reaches it and its automatic message.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const Message = grammar.Message;
const LexerSpec = grammar.LexerSpec;
const diag = @import("diag.zig");
const Automaton = @import("lr/automaton.zig").Automaton;
const Lookaheads = @import("lr/lookahead.zig").Lookaheads;
const table = @import("lr/table.zig");
const Table = table.Table;
const ParseAction = table.ParseAction;
const LexerGenerator = @import("lexgen/lexgen.zig").LexerGenerator;
const codegen = @import("codegen/codegen.zig");

/// One key of the generated message table.
pub const Entry = struct {
    kind: Message.Kind,
    /// The failure state (`at`) or the anchor (`after`).
    state: u16,
    /// The offending token's symbol.
    symbol: u16,
    /// The offending token's text; null when any text matches.
    guard: ?[]const u8,
    text: []const u8,
    /// Where the entry is written.
    line: u32,
    col: u32,

    /// The order of the generated table: by kind, state, symbol, then
    /// guard (unguarded first).
    pub fn lessThan(_: void, x: Entry, y: Entry) bool {
        if (x.kind != y.kind) return @backingInt(x.kind) < @backingInt(y.kind);
        if (x.state != y.state) return x.state < y.state;
        if (x.symbol != y.symbol) return x.symbol < y.symbol;
        const xg = x.guard orelse return y.guard != null;
        const yg = y.guard orelse return false;
        return std.mem.order(u8, xg, yg) == .lt;
    }

    fn sameKey(x: Entry, y: Entry) bool {
        if (x.kind != y.kind or x.state != y.state or x.symbol != y.symbol) return false;
        if (x.guard == null or y.guard == null) return x.guard == null and y.guard == null;
        return std.mem.eql(u8, x.guard.?, y.guard.?);
    }
};

pub const Error = error{ GenerationFailed, OutOfMemory };

pub const Input = struct {
    g: *const Grammar,
    auto: *const Automaton,
    tbl: *const Table,
    la: *const Lookaheads,
    spec: *const LexerSpec,
    /// The lexer, for the guards (`LexerGenerator.gives`).
    lexer: *const LexerGenerator,
    /// The grammar file, for located errors.
    path: []const u8,
};

/// Every entry of `messages` run through the table and keyed, sorted. The
/// first mistake is reported and stops generation.
pub fn compute(a: Allocator, in: Input, messages: []const Message) Error![]const Entry {
    const v = try View.init(a, in.g, in.tbl);
    var entries: std.ArrayList(Entry) = .empty;
    for (messages) |m| {
        var stack: std.ArrayList(u16) = .empty;
        try stack.append(a, try startStateOf(in, m));
        const marker = in.g.getSymbol(try a.print("{s}!", .{in.g.symbols.items[startSymbolOf(in, m)].name})).?;
        try stack.append(a, v.shiftTarget(stack.last().?, marker).?);
        for (m.prefix) |name| {
            const sym = try resolve(a, in, name);
            const ok = if (in.g.symbols.items[sym].kind == .terminal)
                try v.consume(a, &stack, sym)
            else
                try v.enter(a, &stack, sym, in.la);
            if (!ok) return fail(in, name.line, name.col, "the parser fails here, before the example's last token", .{});
        }
        for (m.last) |last| {
            const sym = try resolve(a, in, last.name);
            if (last.guard) |text| try checkGuard(a, in, last, text);
            var s = try stack.clone(a);
            const failure = v.failOn(&s, sym) orelse
                return fail(in, last.name.line, last.name.col, "this example is not a syntax error: the parser takes its last token", .{});
            const state = switch (m.kind) {
                .at => failure,
                .after => v.expectationOf(s.items).states[0],
            };
            const e: Entry = .{ .kind = m.kind, .state = state, .symbol = sym, .guard = last.guard, .text = m.text, .line = m.line, .col = m.col };
            for (entries.items) |other| {
                if (!other.sameKey(e)) continue;
                if (std.mem.eql(u8, other.text, e.text))
                    return fail(in, m.line, m.col, "duplicate message: the one at {d}:{d} is for the same parser state and token", .{ other.line, other.col });
                return fail(in, m.line, m.col, "this message and the one at {d}:{d} are for the same parser state and token; the parser cannot tell them apart", .{ other.line, other.col });
            }
            try entries.append(a, e);
        }
    }
    std.mem.sort(Entry, entries.items, {}, Entry.lessThan);
    return entries.toOwnedSlice(a);
}

fn fail(in: Input, line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
    diag.errLine(in.path, line, col, fmt, args);
    return error.GenerationFailed;
}

/// The start symbol an example starts at: `name!:`, else the first.
fn startSymbolOf(in: Input, m: Message) u16 {
    const name = (m.start orelse return in.g.startSymbols.items[0]).name;
    for (in.g.startSymbols.items) |s| if (std.mem.eql(u8, in.g.symbols.items[s].name, name)) return s;
    return in.g.startSymbols.items[0];
}

fn startStateOf(in: Input, m: Message) Error!u16 {
    if (m.start) |start| {
        const sym = in.g.getSymbol(start.name);
        const index = for (in.g.startSymbols.items, 0..) |s, i| {
            if (sym == s) break i;
        } else return fail(in, start.line, start.col, "'{s}' is not a start symbol (`name!:` names the start symbol an example starts at)", .{start.name});
        return in.auto.startStates.items[index];
    }
    return in.auto.startStates.items[0];
}

/// The symbol a name of an example stands for, as a rule's element would:
/// a rule, a token (a declared token the parser grammar does not use
/// reaches the parser as `error`; EOF is the end of input), or a literal
/// (the token whose lexer rule is exactly its text, or its `@op` token).
fn resolve(a: Allocator, in: Input, name: Message.Name) Error!u16 {
    const g = in.g;
    const n = name.name;
    if (g.getSymbol(n)) |sym| return sym;
    const cat: ?[]const u8 = if (n[0] == '"') lit: {
        const raw = n[1 .. n.len - 1];
        const bytes = try grammar.decode(a, raw);
        for (g.opMappings) |m| if (std.mem.eql(u8, m.lit, bytes)) break :lit m.tok;
        break :lit grammar.findTokenForLiteral(in.spec, raw);
    } else if (std.ascii.isUpper(n[0])) try std.ascii.allocLowerString(a, n) else null;
    if (cat) |c| {
        if (g.terminalOf(c)) |sym| return sym;
        if (std.mem.eql(u8, c, "eof")) return g.endId;
        const declared = for (in.spec.tokens.items) |t| {
            if (std.mem.eql(u8, t, c)) break true;
        } else false;
        const trivia = for (g.trivia) |t| {
            if (std.ascii.eqlIgnoreCase(t, c)) break true;
        } else false;
        if (declared and !trivia) return g.errorId;
    }
    return fail(in, name.line, name.col, "'{s}' is no rule, token or literal of the grammar", .{n});
}

/// A guard's text must be one the lexer gives the token: a token only a
/// lang Lexer makes is exempt.
fn checkGuard(a: Allocator, in: Input, last: Message.Last, text: []const u8) Error!void {
    // The frontend takes a guard on a token name only.
    const n = last.name.name;
    const gives = in.lexer.gives(try std.ascii.allocLowerString(a, n), text) orelse return;
    if (!gives)
        return fail(in, last.guardLine, last.guardCol, "the lexer never gives {s} the text \"{f}\"", .{ n, std.zig.fmtString(text) });
}

// =============================================================================
// The table as the generated parser reads it
// =============================================================================

/// A cell no rule has: a reduction an `X "c"` hint overrides.
const hinted: i16 = std.math.minInt(i16);
const noSymbol: u16 = std.math.maxInt(u16);

/// The generated parser's `parseTable`, `namedRules`, expected lists and
/// symbol names, read from the table.
const View = struct {
    g: *const Grammar,
    tbl: *const Table,
    named: []const u16,
    /// `maxExpected` of the generated parser.
    maxExpected: usize,
    /// `symbolName` of the generated parser, per symbol.
    names: []const []const u8,

    fn init(a: Allocator, g: *const Grammar, tbl: *const Table) Allocator.Error!View {
        const e = tbl.expected;
        var longest: usize = 0;
        for (0..e.numLists()) |i| longest = @max(longest, e.offsets[i + 1] - e.offsets[i]);
        const names = try a.alloc([]const u8, g.symbols.items.len);
        for (g.symbols.items, names) |sym, *name| name.* = try codegen.symbolDisplayName(a, g, sym) orelse "";
        return .{ .g = g, .tbl = tbl, .named = e.namedRules, .maxExpected = longest, .names = names };
    }

    fn actionValue(action: ParseAction) i16 {
        return switch (action) {
            .shift => |t| @intCast(t),
            .reduce => |r| -@as(i16, @intCast(r)) - 2,
            .gotoState => |t| @intCast(t),
            .accept => -1,
            .err => 0,
        };
    }

    /// `getAction`: the cell, or `hinted`.
    fn cell(v: *const View, state: u16, sym: u16) i16 {
        const xs = v.tbl.xExcludes.items;
        if (xs.len > 0) for (xs[v.tbl.xExcludeStart[state]..v.tbl.xExcludeStart[state + 1]]) |x| {
            if (x.sym == sym) return hinted;
        };
        return actionValue(v.tbl.rows[state][sym]);
    }

    /// The action on a token that does not touch the one before: a hinted
    /// cell's reduction (`strictAction`, `reductionOn`).
    fn plain(v: *const View, state: u16, sym: u16) i16 {
        return actionValue(v.tbl.rows[state][sym]);
    }

    fn ruleLen(v: *const View, rule: u16) usize {
        return v.g.rules.items[rule].rhs.len;
    }

    fn ruleLhs(v: *const View, rule: u16) u16 {
        return v.g.rules.items[rule].lhs;
    }

    fn shiftTarget(v: *const View, state: u16, sym: u16) ?u16 {
        const action = v.plain(state, sym);
        return if (action > 0) @intCast(action) else null;
    }

    /// Reduce by `rule` on `stack`; false when there is no goto.
    fn reduce(v: *const View, stack: *std.ArrayList(u16), rule: u16) bool {
        const n = v.ruleLen(rule);
        if (n >= stack.items.len) return false;
        stack.shrinkRetainingCapacity(stack.items.len - n);
        const next = v.plain(stack.last().?, v.ruleLhs(rule));
        if (next <= 0) return false;
        stack.appendAssumeCapacity(@intCast(next));
        return true;
    }

    /// Make the reductions on token `sym` and shift it; false when the
    /// parser rejects it or accepts on it.
    fn consume(v: *const View, a: Allocator, stack: *std.ArrayList(u16), sym: u16) Allocator.Error!bool {
        for (0..maxSteps) |_| {
            const action = v.plain(stack.last().?, sym);
            if (action > 0) {
                try stack.append(a, @intCast(action));
                return true;
            }
            if (action >= -1 or !v.reduce(stack, @intCast(-action - 2))) return false;
        }
        return false;
    }

    /// Make the reductions on token `sym`: the state that rejects it, or
    /// null when the parser shifts it or accepts on it.
    fn failOn(v: *const View, stack: *std.ArrayList(u16), sym: u16) ?u16 {
        for (0..maxSteps) |_| {
            const top = stack.last().?;
            const action = v.plain(top, sym);
            if (action == 0) return top;
            if (action >= -1 or !v.reduce(stack, @intCast(-action - 2))) return null;
        }
        return null;
    }

    /// Enter rule `sym` as any derivation of it does: its goto, after the
    /// reductions the parser makes on the first token (in symbol order)
    /// of the rule that leads to a state with a goto on it.
    fn enter(v: *const View, a: Allocator, stack: *std.ArrayList(u16), sym: u16, la: *const Lookaheads) Allocator.Error!bool {
        if (v.shiftTarget(stack.last().?, sym)) |target| {
            try stack.append(a, target);
            return true;
        }
        const first = la.first.get(sym);
        for (0..v.g.symbols.items.len) |t| {
            if (!first.isSet(t) or v.g.symbols.items[t].kind != .terminal) continue;
            var s = try stack.clone(a);
            var ok = false;
            for (0..maxSteps) |_| {
                const action = v.plain(s.last().?, @intCast(t));
                if (action > 0) {
                    ok = v.shiftTarget(s.last().?, sym) != null;
                    break;
                }
                if (action >= -1 or !v.reduce(&s, @intCast(-action - 2))) break;
            }
            if (!ok) continue;
            try s.append(a, v.shiftTarget(s.last().?, sym).?);
            stack.* = s;
            return true;
        }
        return false;
    }

    /// The most reductions a simulation makes on one token.
    const maxSteps = 100_000;

    // --- The reduction chain, as BaseParser.recordFailure follows it -------

    fn isNamed(v: *const View, sym: u16) bool {
        return std.mem.findScalar(u16, v.named, sym) != null;
    }

    fn namedGoto(v: *const View, below: u16, state: u16) u16 {
        for (v.named) |r| if (v.cell(below, r) == state) return r;
        return noSymbol;
    }

    fn takes(v: *const View, state: u16, sym: u16) bool {
        const action = v.cell(state, sym);
        return action > 0 or action == -1 or action == hinted;
    }

    fn reductionOn(v: *const View, state: u16, sym: u16) ?u16 {
        const action = v.plain(state, sym);
        return if (action <= -2) @intCast(-action - 2) else null;
    }

    /// `VirtualStack` of the runtime.
    const VirtualStack = struct {
        real: []const u16,
        depth: usize,
        pushed: [capacity]u16 = undefined,
        len: usize = 0,

        const capacity = 64;

        fn top(s: *const VirtualStack) u16 {
            return if (s.len > 0) s.pushed[s.len - 1] else s.real[s.depth - 1];
        }

        fn reduce(s: *VirtualStack, v: *const View, rule: u16) bool {
            const n = v.ruleLen(rule);
            const fromPushed = @min(n, s.len);
            s.len -= fromPushed;
            if (n - fromPushed >= s.depth) return false;
            s.depth -= n - fromPushed;
            const next = v.cell(s.top(), v.ruleLhs(rule));
            if (next <= 0 or s.len == capacity) return false;
            s.pushed[s.len] = @intCast(next);
            s.len += 1;
            return true;
        }

        fn goesOn(s: *const VirtualStack, v: *const View, sym: u16) ?Reach {
            var c = s.*;
            for (0..capacity) |i| {
                const action = v.cell(c.top(), sym);
                if (action > 0 or action == -1 or action == hinted) return .{ .height = c.depth + c.len, .reductions = i };
                if (action == 0 or !c.reduce(v, @intCast(-action - 2))) return null;
            }
            return null;
        }

        const Reach = struct {
            height: usize,
            reductions: usize,

            fn outside(x: Reach, y: Reach) bool {
                return x.height < y.height or (x.height == y.height and x.reductions > y.reductions);
            }
        };
    };

    /// `chainRule` of the runtime.
    fn chainRule(v: *const View, s: *const VirtualStack) ?u16 {
        const state = s.top();
        const numSymbols = v.g.symbols.items.len;
        var best: ?u16 = null;
        var bestReach: VirtualStack.Reach = undefined;
        var bestCount: u32 = 0;
        var tried: [16]u16 = undefined;
        var numTried: usize = 0;
        for (0..numSymbols) |t| {
            const rule = v.reductionOn(state, @intCast(t)) orelse continue;
            if (std.mem.findScalar(u16, tried[0..numTried], rule) != null) continue;
            if (numTried < tried.len) {
                tried[numTried] = rule;
                numTried += 1;
            }
            var reach: VirtualStack.Reach = undefined;
            var count: u32 = 0;
            for (0..numSymbols) |u| {
                if (v.reductionOn(state, @intCast(u)) != rule) continue;
                const r = s.goesOn(v, @intCast(u)) orelse continue;
                if (count == 0 or r.outside(reach)) reach = r;
                count += 1;
            }
            if (count == 0) continue;
            const same = best != null and !reach.outside(bestReach) and !bestReach.outside(reach);
            if (best == null or reach.outside(bestReach) or
                (same and (count > bestCount or (count == bestCount and rule < best.?))))
            {
                best = rule;
                bestReach = reach;
                bestCount = count;
            }
        }
        return best;
    }

    const chainLimit = 64;

    const Expectation = struct {
        states: [chainLimit]u16 = @splat(0),
        len: u8 = 0,
        after: u16 = noSymbol,
        takenOnly: bool = true,
    };

    /// `expectationOf` of the runtime: the chain from the top of `stack`.
    fn expectationOf(v: *const View, stack: []const u16) Expectation {
        var s: VirtualStack = .{ .real = stack, .depth = stack.len };
        const first = s.top();
        var chain: [chainLimit]u16 = undefined;
        chain[0] = first;
        var n: usize = 1;
        var anchor: usize = 0;
        var after: u16 = if (stack.len >= 2) v.namedGoto(stack[stack.len - 2], first) else noSymbol;
        while (v.chainRule(&s)) |rule| {
            if (n == chainLimit or !s.reduce(v, rule)) {
                var whole: Expectation = .{ .len = 1, .takenOnly = false };
                whole.states[0] = first;
                return whole;
            }
            chain[n] = s.top();
            n += 1;
            if (v.isNamed(v.ruleLhs(rule))) {
                anchor = n - 1;
                after = v.ruleLhs(rule);
            }
        }
        var e: Expectation = .{ .len = @intCast(n - anchor), .after = after };
        @memcpy(e.states[0..e.len], chain[anchor..n]);
        return e;
    }

    // --- The automatic message --------------------------------------------

    fn expectedNames(v: *const View, state: u16, buf: [][]const u8) []const []const u8 {
        var n: usize = 0;
        for (v.tbl.expected.forState(state)) |sym| {
            const name = v.names[sym];
            if (name.len == 0) continue;
            for (buf[0..n]) |seen| {
                if (std.mem.eql(u8, seen, name)) break;
            } else {
                buf[n] = name;
                n += 1;
            }
        }
        return buf[0..n];
    }

    fn addName(buf: [][]const u8, n: *usize, name: []const u8) bool {
        if (name.len == 0) return true;
        for (buf[0..n.*]) |seen| if (std.mem.eql(u8, seen, name)) return true;
        if (n.* == buf.len) return false;
        buf[n.*] = name;
        n.* += 1;
        return true;
    }

    /// `failureNames` of the runtime, for a failure in `state`.
    fn failureNames(v: *const View, state: u16, e: Expectation, buf: [][]const u8, tokens: []u16) []const []const u8 {
        if (!e.takenOnly) return v.expectedNames(state, buf);
        var numTokens: usize = 0;
        var n: usize = 0;
        for (e.states[0..e.len]) |s| for (v.tbl.expected.forState(s)) |sym| {
            if (!v.takes(s, sym)) continue;
            if (!v.isNamed(sym)) {
                if (std.mem.findScalar(u16, tokens[0..numTokens], sym) != null) continue;
                if (numTokens == tokens.len) return v.expectedNames(state, buf);
                tokens[numTokens] = sym;
                numTokens += 1;
            } else if (!addName(buf, &n, v.names[sym])) return v.expectedNames(state, buf);
        };
        std.mem.sort(u16, tokens[0..numTokens], {}, std.sort.asc(u16));
        for (tokens[0..numTokens]) |sym| {
            if (!addName(buf, &n, v.names[sym])) return v.expectedNames(state, buf);
        }
        if (n == 0) return v.expectedNames(state, buf);
        return buf[0..n];
    }

    /// `expected A, B or C after R`, as `writeFailure` words an error in
    /// the top state of `stack`.
    fn writeAutomatic(v: *const View, a: Allocator, w: *std.Io.Writer, stack: []const u16) !void {
        const e = v.expectationOf(stack);
        const buf = try a.alloc([]const u8, v.maxExpected);
        const tokens = try a.alloc(u16, v.maxExpected);
        const want = v.failureNames(stack[stack.len - 1], e, buf, tokens);
        try w.writeAll("expected ");
        for (want, 0..) |name, i| {
            if (i > 0) try w.writeAll(if (i + 1 == want.len) " or " else ", ");
            try w.writeAll(name);
        }
        if (want.len == 0) try w.writeAll("nothing");
        if (e.after != noSymbol) try w.print(" after {s}", .{v.names[e.after]});
    }
};

// =============================================================================
// Coverage
// =============================================================================

/// `nexus check --messages`: the places an `after` entry can key on, each
/// without one with the shortest example that reaches it and its automatic
/// message, then how many have one.
///
/// A place is the anchor of an error right after a rule `@errors` names:
/// for each state the parser enters on such a rule, in the order a
/// breadth-first walk of the automaton reaches them, the symbols of the
/// walk to it, with each rule a group, list or choice generated written as
/// its shortest expansion (an example names no such rule), run through
/// the table as an example is; the anchor of the stack it leaves is the
/// place, and the first such example its example.
pub fn writeCoverage(a: Allocator, w: *std.Io.Writer, in: Input, entries: []const Entry) Error!void {
    writeCoverageTo(a, w, in, entries) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.OutOfMemory,
    };
}

fn writeCoverageTo(a: Allocator, w: *std.Io.Writer, in: Input, entries: []const Entry) !void {
    const v = try View.init(a, in.g, in.tbl);
    const g = in.g;
    const n = in.auto.states.items.len;
    const none = std.math.maxInt(u16);

    // Breadth first from the start states: each state's parent and the
    // symbol into it.
    const parent = try a.alloc(u16, n);
    const via = try a.alloc(u16, n);
    @memset(parent, none);
    const seen = try a.alloc(bool, n);
    @memset(seen, false);
    var queue: std.ArrayList(u16) = .empty;
    for (in.auto.startStates.items) |s| if (!seen[s]) {
        seen[s] = true;
        try queue.append(a, s);
    };
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const s = queue.items[head];
        for (in.auto.states.items[s].transitions) |t| {
            if (seen[t.target]) continue;
            seen[t.target] = true;
            parent[t.target] = s;
            via[t.target] = t.symbol;
            try queue.append(a, t.target);
        }
    }

    const Place = struct { anchor: u16, marker: u16, example: []const u16, stack: []const u16 };
    const isPlace = try a.alloc(bool, n);
    @memset(isPlace, false);
    var places: std.ArrayList(Place) = .empty;
    var path: std.ArrayList(u16) = .empty;
    var example: std.ArrayList(u16) = .empty;
    for (queue.items) |s| {
        if (parent[s] == none or !v.isNamed(via[s])) continue;
        path.clearRetainingCapacity();
        var t = s;
        var root = s;
        while (parent[t] != none) : (t = parent[t]) {
            try path.append(a, via[t]);
            root = parent[t];
        }
        std.mem.reverse(u16, path.items);
        // path[0] is the start marker `x!`.
        example.clearRetainingCapacity();
        for (path.items[1..]) |sym| try expand(a, &example, g, in.la, sym, 0);
        var stack: std.ArrayList(u16) = .empty;
        try stack.append(a, root);
        try stack.append(a, v.shiftTarget(root, path.items[0]).?);
        const reached = for (example.items) |sym| {
            const ok = if (g.symbols.items[sym].kind == .terminal)
                try v.consume(a, &stack, sym)
            else
                try v.enter(a, &stack, sym, in.la);
            if (!ok) break false;
        } else true;
        if (!reached) continue;
        const anchor = v.expectationOf(stack.items).states[0];
        if (isPlace[anchor]) continue;
        isPlace[anchor] = true;
        try places.append(a, .{ .anchor = anchor, .marker = path.items[0], .example = try a.dupe(u16, example.items), .stack = stack.items });
    }

    const firstMarker = g.getSymbol(try a.print("{s}!", .{g.symbols.items[g.startSymbols.items[0]].name}));
    var covered: usize = 0;
    for (places.items) |p| {
        const has = for (entries) |e| {
            if (e.kind == .after and e.state == p.anchor) break true;
        } else false;
        if (has) {
            covered += 1;
            continue;
        }
        try w.writeAll("after");
        if (p.marker != firstMarker) try w.print(" {s}:", .{g.symbols.items[p.marker].name});
        for (p.example) |sym| {
            const name = if (sym == g.endId) "EOF" else if (sym == g.errorId) "ERR" else g.symbols.items[sym].name;
            try w.print(" {s}", .{name});
        }
        try w.writeAll("\n    # ");
        try v.writeAutomatic(a, w, p.stack);
        try w.writeByte('\n');
    }
    try w.print("{d} of {d} places have a message\n", .{ covered, places.items.len });
}

/// Append `sym` as an example writes it: a rule or a token by name, a
/// literal as written, and a rule the expansion of a group, list or choice
/// generated (no name an example can write) as its shortest expansion.
fn expand(a: Allocator, out: *std.ArrayList(u16), g: *const Grammar, la: *const Lookaheads, sym: u16, depth: usize) !void {
    const s = g.symbols.items[sym];
    if (s.kind == .terminal or isRuleName(s.name) or depth > 64) return out.append(a, sym);
    // The cheapest rule of the generated symbol.
    var best: ?u16 = null;
    var bestCost: u64 = std.math.maxInt(u64);
    for (s.rules.items) |r| {
        var cost: u64 = 0;
        for (g.rules.items[r].rhs) |x| cost += la.costs[x];
        if (cost < bestCost) {
            best = r;
            bestCost = cost;
        }
    }
    for (g.rules.items[best.?].rhs) |x| try expand(a, out, g, la, x, depth + 1);
}

/// A name the grammar writes: a lowercase identifier.
fn isRuleName(name: []const u8) bool {
    if (name.len == 0 or !(std.ascii.isLower(name[0]) or name[0] == '_')) return false;
    for (name) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
