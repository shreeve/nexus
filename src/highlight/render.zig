//! render.zig: patterns as regular expressions of other engines.
//!
//! The editor files and `--describe` write Nexus patterns (lexgen/regex.zig)
//! as regular expressions in four dialects:
//!
//!   bytes        a portable PCRE-style subset over bytes: `(?:…)`, classes
//!                with `\xHH`, `{m,n}`, lookarounds (`--describe`)
//!   oniguruma    TextMate grammars (VS Code's engine)
//!   javascript   highlight.js definitions and VS Code language
//!                configurations
//!   vim          Vim syntax files, very magic (`\v`)
//!
//! The three editor dialects match characters, not bytes, within a line:
//! a UTF-8 sequence written as bytes is its character, a class that holds
//! every byte from 0x80 holds every non-ASCII character, and no class
//! matches a line break (`.` neither). A pattern that matches part of a
//! UTF-8 character (a class with some but not all of 0x80-0xFF, a lone
//! byte above 0x7F) has no editor form: `checkEditor` names the problem.

const std = @import("std");
const regex = @import("../lexgen/regex.zig");
const Node = regex.Node;
const ByteSet = regex.ByteSet;
const Writer = std.Io.Writer;

pub const Dialect = enum {
    bytes,
    oniguruma,
    javascript,
    vim,

    fn chars(self: Dialect) bool {
        return self != .bytes;
    }
};

/// A regular expression to render: a pattern, a literal, or a sequence or
/// alternation of them.
pub const Rx = union(enum) {
    node: *const Node,
    literal: Literal,
    seq: []const Rx,
    alt: []const Rx,
};

/// A literal word of a highlight target: `bytes[0..n]` for
/// `min <= n <= bytes.len` (a `@keywords` abbreviation; `min == bytes.len`
/// for one word), ASCII letters in either case when `caseless`. When
/// `bounded`, an end that is a word character ([0-9A-Za-z_]) may not touch
/// another word character.
pub const Literal = struct {
    bytes: []const u8,
    min: usize,
    caseless: bool = false,
    bounded: bool = false,
};

pub const Look = enum {
    after,
    not_after,
    before,
    not_before,

    pub fn name(self: Look) []const u8 {
        return switch (self) {
            .after => "after",
            .not_after => "not after",
            .before => "before",
            .not_before => "not before",
        };
    }
};

pub const Error = error{ WriteFailed, Unrenderable };

pub const Renderer = struct {
    w: *Writer,
    dialect: Dialect,
    /// Why the last `error.Unrenderable` was returned.
    problem: []const u8 = "",

    pub fn rx(self: *Renderer, r: Rx) Error!void {
        return self.rxAt(r, .alt);
    }

    /// `^`: the start of a line.
    pub fn lineStart(self: *Renderer) Error!void {
        try self.w.writeByte('^');
    }

    /// `$`: the end of a line.
    pub fn lineEnd(self: *Renderer) Error!void {
        try self.w.writeByte('$');
    }

    /// A lookaround of `node` (`after`: what follows the match, `before`:
    /// what precedes it).
    pub fn look(self: *Renderer, kind: Look, node: *const Node) Error!void {
        if (self.dialect == .vim) {
            try self.w.writeAll("%(");
            try self.nodeAt(node, .alt);
            try self.w.writeAll(switch (kind) {
                .after => ")@=",
                .not_after => ")@!",
                .before => ")@<=",
                .not_before => ")@<!",
            });
            return;
        }
        try self.w.writeAll(switch (kind) {
            .after => "(?=",
            .not_after => "(?!",
            .before => "(?<=",
            .not_before => "(?<!",
        });
        try self.nodeAt(node, .alt);
        try self.w.writeByte(')');
    }

    /// A capturing group around `r` (not in the vim dialect).
    pub fn capture(self: *Renderer, r: Rx) Error!void {
        std.debug.assert(self.dialect != .vim);
        try self.w.writeByte('(');
        try self.rxAt(r, .alt);
        try self.w.writeByte(')');
    }

    /// Where an expression is written: anywhere (`alt`), as an element of
    /// a sequence (`seq`: an alternation is grouped), or under a quantifier
    /// (`atom`: a sequence is grouped too).
    const Prec = enum { alt, seq, atom };

    fn open(self: *Renderer) Error!void {
        try self.w.writeAll(if (self.dialect == .vim) "%(" else "(?:");
    }

    fn rxAt(self: *Renderer, r: Rx, prec: Prec) Error!void {
        switch (r) {
            .node => |n| try self.nodeAt(n, prec),
            .literal => |l| try self.literal(l, prec),
            .seq => |items| {
                const group = prec == .atom and items.len > 1;
                if (group) try self.open();
                for (items) |item| try self.rxAt(item, .seq);
                if (group) try self.w.writeByte(')');
            },
            .alt => |items| {
                const group = prec != .alt and items.len > 1;
                if (group) try self.open();
                for (items, 0..) |item, i| {
                    if (i > 0) try self.w.writeByte('|');
                    try self.rxAt(item, .seq);
                }
                if (group) try self.w.writeByte(')');
            },
        }
    }

    fn literal(self: *Renderer, l: Literal, prec: Prec) Error!void {
        const before = l.bounded and isWordByte(l.bytes[0]);
        const after = l.bounded and isWordByte(l.bytes[l.bytes.len - 1]);
        const parts = @as(usize, @intFromBool(before)) + @intFromBool(after) + l.bytes.len;
        const group = prec == .atom and parts > 1;
        if (group) try self.open();
        if (before) try self.wordLook(.not_before);
        try self.bytes(l.bytes[0..l.min], l.caseless);
        // `H[ANG]`: H(?:A(?:N(?:G)?)?)?
        for (l.bytes[l.min..]) |b| {
            try self.open();
            try self.bytes(&.{b}, l.caseless);
        }
        for (l.bytes[l.min..]) |_| try self.w.writeAll(if (self.dialect == .vim) ")=" else ")?");
        if (after) try self.wordLook(.not_after);
        if (group) try self.w.writeByte(')');
    }

    /// A word character may not precede (`not_before`) or follow the match.
    fn wordLook(self: *Renderer, kind: Look) Error!void {
        if (self.dialect == .vim) return self.w.writeAll(if (kind == .not_before) "\\w@<!" else "\\w@!");
        try self.w.writeAll(if (kind == .not_before) "(?<![0-9A-Za-z_])" else "(?![0-9A-Za-z_])");
    }

    fn nodeAt(self: *Renderer, n: *const Node, prec: Prec) Error!void {
        switch (n.*) {
            .empty => if (prec == .atom) {
                try self.open();
                try self.w.writeByte(')');
            },
            .set => |s| try self.set(s),
            .concat => |kids| {
                const group = prec == .atom;
                if (group) try self.open();
                var i: usize = 0;
                while (i < kids.len) {
                    // One-byte sets are literal text; a UTF-8 sequence
                    // spans several.
                    const b = only(kids[i]) orelse {
                        try self.nodeAt(kids[i], .seq);
                        i += 1;
                        continue;
                    };
                    var seq: [4]u8 = .{ b, 0, 0, 0 };
                    var len: usize = 1;
                    if (b >= 0x80 and self.dialect.chars()) {
                        const want = std.unicode.utf8ByteSequenceLength(b) catch 1;
                        while (len < want and i + len < kids.len) : (len += 1) seq[len] = only(kids[i + len]) orelse break;
                    }
                    try self.bytes(seq[0..len], false);
                    i += len;
                }
                if (group) try self.w.writeByte(')');
            },
            .alt => |kids| {
                const group = prec != .alt;
                if (group) try self.open();
                for (kids, 0..) |k, i| {
                    if (i > 0) try self.w.writeByte('|');
                    try self.nodeAt(k, .seq);
                }
                if (group) try self.w.writeByte(')');
            },
            .repeat => |r| {
                try self.nodeAt(r.sub, .atom);
                const optional = if (self.dialect == .vim) "=" else "?";
                if (r.max) |max| {
                    if (r.min == 0 and max == 1) {
                        try self.w.writeAll(optional);
                    } else if (r.min == max) {
                        try self.w.print("{{{d}}}", .{max});
                    } else {
                        try self.w.print("{{{d},{d}}}", .{ r.min, max });
                    }
                } else switch (r.min) {
                    0 => try self.w.writeByte('*'),
                    1 => try self.w.writeByte('+'),
                    else => try self.w.print("{{{d},}}", .{r.min}),
                }
            },
        }
    }

    /// Literal text: ASCII characters escaped, UTF-8 sequences as their
    /// characters (editor dialects) or `\xHH` (bytes).
    fn bytes(self: *Renderer, text: []const u8, caseless: bool) Error!void {
        var i: usize = 0;
        while (i < text.len) {
            const b = text[i];
            if (b < 0x80) {
                if (caseless and std.ascii.isAlphabetic(b)) {
                    try self.w.print("[{c}{c}]", .{ std.ascii.toUpper(b), std.ascii.toLower(b) });
                } else try self.char(b);
                i += 1;
                continue;
            }
            if (!self.dialect.chars()) {
                try self.w.print("\\x{x:0>2}", .{b});
                i += 1;
                continue;
            }
            const n = std.unicode.utf8ByteSequenceLength(b) catch return self.fail("a byte above 0x7F that starts no UTF-8 character");
            if (i + n > text.len or !std.unicode.utf8ValidateSlice(text[i..][0..n]))
                return self.fail("bytes that are not a whole UTF-8 character");
            try self.w.writeAll(text[i..][0..n]);
            i += n;
        }
    }

    /// One ASCII character outside a class.
    fn char(self: *Renderer, b: u8) Error!void {
        if (self.dialect == .vim) {
            if (std.ascii.isAlphanumeric(b) or b == '_' or b == ' ') return self.w.writeByte(b);
            if (b < 0x20 or b == 0x7f) return self.w.print("%x{x:0>2}", .{b});
            return self.w.print("\\{c}", .{b});
        }
        if (b < 0x20 or b == 0x7f) return self.w.print("\\x{x:0>2}", .{b});
        if (std.mem.findScalar(u8, "\\^$.|?*+()[]{}", b) != null) try self.w.writeByte('\\');
        try self.w.writeByte(b);
    }

    /// A byte set: one character, `.`, or a class.
    fn set(self: *Renderer, s: ByteSet) Error!void {
        if (!self.dialect.chars()) {
            if (s.only()) |b| return self.bytes(&.{b}, false);
            if (s.count() == 256) return self.w.writeAll("[\\x00-\\xff]");
            const negate = s.count() > 128;
            return self.class(if (negate) s.invert() else s, negate);
        }
        const high = ByteSet.intersect(s, ByteSet.range(0x80, 0xff));
        var ascii = ByteSet.intersect(s, ByteSet.range(0, 0x7f));
        if (high.count() != 0 and high.count() != 0x80)
            return self.fail("a class that holds some but not all bytes from 0x80, which are parts of UTF-8 characters");
        // Editor patterns match within a line.
        ascii.bits[0] &= ~(@as(u64, 1) << '\n');
        if (high.count() == 0) {
            if (ascii.isEmpty()) return self.char('\n');
            if (ascii.only()) |b| return self.char(b);
            return self.class(ascii, false);
        }
        const missing = ByteSet.intersect(ascii.invert(), ByteSet.range(0, 0x7f));
        if (missing.only() == '\n') return self.w.writeByte('.');
        return self.class(missing, true);
    }

    fn class(self: *Renderer, s: ByteSet, negate: bool) Error!void {
        try self.w.writeAll(if (negate) "[^" else "[");
        var lo: u16 = 0;
        while (lo < 256) {
            if (!s.has(@intCast(lo))) {
                lo += 1;
                continue;
            }
            var hi = lo;
            while (hi + 1 < 256 and s.has(@intCast(hi + 1))) hi += 1;
            try self.classChar(@intCast(lo));
            if (hi == lo + 1) {
                try self.classChar(@intCast(hi));
            } else if (hi > lo + 1) {
                try self.w.writeByte('-');
                try self.classChar(@intCast(hi));
            }
            lo = hi + 1;
        }
        try self.w.writeByte(']');
    }

    fn classChar(self: *Renderer, b: u8) Error!void {
        if (b < 0x20 or b >= 0x7f) return self.w.print("\\x{x:0>2}", .{b});
        if (self.dialect == .vim) {
            // `[` could open `[:name:]`; `"` closes a syntax file's pattern.
            if (b == '[' or b == '"') return self.w.print("\\x{x:0>2}", .{b});
            if (std.mem.findScalar(u8, "\\]^-", b) != null) try self.w.writeByte('\\');
            return self.w.writeByte(b);
        }
        if (std.mem.findScalar(u8, "\\]^-[", b) != null) try self.w.writeByte('\\');
        try self.w.writeByte(b);
    }

    fn fail(self: *Renderer, problem: []const u8) Error {
        self.problem = problem;
        return error.Unrenderable;
    }
};

/// The byte of a one-byte set.
fn only(n: *const Node) ?u8 {
    return if (n.* == .set) n.set.only() else null;
}

pub fn isWordByte(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_';
}

/// Why `r` has no editor form, or null when it has one.
pub fn checkEditor(r: Rx) ?[]const u8 {
    var buf: [256]u8 = undefined;
    var discard: Writer.Discarding = .init(&buf);
    var renderer: Renderer = .{ .w = &discard.writer, .dialect = .oniguruma };
    renderer.rx(r) catch |err| return switch (err) {
        error.Unrenderable => renderer.problem,
        error.WriteFailed => unreachable,
    };
    return null;
}

/// The length range of `n`'s matches in characters (a UTF-8 sequence
/// written as bytes, and a class, are one character); max null when
/// unbounded.
pub const Len = struct { min: u32, max: ?u32 };

pub fn charLen(n: *const Node) Len {
    return switch (n.*) {
        .empty => .{ .min = 0, .max = 0 },
        .set => .{ .min = 1, .max = 1 },
        .concat => |kids| blk: {
            var total: Len = .{ .min = 0, .max = 0 };
            var i: usize = 0;
            while (i < kids.len) {
                var step: usize = 1;
                if (only(kids[i])) |b| if (b >= 0xc0) {
                    const len = std.unicode.utf8ByteSequenceLength(b) catch 1;
                    if (i + len <= kids.len) {
                        step = len;
                        for (kids[i + 1 ..][0 .. len - 1]) |k| if (only(k) == null) {
                            step = 1;
                        };
                    }
                };
                const l: Len = if (step > 1) .{ .min = 1, .max = 1 } else charLen(kids[i]);
                total.min +|= l.min;
                total.max = if (total.max != null and l.max != null) total.max.? +| l.max.? else null;
                i += step;
            }
            break :blk total;
        },
        .alt => |kids| blk: {
            var r: Len = .{ .min = std.math.maxInt(u32), .max = 0 };
            for (kids) |k| {
                const l = charLen(k);
                r.min = @min(r.min, l.min);
                r.max = if (r.max != null and l.max != null) @max(r.max.?, l.max.?) else null;
            }
            break :blk r;
        },
        .repeat => |rep| blk: {
            const l = charLen(rep.sub);
            break :blk .{
                .min = rep.min *| l.min,
                .max = if (rep.max != null and l.max != null) rep.max.? *| l.max.? else null,
            };
        },
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn expectRender(pattern: []const u8, dialect: Dialect, want: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: regex.Diagnostic = .{};
    const p = try regex.parse(arena.allocator(), pattern, &d);
    var out: Writer.Allocating = .init(arena.allocator());
    var r: Renderer = .{ .w = &out.writer, .dialect = dialect };
    try r.rx(.{ .node = p.main });
    try testing.expectEqualStrings(want, out.written());
}

test "render: patterns in each dialect" {
    try expectRender("'\"' ([^\"\\\\\\n] | '\\\\' .)* '\"'", .oniguruma, "\"(?:[^\\x0a\"\\\\]|\\\\.)*\"");
    try expectRender("'\"' ([^\"\\\\\\n] | '\\\\' .)* '\"'", .bytes, "\"(?:[^\\x0a\"\\\\]|\\\\[\\x00-\\xff])*\"");
    try expectRender("'\"' ([^\"\\\\\\n] | '\\\\' .)* '\"'", .vim, "\\\"%([^\\x0a\\x22\\\\]|\\\\.)*\\\"");
    try expectRender("[0-9]{2,3} 'a'? 'b'{2,}", .javascript, "[0-9]{2,3}a?b{2,}");
    try expectRender("[0-9]{2,3} 'a'? 'b'{2,}", .vim, "[0-9]{2,3}a=b{2,}");
    try expectRender("\"\\xe2\\x86\\x92\"+", .oniguruma, "(?:\u{2192})+");
    try expectRender("\"\\xe2\\x86\\x92\"", .bytes, "\\xe2\\x86\\x92");
    try expectRender("[ \\t\\n]+", .oniguruma, "[\\x09 ]+");
    try expectRender("'.' | '[' | '\\t'", .vim, "\\.|\\[|%x09");
}

test "render: editor dialects reject parts of UTF-8 characters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: regex.Diagnostic = .{};
    for ([_][]const u8{ "[\\x80-\\x9f]", "'\\xe2'", "\"\\xe2\\x86\"" }) |pattern| {
        const p = try regex.parse(arena.allocator(), pattern, &d);
        try testing.expect(checkEditor(.{ .node = p.main }) != null);
    }
    const ok = try regex.parse(arena.allocator(), "[^a] \"\\xc3\\xa9\"", &d);
    try testing.expect(checkEditor(.{ .node = ok.main }) == null);
}

test "render: literals with boundaries and abbreviations" {
    var buf: [128]u8 = undefined;
    var w: Writer = .fixed(&buf);
    var r: Renderer = .{ .w = &w, .dialect = .oniguruma };
    try r.rx(.{ .literal = .{ .bytes = "HANG", .min = 1, .caseless = true, .bounded = true } });
    try testing.expectEqualStrings("(?<![0-9A-Za-z_])[Hh](?:[Aa](?:[Nn](?:[Gg])?)?)?(?![0-9A-Za-z_])", w.buffered());
}

test "render: character lengths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: regex.Diagnostic = .{};
    const p = try regex.parse(arena.allocator(), "\"\\xc3\\xa9\" | 'ab'", &d);
    try testing.expectEqual(Len{ .min = 1, .max = 2 }, charLen(p.main));
    const q = try regex.parse(arena.allocator(), "'a' [b-c]{2}", &d);
    try testing.expectEqual(Len{ .min = 3, .max = 3 }, charLen(q.main));
}
