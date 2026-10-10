//! Compares what the parser generated from zig.grammar accepts with what
//! std.zig.Ast.parse accepts. Built by grammars/zig/compare-accept next to the
//! generated parser.zig and zig.zig; see that script for usage.
//!
//!   accept [--list FILE] [--inline FILE] PATH...    compare, input by input
//!   accept --bench N [--list FILE] PATH...           parse-only timing
//!   accept --fuzz N [--seed S] [--list FILE] [--inline FILE] PATH...
//!                                                    compare on N mutants
//!   accept --messages [--list FILE] [--inline FILE] PATH...
//!                                                    both syntax errors
//!
//! The Nexus side is a strict parse from the `root` start symbol; the std
//! side is Ast.parse(.{ .recover = false, .mode = .zig }), which stops at
//! the first error, as std.zig's own fuzz test runs it. An input is
//! accepted when it parses with no error. Compare prints one line per
//! input on which the two disagree, with the first error of the side that
//! rejects, and a summary. A file that Nexus rejects at an `err` token of
//! 65535 bytes, a token std.zig.Tokenizer lexes as one longer token while
//! accepting the file, is listed as LONG, not counted as differing.
//!
//! --inline FILE takes the inputs from the string literals given to
//! testCanonical, testTransform (both sources), testError and
//! checkAgainstOracle in FILE (std.zig's parser_test.zig and
//! parser_fuzz.zig), named FILE:LINE.
//!
//! --fuzz N compares on N inputs made from the given ones: a piece of a
//! seed (the whole seed when small, else the lines from one top-level
//! line to a later one), then one to four token edits (delete, duplicate,
//! swap two neighbors, insert a token taken from the seed or from a list
//! of keywords and operators, with a space, a newline or nothing around
//! it). A differing input is printed in full.
//!
//! --messages prints, for every input both parsers reject, the syntax
//! error each gives (Nexus's writeError, Ast's renderError), and counts
//! how many of Nexus's name at most 6 expected items, and how many report
//! the error at the same line and column as Ast.
//!
//! --bench N times both parsers over the files held in memory, best of N
//! rounds, single thread: Nexus's strict parse (one parser, reset per
//! file) and Ast.parse (tokenize and parse, deinit included). MB are 10^6
//! bytes.

const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const parser = @import("parser.zig");
const inputs = @import("inputs.zig");
const Input = inputs.Input;
const writeQuoted = inputs.writeQuoted;

/// One parser's verdict: accepted, or the byte offset of its first error.
const Verdict = struct {
    ok: bool,
    pos: usize = 0,
    what: []const u8 = "",
    /// Nexus only: the error is at an `err` token of 65535 bytes.
    long: bool = false,
};

fn nexusVerdict(p: *parser.Parser, src: []const u8) Verdict {
    p.reset(src);
    _ = p.parseRoot() catch |err| switch (err) {
        error.ParseError => {
            const f = p.lastError().?;
            return .{
                .ok = false,
                .pos = f.span.start,
                .what = @tagName(f.cat),
                .long = f.cat == .err and f.span.len() == std.math.maxInt(u16),
            };
        },
        else => std.process.fatal("nexus: {t}", .{err}),
    };
    return .{ .ok = true };
}

fn stdVerdict(gpa: std.mem.Allocator, src: [:0]const u8) !Verdict {
    var tree = try Ast.parse(gpa, src, .{ .recover = false, .mode = .zig });
    defer tree.deinit(gpa);
    if (tree.errors.len == 0) return .{ .ok = true };
    const e = tree.errors[0];
    return .{ .ok = false, .pos = tree.tokenStart(e.token) + tree.errorOffset(e), .what = @tagName(e.tag) };
}

fn lineCol(src: []const u8, pos: usize) struct { usize, usize } {
    var line: usize = 1;
    var start: usize = 0;
    for (src[0..@min(pos, src.len)], 0..) |c, i| if (c == '\n') {
        line += 1;
        start = i + 1;
    };
    return .{ line, pos - start + 1 };
}

fn writeVerdict(w: *Io.Writer, src: []const u8, v: Verdict) !void {
    if (v.ok) return w.writeAll("accept");
    const line, const col = lineCol(src, v.pos);
    try w.print("reject {d}:{d} {s}", .{ line, col, v.what });
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();

    var paths: std.ArrayList([]const u8) = .empty;
    var inline_inputs: std.ArrayList(Input) = .empty;
    var rounds: usize = 0;
    var fuzz: usize = 0;
    var seed: u64 = 0;
    var messages = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const value = i + 1 < args.len;
        if (std.mem.eql(u8, arg, "--list") and value) {
            i += 1;
            const data = try cwd.readFileAlloc(io, args[i], arena, .unlimited);
            var it = std.mem.tokenizeScalar(u8, data, '\n');
            while (it.next()) |line| try paths.append(arena, line);
        } else if (std.mem.eql(u8, arg, "--inline") and value) {
            i += 1;
            try inputs.inlineInputs(io, arena, args[i], &inline_inputs);
        } else if (std.mem.eql(u8, arg, "--bench") and value) {
            i += 1;
            rounds = try std.fmt.parseUnsigned(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--fuzz") and value) {
            i += 1;
            fuzz = try std.fmt.parseUnsigned(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--messages")) {
            messages = true;
        } else if (std.mem.eql(u8, arg, "--seed") and value) {
            i += 1;
            seed = try std.fmt.parseUnsigned(u64, args[i], 10);
        } else if (arg.len > 1 and arg[0] == '-') {
            std.process.fatal("unknown option or missing value: {s}", .{arg});
        } else {
            try paths.append(arena, arg);
        }
    }

    var buf: [64 * 1024]u8 = undefined;
    var fw = Io.File.stdout().writerStreaming(io, &buf);
    const w = &fw.interface;
    defer w.flush() catch {};

    if (rounds != 0) return bench(io, arena, gpa, paths.items, rounds, w);
    if (fuzz != 0) {
        for (paths.items) |path| {
            const src = cwd.readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            try inline_inputs.append(arena, .{ .name = path, .src = src });
        }
        if (inline_inputs.items.len == 0) std.process.fatal("--fuzz needs seed inputs", .{});
        return fuzzCompare(gpa, inline_inputs.items, fuzz, seed, w);
    }

    var p = parser.Parser.init(gpa, "");
    defer p.deinit();
    var count: usize = 0;
    var both_accept: usize = 0;
    var both_reject: usize = 0;
    var same_pos: usize = 0;
    var differ: usize = 0;
    var long: usize = 0;
    var bytes: usize = 0;
    var short_msg: usize = 0;
    var same_line_col: usize = 0;

    const total = paths.items.len + inline_inputs.items.len;
    for (0..total) |k| {
        var owned: ?[:0]u8 = null;
        defer if (owned) |o| gpa.free(o);
        const input: Input = if (k < paths.items.len) blk: {
            const path = paths.items[k];
            const src = cwd.readFileAllocOptions(io, path, gpa, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            owned = src;
            break :blk .{ .name = path, .src = src };
        } else inline_inputs.items[k - paths.items.len];
        count += 1;
        bytes += input.src.len;

        const a = nexusVerdict(&p, input.src);
        const b = try stdVerdict(gpa, input.src);
        if (a.ok and b.ok) {
            both_accept += 1;
            continue;
        }
        if (!a.ok and !b.ok) {
            both_reject += 1;
            if (a.pos == b.pos) same_pos += 1;
            if (messages) {
                const short, const same = try writeMessages(gpa, &p, input, w);
                short_msg += @intFromBool(short);
                same_line_col += @intFromBool(same);
            }
            continue;
        }
        if (a.long and b.ok) {
            long += 1;
            const line, const col = lineCol(input.src, a.pos);
            try w.print("LONG {s}: nexus reject {d}:{d} at a token over 65535 bytes | std accept\n", .{ input.name, line, col });
            continue;
        }
        differ += 1;
        try w.print("DIFF {s}: nexus ", .{input.name});
        try writeVerdict(w, input.src, a);
        try w.writeAll(" | std ");
        try writeVerdict(w, input.src, b);
        try w.writeByte('\n');
        if (k >= paths.items.len) {
            try w.writeAll("  input: ");
            try writeQuoted(w, input.src);
            try w.writeByte('\n');
        }
    }
    try w.print("{d} inputs ({d:.2} MB): {d} accepted by both, {d} rejected by both ({d} at the same byte), {d} differ, {d} with a token over 65535 bytes\n", .{
        count, @as(f64, @floatFromInt(bytes)) / 1e6, both_accept, both_reject, same_pos, differ, long,
    });
    if (messages) try w.print("{d} rejected by both: {d} Nexus messages name at most 6 expected items, {d} are at Ast's line and column\n", .{
        both_reject, short_msg, same_line_col,
    });
    try w.flush();
    if (differ != 0) std.process.exit(1);
}

/// Both syntax errors of an input both parsers reject (`p` holds Nexus's
/// failed parse); returns whether Nexus's names at most 6 expected items
/// and whether it is at Ast's line and column.
fn writeMessages(gpa: std.mem.Allocator, p: *parser.Parser, input: Input, w: *Io.Writer) !struct { bool, bool } {
    var nexus: Io.Writer.Allocating = .init(gpa);
    defer nexus.deinit();
    try p.writeError(&nexus.writer);
    var tree = try Ast.parse(gpa, input.src, .{ .recover = false, .mode = .zig });
    defer tree.deinit(gpa);
    const e = tree.errors[0];
    const loc = tree.tokenLocation(0, e.token);
    var std_msg: Io.Writer.Allocating = .init(gpa);
    defer std_msg.deinit();
    try std_msg.writer.print("{d}:{d}: ", .{ loc.line + 1, loc.column + 1 + tree.errorOffset(e) });
    try tree.renderError(e, &std_msg.writer);
    try w.print("MSG {s}\n  nexus: {s}\n  std:   {s}\n", .{ input.name, nexus.written(), std_msg.written() });
    const text = nexus.written();
    const got = std.mem.findLast(u8, text, ", got ") orelse text.len;
    const items = std.mem.count(u8, text[0..got], ", ") + std.mem.count(u8, text[0..got], " or ") + 1;
    const at = text[0 .. std.mem.findScalar(u8, text, ' ') orelse 0];
    const std_at = std_msg.written()[0 .. std.mem.findScalar(u8, std_msg.written(), ' ') orelse 0];
    return .{ items <= 6, std.mem.eql(u8, at, std_at) };
}

fn fuzzCompare(gpa: std.mem.Allocator, seeds: []const Input, n: usize, seed: u64, w: *Io.Writer) !void {
    var mutator: inputs.Mutator = .init(seed);
    defer mutator.deinit(gpa);
    var p = parser.Parser.init(gpa, "");
    defer p.deinit();
    var stats: [3]usize = .{ 0, 0, 0 };
    var differ: usize = 0;
    for (0..n) |k| {
        const s, const src = try mutator.next(gpa, seeds);
        const a = nexusVerdict(&p, src);
        const b = try stdVerdict(gpa, src);
        if (a.ok == b.ok) {
            stats[if (a.ok) 0 else 1] += 1;
            continue;
        }
        if (a.long and b.ok) {
            stats[2] += 1;
            continue;
        }
        differ += 1;
        try w.print("DIFF fuzz #{d} (from {s}): nexus ", .{ k, s.name });
        try writeVerdict(w, src, a);
        try w.writeAll(" | std ");
        try writeVerdict(w, src, b);
        try w.writeAll("\n  input: ");
        try writeQuoted(w, src);
        try w.writeByte('\n');
    }
    try w.print("{d} mutants of {d} seeds: {d} accepted by both, {d} rejected by both, {d} differ, {d} with a token over 65535 bytes\n", .{
        n, seeds.len, stats[0], stats[1], differ, stats[2],
    });
    try w.flush();
    if (differ != 0) std.process.exit(1);
}

fn now(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

fn bench(io: Io, arena: std.mem.Allocator, gpa: std.mem.Allocator, paths: []const []const u8, rounds: usize, w: *Io.Writer) !void {
    const sources = try arena.alloc([:0]const u8, paths.len);
    var bytes: usize = 0;
    for (paths, sources) |path, *s| {
        s.* = Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0) catch |err|
            std.process.fatal("{s}: {t}", .{ path, err });
        bytes += s.len;
    }

    var best: [2]i96 = .{ std.math.maxInt(i96), std.math.maxInt(i96) };
    var accepted: [2]usize = .{ 0, 0 };
    var p = parser.Parser.init(gpa, "");
    defer p.deinit();
    for (0..rounds) |_| {
        var ok: usize = 0;
        var t0 = now(io);
        for (sources) |src| {
            p.reset(src);
            if (p.parseRoot()) |_| {
                ok += 1;
            } else |_| {}
        }
        best[0] = @min(best[0], now(io) - t0);
        accepted[0] = ok;

        ok = 0;
        t0 = now(io);
        for (sources) |src| {
            var tree = try Ast.parse(gpa, src, .{ .recover = false, .mode = .zig });
            if (tree.errors.len == 0) ok += 1;
            tree.deinit(gpa);
        }
        best[1] = @min(best[1], now(io) - t0);
        accepted[1] = ok;
    }
    const mb = @as(f64, @floatFromInt(bytes)) / 1e6;
    try w.print("{d} files, {d:.2} MB, best of {d}\n", .{ sources.len, mb, rounds });
    const names = [_][]const u8{ "nexus", "std" };
    for (names, best, accepted) |name, ns, ok| {
        const s = @as(f64, @floatFromInt(ns)) / 1e9;
        try w.print("  {s:<6} {d:>9.2} ms  {d:>8.1} MB/s  ({d} accepted)\n", .{ name, s * 1e3, mb / s, ok });
    }
}
