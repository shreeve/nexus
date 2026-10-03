//! Generator diagnostics on stderr: `error: <message>`, prefixed with
//! `file:line:col: ` when it points into a grammar file (a grammar has no
//! warnings: every mistake is an error); progress lines are plain text.

const std = @import("std");

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n", args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

/// A grammar file, for turning byte offsets into `file:line:col`.
pub const Source = struct {
    path: []const u8,
    text: []const u8,
    /// The offset of every line start in `text`, ascending; the first is 0.
    lines: []const u32,

    pub const Loc = struct { line: u32, col: u32 };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, text: []const u8) !Source {
        var lines: std.ArrayList(u32) = .empty;
        try lines.append(allocator, 0);
        for (text, 0..) |c, i| if (c == '\n') try lines.append(allocator, @intCast(i + 1));
        return .{ .path = path, .text = text, .lines = try lines.toOwnedSlice(allocator) };
    }

    /// 1-based line and column of the byte at `pos` (clamped to the end).
    pub fn at(self: Source, pos: usize) Loc {
        const off = @min(pos, self.text.len);
        const n = std.sort.partitionPoint(u32, self.lines, off, startsAtOrBefore);
        return .{ .line = @intCast(n), .col = @intCast(off - self.lines[n - 1] + 1) };
    }

    fn startsAtOrBefore(off: usize, start: u32) bool {
        return start <= off;
    }
};

/// `file:line:col: error: <message>` for the byte at `pos`.
pub fn errAt(source: Source, pos: usize, comptime fmt: []const u8, args: anytype) void {
    const loc = source.at(pos);
    errLine(source.path, loc.line, loc.col, fmt, args);
}

/// `file:line:col: error: <message>` for a known line and column.
pub fn errLine(path: []const u8, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}:{d}:{d}: error: " ++ fmt ++ "\n", .{ path, line, col } ++ args);
}

test "Source.at maps offsets to lines and columns" {
    const testing = std.testing;
    const src = try Source.init(testing.allocator, "g", "ab\n\ncd\n");
    defer testing.allocator.free(src.lines);
    const cases = [_]struct { pos: usize, line: u32, col: u32 }{
        .{ .pos = 0, .line = 1, .col = 1 },
        .{ .pos = 2, .line = 1, .col = 3 },
        .{ .pos = 3, .line = 2, .col = 1 },
        .{ .pos = 5, .line = 3, .col = 2 },
        .{ .pos = 7, .line = 4, .col = 1 },
        .{ .pos = 99, .line = 4, .col = 1 },
    };
    for (cases) |c| try testing.expectEqual(Source.Loc{ .line = c.line, .col = c.col }, src.at(c.pos));
}
