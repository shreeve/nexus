//! Action codegen: compiles a rule's action tree (grammar.ActionTree) into
//! the Zig expression `executeAction` returns for it, and collects the tags
//! actions use (for the auto-extracted Tag enum).
//!
//! Two modes. Without a schema, lists drop trailing nils (at run time) and
//! the 0.10 fast paths are kept byte for byte, including their choices:
//! `(tag ...N)` is `sexpSpread`, `(tag M ...N)` and `(tag ...N M)` are
//! `sexpPosSpread` with M first. With a schema, every list has exactly the
//! items its action places (fixed length, nils kept), in order.
//!
//! The emitted code touches the Sexp list representation only through the
//! helpers in the "Runtime surface" section at the bottom.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
const Rule = grammar.Rule;
const ActionTree = grammar.ActionTree;
const ActionList = grammar.ActionList;
const ActionElem = grammar.ActionElem;

/// Tags referenced by actions (heads and child tag literals, nested lists
/// included), in first-seen order over the rules.
pub const TagSet = struct {
    map: std.StringHashMapUnmanaged(u16) = .empty,
    list: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn collect(self: *TagSet, allocator: Allocator, rules: []const Rule) !void {
        for (rules) |rule| {
            const tree = rule.actionTree orelse continue;
            switch (tree) {
                .list => |l| try self.collectList(allocator, l),
                else => {},
            }
        }
    }

    fn collectList(self: *TagSet, allocator: Allocator, l: ActionList) !void {
        switch (l.head) {
            .tag => |t| try self.register(allocator, t),
            else => {},
        }
        for (l.items) |item| switch (item.elem) {
            .tagLit => |t| try self.register(allocator, t),
            .node => |n| try self.collectList(allocator, n.*),
            else => {},
        };
    }

    fn register(self: *TagSet, allocator: Allocator, tag: []const u8) !void {
        if (!self.map.contains(tag)) {
            const owned = try allocator.dupe(u8, tag);
            try self.map.put(allocator, owned, @intCast(self.list.items.len));
            try self.list.append(allocator, owned);
        }
    }
};

/// Per symbol: whether its value can reach the tree, as opposed to only
/// being spread into another list (or dropped). A value reaches the tree
/// when it is the result of a start symbol, an item or head of a list
/// (a list's items stay items when the list is spread into another), or
/// passed through (`→ N`, or the one element of a default action) by a
/// rule whose own value reaches the tree. An untagged list built by a rule
/// whose left-hand side never reaches the tree is plumbing: it needs no
/// node id (nothing can ask for its span).
pub fn treeSymbols(allocator: Allocator, g: *const Grammar) ![]bool {
    const tree = try allocator.alloc(bool, g.symbols.items.len);
    @memset(tree, false);
    for (g.startSymbols.items) |s| tree[s] = true;
    for (g.rules.items) |rule| {
        const action = rule.actionTree orelse {
            if (rule.rhs.len > 1) for (rule.rhs) |s| {
                tree[s] = true;
            };
            continue;
        };
        switch (action) {
            .list => |l| markItems(tree, rule, l),
            else => {},
        }
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (g.rules.items) |rule| {
            if (!tree[rule.lhs]) continue;
            const pos: ?u16 = if (rule.actionTree) |action| switch (action) {
                .pass => |p| p,
                else => null,
            } else if (rule.rhs.len == 1) 1 else null;
            const p = pos orelse continue;
            const s = rule.rhs[p - 1];
            if (!tree[s]) {
                tree[s] = true;
                changed = true;
            }
        }
    }
    return tree;
}

fn markItems(tree: []bool, rule: Rule, l: ActionList) void {
    switch (l.head) {
        .ref => |h| markElem(tree, rule, h),
        else => {},
    }
    for (l.items) |item| markElem(tree, rule, item.elem);
}

fn markElem(tree: []bool, rule: Rule, e: ActionElem) void {
    switch (e) {
        .ref => |p| tree[rule.rhs[p - 1]] = true,
        .node => |n| markItems(tree, rule, n.*),
        .spread, .symId, .nil, .tagLit => {},
    }
}

/// Emit the Zig expression for `rule`'s action. `reachesTree` is whether
/// the rule's value can reach the tree (see `treeSymbols`).
pub fn generateRuleAction(allocator: Allocator, writer: anytype, g: *const Grammar, rule: Rule, reachesTree: bool) !void {
    var e = Emitter{ .allocator = allocator, .fixed = g.schema != null, .use = if (reachesTree) ".tree" else ".spread" };
    const tree = rule.actionTree orelse {
        // Default: nothing, the one element, or an untagged list.
        if (rule.rhs.len == 0) return writer.writeAll(".nil");
        if (rule.rhs.len == 1) return writer.writeAll("pass[0]");
        return writer.print("self.list(pass, {s})", .{e.use});
    };
    switch (tree) {
        .nil => try writer.writeAll(".nil"),
        .pass => |p| try writer.print("pass[{d}]", .{Emitter.index(p)}),
        .list => |l| try e.list(writer, l, "blk"),
    }
}

const Emitter = struct {
    allocator: Allocator,
    /// Schema mode: fixed-length lists, no trailing-nil stripping.
    fixed: bool,
    /// Counter for the labels of nested list blocks.
    depth: usize = 0,
    /// The `ListUse` of the rule's own untagged list (`.tree` or
    /// `.spread`); nested lists always reach the tree.
    use: []const u8,

    /// The value-stack index of action position `pos` (1-based).
    fn index(pos: u16) usize {
        return @as(usize, pos) - 1;
    }

    fn list(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        if (l.head == .none and l.items.len == 0) return w.print(emptyList, .{self.use});

        // (!A ...B): element A consed onto the list at B.
        if (l.head == .ref and l.items.len == 1 and l.items[0].elem == .spread and l.head.ref == .ref) {
            return w.print("self.spreadList(pass[{d}], pass[{d}], {s})", .{ index(l.head.ref.ref), index(l.items[0].elem.spread), self.use });
        }

        if (self.fixed) return self.fixedList(w, l, label);
        return self.legacyList(w, l, label);
    }

    // --- Schema mode -------------------------------------------------------

    fn fixedList(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        var spreads = false;
        for (l.items) |item| if (item.elem == .spread) {
            spreads = true;
        };
        if (!spreads) {
            // Every item is one Sexp: allocate the list in one step.
            try w.writeAll(listFromSlicePrefix);
            var first = true;
            if (headValue(l.head)) |_| {
                try self.headExpr(w, l.head);
                first = false;
            }
            for (l.items) |item| {
                if (!first) try w.writeAll(", ");
                first = false;
                try self.value(w, item.elem);
            }
            return w.print(listFromSliceSuffix, .{self.listUse(l)});
        }
        try self.buildList(w, l, label);
    }

    /// The use of a list this rule builds: tagged lists are nodes; an
    /// untagged one follows the rule.
    fn listUse(self: *const Emitter, l: ActionList) []const u8 {
        return if (l.head == .tag) ".tree" else self.use;
    }

    // --- Without a schema (0.10 output) --------------------------------------

    fn legacyList(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        const tag: ?[]const u8 = switch (l.head) {
            .tag => |t| t,
            else => null,
        };
        const firstIsTag = if (tag) |t| isTagLiteral(t) else false;

        var spreadCount: usize = 0;
        var spreadPos: u16 = 0;
        var posCount: usize = 0;
        var firstPos: u16 = 0;
        var hasTilde = false;
        var hasOther = false;
        var hasNil = false;
        var hasChildTag = false;
        for (l.items) |item| switch (item.elem) {
            .spread => |p| {
                spreadCount += 1;
                spreadPos = p;
            },
            .symId => hasTilde = true,
            .ref => |p| {
                if (posCount == 0) firstPos = p;
                posCount += 1;
            },
            .nil => hasNil = true,
            .tagLit => |t| if (isTagLiteral(t)) {
                hasChildTag = true;
            } else {
                hasOther = true;
            },
            .node => {},
        };
        const plain = firstIsTag and !hasTilde and !hasOther;
        const bare = plain and !hasNil and !hasChildTag and !hasNested(l);

        if (bare and spreadCount == 1 and posCount == 0) {
            return w.print("self.sexpSpread(.@\"{f}\", pass[{d}])", .{ fmtTag(tag.?), index(spreadPos) });
        }
        // `(tag N ...M)`; `(tag ...M N)` keeps its order through buildList.
        const posBeforeSpread = l.items.len == 2 and l.items[0].elem == .ref;
        if (bare and spreadCount == 1 and posCount == 1 and posBeforeSpread) {
            return w.print("self.sexpPosSpread(.@\"{f}\", pass[{d}], pass[{d}])", .{ fmtTag(tag.?), index(firstPos), index(spreadPos) });
        }
        if (plain and spreadCount == 0) {
            try w.print("self.sexp(.@\"{f}\", &.{{", .{fmtTag(tag.?)});
            for (l.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try self.value(w, item.elem);
            }
            return w.writeAll("})");
        }
        try self.buildList(w, l, label);
    }

    fn hasNested(l: ActionList) bool {
        for (l.items) |item| if (item.elem == .node) return true;
        return false;
    }

    // --- Shared ------------------------------------------------------------

    /// A labeled block that appends the head and every item to a list.
    /// A leading `...N` whose N is not used again extends that list in
    /// place (amortized O(1) growth of left-recursive lists; each reduced
    /// value is consumed once). Trailing nils are dropped by the runtime
    /// (keepList/finishList) unless the schema fixes positions.
    fn buildList(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        var extend: ?u16 = null;
        if (l.head == .none and l.items.len > 0 and l.items[0].elem == .spread) {
            const n = l.items[0].elem.spread;
            extend = n;
            for (l.items[1..]) |item| if (refersTo(item.elem, n)) {
                extend = null;
            };
        }
        if (extend) |n| {
            try w.print("{s}: {{ var out = self.extendList(pass[{d}]) catch break :{s} " ++ allocFailed ++ "; ", .{ label, index(n), label });
        } else {
            try w.print("{s}: {{ var out: std.ArrayListUnmanaged(Sexp) = .empty; ", .{label});
        }
        if (headValue(l.head)) |_| {
            try w.writeAll("out.append(self.allocator(), ");
            try self.headExpr(w, l.head);
            try w.print(") catch break :{s} " ++ allocFailed ++ "; ", .{label});
        }
        for (l.items, 0..) |item, i| {
            if (extend != null and i == 0) continue;
            switch (item.elem) {
                .spread => |p| {
                    const at = index(p);
                    try w.print("for (" ++ itemsOf ++ ") |item| out.append(self.allocator(), item) catch break :{s} " ++ allocFailed ++ "; ", .{ at, label });
                },
                else => {
                    try w.writeAll("out.append(self.allocator(), ");
                    try self.value(w, item.elem);
                    try w.print(") catch break :{s} " ++ allocFailed ++ "; ", .{label});
                },
            }
        }
        if (extend != null) {
            try w.print("break :{s} self.keepList(&out, {s}); }}", .{ label, self.listUse(l) });
        } else {
            try w.print("break :{s} " ++ listFromOwned ++ "; }}", .{ label, self.listUse(l) });
        }
    }

    fn headValue(head: ActionList.Head) ?void {
        return switch (head) {
            .none => null,
            else => {},
        };
    }

    fn headExpr(self: *Emitter, w: anytype, head: ActionList.Head) anyerror!void {
        switch (head) {
            .tag => |t| try w.print(".{{ .tag = .@\"{f}\" }}", .{fmtTag(t)}),
            .ref => |e| try self.value(w, e),
            .none => unreachable,
        }
    }

    /// One item's Sexp value (spreads are handled by the list builders).
    fn value(self: *Emitter, w: anytype, e: ActionElem) anyerror!void {
        switch (e) {
            .ref => |p| try w.print("pass[{d}]", .{index(p)}),
            .symId => |p| {
                const at = index(p);
                try w.print("if (pass[{d}] == .src) pass[{d}] else .{{ .src = .{{ .pos = 0, .len = 0, .id = 0 }} }}", .{ at, at });
            },
            .nil => try w.writeAll(".nil"),
            .tagLit => |t| try w.print(".{{ .tag = .@\"{f}\" }}", .{fmtTag(t)}),
            .node => |n| {
                // A nested node gets its own node id, spanning the
                // pattern elements it references.
                const use = self.use;
                self.use = ".tree";
                defer self.use = use;
                self.depth += 1;
                var buf: [16]u8 = undefined;
                const label = try std.fmt.bufPrint(&buf, "blk{d}", .{self.depth});
                var range: Range = .{};
                range.addList(n.*);
                if (range.lo) |lo| {
                    try w.writeAll("self.nested(");
                    try self.list(w, n.*, label);
                    try w.print(", {d}, {d})", .{ index(lo), index(range.hi) });
                } else {
                    try w.writeAll("self.nestedEmpty(");
                    try self.list(w, n.*, label);
                    try w.writeAll(")");
                }
            },
            .spread => unreachable,
        }
    }
};

/// The pattern positions an action list references.
const Range = struct {
    lo: ?u16 = null,
    hi: u16 = 0,

    fn add(self: *Range, pos: u16) void {
        self.lo = if (self.lo) |lo| @min(lo, pos) else pos;
        self.hi = @max(self.hi, pos);
    }

    fn addElem(self: *Range, e: ActionElem) void {
        switch (e) {
            .ref, .spread, .symId => |p| self.add(p),
            .node => |n| self.addList(n.*),
            .nil, .tagLit => {},
        }
    }

    fn addList(self: *Range, l: ActionList) void {
        switch (l.head) {
            .ref => |h| self.addElem(h),
            else => {},
        }
        for (l.items) |item| self.addElem(item.elem);
    }
};

fn refersTo(e: ActionElem, pos: u16) bool {
    return switch (e) {
        .ref, .spread, .symId => |p| p == pos,
        .node => |n| blk: {
            switch (n.head) {
                .ref => |h| if (refersTo(h, pos)) break :blk true,
                else => {},
            }
            for (n.items) |item| if (refersTo(item.elem, pos)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// Tags the 0.10 fast paths accept at the head: letters and `! # ? @ $ * /`.
fn isTagLiteral(t: []const u8) bool {
    if (t.len == 0) return false;
    const c = t[0];
    return std.ascii.isAlphabetic(c) or c == '!' or c == '#' or c == '?' or c == '@' or c == '$' or c == '*' or c == '/';
}

/// A tag name inside `@"..."` (escapes `\`).
fn fmtTag(t: []const u8) std.fmt.Alt([]const u8, writeTag) {
    return .{ .data = t };
}

fn writeTag(t: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (t) |c| {
        if (c == '\\' or c == '"') try w.writeByte('\\');
        try w.writeByte(c);
    }
}

// =============================================================================
// Runtime surface: the builders emitted action code calls (runtime_template
// `BaseParser`). Each gives the list it builds a node id when the parser
// keeps a node store.
// =============================================================================

/// `listFromSlicePrefix` + comma-separated item expressions + suffix (a
/// format taking the list's `ListUse`): a list node over exactly those
/// items.
const listFromSlicePrefix = "self.build(&.{ ";
const listFromSliceSuffix = " }}, {s})";
/// The list node holding the items of the ArrayList `out` (format: the
/// list's `ListUse`).
const listFromOwned = "self.finishList(&out, {s})";
/// `()` (format: its `ListUse`)
const emptyList = "self.emptyList({s})";
/// The items of the list in `pass[{d}]` (none for any other value).
const itemsOf = "pass[{d}].items()";
/// The value of a list block whose allocation failed.
const allocFailed = "self.oomNil()";
