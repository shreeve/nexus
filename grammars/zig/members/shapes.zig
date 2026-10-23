//! Containers and their members, imported by main.zig and nested/deep.zig.

pub const Point = struct {
    x: i32,
    y: i32,

    pub const origin: Point = .{ .x = 0, .y = 0 };
};

pub const Shape = union(enum) {
    circle: f32,
    square: f32,
};

/// An enum whose fields are named like primitives.
pub const Color = enum { true, false, bool };

pub fn area(p: Point) i32 {
    return p.x * p.y;
}

pub fn make() Point {
    return Point.origin;
}

const hidden = 1;
