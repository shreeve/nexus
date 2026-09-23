//! The conflict manifest (`@conflicts`): classifies every unresolved
//! conflict, compares the result with the grammar's declared manifest, and
//! on any drift fails generation with a report (state, items, and a shortest
//! input prefix reaching the state) and the actual manifest, ready to paste.
//!
//! A manifest entry is one (kind, rule[, over]) with the number of table
//! cells (state, terminal) it covers:
//!
//!     shift  <rule>                 N  # reason   a reduction that lost to the default shift
//!     reduce <winner> over <loser>  N  # reason   a reduction dropped for a lower-numbered rule
//!
//! Rules are written `lhs → rhs` over the desugared grammar (see `ruleText`).
//! Conflicts that `<`, `>`, or `X "c"` hints resolve are not conflicts.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const ConflictEntry = grammar.ConflictEntry;
const Automaton = @import("automaton.zig").Automaton;
const Item = @import("automaton.zig").Item;
const table = @import("table.zig");
const Table = table.Table;
const Conflict = table.Conflict;

/// One aggregated manifest entry of the actual grammar.
pub const Entry = struct {
    kind: Conflict.Kind,
    rule: u16,
    over: u16 = 0,
    count: u32,
    /// Index of the first conflict of this entry in `Table.conflictList`.
    first: u32,
};

/// Aggregate the table's conflicts into manifest entries, ordered by kind
/// (shift first), then rule, then `over`.
pub fn entries(a: Allocator, tbl: *const Table) ![]Entry {
    var list: std.ArrayListUnmanaged(Entry) = .empty;
    for (tbl.conflictList, 0..) |c, ci| {
        const over: u16 = if (c.kind == .reduce) c.over else 0;
        for (list.items) |*e| {
            if (e.kind == c.kind and e.rule == c.rule and e.over == over) {
                e.count += 1;
                break;
            }
        } else try list.append(a, .{ .kind = c.kind, .rule = c.rule, .over = over, .count = 1, .first = @intCast(ci) });
    }
    std.mem.sort(Entry, list.items, {}, struct {
        fn lessThan(_: void, x: Entry, y: Entry) bool {
            if (x.kind != y.kind) return @intFromEnum(x.kind) < @intFromEnum(y.kind);
            if (x.rule != y.rule) return x.rule < y.rule;
            return x.over < y.over;
        }
    }.lessThan);
    return list.toOwnedSlice(a);
}

// =============================================================================
// Rule and symbol text
// =============================================================================

/// A symbol as the grammar author wrote it. Symbols the desugarer
/// synthesized print in source syntax, built from their rules (never from
/// the numeric ids in their internal names): `X?`, `X*`, `X+`, `L(X)`,
/// `L(X?)`, `L(X, sep)`, `L(X).tail` (a list's repetition), and `(A B)` for a
/// group.
pub fn writeSymbol(w: *std.Io.Writer, g: *const Grammar, sym: u16) std.Io.Writer.Error!void {
    const s = &g.symbols.items[sym];
    const name = s.name;
    if (s.kind == .nonterminal and name.len > 0 and name[0] == '_') {
        const rules = s.rules.items;
        const rhsOf = struct {
            fn f(gg: *const Grammar, r: u16) []const u16 {
                return gg.rules.items[r].rhs;
            }
        }.f;
        if (std.mem.startsWith(u8, name, "_opt_") and rules.len == 2) {
            try writeSymbol(w, g, rhsOf(g, rules[0])[0]);
            return w.writeByte('?');
        }
        if (std.mem.startsWith(u8, name, "_star_") and rules.len == 2) {
            try writeSymbol(w, g, rhsOf(g, rules[0])[0]);
            return w.writeByte('*');
        }
        if (std.mem.startsWith(u8, name, "_plus_") and rules.len == 1) {
            try writeSymbol(w, g, rhsOf(g, rules[0])[0]);
            return w.writeByte('+');
        }
        if (std.mem.startsWith(u8, name, "_list_") and rules.len == 1) {
            // _list → item _tail;  _tail → sep item _tail | ε
            const rhs = rhsOf(g, rules[0]);
            try writeList(w, g, rhs[0], rhs[1]);
            return;
        }
        if (std.mem.startsWith(u8, name, "_tail_") and rules.len == 2) {
            const rhs = rhsOf(g, rules[0]);
            try writeList(w, g, rhs[1], sym);
            return w.writeAll(".tail");
        }
        if (std.mem.startsWith(u8, name, "_grp_") and rules.len == 1) {
            try w.writeByte('(');
            try writeSeq(w, g, rhsOf(g, rules[0]));
            return w.writeByte(')');
        }
    }
    try w.writeAll(name);
}

fn writeList(w: *std.Io.Writer, g: *const Grammar, item: u16, tail: u16) !void {
    const sep = g.rules.items[g.symbols.items[tail].rules.items[0]].rhs[0];
    try w.writeAll("L(");
    try writeSymbol(w, g, item);
    if (!std.mem.eql(u8, g.symbols.items[sep].name, "\",\"")) {
        try w.writeAll(", ");
        try writeSymbol(w, g, sep);
    }
    try w.writeByte(')');
}

/// Symbols separated by spaces, start markers omitted.
fn writeSeq(w: *std.Io.Writer, g: *const Grammar, seq: []const u16) !void {
    var first = true;
    for (seq) |s| {
        if (table.isStartMarker(g, s)) continue;
        if (!first) try w.writeByte(' ');
        first = false;
        try writeSymbol(w, g, s);
    }
}

/// `lhs → rhs` (`lhs → ε` for an empty rule); the text manifest entries use.
pub fn writeRule(w: *std.Io.Writer, g: *const Grammar, ruleId: u16) !void {
    const rule = &g.rules.items[ruleId];
    try writeSymbol(w, g, rule.lhs);
    try w.writeAll(" →");
    var any = false;
    for (rule.rhs) |s| {
        if (!table.isStartMarker(g, s)) any = true;
    }
    try w.writeByte(' ');
    if (any) try writeSeq(w, g, rule.rhs) else try w.writeAll("ε");
}

pub fn ruleText(a: Allocator, g: *const Grammar, ruleId: u16) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    try writeRule(&out.writer, g, ruleId);
    return out.toOwnedSlice();
}

/// An item `lhs → α • β`.
fn writeItem(w: *std.Io.Writer, g: *const Grammar, item: Item) !void {
    const rule = &g.rules.items[item.ruleId];
    try writeSymbol(w, g, rule.lhs);
    try w.writeAll(" →");
    for (rule.rhs, 0..) |s, i| {
        if (i == item.dot) try w.writeAll(" •");
        if (table.isStartMarker(g, s)) continue;
        try w.writeByte(' ');
        try writeSymbol(w, g, s);
    }
    if (item.dot == rule.rhs.len) try w.writeAll(" •");
}

/// Rule text normalized for comparison: `->` is `→`, whitespace runs are one
/// space, an empty right-hand side is `ε`.
pub fn normalize(a: Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    var pendingSpace = false;
    while (i < text.len) {
        const c = text[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            pendingSpace = out.items.len > 0;
            i += 1;
            continue;
        }
        if (pendingSpace) try out.append(a, ' ');
        pendingSpace = false;
        if (c == '-' and i + 1 < text.len and text[i + 1] == '>') {
            try out.appendSlice(a, "→");
            i += 2;
            continue;
        }
        try out.append(a, c);
        i += 1;
    }
    if (std.mem.endsWith(u8, out.items, "→")) try out.appendSlice(a, " ε");
    return out.toOwnedSlice(a);
}

// =============================================================================
// Shortest example: a viable prefix reaching a state
// =============================================================================

/// The shortest symbol path from any start state to `target` (BFS over the
/// automaton's transitions), start markers omitted.
pub fn shortestPrefix(a: Allocator, g: *const Grammar, auto: *const Automaton, target: u16) ![]u16 {
    const n = auto.states.items.len;
    const none = std.math.maxInt(u16);
    const parent = try a.alloc(u16, n);
    defer a.free(parent);
    const via = try a.alloc(u16, n);
    defer a.free(via);
    @memset(parent, none);
    const seen = try a.alloc(bool, n);
    defer a.free(seen);
    @memset(seen, false);

    var queue: std.ArrayListUnmanaged(u16) = .empty;
    defer queue.deinit(a);
    for (auto.startStates.items) |s| {
        if (!seen[s]) {
            seen[s] = true;
            try queue.append(a, s);
        }
    }
    var head: usize = 0;
    while (head < queue.items.len and !seen[target]) : (head += 1) {
        const s = queue.items[head];
        for (auto.states.items[s].transitions) |t| {
            if (seen[t.target]) continue;
            seen[t.target] = true;
            parent[t.target] = s;
            via[t.target] = t.symbol;
            try queue.append(a, t.target);
        }
    }

    var path: std.ArrayListUnmanaged(u16) = .empty;
    var s = target;
    while (parent[s] != none) : (s = parent[s]) {
        if (!table.isStartMarker(g, via[s])) try path.append(a, via[s]);
    }
    std.mem.reverse(u16, path.items);
    return path.toOwnedSlice(a);
}

// =============================================================================
// Reports
// =============================================================================

/// Print one conflict: its state, the items involved, and an example.
pub fn writeConflict(w: *std.Io.Writer, a: Allocator, g: *const Grammar, auto: *const Automaton, c: Conflict) !void {
    const state = &auto.states.items[c.state];
    try w.print("    state {d}, on ", .{c.state});
    try writeSymbol(w, g, c.terminal);
    try w.writeByte('\n');
    for (state.items) |item| {
        const rule = &g.rules.items[item.ruleId];
        const involved = if (item.dot == rule.rhs.len)
            item.ruleId == c.rule or (c.kind == .reduce and item.ruleId == c.over)
        else
            c.kind == .shift and rule.rhs[item.dot] == c.terminal;
        if (!involved) continue;
        try w.writeAll("      ");
        try writeItem(w, g, item);
        try w.writeAll(if (item.dot == rule.rhs.len) "   (reduce)\n" else "   (shift)\n");
    }
    const prefix = try shortestPrefix(a, g, auto, c.state);
    defer a.free(prefix);
    try w.writeAll("      example: ");
    try writeSeq(w, g, prefix);
    if (prefix.len > 0) try w.writeByte(' ');
    try w.writeAll("• ");
    try writeSymbol(w, g, c.terminal);
    try w.writeByte('\n');
}

/// The manifest line of an entry, without the reason.
fn writeEntryHead(w: *std.Io.Writer, g: *const Grammar, e: Entry) !void {
    try w.writeAll(if (e.kind == .shift) "shift  " else "reduce ");
    try writeRule(w, g, e.rule);
    if (e.kind == .reduce) {
        try w.writeAll(" over ");
        try writeRule(w, g, e.over);
    }
}

/// The actual manifest, ready to paste; reasons are carried over from the
/// declared entries that still match.
pub fn writeManifest(w: *std.Io.Writer, a: Allocator, g: *const Grammar, actual: []const Entry, declared: []const ConflictEntry) !void {
    var heads: std.ArrayListUnmanaged([]const u8) = .empty;
    defer heads.deinit(a);
    var width: usize = 0;
    for (actual) |e| {
        var out: std.Io.Writer.Allocating = .init(a);
        try writeEntryHead(&out.writer, g, e);
        const h = try out.toOwnedSlice();
        width = @max(width, columns(h));
        try heads.append(a, h);
    }
    try w.writeAll("@conflicts\n");
    for (actual, heads.items) |e, h| {
        const reason = for (declared) |d| {
            if (try matches(a, g, d, e)) break d.reason;
        } else "<reason>";
        try w.print("    {s}", .{h});
        try w.splatByteAll(' ', width - columns(h) + 2);
        try w.print("{d}  # {s}\n", .{ e.count, reason });
    }
}

/// Display width of UTF-8 text (one column per code point).
fn columns(text: []const u8) usize {
    var n: usize = 0;
    for (text) |b| {
        if (b & 0xC0 != 0x80) n += 1;
    }
    return n;
}

/// Whether a declared entry names the same conflict as an actual one
/// (count aside).
fn matches(a: Allocator, g: *const Grammar, d: ConflictEntry, e: Entry) !bool {
    if (@intFromEnum(d.kind) != @intFromEnum(e.kind)) return false;
    if (!try sameRule(a, g, d.rule, e.rule)) return false;
    if (e.kind == .reduce) {
        const over = d.over orelse return false;
        if (!try sameRule(a, g, over, e.over)) return false;
    }
    return true;
}

fn sameRule(a: Allocator, g: *const Grammar, text: []const u8, ruleId: u16) !bool {
    const want = try normalize(a, text);
    defer a.free(want);
    const have = try ruleText(a, g, ruleId);
    defer a.free(have);
    return std.mem.eql(u8, want, have);
}

pub const Options = struct {
    /// The grammar file, for located messages.
    path: []const u8,
    /// Where reports go; null = stderr.
    out: ?*std.Io.Writer = null,

    fn emit(self: Options, text: []const u8) !void {
        if (self.out) |w| try w.writeAll(text) else std.debug.print("{s}", .{text});
    }
};

pub const CheckError = error{ ConflictDrift, OutOfMemory, WriteFailed };

/// Compare the actual conflicts with the grammar's declaration and fail on
/// any drift. The declaration is the `@conflicts` manifest when present;
/// otherwise the legacy `@conflicts = N` total; otherwise "no conflicts".
pub fn check(a: Allocator, g: *const Grammar, auto: *const Automaton, tbl: *const Table, opts: Options) CheckError!void {
    const actual = try entries(a, tbl);
    defer a.free(actual);

    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    const w = &out.writer;
    var drift = false;

    if (g.conflicts.len > 0) {
        // Declared entries, each matched to at most one actual entry.
        const taken = try a.alloc(bool, actual.len);
        defer a.free(taken);
        @memset(taken, false);
        for (g.conflicts) |d| {
            const found: ?usize = for (actual, 0..) |e, i| {
                if (!taken[i] and try matches(a, g, d, e)) break i;
            } else null;
            if (found) |i| {
                taken[i] = true;
                if (actual[i].count != d.count) {
                    drift = true;
                    try located(w, opts.path, d.line);
                    try w.print("conflict count changed: {d} declared, {d} now: ", .{ d.count, actual[i].count });
                    try writeEntryHead(w, g, actual[i]);
                    try w.writeByte('\n');
                    try writeConflict(w, a, g, auto, tbl.conflictList[actual[i].first]);
                }
                continue;
            }
            drift = true;
            // A reduce entry whose winner and loser swapped is a flip.
            const flipped: ?usize = if (d.kind == .reduce) for (actual, 0..) |e, i| {
                if (taken[i] or e.kind != .reduce) continue;
                if (try sameRule(a, g, d.rule, e.over) and try sameRule(a, g, d.over orelse "", e.rule)) break i;
            } else null else null;
            try located(w, opts.path, d.line);
            if (flipped) |i| {
                taken[i] = true;
                try w.print("reduce/reduce winner flipped: declared {s} over {s}, now ", .{ d.rule, d.over.? });
                try writeEntryHead(w, g, actual[i]);
                try w.writeByte('\n');
                try writeConflict(w, a, g, auto, tbl.conflictList[actual[i].first]);
            } else {
                try w.print("declared conflict no longer occurs: {s} {s}", .{ @tagName(d.kind), d.rule });
                if (d.over) |o| try w.print(" over {s}", .{o});
                try w.writeByte('\n');
            }
        }
        for (actual, 0..) |e, i| {
            if (taken[i]) continue;
            drift = true;
            try located(w, opts.path, 0);
            try w.writeAll("undeclared conflict: ");
            try writeEntryHead(w, g, e);
            try w.print("  ({d})\n", .{e.count});
            try writeConflict(w, a, g, auto, tbl.conflictList[e.first]);
        }
    } else if (g.expectConflicts) |n| {
        if (tbl.conflicts != n) {
            drift = true;
            try located(w, opts.path, 0);
            try w.print("{d} conflicts, but @conflicts = {d}\n", .{ tbl.conflicts, n });
        }
    } else if (actual.len > 0) {
        drift = true;
        for (actual) |e| {
            try located(w, opts.path, 0);
            try w.writeAll("undeclared conflict: ");
            try writeEntryHead(w, g, e);
            try w.print("  ({d})\n", .{e.count});
            try writeConflict(w, a, g, auto, tbl.conflictList[e.first]);
        }
    }

    if (!drift) return;
    try w.writeAll("the grammar's conflicts are now:\n\n");
    try writeManifest(w, a, g, actual, g.conflicts);
    try opts.emit(out.written());
    return error.ConflictDrift;
}

/// `path:line:1: error: ` (or `path: error: ` without a line).
fn located(w: *std.Io.Writer, path: []const u8, line: u32) !void {
    if (line > 0) try w.print("{s}:{d}:1: error: ", .{ path, line }) else try w.print("{s}: error: ", .{path});
}

/// Fail on `X "c"` hints that decide nothing: in no state does the rule's
/// reduction on the character's terminal meet a shift. (The LR(1)
/// lookaheads already separate the cases, so the hint has no effect.)
/// Hints are grouped by source alternative (lhs and line), so a hint that
/// applies to any rule expanded from its alternative counts as used.
pub fn checkHints(a: Allocator, g: *const Grammar, tbl: *const Table, opts: Options) CheckError!void {
    var failed = false;
    for (tbl.hints, 0..) |h, i| {
        if (h.used) continue;
        const rule = &g.rules.items[h.rule];
        // Report each (alternative, char) once, and only if no sibling used it.
        const dup = for (tbl.hints[0..i]) |o| {
            const orule = &g.rules.items[o.rule];
            if (o.char == h.char and orule.lhs == rule.lhs and orule.line == rule.line) break true;
        } else false;
        if (dup) continue;
        const siblingUsed = for (tbl.hints) |o| {
            const orule = &g.rules.items[o.rule];
            if (o.used and o.char == h.char and orule.lhs == rule.lhs and orule.line == rule.line) break true;
        } else false;
        if (siblingUsed) continue;

        failed = true;
        var out: std.Io.Writer.Allocating = .init(a);
        defer out.deinit();
        try located(&out.writer, opts.path, rule.line);
        try out.writer.print("X \"{c}\" on ", .{h.char});
        try writeRule(&out.writer, g, h.rule);
        try out.writer.print(" has no effect: no state has a shift/reduce conflict between this rule and \"{c}\"; remove the hint\n", .{h.char});
        try opts.emit(out.written());
    }
    if (failed) return error.ConflictDrift;
}
