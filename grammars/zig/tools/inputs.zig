//! Inputs shared by the Zig comparison tools (accept.zig, trees.zig):
//! source files, and the sources std.zig's parser tests give as string
//! literals.

const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;

/// A named source, with the 0 sentinel std.zig.Ast.parse needs.
pub const Input = struct {
    name: []const u8,
    src: [:0]const u8,
};

/// Writes `text` as a double-quoted string with Zig escapes.
pub fn writeQuoted(w: *Io.Writer, text: []const u8) !void {
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

/// The string literals passed to the test helpers in `path`.
pub fn inlineInputs(io: Io, arena: std.mem.Allocator, path: []const u8, out: *std.ArrayList(Input)) !void {
    const file = try Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0);
    var tree = try Ast.parse(arena, file, .{});
    if (tree.errors.len != 0) std.process.fatal("{s}: does not parse", .{path});
    const helpers = [_][]const u8{ "testCanonical", "testTransform", "testError", "checkAgainstOracle" };
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
        var b: [1]Ast.Node.Index = undefined;
        const call = tree.fullCall(&b, node) orelse continue;
        const f = call.ast.fn_expr;
        if (tree.nodeTag(f) != .identifier) continue;
        const name = tree.tokenSlice(tree.nodeMainToken(f));
        const helper = for (helpers) |h| {
            if (std.mem.eql(u8, name, h)) break h;
        } else continue;
        const nargs: usize = if (std.mem.eql(u8, helper, "testTransform")) 2 else 1;
        for (call.ast.params[0..@min(nargs, call.ast.params.len)]) |arg| {
            var bytes: std.ArrayList(u8) = .empty;
            switch (tree.nodeTag(arg)) {
                .string_literal => {
                    const lit = tree.tokenSlice(tree.nodeMainToken(arg));
                    try bytes.appendSlice(arena, try std.zig.string_literal.parseAlloc(arena, lit));
                },
                .multiline_string_literal => {
                    const first, const last = tree.nodeData(arg).token_and_token;
                    var t = first;
                    while (t <= last) : (t += 1) {
                        if (t != first) try bytes.append(arena, '\n');
                        try bytes.appendSlice(arena, tree.tokenSlice(t)[2..]);
                    }
                },
                else => continue,
            }
            const loc = tree.tokenLocation(0, tree.firstToken(arg));
            try bytes.append(arena, 0);
            const src = bytes.items[0 .. bytes.items.len - 1 :0];
            try out.append(arena, .{ .name = try std.fmt.allocPrint(arena, "{s}:{d}", .{ path, loc.line + 1 }), .src = src });
        }
    }
}

/// Makes inputs by token edits of seed inputs: a piece of a seed (the
/// whole seed when small, else the lines from one top-level line to a
/// later one), then one to four edits (delete a token, duplicate one, swap
/// two neighbors, insert a token taken from the seed or from a list of
/// keywords and operators, with a space, a newline or nothing around it).
pub const Mutator = struct {
    prng: std.Random.DefaultPrng,
    out: std.ArrayList(u8) = .empty,
    toks: std.ArrayList([2]usize) = .empty,
    piece: std.ArrayList(u8) = .empty,

    pub fn init(seed: u64) Mutator {
        return .{ .prng = .init(seed) };
    }

    pub fn deinit(m: *Mutator, gpa: std.mem.Allocator) void {
        m.out.deinit(gpa);
        m.toks.deinit(gpa);
        m.piece.deinit(gpa);
    }

    /// The seed it picked and a new input made from it, valid until the
    /// next call.
    pub fn next(m: *Mutator, gpa: std.mem.Allocator, seeds: []const Input) !struct { Input, [:0]const u8 } {
        const rand = m.prng.random();
        const s = seeds[rand.uintLessThan(usize, seeds.len)];
        m.piece.clearRetainingCapacity();
        try m.piece.appendSlice(gpa, window(rand, s.src));
        try m.piece.append(gpa, 0);
        const piece = m.piece.items[0 .. m.piece.items.len - 1 :0];
        m.toks.clearRetainingCapacity();
        var tz: std.zig.Tokenizer = .init(piece);
        while (true) {
            const t = tz.next();
            if (t.tag == .eof) break;
            try m.toks.append(gpa, .{ t.loc.start, t.loc.end });
        }
        m.out.clearRetainingCapacity();
        // The gaps between tokens are kept with the token after them.
        var edits = rand.intRangeAtMost(usize, 1, 4);
        var i: usize = 0;
        var gap_start: usize = 0;
        while (i <= m.toks.items.len) : (i += 1) {
            const end = if (i < m.toks.items.len) m.toks.items[i][1] else piece.len;
            const start = if (i < m.toks.items.len) m.toks.items[i][0] else piece.len;
            if (edits > 0 and rand.uintLessThan(usize, m.toks.items.len + 1) < 2) {
                edits -= 1;
                switch (rand.uintLessThan(u8, 4)) {
                    0 => { // delete
                        try m.out.appendSlice(gpa, piece[gap_start..start]);
                        gap_start = end;
                        continue;
                    },
                    1 => try m.out.appendSlice(gpa, piece[start..end]), // duplicate
                    2 => { // insert from the pool or the seed
                        const ins = if (rand.boolean() or m.toks.items.len == 0) pool[rand.uintLessThan(usize, pool.len)] else blk: {
                            const t = m.toks.items[rand.uintLessThan(usize, m.toks.items.len)];
                            break :blk piece[t[0]..t[1]];
                        };
                        try m.out.appendSlice(gpa, switch (rand.uintLessThan(u8, 3)) {
                            0 => "",
                            1 => " ",
                            else => "\n",
                        });
                        try m.out.appendSlice(gpa, ins);
                        try m.out.appendSlice(gpa, switch (rand.uintLessThan(u8, 3)) {
                            0 => "",
                            1 => " ",
                            else => "\n",
                        });
                    },
                    else => if (i + 1 < m.toks.items.len) { // swap with the next token
                        const nx = m.toks.items[i + 1];
                        try m.out.appendSlice(gpa, piece[gap_start..start]);
                        try m.out.appendSlice(gpa, piece[nx[0]..nx[1]]);
                        try m.out.appendSlice(gpa, piece[end..nx[0]]);
                        try m.out.appendSlice(gpa, piece[start..end]);
                        gap_start = nx[1];
                        i += 1;
                        continue;
                    },
                }
            }
            try m.out.appendSlice(gpa, piece[gap_start..end]);
            gap_start = end;
        }
        try m.out.append(gpa, 0);
        const src = m.out.items[0 .. m.out.items.len - 1 :0];
        return .{ s, src };
    }
};

const pool = [_][]const u8{
    "const",   "var",       "fn",       "pub",         "comptime", "inline",   "extern",      "export",    "test",   "struct",   "enum",
    "union",   "error",     "if",       "else",        "while",    "for",      "switch",      "return",    "break",  "continue", "try",
    "catch",   "orelse",    "and",      "or",          "defer",    "errdefer", "suspend",     "nosuspend", "resume", "asm",      "volatile",
    "align",   "addrspace", "callconv", "linksection", "anytype",  "noalias",  "threadlocal", "packed",    "opaque", "anyframe", "unreachable",
    "x",       "blk",       "c",        "_",           "0",        "1",        "'a'",         "\"s\"",     "@f",     "///d\n",   "//!d\n",
    "\\\\l\n", "(",         ")",        "[",           "]",        "{",        "}",           ".",         ",",      ";",        ":",
    "?",       "!",         "*",        "**",          "&",        "&&",       "|",           "||",        "-",      "-%",       "+",
    "~",       "=",         "==",       "=>",          "->",       "..",       "...",         ".*",        ".?",     "<",        ">",
    "<<",      "%",         "/",        "^",           "+=",       "[*",       "[*c]",        "[*]",       "[]",     "[_]",      ".{",
    "x:",      ":x",        "|x|",      "|*x|",        "|x, y|",
};

/// A seed of up to 4 KB whole; of a bigger one, the lines from a random
/// line that starts in column 1 up to one of the next few such lines.
fn window(rand: std.Random, src: []const u8) []const u8 {
    if (src.len <= 4096) return src;
    var starts: [8]usize = undefined;
    var count: usize = 0;
    var pos = rand.uintLessThan(usize, src.len);
    while (count < starts.len) {
        const nl = std.mem.findScalarPos(u8, src, pos, '\n') orelse break;
        pos = nl + 1;
        if (pos < src.len and src[pos] != ' ' and src[pos] != '\n' and src[pos] != '}') {
            starts[count] = pos;
            count += 1;
        }
    }
    if (count < 2) return src[0..4096];
    return src[starts[0]..starts[rand.intRangeAtMost(usize, 1, count - 1)]];
}
