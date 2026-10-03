//! Unit tests of the LR core on small grammars: LALR(1) lookaheads against
//! a canonical LR(1) reference, conflict classification and
//! the manifest, hints, examples, expected sets, and repair ranking.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const lr = @import("lr.zig");
const automaton = lr.automaton;
const lookahead = lr.lookahead;
const table = lr.table;
const conflicts = lr.conflicts;
const repair = lr.repair;

// =============================================================================
// Test grammars
// =============================================================================

/// Build a desugared grammar the way expand.zig does (special symbols,
/// start markers, one accept rule per start symbol) from rules written
/// `lhs → sym sym ...`. Lowercase names are nonterminals, everything else
/// (UPPER tokens, quoted literals) terminals; `ε` is the empty rhs. A rule
/// may end with hints: `<`, `>`, and `X "c"` (any number).
fn build(a: Allocator, rules: []const []const u8, starts: []const []const u8) !Grammar {
    var g = Grammar.init(a);
    g.acceptId = try g.addSymbol("$accept", .nonterminal);
    g.endId = try g.addSymbol("$end", .terminal);
    g.errorId = try g.addSymbol("error", .terminal);
    for (rules) |text| {
        const arrow = std.mem.find(u8, text, "→").?;
        _ = try g.addSymbol(std.mem.trim(u8, text[0..arrow], " "), .nonterminal);
    }
    for (rules) |text| {
        const arrow = std.mem.find(u8, text, "→").?;
        const lhs = g.getSymbol(std.mem.trim(u8, text[0..arrow], " ")).?;
        var rhs: std.ArrayList(u16) = .empty;
        var excl: std.ArrayList(u8) = .empty;
        var rule: grammar.Rule = .{ .id = @intCast(g.rules.items.len), .lhs = lhs, .rhs = &.{} };
        var it = std.mem.tokenizeScalar(u8, text[arrow + "→".len ..], ' ');
        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "ε")) continue;
            if (std.mem.eql(u8, tok, "<")) {
                rule.preferReduce = true;
            } else if (std.mem.eql(u8, tok, ">")) {
                rule.preferShift = true;
            } else if (std.mem.eql(u8, tok, "X")) {
                try excl.append(a, it.next().?[1]);
            } else {
                const kind: grammar.Symbol.Kind = if (tok[0] >= 'a' and tok[0] <= 'z') .nonterminal else .terminal;
                try rhs.append(a, try g.addSymbol(tok, kind));
            }
        }
        rule.rhs = try rhs.toOwnedSlice(a);
        rule.excludeChars = try excl.toOwnedSlice(a);
        try g.rules.append(a, rule);
        try g.symbols.items[lhs].rules.append(a, rule.id);
    }
    for (starts) |name| {
        const start = g.getSymbol(name).?;
        const marker = try g.addSymbol(try a.print("{s}!", .{name}), .terminal);
        const acc = try g.addSymbol(try a.print("$accept_{s}", .{name}), .nonterminal);
        const id: u16 = @intCast(g.rules.items.len);
        try g.rules.append(a, .{ .id = id, .lhs = acc, .rhs = try a.dupe(u16, &.{ marker, start, g.endId }) });
        try g.symbols.items[acc].rules.append(a, id);
        try g.startSymbols.append(a, start);
        try g.acceptRules.append(a, id);
    }
    return g;
}

const Built = struct {
    g: Grammar,
    auto: automaton.Automaton,
    la: lookahead.Lookaheads,
    tbl: table.Table,
};

fn generate(a: Allocator, rules: []const []const u8, starts: []const []const u8) !*Built {
    const b = try a.create(Built);
    b.g = try build(a, rules, starts);
    b.auto = try automaton.build(&b.g);
    b.la = try lookahead.compute(&b.g, &b.auto, try repair.insertCosts(a, &b.g));
    b.tbl = try table.build(&b.g, &b.auto, b.la);
    return b;
}

fn sym(g: *const Grammar, name: []const u8) u16 {
    return g.getSymbol(name).?;
}

/// The state whose kernel contains `lhs → rhs[0..dot] • ...` for rule `ruleId`.
fn stateWith(auto: *const automaton.Automaton, ruleId: u16, dot: u16) !u16 {
    for (auto.states.items, 0..) |s, i| {
        for (s.kernel) |item| {
            if (item.ruleId == ruleId and item.dot == dot) return @intCast(i);
        }
    }
    return error.TestNoSuchState;
}

// =============================================================================
// Canonical LR(1) reference
// =============================================================================
//
// The LALR(1) lookahead of a reduction in an LR(0) state is, by definition,
// the union of its lookaheads over all canonical LR(1) states with that
// core. This builds the canonical LR(1) collection directly (tiny grammars
// only) and returns those unions.

const Lr1 = struct { rule: u16, dot: u16, la: u16 };

fn lr1Closure(a: Allocator, g: *const Grammar, la: lookahead.Lookaheads, seed: []const Lr1) ![]Lr1 {
    var items: std.ArrayList(Lr1) = .empty;
    try items.appendSlice(a, seed);
    var i: usize = 0;
    while (i < items.items.len) : (i += 1) {
        const it = items.items[i];
        const rhs = g.rules.items[it.rule].rhs;
        if (it.dot >= rhs.len or g.symbols.items[rhs[it.dot]].kind != .nonterminal) continue;
        // FIRST(rest la)
        var firsts: std.ArrayList(u16) = .empty;
        var allNullable = true;
        for (rhs[it.dot + 1 ..]) |s| {
            var fit = la.first.get(s).iterator();
            while (fit.next()) |t| try firsts.append(a, t);
            if (!la.nullable[s]) {
                allNullable = false;
                break;
            }
        }
        if (allNullable) try firsts.append(a, it.la);
        for (g.symbols.items[rhs[it.dot]].rules.items) |r| {
            for (firsts.items) |t| {
                const n: Lr1 = .{ .rule = r, .dot = 0, .la = t };
                const have = for (items.items) |x| {
                    if (std.meta.eql(x, n)) break true;
                } else false;
                if (!have) try items.append(a, n);
            }
        }
    }
    std.mem.sort(Lr1, items.items, {}, struct {
        fn lt(_: void, x: Lr1, y: Lr1) bool {
            if (x.rule != y.rule) return x.rule < y.rule;
            if (x.dot != y.dot) return x.dot < y.dot;
            return x.la < y.la;
        }
    }.lt);
    return items.toOwnedSlice(a);
}

/// ref[state][reduction] = sorted terminal ids.
fn canonicalLalr(a: Allocator, b: *const Built) ![][][]u16 {
    const g = &b.g;
    const auto = &b.auto;
    var states: std.ArrayList([]Lr1) = .empty;
    var lr0: std.ArrayList(u16) = .empty; // LR(0) state of each LR(1) state
    for (g.acceptRules.items, auto.startStates.items) |r, s0| {
        try states.append(a, try lr1Closure(a, g, b.la, &.{.{ .rule = r, .dot = 0, .la = g.endId }}));
        try lr0.append(a, s0);
    }
    var i: usize = 0;
    while (i < states.items.len) : (i += 1) {
        for (auto.states.items[lr0.items[i]].transitions) |t| {
            var kernel: std.ArrayList(Lr1) = .empty;
            for (states.items[i]) |it| {
                const rhs = g.rules.items[it.rule].rhs;
                if (it.dot < rhs.len and rhs[it.dot] == t.symbol)
                    try kernel.append(a, .{ .rule = it.rule, .dot = it.dot + 1, .la = it.la });
            }
            const closed = try lr1Closure(a, g, b.la, kernel.items);
            const known = for (states.items, 0..) |s, k| {
                if (s.len == closed.len and for (s, closed) |x, y| {
                    if (!std.meta.eql(x, y)) break false;
                } else true) break k;
            } else null;
            if (known == null) {
                try states.append(a, closed);
                try lr0.append(a, t.target);
            }
        }
    }

    const ref = try a.alloc([][]u16, auto.states.items.len);
    for (auto.states.items, 0..) |s, si| {
        ref[si] = try a.alloc([]u16, s.reductions.len);
        for (s.reductions, 0..) |red, ri| {
            var set: std.ArrayList(u16) = .empty;
            for (states.items, lr0.items) |items, s0| {
                if (s0 != si) continue;
                for (items) |it| {
                    if (it.rule == red.ruleId and it.dot == red.dot and
                        std.mem.findScalar(u16, set.items, it.la) == null)
                        try set.append(a, it.la);
                }
            }
            std.mem.sort(u16, set.items, {}, std.sort.asc(u16));
            ref[si][ri] = set.items;
        }
    }
    return ref;
}

fn expectLalrMatchesCanonical(a: Allocator, b: *const Built) !void {
    const ref = try canonicalLalr(a, b);
    for (b.auto.states.items, 0..) |s, si| {
        for (s.reductions, 0..) |red, ri| {
            if (b.g.isAcceptRule(red.ruleId)) continue;
            var got: std.ArrayList(u16) = .empty;
            var it = b.la.sets[si][ri].iterator();
            while (it.next()) |t| try got.append(a, t);
            try testing.expectEqualSlices(u16, ref[si][ri], got.items);
        }
    }
}

// =============================================================================
// Lookaheads
// =============================================================================

test "LALR resolves the classic L = R grammar (SLR(1) cannot)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rules = [_][]const u8{
        "s → l \"=\" r",
        "s → r",
        "l → \"*\" r",
        "l → ID",
        "r → l",
    };
    const lalr = try generate(a, &rules, &.{"s"});
    try testing.expectEqual(@as(u32, 0), lalr.tbl.conflicts);
    // In the state after `l`, `r → l •` reduces only on $end.
    const q = try stateWith(&lalr.auto, 0, 1);
    const red = lalr.auto.states.items[q].reductions;
    try testing.expectEqual(@as(usize, 1), red.len);
    try testing.expectEqual(@as(usize, 1), lalr.la.sets[q][0].count());
    try testing.expect(lalr.la.sets[q][0].isSet(lalr.g.endId));
    try expectLalrMatchesCanonical(a, lalr);
}

test "lookaheads through nullable symbols (reads) and right recursion (includes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const b = try generate(a, &.{
        "s → x opt tail C",
        "opt → A",
        "opt → ε",
        "tail → B tail",
        "tail → ε",
        "x → D x",
        "x → E",
    }, &.{"s"});
    try expectLalrMatchesCanonical(a, b);
    // After `x`, `opt → ε` reduces on what can follow: B (tail) or C.
    const q = try stateWith(&b.auto, 0, 1);
    const reds = b.auto.states.items[q].reductions;
    try testing.expectEqual(@as(usize, 1), reds.len);
    try testing.expectEqual(@as(usize, 2), b.la.sets[q][0].count());
    try testing.expect(b.la.sets[q][0].isSet(sym(&b.g, "B")) and b.la.sets[q][0].isSet(sym(&b.g, "C")));
}

test "LALR lookaheads equal merged canonical LR(1) on random grammars" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rand = prng.random();
    const nts = [_][]const u8{ "s", "a", "b", "c", "d" };
    const ts = [_][]const u8{ "P", "Q", "R", "\"+\"" };
    var tested: usize = 0;
    var round: usize = 0;
    while (round < 600) : (round += 1) {
        var rules: std.ArrayList([]const u8) = .empty;
        for (nts) |lhs| {
            const n = 1 + rand.uintLessThan(usize, 3);
            for (0..n) |_| {
                var text: std.ArrayList(u8) = .empty;
                try text.print(a, "{s} →", .{lhs});
                const len = rand.uintLessThan(usize, 4);
                if (len == 0) try text.appendSlice(a, " ε");
                for (0..len) |_| {
                    const s = if (rand.boolean()) nts[rand.uintLessThan(usize, nts.len)] else ts[rand.uintLessThan(usize, ts.len)];
                    try text.print(a, " {s}", .{s});
                }
                try rules.append(a, text.items);
            }
        }
        // DeRemer–Pennello assumes a reduced grammar; the generator rejects
        // nonterminals that derive no finite input.
        var g = try build(a, rules.items, &.{ "s", "a" });
        const costs = try repair.insertCosts(a, &g);
        const reduced = for (g.symbols.items, 0..) |x, i| {
            if (x.kind == .nonterminal and x.rules.items.len > 0 and costs[i] == repair.infinite) break false;
        } else true;
        if (!reduced) continue;
        const b = try generate(a, rules.items, &.{ "s", "a" });
        tested += 1;
        expectLalrMatchesCanonical(a, b) catch |err| {
            for (rules.items) |r| std.debug.print("  {s}\n", .{r});
            return err;
        };
    }
    try testing.expect(tested >= 100);
}

// =============================================================================
// Conflicts and the manifest
// =============================================================================

test "classifies shift and reduce conflicts; manifest text; shortest example" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const b = try generate(a, &.{
        "prog → stmt",
        "stmt → IF ID stmt",
        "stmt → IF ID stmt ELSE stmt",
        "stmt → val \";\"",
        "stmt → ref \";\"",
        "val → ID",
        "ref → ID",
    }, &.{"prog"});
    const entries = try conflicts.entries(a, &b.tbl);
    try testing.expectEqual(@as(usize, 2), entries.len);
    try testing.expectEqual(table.Conflict.Kind.shift, entries[0].kind);
    try testing.expectEqual(@as(u16, 1), entries[0].rule);
    try testing.expectEqual(table.Conflict.Kind.reduce, entries[1].kind);
    try testing.expectEqual(@as(u16, 5), entries[1].rule); // val → ID wins (lower rule)
    try testing.expectEqual(@as(u16, 6), entries[1].over);

    var out: std.Io.Writer.Allocating = .init(a);
    try conflicts.writeManifest(&out.writer, a, &b.g, entries, &.{});
    try testing.expectEqualStrings(
        \\@conflicts
        \\    shift  stmt → IF ID stmt       1  # <reason>
        \\    reduce val → ID over ref → ID  1  # <reason>
        \\
    , out.written());

    // The example reaches the dangling-else state; the start marker never shows.
    var sr: ?table.Conflict = null;
    for (b.tbl.conflictList) |c| {
        if (c.kind == .shift) sr = c;
    }
    out.clearRetainingCapacity();
    try conflicts.writeConflict(&out.writer, a, &b.g, &b.auto, sr.?);
    const text = out.written();
    try testing.expect(std.mem.find(u8, text, "example: IF ID stmt • ELSE\n") != null);
    try testing.expect(std.mem.find(u8, text, "stmt → IF ID stmt •   (reduce)") != null);
    try testing.expect(std.mem.find(u8, text, "stmt → IF ID stmt • ELSE stmt   (shift)") != null);
    try testing.expect(std.mem.find(u8, text, "prog!") == null);
}

test "manifest check: match, count change, winner flip, missing, undeclared" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const b = try generate(a, &.{
        "prog → stmt",
        "stmt → IF ID stmt",
        "stmt → IF ID stmt ELSE stmt",
        "stmt → val \";\"",
        "stmt → ref \";\"",
        "val → ID",
        "ref → ID",
    }, &.{"prog"});
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };
    const shift: grammar.ConflictEntry = .{ .kind = .shift, .rule = "stmt  ->  IF ID stmt", .count = 1, .reason = "dangling else" };
    const reduce: grammar.ConflictEntry = .{ .kind = .reduce, .rule = "val → ID", .over = "ref → ID", .count = 1, .reason = "values first" };

    b.g.conflicts = &.{ shift, reduce };
    try conflicts.check(a, &b.g, &b.auto, &b.tbl, opts);

    var changed = shift;
    changed.count = 2;
    b.g.conflicts = &.{ changed, reduce };
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
    try expectContains(sink.written(), "t.grammar:1:1: error: conflict count changed: 2 declared, 1 now: shift  stmt → IF ID stmt\n");
    // The pasteable manifest keeps the declared reasons.
    try expectContains(sink.written(), "    shift  stmt → IF ID stmt       1  # dangling else\n");
    sink.clearRetainingCapacity();

    var flipped = reduce;
    flipped.rule = "ref → ID";
    flipped.over = "val → ID";
    b.g.conflicts = &.{ shift, flipped };
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
    try expectContains(sink.written(), "winner flipped: declared ref → ID over val → ID, now reduce val → ID over ref → ID");
    sink.clearRetainingCapacity();

    b.g.conflicts = &.{shift};
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
    try expectContains(sink.written(), "undeclared conflict: reduce val → ID over ref → ID  (1)\n    state ");
    try expectContains(sink.written(), "      example: ID • \";\"\n");
    sink.clearRetainingCapacity();

    const extra: grammar.ConflictEntry = .{ .kind = .shift, .rule = "stmt → val \";\"", .count = 1, .reason = "gone" };
    b.g.conflicts = &.{ shift, reduce, extra };
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
    try expectContains(sink.written(), "declared conflict no longer occurs: shift stmt → val \";\"");

    // No manifest: the grammar must be conflict-free.
    b.g.conflicts = &.{};
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
}

test "hints resolve conflicts silently; X \"c\" records every character" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `>` keeps the shift, `<` takes the reduce; neither is a conflict.
    const shiftHint = try generate(a, &.{
        "prog → stmt",
        "stmt → IF ID stmt >",
        "stmt → IF ID stmt ELSE stmt",
        "stmt → ID",
    }, &.{"prog"});
    try testing.expectEqual(@as(u32, 0), shiftHint.tbl.conflicts);
    const q = try stateWith(&shiftHint.auto, 1, 3);
    try testing.expect(shiftHint.tbl.rows[q][sym(&shiftHint.g, "ELSE")] == .shift);

    const reduceHint = try generate(a, &.{
        "prog → stmt",
        "stmt → IF ID stmt <",
        "stmt → IF ID stmt ELSE stmt",
        "stmt → ID",
    }, &.{"prog"});
    try testing.expectEqual(@as(u32, 0), reduceHint.tbl.conflicts);
    try testing.expect(reduceHint.tbl.rows[try stateWith(&reduceHint.auto, 1, 3)][sym(&reduceHint.g, "ELSE")] == .reduce);

    // `name X "(" X "["`: both characters reduce in the table and record a
    // runtime shift override.
    const x = try generate(a, &.{
        "prog → e",
        "e → name X \"(\" X \"[\"",
        "e → name \"(\" \")\"",
        "e → name \"[\" \"]\"",
        "e → \"(\" e \")\"",
        "e → \"[\" e \"]\"",
        "e → e e",
        "name → ID",
    }, &.{"prog"});
    const xs = x.tbl.xExcludes.items;
    try testing.expectEqual(@as(usize, 2), xs.len);
    try testing.expectEqual(xs[0].state, xs[1].state);
    const st = xs[0].state;
    try testing.expectEqual(@as(u32, 0), x.tbl.xExcludeStart[st]);
    try testing.expectEqual(@as(u32, 2), x.tbl.xExcludeStart[st + 1]);
    try testing.expectEqual(@as(u32, 2), x.tbl.xExcludeStart[x.auto.states.items.len]);
    const syms = [2]u16{ xs[0].sym, xs[1].sym };
    try testing.expect(std.mem.findScalar(u16, &syms, sym(&x.g, "\"(\"")) != null);
    try testing.expect(std.mem.findScalar(u16, &syms, sym(&x.g, "\"[\"")) != null);
    for (xs) |e| try testing.expect(x.tbl.rows[e.state][e.sym] == .reduce);
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };
    try conflicts.checkHints(a, &x.g, &x.tbl, opts);

    // A hint that decides nothing is an error.
    const dead = try generate(a, &.{
        "prog → e \":\"",
        "e → name X \":\"",
        "e → name \"(\" \")\"",
        "name → ID",
    }, &.{"prog"});
    try testing.expectEqual(@as(usize, 0), dead.tbl.xExcludes.items.len);
    try testing.expectError(error.ConflictDrift, conflicts.checkHints(a, &dead.g, &dead.tbl, opts));
    try testing.expectEqualStrings(
        "t.grammar:1:1: error: X \":\" on e → name has no effect: it decides no shift/reduce conflict between this rule and \":\"; remove the hint\n",
        sink.written(),
    );
}

test "a hint names its literal terminal, escapes included; a missing literal is an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };

    // `X "\\"` names the terminal `"\\"`: after ID the table reduces on it,
    // and the runtime shifts a touching backslash instead.
    const esc = try generate(a, &.{
        "prog → es",
        "es → es e",
        "es → e",
        \\e → ID X "\\"
        ,
        \\e → ID "\\" ID
        ,
        \\e → "\\" ID
        ,
    }, &.{"prog"});
    try testing.expectEqual(@as(u32, 0), esc.tbl.conflicts);
    try testing.expectEqual(@as(usize, 1), esc.tbl.xExcludes.items.len);
    try testing.expectEqual(sym(&esc.g, "\"\\\\\""), esc.tbl.xExcludes.items[0].sym);
    try conflicts.checkHints(a, &esc.g, &esc.tbl, opts);

    // No literal "(" in the grammar: the hint names nothing.
    const missing = try generate(a, &.{
        "prog → es",
        "es → es e",
        "es → e",
        "e → ID X \"(\"",
        "e → ID LPAREN ID",
        "e → LPAREN ID",
    }, &.{"prog"});
    try testing.expectError(error.ConflictDrift, conflicts.checkHints(a, &missing.g, &missing.tbl, opts));
    try expectContains(sink.written(), "X \"(\" on e → ID names no terminal: the parser grammar has no literal \"(\"");
}

test "several `<` rules in one cell: the lowest reduces, the rest are reduce/reduce conflicts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const b = try generate(a, &.{
        "prog → es",
        "es → es e",
        "es → e",
        "e → p",
        "e → q",
        "p → ID <",
        "q → ID <",
        "e → ID \"(\" \")\"",
        "e → \"(\" e \")\"",
    }, &.{"prog"});
    const entries = try conflicts.entries(a, &b.tbl);
    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expectEqual(table.Conflict.Kind.reduce, entries[0].kind);
    try testing.expectEqual(@as(u16, 5), entries[0].rule); // p → ID
    try testing.expectEqual(@as(u16, 6), entries[0].over); // q → ID
    // On $end, ID and ")" nothing shifts; on "(" both beat the shift, p first.
    try testing.expectEqual(@as(u32, 4), entries[0].count);
    const s = b.tbl.conflictList[entries[0].first].state;
    try testing.expectEqual(table.ParseAction{ .reduce = 5 }, b.tbl.rows[s][sym(&b.g, "\"(\"")]);
}

test "a hint counts as used only where its rule wins the cell" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };
    // After ID, p and q both reduce on "(" against its shift; p, the lower
    // rule, wins by its hint, so q's hint decides nothing.
    const b = try generate(a, &.{
        "prog → es",
        "es → es e",
        "es → e",
        "e → p",
        "e → q",
        "p → ID X \"(\"",
        "q → ID X \"(\"",
        "e → ID \"(\" \")\"",
        "e → \"(\" e \")\"",
    }, &.{"prog"});
    try testing.expectError(error.ConflictDrift, conflicts.checkHints(a, &b.g, &b.tbl, opts));
    try testing.expectEqualStrings(
        "t.grammar:1:1: error: X \"(\" on q → ID has no effect: it decides no shift/reduce conflict between this rule and \"(\"; remove the hint\n",
        sink.written(),
    );
}

test "hints group by source alternative: line and column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };
    // `e = ID X "(" | NUM X "("` on one line: only ID's hint decides a cell.
    const b = try generate(a, &.{
        "prog → es",
        "es → es e",
        "es → e",
        "e → ID X \"(\"",
        "e → NUM X \"(\"",
        "e → ID \"(\" e \")\"",
        "e → \"(\" e \")\"",
    }, &.{"prog"});
    for (b.g.rules.items[3..5], [_]u32{ 8, 20 }) |*r, col| {
        r.line = 7;
        r.col = col;
    }
    try testing.expectError(error.ConflictDrift, conflicts.checkHints(a, &b.g, &b.tbl, opts));
    try testing.expectEqualStrings(
        "t.grammar:7:20: error: X \"(\" on e → NUM has no effect: it decides no shift/reduce conflict between this rule and \"(\"; remove the hint\n",
        sink.written(),
    );
    // Rules expanded from one alternative (one line and column) share it.
    b.g.rules.items[4].col = 8;
    try conflicts.checkHints(a, &b.g, &b.tbl, opts);
}

test "a start marker adds no conflicts and every start alternative is reachable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rules = [_][]const u8{
        "program → forms",
        "forms → forms form",
        "forms → form",
        "forms → ε",
        "form → ID",
        "form → \"(\" forms \")\"",
    };
    const one = try generate(a, &rules, &.{"program"});
    const two = try generate(a, &rules, &.{ "program", "form" });
    try testing.expectEqual(one.tbl.conflicts, two.tbl.conflicts);
    // From form's entry state (after the injected marker), both of form's
    // rules can start.
    const entry = try stateWith(&two.auto, two.g.acceptRules.items[1], 1);
    try testing.expect(two.tbl.rows[entry][sym(&two.g, "ID")] == .shift);
    try testing.expect(two.tbl.rows[entry][sym(&two.g, "\"(\"")] == .shift);
}

test "manifest rule texts normalize arrows, blanks and empty right-hand sides" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("a → b", try conflicts.normalize(a, " a  ->   b "));
    try testing.expectEqualStrings("a → ε", try conflicts.normalize(a, "a ->"));
    try testing.expectEqualStrings("L(x, \";\") → x L(x, \";\").tail", try conflicts.normalize(a, "L(x, \";\")  ->  x L(x, \";\").tail"));
    // Quoted text is kept as written: `->`, blank runs, escaped quotes.
    try testing.expectEqualStrings("s → IF \"->\" s", try conflicts.normalize(a, "s ->  IF \"->\"  s"));
    try testing.expectEqualStrings("s → \"a  b\" \"\\\"->\" X", try conflicts.normalize(a, "s -> \"a  b\" \"\\\"->\"   X"));
}

test "a manifest entry naming a literal with `->` or blanks matches its rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const b = try generate(a, &.{
        "prog → stmt",
        "stmt → IF ID \"->\" stmt",
        "stmt → IF ID \"->\" stmt ELSE stmt",
        "stmt → ID",
    }, &.{"prog"});
    var sink: std.Io.Writer.Allocating = .init(a);
    const opts: conflicts.Options = .{ .path = "t.grammar", .out = &sink.writer };
    b.g.conflicts = &.{.{ .kind = .shift, .rule = "stmt -> IF ID \"->\" stmt", .count = 1, .reason = "dangling else" }};
    try conflicts.check(a, &b.g, &b.auto, &b.tbl, opts);
    b.g.conflicts = &.{.{ .kind = .shift, .rule = "stmt → IF ID \"→\" stmt", .count = 1, .reason = "dangling else" }};
    try testing.expectError(error.ConflictDrift, conflicts.check(a, &b.g, &b.auto, &b.tbl, opts));
}

// =============================================================================
// Grammar and table checks
// =============================================================================

test "only the causes of unproductive rules are reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // b needs itself; bs, top and the accept rule fail only through b.
    var g = try build(a, &.{ "top → Y bs", "bs → b", "bs → bs b", "b → Y b" }, &.{"top"});
    try testing.expectEqualSlices(u16, &.{sym(&g, "b")}, try lr.unproductiveRoots(a, &g, try repair.insertCosts(a, &g)));
    // a and c need each other: both are the cause.
    g = try build(a, &.{ "top → a", "a → W c", "c → Y a", "c → Y a Z" }, &.{"top"});
    try testing.expectEqualSlices(u16, &.{ sym(&g, "a"), sym(&g, "c") }, try lr.unproductiveRoots(a, &g, try repair.insertCosts(a, &g)));
    // One alternative that completes is enough.
    g = try build(a, &.{ "top → a", "a → W a", "a → Y" }, &.{"top"});
    try testing.expectEqual(@as(usize, 0), (try lr.unproductiveRoots(a, &g, try repair.insertCosts(a, &g))).len);
}

test "a cycle of unit derivations is found through nullable neighbors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // a ⇒ b (opt is nullable) ⇒ a.
    var g = try build(a, &.{ "top → a", "a → b opt", "a → Y", "b → opt a", "opt → Z", "opt → ε" }, &.{"top"});
    const cycle = (try lr.findCycle(a, &g, try repair.insertCosts(a, &g))).?;
    try testing.expectEqual(@as(usize, 2), cycle.len);
    try testing.expectEqual(sym(&g, "a"), g.rules.items[cycle[0]].lhs);
    try testing.expectEqual(sym(&g, "b"), g.rules.items[cycle[1]].lhs);
    // A neighbor that must consume input breaks the cycle.
    g = try build(a, &.{ "top → a", "a → b W", "a → Y", "b → opt a", "opt → Z", "opt → ε" }, &.{"top"});
    try testing.expectEqual(@as(?[]const u16, null), try lr.findCycle(a, &g, try repair.insertCosts(a, &g)));
    // A deep chain of unit rules is searched without recursion.
    var rules: std.ArrayList([]const u8) = .empty;
    try rules.append(a, "top → n0");
    for (0..20000) |i| try rules.append(a, try a.print("n{d} → n{d}", .{ i, i + 1 }));
    try rules.append(a, "n20000 → Y");
    g = try build(a, rules.items, &.{"top"});
    try testing.expectEqual(@as(?[]const u16, null), try lr.findCycle(a, &g, try repair.insertCosts(a, &g)));
}

test "a synthesized rule is located where a written rule uses it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var g = try build(a, &.{ "top → Y bs", "bs → b", "bs → bs b", "b → Y" }, &.{"top"});
    g.rules.items[0].line = 3;
    g.rules.items[0].col = 7;
    g.rules.items[3].line = 4;
    g.rules.items[3].col = 5;
    try testing.expectEqual(conflicts.Loc{ .line = 3, .col = 7 }, conflicts.ruleLoc(&g, 2)); // bs, via top
    try testing.expectEqual(conflicts.Loc{ .line = 4, .col = 5 }, conflicts.ruleLoc(&g, 3));
    try testing.expectEqual(conflicts.Loc{ .line = 1, .col = 1 }, conflicts.ruleLoc(&g, g.acceptRules.items[0]));
}

test "an endless reduce chain is found through empty and unit reductions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `<` makes b → ε win over shifting Y. Reducing it leads (through the
    // unit rules d → e → b, when present) back to a state on the stack.
    const chains = [_][]const []const u8{
        &.{ "top → a", "a → b a C", "a → Y", "b → ε <" },
        &.{ "top → a", "a → d a C", "a → Y", "d → b", "b → ε <" },
        &.{ "top → a", "a → d a C", "a → Y", "d → e", "e → b", "b → ε <" },
    };
    for (chains) |rules| {
        const b = try generate(a, rules, &.{"top"});
        const loop = (try lr.emptyLoop(a, &b.g, &b.tbl)).?;
        try testing.expectEqual(sym(&b.g, "b"), b.g.rules.items[loop.rule].lhs);
        try testing.expectEqual(sym(&b.g, "Y"), loop.terminal);
    }
    // Without the hint Y shifts, and every chain ends.
    const fine = try generate(a, &.{ "top → a", "a → d a C", "a → Y", "d → b", "b → ε" }, &.{"top"});
    try testing.expectEqual(@as(?lr.EmptyLoop, null), try lr.emptyLoop(a, &fine.g, &fine.tbl));
    // An empty reduction that a non-empty one completes ends too.
    const list = try generate(a, &.{ "top → items", "items → items item", "items → ε", "item → Y" }, &.{"top"});
    try testing.expectEqual(@as(?lr.EmptyLoop, null), try lr.emptyLoop(a, &list.g, &list.tbl));
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("missing:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

// =============================================================================
// Expected sets and repair
// =============================================================================

test "expected sets name @errors nonterminals, then remaining terminals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rules = [_][]const u8{
        "prog → \"(\" args \")\"",
        "args → expr",
        "args → args \",\" expr",
        "args → ε",
        "expr → ID",
        "expr → NUM",
    };
    var b = try generate(a, &rules, &.{"prog"});
    const q = try stateWith(&b.auto, 0, 1); // prog → "(" • args ")"
    // Without names: every terminal with an action.
    const plain = b.tbl.expected.forState(q);
    try testing.expectEqualSlices(u16, &.{ sym(&b.g, "\")\""), sym(&b.g, "\",\""), sym(&b.g, "ID"), sym(&b.g, "NUM") }, sortedCopy(a, plain));

    b.g.errorNames = &.{.{ .rule = "expr", .name = "an expression" }};
    b.tbl = try table.build(&b.g, &b.auto, b.la);
    try testing.expectEqualSlices(u16, &.{ sym(&b.g, "expr"), sym(&b.g, "\")\""), sym(&b.g, "\",\"") }, b.tbl.expected.forState(q));
    // Lists are shared: fewer lists than states.
    try testing.expect(b.tbl.expected.numLists() < b.auto.states.items.len);
    // Start markers never appear.
    for (b.tbl.expected.symbols) |s| try testing.expect(!table.isStartMarker(&b.g, s));
}

fn sortedCopy(a: Allocator, xs: []const u16) []u16 {
    const c = a.dupe(u16, xs) catch unreachable;
    std.mem.sort(u16, c, {}, std.sort.asc(u16));
    return c;
}

test "repair candidates: holes before structure, then fewest fabrications, then id" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var g = try build(a, &.{
        "prog → stmts",
        "stmts → stmts stmt",
        "stmts → stmt",
        "stmt → call NEWLINE",
        "stmt → ID \"=\" ID ID NEWLINE",
        "call → ID \"(\" args \")\"",
        "args → ID",
        "args → args \",\" ID",
    }, &.{"prog"});
    const auto = try automaton.build(&g);
    const la = try lookahead.compute(&g, &auto, try repair.insertCosts(a, &g));

    const costs = la.costs;
    try testing.expectEqual(@as(u32, 1), costs[sym(&g, "args")]);
    try testing.expectEqual(@as(u32, 4), costs[sym(&g, "call")]);
    try testing.expectEqual(@as(u32, 5), costs[sym(&g, "stmt")]);

    g.repair = .{ .holes = &.{"ID"}, .structure = &.{"\")\""}, .terminators = &.{"NEWLINE"} };
    const tbl = try table.build(&g, &auto, la);
    const rep = tbl.repair.?;
    // After `ID "(" args`: `)` closes the call (structure).
    const afterArgs = try stateWith(&auto, 5, 3);
    try testing.expectEqualSlices(u16, &.{sym(&g, "\")\"")}, rep.forState(afterArgs));
    // After `ID "(" args ","`: the hole ID comes first.
    const afterComma = try stateWith(&auto, 7, 2);
    try testing.expectEqualSlices(u16, &.{sym(&g, "ID")}, rep.forState(afterComma));
    // Further fabrications an inserted ID commits to: in `ID "=" •` the rest
    // `ID NEWLINE` (2); in `ID "=" ID •`, NEWLINE (1).
    const eq1 = try stateWith(&auto, 4, 2);
    try testing.expectEqual(@as(u32, 2), repair.costAt(&g, la, auto.states.items[eq1], sym(&g, "ID")));
    const eq2 = try stateWith(&auto, 4, 3);
    try testing.expectEqual(@as(u32, 1), repair.costAt(&g, la, auto.states.items[eq2], sym(&g, "ID")));

    // Names must be tokens of the parser grammar.
    try testing.expect(repair.validate(&g, .{ .holes = &.{"NOPE"}, .structure = &.{} }) != null);
    try testing.expect(repair.validate(&g, .{ .holes = &.{"args"}, .structure = &.{} }) != null);
    try testing.expect(repair.validate(&g, .{ .holes = &.{"ID"}, .structure = &.{"ID"} }) != null);
    try testing.expect(repair.validate(&g, .{ .holes = &.{"ID"}, .structure = &.{"NEWLINE"} }) == null);
    try testing.expect(repair.validate(&g, .{ .holes = &.{"ID"}, .structure = &.{}, .terminators = &.{"ID"} }) != null);
}

test "ranking puts holes above cheaper structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // After `f "(" ID ","` both a hole (ID, then `)` still needed) and, via
    // the optional trailing comma, `)` (structure, nothing more needed) fit.
    var g = try build(a, &.{
        "prog → call",
        "call → ID \"(\" args \")\"",
        "call → ID \"(\" args \",\" \")\"",
        "args → ID",
        "args → args \",\" ID",
    }, &.{"prog"});
    const auto = try automaton.build(&g);
    const la = try lookahead.compute(&g, &auto, try repair.insertCosts(a, &g));
    g.repair = .{ .holes = &.{"ID"}, .structure = &.{"\")\""} };
    const tbl = try table.build(&g, &auto, la);
    const q = try stateWith(&auto, 2, 4);
    try testing.expectEqualSlices(u16, &.{ sym(&g, "ID"), sym(&g, "\")\"") }, tbl.repair.?.forState(q));
}
