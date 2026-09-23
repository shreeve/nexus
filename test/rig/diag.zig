//! Diagnostics shared by the compiler passes.
//!
//! A `Diagnostic` is a severity, a source range of the module (usually
//! the span of the IR node it is about), and a message. Passes collect
//! them and the CLI prints each as `file:line:col: error: message` at the
//! start of the range, followed by the source line with the range
//! underlined (notes are indented and attach to the preceding error).
//!
//! Node spans come from the parser (`parser.Parser.span`); `leafSpan`
//! is the fallback for a tree without them. `lineCol` turns a byte
//! offset into a 1-based line and column.

const std = @import("std");
const parser = @import("parser.zig");

const Sexp = parser.Sexp;

pub const Severity = enum { @"error", note };

pub const Span = parser.Span;

pub const Diagnostic = struct {
    severity: Severity,
    /// Where the diagnostic points: the start of its range.
    pos: u32,
    /// End of the range (exclusive); at most `pos` for a single point.
    end: u32 = 0,
    message: []const u8,
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
            try writeExcerpt(source, d.pos, d.end, w);
        }
    }
}

/// The source line holding `pos`, then a line underlining the range
/// `pos..end` on it (`^` at `pos`, `~` for the rest of the range, which
/// stops at the end of the line). Tabs are copied into the underline so
/// it stays aligned.
pub fn writeExcerpt(source: []const u8, pos: u32, end: u32, w: anytype) !void {
    const at: usize = @min(pos, source.len);
    var start = at;
    while (start > 0 and source[start - 1] != '\n') start -= 1;
    var stop = at;
    while (stop < source.len and source[stop] != '\n' and source[stop] != '\r') stop += 1;
    try w.print("{s}\n", .{source[start..stop]});
    for (source[start..at]) |c| try w.writeByte(if (c == '\t') '\t' else ' ');
    try w.writeByte('^');
    const last = @min(@as(usize, @max(end, pos)), stop);
    if (last > at + 1) for (at + 1..last) |_| try w.writeByte('~');
    try w.writeByte('\n');
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

/// The range from the first to the end of the last source token in
/// `sexp`: a node's span as far as its leaves tell. Keywords and
/// punctuation are not leaves, so this is a fallback for trees without
/// the parser's spans; it is empty at 0 for a node without leaves.
pub fn leafSpan(sexp: Sexp) Span {
    switch (sexp) {
        .src => |s| return .{ .start = s.pos, .end = s.pos + s.len },
        .list => {
            var out: ?Span = null;
            for (sexp.items()) |c| {
                const cs = leafSpan(c);
                if (cs.end == 0) continue;
                out = if (out) |o| .{ .start = @min(o.start, cs.start), .end = @max(o.end, cs.end) } else cs;
            }
            return out orelse .empty;
        },
        else => return .empty,
    }
}

test "lineCol: counts lines and columns from 1" {
    const src = "ab\ncd\n";
    try std.testing.expectEqual(LineCol{ .line = 1, .col = 1 }, lineCol(src, 0));
    try std.testing.expectEqual(LineCol{ .line = 1, .col = 2 }, lineCol(src, 1));
    try std.testing.expectEqual(LineCol{ .line = 2, .col = 1 }, lineCol(src, 3));
    try std.testing.expectEqual(LineCol{ .line = 3, .col = 1 }, lineCol(src, 999));
}

test "write: position, message, and the range underlined on its line" {
    const src = "sub main()\n  x = foo(1, 2)\n  y\n";
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const at: u32 = 17; // `foo`
    try write(&.{
        .{ .severity = .@"error", .pos = at, .end = at + 9, .message = "bad call" },
        .{ .severity = .note, .pos = 0, .message = "here" },
    }, src, "m.rig", &w);
    try std.testing.expectEqualStrings(
        \\m.rig:2:7: error: bad call
        \\  x = foo(1, 2)
        \\      ^~~~~~~~~
        \\m.rig:1:1:   note: here
        \\sub main()
        \\^
        \\
    , w.buffered());
}

test "leafSpan: from the first leaf to the end of the last" {
    var inner = [_]Sexp{ .{ .tag = .@"+" }, .{ .src = .{ .pos = 4, .len = 1, .id = 0 } }, .{ .src = .{ .pos = 8, .len = 2, .id = 0 } } };
    const s = leafSpan(Sexp.listOf(&inner));
    try std.testing.expectEqual(@as(u32, 4), s.start);
    try std.testing.expectEqual(@as(u32, 10), s.end);
}
