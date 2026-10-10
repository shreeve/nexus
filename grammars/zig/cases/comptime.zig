const std = @import("std");

const table = comptime blk: {
    var t: [16]u8 = undefined;
    for (&t, 0..) |*v, i| v.* = @intCast(i);
    break :blk t;
};

fn sum(comptime xs: []const u32) u32 {
    comptime var total: u32 = 0;
    inline for (xs) |x| total += x;
    return total;
}

test {
    comptime {
        std.debug.assert(sum(&.{ 1, 2, 3 }) == 6);
    }
    comptime var i = 0;
    comptime i += 1;
    comptime std.debug.assert(i == 1);
    const T = comptime if (true) u8 else u16;
    _ = T;
    comptime var a: u8, var b: u8 = .{ 1, 2 };
    a, b = .{ b, a };
}
