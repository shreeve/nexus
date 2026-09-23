//! The semantic layer (schema mode): checks a grammar's actions against its
//! `@schema` and resolves them into fixed-length node constructions.
//!
//! Before expansion (`resolve`, on the grammar IR):
//!   - the schema itself: role types name declared kinds;
//!   - the tag inventory: every head an action builds is a declared kind,
//!     every declared kind (except `@wrapper` kinds) is built by some rule,
//!     every tag literal is declared; on drift the actual inventory is
//!     printed as a paste-ready `@schema` block;
//!   - role filling: positional items fill slots in order, `role:value`
//!     items and pattern labels fill roles by name, labels naming side-band
//!     roles become `Rule.sideLabels`; every required role is filled, and
//!     the result lists every slot in schema order (nil where unfilled)
//!     followed by the rest children;
//!   - the coverage gate: every value-bearing pattern element is used by
//!     the action, labeled, or dropped (`!X`, `_:X`), unless the
//!     alternative opts out (`~ "reason"`).
//!
//! After expansion (`checkTypes`, on the desugared Grammar): the static
//! result types of every nonterminal (a fixpoint over the rules), and every
//! role's value checked against its declared type.
//!
//! Every error is `file:line:col: error: ...` naming the rule; all errors
//! of a phase are reported before generation stops.

const std = @import("std");
const Allocator = std.mem.Allocator;
const diag = @import("diag.zig");
const grammar = @import("grammar.zig");
const expand = @import("expand.zig");
const writeSymbol = @import("lr/conflicts.zig").writeSymbol;
const GrammarIR = grammar.GrammarIR;
const Grammar = grammar.Grammar;
const Schema = grammar.Schema;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const ActionTree = grammar.ActionTree;
const ActionList = grammar.ActionList;
const ActionItem = grammar.ActionItem;
const ActionElem = grammar.ActionElem;
const LexerSpec = grammar.LexerSpec;
const Resolved = expand.Resolved;
const Layout = expand.Layout;

pub const Error = error{ SemanticError, OutOfMemory };

pub const Result = struct {
    /// Per rule, per alternative (parallel to `ir.rules`).
    resolved: []const []const Resolved,
    /// Per `@infix` operator (parallel to `ir.infix.ops`): the placed
    /// `(op 1 3)` node.
    infix: []const Resolved,
    /// The schema with `extraTags` extended by the marker values used in
    /// unrestricted `tag` roles (after the `@tags` entries).
    schema: Schema,
};

/// The complete, ordered Tag inventory of a schema: kinds in declaration
/// order, then `tag(...)` values, then `extraTags`, without duplicates.
pub fn schemaTags(allocator: Allocator, schema: Schema) ![]const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    const add = struct {
        fn f(a: Allocator, o: *std.ArrayListUnmanaged([]const u8), s: *std.StringHashMapUnmanaged(void), t: []const u8) !void {
            if (s.contains(t)) return;
            try s.put(a, t, {});
            try o.append(a, t);
        }
    }.f;
    for (schema.kinds) |k| try add(allocator, &out, &seen, k.tag);
    for (schema.kinds) |k| for (k.roles) |r| switch (r.type) {
        .tag => |values| for (values) |v| try add(allocator, &out, &seen, v),
        else => {},
    };
    for (schema.extraTags) |t| try add(allocator, &out, &seen, t);
    return out.toOwnedSlice(allocator);
}

// =============================================================================
// Before expansion
// =============================================================================

/// Resolve every action of a schema-mode grammar (`ir.schema` non-null).
pub fn resolve(allocator: Allocator, ir: *const GrammarIR, lexerSpec: ?*const LexerSpec, path: []const u8) Error!Result {
    var r = Resolver{ .a = allocator, .ir = ir, .schema = ir.schema.?, .lexer = lexerSpec, .path = path };
    return r.run();
}

const Resolver = struct {
    a: Allocator,
    ir: *const GrammarIR,
    schema: Schema,
    lexer: ?*const LexerSpec,
    path: []const u8,
    failed: bool = false,

    kindIndex: std.StringHashMapUnmanaged(u16) = .empty,
    /// Tags declared outside kinds: `tag(...)` values and `@tags`.
    declaredTags: std.StringHashMapUnmanaged(void) = .empty,
    /// Marker values used in unrestricted `tag` roles, in first-seen order.
    markers: std.ArrayListUnmanaged([]const u8) = .empty,
    /// Kinds some action builds.
    built: std.StringHashMapUnmanaged(void) = .empty,
    drift: std.ArrayListUnmanaged(u8) = .empty,
    /// Heads and tag literals used but not declared, in first-seen order.
    undeclaredKinds: std.ArrayListUnmanaged(Use) = .empty,
    undeclaredTags: std.ArrayListUnmanaged([]const u8) = .empty,

    /// One construction of an undeclared kind, for the inventory printout.
    const Use = struct { tag: []const u8, list: ActionList };

    const Ctx = struct { rule: []const u8, line: u32, col: u32 };

    fn err(self: *Resolver, ctx: Ctx, comptime fmt: []const u8, args: anytype) void {
        self.failed = true;
        diag.errLine(self.path, ctx.line, ctx.col, "rule '{s}': " ++ fmt, .{ctx.rule} ++ args);
    }

    fn run(self: *Resolver) Error!Result {
        const a = self.a;
        for (self.schema.kinds, 0..) |k, i| try self.kindIndex.put(a, k.tag, @intCast(i));
        for (self.schema.kinds) |k| for (k.roles) |role| switch (role.type) {
            .tag => |values| for (values) |v| try self.declaredTags.put(a, v, {}),
            .kinds => |names| for (names) |n| if (!self.kindIndex.contains(n)) {
                self.failed = true;
                diag.errLine(self.path, k.line, k.col, "kind '{s}': role '{s}' names '{s}', which is not a declared kind", .{ k.tag, role.name, n });
            },
            else => {},
        };
        for (self.schema.extraTags) |t| try self.declaredTags.put(a, t, {});
        if (self.failed) return error.SemanticError;

        const aliases = try self.aliasTargets();

        var resolved: std.ArrayListUnmanaged([]const Resolved) = .empty;
        for (self.ir.rules) |rule| {
            var alts: std.ArrayListUnmanaged(Resolved) = .empty;
            for (rule.alternatives) |alt| try alts.append(a, try self.resolveAlternative(rule, alt, &aliases));
            try resolved.append(a, try alts.toOwnedSlice(a));
        }

        var infix: std.ArrayListUnmanaged(Resolved) = .empty;
        if (self.ir.infix) |decl| for (decl.ops) |op| {
            const items = try a.dupe(ActionItem, &.{ .{ .elem = .{ .ref = 1 } }, .{ .elem = .{ .ref = 3 } } });
            const list: ActionList = .{ .head = .{ .tag = op.op }, .items = items };
            const ctx: Ctx = .{ .rule = "@infix", .line = 0, .col = 0 };
            try infix.append(a, .{ .tree = .{ .list = try self.place(ctx, list, &.{}, null) }, .kind = self.kindIndex.get(op.op) });
        };

        try self.checkInventory();
        if (self.failed) return error.SemanticError;

        var schema = self.schema;
        var extra: std.ArrayListUnmanaged([]const u8) = .empty;
        try extra.appendSlice(a, schema.extraTags);
        for (self.markers.items) |m| if (!containsName(extra.items, m)) try extra.append(a, m);
        schema.extraTags = try extra.toOwnedSlice(a);
        return .{ .resolved = try resolved.toOwnedSlice(a), .infix = try infix.toOwnedSlice(a), .schema = schema };
    }

    /// `name = TOKEN` aliases: name → token.
    fn aliasTargets(self: *Resolver) !std.StringHashMapUnmanaged([]const u8) {
        var out: std.StringHashMapUnmanaged([]const u8) = .empty;
        for (self.ir.rules) |rule| {
            if (rule.alternatives.len != 1) continue;
            const alt = rule.alternatives[0];
            if (alt.elements.len != 1 or alt.actionTree != null) continue;
            const e = alt.elements[0];
            if (e.quantifier == .one and (e.kind == .token or e.kind == .ident)) try out.put(self.a, rule.name, e.value);
        }
        return out;
    }

    fn resolveAlternative(self: *Resolver, rule: ParsedRule, alt: ParsedAlternative, aliases: *const std.StringHashMapUnmanaged([]const u8)) Error!Resolved {
        const ctx: Ctx = .{ .rule = rule.name, .line = alt.line, .col = alt.col };
        const layout = try Layout.of(self.a, alt.elements);

        // Pattern labels, with their positions.
        var labels: std.ArrayListUnmanaged(Label) = .empty;
        for (1..layout.slots.len + 1) |p| {
            const e = layout.element(alt.elements, p);
            const name = e.label orelse continue;
            if (std.mem.eql(u8, name, "_")) continue;
            try labels.append(self.a, .{ .name = name, .pos = @intCast(p), .line = e.line, .col = e.col });
        }

        var out: Resolved = .{ .tree = alt.actionTree };
        var sides: std.ArrayListUnmanaged(Resolved.SideLabel) = .empty;
        if (alt.actionTree) |tree| switch (tree) {
            .list => |l| {
                const kind: ?u16 = switch (l.head) {
                    .tag => |t| self.kindIndex.get(t),
                    else => null,
                };
                out.kind = kind;
                const placed = try self.place(ctx, l, labels.items, &sides);
                out.tree = .{ .list = placed };
            },
            else => {},
        };
        const constructsKind = out.kind != null;
        if (!constructsKind) for (labels.items) |lab| {
            self.err(.{ .rule = rule.name, .line = lab.line, .col = lab.col }, "label '{s}' fills a role, but the action builds no schema node", .{lab.name});
        };
        out.sideLabels = try sides.toOwnedSlice(self.a);

        if (alt.optOut == null and alt.actionTree != null) try self.checkCoverage(ctx, alt, layout, aliases);
        return out;
    }

    const Label = struct { name: []const u8, pos: u16, line: u32, col: u32 };

    /// Place a list's items: a kind-headed list gets its slots in schema
    /// order; any other list is plumbing and keeps its items. Nested lists
    /// are placed too. `labels` fill roles of this (top-level) list only.
    fn place(self: *Resolver, ctx: Ctx, l: ActionList, labels: []const Label, sides: ?*std.ArrayListUnmanaged(Resolved.SideLabel)) Error!ActionList {
        const a = self.a;
        const tag = switch (l.head) {
            .tag => |t| t,
            else => {
                // Plumbing: no roles, nested lists placed.
                var items: std.ArrayListUnmanaged(ActionItem) = .empty;
                for (l.items) |item| {
                    if (item.role) |r| self.err(ctx, "role '{s}' in a list without a kind (roles belong to schema nodes)", .{r});
                    try self.noteTag(ctx, item.elem, null);
                    try items.append(a, .{ .elem = try self.placeElem(ctx, item.elem) });
                }
                return .{ .head = l.head, .items = try items.toOwnedSlice(a) };
            },
        };
        const ki = self.kindIndex.get(tag) orelse {
            try self.undeclaredKind(tag, l);
            for (l.items) |item| try self.noteTag(ctx, item.elem, null);
            return l;
        };
        try self.built.put(a, tag, {});
        const kind = self.schema.kinds[ki];
        const roles = kind.roles;
        const slotCount = if (roles.len > 0 and roles[roles.len - 1].rest) roles.len - 1 else roles.len;
        const restRole: ?Schema.Role = if (slotCount < roles.len) roles[slotCount] else null;

        const slots = try a.alloc(?ActionElem, slotCount);
        @memset(slots, null);
        var rest: std.ArrayListUnmanaged(ActionElem) = .empty;
        var next: usize = 0;
        var named = false;

        for (l.items) |item| {
            const elem = try self.placeElem(ctx, item.elem);
            if (item.role) |roleName| {
                named = true;
                const ri = roleIndex(roles, roleName) orelse {
                    if (containsName(kind.side, roleName)) {
                        self.err(ctx, "'{s}' is a side-band role of '{s}'; side-band roles are filled by pattern labels", .{ roleName, tag });
                    } else self.err(ctx, "'{s}' has no role '{s}' (roles: {f})", .{ tag, roleName, fmtRoles(kind) });
                    continue;
                };
                if (ri < slotCount) {
                    if (elem == .spread) {
                        self.err(ctx, "role '{s}' of '{s}' takes one value; only the rest role takes a spread", .{ roleName, tag });
                        continue;
                    }
                    if (slots[ri] != null) {
                        self.err(ctx, "role '{s}' of '{s}' is filled twice", .{ roleName, tag });
                        continue;
                    }
                    try self.noteTag(ctx, elem, roles[ri]);
                    slots[ri] = elem;
                } else {
                    try self.noteTag(ctx, elem, roles[ri]);
                    try rest.append(a, elem);
                }
                continue;
            }
            if (named) {
                self.err(ctx, "positional items come before role:value items", .{});
                continue;
            }
            if (next < slotCount) {
                if (elem == .spread) {
                    self.err(ctx, "a spread cannot fill role '{s}' of '{s}'; only the rest role takes a spread", .{ roles[next].name, tag });
                    next += 1;
                    continue;
                }
                try self.noteTag(ctx, elem, roles[next]);
                slots[next] = elem;
                next += 1;
            } else if (restRole) |rr| {
                try self.noteTag(ctx, elem, rr);
                try rest.append(a, elem);
            } else {
                self.err(ctx, "'{s}' has {d} role{s}; the action gives more items", .{ tag, slotCount, if (slotCount == 1) "" else "s" });
                break;
            }
        }

        for (labels) |lab| {
            const lctx: Ctx = .{ .rule = ctx.rule, .line = lab.line, .col = lab.col };
            if (roleIndex(roles, lab.name)) |ri| {
                if (ri < slotCount) {
                    if (slots[ri] != null) {
                        self.err(lctx, "role '{s}' of '{s}' is filled by the label and by the action", .{ lab.name, tag });
                        continue;
                    }
                    slots[ri] = .{ .ref = lab.pos };
                } else {
                    try rest.append(a, .{ .spread = lab.pos });
                }
            } else if (containsName(kind.side, lab.name)) {
                if (sides) |s| try s.append(a, .{ .role = lab.name, .pos = lab.pos });
            } else {
                self.err(lctx, "label '{s}' is neither a role nor a side-band role of '{s}' (roles: {f})", .{ lab.name, tag, fmtRoles(kind) });
            }
        }

        var items: std.ArrayListUnmanaged(ActionItem) = .empty;
        for (slots, 0..) |s, i| {
            const role = roles[i];
            if (s == null and !role.optional)
                self.err(ctx, "required role '{s}' of '{s}' is not filled", .{ role.name, tag });
            try items.append(a, .{ .role = role.name, .elem = s orelse .nil });
        }
        for (rest.items) |e| try items.append(a, .{ .role = restRole.?.name, .elem = e });
        return .{ .head = l.head, .items = try items.toOwnedSlice(a) };
    }

    fn placeElem(self: *Resolver, ctx: Ctx, e: ActionElem) Error!ActionElem {
        return switch (e) {
            .node => |n| blk: {
                const p = try self.a.create(ActionList);
                p.* = try self.place(ctx, n.*, &.{}, null);
                break :blk .{ .node = p };
            },
            else => e,
        };
    }

    /// Record a tag literal's use: allowed values of a `tag(...)` role are
    /// checked, unrestricted `tag` roles declare their values, and any
    /// other use must name a declared tag.
    fn noteTag(self: *Resolver, ctx: Ctx, e: ActionElem, role: ?Schema.Role) Error!void {
        const t = switch (e) {
            .tagLit => |t| t,
            else => return,
        };
        if (role) |r| switch (r.type) {
            .tag => |values| {
                if (values.len == 0) {
                    if (!self.declaredTags.contains(t) and !self.kindIndex.contains(t) and !containsName(self.markers.items, t))
                        try self.markers.append(self.a, t);
                    return;
                }
                if (!containsName(values, t)) self.err(ctx, "role '{s}' takes one of {f}, not '{s}'", .{ r.name, fmtList(values), t });
                return;
            },
            .any => {},
            else => {
                self.err(ctx, "tag literal '{s}' in role '{s}', which takes {s}", .{ t, r.name, typeName(r.type) });
                return;
            },
        };
        if (self.declaredTags.contains(t) or self.kindIndex.contains(t) or containsName(self.markers.items, t)) return;
        if (!containsName(self.undeclaredTags.items, t)) try self.undeclaredTags.append(self.a, t);
    }

    fn undeclaredKind(self: *Resolver, tag: []const u8, l: ActionList) !void {
        try self.undeclaredKinds.append(self.a, .{ .tag = tag, .list = l });
    }

    fn checkInventory(self: *Resolver) Error!void {
        var unbuilt: std.ArrayListUnmanaged([]const u8) = .empty;
        for (self.schema.kinds) |k| {
            if (!k.wrapper and !self.built.contains(k.tag)) try unbuilt.append(self.a, k.tag);
        }
        if (self.undeclaredKinds.items.len == 0 and self.undeclaredTags.items.len == 0 and unbuilt.items.len == 0) return;
        self.failed = true;

        var out: std.Io.Writer.Allocating = .init(self.a);
        const w = &out.writer;
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        for (self.undeclaredKinds.items) |u| {
            if (seen.contains(u.tag)) continue;
            try seen.put(self.a, u.tag, {});
            w.print("{s}: error: undeclared kind '{s}' (an action builds it; @schema does not declare it)\n", .{ self.path, u.tag }) catch return error.OutOfMemory;
        }
        for (unbuilt.items) |t| w.print("{s}: error: kind '{s}' is declared but no rule builds it (mark it @wrapper if a lang Parser does)\n", .{ self.path, t }) catch return error.OutOfMemory;
        for (self.undeclaredTags.items) |t| w.print("{s}: error: undeclared tag '{s}' (list it in @tags or as a tag(...) value)\n", .{ self.path, t }) catch return error.OutOfMemory;

        w.writeAll("the actions' inventory, ready to paste:\n\n@schema\n") catch return error.OutOfMemory;
        for (self.schema.kinds) |k| {
            if (!k.wrapper and !self.built.contains(k.tag)) continue;
            writeKind(w, k) catch return error.OutOfMemory;
        }
        seen.clearRetainingCapacity();
        for (self.undeclaredKinds.items) |u| {
            if (seen.contains(u.tag)) continue;
            try seen.put(self.a, u.tag, {});
            self.writeInferred(w, u.tag) catch return error.OutOfMemory;
        }
        if (self.schema.extraTags.len > 0 or self.undeclaredTags.items.len > 0) {
            w.writeAll("@tags") catch return error.OutOfMemory;
            for (self.schema.extraTags) |t| writeName(w, " ", t) catch return error.OutOfMemory;
            for (self.undeclaredTags.items) |t| writeName(w, " ", t) catch return error.OutOfMemory;
            w.writeByte('\n') catch return error.OutOfMemory;
        }
        std.debug.print("{s}", .{out.written()});
    }

    /// A kind line inferred from the actions that build an undeclared kind:
    /// the longest item list, role names from `role:` items where given
    /// (else r1, r2, ...), `?` where some action leaves the slot out or nil,
    /// `...rest` for a spread.
    fn writeInferred(self: *Resolver, w: *std.Io.Writer, tag: []const u8) !void {
        var width: usize = 0;
        for (self.undeclaredKinds.items) |u| if (std.mem.eql(u8, u.tag, tag)) {
            width = @max(width, u.list.items.len);
        };
        try writeName(w, "    ", tag);
        for (0..width) |i| {
            var name: ?[]const u8 = null;
            var optional = false;
            var spread = false;
            for (self.undeclaredKinds.items) |u| {
                if (!std.mem.eql(u8, u.tag, tag)) continue;
                if (i >= u.list.items.len) {
                    optional = true;
                    continue;
                }
                const item = u.list.items[i];
                if (name == null) name = item.role;
                if (item.elem == .nil) optional = true;
                if (item.elem == .spread) spread = true;
            }
            try w.writeByte(' ');
            if (spread) try w.writeAll("...");
            if (name) |n| try w.writeAll(n) else try w.print("r{d}", .{i + 1});
            if (optional and !spread) try w.writeByte('?');
        }
        try w.writeByte('\n');
    }

    // --- Coverage ---

    fn checkCoverage(self: *Resolver, ctx: Ctx, alt: ParsedAlternative, layout: Layout, aliases: *const std.StringHashMapUnmanaged([]const u8)) Error!void {
        const used = try self.a.alloc(bool, layout.slots.len + 1);
        @memset(used, false);
        markTree(alt.actionTree.?, used);
        for (1..layout.slots.len + 1) |p| {
            const e = layout.element(alt.elements, p);
            if (used[p] or e.label != null or e.skip) continue;
            const s = layout.slots[p - 1];
            if (s.kind == .choice) {
                // A choice not used as a whole: its elements are checked
                // one by one (their internal positions).
                continue;
            }
            if (!self.valueBearing(e, aliases)) continue;
            if (s.kind == .choiceElem) {
                // Covered when the whole choice is used and this is its
                // alternative's only element.
                const choice = alt.elements[s.elem];
                const choicePos = for (layout.slots[0..layout.length], 1..) |cs, q| {
                    if (cs.elem == s.elem) break q;
                } else unreachable;
                if (used[choicePos] and choice.choices[s.sub].len == 1) continue;
                if (choice.label != null) continue;
            }
            const where = if (p <= layout.length) "element" else "choice element";
            if (p <= layout.length) {
                self.err(ctx, "{s} {d} ({s}) carries a value the action does not use; use it, label it, or drop it with !X or _:X (or opt out with ~ \"reason\")", .{ where, p, e.value });
            } else {
                self.err(ctx, "{s} '{s}' carries a value the action does not use; label it or drop it with !X or _:X (or opt out with ~ \"reason\")", .{ where, e.value });
            }
        }
    }

    fn markTree(tree: ActionTree, used: []bool) void {
        switch (tree) {
            .pass => |p| used[p] = true,
            .nil => {},
            .list => |l| markList(l, used),
        }
    }

    fn markList(l: ActionList, used: []bool) void {
        switch (l.head) {
            .ref => |e| markElem(e, used),
            else => {},
        }
        for (l.items) |item| markElem(item.elem, used);
    }

    fn markElem(e: ActionElem, used: []bool) void {
        switch (e) {
            .ref, .spread, .symId => |p| used[p] = true,
            .node => |n| markList(n.*, used),
            else => {},
        }
    }

    /// Whether an element's value matters: rule references, lists and
    /// groups, and tokens whose text varies (a lexer pattern that is not a
    /// single literal, or an `@as` fallback terminal). Literals and keyword
    /// or structure tokens carry no value.
    fn valueBearing(self: *Resolver, e: ParsedElement, aliases: *const std.StringHashMapUnmanaged([]const u8)) bool {
        if (e.skip) return false;
        if (e.label) |l| if (std.mem.eql(u8, l, "_")) return false;
        return switch (e.kind) {
            .string => false,
            .token => self.tokenBearing(e.value),
            .ident => if (aliases.get(e.value)) |target| (if (isUpper(target)) self.tokenBearing(target) else true) else true,
            .reqList, .optList => true,
            .group => for (e.subElements) |sub| {
                if (self.valueBearing(sub, aliases)) break true;
            } else false,
            .choice => for (e.choices) |c| {
                for (c) |sub| if (self.valueBearing(sub, aliases)) return true;
            } else false,
            .optGroup => true,
        };
    }

    fn tokenBearing(self: *Resolver, name: []const u8) bool {
        for (self.ir.asDirectives) |d| {
            if (std.ascii.eqlIgnoreCase(d.rule, name)) return true;
            if (std.ascii.eqlIgnoreCase(d.token, name)) return true;
        }
        const spec = self.lexer orelse return true;
        for (spec.rules.items) |rule| {
            if (std.ascii.eqlIgnoreCase(rule.token, name) and !isLiteralPattern(rule.pattern)) return true;
        }
        return false;
    }
};

fn isUpper(s: []const u8) bool {
    return s.len > 0 and s[0] >= 'A' and s[0] <= 'Z';
}

/// A lexer pattern that is one quoted literal (`'x'`, `"->"`): its token's
/// text never varies.
fn isLiteralPattern(pattern: []const u8) bool {
    const p = std.mem.trim(u8, pattern, " \t");
    if (p.len < 2) return false;
    const q = p[0];
    if (q != '\'' and q != '"') return false;
    var i: usize = 1;
    while (i < p.len) : (i += 1) {
        if (p[i] == '\\') {
            i += 1;
            continue;
        }
        if (p[i] == q) return i == p.len - 1;
    }
    return false;
}

fn roleIndex(roles: []const Schema.Role, name: []const u8) ?usize {
    for (roles, 0..) |r, i| if (std.mem.eql(u8, r.name, name)) return i;
    return null;
}

fn containsName(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn typeName(t: Schema.RoleType) []const u8 {
    return switch (t) {
        .any => "any value",
        .node => "a node",
        .leaf => "a leaf",
        .tag => "a tag",
        .group => "a group (an untagged list)",
        .kinds => "a node of the listed kinds",
    };
}

fn fmtRoles(k: Schema.Kind) std.fmt.Alt(Schema.Kind, writeRoleNames) {
    return .{ .data = k };
}

fn writeRoleNames(k: Schema.Kind, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (k.roles.len == 0) return w.writeAll("none");
    for (k.roles, 0..) |r, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(r.name);
    }
}

fn fmtList(names: []const []const u8) std.fmt.Alt([]const []const u8, writeList) {
    return .{ .data = names };
}

fn writeList(names: []const []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (names, 0..) |n, i| {
        if (i > 0) try w.writeAll("|");
        try w.writeAll(n);
    }
}

fn isIdent(s: []const u8) bool {
    if (s.len == 0 or !(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}

/// A kind or tag name as written in `@schema`: bare when it is an
/// identifier, quoted otherwise.
fn writeName(w: *std.Io.Writer, prefix: []const u8, name: []const u8) !void {
    try w.writeAll(prefix);
    if (isIdent(name)) return w.writeAll(name);
    try w.writeByte('"');
    for (name) |c| {
        if (c == '"' or c == '\\') try w.writeByte('\\');
        try w.writeByte(c);
    }
    try w.writeByte('"');
}

/// One declared kind as an `@schema` line.
pub fn writeKind(w: *std.Io.Writer, k: Schema.Kind) !void {
    try writeName(w, "    ", k.tag);
    for (k.roles) |r| {
        try w.writeByte(' ');
        if (r.rest) try w.writeAll("...");
        try w.writeAll(r.name);
        switch (r.type) {
            .any => {},
            .node => try w.writeAll(":node"),
            .leaf => try w.writeAll(":leaf"),
            .group => try w.writeAll(":group"),
            .tag => |values| {
                try w.writeAll(":tag");
                if (values.len > 0) {
                    try w.writeByte('(');
                    for (values, 0..) |v, i| try writeName(w, if (i > 0) "|" else "", v);
                    try w.writeByte(')');
                }
            },
            .kinds => |names| for (names, 0..) |n, i| try writeName(w, if (i > 0) "|" else ":", n),
        }
        if (r.optional) try w.writeByte('?');
    }
    if (k.side.len > 0) {
        try w.writeAll(" |");
        for (k.side) |s| try writeName(w, " ", s);
    }
    if (k.wrapper) try w.writeAll(" @wrapper");
    try w.writeByte('\n');
}

// =============================================================================
// After expansion: static result types
// =============================================================================

/// A set of possible values: nil, leaf, tag, untagged list, and one bit per
/// schema kind.
const Types = struct {
    bits: std.DynamicBitSetUnmanaged,

    const nil = 0;
    const leaf = 1;
    const tag = 2;
    const list = 3;
    const firstKind = 4;
};

/// Check every role of every node construction against the static result
/// types of the nonterminals that fill it.
pub fn checkTypes(allocator: Allocator, g: *const Grammar, path: []const u8) Error!void {
    var c = TypeChecker{ .a = allocator, .g = g, .schema = g.schema.?, .path = path };
    return c.run();
}

const TypeChecker = struct {
    a: Allocator,
    g: *const Grammar,
    schema: Schema,
    path: []const u8,
    failed: bool = false,
    width: usize = 0,
    /// Per symbol: the values it can produce, and the items of the lists it
    /// can produce.
    result: []std.DynamicBitSetUnmanaged = &.{},
    items: []std.DynamicBitSetUnmanaged = &.{},
    kindIndex: std.StringHashMapUnmanaged(u16) = .empty,
    reported: std.AutoHashMapUnmanaged(u64, void) = .empty,

    fn run(self: *TypeChecker) Error!void {
        const a = self.a;
        const g = self.g;
        for (self.schema.kinds, 0..) |k, i| try self.kindIndex.put(a, k.tag, @intCast(i));
        self.width = Types.firstKind + self.schema.kinds.len;
        const n = g.symbols.items.len;
        self.result = try a.alloc(std.DynamicBitSetUnmanaged, n);
        self.items = try a.alloc(std.DynamicBitSetUnmanaged, n);
        for (g.symbols.items, 0..) |symbol, i| {
            self.result[i] = try std.DynamicBitSetUnmanaged.initEmpty(a, self.width);
            self.items[i] = try std.DynamicBitSetUnmanaged.initEmpty(a, self.width);
            if (symbol.kind == .terminal) self.result[i].set(Types.leaf);
        }

        // Fixpoint: add each rule's possible results to its lhs until
        // nothing changes.
        var scratch = try std.DynamicBitSetUnmanaged.initEmpty(a, self.width);
        var scratchItems = try std.DynamicBitSetUnmanaged.initEmpty(a, self.width);
        var changed = true;
        while (changed) {
            changed = false;
            for (g.rules.items) |rule| {
                scratch.unsetAll();
                scratchItems.unsetAll();
                self.ruleResult(rule, &scratch, &scratchItems);
                changed = unionInto(&self.result[rule.lhs], scratch) or changed;
                changed = unionInto(&self.items[rule.lhs], scratchItems) or changed;
            }
        }

        for (g.rules.items, 0..) |rule, ri| {
            const tree = rule.actionTree orelse continue;
            switch (tree) {
                .list => |l| try self.checkList(@intCast(ri), l),
                else => {},
            }
        }
        if (self.failed) return error.SemanticError;
    }

    fn unionInto(dst: *std.DynamicBitSetUnmanaged, src: std.DynamicBitSetUnmanaged) bool {
        var changed = false;
        var it = src.iterator(.{});
        while (it.next()) |b| if (!dst.isSet(b)) {
            dst.set(b);
            changed = true;
        };
        return changed;
    }

    fn sym(rule: grammar.Rule, pos: u16) u16 {
        return rule.rhs[pos - 1 + rule.actionOffset];
    }

    fn ruleResult(self: *TypeChecker, rule: grammar.Rule, out: *std.DynamicBitSetUnmanaged, items: *std.DynamicBitSetUnmanaged) void {
        const tree = rule.actionTree orelse {
            switch (rule.rhs.len) {
                0 => out.set(Types.nil),
                1 => {
                    _ = unionInto(out, self.result[rule.rhs[0]]);
                    _ = unionInto(items, self.items[rule.rhs[0]]);
                },
                else => {
                    out.set(Types.list);
                    for (rule.rhs) |s| _ = unionInto(items, self.result[s]);
                },
            }
            return;
        };
        switch (tree) {
            .nil => out.set(Types.nil),
            .pass => |p| {
                _ = unionInto(out, self.result[sym(rule, p)]);
                _ = unionInto(items, self.items[sym(rule, p)]);
            },
            .list => |l| self.listResult(rule, l, out, items),
        }
    }

    fn listResult(self: *TypeChecker, rule: grammar.Rule, l: ActionList, out: *std.DynamicBitSetUnmanaged, items: *std.DynamicBitSetUnmanaged) void {
        switch (l.head) {
            .tag => |t| if (self.kindIndex.get(t)) |k| {
                out.set(Types.firstKind + k);
                return;
            },
            .ref => |e| self.elemInto(rule, e, items),
            .none => {},
        }
        out.set(Types.list);
        for (l.items) |item| self.elemInto(rule, item.elem, items);
    }

    /// The values an item contributes to a list (a spread contributes its
    /// list's items).
    fn elemInto(self: *TypeChecker, rule: grammar.Rule, e: ActionElem, out: *std.DynamicBitSetUnmanaged) void {
        switch (e) {
            .ref => |p| _ = unionInto(out, self.result[sym(rule, p)]),
            .spread => |p| _ = unionInto(out, self.items[sym(rule, p)]),
            .symId => out.set(Types.leaf),
            .nil => out.set(Types.nil),
            .tagLit => out.set(Types.tag),
            .node => |n| switch (n.head) {
                .tag => |t| if (self.kindIndex.get(t)) |k| out.set(Types.firstKind + k) else out.set(Types.list),
                else => out.set(Types.list),
            },
            .label => {},
        }
    }

    fn allowed(self: *TypeChecker, role: Schema.Role, forRest: bool) !std.DynamicBitSetUnmanaged {
        var set = try std.DynamicBitSetUnmanaged.initEmpty(self.a, self.width);
        if (role.optional or forRest) set.set(Types.nil);
        switch (role.type) {
            .any => {
                set.set(Types.leaf);
                set.set(Types.tag);
                for (0..self.schema.kinds.len) |k| set.set(Types.firstKind + k);
            },
            .node => {
                set.set(Types.leaf);
                for (0..self.schema.kinds.len) |k| set.set(Types.firstKind + k);
            },
            .leaf => set.set(Types.leaf),
            .tag => set.set(Types.tag),
            .group => set.set(Types.list),
            .kinds => |names| for (names) |nm| set.set(Types.firstKind + self.kindIndex.get(nm).?),
        }
        return set;
    }

    fn checkList(self: *TypeChecker, ruleId: u16, l: ActionList) Error!void {
        const rule = self.g.rules.items[ruleId];
        for (l.items) |item| if (item.elem == .node) try self.checkList(ruleId, item.elem.node.*);
        const t = switch (l.head) {
            .tag => |t| t,
            else => return,
        };
        const k = self.kindIndex.get(t) orelse return;
        const kind = self.schema.kinds[k];
        const roles = kind.roles;
        const slotCount = if (roles.len > 0 and roles[roles.len - 1].rest) roles.len - 1 else roles.len;
        var actual = try std.DynamicBitSetUnmanaged.initEmpty(self.a, self.width);
        for (l.items, 0..) |item, i| {
            const forRest = i >= slotCount;
            const role = roles[@min(i, roles.len - 1)];
            const ok = try self.allowed(role, forRest);
            actual.unsetAll();
            var source: ?u16 = null;
            switch (item.elem) {
                .spread => |p| {
                    source = sym(rule, p);
                    _ = unionInto(&actual, self.items[source.?]);
                    // A spread splices a list; spreading a node or leaf is a mistake.
                    var whole = try self.result[source.?].clone(self.a);
                    whole.unset(Types.nil);
                    whole.unset(Types.list);
                    if (whole.count() > 0) try self.report(ruleId, role, kind, item.elem, whole, "a spread of a value that is not a list");
                },
                .ref => |p| {
                    source = sym(rule, p);
                    _ = unionInto(&actual, self.result[source.?]);
                },
                else => self.elemInto(rule, item.elem, &actual),
            }
            var bad = try actual.clone(self.a);
            var it = ok.iterator(.{});
            while (it.next()) |b| bad.unset(b);
            if (bad.count() > 0) try self.report(ruleId, role, kind, item.elem, bad, null);
        }
    }

    fn report(self: *TypeChecker, ruleId: u16, role: Schema.Role, kind: Schema.Kind, e: ActionElem, bad: std.DynamicBitSetUnmanaged, what: ?[]const u8) Error!void {
        const rule = self.g.rules.items[ruleId];
        // One message per source alternative and role.
        var h = std.hash.Wyhash.init(rule.line);
        h.update(std.mem.asBytes(&rule.col));
        h.update(role.name);
        h.update(kind.tag);
        const key = h.final();
        if (self.reported.contains(key)) return;
        try self.reported.put(self.a, key, {});
        self.failed = true;

        var out: std.Io.Writer.Allocating = .init(self.a);
        const w = &out.writer;
        self.describe(w, ruleId, role, kind, e, bad, what) catch return error.OutOfMemory;
        diag.errLine(self.path, rule.line, rule.col, "{s}", .{out.written()});
    }

    fn describe(self: *TypeChecker, w: *std.Io.Writer, ruleId: u16, role: Schema.Role, kind: Schema.Kind, e: ActionElem, bad: std.DynamicBitSetUnmanaged, what: ?[]const u8) !void {
        const g = self.g;
        const rule = g.rules.items[ruleId];
        try w.writeAll("rule '");
        try writeSymbol(w, g, rule.lhs);
        try w.print("': role '{s}' of '{s}' takes ", .{ role.name, kind.tag });
        try self.writeAllowed(w, role);
        switch (e) {
            .ref, .spread => |p| {
                try w.print(", but element {d} (", .{p});
                try writeSymbol(w, g, sym(rule, p));
                try w.writeAll(")");
            },
            else => try w.writeAll(", but the action"),
        }
        if (what) |s| {
            try w.print(" is {s}", .{s});
        } else {
            try w.writeAll(" can be ");
            try self.writeTypes(w, bad);
        }
        // Name a production that yields the first offending value.
        const s = switch (e) {
            .ref, .spread => |p| sym(rule, p),
            else => return,
        };
        var it = bad.iterator(.{});
        const b = it.next() orelse return;
        if (self.producer(s, b, e == .spread)) |pr| {
            try w.writeAll(" (from ");
            try @import("lr/conflicts.zig").writeRule(w, g, pr);
            const pl = g.rules.items[pr].line;
            if (pl > 0) try w.print(", line {d}", .{pl});
            try w.writeAll(")");
        }
    }

    /// A rule of nonterminal `s` (or of the nonterminals it passes through)
    /// whose result includes type bit `b`.
    fn producer(self: *TypeChecker, s: u16, b: usize, asItem: bool) ?u16 {
        var visited = std.DynamicBitSetUnmanaged.initEmpty(self.a, self.g.symbols.items.len) catch return null;
        return self.findProducer(s, b, asItem, &visited);
    }

    fn findProducer(self: *TypeChecker, s: u16, b: usize, asItem: bool, visited: *std.DynamicBitSetUnmanaged) ?u16 {
        if (visited.isSet(s)) return null;
        visited.set(s);
        var one = std.DynamicBitSetUnmanaged.initEmpty(self.a, self.width) catch return null;
        var items = std.DynamicBitSetUnmanaged.initEmpty(self.a, self.width) catch return null;
        for (self.g.symbols.items[s].rules.items) |ri| {
            one.unsetAll();
            items.unsetAll();
            const rule = self.g.rules.items[ri];
            self.ruleResult(rule, &one, &items);
            const hit = if (asItem) items.isSet(b) else one.isSet(b);
            if (!hit) continue;
            // Follow a pass-through to the rule that builds the value.
            const via: ?u16 = if (rule.actionTree) |t| switch (t) {
                .pass => |p| sym(rule, p),
                else => null,
            } else if (rule.rhs.len == 1) rule.rhs[0] else null;
            if (via) |v| if (self.g.symbols.items[v].kind == .nonterminal) {
                if (self.findProducer(v, b, asItem, visited)) |deeper| return deeper;
            };
            return @intCast(ri);
        }
        return null;
    }

    fn writeAllowed(self: *TypeChecker, w: *std.Io.Writer, role: Schema.Role) !void {
        _ = self;
        switch (role.type) {
            .kinds => |names| for (names, 0..) |n, i| {
                if (i > 0) try w.writeAll("|");
                try w.writeAll(n);
            },
            else => try w.writeAll(typeName(role.type)),
        }
        if (role.optional) try w.writeAll(" or nil");
    }

    fn writeTypes(self: *TypeChecker, w: *std.Io.Writer, set: std.DynamicBitSetUnmanaged) !void {
        var it = set.iterator(.{});
        var first = true;
        while (it.next()) |b| {
            if (!first) try w.writeAll(", ");
            first = false;
            switch (b) {
                Types.nil => try w.writeAll("nil"),
                Types.leaf => try w.writeAll("a leaf"),
                Types.tag => try w.writeAll("a tag"),
                Types.list => try w.writeAll("an untagged list"),
                else => try w.print("a '{s}' node", .{self.schema.kinds[b - Types.firstKind].tag}),
            }
        }
    }
};
