//! Generator diagnostics on stderr. Errors and warnings share one format,
//! `error: <message>` / `warning: <message>`; progress lines are plain text.

const std = @import("std");

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n", args);
}

/// A located error: `file:line:col: error: message`.
pub fn errAt(file: []const u8, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}:{d}:{d}: error: " ++ fmt ++ "\n", .{ file, line, col } ++ args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("warning: " ++ fmt ++ "\n", args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
