//! Colours by meaning (server/tokens.session).
const std = @import("std");

/// A point.
pub const Point = struct {
    x: i32,
    y: i32,

    pub fn sum(p: Point) i32 {
        return p.x + p.y;
    }
};

const Color = enum { red, green };
const Failure = error{Broken};
const limit = 10;
var count: u32 = 0;

fn scale(value: i32, by: i32) Failure!i32 {
    if (by > limit) return error.Broken;
    count += 1;
    const c: Color = .red;
    std.debug.assert(c != .green);
    return value * by;
}

test scale {
    const p: Point = .{ .x = 1, .y = 2 };
    _ = try scale(p.sum(), 2);
}
