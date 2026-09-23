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

/// Emit the Zig expression for `rule`'s action.
pub fn generateRuleAction(allocator: Allocator, writer: anytype, g: *const Grammar, rule: Rule) !void {
    var e = Emitter{ .allocator = allocator, .offset = rule.actionOffset, .fixed = g.schema != null };
    const tree = rule.actionTree orelse {
        try writer.writeAll("self.list(pass)");
        return;
    };
    switch (tree) {
        .nil => try writer.writeAll(".nil"),
        .pass => |p| try writer.print("pass[{d}]", .{e.index(p)}),
        .list => |l| try e.list(writer, l, "blk"),
    }
}

const Emitter = struct {
    allocator: Allocator,
    /// Added to every position (the start-marker offset).
    offset: u8,
    /// Schema mode: fixed-length lists, no trailing-nil stripping.
    fixed: bool,
    /// Counter for the labels of nested list blocks.
    depth: usize = 0,

    fn index(self: *const Emitter, pos: u16) usize {
        return @as(usize, pos) - 1 + self.offset;
    }

    fn list(self: *Emitter, w: anytype, l: ActionList, label: []const u8) anyerror!void {
        if (l.head == .none and l.items.len == 0) return w.writeAll(".{ .list = &[_]Sexp{} }");

        // (!A ...B): element A consed onto the list at B.
        if (l.head == .ref and l.items.len == 1 and l.items[0].elem == .spread and l.head.ref == .ref) {
            return w.print("self.spreadList(pass[{d}], pass[{d}])", .{ self.index(l.head.ref.ref), self.index(l.items[0].elem.spread) });
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
            return w.writeAll(listFromSliceSuffix);
        }
        try self.buildList(w, l, label, false);
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
            .label => hasOther = true,
        };
        const plain = firstIsTag and !hasTilde and !hasOther;
        const bare = plain and !hasNil and !hasChildTag and !hasNested(l);

        if (bare and spreadCount == 1 and posCount == 0) {
            return w.print("self.sexpSpread(.@\"{f}\", pass[{d}])", .{ fmtTag(tag.?), self.index(spreadPos) });
        }
        if (bare and spreadCount == 1 and posCount == 1) {
            return w.print("self.sexpPosSpread(.@\"{f}\", pass[{d}], pass[{d}])", .{ fmtTag(tag.?), self.index(firstPos), self.index(spreadPos) });
        }
        if (plain and spreadCount == 0) {
            try w.print("self.sexp(.@\"{f}\", &.{{", .{fmtTag(tag.?)});
            for (l.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try self.value(w, item.elem);
            }
            return w.writeAll("})");
        }
        try self.buildList(w, l, label, true);
    }

    fn hasNested(l: ActionList) bool {
        for (l.items) |item| if (item.elem == .node) return true;
        return false;
    }

    // --- Shared ------------------------------------------------------------

    /// A labeled block that appends the head and every item to a list.
    /// A leading `...N` whose N is not used again extends that list in
    /// place (amortized O(1) growth of left-recursive lists; each reduced
    /// value is consumed once). `strip` drops trailing nils.
    fn buildList(self: *Emitter, w: anytype, l: ActionList, label: []const u8, strip: bool) anyerror!void {
        var extend: ?u16 = null;
        if (l.head == .none and l.items.len > 0 and l.items[0].elem == .spread) {
            const n = l.items[0].elem.spread;
            extend = n;
            for (l.items[1..]) |item| if (refersTo(item.elem, n)) {
                extend = null;
            };
        }
        if (extend) |n| {
            try w.print("{s}: {{ var out = self.extendList(pass[{d}]) catch break :{s} .nil; ", .{ label, self.index(n), label });
        } else {
            try w.print("{s}: {{ var out: std.ArrayListUnmanaged(Sexp) = .empty; ", .{label});
        }
        if (headValue(l.head)) |_| {
            try w.writeAll("out.append(self.allocator(), ");
            try self.headExpr(w, l.head);
            try w.print(") catch break :{s} .nil; ", .{label});
        }
        for (l.items, 0..) |item, i| {
            if (extend != null and i == 0) continue;
            switch (item.elem) {
                .spread => |p| {
                    const at = self.index(p);
                    try w.print("if (pass[{d}] == .list) for (" ++ itemsOf ++ ") |item| out.append(self.allocator(), item) catch break :{s} .nil; ", .{ at, at, label });
                },
                else => {
                    try w.writeAll("out.append(self.allocator(), ");
                    try self.value(w, item.elem);
                    try w.print(") catch break :{s} .nil; ", .{label});
                },
            }
        }
        if (strip) try w.writeAll("while (out.items.len > 0 and out.items[out.items.len - 1] == .nil) _ = out.pop(); ");
        if (extend != null) {
            try w.print("break :{s} self.keepList(&out); }}", .{label});
        } else {
            try w.print("break :{s} ", .{label});
            try w.writeAll(listFromOwned ++ "; }");
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
            .ref => |p| try w.print("pass[{d}]", .{self.index(p)}),
            .symId => |p| {
                const at = self.index(p);
                try w.print("if (pass[{d}] == .src) pass[{d}] else .{{ .src = .{{ .pos = 0, .len = 0, .id = 0 }} }}", .{ at, at });
            },
            .nil => try w.writeAll(".nil"),
            .tagLit => |t| try w.print(".{{ .tag = .@\"{f}\" }}", .{fmtTag(t)}),
            .node => |n| {
                self.depth += 1;
                var buf: [16]u8 = undefined;
                const label = try std.fmt.bufPrint(&buf, "blk{d}", .{self.depth});
                try self.list(w, n.*, label);
            },
            .spread, .label => unreachable,
        }
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
// Runtime surface: the only places emitted action code depends on how a
// list Sexp is represented (`.list` holds a `[]const Sexp`).
// =============================================================================

/// `...` + `listFromSliceSuffix` around comma-separated item expressions.
const listFromSlicePrefix = ".{ .list = self.allocator().dupe(Sexp, &.{ ";
const listFromSliceSuffix = " }) catch &[_]Sexp{} }";
/// The list Sexp holding the items of the ArrayList `out`.
const listFromOwned = ".{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} }";
/// The items of the list in `pass[{d}]` (the format argument).
const itemsOf = "pass[{d}].list";
