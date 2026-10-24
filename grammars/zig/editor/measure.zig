//! measure.zig: times hooks.zig's `parseDiagnostics` and `format` on files,
//! and counts what `format` does with each (README.md, "The language
//! server"). It builds in the server's `src/`, beside `hooks.zig`:
//!
//!     cp grammars/zig/editor/measure.zig ~/nexus-zig/server/src/
//!     cd ~/nexus-zig/server && zig build-exe -O safe src/measure.zig
//!     ./measure [-n ROUNDS] [-q] [-r] [-t] [-c] FILE...
//!
//! `-n` takes the best of ROUNDS runs of each; `-q` prints only the files
//! that are not formatted already. Before the hooks see a file, `-r`
//! halves the blanks that start each line, `-t` puts a blank at the end of
//! each line and `-c` ends each line with CRLF: each makes a file that
//! `zig fmt` changes but whose program stays the same, so the guard of
//! `format` must let the edit through.

const std = @import("std");
const hooks = @import("hooks.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = std.heap.page_allocator;
    var args = try init.minimal.args.iterateAllocator(gpa);
    _ = args.next();
    var rounds: usize = 1;
    var quiet = false;
    var reindent = false;
    var trailing = false;
    var crlf = false;
    var counts: std.StringArrayHashMapUnmanaged(usize) = .empty;
    var files: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-n")) {
            rounds = try std.fmt.parseInt(usize, args.next() orelse return error.MissingRounds, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "-q")) {
            quiet = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-r")) {
            reindent = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-t")) {
            trailing = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-c")) {
            crlf = true;
            continue;
        }
        var text = try std.Io.Dir.cwd().readFileAlloc(io, arg, gpa, .limited(1 << 30));
        if (reindent) text = try halveIndents(gpa, text);
        if (trailing) text = try endLines(gpa, text, " \n");
        if (crlf) text = try endLines(gpa, text, "\r\n");
        files += 1;
        var best_diagnostics: u64 = std.math.maxInt(u64);
        var best_format: u64 = std.math.maxInt(u64);
        var errors: usize = 0;
        var outcome: []const u8 = "";
        for (0..rounds) |_| {
            var arena: std.heap.ArenaAllocator = .init(gpa);
            defer arena.deinit();
            const t0 = std.Io.Clock.awake.now(io);
            const diagnostics = try hooks.parseDiagnostics(arena.allocator(), arg, text);
            const t1 = std.Io.Clock.awake.now(io);
            const formatted = hooks.format(arena.allocator(), arg, text);
            const t2 = std.Io.Clock.awake.now(io);
            errors = diagnostics.len;
            outcome = if (formatted) |f| (if (f == null) "formatted already" else "formatted") else |err| @errorName(err);
            best_diagnostics = @min(best_diagnostics, @as(u64, @intCast(t0.durationTo(t1).toNanoseconds())));
            best_format = @min(best_format, @as(u64, @intCast(t1.durationTo(t2).toNanoseconds())));
        }
        const count = try counts.getOrPut(gpa, outcome);
        if (!count.found_existing) count.value_ptr.* = 0;
        count.value_ptr.* += 1;
        if (!quiet or !std.mem.eql(u8, outcome, "formatted already"))
            std.debug.print("{s}: {d} bytes, parseDiagnostics {d:.1} ms ({d} errors), format {d:.1} ms ({s})\n", .{
                arg, text.len, ms(best_diagnostics), errors, ms(best_format), outcome,
            });
    }
    std.debug.print("{d} files\n", .{files});
    for (counts.keys(), counts.values()) |k, v| std.debug.print("  {s}: {d}\n", .{ k, v });
}

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}

/// The text with the blanks that start each line halved.
fn halveIndents(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(gpa, '\n');
        first = false;
        var n: usize = 0;
        while (n < line.len and line[n] == ' ') n += 1;
        try out.appendNTimes(gpa, ' ', n / 2);
        try out.appendSlice(gpa, line[n..]);
    }
    return out.items;
}

/// The text with each `\n` replaced by `end`.
fn endLines(gpa: std.mem.Allocator, text: []const u8, end: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |c| if (c == '\n') try out.appendSlice(gpa, end) else try out.append(gpa, c);
    return out.items;
}
