//! Members and imports across files, for grammars/zig/compare-members.

const std = @import("std");
const shapes = @import("shapes.zig");
const deep = @import("nested/deep.zig");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Point = shapes.Point;

pub fn main() void {
    // Through std's files: std.zig, then mem.zig.
    _ = std.mem.eql(u8, "a", "b");
    _ = mem.indexOfScalar(u8, "ab", 'b');
    const gpa: Allocator = std.heap.page_allocator;
    _ = gpa;
    // A declared type's members, and a container's.
    var p: Point = .{ .x = 1, .y = 2 };
    p.x += shapes.Point.origin.y;
    _ = shapes.Shape.circle;
    _ = shapes.Color.true;
    // A file two imports away, and an alias.
    _ = deep.Level.depth;
    _ = deep.shapes.area(p);
    // Answers nothing: a call's result, a generic, a private declaration
    // of another file, and a block's value.
    _ = shapes.make().x;
    var list: std.ArrayList(u8) = .empty;
    _ = list.items;
    _ = shapes.hidden;
    const block = blk: {
        const inner = 1;
        break :blk inner;
    };
    _ = block.inner;
}
