//! @lang module of the repair_runaway test: a Parser whose start method
//! parses tolerantly with a budget of 1,000,000 repairs and returns the
//! tree, or a summary of the repairs when the parse is incomplete.
const std = @import("std");
const parser = @import("parser.zig");

pub const Parser = struct {
    base: parser.BaseParser,
    gpa: std.mem.Allocator,
    summary: []u8 = &.{},

    pub fn init(gpa: std.mem.Allocator, source: []const u8) Parser {
        return .{ .base = .init(gpa, source), .gpa = gpa };
    }

    pub fn deinit(self: *Parser) void {
        self.base.deinit();
        self.gpa.free(self.summary);
    }

    pub fn parseTop(self: *Parser) !parser.Sexp {
        const r = try self.base.parseTolerant(.top, 1_000_000);
        if (r.complete) return r.sexp;
        self.summary = try std.fmt.allocPrint(self.gpa, "incomplete: {d} insertions, {d} deletions", .{ r.insertions, r.deletions });
        return .{ .str = self.summary };
    }
};
