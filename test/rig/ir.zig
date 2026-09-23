//! The shape of every semantic IR node, and a check that a tree has it.
//!
//! Each tag that heads a node has a schema: a fixed sequence of slots,
//! optionally followed by any number of `rest` slots. The parser pads
//! absent trailing optional slots with `_` (`pad`), so every fixed slot
//! of a node exists and a consumer reads `items[i]` without a length
//! check; `validate` confirms the tree matches the schemas. Debug builds
//! of the compiler validate every module right after parsing.

const std = @import("std");
const parser = @import("parser.zig");
const rig = @import("rig.zig");
const diag = @import("diag.zig");

const Sexp = parser.Sexp;
const Tag = rig.Tag;

/// What one position of a node holds.
pub const Slot = enum {
    /// An expression, statement, pattern, or type: a leaf or a node.
    node,
    /// `node` or `_`.
    opt,
    /// A source leaf: a name or literal.
    leaf,
    /// `leaf` or `_`.
    opt_leaf,
    /// A marker tag (a binding kind, a loop mode) or `_`.
    marker,
    /// An untagged list (parameters, type parameters) or `_`.
    group,
};

pub const Shape = struct {
    slots: []const Slot,
    /// Slots after the fixed ones, any number of them.
    rest: ?Slot = null,
};

fn fixed(comptime slots: []const Slot) Shape {
    return .{ .slots = slots };
}

fn variadic(comptime slots: []const Slot, comptime rest: Slot) Shape {
    return .{ .slots = slots, .rest = rest };
}

/// The schema of nodes headed by `tag`; null for a tag that only
/// appears as a marker (`iter`, `ptr`, `fixed`, `shadow`, `+=`, ...).
pub fn shapeOf(tag: Tag) ?Shape {
    return switch (tag) {
        // Declarations
        .@"module" => variadic(&.{}, .node),
        .@"use", .@"zig" => fixed(&.{.leaf}),
        .@"fun", .@"sub" => fixed(&.{ .leaf, .group, .opt, .node }), // name params returns body
        .@"lambda" => fixed(&.{ .opt, .group, .opt, .node }), // captures params returns body
        .@"struct", .@"enum", .@"errors" => variadic(&.{.leaf}, .node), // name members...
        .@"generic_type", .@"generic_enum" => variadic(&.{ .leaf, .group }, .node),
        .@"type" => fixed(&.{ .leaf, .node }),
        .@"test" => fixed(&.{ .leaf, .node }),
        .@"pub" => fixed(&.{.node}),
        .@"extern" => fixed(&.{ .marker, .leaf, .node }), // _ name type
        .@"extern_fun" => fixed(&.{ .leaf, .group, .opt }), // name params returns
        .@"extern_sub" => fixed(&.{ .leaf, .group }),
        .@"drop_decl" => fixed(&.{ .group, .node }),
        .@"labeled" => fixed(&.{ .leaf, .node }),

        // Members and parameters
        .@":", .@"pre_param" => fixed(&.{ .leaf, .node }),
        .@"default" => fixed(&.{ .leaf, .node, .node }),
        .@"valued" => fixed(&.{ .leaf, .node }),
        .@"variant" => fixed(&.{ .leaf, .group }),

        // Bindings
        .@"set" => fixed(&.{ .marker, .node, .opt, .node }), // kind target type value
        .@"drop" => fixed(&.{.leaf}),

        // Control flow
        .@"if" => fixed(&.{ .node, .node, .opt }), // cond then else
        .@"as" => fixed(&.{ .node, .leaf }), // optional name
        .@"while" => fixed(&.{ .node, .opt, .node, .opt }), // cond step body else
        .@"for" => fixed(&.{ .marker, .leaf, .opt_leaf, .node, .node, .opt }), // mode x i source body else
        .@"match" => variadic(&.{.node}, .node),
        .@"arm" => fixed(&.{ .node, .node }), // pattern body
        .@"range_pattern" => fixed(&.{ .node, .node }),
        .@"variant_pattern" => variadic(&.{.leaf}, .leaf),
        .@"enum_lit" => fixed(&.{.leaf}),
        .@"return" => fixed(&.{.opt}),
        .@"break" => fixed(&.{ .opt, .opt_leaf }), // value label
        .@"continue" => fixed(&.{.opt_leaf}),
        .@"defer", .@"errdefer", .@"raw_block", .@"pre_block", .@"pre", .@"propagate" => fixed(&.{.node}),
        .@"try_block" => fixed(&.{ .node, .opt }), // body catch_block
        .@"catch_block" => fixed(&.{ .leaf, .node }),
        .@"catch" => fixed(&.{ .node, .opt_leaf, .node }), // value name handler
        .@"block" => variadic(&.{}, .node),

        // Closures
        .@"captures" => variadic(&.{}, .node),
        .@"cap_clone", .@"cap_weak", .@"cap_move" => fixed(&.{.leaf}),

        // Calls and access
        .@"call" => variadic(&.{.node}, .node),
        .@"builtin" => variadic(&.{.leaf}, .node),
        .@"member" => fixed(&.{ .node, .leaf }),
        .@"index" => fixed(&.{ .node, .node }),
        .@"array" => variadic(&.{}, .node),
        .@"kwarg" => fixed(&.{ .leaf, .node }),

        // Operators
        .@"+", .@"-", .@"*", .@"/", .@"%", .@"==", .@"!=", .@"<", .@">", .@"<=", .@">=",
        .@"&", .@"|", .@"^", .@"<<", .@">>", .@"??", .@"..", .@"and", .@"or",
        => fixed(&.{ .node, .node }),
        .@"neg", .@"not" => fixed(&.{.node}),

        // Ownership sigils (and `~T`, `?T`, `!T`, `*T` in type position)
        .@"move", .@"read", .@"write", .@"clone", .@"share", .@"weak", .@"pin" => fixed(&.{.node}),

        // Types
        .@"optional", .@"error_union", .@"borrow_read", .@"borrow_write", .@"shared", .@"slice" => fixed(&.{.node}),
        .@"generic_inst" => variadic(&.{.leaf}, .node),
        .@"array_type" => fixed(&.{ .leaf, .node }),
        .@"fun_type" => fixed(&.{ .group, .opt }), // params returns

        // Markers only.
        .@"iter", .@"ptr", .@"fixed", .@"shadow", .@"+=", .@"-=", .@"*=", .@"/=", .@"%=", .@"&=", .@"|=", .@"^=", .@"<<=", .@">>=" => null,
        _ => null,
    };
}

/// `items` (a node's head and children) with absent trailing optional
/// slots filled with `_`. Returns `items` itself when nothing is missing.
pub fn pad(allocator: std.mem.Allocator, items: []Sexp) std.mem.Allocator.Error![]Sexp {
    if (items.len == 0 or items[0] != .tag) return items;
    const shape = shapeOf(items[0].tag) orelse return items;
    const want = 1 + shape.slots.len;
    if (items.len >= want) return items;
    const out = try allocator.alloc(Sexp, want);
    @memcpy(out[0..items.len], items);
    @memset(out[items.len..], .nil);
    return out;
}

pub const Problem = struct {
    pos: u32,
    message: []const u8,
};

/// The first node in `tree` that does not match its schema, or null.
pub fn validate(tree: Sexp) ?Problem {
    return checkSlot(tree, .node);
}

fn checkSlot(s: Sexp, slot: Slot) ?Problem {
    switch (slot) {
        .node => return switch (s) {
            .src, .str => null,
            .list => checkNode(s),
            else => problem(s, "expected an expression or declaration"),
        },
        .opt => return if (s == .nil) null else checkSlot(s, .node),
        .leaf => return if (s == .src or s == .str) null else problem(s, "expected a name or literal"),
        .opt_leaf => return if (s == .nil) null else checkSlot(s, .leaf),
        .marker => return if (s == .nil or s == .tag) null else problem(s, "expected a marker tag"),
        .group => return switch (s) {
            .nil => null,
            .list => |items| blk: {
                if (items.len > 0 and items[0] == .tag) break :blk problem(s, "expected an untagged list");
                for (items) |c| if (checkSlot(c, .node)) |p| break :blk p;
                break :blk null;
            },
            else => problem(s, "expected a list"),
        },
    }
}

fn checkNode(s: Sexp) ?Problem {
    const items = s.list;
    if (items.len == 0 or items[0] != .tag) return problem(s, "expected a tagged node");
    const tag = items[0].tag;
    const shape = shapeOf(tag) orelse return problem(s, "a marker tag cannot head a node");
    const children = items[1..];
    if (children.len < shape.slots.len or (shape.rest == null and children.len > shape.slots.len)) {
        return problem(s, "wrong number of slots");
    }
    for (shape.slots, children[0..shape.slots.len]) |slot, c| {
        if (checkSlot(c, slot)) |p| return p;
    }
    if (shape.rest) |rest| for (children[shape.slots.len..]) |c| {
        if (checkSlot(c, rest)) |p| return p;
    };
    return null;
}

fn problem(s: Sexp, message: []const u8) Problem {
    return .{ .pos = diag.firstSrcPos(s), .message = message };
}

/// Debug builds: stop with an internal error if `tree` is malformed. The
/// parser produced it, so a mismatch is a compiler bug.
pub fn assertValid(tree: Sexp, source: []const u8, path: []const u8) void {
    if (@import("builtin").mode != .Debug) return;
    const p = validate(tree) orelse return;
    const lc = diag.lineCol(source, p.pos);
    std.debug.panic("{s}:{d}:{d}: internal error: malformed IR: {s}", .{ path, lc.line, lc.col, p.message });
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn parseValid(source: []const u8) !void {
    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    if (validate(tree)) |prob| {
        std.debug.print("malformed IR at {d}: {s}\n", .{ prob.pos, prob.message });
        return error.TestUnexpectedResult;
    }
}

test "every form the grammar produces matches its schema" {
    try parseValid(
        \\use m
        \\
        \\type Id = U64
        \\
        \\type Box(T)
        \\  value: T
        \\
        \\  fun get(?self) -> T
        \\    self.value
        \\
        \\enum Shape
        \\  circle(radius: Int)
        \\  empty()
        \\  dot
        \\
        \\enum Code
        \\  ok = 200
        \\
        \\error Net
        \\  timeout
        \\
        \\struct P
        \\  n: Int
        \\
        \\  drop self: !P
        \\    print(self.n)
        \\
        \\extern fun abs(n: Int) -> Int
        \\extern fun tick(n: Int)
        \\extern sub halt
        \\extern ptr: fun(Int) Int
        \\
        \\pub fun f(a: Int, b: Int = 2, pre c: Int) -> Int!
        \\  a
        \\
        \\test "t"
        \\  print(1)
        \\
        \\sub main()
        \\  x = 1
        \\  y: [2]Int =! [1, 2]
        \\  new x = x + 1
        \\  x += 1
        \\  x <<= 2
        \\  z <- w
        \\  -z
        \\  if x > 1
        \\    print x, y
        \\  else if not (x < 0 and true)
        \\    return
        \\  if m as v
        \\    print(v)
        \\  :outer while x < 3 : x += 1
        \\    break :outer
        \\  while m as v
        \\    continue
        \\  else
        \\    break
        \\  for a, i in ?xs
        \\    print(a[i])
        \\  else
        \\    print(0)
        \\  for *p in xs
        \\    print(p)
        \\  match s
        \\    .circle(r) => print(r)
        \\    1..3 => print(-1)
        \\    else
        \\      print(2)
        \\  g = |+c, <d, ~e, k: Int, j| c + k
        \\  h = *|+c| c.set(@sizeOf(Int))
        \\  i = || print(1)
        \\  v = f(1, b: 3) catch 0
        \\  u = f(1)!
        \\  t = f(1) catch |err| 0
        \\  q = a ?? b
        \\  o = 1 if c else 2
        \\  defer print(1)
        \\  raw
        \\    print(@intCast(x))
        \\  print(+a, <b, ?c, !d, *e, ~f, v.w[0])
        \\  n: fun() Int = f
        \\  n2: *sub(Int, ?Box(Int)) = h
        \\  n3: sub() = i
        \\  o2: (*Box(Int))? = none
        \\  o3: []~Int = o
        \\  return x
        \\
    );
}

test "malformed nodes are reported" {
    const a = testing.allocator;
    const cond: Sexp = .{ .src = .{ .pos = 0, .len = 1, .id = 0 } };
    var missing = [_]Sexp{ .{ .tag = .@"if" }, cond };
    try testing.expect(validate(.{ .list = &missing }) != null);
    var extra = [_]Sexp{ .{ .tag = .@"return" }, cond, cond };
    try testing.expect(validate(.{ .list = &extra }) != null);
    var not_leaf = [_]Sexp{ .{ .tag = .@"member" }, cond, .{ .list = &extra } };
    try testing.expect(validate(.{ .list = &not_leaf }) != null);
    var marker_head = [_]Sexp{ .{ .tag = .@"iter" }, cond };
    try testing.expect(validate(.{ .list = &marker_head }) != null);

    // Padding supplies absent trailing optional slots.
    var short = [_]Sexp{ .{ .tag = .@"if" }, cond, cond };
    const padded = try pad(a, &short);
    defer a.free(padded);
    try testing.expectEqual(@as(usize, 4), padded.len);
    try testing.expect(padded[3] == .nil);
    try testing.expect(validate(.{ .list = padded }) == null);
}
