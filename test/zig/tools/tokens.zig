//! Compares the lexer generated from zig.grammar with std.zig.Tokenizer.
//! Built by test/zig/compare-tokens next to the generated parser.zig and
//! zig.zig; see that script for usage.
//!
//!   tokens [--list FILE] PATH...                compare, file by file
//!   tokens --fuzz N [--seed S]                  compare on N random inputs
//!   tokens --dump nexus|std [--list FILE] PATH...
//!   tokens --bench N [--list FILE] PATH...      tokenize-only timing
//!
//! Compare prints one line per input whose token streams differ (tag by
//! name, start, end, up to and including eof), with the first difference,
//! then a summary with the longest token. A token longer than 65535 bytes,
//! the most a Nexus token holds, is the one difference it allows: Nexus
//! lexes it as `err` over the same bytes, and the input is listed as LONG
//! when everything else is equal. --fuzz draws inputs of up to 511 bytes,
//! alternately from std.zig.Tokenizer's own fuzz-test byte weights and
//! from a mix of token fragments. --dump prints a stream in the format of
//! the zigtok oracle (`# path bytes`, then `tag start end`). --bench times
//! both lexers over the files held in memory, best of N rounds, single
//! thread; MB are 10^6 bytes and token counts include one eof per file.

const std = @import("std");
const Io = std.Io;
const parser = @import("parser.zig");

const Tok = struct {
    tag: []const u8,
    start: usize,
    end: usize,

    fn eql(a: Tok, b: Tok) bool {
        return a.start == b.start and a.end == b.end and std.mem.eql(u8, a.tag, b.tag);
    }
};

/// A Nexus token as std.zig.Tokenizer would name it. A token longer than
/// 65535 bytes is an `err` token holding its first 65535; the lexer resumes
/// after the whole match, so its true end is the lexer's position.
fn nexusTok(lx: *parser.BaseLexer, t: parser.Token) Tok {
    const end: usize = if (t.cat == .err and t.len == std.math.maxInt(u16)) lx.pos else @as(usize, t.pos) + t.len;
    return .{ .tag = @tagName(t.cat), .start = t.pos, .end = end };
}

/// The generated lexer as the lang module starts it (after a byte order
/// mark), driven without the lang Lexer's own token rewriting.
fn baseLexer(src: []const u8) parser.BaseLexer {
    return parser.Lexer.init(src).base;
}

fn stdTok(t: std.zig.Token) Tok {
    return .{ .tag = @tagName(t.tag), .start = t.loc.start, .end = t.loc.end };
}

const Stats = struct {
    inputs: usize = 0,
    differ: usize = 0,
    long: usize = 0,
    tokens: usize = 0,
    longest: Tok = .{ .tag = "none", .start = 0, .end = 0 },
    longest_in: []const u8 = "",
};

/// Compares the two streams of `src`; `name` labels its report lines.
fn compare(arena: std.mem.Allocator, w: *Io.Writer, st: *Stats, name: []const u8, src: [:0]const u8) !void {
    st.inputs += 1;
    var lx = baseLexer(src);
    var tz = std.zig.Tokenizer.init(src);
    var n: usize = 0;
    var long = false;
    var nexus_done = false;
    var std_done = false;
    defer st.tokens += n;
    while (!(nexus_done and std_done)) : (n += 1) {
        const a: ?Tok = if (nexus_done) null else nexusTok(&lx, lx.next());
        const b: ?Tok = if (std_done) null else stdTok(tz.next());
        if (a) |t| nexus_done = std.mem.eql(u8, t.tag, "eof");
        if (b) |t| std_done = std.mem.eql(u8, t.tag, "eof");
        if (a != null and b != null) {
            const t = b.?;
            if (t.end - t.start > st.longest.end - st.longest.start) {
                st.longest = t;
                st.longest_in = try arena.dupe(u8, name);
            }
            if (a.?.eql(t)) continue;
            // A token longer than a Nexus token can hold: the same extent,
            // as `err`; the streams go on in step.
            if (std.mem.eql(u8, a.?.tag, "err") and a.?.start == t.start and a.?.end == t.end and
                t.end - t.start > std.math.maxInt(u16))
            {
                if (!long) st.long += 1;
                long = true;
                try w.print("LONG {s}: token {d}: std {s} {d} {d} ({d} bytes) is a Nexus err token\n", .{
                    name, n, t.tag, t.start, t.end, t.end - t.start,
                });
                continue;
            }
        }
        st.differ += 1;
        try w.print("DIFF {s}: token {d}: nexus ", .{ name, n });
        try writeTok(w, src, a);
        try w.writeAll(" | std ");
        try writeTok(w, src, b);
        try w.writeByte('\n');
        return;
    }
}

const Mode = enum { compare, fuzz, dump_nexus, dump_std, bench };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();

    var paths: std.ArrayList([]const u8) = .empty;
    var mode: Mode = .compare;
    var count: usize = 5;
    var seed: u64 = 0;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const value = i + 1 < args.len;
        if (std.mem.eql(u8, arg, "--list") and value) {
            i += 1;
            const data = try cwd.readFileAlloc(io, args[i], arena, .unlimited);
            var it = std.mem.tokenizeScalar(u8, data, '\n');
            while (it.next()) |line| try paths.append(arena, line);
        } else if (std.mem.eql(u8, arg, "--dump") and value) {
            i += 1;
            mode = if (std.mem.eql(u8, args[i], "nexus")) .dump_nexus else if (std.mem.eql(u8, args[i], "std")) .dump_std else std.process.fatal("--dump needs nexus or std", .{});
        } else if ((std.mem.eql(u8, arg, "--bench") or std.mem.eql(u8, arg, "--fuzz")) and value) {
            mode = if (arg[2] == 'b') .bench else .fuzz;
            i += 1;
            count = try std.fmt.parseUnsigned(usize, args[i], 10);
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

    var st: Stats = .{};
    switch (mode) {
        .bench => return bench(io, arena, paths.items, count, w),
        .fuzz => {
            var prng: std.Random.DefaultPrng = .init(seed);
            const rand = prng.random();
            var src_buf: [512]u8 = undefined;
            for (0..count) |k| {
                const len = if (k % 2 == 0) weightedBytes(rand, &src_buf) else fragments(rand, &src_buf);
                src_buf[len] = 0;
                const src = src_buf[0..len :0];
                const before = st.differ;
                try compare(arena, w, &st, try std.fmt.allocPrint(arena, "fuzz #{d}", .{k}), src);
                if (st.differ != before) {
                    try w.writeAll("  input: ");
                    try writeQuoted(w, src);
                    try w.writeByte('\n');
                }
            }
        },
        .compare => for (paths.items) |path| {
            const src = cwd.readFileAllocOptions(io, path, gpa, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            defer gpa.free(src);
            try compare(arena, w, &st, path, src);
        },
        .dump_nexus, .dump_std => for (paths.items) |path| {
            const src = cwd.readFileAllocOptions(io, path, gpa, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            defer gpa.free(src);
            var lx = baseLexer(src);
            var tz = std.zig.Tokenizer.init(src);
            try w.print("# {s} {d}\n", .{ path, src.len });
            while (true) {
                const t = if (mode == .dump_nexus) nexusTok(&lx, lx.next()) else stdTok(tz.next());
                try w.print("{s} {d} {d}\n", .{ t.tag, t.start, t.end });
                if (std.mem.eql(u8, t.tag, "eof")) break;
            }
        },
    }
    if (mode == .dump_nexus or mode == .dump_std) return;
    try w.print("{d} inputs, {d} differ, {d} with a token over 65535 bytes, {d} tokens; longest token: {s} of {d} bytes at {s}:{d}\n", .{
        st.inputs, st.differ, st.long, st.tokens, st.longest.tag, st.longest.end - st.longest.start, st.longest_in, st.longest.start,
    });
    try w.flush();
    if (st.differ != 0) std.process.exit(1);
}

/// Random bytes weighted as std.zig.Tokenizer's fuzz test weights them.
fn weightedBytes(rand: std.Random, out: []u8) usize {
    const Range = struct { lo: u8, hi: u8, weight: u8 };
    const ranges = [_]Range{
        .{ .lo = 0x00, .hi = 0xff, .weight = 1 }, .{ .lo = 0x20, .hi = 0x7e, .weight = 4 },
        .{ .lo = 0x00, .hi = 0x1f, .weight = 1 }, .{ .lo = 0, .hi = 0, .weight = 6 },
        .{ .lo = ' ', .hi = ' ', .weight = 6 },   .{ .lo = '\t', .hi = '\n', .weight = 6 },
        .{ .lo = '\r', .hi = '\r', .weight = 3 },
    };
    const len = rand.uintLessThan(usize, out.len);
    for (out[0..len]) |*c| {
        var pick = rand.uintLessThan(u8, 27);
        for (ranges) |r| {
            if (pick < r.weight) {
                c.* = rand.intRangeAtMost(u8, r.lo, r.hi);
                break;
            }
            pick -= r.weight;
        }
    }
    return len;
}

/// A random mix of fragments that reach every tokenizer state.
fn fragments(rand: std.Random, out: []u8) usize {
    const pieces = [_][]const u8{
        "//", "///",  "////", "//!",  "\\\\",         "\\",       "\"", "'",   "@",    "@\"",  "\n",  "\r",     "\r\n", "\t",
        " ",  "\x00", "\x01", "\x7f", "\xef\xbb\xbf", "\xc2\x80", "#",  "$",   "`",    "0",    "1",   "9",      "0x",   "0b",
        "e",  "E",    "p",    "P",    "+",            "-",        ".",  "..",  "_",    "a",    "z",   "if",     "or",   "const",
        "x",  "*",    "%",    "|",    "=",            "!",        "<",  ">",   "&",    "^",    "~",   "?",      ":",    ";",
        ",",  "(",    ")",    "[",    "]",            "{",        "}",  "\\x", "\\u{", "\\\"", "\\'", "\\\\\\",
    };
    var len: usize = 0;
    const want = rand.uintLessThan(usize, out.len);
    while (true) {
        const p = pieces[rand.uintLessThan(usize, pieces.len)];
        if (len + p.len > want) break;
        @memcpy(out[len..][0..p.len], p);
        len += p.len;
    }
    return len;
}

fn writeQuoted(w: *Io.Writer, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0x20...0x21, 0x23...0x5b, 0x5d...0x7e => try w.writeByte(c),
        else => try w.print("\\x{x:0>2}", .{c}),
    };
    try w.writeByte('"');
}

fn writeTok(w: *Io.Writer, src: []const u8, t: ?Tok) !void {
    const tok = t orelse return w.writeAll("(ended)");
    try w.print("{s} {d} {d} ", .{ tok.tag, tok.start, tok.end });
    try writeQuoted(w, src[tok.start..@min(tok.end, tok.start + 40)]);
    if (tok.end - tok.start > 40) try w.writeAll("...");
}

fn now(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

fn bench(io: Io, arena: std.mem.Allocator, paths: []const []const u8, rounds: usize, w: *Io.Writer) !void {
    const sources = try arena.alloc([:0]const u8, paths.len);
    var bytes: usize = 0;
    for (paths, sources) |path, *s| {
        s.* = Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0) catch |err|
            std.process.fatal("{s}: {t}", .{ path, err });
        bytes += s.len;
    }

    var best: [2]i96 = .{ std.math.maxInt(i96), std.math.maxInt(i96) };
    var counts: [2]usize = .{ 0, 0 };
    var invalid: [2]usize = .{ 0, 0 };
    for (0..rounds) |_| {
        // Nexus, through the lang Lexer wrapper, as a parser drives it.
        var count: usize = 0;
        var bad: usize = 0;
        var t0 = now(io);
        for (sources) |src| {
            var lx = parser.Lexer.init(src);
            while (true) {
                const t = lx.next();
                count += 1;
                if (t.cat == .invalid) bad += 1;
                if (t.cat == .eof) break;
            }
        }
        best[0] = @min(best[0], now(io) - t0);
        counts[0] = count;
        invalid[0] = bad;

        // std.zig.Tokenizer, as zigbench's tokenize phase runs it.
        count = 0;
        bad = 0;
        t0 = now(io);
        for (sources) |src| {
            var tz: std.zig.Tokenizer = .init(src);
            while (true) {
                const t = tz.next();
                count += 1;
                if (t.tag == .invalid) bad += 1;
                if (t.tag == .eof) break;
            }
        }
        best[1] = @min(best[1], now(io) - t0);
        counts[1] = count;
        invalid[1] = bad;
    }
    const mb = @as(f64, @floatFromInt(bytes)) / 1e6;
    try w.print("{d} files, {d:.2} MB, best of {d}\n", .{ sources.len, mb, rounds });
    const names = [_][]const u8{ "nexus", "std" };
    for (names, best, counts, invalid) |name, ns, n, bad| {
        const s = @as(f64, @floatFromInt(ns)) / 1e9;
        try w.print("  {s:<6} {d:>9.2} ms  {d:>8.1} MB/s  {d:>7.2} Mtok/s  ({d} tokens, {d} invalid)\n", .{
            name, s * 1e3, mb / s, @as(f64, @floatFromInt(n)) / s / 1e6, n, bad,
        });
    }
}
