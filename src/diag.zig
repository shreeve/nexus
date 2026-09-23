//! Generator diagnostics on stderr. Errors and warnings share one format,
//! `error: <message>` / `warning: <message>`, prefixed with
//! `file:line:col: ` when they point into a grammar file; progress lines
//! are plain text.

const std = @import("std");

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n", args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("warning: " ++ fmt ++ "\n", args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

/// A grammar file, for turning byte offsets into `file:line:col`.
pub const Source = struct {
    path: []const u8,
    text: []const u8,
    /// Offset in `text` that positions passed to `at` are relative to
    /// (the start of the @parser body for frontend positions).
    base: usize = 0,

    pub const Loc = struct { line: u32, col: u32 };

    /// 1-based line and column of the byte at `base + pos`.
    pub fn at(self: Source, pos: usize) Loc {
        const off = @min(self.base + pos, self.text.len);
        var line: u32 = 1;
        var col: u32 = 1;
        for (self.text[0..off]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else col += 1;
        }
        return .{ .line = line, .col = col };
    }
};

/// `file:line:col: error: <message>` for the byte at `pos` (relative to
/// `source.base`).
pub fn errAt(source: Source, pos: usize, comptime fmt: []const u8, args: anytype) void {
    const loc = source.at(pos);
    errLine(source.path, loc.line, loc.col, fmt, args);
}

/// `file:line:col: error: <message>` for a known line and column.
pub fn errLine(path: []const u8, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}:{d}:{d}: error: " ++ fmt ++ "\n", .{ path, line, col } ++ args);
}
