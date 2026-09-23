//! Diagnostics shared by the compiler passes.
//!
//! A `Diagnostic` is a severity, a byte offset into the module source,
//! and a message. Passes collect them in a `DiagList` and the CLI prints
//! them as `file:line:col: error: message` (notes are indented and
//! attach to the preceding error).
//!
//! `firstSrcPos` recovers a source position for any IR node, and
//! `lineCol` turns a byte offset into a 1-based line and column.

const std = @import("std");
const parser = @import("parser.zig");

const Sexp = parser.Sexp;

pub const Severity = enum { @"error", note };

pub const Diagnostic = struct {
    severity: Severity,
    pos: u32,
    message: []const u8,
};

/// An append-only list of diagnostics. Messages are allocated in
/// `arena`, which the owner frees in one step; the list itself uses
/// `allocator`.
pub const DiagList = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    items: std.ArrayListUnmanaged(Diagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator) DiagList {
        return .{ .allocator = allocator, .arena = arena };
    }

    pub fn deinit(self: *DiagList) void {
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *DiagList, severity: Severity, pos: u32, comptime fmt: []const u8, args: anytype) std.mem.Allocator.Error!void {
        const msg = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.items.append(self.allocator, .{ .severity = severity, .pos = pos, .message = msg });
    }

    pub fn err(self: *DiagList, pos: u32, comptime fmt: []const u8, args: anytype) std.mem.Allocator.Error!void {
        return self.add(.@"error", pos, fmt, args);
    }

    pub fn note(self: *DiagList, pos: u32, comptime fmt: []const u8, args: anytype) std.mem.Allocator.Error!void {
        return self.add(.note, pos, fmt, args);
    }

    pub fn hasErrors(self: *const DiagList) bool {
        return hasErrorsIn(self.items.items);
    }
};

pub fn hasErrorsIn(items: []const Diagnostic) bool {
    for (items) |d| {
        if (d.severity == .@"error") return true;
    }
    return false;
}

/// Print `items` as `path:line:col: error: message`. Never fails on
/// odd input: an empty path, an empty source, or a position past the
/// end of the source all still print something readable.
pub fn write(items: []const Diagnostic, source: []const u8, file_path: []const u8, w: anytype) !void {
    const path = if (file_path.len == 0) "<unknown>" else file_path;
    for (items) |d| {
        const tag = switch (d.severity) {
            .@"error" => "error",
            .note => "  note",
        };
        const msg = if (d.message.len == 0) "(no message)" else d.message;
        if (source.len == 0) {
            try w.print("{s}: {s}: {s}\n", .{ path, tag, msg });
        } else {
            const lc = lineCol(source, d.pos);
            try w.print("{s}:{d}:{d}: {s}: {s}\n", .{ path, lc.line, lc.col, tag, msg });
        }
    }
}

pub const LineCol = struct { line: u32, col: u32 };

/// 1-based line and column of byte offset `pos`. A tab counts as one
/// column. Positions past the end clamp to the end of the source.
pub fn lineCol(source: []const u8, pos: u32) LineCol {
    var line: u32 = 1;
    var col: u32 = 1;
    const end = @min(pos, source.len);
    for (source[0..end]) |c| {
        if (c == '\n') {
            line += 1;
            col = 1;
        } else col += 1;
    }
    return .{ .line = line, .col = col };
}

/// Position of the first source token inside `sexp`, or 0 if it has
/// none. Used to anchor diagnostics on compound nodes.
pub fn firstSrcPos(sexp: Sexp) u32 {
    return switch (sexp) {
        .src => |s| s.pos,
        .list => |items| blk: {
            for (items) |c| {
                const p = firstSrcPos(c);
                if (p > 0) break :blk p;
            }
            break :blk 0;
        },
        else => 0,
    };
}

test "lineCol: counts lines and columns from 1" {
    const src = "ab\ncd\n";
    try std.testing.expectEqual(LineCol{ .line = 1, .col = 1 }, lineCol(src, 0));
    try std.testing.expectEqual(LineCol{ .line = 1, .col = 2 }, lineCol(src, 1));
    try std.testing.expectEqual(LineCol{ .line = 2, .col = 1 }, lineCol(src, 3));
    try std.testing.expectEqual(LineCol{ .line = 3, .col = 1 }, lineCol(src, 999));
}

test "DiagList: collects errors and notes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var list = DiagList.init(std.testing.allocator, arena.allocator());
    defer list.deinit();
    try list.note(0, "n", .{});
    try std.testing.expect(!list.hasErrors());
    try list.err(3, "bad {s}", .{"thing"});
    try std.testing.expect(list.hasErrors());
    try std.testing.expectEqualStrings("bad thing", list.items.items[1].message);
}
