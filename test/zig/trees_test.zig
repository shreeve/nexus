//! The trees the parser generated from zig.grammar builds against
//! std.zig.Ast's (trees.zig), on inputs that use every kind and role of
//! the schema and every rule trees.zig lists. test/zig/compare-trees runs
//! the same comparison over any corpus.
const std = @import("std");
const parser = @import("parser.zig");
const trees = @import("trees.zig");

fn expectSameTree(src: [:0]const u8) !void {
    const gpa = std.testing.allocator;
    var p = parser.Parser.init(gpa, "");
    defer p.deinit();
    var a: std.Io.Writer.Allocating = .init(gpa);
    defer a.deinit();
    var b: std.Io.Writer.Allocating = .init(gpa);
    defer b.deinit();
    switch (try trees.compare(gpa, &p, src, &a, &b)) {
        .same => {},
        .skipped => {
            std.debug.print("input {f}: not accepted by both\n", .{std.zig.fmtString(src)});
            return error.TestUnexpectedResult;
        },
        .differ => {
            const d = trees.firstDiff(a.written(), b.written());
            std.debug.print("input {f}: line {d}\n  after: {s}\n  nexus: {s}\n  std:   {s}\n", .{
                std.zig.fmtString(src), d.line, d.prev, d.a, d.b,
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "declarations, containers, fields, doc comments" {
    try expectSameTree(
        \\//! A file.
        \\//! Its doc.
        \\
        \\/// A test? No: a constant.
        \\pub const a: u8 align(4) addrspace(.generic) linksection(".x") = 1;
        \\pub extern "c" threadlocal var b: c_int;
        \\export var c: u32 = 0;
        \\extern fn d(x: c_int, ...) callconv(.c) c_int;
        \\/// e
        \\pub inline fn e(
        \\    comptime T: type,
        \\    noalias p: *T,
        \\    q: anytype,
        \\    /// r's doc
        \\    r: u8,
        \\    /// doc
        \\    u8,
        \\) !void {}
        \\noinline fn f(u8, comptime u8) align(8) void {}
        \\test "t" {}
        \\test f {}
        \\comptime {}
        \\const S = extern struct {
        \\    //! S's doc
        \\    /// x's doc
        \\    x: u32 align(4) = 1,
        \\    comptime y: u8 = 2,
        \\    const z = 3;
        \\};
        \\const T = struct { u8, comptime u32 = 3 };
        \\const U = union(enum(u8)) { a: u8, b };
        \\const V = packed union(u32) { a: u32 };
        \\const W = union(enum) { a };
        \\const X = enum(u8) {
        \\    //! T7: an empty enum(T) ends at its `}`
        \\};
        \\const Y = opaque {};
        \\const E = error{
        \\    A,
        \\    /// B's doc
        \\    B,
        \\};
    );
}

test "statements, `;`, destructures (T3), labels (T5)" {
    try expectSameTree(
        \\fn f() void {
        \\    var x: u32 = 0;
        \\    comptime var y = 1;
        \\    x += 1;
        \\    x = y;
        \\    const a, var b = .{ 1, 2 };
        \\    comptime var c, var d = .{ 1, 2 };
        \\    comptime e, f = .{ 1, 2 };
        \\    a, b = .{ b, a };
        \\    comptime x = 1;
        \\    comptime {}
        \\    defer x += 1;
        \\    errdefer {}
        \\    nosuspend g();
        \\    suspend {}
        \\    if (x) |v| y = v else |err| y = err;
        \\    if (x) {} else if (y) |*v| {} else {}
        \\    if (x) y = 1;
        \\    while (x) |v| : (i += 1) y = v else |e| y = e;
        \\    outer: while (true) {}
        \\    inline for (a, 0..) |*p, i| {} else {}
        \\    blk: {
        \\        break :blk;
        \\    }
        \\    sw: switch (x) {
        \\        0 => continue :sw 1,
        \\        1, 2...3 => |v| y = v,
        \\        inline 4 => |v, tag| {},
        \\        inline else => break :sw,
        \\    }
        \\    _ = [.x: {}]u8;
        \\    _ = a[0..break :x: {}];
        \\    return;
        \\}
    );
}

test "expressions" {
    try expectSameTree(
        \\const a = b or c and d == e;
        \\const b = (f != g) and (h < i) or (j > k) and (l <= m) or (n >= o);
        \\const k = l & m ^ n | o orelse p catch |e| q catch r;
        \\const s = t << u >> v <<| w + x - y ++ z +% a -% b +| c -| d;
        \\const e = f * g / h % i *% j *| k || l;
        \\const m = !n + -o + ~p + -%q + &r + try s;
        \\const t = u(v, w,).x.*.?[y][z..][a..b][c..d :0][e.. :0];
        \\const f = @import("std");
        \\const g = .h;
        \\const i = error.J;
        \\const k = .{ .l = 1, .m = 2 };
        \\const n = T{ 1, 2 };
        \\const o = T{};
        \\const p = .{};
        \\const q = (r);
        \\const s = unreachable;
        \\const t = anyframe;
        \\const u = 'c';
        \\const v =
        \\    \\multi
        \\    \\line
        \\;
        \\const w = if (x) y else z;
        \\const a = for (b) |c| d else e;
        \\const f = while (g) |h| i else |j| k;
        \\const l = switch (m) { else => n };
        \\const o = comptime p;
        \\const q = nosuspend r;
        \\fn s() void { resume t; }
        \\const u = asm volatile ("x" : [a] "=r" (-> u8), [b] "=r" (c) : [d] "r" (e) : .{ .memory = true });
        \\const f = asm ("x");
        \\const g = asm ("x" :);
    );
}

test "types, pointers (T6), parameters and captures (T1)" {
    try expectSameTree(
        \\const a: ?*const volatile u8 = null;
        \\const b: [*]align(4) const u8 = undefined;
        \\const c: [*c]u8 = undefined;
        \\const d: [*:0]u8 = undefined;
        \\const e: []allowzero u8 = undefined;
        \\const f: [:0]align(1) addrspace(.generic) const u8 = undefined;
        \\const g: *align(1:2:4) u8 = undefined;
        \\const h: *addrspace(.generic) align(2) u8 = undefined;
        \\const i: *const const u8 = undefined;
        \\const j: [4:0]u8 = undefined;
        \\const k: [4]u8 = undefined;
        \\const l: anyframe->u8 = undefined;
        \\const m: E!u8 = undefined;
        \\const n: fn (u8) callconv(.c) void = undefined;
        \\const o = a[*c];
        \\const p = a[*T];
        \\fn q(r: if (s) t else u, v: for (w) |x| y) void {}
    );
}

test "loops and blocks Ast's helpers misread (T5, T8, T9)" {
    try expectSameTree(
        \\fn g() void {
        \\    _ = [.x: {}]u8;
        \\    _ = [.x: for (a) |b| c]u8;
        \\    _ = [.x: inline while (a) b]u8;
        \\    _ = a[0..break :x: for (a) |b| c];
        \\    _ = f(blk: for (a) |b| c);
        \\    _ = .{ .x = blk: while (a) b };
        \\    switch (x) {
        \\        inline for (a) |b| c => {},
        \\        inline while (d) e => {},
        \\        inline inline for (a) |b| c => {},
        \\        inline blk: while (d) e => {},
        \\        inline fn () void => {},
        \\        for (a) |b| c, inline for (a) |b| c => {},
        \\        inline else => {},
        \\    }
        \\}
        \\const S = struct { x: inline for (a) |b| c, y: while (a) b = 1 };
        \\fn h(comptime T: inline while (a) b, U: for (a) |b| c, x: blk: for (a) |b| c) void {
        \\    const a: for (b) |c| d = 1;
        \\    var e: inline while (f) g = 2;
        \\}
    );
}
