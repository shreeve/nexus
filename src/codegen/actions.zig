//! Action codegen: compiles a rule's action tree (grammar.ActionTree) into
//! the Zig expression `executeAction` returns for it, and collects the tags
//! actions use (for the auto-extracted Tag enum).
//!
//! Two modes. Without a schema, lists drop trailing nils (at run time), and
//! common shapes use dedicated builders: `(tag ...N)` is `sexpSpread`,
//! `(tag M ...N)` is `sexpPosSpread`, `(tag a b)` is `sexp`. With a schema,
//! every list has exactly the items its action places (fixed length, nils
//! kept), in order.
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
    list: std.ArrayList([]const u8) = .empty,

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
        .spread, .symId, .nil, .tagLit, .litTag => {},
    }
}

/// The value of a rule whose action builds nothing: nil, or one of its
/// elements as it is. The parser takes it without calling the action
/// function.
pub const Copy = union(enum) { nil, element: u16 };

pub fn copyOf(rule: Rule) ?Copy {
    const tree = rule.actionTree orelse return switch (rule.rhs.len) {
        0 => .nil,
        1 => .{ .element = 0 },
        else => null,
    };
    return switch (tree) {
        .nil => .nil,
        .pass => |p| .{ .element = p - 1 },
        .list => null,
    };
}

/// What the emitted actions refer to, so that `executeAction` discards
/// the parameters none reads and the module keeps element extents only
/// when some action builds a nested node.
pub const Uses = struct {
    /// Some action reads its elements (`pass`).
    pass: bool = false,
    /// Some action calls a builder (`self`).
    self: bool = false,
    /// Some action builds a nested node over elements (`self.nested`).
    nested: bool = false,
};

/// Emit the Zig expression for `rule`'s action, recording in `uses` what
/// it refers to. `reachesTree` is whether the rule's value can reach the
/// tree (see `treeSymbols`).
pub fn generateRuleAction(allocator: Allocator, writer: anytype, g: *const Grammar, rule: Rule, reachesTree: bool, uses: *Uses) !void {
    var e = Emitter{ .allocator = allocator, .g = g, .rule = rule, .fixed = g.schema != null, .use = if (reachesTree) ".tree" else ".spread", .uses = uses };
    // A rule whose value is nil or one of its elements has no action
    // (`copyOf`); the default action of several elements is their list.
    const tree = rule.actionTree orelse {
        uses.self = true;
        uses.pass = true;
        return writer.print("self.build(pass, {s})", .{e.use});
    };
    try e.list(writer, tree.list, "blk");
}

const Emitter = struct {
    allocator: Allocator,
    g: *const Grammar,
    rule: Rule,
    /// Schema mode: fixed-length lists, no trailing-nil stripping.
    fixed: bool,
    /// Counter for the labels of nested list blocks.
    depth: usize = 0,
    /// The `ListUse` of the rule's own untagged list (`.tree` or
    /// `.spread`); nested lists always reach the tree.
    use: []const u8,
    uses: *Uses,

    /// The value-stack index of action position `pos` (1-based).
    fn index(pos: u16) usize {
        return @as(usize, pos) - 1;
    }

    fn list(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        // Every list is built by a builder.
        self.uses.self = true;
        if (readsElements(l)) self.uses.pass = true;
        if (l.head == .none and l.items.len == 0) return w.print(emptyList, .{self.use});

        // (!A ...B): element A consed onto the list at B (A nil when it is
        // an absent optional element: the head stays either way).
        if (l.head == .ref and l.items.len == 1 and l.items[0].elem == .spread) switch (l.head.ref) {
            .ref => |a| return w.print("self.spreadList(pass[{d}], pass[{d}], {s})", .{ index(a), index(l.items[0].elem.spread), self.use }),
            .nil => return w.print("self.spreadList(.nil, pass[{d}], {s})", .{ index(l.items[0].elem.spread), self.use }),
            else => {},
        };

        if (self.fixed or l.keepNils) return self.fixedList(w, l, label);
        return self.schemalessList(w, l, label);
    }

    // --- Schema mode -------------------------------------------------------

    fn fixedList(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        var spreads = false;
        for (l.items) |item| if (item.elem == .spread) {
            spreads = true;
        };
        if (!spreads) {
            // Every item is one Sexp: allocate the list in one step.
            if (staticItems(l)) {
                try self.staticList(w, l);
                return w.print(", pass, {s}, false)", .{self.listUse(l)});
            }
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

    // --- Without a schema ----------------------------------------------------

    fn schemalessList(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
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
            .litTag => hasChildTag = true,
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
            return w.print("self.sexpSpread(.@\"{f}\", pass[{d}])", .{ std.zig.fmtString(tag.?), index(spreadPos) });
        }
        // `(tag N ...M)`; `(tag ...M N)` keeps its order through buildList.
        const posBeforeSpread = l.items.len == 2 and l.items[0].elem == .ref;
        if (bare and spreadCount == 1 and posCount == 1 and posBeforeSpread) {
            return w.print("self.sexpPosSpread(.@\"{f}\", pass[{d}], pass[{d}])", .{ std.zig.fmtString(tag.?), index(firstPos), index(spreadPos) });
        }
        if (plain and spreadCount == 0) {
            if (staticItems(l)) {
                try self.staticList(w, l);
                return w.writeAll(", pass, .tree, true)");
            }
            try w.print("self.sexp(.@\"{f}\", &.{{", .{std.zig.fmtString(tag.?)});
            for (l.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try self.value(w, item.elem);
            }
            return w.writeAll("})");
        }
        try self.buildList(w, l, label);
    }

    /// Whether every item of a list without spreads is an element, a tag
    /// or nil: the list is then static data (`buildOf`).
    fn staticItems(l: ActionList) bool {
        switch (l.head) {
            .ref => |h| if (!staticItem(h)) return false,
            else => {},
        }
        for (l.items) |item| if (!staticItem(item.elem)) return false;
        return true;
    }

    fn staticItem(e: ActionElem) bool {
        return switch (e) {
            .ref, .nil, .tagLit, .litTag => true,
            .spread, .symId, .node => false,
        };
    }

    /// `self.buildOf(&.{ items... }` for a list of static items.
    fn staticList(self: *Emitter, w: anytype, l: ActionList) anyerror!void {
        self.uses.pass = true;
        try w.writeAll("self.buildOf(&.{");
        var first = true;
        switch (l.head) {
            .tag => |t| {
                try w.print(" .{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(t)});
                first = false;
            },
            .ref => |h| {
                try self.staticValue(w, h);
                first = false;
            },
            .none => {},
        }
        for (l.items) |it| {
            if (!first) try w.writeAll(",");
            first = false;
            try self.staticValue(w, it.elem);
        }
        try w.writeAll(" }");
    }

    /// One static item as an `Item` literal.
    fn staticValue(self: *Emitter, w: anytype, e: ActionElem) anyerror!void {
        switch (e) {
            .ref => |p| try w.print(" .{{ .elem = {d} }}", .{index(p)}),
            .nil => try w.writeAll(" .nil"),
            .tagLit => |t| try w.print(" .{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(t)}),
            .litTag => |p| try w.print(" .{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(try literalText(self.allocator, self.g.symbols.items[self.rule.rhs[p - 1]].name))}),
            .spread, .symId, .node => unreachable,
        }
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
    /// (keepList/finishList) unless the schema fixes positions or the list
    /// keeps its nils.
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
            try w.print("{s}: {{ var out = self.extendList(pass, {d}) catch break :{s} " ++ allocFailed ++ "; ", .{ label, index(n), label });
        } else {
            try w.print("{s}: {{ var out: std.ArrayList(Sexp) = .empty; ", .{label});
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
            const keep = if (l.keepNils) "keepListNils" else "keepList";
            try w.print("break :{s} self.{s}(&out, pass, {d}, {s}); }}", .{ label, keep, index(extend.?), self.listUse(l) });
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
            .tag => |t| try w.print(".{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(t)}),
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
                try w.print("if (pass[{d}] == .src) pass[{d}] else self.emptyLeaf(pass, {d})", .{ at, at, at });
            },
            .nil => try w.writeAll(".nil"),
            .tagLit => |t| try w.print(".{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(t)}),
            .litTag => |p| try w.print(".{{ .tag = .@\"{f}\" }}", .{std.zig.fmtString(try literalText(self.allocator, self.g.symbols.items[self.rule.rhs[p - 1]].name))}),
            .node => |n| {
                // A nested node gets its own node id, spanning the
                // pattern elements it references.
                const use = self.use;
                self.use = ".tree";
                defer self.use = use;
                self.depth += 1;
                var buf: [16]u8 = undefined;
                const label = try std.mem.print(&buf, "blk{d}", .{self.depth});
                var range: Range = .{};
                range.addList(n.*);
                if (range.lo) |lo| {
                    self.uses.nested = true;
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
            .ref, .spread, .symId, .litTag => |p| self.add(p),
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

/// Whether a list reads any element (`pass`).
fn readsElements(l: ActionList) bool {
    switch (l.head) {
        .ref => |h| if (readsElement(h)) return true,
        else => {},
    }
    for (l.items) |item| if (readsElement(item.elem)) return true;
    return false;
}

fn readsElement(e: ActionElem) bool {
    return switch (e) {
        .ref, .spread, .symId => true,
        .node => |n| readsElements(n.*),
        .nil, .tagLit, .litTag => false,
    };
}

fn refersTo(e: ActionElem, pos: u16) bool {
    return switch (e) {
        .ref, .spread, .symId, .litTag => |p| p == pos,
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

/// Tags the dedicated builders accept at the head: letters and `! # ? @ $ * /`.
fn isTagLiteral(t: []const u8) bool {
    if (t.len == 0) return false;
    const c = t[0];
    return std.ascii.isAlphabetic(c) or c == '!' or c == '#' or c == '?' or c == '@' or c == '$' or c == '*' or c == '/';
}

/// The text a string-literal terminal (`"+="`) matches: its name without
/// the quotes, its escapes decoded.
fn literalText(allocator: Allocator, name: []const u8) ![]const u8 {
    return grammar.decode(allocator, name[1 .. name.len - 1]);
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
