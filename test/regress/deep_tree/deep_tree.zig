//! @lang module of the deep_tree test: a Parser that reads N from its
//! source, parses `x+x+...+x` (N additions), walks the tree with every
//! public walk the runtime has, and returns a summary of what they saw.
const std = @import("std");
const parser = @import("parser.zig");

pub const Parser = struct {
    base: parser.BaseParser,
    gpa: std.mem.Allocator,
    input: []u8,
    summary: []u8 = &.{},

    pub fn init(gpa: std.mem.Allocator, source: []const u8) Parser {
        const n = std.fmt.parseInt(usize, std.mem.trim(u8, source, " \n"), 10) catch 0;
        const input = gpa.alloc(u8, 2 * n + 1) catch @panic("out of memory");
        input[0] = 'x';
        for (0..n) |i| input[1 + 2 * i ..][0..2].* = "+x".*;
        return .{ .base = .init(gpa, input), .gpa = gpa, .input = input };
    }

    pub fn deinit(self: *Parser) void {
        self.base.deinit();
        self.gpa.free(self.input);
        self.gpa.free(self.summary);
    }

    pub fn span(self: *const Parser, s: parser.Sexp) parser.Span {
        return self.base.span(s);
    }

    pub fn parseProg(self: *Parser) !parser.Sexp {
        const tree = try self.base.parseProg();
        var out: std.Io.Writer.Discarding = .init(&.{});
        try tree.write(self.input, &out.writer);
        const written = out.fullCount();
        var facts: u64 = 0;
        if (parser.nodeStore) {
            out = .init(&.{});
            try self.base.writeFacts(&out.writer, tree);
            facts = out.fullCount();
        }
        const sp = self.base.span(tree.items()[1]);
        self.summary = try std.fmt.allocPrint(self.gpa, "{d} bytes in, write {d} bytes, facts {d} bytes, span {d}..{d}", .{ self.input.len, written, facts, sp.start, sp.end });
        return .{ .str = self.summary };
    }
};
