//! Generator diagnostics on stderr. Errors and warnings share one format,
//! `error: <message>` / `warning: <message>`; progress lines are plain text.

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
