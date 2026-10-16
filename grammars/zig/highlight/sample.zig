//! A module doc comment.
const std = @import("std");

/// A point, with a doc comment.
pub const Point = struct {
    x: i32 = 0,
    y: u8,
    name: []const u8 = "p\tq\x41\u{2192} \"done\"",

    pub fn norm(self: Point) usize {
        return @intCast(self.x * self.x) +% 1;
    }
};

extern "c" fn puts(s: [*:0]const u8) c_int;

test "points" {
    var p: Point = .{ .y = 'a', .x = -0x1F };
    const c = '\n';
    outer: while (p.x < 10) : (p.x += 1) {
        if (p.x == 3 and c != 0) continue :outer else break :outer;
    }
    const s =
        \\multiline "string"
    ;
    _ = s orelse null;
    try std.testing.expect(p.y >= 1.5e3 or true);
    const T = ?*anyopaque;
    _ = T;
}
