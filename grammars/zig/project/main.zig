//! Names across files, std's included (editor/names.session).
const std = @import("std");
const util = @import("util.zig");

pub fn main() void {
    const total = util.add(1, 2);
    std.debug.assert(std.mem.eql(u8, "ab", "ab"));
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.heap.page_allocator);
    _ = total;
}
