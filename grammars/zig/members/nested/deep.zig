//! A file in a directory below main.zig, importing one above it.

pub const shapes = @import("../shapes.zig");

pub const Level = struct {
    pub const depth = 2;
    pub const corner = shapes.Point.origin;
};
