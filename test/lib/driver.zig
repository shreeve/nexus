//! Generic test driver for Nexus-generated parsers.
//!
//! Compiled next to a generated `parser.zig` (and the grammar's `@lang`
//! module files) by test/lib/build-grammar. It parses source files with a
//! fresh parser each and prints the resulting trees in a canonical form:
//!
//!   (tag child …)      a list; the head is printed like any other child
//!   `text`             a .src leaf (escaped: \\ \` \n \r \t \xHH)
//!   `text`#7           a .src leaf whose id is non-zero
//!   "text"             a .str value
//!   name               a .tag value
//!   _                  nil
//!   (…)@12..40         a list with a node span, when the parser records spans
//!   !error Name at L:C unexpected <cat>   a parse failure
//!
//! Usage:
//!   driver [--start parseX] [--pretty|--compact|--hash] [--no-spans]
//!          [--list FILE] [--bench N] FILE...
//!
//!   --pretty    (default) indented tree, one file per invocation is typical
//!   --compact   one line per file: `<path>\t<tree or !error …>`
//!   --hash      one line per file: `<path>\t<ok|err>\t<16 hex digits>\t<error>`
//!   --bench N   time lexing alone and lexing+parsing, best of N rounds
//!   --no-spans  never print node spans (differential runs between a parser
//!               with spans and one without)
//!
//! The start rule defaults to the first `parse*` method of the parser. Any
//! method `fn (*Parser) !Sexp` whose name starts with `parse` can be named.
//! The driver adapts to the Sexp representation at compile time: lists may
//! be a slice (0.10.x) or a struct with `items()` (1.0).

const std = @import("std");
const parser = @import("parser.zig");

const Sexp = parser.Sexp;
// 0.10.x emits no `Parser` alias for a grammar without @lang.
const P = if (@hasDecl(parser, "Parser")) parser.Parser else parser.BaseParser;

const width = 100;

// -----------------------------------------------------------------------------
// Start rules: every `pub fn parseX(self: *P) !Sexp`, discovered at comptime
// -----------------------------------------------------------------------------

fn isStart(comptime name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "parse")) return false;
    const F = @TypeOf(@field(P, name));
    const info = @typeInfo(F);
    if (info != .@"fn") return false;
    const f = info.@"fn";
    if (f.params.len != 1) return false;
    if (f.params[0].type != *P) return false;
    const R = f.return_type orelse return false;
    const ri = @typeInfo(R);
    if (ri != .error_union) return false;
    return ri.error_union.payload == Sexp;
}

const start_names = blk: {
    var names: []const []const u8 = &.{};
    for (@typeInfo(P).@"struct".decls) |d| {
        if (isStart(d.name)) names = names ++ .{d.name};
    }
    break :blk names;
};

fn callStart(p: *P, name: []const u8) !Sexp {
    inline for (start_names) |n| {
        if (std.mem.eql(u8, n, name)) return @field(P, n)(p);
    }
    return error.UnknownStartRule;
}

fn currentToken(p: *P) parser.Token {
    if (@hasField(P, "current")) return p.current;
    if (@hasField(P, "base")) {
        const B = @TypeOf(p.base);
        if (@hasField(B, "current")) return p.base.current;
    }
    return .{ .pos = 0, .len = 0, .cat = @enumFromInt(0), .pre = 0 };
}

// -----------------------------------------------------------------------------
// Tree rendering
// -----------------------------------------------------------------------------

fn listItems(l: anytype) []const Sexp {
    const L = @TypeOf(l);
    if (L == []const Sexp) return l;
    if (L == []Sexp) return l;
    return l.items();
}

// Spans are printed when the parser records them (`nodeStore`: `@schema`
// or `--spans`); without a node store `span()` only hulls the leaves.
const has_spans = @hasDecl(P, "span") and (!@hasDecl(parser, "nodeStore") or parser.nodeStore);

const Printer = struct {
    src: []const u8,
    parser: *P,
    spans: bool,
    out: *std.Io.Writer,

    fn spanOf(self: *Printer, s: Sexp) ?struct { usize, usize } {
        if (!has_spans) return null;
        if (!self.spans) return null;
        const sp = self.parser.span(s);
        return .{ @intCast(sp.start), @intCast(sp.end) };
    }

    fn escaped(self: *Printer, text: []const u8, quote: u8) !void {
        for (text) |c| switch (c) {
            '\\' => try self.out.writeAll("\\\\"),
            '\n' => try self.out.writeAll("\\n"),
            '\r' => try self.out.writeAll("\\r"),
            '\t' => try self.out.writeAll("\\t"),
            else => if (c == quote) {
                try self.out.writeByte('\\');
                try self.out.writeByte(c);
            } else if (c < 0x20 or c == 0x7f) {
                try self.out.print("\\x{x:0>2}", .{c});
            } else try self.out.writeByte(c),
        };
    }

    fn atom(self: *Printer, s: Sexp) !void {
        switch (s) {
            .nil => try self.out.writeByte('_'),
            .tag => |t| {
                if (std.enums.tagName(@TypeOf(t), t)) |n| try self.out.writeAll(n) else try self.out.print("?tag{d}", .{@intFromEnum(t)});
            },
            .src => |x| {
                const lo: usize = @min(@as(usize, x.pos), self.src.len);
                const hi: usize = @min(lo + @as(usize, x.len), self.src.len);
                try self.out.writeByte('`');
                try self.escaped(self.src[lo..hi], '`');
                try self.out.writeByte('`');
                if (x.id != 0) try self.out.print("#{d}", .{x.id});
            },
            .str => |x| {
                try self.out.writeByte('"');
                try self.escaped(x, '"');
                try self.out.writeByte('"');
            },
            .list => unreachable,
        }
    }

    fn compact(self: *Printer, s: Sexp) !void {
        switch (s) {
            .list => |l| {
                try self.out.writeByte('(');
                for (listItems(l), 0..) |it, i| {
                    if (i > 0) try self.out.writeByte(' ');
                    try self.compact(it);
                }
                try self.out.writeByte(')');
                try self.spanSuffix(s);
            },
            else => try self.atom(s),
        }
    }

    fn spanSuffix(self: *Printer, s: Sexp) !void {
        if (self.spanOf(s)) |sp| try self.out.print("@{d}..{d}", .{ sp[0], sp[1] });
    }

    /// Length of the compact rendering, or anything > limit once it is known
    /// to exceed it (keeps pretty-printing linear in practice).
    fn flatLen(self: *Printer, s: Sexp, limit: usize) usize {
        var d: std.Io.Writer.Discarding = .init(&.{});
        var sub = Printer{ .src = self.src, .parser = self.parser, .spans = self.spans, .out = &d.writer };
        switch (s) {
            .list => |l| {
                var n: usize = 2;
                if (self.spanOf(s)) |_| {
                    sub.spanSuffix(s) catch {};
                    n += @intCast(d.fullCount());
                }
                for (listItems(l), 0..) |it, i| {
                    if (i > 0) n += 1;
                    n += self.flatLen(it, limit -| n);
                    if (n > limit) return n;
                }
                return n;
            },
            else => {
                sub.atom(s) catch {};
                return @intCast(d.fullCount());
            },
        }
    }

    fn pretty(self: *Printer, s: Sexp, indent: usize) !void {
        const room = width -| indent;
        if (s != .list or self.flatLen(s, room) <= room) return self.compact(s);
        const items = listItems(s.list);
        try self.out.writeByte('(');
        for (items, 0..) |it, i| {
            if (i > 0) {
                try self.out.writeByte('\n');
                try self.out.splatByteAll(' ', indent + 2);
                try self.pretty(it, indent + 2);
            } else {
                try self.pretty(it, indent + 1);
            }
        }
        try self.out.writeByte(')');
        try self.spanSuffix(s);
    }
};

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

const Mode = enum { pretty, compact, hash, bench };

fn lineCol(src: []const u8, pos: usize) struct { usize, usize } {
    var line: usize = 1;
    var col: usize = 1;
    for (src[0..@min(pos, src.len)]) |c| {
        if (c == '\n') {
            line += 1;
            col = 1;
        } else col += 1;
    }
    return .{ line, col };
}

fn writeError(out: *std.Io.Writer, src: []const u8, p: *P, err: anyerror) !void {
    const tok = currentToken(p);
    const lc = lineCol(src, tok.pos);
    try out.print("!error {s} at {d}:{d} unexpected {s}", .{ @errorName(err), lc[0], lc[1], @tagName(tok.cat) });
}

fn usage() noreturn {
    std.debug.print("usage: driver [--start parseX] [--pretty|--compact|--hash] [--no-spans] [--list FILE] [--bench N] FILE...\n", .{});
    std.debug.print("start rules:", .{});
    inline for (start_names) |n| std.debug.print(" {s}", .{n});
    std.debug.print("\n", .{});
    std.process.exit(2);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = std.heap.smp_allocator;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (start_names.len == 0) @compileError("parser has no parse* start method");
    var start: []const u8 = start_names[0];
    var mode: Mode = .pretty;
    var spans = true;
    var rounds: usize = 1;
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    const cwd = std.Io.Dir.cwd();

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--start")) {
            i += 1;
            if (i >= args.len) usage();
            start = args[i];
        } else if (std.mem.eql(u8, a, "--pretty")) {
            mode = .pretty;
        } else if (std.mem.eql(u8, a, "--compact")) {
            mode = .compact;
        } else if (std.mem.eql(u8, a, "--hash")) {
            mode = .hash;
        } else if (std.mem.eql(u8, a, "--no-spans")) {
            spans = false;
        } else if (std.mem.eql(u8, a, "--bench")) {
            i += 1;
            if (i >= args.len) usage();
            mode = .bench;
            rounds = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, a, "--list")) {
            i += 1;
            if (i >= args.len) usage();
            const list = try cwd.readFileAlloc(io, args[i], arena, .limited(1 << 30));
            var it = std.mem.tokenizeScalar(u8, list, '\n');
            while (it.next()) |path| try files.append(arena, path);
        } else if (std.mem.eql(u8, a, "--starts")) {
            inline for (start_names) |n| std.debug.print("{s}\n", .{n});
            return;
        } else if (a.len > 1 and a[0] == '-') {
            usage();
        } else {
            try files.append(arena, a);
        }
    }
    var known = false;
    inline for (start_names) |n| {
        if (std.mem.eql(u8, n, start)) known = true;
    }
    if (!known) {
        std.debug.print("driver: no start rule '{s}'\n", .{start});
        usage();
    }

    var buf: [64 * 1024]u8 = undefined;
    var fw = std.Io.File.stdout().writerStreaming(io, &buf);
    const out = &fw.interface;

    if (mode == .bench) return bench(io, gpa, arena, files.items, start, rounds, out);

    var render: std.Io.Writer.Allocating = .init(gpa);
    defer render.deinit();

    var status: u8 = 0;
    for (files.items) |path| {
        const src = cwd.readFileAlloc(io, path, gpa, .limited(1 << 28)) catch |e| {
            try out.print("{s}\t!read-error {s}\n", .{ path, @errorName(e) });
            try out.flush();
            status = 1;
            continue;
        };
        defer gpa.free(src);

        var p = P.init(gpa, src);
        defer if (@hasDecl(P, "deinit")) p.deinit();
        const result = callStart(&p, start);

        render.clearRetainingCapacity();
        const w = &render.writer;
        var pr = Printer{ .src = src, .parser = &p, .spans = spans, .out = w };
        var ok = true;
        if (result) |sexp| {
            switch (mode) {
                .pretty => try pr.pretty(sexp, 0),
                else => try pr.compact(sexp),
            }
        } else |err| {
            ok = false;
            status = 1;
            try writeError(w, src, &p, err);
        }
        const text = render.written();
        switch (mode) {
            .pretty => {
                try out.writeAll(text);
                try out.writeByte('\n');
            },
            .compact => try out.print("{s}\t{s}\n", .{ path, text }),
            .hash => {
                const h = std.hash.Wyhash.hash(0, text);
                try out.print("{s}\t{s}\t{x:0>16}\t{s}\n", .{ path, if (ok) "ok" else "err", h, if (ok) "" else text });
            },
            .bench => unreachable,
        }
        try out.flush();
    }
    try out.flush();
    // Parse failures are part of the output, not a driver failure; the exit
    // status only says whether every file parsed.
    std.process.exit(status);
}

fn bench(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    paths: []const []const u8,
    start: []const u8,
    rounds: usize,
    out: *std.Io.Writer,
) !void {
    const cwd = std.Io.Dir.cwd();
    var srcs: std.ArrayListUnmanaged([]const u8) = .empty;
    var bytes: usize = 0;
    for (paths) |path| {
        const src = try cwd.readFileAlloc(io, path, arena, .limited(1 << 28));
        try srcs.append(arena, src);
        bytes += src.len;
    }

    var best_lex: i96 = std.math.maxInt(i96);
    var best_parse: i96 = std.math.maxInt(i96);
    var tokens: usize = 0;
    var ok: usize = 0;
    var round: usize = 0;
    while (round < rounds) : (round += 1) {
        // Lexing alone (through the lang Lexer wrapper when there is one).
        var t0 = std.Io.Timestamp.now(io, .awake);
        var ntok: usize = 0;
        for (srcs.items) |src| {
            var lx = parser.Lexer.init(src);
            const cap = src.len * 2 + 16;
            var n: usize = 0;
            while (n < cap) : (n += 1) {
                const tok = lx.next();
                if (tok.cat == .eof) break;
            }
            ntok += n + 1;
        }
        const lex_ns = t0.untilNow(io, .awake).nanoseconds;
        best_lex = @min(best_lex, lex_ns);
        tokens = ntok;

        // Lexing + parsing.
        t0 = std.Io.Timestamp.now(io, .awake);
        var nok: usize = 0;
        for (srcs.items) |src| {
            var p = P.init(gpa, src);
            defer if (@hasDecl(P, "deinit")) p.deinit();
            if (callStart(&p, start)) |_| nok += 1 else |_| {}
        }
        const parse_ns = t0.untilNow(io, .awake).nanoseconds;
        best_parse = @min(best_parse, parse_ns);
        ok = nok;
    }
    const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
    const lex_s = @as(f64, @floatFromInt(best_lex)) / 1e9;
    const parse_s = @as(f64, @floatFromInt(best_parse)) / 1e9;
    try out.print(
        "files={d} ok={d} bytes={d} tokens={d} lex_ms={d:.1} lex_mb_s={d:.1} parse_ms={d:.1} parse_mb_s={d:.1} mtok_s={d:.2}\n",
        .{ srcs.items.len, ok, bytes, tokens, lex_s * 1000, mb / lex_s, parse_s * 1000, mb / parse_s, @as(f64, @floatFromInt(tokens)) / 1e6 / parse_s },
    );
    try out.flush();
}
