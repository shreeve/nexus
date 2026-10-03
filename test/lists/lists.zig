//! @lang module of the list grammar: its tags and a pass-through Lexer
//! wrapper. Its test parses long lists within a fixed memory budget.
const std = @import("std");
const parser = @import("parser.zig");

pub const Tag = enum(u8) { top, star, plus, list, sep, opt, nils, _ };

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        return self.base.next();
    }
    pub fn text(self: *const Lexer, tok: parser.Token) []const u8 {
        return self.base.text(tok);
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};

const testing = std.testing;

/// `open`, `first`, n - 1 copies of `rest`, then `;`: a list of n items.
fn listText(open: []const u8, first: []const u8, rest: []const u8, n: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(testing.allocator);
    try out.appendSlice(testing.allocator, open);
    try out.appendSlice(testing.allocator, first);
    for (1..n) |_| try out.appendSlice(testing.allocator, rest);
    try out.append(testing.allocator, ';');
    return out.toOwnedSlice(testing.allocator);
}

// Each list is built in place, so a list of n items costs O(n) memory
// (about 17 MB here). A list copied at every item would allocate n²/2
// item copies (5·10⁹ here) and run out at once.
test "a list of 100,000 items parses within 32 MB" {
    const n = 100_000;
    const budget = try testing.allocator.alloc(u8, 32 << 20);
    defer testing.allocator.free(budget);
    const forms = [_][3][]const u8{
        .{ "*", "a ", "a " }, .{ "+", "a ", "a " }, .{ ",", "a", ", a" },
        .{ "/", "a", "/a" },  .{ "?", "", "," },    .{ "=", "- ", "- " },
    };
    for (forms) |f| {
        const text = try listText(f[0], f[1], f[2], n);
        defer testing.allocator.free(text);
        var fba: std.heap.FixedBufferAllocator = .init(budget);
        var p = parser.Parser.init(fba.allocator(), text);
        defer p.deinit();
        const tree = try p.parseTop();
        // (top (star (a a ...)))
        const list = tree.list.items()[1].list.items()[1];
        try testing.expectEqual(@as(usize, n), list.list.items().len);
    }
}
