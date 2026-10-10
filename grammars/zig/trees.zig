//! The tree the parser generated from zig.grammar builds against the tree
//! std.zig.Ast.parse builds (the Zig compiling this file, which must be
//! 0.17.0), node for node: `compare` prints both in one canonical form and
//! compares them as text. grammars/zig/compare-trees runs it over a corpus
//! (tools/compare_trees.zig), trees_test.zig over the inputs it holds.
//!
//! Both trees are printed in one canonical form and compared as text. The
//! form is the grammar's @schema: one line per child, indented under its
//! node, as `role: value`, where a value is a node `kind start..end`, a
//! leaf `text@start`, a tag, or `[` for a group, whose items follow as
//! `- value`. Nil children and empty groups are not printed; the root has
//! no span. The Nexus side prints its tree as it is: the grammar's span
//! marks leave a statement's `;` and a declaration's, field's or
//! parameter's doc comments out of its node's span, as Ast does. The std
//! side maps each Ast node to its kind and roles with Ast's full* helpers
//! and the tokens around the node. The rules, each a difference in
//! representation:
//!
//!     T1  the kinds Ast has no node for are made from its tokens and
//!         helpers: `param` (FnProto.iterate: first token after the doc
//!         comments to the type or `anytype`/`...`), `capture` (`*`? name),
//!         `field_init` (`.` name `=` value: two tokens before the value),
//!         `error_name` (a member of an error set, its name token).
//!     T2  token facts become roles: doc comments (the doc_comment tokens
//!         before a declaration, field, parameter or error name; the
//!         container_doc_comment tokens that open a container), labels,
//!         captures, `pub`, `extern`/`export`/`inline`/`noinline`, the
//!         library name, `threadlocal`, `comptime`, `volatile`, `inline`,
//!         pointer qualifiers (in source order), the inferred-error `!`,
//!         asm names, constraints and output variables.
//!     T3  a destructure's leading `comptime` is the destructure's: Ast's
//!         assignDestructure finds it before the first target, and when
//!         that target is a variable declaration, fullVarDecl and
//!         firstToken take it as that declaration's too. The declaration
//!         has no `comptime` and starts at `const`/`var`; the destructure
//!         starts at the `comptime`.
//!     T4  `identifier`, `number_literal`, `char_literal`,
//!         `string_literal`, `unreachable_literal` and `anyframe_literal`
//!         nodes hold one token: they print as leaves.
//!     T5  a block or loop is labeled when `name :` comes before it and
//!         the name follows neither a `.` nor the `:` of `break :` or
//!         `continue :`: in `[.x: {}]u8` and `a[0..break :x: for ...]`
//!         the `x` is an enum literal's or a break label's and the `:` a
//!         sentinel's (Parse.zig takes `.x` and `:x` first). Ast's
//!         firstToken, fullFor, fullWhile and isTokenPrecededByTags look
//!         only at the two tokens, and start such a block or loop at the
//!         `x`.
//!     T6  a pointer's qualifiers are every `const`, `volatile` and
//!         `allowzero` token before its child type (Parse.zig takes any
//!         number of each), found by the scan fullPtrType makes;
//!         full.PtrType keeps only the last of each, and duplicate_token.
//!     T7  no node ends at a container doc comment: Ast's lastToken
//!         skips the doc comments of an empty `struct { //! ... }` or
//!         `union(enum) { //! ... }`, but not of an empty `enum(T) { ... }`
//!         or `union(enum(T)) { ... }`, whose span (and every enclosing
//!         span that ends with it) it ends at the last doc comment; the
//!         span ends at the `}` after them.
//!     T8  a `for` or `while` right after the `name :` of a parameter,
//!         field or variable declaration has no label: Parse.zig takes
//!         `name :` as the declaration's, but Ast's firstToken, fullFor
//!         and fullWhile take any `name :` before the loop as its label
//!         (and FnProto.iterate, starting its scan from that label, finds
//!         no parameter name). The loop starts at its `inline` or keyword.
//!     T9  a switch prong's leading `inline` is the prong's: Parse.zig
//!         takes it first, so in `inline for (a) |b| c => d` the `for` is
//!         not inline, nor the `fn` type of `inline fn () void => d`.
//!         fullFor, fullWhile, fullFnProto and firstToken take an
//!         `inline` before the loop or `fn` as the item's, and
//!         fullSwitchCase takes the token before the item's first token
//!         (the `{` or `,` before the `inline`) as the prong's.
//!
//! An input that either parser rejects is not compared.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const AstNode = Ast.Node;
const TokenIndex = Ast.TokenIndex;
const parser = @import("parser.zig");
const Tag = parser.Tag;
const Role = parser.Role;
const Sexp = parser.Sexp;
const ir = parser.ir;

// -----------------------------------------------------------------------------
// The canonical tree
// -----------------------------------------------------------------------------

const Item = union(enum) {
    nil,
    leaf: struct { pos: u32, len: u32 },
    tag: Tag,
    node: *Node,
    group: []const Item,

    fn absent(self: Item) bool {
        return switch (self) {
            .nil => true,
            .group => |g| g.len == 0,
            else => false,
        };
    }
};

const Node = struct {
    kind: Tag,
    /// Byte offsets; null for the root.
    span: ?[2]u32,
    slots: []Item,
    rest: []const Item = &.{},
};

/// Per kind of the schema, its role names: the slot roles in slot order,
/// then the rest role, if any. Read from the generated `ir` views.
const KindInfo = struct {
    slots: []const []const u8 = &.{},
    rest: ?[]const u8 = null,
};

fn viewName(comptime kind: []const u8) []const u8 {
    comptime var out: []const u8 = "";
    comptime var upper = true;
    inline for (kind) |c| {
        if (c == '_') {
            upper = true;
        } else {
            out = out ++ &[_]u8{if (upper) std.ascii.toUpper(c) else c};
            upper = false;
        }
    }
    return out;
}

const kinds: []const KindInfo = blk: {
    @setEvalBranchQuota(200_000);
    const tags = std.meta.tags(Tag);
    var infos: [tags.len]KindInfo = @splat(.{});
    for (tags) |t| {
        const view = viewName(@tagName(t));
        if (!@hasDecl(ir, view)) continue;
        const V = @field(ir, view);
        var slots: []const []const u8 = &.{};
        var rest: ?[]const u8 = null;
        for (std.meta.declarations(V)) |d| {
            const R = @typeInfo(@TypeOf(@field(V, d))).@"fn".return_type.?;
            if (R == []const Sexp) rest = d else slots = slots ++ &[_][]const u8{d};
        }
        infos[@backingInt(t)] = .{ .slots = slots, .rest = rest };
    }
    const final = infos;
    break :blk &final;
};

fn info(kind: Tag) KindInfo {
    return kinds[@backingInt(kind)];
}

const Printer = struct {
    w: *Io.Writer,
    src: []const u8,

    fn item(pr: *Printer, it: Item, role: []const u8, depth: usize) Io.Writer.Error!void {
        if (it.absent()) return;
        try pr.w.splatByteAll(' ', depth * 2);
        if (role.len != 0) try pr.w.print("{s}: ", .{role});
        switch (it) {
            .nil => unreachable,
            .leaf => |l| {
                try writeAtom(pr.w, pr.src[l.pos..][0..l.len]);
                try pr.w.print("@{d}\n", .{l.pos});
            },
            .tag => |t| try pr.w.print("{t}\n", .{t}),
            .group => |g| {
                try pr.w.writeAll("[\n");
                for (g) |x| try pr.item(x, "-", depth + 1);
            },
            .node => |n| {
                try pr.w.print("{t}", .{n.kind});
                if (n.span) |s| try pr.w.print(" {d}..{d}", .{ s[0], s[1] });
                try pr.w.writeByte('\n');
                const k = info(n.kind);
                for (n.slots, 0..) |x, i| try pr.item(x, k.slots[i], depth + 1);
                for (n.rest) |x| try pr.item(x, k.rest.?, depth + 1);
            },
        }
    }
};

fn writeQuoted(w: *Io.Writer, text: []const u8) !void {
    try w.print("\"{f}\"", .{std.zig.fmtString(text)});
}

fn writeAtom(w: *Io.Writer, text: []const u8) !void {
    for (text) |c| if (c <= ' ' or c >= 0x7f or c == '"') return writeQuoted(w, text);
    if (text.len == 0) return writeQuoted(w, text);
    try w.writeAll(text);
}

// -----------------------------------------------------------------------------
// The Nexus side: the tree as it is
// -----------------------------------------------------------------------------

fn fromSexp(a: Allocator, p: *parser.Parser, s: Sexp) !Item {
    switch (s) {
        .nil => return .nil,
        .src => |l| return .{ .leaf = .{ .pos = l.pos, .len = l.len } },
        .tag => |t| return .{ .tag = t },
        .str => unreachable,
        .list => {
            const items = s.items();
            const kind = s.kind() orelse {
                const g = try a.alloc(Item, items.len);
                for (items, g) |x, *y| y.* = try fromSexp(a, p, x);
                return .{ .group = g };
            };
            const k = info(kind);
            const n = try a.create(Node);
            n.* = .{
                .kind = kind,
                .span = if (kind == .root) null else span: {
                    const sp = p.span(s);
                    break :span .{ sp.start, sp.end };
                },
                .slots = try a.alloc(Item, k.slots.len),
            };
            for (n.slots, 0..) |*y, i| y.* = if (1 + i < items.len) try fromSexp(a, p, items[1 + i]) else .nil;
            if (items.len > 1 + k.slots.len) {
                const r = try a.alloc(Item, items.len - 1 - k.slots.len);
                for (items[1 + k.slots.len ..], r) |x, *y| y.* = try fromSexp(a, p, x);
                n.rest = r;
            }
            return .{ .node = n };
        },
    }
}

// -----------------------------------------------------------------------------
// The std side: std.zig.Ast in the schema's kinds and roles
// -----------------------------------------------------------------------------

const Conv = struct {
    a: Allocator,
    tree: *const Ast,

    const Error = Allocator.Error;

    fn tag(c: *Conv, t: TokenIndex) std.zig.Token.Tag {
        return c.tree.tokenTag(t);
    }

    fn leaf(c: *Conv, t: TokenIndex) Item {
        return .{ .leaf = .{ .pos = c.tree.tokenStart(t), .len = @intCast(c.tree.tokenSlice(t).len) } };
    }

    fn optLeaf(c: *Conv, t: ?TokenIndex) Item {
        return if (t) |x| c.leaf(x) else .nil;
    }

    fn new(c: *Conv, comptime kind: Tag, first: TokenIndex, last_token: TokenIndex) Error!*Node {
        // No node ends at a container doc comment: past them is the `}` (T7).
        var last = last_token;
        while (c.tag(last) == .container_doc_comment) last += 1;
        const n = try c.a.create(Node);
        const slots = try c.a.alloc(Item, info(kind).slots.len);
        @memset(slots, .nil);
        n.* = .{
            .kind = kind,
            .span = .{ c.tree.tokenStart(first), c.tree.tokenStart(last) + @as(u32, @intCast(c.tree.tokenSlice(last).len)) },
            .slots = slots,
        };
        return n;
    }

    /// A node of `kind` spanning Ast's firstToken..lastToken of `n`.
    fn like(c: *Conv, comptime kind: Tag, n: AstNode.Index) Error!*Node {
        return c.new(kind, c.tree.firstToken(n), c.tree.lastToken(n));
    }

    fn set(n: *Node, comptime kind: Tag, comptime role: Role, it: Item) void {
        std.debug.assert(n.kind == kind);
        n.slots[ir.slot(kind, role) - 1] = it;
    }

    fn conv(c: *Conv, n: AstNode.Index) Error!Item {
        return c.convert(n);
    }

    fn opt(c: *Conv, n: AstNode.OptionalIndex) Error!Item {
        return if (n.unwrap()) |x| c.convert(x) else .nil;
    }

    fn all(c: *Conv, ns: []const AstNode.Index) Error![]const Item {
        const out = try c.a.alloc(Item, ns.len);
        for (ns, out) |x, *y| y.* = try c.convert(x);
        return out;
    }

    fn group(c: *Conv, ns: []const AstNode.Index) Error!Item {
        return .{ .group = try c.all(ns) };
    }

    /// The doc comments right before token `t` (T2).
    fn docsBefore(c: *Conv, t: TokenIndex) Error!Item {
        var first = t;
        while (first > 0 and c.tag(first - 1) == .doc_comment) first -= 1;
        return c.tokenRun(first, .doc_comment);
    }

    /// The run of `tag` tokens from `first` on, as a group of leaves.
    fn tokenRun(c: *Conv, first: TokenIndex, comptime t: std.zig.Token.Tag) Error!Item {
        var last = first;
        while (c.tag(last) == t) last += 1;
        const g = try c.a.alloc(Item, last - first);
        for (g, first..) |*y, tok| y.* = c.leaf(@intCast(tok));
        return .{ .group = g };
    }

    /// `*`? name, from the first token after `|` (T1).
    fn capture(c: *Conv, first: TokenIndex) Error!*Node {
        const ptr = c.tag(first) == .asterisk;
        const name = first + @intFromBool(ptr);
        const n = try c.new(.capture, first, name);
        set(n, .capture, .ptr, if (ptr) c.leaf(first) else .nil);
        set(n, .capture, .name, c.leaf(name));
        return n;
    }

    /// Whether `name :`, found before a block or loop, is its label: the
    /// name follows neither a `.` nor the `:` of `break :` or `continue :`
    /// (T5).
    fn isLabel(c: *Conv, name: TokenIndex) bool {
        if (name >= 1 and c.tag(name - 1) == .period) return false;
        return !(name >= 2 and c.tag(name - 1) == .colon and
            (c.tag(name - 2) == .keyword_break or c.tag(name - 2) == .keyword_continue));
    }

    /// The label Ast gives a `for` or `while` node (by the tokens before it).
    fn loopLabel(c: *Conv, n: AstNode.Index) ?TokenIndex {
        return switch (c.tree.nodeTag(n)) {
            .for_simple, .@"for" => c.tree.fullFor(n).?.label_token,
            .while_simple, .while_cont, .@"while" => c.tree.fullWhile(n).?.label_token,
            else => null,
        };
    }

    /// The type after `name :` in a declaration: a `for` or `while` there
    /// has no label, though `name :` is before it (T8).
    fn declType(c: *Conv, n: AstNode.Index, name: TokenIndex) Error!Item {
        const it = try c.conv(n);
        if (c.loopLabel(n) != name) return it;
        const node = it.node;
        switch (node.kind) {
            .@"for" => {
                set(node, .@"for", .label, .nil);
                node.span.?[0] = c.tree.tokenStart(c.tree.fullFor(n).?.inline_token orelse c.tree.nodeMainToken(n));
            },
            .@"while" => {
                set(node, .@"while", .label, .nil);
                node.span.?[0] = c.tree.tokenStart(c.tree.fullWhile(n).?.inline_token orelse c.tree.nodeMainToken(n));
            },
            else => unreachable,
        }
        return it;
    }

    fn varDecl(c: *Conv, n: AstNode.Index, in_destructure: bool) Error!Item {
        const v = c.tree.fullVarDecl(n).?;
        const node = try c.like(.var_decl, n);
        if (in_destructure) {
            node.span.?[0] = c.tree.tokenStart(v.ast.mut_token); // T3
        } else {
            set(node, .var_decl, .doc, try c.docsBefore(c.tree.firstToken(n)));
            set(node, .var_decl, .@"comptime", c.optLeaf(v.comptime_token));
        }
        set(node, .var_decl, .visib, c.optLeaf(v.visib_token));
        set(node, .var_decl, .modifier, c.optLeaf(v.extern_export_token));
        set(node, .var_decl, .lib_name, c.optLeaf(v.lib_name));
        set(node, .var_decl, .@"threadlocal", c.optLeaf(v.threadlocal_token));
        set(node, .var_decl, .mut, c.leaf(v.ast.mut_token));
        set(node, .var_decl, .name, c.leaf(v.ast.mut_token + 1));
        set(node, .var_decl, .type, if (v.ast.type_node.unwrap()) |t| try c.declType(t, v.ast.mut_token + 1) else .nil);
        set(node, .var_decl, .@"align", try c.opt(v.ast.align_node));
        set(node, .var_decl, .@"addrspace", try c.opt(v.ast.addrspace_node));
        set(node, .var_decl, .section, try c.opt(v.ast.section_node));
        set(node, .var_decl, .init, try c.opt(v.ast.init_node));
        return .{ .node = node };
    }

    fn unary(c: *Conv, comptime kind: Tag, comptime role: Role, n: AstNode.Index, operand: AstNode.Index) Error!Item {
        const node = try c.like(kind, n);
        set(node, kind, role, try c.conv(operand));
        return .{ .node = node };
    }

    fn convert(c: *Conv, n: AstNode.Index) Error!Item {
        const tree = c.tree;
        const mt = tree.nodeMainToken(n);
        switch (tree.nodeTag(n)) {
            .root => {
                const node = try c.a.create(Node);
                node.* = .{ .kind = .root, .span = null, .slots = try c.a.alloc(Item, info(.root).slots.len) };
                @memset(node.slots, .nil);
                set(node, .root, .doc, try c.tokenRun(0, .container_doc_comment));
                node.rest = try c.all(tree.rootDecls());
                return .{ .node = node };
            },

            .test_decl => {
                const name, const body = tree.nodeData(n).opt_token_and_node;
                const node = try c.like(.test_decl, n);
                set(node, .test_decl, .name, c.optLeaf(name.unwrap()));
                set(node, .test_decl, .body, try c.conv(body));
                return .{ .node = node };
            },

            .global_var_decl, .local_var_decl, .simple_var_decl, .aligned_var_decl => return c.varDecl(n, false),

            .@"errdefer" => return c.unary(.@"errdefer", .body, n, tree.nodeData(n).node),
            .@"defer" => return c.unary(.@"defer", .body, n, tree.nodeData(n).node),
            .@"suspend" => return c.unary(.@"suspend", .body, n, tree.nodeData(n).node),
            .@"comptime" => return c.unary(.@"comptime", .operand, n, tree.nodeData(n).node),
            .@"nosuspend" => return c.unary(.@"nosuspend", .operand, n, tree.nodeData(n).node),
            .@"resume" => return c.unary(.@"resume", .operand, n, tree.nodeData(n).node),
            .bool_not => return c.unary(.bool_not, .operand, n, tree.nodeData(n).node),
            .negation => return c.unary(.negation, .operand, n, tree.nodeData(n).node),
            .bit_not => return c.unary(.bit_not, .operand, n, tree.nodeData(n).node),
            .negation_wrap => return c.unary(.negation_wrap, .operand, n, tree.nodeData(n).node),
            .address_of => return c.unary(.address_of, .operand, n, tree.nodeData(n).node),
            .@"try" => return c.unary(.@"try", .operand, n, tree.nodeData(n).node),
            .deref => return c.unary(.deref, .operand, n, tree.nodeData(n).node),
            .optional_type => return c.unary(.optional_type, .child, n, tree.nodeData(n).node),
            .unwrap_optional => return c.unary(.unwrap_optional, .operand, n, tree.nodeData(n).node_and_token[0]),
            .grouped_expression => return c.unary(.grouped_expression, .operand, n, tree.nodeData(n).node_and_token[0]),
            .anyframe_type => return c.unary(.anyframe_type, .result, n, tree.nodeData(n).token_and_node[1]),

            .@"catch" => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.@"catch", n);
                set(node, .@"catch", .lhs, try c.conv(lhs));
                if (c.tag(mt + 1) == .pipe) set(node, .@"catch", .payload, c.leaf(mt + 2));
                set(node, .@"catch", .rhs, try c.conv(rhs));
                return .{ .node = node };
            },

            .equal_equal,
            .bang_equal,
            .less_than,
            .greater_than,
            .less_or_equal,
            .greater_or_equal,
            .merge_error_sets,
            .mul,
            .div,
            .mod,
            .mul_wrap,
            .mul_sat,
            .add,
            .sub,
            .array_cat,
            .add_wrap,
            .sub_wrap,
            .add_sat,
            .sub_sat,
            .shl,
            .shl_sat,
            .shr,
            .bit_and,
            .bit_xor,
            .bit_or,
            .@"orelse",
            .bool_and,
            .bool_or,
            => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.binary, n);
                set(node, .binary, .op, c.leaf(mt));
                set(node, .binary, .lhs, try c.conv(lhs));
                set(node, .binary, .rhs, try c.conv(rhs));
                return .{ .node = node };
            },

            .assign_mul,
            .assign_div,
            .assign_mod,
            .assign_add,
            .assign_sub,
            .assign_shl,
            .assign_shl_sat,
            .assign_shr,
            .assign_bit_and,
            .assign_bit_xor,
            .assign_bit_or,
            .assign_mul_wrap,
            .assign_add_wrap,
            .assign_sub_wrap,
            .assign_mul_sat,
            .assign_add_sat,
            .assign_sub_sat,
            .assign,
            => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.assign, n);
                set(node, .assign, .op, c.leaf(mt));
                set(node, .assign, .target, try c.conv(lhs));
                set(node, .assign, .value, try c.conv(rhs));
                return .{ .node = node };
            },

            .error_union => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.error_union, n);
                set(node, .error_union, .error_set, try c.conv(lhs));
                set(node, .error_union, .payload, try c.conv(rhs));
                return .{ .node = node };
            },

            .switch_range => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.switch_range, n);
                set(node, .switch_range, .start, try c.conv(lhs));
                set(node, .switch_range, .end, try c.conv(rhs));
                return .{ .node = node };
            },

            .array_access => {
                const lhs, const rhs = tree.nodeData(n).node_and_node;
                const node = try c.like(.array_access, n);
                set(node, .array_access, .operand, try c.conv(lhs));
                set(node, .array_access, .index, try c.conv(rhs));
                return .{ .node = node };
            },

            .field_access => {
                const lhs, const field = tree.nodeData(n).node_and_token;
                const node = try c.like(.field_access, n);
                set(node, .field_access, .operand, try c.conv(lhs));
                set(node, .field_access, .name, c.leaf(field));
                return .{ .node = node };
            },

            .assign_destructure => {
                const ad = tree.assignDestructure(n);
                const node = try c.like(.assign_destructure, n);
                if (ad.comptime_token) |t| {
                    node.span.?[0] = tree.tokenStart(t); // T3
                    set(node, .assign_destructure, .@"comptime", c.leaf(t));
                }
                const targets = try c.a.alloc(Item, ad.ast.variables.len);
                for (ad.ast.variables, targets) |v, *y| y.* = switch (tree.nodeTag(v)) {
                    .global_var_decl, .local_var_decl, .simple_var_decl, .aligned_var_decl => try c.varDecl(v, true),
                    else => try c.conv(v),
                };
                set(node, .assign_destructure, .targets, .{ .group = targets });
                set(node, .assign_destructure, .value, try c.conv(ad.ast.value_expr));
                return .{ .node = node };
            },

            .array_type, .array_type_sentinel => {
                const at = tree.fullArrayType(n).?;
                const node = try c.like(.array_type, n);
                set(node, .array_type, .len, try c.conv(at.ast.elem_count));
                set(node, .array_type, .sentinel, try c.opt(at.ast.sentinel));
                set(node, .array_type, .elem, try c.conv(at.ast.elem_type));
                return .{ .node = node };
            },

            .ptr_type_aligned, .ptr_type_sentinel, .ptr_type, .ptr_type_bit_range => {
                const pt = tree.fullPtrType(n).?;
                const node = try c.like(.ptr_type, n);
                set(node, .ptr_type, .size, .{ .tag = switch (pt.size) {
                    .one => .one,
                    .many => .many,
                    .slice => .slice,
                    .c => .c,
                } });
                set(node, .ptr_type, .sentinel, try c.opt(pt.ast.sentinel));
                set(node, .ptr_type, .@"align", try c.opt(pt.ast.align_node));
                set(node, .ptr_type, .bit_start, try c.opt(pt.ast.bit_range_start));
                set(node, .ptr_type, .bit_end, try c.opt(pt.ast.bit_range_end));
                set(node, .ptr_type, .@"addrspace", try c.opt(pt.ast.addrspace_node));
                set(node, .ptr_type, .child, try c.conv(pt.ast.child_type));
                // Every qualifier token, by fullPtrType's own scan (T6).
                var quals: std.ArrayList(Item) = .empty;
                var t = (if (pt.ast.sentinel.unwrap()) |x| tree.lastToken(x) + 1 else switch (pt.size) {
                    .one => mt,
                    .slice => mt + 1,
                    .many => mt + 2,
                    .c => mt + 3,
                }) + 1;
                const end = tree.firstToken(pt.ast.child_type);
                while (t < end) : (t += 1) switch (c.tag(t)) {
                    .keyword_allowzero, .keyword_const, .keyword_volatile => try quals.append(c.a, c.leaf(t)),
                    .keyword_align => t = tree.lastToken((pt.ast.bit_range_end.unwrap() orelse pt.ast.align_node.unwrap()).?) + 1,
                    .keyword_addrspace => t = tree.lastToken(pt.ast.addrspace_node.unwrap().?) + 1,
                    else => unreachable,
                };
                node.rest = quals.items;
                return .{ .node = node };
            },

            .slice_open, .slice, .slice_sentinel => {
                const s = tree.fullSlice(n).?;
                const node = try c.like(.slice, n);
                set(node, .slice, .operand, try c.conv(s.ast.sliced));
                set(node, .slice, .start, try c.conv(s.ast.start));
                set(node, .slice, .end, try c.opt(s.ast.end));
                set(node, .slice, .sentinel, try c.opt(s.ast.sentinel));
                return .{ .node = node };
            },

            .array_init_one,
            .array_init_one_comma,
            .array_init_dot_two,
            .array_init_dot_two_comma,
            .array_init_dot,
            .array_init_dot_comma,
            .array_init,
            .array_init_comma,
            => {
                var buf: [2]AstNode.Index = undefined;
                const ai = tree.fullArrayInit(&buf, n).?;
                const node = try c.like(.array_init, n);
                set(node, .array_init, .type, try c.opt(ai.ast.type_expr));
                node.rest = try c.all(ai.ast.elements);
                return .{ .node = node };
            },

            .struct_init_one,
            .struct_init_one_comma,
            .struct_init_dot_two,
            .struct_init_dot_two_comma,
            .struct_init_dot,
            .struct_init_dot_comma,
            .struct_init,
            .struct_init_comma,
            => {
                var buf: [2]AstNode.Index = undefined;
                const si = tree.fullStructInit(&buf, n).?;
                const node = try c.like(.struct_init, n);
                set(node, .struct_init, .type, try c.opt(si.ast.type_expr));
                const fields = try c.a.alloc(Item, si.ast.fields.len);
                for (si.ast.fields, fields) |f, *y| {
                    // `.name = value`: the name is two tokens before the value (T1).
                    const name = tree.firstToken(f) - 2;
                    const fi = try c.new(.field_init, name - 1, tree.lastToken(f));
                    set(fi, .field_init, .name, c.leaf(name));
                    set(fi, .field_init, .value, try c.conv(f));
                    y.* = .{ .node = fi };
                }
                node.rest = fields;
                return .{ .node = node };
            },

            .call_one, .call_one_comma, .call, .call_comma => {
                var buf: [1]AstNode.Index = undefined;
                const call = tree.fullCall(&buf, n).?;
                const node = try c.like(.call, n);
                set(node, .call, .callee, try c.conv(call.ast.fn_expr));
                node.rest = try c.all(call.ast.params);
                return .{ .node = node };
            },

            .@"switch", .switch_comma => {
                const s = tree.fullSwitch(n).?;
                const node = try c.like(.@"switch", n);
                set(node, .@"switch", .label, c.optLeaf(s.label_token));
                set(node, .@"switch", .cond, try c.conv(s.ast.condition));
                node.rest = try c.all(s.ast.cases);
                return .{ .node = node };
            },

            .switch_case_one, .switch_case_inline_one, .switch_case, .switch_case_inline => {
                const sc = tree.fullSwitchCase(n).?;
                const node = try c.like(.switch_case, n);
                const values = try c.all(sc.ast.values);
                var inline_token = sc.inline_token;
                if (inline_token) |t| if (c.tag(t) != .keyword_inline) {
                    // The prong's `inline` is the first item's to Ast (T9).
                    const item = values[0].node;
                    const v0 = sc.ast.values[0];
                    inline_token = t + 1;
                    node.span.?[0] = tree.tokenStart(t + 1);
                    item.span.?[0] = tree.tokenStart(tree.nodeMainToken(v0));
                    switch (item.kind) {
                        .@"for" => set(item, .@"for", .@"inline", .nil),
                        .@"while" => set(item, .@"while", .@"inline", .nil),
                        .fn_proto => set(item, .fn_proto, .modifier, .nil),
                        else => unreachable,
                    }
                };
                set(node, .switch_case, .@"inline", c.optLeaf(inline_token));
                set(node, .switch_case, .values, .{ .group = values });
                if (sc.payload_token) |t| {
                    const cap = try c.capture(t);
                    set(node, .switch_case, .capture, .{ .node = cap });
                    const name = t + @intFromBool(c.tag(t) == .asterisk);
                    if (c.tag(name + 1) == .comma) set(node, .switch_case, .index, c.leaf(name + 2));
                }
                set(node, .switch_case, .body, try c.conv(sc.ast.target_expr));
                return .{ .node = node };
            },

            .while_simple, .while_cont, .@"while" => {
                var wh = tree.fullWhile(n).?;
                const node = try c.like(.@"while", n);
                if (wh.label_token) |t| if (!c.isLabel(t)) {
                    wh.label_token = null;
                    node.span.?[0] = tree.tokenStart(wh.inline_token orelse mt); // T5
                };
                set(node, .@"while", .label, c.optLeaf(wh.label_token));
                set(node, .@"while", .@"inline", c.optLeaf(wh.inline_token));
                set(node, .@"while", .cond, try c.conv(wh.ast.cond_expr));
                if (wh.payload_token) |t| set(node, .@"while", .capture, .{ .node = try c.capture(t) });
                set(node, .@"while", .cont, try c.opt(wh.ast.cont_expr));
                set(node, .@"while", .then, try c.conv(wh.ast.then_expr));
                set(node, .@"while", .else_capture, c.optLeaf(wh.error_token));
                set(node, .@"while", .@"else", try c.opt(wh.ast.else_expr));
                return .{ .node = node };
            },

            .for_simple, .@"for" => {
                var f = tree.fullFor(n).?;
                const node = try c.like(.@"for", n);
                if (f.label_token) |t| if (!c.isLabel(t)) {
                    f.label_token = null;
                    node.span.?[0] = tree.tokenStart(f.inline_token orelse mt); // T5
                };
                set(node, .@"for", .label, c.optLeaf(f.label_token));
                set(node, .@"for", .@"inline", c.optLeaf(f.inline_token));
                set(node, .@"for", .inputs, try c.group(f.ast.inputs));
                var caps: std.ArrayList(Item) = .empty;
                var t = f.payload_token;
                while (c.tag(t) != .pipe) {
                    const cap = try c.capture(t);
                    try caps.append(c.a, .{ .node = cap });
                    t = t + 1 + @intFromBool(c.tag(t) == .asterisk);
                    if (c.tag(t) == .comma) t += 1;
                }
                set(node, .@"for", .captures, .{ .group = caps.items });
                set(node, .@"for", .then, try c.conv(f.ast.then_expr));
                set(node, .@"for", .@"else", try c.opt(f.ast.else_expr));
                return .{ .node = node };
            },

            .for_range => {
                const start, const end = tree.nodeData(n).node_and_opt_node;
                const node = try c.like(.for_range, n);
                set(node, .for_range, .start, try c.conv(start));
                set(node, .for_range, .end, try c.opt(end));
                return .{ .node = node };
            },

            .if_simple, .@"if" => {
                const f = tree.fullIf(n).?;
                const node = try c.like(.@"if", n);
                set(node, .@"if", .cond, try c.conv(f.ast.cond_expr));
                if (f.payload_token) |t| set(node, .@"if", .capture, .{ .node = try c.capture(t) });
                set(node, .@"if", .then, try c.conv(f.ast.then_expr));
                set(node, .@"if", .else_capture, c.optLeaf(f.error_token));
                set(node, .@"if", .@"else", try c.opt(f.ast.else_expr));
                return .{ .node = node };
            },

            .@"continue", .@"break" => |t| {
                const label, const value = tree.nodeData(n).opt_token_and_opt_node;
                if (t == .@"break") {
                    const node = try c.like(.@"break", n);
                    set(node, .@"break", .label, c.optLeaf(label.unwrap()));
                    set(node, .@"break", .value, try c.opt(value));
                    return .{ .node = node };
                }
                const node = try c.like(.@"continue", n);
                set(node, .@"continue", .label, c.optLeaf(label.unwrap()));
                set(node, .@"continue", .value, try c.opt(value));
                return .{ .node = node };
            },

            .@"return" => {
                const node = try c.like(.@"return", n);
                set(node, .@"return", .value, try c.opt(tree.nodeData(n).opt_node));
                return .{ .node = node };
            },

            .fn_proto_simple, .fn_proto_multi, .fn_proto_one, .fn_proto => {
                var buf: [1]AstNode.Index = undefined;
                const fp = tree.fullFnProto(&buf, n).?;
                const node = try c.like(.fn_proto, n);
                set(node, .fn_proto, .doc, try c.docsBefore(tree.firstToken(n)));
                set(node, .fn_proto, .visib, c.optLeaf(fp.visib_token));
                set(node, .fn_proto, .modifier, c.optLeaf(fp.extern_export_inline_token));
                set(node, .fn_proto, .lib_name, c.optLeaf(fp.lib_name));
                set(node, .fn_proto, .name, c.optLeaf(fp.name_token));
                var params: std.ArrayList(Item) = .empty;
                var it = fp.iterate(tree);
                while (it.next()) |pd| try params.append(c.a, try c.param(pd));
                set(node, .fn_proto, .params, .{ .group = params.items });
                set(node, .fn_proto, .@"align", try c.opt(fp.ast.align_expr));
                set(node, .fn_proto, .@"addrspace", try c.opt(fp.ast.addrspace_expr));
                set(node, .fn_proto, .section, try c.opt(fp.ast.section_expr));
                set(node, .fn_proto, .@"callconv", try c.opt(fp.ast.callconv_expr));
                const ret = fp.ast.return_type.unwrap().?;
                // An inferred error set: `!` directly before the return type.
                const bang = tree.firstToken(ret) - 1;
                if (c.tag(bang) == .bang) set(node, .fn_proto, .bang, c.leaf(bang));
                set(node, .fn_proto, .return_type, try c.conv(ret));
                return .{ .node = node };
            },

            .fn_decl => {
                const proto, const body = tree.nodeData(n).node_and_node;
                const node = try c.like(.fn_decl, n);
                set(node, .fn_decl, .proto, try c.conv(proto));
                set(node, .fn_decl, .body, try c.conv(body));
                return .{ .node = node };
            },

            .anyframe_literal,
            .char_literal,
            .number_literal,
            .unreachable_literal,
            .identifier,
            .string_literal,
            => return c.leaf(mt), // T4

            .enum_literal => {
                const node = try c.like(.enum_literal, n);
                set(node, .enum_literal, .name, c.leaf(mt));
                return .{ .node = node };
            },

            .error_value => {
                const node = try c.like(.error_value, n);
                set(node, .error_value, .name, c.leaf(mt + 2));
                return .{ .node = node };
            },

            .multiline_string_literal => {
                const first, const last = tree.nodeData(n).token_and_token;
                const node = try c.like(.multiline_string_literal, n);
                const lines = try c.a.alloc(Item, last - first + 1);
                for (lines, first..) |*y, t| y.* = c.leaf(@intCast(t));
                node.rest = lines;
                return .{ .node = node };
            },

            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {
                var buf: [2]AstNode.Index = undefined;
                const node = try c.like(.builtin_call, n);
                set(node, .builtin_call, .name, c.leaf(mt));
                node.rest = try c.all(tree.builtinCallParams(&buf, n).?);
                return .{ .node = node };
            },

            .error_set_decl => {
                const lbrace, const rbrace = tree.nodeData(n).token_and_token;
                const node = try c.like(.error_set_decl, n);
                var members: std.ArrayList(Item) = .empty;
                var t = lbrace + 1;
                while (t < rbrace) : (t += 1) {
                    if (c.tag(t) != .identifier) continue;
                    const m = try c.new(.error_name, t, t); // T1
                    set(m, .error_name, .doc, try c.docsBefore(t));
                    set(m, .error_name, .name, c.leaf(t));
                    try members.append(c.a, .{ .node = m });
                }
                node.rest = members.items;
                return .{ .node = node };
            },

            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            .tagged_union,
            .tagged_union_trailing,
            .tagged_union_two,
            .tagged_union_two_trailing,
            .tagged_union_enum_tag,
            .tagged_union_enum_tag_trailing,
            => {
                var buf: [2]AstNode.Index = undefined;
                const cd = tree.fullContainerDecl(&buf, n).?;
                const node = try c.like(.container_decl, n);
                set(node, .container_decl, .layout, c.optLeaf(cd.layout_token));
                set(node, .container_decl, .kind, c.leaf(cd.ast.main_token));
                set(node, .container_decl, .@"enum", c.optLeaf(cd.ast.enum_token));
                set(node, .container_decl, .arg, try c.opt(cd.ast.arg));
                const lbrace = if (cd.ast.arg.unwrap()) |arg|
                    tree.lastToken(arg) + @as(TokenIndex, if (cd.ast.enum_token != null) 3 else 2)
                else if (cd.ast.enum_token) |t| t + 2 else cd.ast.main_token + 1;
                set(node, .container_decl, .doc, try c.tokenRun(lbrace + 1, .container_doc_comment));
                node.rest = try c.all(cd.ast.members);
                return .{ .node = node };
            },

            .container_field_init, .container_field_align, .container_field => {
                const cf = tree.fullContainerField(n).?;
                const node = try c.like(.container_field, n);
                set(node, .container_field, .doc, try c.docsBefore(tree.firstToken(n)));
                set(node, .container_field, .@"comptime", c.optLeaf(cf.comptime_token));
                if (cf.ast.tuple_like) {
                    set(node, .container_field, .type, try c.opt(cf.ast.type_expr));
                } else {
                    set(node, .container_field, .name, c.leaf(cf.ast.main_token));
                    set(node, .container_field, .type, try c.declType(cf.ast.type_expr.unwrap().?, cf.ast.main_token));
                }
                set(node, .container_field, .@"align", try c.opt(cf.ast.align_expr));
                set(node, .container_field, .value, try c.opt(cf.ast.value_expr));
                return .{ .node = node };
            },

            .block_two, .block_two_semicolon, .block, .block_semicolon => {
                var buf: [2]AstNode.Index = undefined;
                const node = try c.like(.block, n);
                if (tree.isTokenPrecededByTags(mt, &.{ .identifier, .colon })) {
                    if (c.isLabel(mt - 2)) {
                        set(node, .block, .label, c.leaf(mt - 2));
                    } else {
                        node.span.?[0] = tree.tokenStart(mt); // T5
                    }
                }
                node.rest = try c.all(tree.blockStatements(&buf, n).?);
                return .{ .node = node };
            },

            .asm_simple, .@"asm" => {
                const as = tree.fullAsm(n).?;
                const node = try c.like(.@"asm", n);
                set(node, .@"asm", .@"volatile", c.optLeaf(as.volatile_token));
                set(node, .@"asm", .template, try c.conv(as.ast.template));
                set(node, .@"asm", .clobbers, try c.opt(as.ast.clobbers));
                node.rest = try c.all(as.ast.items);
                return .{ .node = node };
            },

            // `[name] "constraint" (var)` or `[name] "constraint" (-> type)`.
            .asm_output => {
                const ty, _ = tree.nodeData(n).opt_node_and_token;
                const node = try c.like(.asm_output, n);
                set(node, .asm_output, .name, c.leaf(mt));
                set(node, .asm_output, .constraint, c.leaf(mt + 2));
                if (ty.unwrap()) |t| {
                    set(node, .asm_output, .type, try c.conv(t));
                } else {
                    set(node, .asm_output, .variable, c.leaf(mt + 4));
                }
                return .{ .node = node };
            },

            .asm_input => {
                const node = try c.like(.asm_input, n);
                set(node, .asm_input, .name, c.leaf(mt));
                set(node, .asm_input, .constraint, c.leaf(mt + 2));
                set(node, .asm_input, .value, try c.conv(tree.nodeData(n).node_and_token[0]));
                return .{ .node = node };
            },
        }
    }

    /// A parameter: FnProto.iterate's tokens and type (T1).
    fn param(c: *Conv, param_in: Ast.full.FnProto.Param) Error!Item {
        const tree = c.tree;
        var p = param_in;
        // Unnamed, with a labeled loop for a type: the label is the name (T8).
        if (p.name_token == null) if (p.type_expr) |t| if (c.loopLabel(t)) |label| {
            p.name_token = label;
        };
        const first = p.comptime_noalias orelse p.name_token orelse p.anytype_ellipsis3 orelse tree.firstToken(p.type_expr.?);
        const last = if (p.type_expr) |t| tree.lastToken(t) else p.anytype_ellipsis3.?;
        const node = try c.new(.param, first, last);
        if (p.first_doc_comment) |t| set(node, .param, .doc, try c.tokenRun(t, .doc_comment));
        set(node, .param, .modifier, c.optLeaf(p.comptime_noalias));
        set(node, .param, .name, c.optLeaf(p.name_token));
        set(node, .param, .type, if (p.type_expr) |t|
            (if (p.name_token) |name| try c.declType(t, name) else try c.conv(t))
        else
            c.leaf(p.anytype_ellipsis3.?));
        return .{ .node = node };
    }
};

// -----------------------------------------------------------------------------
// Comparison
// -----------------------------------------------------------------------------

pub const Outcome = enum { same, differ, skipped };

/// Parses `src` with both parsers and, when both accept it, prints both
/// trees, the Nexus tree to `nexus_out` and Ast's to `std_out`; `p` is
/// reset to `src`.
pub fn compare(
    gpa: Allocator,
    p: *parser.Parser,
    src: [:0]const u8,
    nexus_out: *Io.Writer.Allocating,
    std_out: *Io.Writer.Allocating,
) !Outcome {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    var tree = try Ast.parse(gpa, src, .{ .recover = false, .mode = .zig });
    defer tree.deinit(gpa);
    if (tree.errors.len != 0) return .skipped;
    p.reset(src);
    const root = p.parseRoot() catch |err| switch (err) {
        error.ParseError => return .skipped,
        else => |e| return e,
    };

    const mine = try fromSexp(a, p, root);
    var conv: Conv = .{ .a = a, .tree = &tree };
    const theirs = try conv.convert(.root);

    nexus_out.clearRetainingCapacity();
    std_out.clearRetainingCapacity();
    var pa: Printer = .{ .w = &nexus_out.writer, .src = src };
    try pa.item(mine, "", 0);
    var pb: Printer = .{ .w = &std_out.writer, .src = src };
    try pb.item(theirs, "", 0);
    return if (std.mem.eql(u8, nexus_out.written(), std_out.written())) .same else .differ;
}

/// The first line on which `a` and `b` differ, and the line before it.
pub fn firstDiff(a: []const u8, b: []const u8) struct { line: usize, prev: []const u8, a: []const u8, b: []const u8 } {
    var line: usize = 1;
    var start: usize = 0;
    var prev_start: usize = 0;
    var i: usize = 0;
    while (i < a.len and i < b.len and a[i] == b[i]) : (i += 1) if (a[i] == '\n') {
        line += 1;
        prev_start = start;
        start = i + 1;
    };
    const lineOf = struct {
        fn f(s: []const u8, from: usize) []const u8 {
            if (from >= s.len) return "(end)";
            const e = std.mem.findScalarPos(u8, s, from, '\n') orelse s.len;
            return s[from..e];
        }
    }.f;
    return .{ .line = line, .prev = if (line > 1) lineOf(a, prev_start) else "", .a = lineOf(a, start), .b = lineOf(b, start) };
}
