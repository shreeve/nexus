//! Strict lowering of the frontend's S-expression tree into the grammar IR.
//!
//! The tree's shapes are documented at the top of nexus.grammar. Every
//! lowering entry point accepts exactly those shapes; anything else is a
//! hard error (`error.ShapeError`) reported at a source position. Semantic
//! mistakes the tree can express (an unknown associativity, a position 0,
//! a missing conflict rationale, ...) are reported the same way, as
//! `error.LowerError`. There are no silent defaults and no heuristic
//! unwrapping.

const std = @import("std");
const diag = @import("../diag.zig");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Sexp = parser.Sexp;
const Tag = parser.Tag;
const grammar = @import("../grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const InfixDecl = grammar.InfixDecl;
const InfixOp = grammar.InfixOp;
const AsDirective = grammar.AsDirective;
const OpMapping = grammar.OpMapping;
const ErrorName = grammar.ErrorName;
const Schema = grammar.Schema;
const ActionTree = grammar.ActionTree;
const ActionList = grammar.ActionList;
const ActionItem = grammar.ActionItem;
const ActionElem = grammar.ActionElem;
const ConflictEntry = grammar.ConflictEntry;
const DisplayName = grammar.DisplayName;

pub const LowerError = error{ ShapeError, LowerError, OutOfMemory };

pub const GrammarLowerer = struct {
    allocator: Allocator,
    /// The grammar file; `.src` positions are relative to `source.base`
    /// (the start of the @parser body).
    source: diag.Source,

    rules: std.ArrayListUnmanaged(ParsedRule) = .empty,
    startSymbols: std.ArrayListUnmanaged([]const u8) = .empty,
    asDirectives: std.ArrayListUnmanaged(AsDirective) = .empty,
    opMappings: std.ArrayListUnmanaged(OpMapping) = .empty,
    errorNames: std.ArrayListUnmanaged(ErrorName) = .empty,
    displayNames: std.ArrayListUnmanaged(DisplayName) = .empty,
    infixOps: std.ArrayListUnmanaged(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    expectConflicts: ?u32 = null,
    conflicts: std.ArrayListUnmanaged(ConflictEntry) = .empty,
    hasManifest: bool = false,
    kinds: std.ArrayListUnmanaged(Schema.Kind) = .empty,
    hasSchema: bool = false,
    extraTags: std.ArrayListUnmanaged([]const u8) = .empty,
    tagsNode: ?Sexp = null,
    trivia: std.ArrayListUnmanaged([]const u8) = .empty,
    repair: ?grammar.RepairSpec = null,

    pub fn lower(allocator: Allocator, sexp: Sexp, source: diag.Source) LowerError!GrammarIR {
        var self = GrammarLowerer{ .allocator = allocator, .source = source };
        try self.lowerRoot(sexp);
        if (self.tagsNode) |node| if (!self.hasSchema)
            return self.fail(node, "@tags lists extra schema tags; it needs an @schema", .{});
        if (self.hasManifest and self.expectConflicts != null)
            return self.fail(sexp, "use either `@conflicts = N` or an `@conflicts` block, not both", .{});
        return GrammarIR{
            .rules = try self.rules.toOwnedSlice(allocator),
            .startSymbols = try self.startSymbols.toOwnedSlice(allocator),
            .asDirectives = try self.asDirectives.toOwnedSlice(allocator),
            .opMappings = try self.opMappings.toOwnedSlice(allocator),
            .errorNames = try self.errorNames.toOwnedSlice(allocator),
            .infix = if (self.infixBase) |base| InfixDecl{
                .baseRule = base,
                .ops = try self.infixOps.toOwnedSlice(allocator),
            } else null,
            .lang = self.lang,
            .expectConflicts = self.expectConflicts,
            .schema = if (self.hasSchema) Schema{
                .kinds = try self.kinds.toOwnedSlice(allocator),
                .extraTags = try self.extraTags.toOwnedSlice(allocator),
            } else null,
            .conflicts = try self.conflicts.toOwnedSlice(allocator),
            .displayNames = try self.displayNames.toOwnedSlice(allocator),
            .trivia = try self.trivia.toOwnedSlice(allocator),
            .repair = self.repair,
        };
    }

    // --- Shape helpers ---

    fn listItems(node: Sexp) ?[]const Sexp {
        return switch (node) {
            .list => |items| items,
            else => null,
        };
    }

    const Tagged = struct { tag: Tag, items: []const Sexp };

    fn taggedItems(node: Sexp) ?Tagged {
        const items = listItems(node) orelse return null;
        if (items.len == 0) return null;
        const tag = switch (items[0]) {
            .tag => |t| t,
            else => return null,
        };
        return .{ .tag = tag, .items = items };
    }

    /// Child `i` of a list whose trailing nil children were omitted.
    fn slot(items: []const Sexp, i: usize) Sexp {
        return if (i < items.len) items[i] else .nil;
    }

    fn stripQuotes(s: []const u8) []const u8 {
        if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
        return s;
    }

    /// The first source position inside `node`, if any.
    fn firstPos(node: Sexp) ?u32 {
        return switch (node) {
            .src => |s| s.pos,
            .list => |items| for (items) |item| {
                if (firstPos(item)) |p| break p;
            } else null,
            else => null,
        };
    }

    fn report(self: *const GrammarLowerer, node: Sexp, comptime fmt: []const u8, args: anytype) void {
        // The negative tests fire these paths by design; keep their output clean.
        if (@import("builtin").is_test) return;
        diag.errAt(self.source, firstPos(node) orelse 0, fmt, args);
    }

    fn shapeError(self: *const GrammarLowerer, node: Sexp, expected: []const u8) LowerError {
        self.report(node, "malformed frontend tree: expected {s}", .{expected});
        return error.ShapeError;
    }

    fn fail(self: *const GrammarLowerer, node: Sexp, comptime fmt: []const u8, args: anytype) LowerError {
        self.report(node, fmt, args);
        return error.LowerError;
    }

    fn loc(self: *const GrammarLowerer, node: Sexp) diag.Source.Loc {
        return self.source.at(firstPos(node) orelse 0);
    }

    fn requireTag(self: *const GrammarLowerer, node: Sexp, expected: Tag) LowerError![]const Sexp {
        const t = taggedItems(node) orelse return self.shapeError(node, @tagName(expected));
        if (t.tag != expected) return self.shapeError(node, @tagName(expected));
        return t.items;
    }

    fn requireArity(self: *const GrammarLowerer, node: Sexp, items: []const Sexp, min: usize, max: usize, what: []const u8) LowerError!void {
        if (items.len < min or items.len > max) return self.shapeError(node, what);
    }

    fn text(self: *const GrammarLowerer, s: anytype) []const u8 {
        return self.source.text[self.source.base + s.pos ..][0..s.len];
    }

    fn requireSrc(self: *const GrammarLowerer, node: Sexp, what: []const u8) LowerError![]const u8 {
        return switch (node) {
            .src => |s| self.text(s),
            else => self.shapeError(node, what),
        };
    }

    fn optSrc(self: *const GrammarLowerer, node: Sexp, what: []const u8) LowerError!?[]const u8 {
        return switch (node) {
            .nil => null,
            .src => |s| self.text(s),
            else => self.shapeError(node, what),
        };
    }

    fn requireList(self: *const GrammarLowerer, node: Sexp, what: []const u8) LowerError![]const Sexp {
        return listItems(node) orelse self.shapeError(node, what);
    }

    /// A kind-discriminator slot: nil, or one of the allowed tags.
    fn flag(self: *const GrammarLowerer, parent: Sexp, node: Sexp, allowed: []const Tag, what: []const u8) LowerError!?Tag {
        switch (node) {
            .nil => return null,
            .tag => |t| {
                for (allowed) |a| if (a == t) return t;
                return self.shapeError(parent, what);
            },
            else => return self.shapeError(parent, what),
        }
    }

    fn parseCount(self: *const GrammarLowerer, node: Sexp, what: []const u8) LowerError!u32 {
        const t = try self.requireSrc(node, what);
        return std.fmt.parseInt(u32, t, 10) catch self.fail(node, "{s} '{s}' is not a number", .{ what, t });
    }

    // --- Root ---

    fn lowerRoot(self: *GrammarLowerer, sexp: Sexp) LowerError!void {
        const items = try self.requireTag(sexp, .grammar);
        for (items[1..]) |entry| try self.lowerEntry(entry);
    }

    fn lowerEntry(self: *GrammarLowerer, entry: Sexp) LowerError!void {
        const t = taggedItems(entry) orelse return self.shapeError(entry, "directive or rule");
        switch (t.tag) {
            .lang => try self.lowerLang(entry, t.items),
            .conflicts => try self.lowerConflictCount(entry, t.items),
            .manifest => try self.lowerManifest(entry, t.items),
            .as => try self.lowerAs(entry, t.items),
            .op => try self.lowerOp(entry, t.items),
            .errors => try self.lowerErrors(entry, t.items),
            .display => try self.lowerDisplay(entry, t.items),
            .infix => try self.lowerInfix(entry, t.items),
            .schema => try self.lowerSchema(entry, t.items),
            .tags => try self.lowerTags(entry, t.items),
            .trivia => try self.lowerTrivia(entry, t.items),
            .repair => try self.lowerRepair(entry, t.items),
            .rule => try self.lowerRule(entry, t.items),
            else => return self.shapeError(entry, "directive or rule"),
        }
    }

    // --- Directives ---

    fn lowerLang(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        try self.requireArity(node, items, 2, 2, "(lang STRING)");
        self.lang = stripQuotes(try self.requireSrc(items[1], "language-name string"));
    }

    fn lowerConflictCount(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        try self.requireArity(node, items, 2, 2, "(conflicts INTEGER)");
        if (self.expectConflicts != null) return self.fail(node, "duplicate `@conflicts = N`", .{});
        self.expectConflicts = try self.parseCount(items[1], "conflict count");
    }

    fn lowerManifest(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(manifest CONFLICT+)");
        self.hasManifest = true;
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .conflict);
            try self.requireArity(entry, et, 3, 6, "(conflict KIND CRULE OVER COUNT REASON)");
            const kindName = try self.requireSrc(et[1], "conflict kind");
            const kind: @FieldType(ConflictEntry, "kind") = if (std.mem.eql(u8, kindName, "shift"))
                .shift
            else if (std.mem.eql(u8, kindName, "reduce"))
                .reduce
            else
                return self.fail(et[1], "conflict kind must be `shift` or `reduce`, not '{s}'", .{kindName});
            const rule = try self.lowerCrule(slot(et, 2));
            const over: ?[]const u8 = if (slot(et, 3) == .nil) null else try self.lowerCrule(et[3]);
            if (kind == .shift and over != null)
                return self.fail(et[3], "a `shift` entry names one rule; `over` belongs to `reduce` entries", .{});
            if (kind == .reduce and over == null)
                return self.fail(entry, "a `reduce` entry names the winning rule `over` the losing one", .{});
            if (slot(et, 4) == .nil) return self.fail(entry, "conflict entry needs a count", .{});
            const count = try self.parseCount(et[4], "conflict count");
            const reasonRaw = try self.optSrc(slot(et, 5), "rationale comment") orelse
                return self.fail(entry, "conflict entry needs a `# rationale` comment", .{});
            const reason = std.mem.trim(u8, reasonRaw[1..], " \t\r");
            if (reason.len == 0) return self.fail(et[5], "conflict rationale is empty", .{});
            const l = self.loc(entry);
            try self.conflicts.append(self.allocator, .{
                .kind = kind,
                .rule = rule,
                .over = over,
                .count = count,
                .reason = reason,
                .line = l.line,
                .col = l.col,
            });
        }
    }

    /// `(crule LHS SYM...)` as the text `lhs → sym sym` (`lhs → ε` for an
    /// empty right-hand side).
    fn lowerCrule(self: *GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const items = try self.requireTag(node, .crule);
        if (items.len < 3) return self.shapeError(node, "(crule LHS SYM+)");
        var out: std.ArrayListUnmanaged(u8) = .empty;
        try out.appendSlice(self.allocator, try self.requireSrc(items[1], "rule name"));
        try out.appendSlice(self.allocator, " \u{2192}");
        for (items[2..]) |sym| {
            const t = try self.requireSrc(sym, "symbol");
            if (std.mem.eql(u8, t, "\u{03B5}") and items.len != 3)
                return self.fail(sym, "ε stands for an empty right-hand side; it cannot be mixed with symbols", .{});
            try out.append(self.allocator, ' ');
            try out.appendSlice(self.allocator, t);
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn lowerAs(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 4) return self.shapeError(node, "(as TOKEN VIA AS_ENTRY+)");
        const token = try self.requireSrc(items[1], "@as token");
        const sharedVia = try self.optSrc(items[2], "@as lookup function");
        var groups: usize = 0;
        for (items[3..]) |entry| {
            const et = try self.requireTag(entry, .as_entry);
            try self.requireArity(entry, et, 3, 4, "(as_entry KIND IDENT VIA?)");
            const permissive = (try self.flag(entry, et[1], &.{.perm}, "(as_entry KIND ...): KIND must be _ or perm")) != null;
            const rule = try self.requireSrc(et[2], "@as group name");
            const via = try self.optSrc(slot(et, 3), "@as lookup function");
            if (std.mem.eql(u8, rule, "self")) {
                if (permissive) return self.fail(et[2], "`self!` is not allowed: `self` is a checkpoint, not a group", .{});
                if (via != null) return self.fail(et[3], "`self` has no lookup function", .{});
            } else groups += 1;
            try self.asDirectives.append(self.allocator, .{
                .token = token,
                .rule = rule,
                .permissive = permissive,
                .via = via orelse if (std.mem.eql(u8, rule, "self")) null else sharedVia,
            });
        }
        if (sharedVia != null and groups != 1)
            return self.fail(items[2], "`@as TOKEN via fn` names the lookup of a single group; give each group its own `via`", .{});
    }

    fn lowerOp(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(op OP_MAP+)");
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .op_map);
            try self.requireArity(entry, et, 3, 3, "(op_map STRING STRING)");
            const lit = stripQuotes(try self.requireSrc(et[1], "op literal"));
            const tok = stripQuotes(try self.requireSrc(et[2], "op target token"));
            try self.opMappings.append(self.allocator, .{ .lit = lit, .tok = tok });
        }
    }

    const Pair = struct { key: []const u8, name: []const u8, quoted: bool };

    fn lowerPair(self: *GrammarLowerer, entry: Sexp) LowerError!Pair {
        const et = try self.requireTag(entry, .name_pair);
        try self.requireArity(entry, et, 3, 3, "(name_pair KEY STRING)");
        const key = try self.requireSrc(et[1], "name key");
        const name = try self.requireSrc(et[2], "display string");
        if (name.len < 2 or name[0] != '"') return self.shapeError(et[2], "display string");
        return .{ .key = key, .name = stripQuotes(name), .quoted = key.len > 0 and key[0] == '"' };
    }

    fn lowerErrors(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(errors NAME_PAIR+)");
        for (items[1..]) |entry| {
            const p = try self.lowerPair(entry);
            if (p.quoted) return self.fail(entry, "@errors names rules (`rule: \"name\"`); name tokens in @display", .{});
            try self.errorNames.append(self.allocator, .{ .rule = p.key, .name = p.name });
        }
    }

    fn lowerDisplay(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(display NAME_PAIR+)");
        for (items[1..]) |entry| {
            const p = try self.lowerPair(entry);
            if (!p.quoted and !(p.key[0] >= 'A' and p.key[0] <= 'Z'))
                return self.fail(entry, "@display names tokens (`TOKEN: \"name\"` or `\"lit\": \"name\"`); name rules in @errors", .{});
            try self.displayNames.append(self.allocator, .{ .token = p.key, .name = p.name });
        }
    }

    fn lowerInfix(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 3) return self.shapeError(node, "(infix IDENT LEVEL+)");
        if (self.infixBase != null) return self.fail(node, "duplicate @infix", .{});
        self.infixBase = try self.requireSrc(items[1], "@infix base expression");
        var prec: u32 = 1;
        for (items[2..]) |level| {
            const lt = try self.requireTag(level, .level);
            if (lt.len < 2) return self.shapeError(level, "(level INFIX_OP+)");
            for (lt[1..]) |opNode| {
                const ot = try self.requireTag(opNode, .infix_op);
                try self.requireArity(opNode, ot, 3, 3, "(infix_op STRING ASSOC)");
                const op = stripQuotes(try self.requireSrc(ot[1], "operator literal"));
                const assocName = try self.requireSrc(ot[2], "associativity");
                const assoc = std.meta.stringToEnum(InfixOp.Assoc, assocName) orelse
                    return self.fail(ot[2], "associativity must be left, right or none, not '{s}'", .{assocName});
                try self.infixOps.append(self.allocator, .{ .op = op, .assoc = assoc, .prec = prec });
            }
            prec += 1;
        }
    }

    fn lowerSchema(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(schema KIND_DECL+)");
        self.hasSchema = true;
        for (items[1..]) |decl| try self.lowerKindDecl(decl);
    }

    fn lowerKindDecl(self: *GrammarLowerer, decl: Sexp) LowerError!void {
        const dt = try self.requireTag(decl, .kind_decl);
        try self.requireArity(decl, dt, 3, 5, "(kind_decl KINDS ROLES SIDES? WRAPPER?)");
        const names = try self.requireTag(dt[1], .kinds);
        if (names.len < 2) return self.shapeError(dt[1], "(kinds NAME+)");
        const roleNodes = try self.requireTag(dt[2], .roles);

        var roles: std.ArrayListUnmanaged(Schema.Role) = .empty;
        for (roleNodes[1..], 0..) |roleNode, i| {
            const role = try self.lowerRole(roleNode);
            if (role.rest and i + 1 != roleNodes.len - 1)
                return self.fail(roleNode, "rest role `...{s}` must be the last role", .{role.name});
            for (roles.items) |other| if (std.mem.eql(u8, other.name, role.name))
                return self.fail(roleNode, "duplicate role '{s}'", .{role.name});
            try roles.append(self.allocator, role);
        }

        var side: std.ArrayListUnmanaged([]const u8) = .empty;
        if (slot(dt, 3) != .nil) {
            const st = try self.requireTag(dt[3], .sides);
            if (st.len < 2) return self.shapeError(dt[3], "(sides IDENT+)");
            for (st[1..]) |s| {
                const name = try self.requireSrc(s, "side-band role name");
                for (roles.items) |r| if (std.mem.eql(u8, r.name, name))
                    return self.fail(s, "'{s}' is both a slot role and a side-band role", .{name});
                for (side.items) |o| if (std.mem.eql(u8, o, name))
                    return self.fail(s, "duplicate side-band role '{s}'", .{name});
                try side.append(self.allocator, name);
            }
        }
        const wrapper = (try self.flag(decl, slot(dt, 4), &.{.wrapper}, "(kind_decl ... WRAPPER): wrapper or _")) != null;

        const roleSlice = try roles.toOwnedSlice(self.allocator);
        const sideSlice = try side.toOwnedSlice(self.allocator);
        for (names[1..]) |nameNode| {
            const raw = try self.requireSrc(nameNode, "kind name");
            const tag = stripQuotes(raw);
            if (tag.len == 0) return self.fail(nameNode, "empty kind name", .{});
            for (self.kinds.items) |k| if (std.mem.eql(u8, k.tag, tag))
                return self.fail(nameNode, "kind '{s}' is declared twice", .{tag});
            const l = self.loc(nameNode);
            try self.kinds.append(self.allocator, .{
                .tag = tag,
                .roles = roleSlice,
                .side = sideSlice,
                .wrapper = wrapper,
                .line = l.line,
                .col = l.col,
            });
        }
    }

    fn lowerRole(self: *GrammarLowerer, node: Sexp) LowerError!Schema.Role {
        const rt = try self.requireTag(node, .role);
        try self.requireArity(node, rt, 3, 5, "(role REST NAME TYPE? OPT?)");
        const rest = (try self.flag(node, rt[1], &.{.rest}, "(role REST ...): rest or _")) != null;
        const name = try self.requireSrc(rt[2], "role name");
        if (name.len == 0 or name[0] == '_' or !std.ascii.isLower(name[0]))
            return self.fail(rt[2], "role names start with a lowercase letter: '{s}'", .{name});
        const optional = (try self.flag(node, slot(rt, 4), &.{.opt}, "(role ... OPT): opt or _")) != null;
        const roleType: Schema.RoleType = if (slot(rt, 3) == .nil) .any else try self.lowerRoleType(rt[3]);
        return .{ .name = name, .type = roleType, .optional = optional, .rest = rest };
    }

    fn lowerRoleType(self: *GrammarLowerer, node: Sexp) LowerError!Schema.RoleType {
        const tt = try self.requireTag(node, .type);
        if (tt.len < 2) return self.shapeError(node, "(type ATOM+)");
        var kinds: std.ArrayListUnmanaged([]const u8) = .empty;
        var builtin: ?Schema.RoleType = null;
        for (tt[1..]) |atom| {
            if (taggedItems(atom)) |at| {
                if (at.tag != .tagset or at.items.len < 3) return self.shapeError(atom, "(tagset tag VALUE+)");
                const head = try self.requireSrc(at.items[1], "tag");
                if (!std.mem.eql(u8, head, "tag"))
                    return self.fail(at.items[1], "only `tag(...)` takes a value list, not '{s}(...)'", .{head});
                var values: std.ArrayListUnmanaged([]const u8) = .empty;
                for (at.items[2..]) |v| try values.append(self.allocator, stripQuotes(try self.requireSrc(v, "tag value")));
                if (builtin != null or tt.len > 2) return self.fail(atom, "`tag(...)` cannot be combined with other types", .{});
                builtin = .{ .tag = try values.toOwnedSlice(self.allocator) };
                continue;
            }
            const raw = try self.requireSrc(atom, "type name");
            const b: ?Schema.RoleType = if (raw[0] == '"')
                null
            else if (std.mem.eql(u8, raw, "node"))
                .node
            else if (std.mem.eql(u8, raw, "leaf"))
                .leaf
            else if (std.mem.eql(u8, raw, "group"))
                .group
            else if (std.mem.eql(u8, raw, "tag"))
                .{ .tag = &.{} }
            else if (std.mem.eql(u8, raw, "any"))
                .any
            else
                null;
            if (b) |t| {
                if (tt.len > 2) return self.fail(atom, "`{s}` cannot be combined with other types in a union", .{raw});
                builtin = t;
            } else {
                try kinds.append(self.allocator, stripQuotes(raw));
            }
        }
        if (builtin) |b| return b;
        return .{ .kinds = try kinds.toOwnedSlice(self.allocator) };
    }

    fn lowerNames(self: *GrammarLowerer, node: Sexp, items: []const Sexp, what: []const u8, out: *std.ArrayListUnmanaged([]const u8)) LowerError!void {
        if (items.len < 2) return self.shapeError(node, what);
        for (items[1..]) |n| try out.append(self.allocator, stripQuotes(try self.requireSrc(n, "name")));
    }

    fn lowerTags(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        self.tagsNode = node;
        try self.lowerNames(node, items, "(tags NAME+)", &self.extraTags);
    }

    fn lowerTrivia(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        try self.lowerNames(node, items, "(trivia NAME+)", &self.trivia);
    }

    fn lowerRepair(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 2) return self.shapeError(node, "(repair REPAIR_LINE+)");
        if (self.repair != null) return self.fail(node, "duplicate @repair", .{});
        var holes: std.ArrayListUnmanaged([]const u8) = .empty;
        var structure: std.ArrayListUnmanaged([]const u8) = .empty;
        for (items[1..]) |line| {
            const lt = try self.requireTag(line, .repair_line);
            if (lt.len < 3) return self.shapeError(line, "(repair_line IDENT NAME+)");
            const which = try self.requireSrc(lt[1], "repair class");
            const out = if (std.mem.eql(u8, which, "holes"))
                &holes
            else if (std.mem.eql(u8, which, "structure"))
                &structure
            else
                return self.fail(lt[1], "@repair lines are `holes ...` or `structure ...`, not '{s}'", .{which});
            for (lt[2..]) |n| try out.append(self.allocator, stripQuotes(try self.requireSrc(n, "token name")));
        }
        self.repair = .{
            .holes = try holes.toOwnedSlice(self.allocator),
            .structure = try structure.toOwnedSlice(self.allocator),
        };
    }

    // --- Rules ---

    fn lowerRule(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!void {
        if (items.len < 3) return self.shapeError(node, "(rule RULE_NAME ALT+)");
        const nt = taggedItems(items[1]) orelse return self.shapeError(items[1], "(start ...) or (name ...)");
        if (nt.tag != .start and nt.tag != .name) return self.shapeError(items[1], "(start ...) or (name ...)");
        try self.requireArity(items[1], nt.items, 2, 2, "(start|name IDENT-or-TOKEN)");
        const name = try self.requireSrc(nt.items[1], "rule name");
        const isStart = nt.tag == .start;
        if (isStart) {
            for (self.startSymbols.items) |s| if (std.mem.eql(u8, s, name))
                return self.fail(items[1], "start symbol '{s}' is declared twice", .{name});
            try self.startSymbols.append(self.allocator, name);
        }

        var alts: std.ArrayListUnmanaged(ParsedAlternative) = .empty;
        for (items[2..]) |altNode| try alts.append(self.allocator, try self.lowerAlt(altNode, items[1]));

        const l = self.loc(node);
        try self.rules.append(self.allocator, .{
            .name = name,
            .isStart = isStart,
            .alternatives = try alts.toOwnedSlice(self.allocator),
            .line = l.line,
            .col = l.col,
        });
    }

    fn lowerAlt(self: *GrammarLowerer, altNode: Sexp, ruleName: Sexp) LowerError!ParsedAlternative {
        const items = try self.requireTag(altNode, .alt);
        try self.requireArity(altNode, items, 3, 5, "(alt KIND ELEMENTS ACTION? OPTOUT?)");
        const kind = try self.flag(altNode, items[1], &.{ .reduce, .shift }, "(alt KIND ...): KIND must be _, reduce or shift");

        // (exclude "c") hints are consumed here: they set the alternative's
        // excluded characters and never reach the element list.
        const rawChildren = try self.requireList(items[2], "element list");
        var elements: std.ArrayListUnmanaged(ParsedElement) = .empty;
        var exclude: std.ArrayListUnmanaged(u8) = .empty;
        for (rawChildren) |child| {
            if (taggedItems(child)) |ct| if (ct.tag == .exclude) {
                try self.requireArity(child, ct.items, 2, 2, "(exclude STRING)");
                const c = try self.hintChar(ct.items[1]);
                if (std.mem.indexOfScalar(u8, exclude.items, c) == null) try exclude.append(self.allocator, c);
                continue;
            };
            try elements.append(self.allocator, try self.lowerElement(child));
        }

        const elems = try elements.toOwnedSlice(self.allocator);
        const actionTree: ?ActionTree = if (slot(items, 3) == .nil) null else try self.lowerAction(items[3], logicalLength(elems));
        const optOut = try self.optSrc(slot(items, 4), "opt-out reason");
        if (optOut) |o| if (stripQuotes(o).len == 0) return self.fail(items[4], "an opt-out needs a reason", .{});

        const excludeChars = try exclude.toOwnedSlice(self.allocator);
        const l = self.loc(if (firstPos(items[2]) != null) items[2] else if (slot(items, 3) != .nil) items[3] else ruleName);
        return .{
            .elements = elems,
            .action = if (actionTree) |t| try grammar.renderAction(self.allocator, t) else null,
            .actionTree = actionTree,
            .optOut = if (optOut) |o| stripQuotes(o) else null,
            .excludeChar = if (excludeChars.len > 0) excludeChars[excludeChars.len - 1] else 0,
            .excludeChars = excludeChars,
            .preferReduce = kind == .reduce,
            .preferShift = kind == .shift,
            .line = l.line,
            .col = l.col,
        };
    }

    /// The character of an `X "c"` hint literal (`"c"` or an escape `"\c"`).
    fn hintChar(self: *GrammarLowerer, node: Sexp) LowerError!u8 {
        const inner = stripQuotes(try self.requireSrc(node, "exclusion literal"));
        if (inner.len == 1) return inner[0];
        if (inner.len == 2 and inner[0] == '\\') return switch (inner[1]) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            else => inner[1],
        };
        return self.fail(node, "X \"c\": the hint takes one character, not \"{s}\"", .{inner});
    }

    /// Number of action positions a pattern has: one per element, and one
    /// per sub-element of a multi-element `[A B]` group.
    pub fn logicalLength(elements: []const ParsedElement) usize {
        var n: usize = 0;
        for (elements) |e| n += if (e.kind == .optGroup) e.subElements.len else 1;
        return n;
    }

    // --- Elements ---

    fn lowerElement(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        const t = taggedItems(node) orelse return self.shapeError(node, "tagged element sexp");
        var elem = switch (t.tag) {
            .ref => try self.lowerScalarElement(node, t.items, .ident),
            .tok => try self.lowerScalarElement(node, t.items, .token),
            .lit => try self.lowerScalarElement(node, t.items, .string),
            .at_ref => try self.lowerScalarElement(node, t.items, .ident),
            .list_req => try self.lowerListElement(node, t.items),
            .group => try self.lowerGroupKinded(node, t.items),
            .quantified => try self.lowerQuantifiedElement(node, t.items),
            .skip => try self.lowerSkipElement(node, t.items, false),
            .skip_q => try self.lowerSkipElement(node, t.items, true),
            .label => try self.lowerLabeled(node, t.items),
            else => return self.shapeError(node, "element"),
        };
        if (elem.line == 0) {
            const l = self.loc(node);
            elem.line = l.line;
            elem.col = l.col;
        }
        return elem;
    }

    fn lowerLabeled(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!ParsedElement {
        try self.requireArity(node, items, 3, 3, "(label NAME ELEMENT)");
        const name = try self.requireSrc(items[1], "label name");
        if (!std.mem.eql(u8, name, "_") and (name[0] == '_' or !std.ascii.isLower(name[0])))
            return self.fail(items[1], "labels are role names (lowercase) or `_`: '{s}'", .{name});
        if (taggedItems(items[2])) |inner| switch (inner.tag) {
            .skip, .skip_q, .label => return self.fail(node, "label '{s}' needs a plain element", .{name}),
            else => {},
        };
        var elem = try self.lowerElement(items[2]);
        if (elem.kind == .optGroup) return self.fail(node, "label '{s}' on a multi-element [...] group; label its elements", .{name});
        elem.label = name;
        const l = self.loc(items[1]);
        elem.line = l.line;
        elem.col = l.col;
        return elem;
    }

    fn lowerScalarElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp, kind: ParsedElement.Kind) LowerError!ParsedElement {
        try self.requireArity(node, items, 2, 2, "(ref|tok|lit|at_ref SRC)");
        return .{ .kind = kind, .value = try self.requireSrc(items[1], "identifier/token/string") };
    }

    fn lowerListElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!ParsedElement {
        try self.requireArity(node, items, 3, 3, "(list_req TOKEN LIST_INNER)");
        _ = try self.requireSrc(items[1], "list keyword");
        const inner = taggedItems(items[2]) orelse return self.shapeError(items[2], "LIST_INNER");
        var elem = ParsedElement{ .kind = .reqList };
        switch (inner.tag) {
            .plain, .opt_items_nosep => try self.requireArity(items[2], inner.items, 2, 2, "(plain|opt_items_nosep ITEM)"),
            .sep_items, .opt_items => {
                try self.requireArity(items[2], inner.items, 3, 3, "(sep_items|opt_items ITEM SEP)");
                elem.listSeparator = try self.requireSrc(inner.items[2], "separator");
            },
            else => return self.shapeError(items[2], "plain|opt_items|sep_items|opt_items_nosep"),
        }
        elem.value = try self.requireSrc(inner.items[1], "list item");
        elem.optionalItems = inner.tag == .opt_items or inner.tag == .opt_items_nosep;
        return elem;
    }

    // `(group KIND BODY ...)`, KIND ∈ _ (parens), opt ([...]), many ([X ...]).
    fn lowerGroupKinded(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!ParsedElement {
        if (items.len < 3) return self.shapeError(node, "(group KIND BODY+)");
        const kind = try self.flag(node, items[1], &.{ .many, .opt }, "(group KIND ...): KIND must be _, many or opt");
        const bodies = items[2..];

        var lowered: std.ArrayListUnmanaged([]const ParsedElement) = .empty;
        for (bodies) |body| {
            const elems = try self.lowerAltBody(body);
            if (elems.len == 0) return self.shapeError(body, "non-empty group alternative");
            try lowered.append(self.allocator, elems);
        }

        if (kind == .many) {
            // [X ...]: an optional comma-separated list of one item.
            if (lowered.items.len != 1 or !isSingleSimpleElem(lowered.items[0]))
                return self.fail(node, "`[X ...]` takes a single rule or token name", .{});
            return .{ .kind = .optList, .value = lowered.items[0][0].value };
        }

        if (lowered.items.len > 1) {
            // (A | B | C): exactly one alternative; [A | B]: at most one.
            return .{
                .kind = .choice,
                .choices = try lowered.toOwnedSlice(self.allocator),
                .quantifier = if (kind == .opt) .optional else .one,
            };
        }
        const body = lowered.items[0];

        if (kind == null) return .{ .kind = .group, .subElements = body };

        // [L(X)]: an optional list with the same item, separator and item optionality.
        if (body.len == 1 and body[0].kind == .reqList and body[0].quantifier == .one and !body[0].skip and body[0].label == null) {
            const inner = body[0];
            return .{
                .kind = .optList,
                .value = inner.value,
                .optionalItems = inner.optionalItems,
                .listSeparator = inner.listSeparator,
            };
        }

        // [X]: the element itself with an optional quantifier.
        if (isSingleSimpleElem(body)) {
            var e = body[0];
            e.quantifier = .optional;
            return e;
        }
        if (body.len == 1 and body[0].label != null) {
            var e = body[0];
            if (e.quantifier != .one) return self.fail(node, "[X?] and similar are ambiguous; write [X] or X?", .{});
            e.quantifier = .optional;
            return e;
        }

        // [A B C]: expanded into alternatives downstream (stable positions).
        return .{ .kind = .optGroup, .value = body[0].value, .subElements = body };
    }

    fn lowerAltBody(self: *GrammarLowerer, node: Sexp) LowerError![]const ParsedElement {
        const items = try self.requireList(node, "element list");
        var out: std.ArrayListUnmanaged(ParsedElement) = .empty;
        for (items) |child| try out.append(self.allocator, try self.lowerElement(child));
        return out.toOwnedSlice(self.allocator);
    }

    fn isSingleSimpleElem(elements: []const ParsedElement) bool {
        if (elements.len != 1) return false;
        const e = elements[0];
        if (e.skip or e.label != null) return false;
        if (e.quantifier != .one) return false;
        return e.kind == .ident or e.kind == .token;
    }

    fn lowerQuantifiedElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LowerError!ParsedElement {
        try self.requireArity(node, items, 3, 3, "(quantified ELEMENT QUANT)");
        var inner = try self.lowerElement(items[1]);
        if (inner.quantifier != .one) return self.fail(node, "an element takes one quantifier", .{});
        inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerSkipElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp, withQuant: bool) LowerError!ParsedElement {
        const need: usize = if (withQuant) 3 else 2;
        try self.requireArity(node, items, need, need, if (withQuant) "(skip_q ELEMENT QUANT)" else "(skip ELEMENT)");
        var inner = try self.lowerElement(items[1]);
        inner.skip = true;
        if (withQuant) inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerQuantifier(self: *const GrammarLowerer, node: Sexp) LowerError!ParsedElement.Quantifier {
        const t = taggedItems(node) orelse return self.shapeError(node, "(opt|zero_plus|one_plus)");
        if (t.items.len != 1) return self.shapeError(node, "(opt|zero_plus|one_plus)");
        return switch (t.tag) {
            .opt => .optional,
            .zero_plus => .zeroPlus,
            .one_plus => .onePlus,
            else => self.shapeError(node, "(opt|zero_plus|one_plus)"),
        };
    }

    // --- Actions ---

    fn lowerAction(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionTree {
        const t = taggedItems(node) orelse return self.shapeError(node, "action");
        return switch (t.tag) {
            .pos => .{ .pass = try self.lowerPosition(node, t.items, length) },
            .null => blk: {
                try self.requireArity(node, t.items, 1, 1, "(null)");
                break :blk .nil;
            },
            .node, .list, .keep => .{ .list = try self.lowerActionList(node, t, length) },
            else => self.shapeError(node, "action (pos, null, node, list or keep)"),
        };
    }

    fn lowerPosition(self: *GrammarLowerer, node: Sexp, items: []const Sexp, length: usize) LowerError!u16 {
        try self.requireArity(node, items, 2, 2, "(pos|spread|symid INTEGER)");
        const t = try self.requireSrc(items[1], "position");
        const n = std.fmt.parseInt(u16, t, 10) catch
            return self.fail(items[1], "position {s} is too large", .{t});
        if (n == 0) return self.fail(items[1], "positions start at 1; 0 is not an element", .{});
        if (n > length) return self.fail(items[1], "position {d} is past the end of the pattern ({d} element{s})", .{ n, length, if (length == 1) "" else "s" });
        return n;
    }

    fn lowerActionList(self: *GrammarLowerer, node: Sexp, t: Tagged, length: usize) LowerError!ActionList {
        var first: usize = 1;
        const head: ActionList.Head = switch (t.tag) {
            .node => blk: {
                if (t.items.len < 2) return self.shapeError(node, "(node WORD ITEM...)");
                first = 2;
                break :blk .{ .tag = try self.tagWord(t.items[1]) };
            },
            .keep => blk: {
                if (t.items.len < 2) return self.shapeError(node, "(keep INTEGER ITEM...)");
                first = 2;
                break :blk .{ .ref = .{ .ref = try self.lowerPosition(node, t.items[0..2], length) } };
            },
            else => .none,
        };
        var items: std.ArrayListUnmanaged(ActionItem) = .empty;
        for (t.items[first..]) |item| try items.append(self.allocator, try self.lowerActionItem(item, length));
        return .{ .head = head, .items = try items.toOwnedSlice(self.allocator) };
    }

    fn tagWord(self: *GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const w = try self.requireSrc(node, "tag");
        for (w) |c| if (c == '"' or c < ' ')
            return self.fail(node, "tag '{s}' contains a quote or control character", .{w});
        return w;
    }

    fn lowerActionItem(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionItem {
        if (taggedItems(node)) |t| if (t.tag == .named) {
            try self.requireArity(node, t.items, 3, 3, "(named LABEL VALUE)");
            const role = try self.requireSrc(t.items[1], "role name");
            if (std.ascii.isUpper(role[0]) or role[0] == '_')
                return self.fail(t.items[1], "role names start with a lowercase letter: '{s}'", .{role});
            return .{ .role = role, .elem = try self.lowerActionValue(t.items[2], length) };
        };
        return .{ .elem = try self.lowerActionValue(node, length) };
    }

    fn lowerActionValue(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionElem {
        const t = taggedItems(node) orelse return self.shapeError(node, "action value");
        return switch (t.tag) {
            .pos => .{ .ref = try self.lowerPosition(node, t.items, length) },
            .spread => .{ .spread = try self.lowerPosition(node, t.items, length) },
            .symid => .{ .symId = try self.lowerPosition(node, t.items, length) },
            .null => blk: {
                try self.requireArity(node, t.items, 1, 1, "(null)");
                break :blk .nil;
            },
            .tag => blk: {
                try self.requireArity(node, t.items, 2, 2, "(tag WORD)");
                break :blk .{ .tagLit = try self.tagWord(t.items[1]) };
            },
            .node, .list, .keep => blk: {
                const list = try self.allocator.create(ActionList);
                list.* = try self.lowerActionList(node, t, length);
                break :blk .{ .node = list };
            },
            else => self.shapeError(node, "action value"),
        };
    }
};

// =============================================================================
// Negative shape tests
//
// Each test builds a malformed tree by hand (the frontend cannot produce
// one) and asserts the lowerer rejects it: error.ShapeError for a wrong
// shape, error.LowerError for a well-formed tree that means something
// invalid. Together they cover every dispatch site of the lowerer.
// =============================================================================

const testing = std.testing;

// Source bytes the test srcs point into:
//   0 "x"   1..5 "\"ab\""   5 "0"   6 "3"   7 "Y"   8..13 "shift"
//   13..19 "reduce"   19 "!"   20..24 "self"   24..26 "fn"
//   26..28 "#r"   28..31 "tag"   31..34 "zzz"   34..36 "\"\""   36 "1"
const negText = "x\"ab\"03Yshiftreduce!selffn#rtagzzz\"\"1";
const negSourceMap: diag.Source = .{ .path = "test.grammar", .text = negText };

fn src(pos: u32, len: u16) Sexp {
    return .{ .src = .{ .pos = pos, .len = len, .id = 0 } };
}
const sX = src(0, 1);
const sStr = src(1, 4);
const sZero = src(5, 1);
const sThree = src(6, 1);
const sUpper = src(7, 1);
const sShift = src(8, 5);
const sReduce = src(13, 6);
const sSelf = src(20, 4);
const sFn = src(24, 2);
const sComment = src(26, 2);
const sTagWord = src(28, 3);
const sZzz = src(31, 3);
const sEmptyStr = src(34, 2);
const sOne = src(36, 1);

fn L(comptime items: []const Sexp) Sexp {
    return .{ .list = items };
}
fn T(comptime t: Tag) Sexp {
    return .{ .tag = t };
}

fn root(comptime entries: []const Sexp) Sexp {
    return comptime L(&[_]Sexp{T(.grammar)} ++ entries);
}

// (grammar (rule (name x) (alt _ (ELEMS...) ACTION?)))
fn ruleWith(comptime elems: []const Sexp, comptime action: ?Sexp) Sexp {
    return comptime blk: {
        const alt = if (action) |a| L(&.{ T(.alt), .nil, L(elems), a }) else L(&.{ T(.alt), .nil, L(elems) });
        break :blk root(&.{L(&.{ T(.rule), L(&.{ T(.name), sX }), alt })});
    };
}
fn negRule(comptime elems: []const Sexp) Sexp {
    return ruleWith(elems, null);
}
// A rule with one element and the given action.
fn actionRule(comptime action: Sexp) Sexp {
    return ruleWith(&.{L(&.{ T(.ref), sX })}, action);
}

fn expectErr(expected: LowerError, sexp: Sexp) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(expected, GrammarLowerer.lower(arena.allocator(), sexp, negSourceMap));
}
fn expectShapeError(sexp: Sexp) !void {
    try expectErr(error.ShapeError, sexp);
}
fn expectLowerError(sexp: Sexp) !void {
    try expectErr(error.LowerError, sexp);
}

test "lowerer accepts a minimal well-formed tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const ir = try GrammarLowerer.lower(arena.allocator(), actionRule(L(&.{ T(.node), sTagWord, L(&.{ T(.pos), sOne }) })), negSourceMap);
    try testing.expectEqual(@as(usize, 1), ir.rules.len);
    const tree = ir.rules[0].alternatives[0].actionTree.?;
    try testing.expectEqualStrings("tag", tree.list.head.tag);
    try testing.expectEqual(@as(u16, 1), tree.list.items[0].elem.ref);
}

// --- Root, directives ---

test "lowerer rejects non-list root" {
    try expectShapeError(sX);
}
test "lowerer rejects root list with wrong tag" {
    try expectShapeError(L(&.{T(.alt)}));
}
test "lowerer rejects entry that is not a tagged list" {
    try expectShapeError(root(&.{sX}));
}
test "lowerer rejects entry with unknown tag" {
    try expectShapeError(root(&.{L(&.{T(.opt)})}));
}
test "lowerer rejects (lang) with no STRING" {
    try expectShapeError(root(&.{L(&.{T(.lang)})}));
}
test "lowerer rejects (conflicts) with non-numeric count" {
    try expectLowerError(root(&.{L(&.{ T(.conflicts), sX })}));
}
test "lowerer rejects (as) with no entries" {
    try expectShapeError(root(&.{L(&.{ T(.as), sX, .nil })}));
}
test "lowerer rejects (as) entry with wrong tag" {
    try expectShapeError(root(&.{L(&.{ T(.as), sX, .nil, L(&.{ T(.ref), sX }) })}));
}
test "lowerer rejects (as_entry) with a bad kind" {
    try expectShapeError(root(&.{L(&.{ T(.as), sX, .nil, L(&.{ T(.as_entry), T(.many), sX }) })}));
}
test "lowerer rejects self! in @as" {
    try expectLowerError(root(&.{L(&.{ T(.as), sX, .nil, L(&.{ T(.as_entry), T(.perm), sSelf }) })}));
}
test "lowerer rejects self via fn in @as" {
    try expectLowerError(root(&.{L(&.{ T(.as), sX, .nil, L(&.{ T(.as_entry), .nil, sSelf, sFn }) })}));
}
test "lowerer rejects a shared @as via with two groups" {
    try expectLowerError(root(&.{L(&.{
        T(.as),                                  sX,                                      sFn,
        L(&.{ T(.as_entry), .nil, sX }), L(&.{ T(.as_entry), .nil, sFn }),
    })}));
}
test "lowerer rejects (op_map) with wrong arity" {
    try expectShapeError(root(&.{L(&.{ T(.op), L(&.{ T(.op_map), sX }) })}));
}
test "lowerer rejects (level) containing non-infix_op child" {
    try expectShapeError(root(&.{L(&.{ T(.infix), sX, L(&.{ T(.level), L(&.{ T(.ref), sX }) }) })}));
}
test "lowerer rejects an unknown associativity" {
    try expectLowerError(root(&.{L(&.{ T(.infix), sX, L(&.{ T(.level), L(&.{ T(.infix_op), sStr, sZzz }) }) })}));
}
test "lowerer rejects @errors keyed by a string" {
    try expectLowerError(root(&.{L(&.{ T(.errors), L(&.{ T(.name_pair), sStr, sStr }) })}));
}
test "lowerer rejects @display keyed by a rule name" {
    try expectLowerError(root(&.{L(&.{ T(.display), L(&.{ T(.name_pair), sX, sStr }) })}));
}
test "lowerer rejects (name_pair) whose name is not a string" {
    try expectShapeError(root(&.{L(&.{ T(.display), L(&.{ T(.name_pair), sUpper, sX }) })}));
}

// --- Conflict manifest ---

fn crule() Sexp {
    return comptime L(&.{ T(.crule), sX, sUpper });
}
test "lowerer rejects (manifest) with no entries" {
    try expectShapeError(root(&.{L(&.{T(.manifest)})}));
}
test "lowerer rejects a conflict kind other than shift or reduce" {
    try expectLowerError(root(&.{L(&.{ T(.manifest), L(&.{ T(.conflict), sX, crule(), .nil, sThree, sComment }) })}));
}
test "lowerer rejects a conflict entry without a rationale" {
    try expectLowerError(root(&.{L(&.{ T(.manifest), L(&.{ T(.conflict), sShift, crule(), .nil, sThree }) })}));
}
test "lowerer rejects a shift entry with over" {
    try expectLowerError(root(&.{L(&.{ T(.manifest), L(&.{ T(.conflict), sShift, crule(), crule(), sThree, sComment }) })}));
}
test "lowerer rejects a reduce entry without over" {
    try expectLowerError(root(&.{L(&.{ T(.manifest), L(&.{ T(.conflict), sReduce, crule(), .nil, sThree, sComment }) })}));
}
test "lowerer rejects a (crule) with no right-hand side" {
    try expectShapeError(root(&.{L(&.{ T(.manifest), L(&.{ T(.conflict), sShift, L(&.{ T(.crule), sX }), .nil, sThree, sComment }) })}));
}
test "lowerer rejects both @conflicts forms" {
    try expectLowerError(root(&.{
        L(&.{ T(.conflicts), sThree }),
        L(&.{ T(.manifest), L(&.{ T(.conflict), sShift, crule(), .nil, sThree, sComment }) }),
    }));
}

// --- Schema ---

fn kindDecl(comptime roles: []const Sexp) Sexp {
    return comptime root(&.{L(&.{ T(.schema), L(&.{ T(.kind_decl), L(&.{ T(.kinds), sX }), L(&[_]Sexp{T(.roles)} ++ roles) }) })});
}
test "lowerer accepts a schema kind with typed, optional and rest roles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const ir = try GrammarLowerer.lower(arena.allocator(), kindDecl(&.{
        L(&.{ T(.role), .nil, sFn, L(&.{ T(.type), L(&.{ T(.tagset), sTagWord, sX, sZzz }) }) }),
        L(&.{ T(.role), .nil, sSelf, .nil, T(.opt) }),
        L(&.{ T(.role), T(.rest), sZzz }),
    }), negSourceMap);
    const kind = ir.schema.?.kinds[0];
    try testing.expectEqual(@as(usize, 3), kind.roles.len);
    try testing.expectEqual(@as(usize, 2), kind.roles[0].type.tag.len);
    try testing.expect(kind.roles[1].optional);
    try testing.expect(kind.roles[2].rest);
}
test "lowerer rejects (schema) with no kinds" {
    try expectShapeError(root(&.{L(&.{T(.schema)})}));
}
test "lowerer rejects (kind_decl) without a roles list" {
    try expectShapeError(root(&.{L(&.{ T(.schema), L(&.{ T(.kind_decl), L(&.{ T(.kinds), sX }) }) })}));
}
test "lowerer rejects a rest role that is not last" {
    try expectLowerError(kindDecl(&.{ L(&.{ T(.role), T(.rest), sZzz }), L(&.{ T(.role), .nil, sFn }) }));
}
test "lowerer rejects a duplicate role" {
    try expectLowerError(kindDecl(&.{ L(&.{ T(.role), .nil, sFn }), L(&.{ T(.role), .nil, sFn }) }));
}
test "lowerer rejects an uppercase role name" {
    try expectLowerError(kindDecl(&.{L(&.{ T(.role), .nil, sUpper })}));
}
test "lowerer rejects a value list on a type other than tag" {
    try expectLowerError(kindDecl(&.{L(&.{ T(.role), .nil, sFn, L(&.{ T(.type), L(&.{ T(.tagset), sZzz, sX }) }) })}));
}
test "lowerer rejects a builtin type in a union" {
    try expectLowerError(kindDecl(&.{L(&.{ T(.role), .nil, sFn, L(&.{ T(.type), sTagWord, sZzz }) })}));
}
test "lowerer rejects a side-band role that is also a slot role" {
    try expectLowerError(root(&.{L(&.{ T(.schema), L(&.{
        T(.kind_decl),
        L(&.{ T(.kinds), sX }),
        L(&.{ T(.roles), L(&.{ T(.role), .nil, sFn }) }),
        L(&.{ T(.sides), sFn }),
    }) })}));
}
test "lowerer rejects a kind declared twice" {
    try expectLowerError(root(&.{L(&.{
        T(.schema),
        L(&.{ T(.kind_decl), L(&.{ T(.kinds), sX }), L(&.{T(.roles)}) }),
        L(&.{ T(.kind_decl), L(&.{ T(.kinds), sX }), L(&.{T(.roles)}) }),
    })}));
}
test "lowerer rejects @tags without @schema" {
    try expectLowerError(root(&.{L(&.{ T(.tags), sX })}));
}
test "lowerer rejects an unknown @repair line" {
    try expectLowerError(root(&.{L(&.{ T(.repair), L(&.{ T(.repair_line), sZzz, sUpper }) })}));
}

// --- Rules and elements ---

test "lowerer rejects (rule) with no alts" {
    try expectShapeError(root(&.{L(&.{ T(.rule), L(&.{ T(.name), sX }) })}));
}
test "lowerer rejects rule_name tag that is neither start nor name" {
    try expectShapeError(root(&.{L(&.{ T(.rule), L(&.{ T(.ref), sX }), L(&.{ T(.alt), .nil, L(&.{}) }) })}));
}
test "lowerer rejects alt child that is not list" {
    try expectShapeError(root(&.{L(&.{ T(.rule), L(&.{ T(.name), sX }), L(&.{ T(.alt), .nil, sX }) })}));
}
test "lowerer rejects an alt with a bad hint kind" {
    try expectShapeError(root(&.{L(&.{ T(.rule), L(&.{ T(.name), sX }), L(&.{ T(.alt), T(.many), L(&.{}) }) })}));
}
test "lowerer rejects an empty opt-out reason" {
    try expectLowerError(root(&.{L(&.{
        T(.rule),
        L(&.{ T(.name), sX }),
        L(&.{ T(.alt), .nil, L(&.{L(&.{ T(.ref), sX })}), L(&.{ T(.pos), sX }), sEmptyStr }),
    })}));
}
test "lowerer rejects bare src as an element" {
    try expectShapeError(negRule(&.{sX}));
}
test "lowerer rejects (ref) with wrong arity" {
    try expectShapeError(negRule(&.{L(&.{T(.ref)})}));
}
test "lowerer rejects (list_req) missing inner" {
    try expectShapeError(negRule(&.{L(&.{ T(.list_req), sX })}));
}
test "lowerer rejects (list_req) inner with unknown tag" {
    try expectShapeError(negRule(&.{L(&.{ T(.list_req), sX, L(&.{ T(.ref), sX }) })}));
}
test "lowerer rejects (sep_items) whose separator is not a src" {
    try expectShapeError(negRule(&.{L(&.{ T(.list_req), sX, L(&.{ T(.sep_items), sX, L(&.{sStr}) }) })}));
}
test "lowerer rejects (group) with no body" {
    try expectShapeError(negRule(&.{L(&.{ T(.group), .nil })}));
}
test "lowerer rejects [X ...] over several elements" {
    try expectLowerError(negRule(&.{L(&.{ T(.group), T(.many), L(&.{ L(&.{ T(.ref), sX }), L(&.{ T(.ref), sX }) }) })}));
}
test "lowerer rejects (quantified) missing quant" {
    try expectShapeError(negRule(&.{L(&.{ T(.quantified), L(&.{ T(.ref), sX }) })}));
}
test "lowerer rejects (quantified) quant child with wrong tag" {
    try expectShapeError(negRule(&.{L(&.{ T(.quantified), L(&.{ T(.ref), sX }), L(&.{T(.skip)}) })}));
}
test "lowerer rejects (skip_q) missing quant" {
    try expectShapeError(negRule(&.{L(&.{ T(.skip_q), L(&.{ T(.ref), sX }) })}));
}
test "lowerer rejects (exclude) with wrong arity" {
    try expectShapeError(negRule(&.{L(&.{T(.exclude)})}));
}
test "lowerer rejects (exclude) with multi-char literal" {
    try expectLowerError(negRule(&.{L(&.{ T(.exclude), sStr })}));
}
test "lowerer rejects (exclude) appearing inside a group body" {
    try expectShapeError(negRule(&.{L(&.{ T(.group), .nil, L(&.{L(&.{ T(.exclude), sX })}) })}));
}
test "lowerer rejects (label) with wrong arity" {
    try expectShapeError(negRule(&.{L(&.{ T(.label), sX })}));
}
test "lowerer rejects a label on a skipped element" {
    try expectLowerError(negRule(&.{L(&.{ T(.label), sX, L(&.{ T(.skip), L(&.{ T(.ref), sX }) }) })}));
}
test "lowerer rejects an uppercase label" {
    try expectLowerError(negRule(&.{L(&.{ T(.label), sUpper, L(&.{ T(.ref), sX }) })}));
}
test "lowerer rejects a label on a multi-element [...] group" {
    try expectLowerError(negRule(&.{L(&.{ T(.label), sX, L(&.{ T(.group), T(.opt), L(&.{ L(&.{ T(.ref), sX }), L(&.{ T(.ref), sX }) }) }) })}));
}

// --- Actions ---

test "lowerer rejects an unknown action form" {
    try expectShapeError(actionRule(L(&.{ T(.ref), sX })));
}
test "lowerer rejects position 0" {
    try expectLowerError(actionRule(L(&.{ T(.pos), sZero })));
}
test "lowerer rejects a position past the pattern" {
    try expectLowerError(actionRule(L(&.{ T(.pos), sThree })));
}
test "lowerer rejects a spread past the pattern" {
    try expectLowerError(actionRule(L(&.{ T(.list), L(&.{ T(.spread), sThree }) })));
}
test "lowerer rejects (pos) without a number" {
    try expectShapeError(actionRule(L(&.{T(.pos)})));
}
test "lowerer rejects (node) without a head" {
    try expectShapeError(actionRule(L(&.{T(.node)})));
}
test "lowerer rejects (keep) with position 0" {
    try expectLowerError(actionRule(L(&.{ T(.keep), sZero })));
}
test "lowerer rejects (named) with wrong arity" {
    try expectShapeError(actionRule(L(&.{ T(.list), L(&.{ T(.named), sX }) })));
}
test "lowerer rejects an uppercase role in an action" {
    try expectLowerError(actionRule(L(&.{ T(.list), L(&.{ T(.named), sUpper, L(&.{ T(.pos), sX }) }) })));
}
test "lowerer rejects an unknown action value" {
    try expectShapeError(actionRule(L(&.{ T(.list), L(&.{ T(.lit), sX }) })));
}
test "lowerer rejects a bare src as an action value" {
    try expectShapeError(actionRule(L(&.{ T(.list), sX })));
}
test "lowerer rejects a tag word with a quote" {
    try expectLowerError(actionRule(L(&.{ T(.node), sStr })));
}
