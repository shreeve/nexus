//! The facts std.zig.Ast keeps only as tokens, each in its role: doc
//! comments (`doc`), `pub` (`visib`), `extern`/`export`/`inline`
//! (`modifier`), library names, `threadlocal`, `comptime`, parameter
//! flags, names and `anytype`/`...` types, the inferred-error `!`
//! (`bang`), labels, captures, else captures, prong flags and indexes,
//! pointer qualifiers (`quals`), struct initializer names, error set
//! members.

/// doc
pub extern "c" threadlocal var a: u8;
/// doc
pub inline fn b(comptime T: type, noalias p: *T, q: anytype, ...) !void {
    blk: {
        comptime var c, var d = .{ 1, 2 };
        outer: for (p, 0..) |*e, i| while (q) |f| : (c += 1) {} else |err| break :outer err;
        sw: switch (c) {
            inline 0, 1...2 => |v, tag| continue :sw v + tag,
            else => |v| break :blk v catch |e| e,
        }
    }
}
const g: *allowzero align(4:0:8) const volatile u8 = .{ .h = 1, .i = 2 };
const E = error{
    /// doc
    A,
    B,
};
