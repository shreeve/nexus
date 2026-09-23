//! Lexer pattern language: parser and AST.
//!
//! A lexer rule's pattern is a regular expression over bytes:
//!
//!   'abc'  "abc"      literal bytes (escapes: \n \r \t \0 \\ \' \" \xHH)
//!   [a-z_] [^"\n]     byte class; ranges, negation, escapes, \d \w \s
//!   .                 any byte (including newline)
//!   \n \d \w ...      a bare escape is a one-byte atom (or class)
//!   ( r )             grouping; ( ) is the empty string
//!   r1 r2             concatenation (atoms are separated by whitespace or
//!                     simply juxtaposed)
//!   r1 | r2           alternation
//!   r* r+ r?          repetition
//!   r{n} r{n,} r{n,m} bounded repetition
//!   r1 / r2           trailing context (top level only): match r1 only when
//!                     r2 follows; r2 is not part of the token
//!
//! Anything outside this language is a located error; nothing is skipped.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Largest bound accepted in `r{n,m}`; keeps the expanded automaton small.
pub const maxRepeat: u32 = 255;

/// A set of bytes.
pub const ByteSet = struct {
    bits: [4]u64 = .{ 0, 0, 0, 0 },

    pub const empty: ByteSet = .{};
    pub const full: ByteSet = .{ .bits = .{ ~@as(u64, 0), ~@as(u64, 0), ~@as(u64, 0), ~@as(u64, 0) } };

    pub fn single(b: u8) ByteSet {
        var s: ByteSet = .{};
        s.add(b);
        return s;
    }

    pub fn range(lo: u8, hi: u8) ByteSet {
        var s: ByteSet = .{};
        s.addRange(lo, hi);
        return s;
    }

    pub fn add(self: *ByteSet, b: u8) void {
        self.bits[b >> 6] |= @as(u64, 1) << @intCast(b & 63);
    }

    pub fn addRange(self: *ByteSet, lo: u8, hi: u8) void {
        var c: u16 = lo;
        while (c <= hi) : (c += 1) self.add(@intCast(c));
    }

    pub fn has(self: ByteSet, b: u8) bool {
        return (self.bits[b >> 6] >> @intCast(b & 63)) & 1 != 0;
    }

    pub fn merge(self: *ByteSet, other: ByteSet) void {
        for (&self.bits, other.bits) |*a, b| a.* |= b;
    }

    pub fn intersect(a: ByteSet, b: ByteSet) ByteSet {
        var r: ByteSet = .{};
        for (&r.bits, a.bits, b.bits) |*x, y, z| x.* = y & z;
        return r;
    }

    pub fn invert(self: ByteSet) ByteSet {
        var r: ByteSet = .{};
        for (&r.bits, self.bits) |*x, y| x.* = ~y;
        return r;
    }

    pub fn count(self: ByteSet) u32 {
        var n: u32 = 0;
        for (self.bits) |w| n += @popCount(w);
        return n;
    }

    pub fn isEmpty(self: ByteSet) bool {
        return self.count() == 0;
    }

    pub fn eql(a: ByteSet, b: ByteSet) bool {
        return std.mem.eql(u64, &a.bits, &b.bits);
    }

    /// The only byte of a one-byte set.
    pub fn only(self: ByteSet) ?u8 {
        if (self.count() != 1) return null;
        for (self.bits, 0..) |w, i| {
            if (w != 0) return @intCast(i * 64 + @ctz(w));
        }
        return null;
    }

    pub fn subsetOf(a: ByteSet, b: ByteSet) bool {
        for (a.bits, b.bits) |x, y| {
            if (x & ~y != 0) return false;
        }
        return true;
    }
};

pub const Node = union(enum) {
    /// The empty string.
    empty,
    /// One byte from the set.
    set: ByteSet,
    concat: []const *const Node,
    alt: []const *const Node,
    repeat: Repeat,

    pub const Repeat = struct {
        sub: *const Node,
        min: u32,
        /// null = unbounded.
        max: ?u32,
    };
};

/// A parsed lexer pattern: `main` is the token; `trail` (from `r1 / r2`) is
/// context that must follow but is not consumed.
pub const Pattern = struct {
    main: *const Node,
    trail: ?*const Node = null,

    /// The whole text the automaton must match (main followed by trail).
    pub fn full(self: Pattern, arena: Allocator) !*const Node {
        const t = self.trail orelse return self.main;
        const kids = try arena.alloc(*const Node, 2);
        kids[0] = self.main;
        kids[1] = t;
        const n = try arena.create(Node);
        n.* = .{ .concat = kids };
        return n;
    }
};

/// A located pattern error: `offset` is a byte offset into the pattern text.
pub const Diagnostic = struct {
    offset: usize = 0,
    message: []const u8 = "",
};

pub const ParseError = error{ InvalidPattern, OutOfMemory };

/// Parse `text` into a Pattern. On error, `diag` holds the offset and message.
pub fn parse(arena: Allocator, text: []const u8, diag: *Diagnostic) ParseError!Pattern {
    var p: Parser = .{ .arena = arena, .text = text, .diag = diag };
    return p.parsePattern();
}

const Parser = struct {
    arena: Allocator,
    text: []const u8,
    pos: usize = 0,
    diag: *Diagnostic,

    fn fail(self: *Parser, offset: usize, message: []const u8) ParseError {
        self.diag.* = .{ .offset = offset, .message = message };
        return error.InvalidPattern;
    }

    fn skipSpace(self: *Parser) void {
        while (self.pos < self.text.len and (self.text[self.pos] == ' ' or self.text[self.pos] == '\t')) self.pos += 1;
    }

    fn peek(self: *Parser) ?u8 {
        return if (self.pos < self.text.len) self.text[self.pos] else null;
    }

    fn node(self: *Parser, n: Node) ParseError!*const Node {
        const p = try self.arena.create(Node);
        p.* = n;
        return p;
    }

    fn parsePattern(self: *Parser) ParseError!Pattern {
        const main = try self.parseAlt(0);
        self.skipSpace();
        var trail: ?*const Node = null;
        if (self.peek() == '/') {
            const slash = self.pos;
            self.pos += 1;
            trail = try self.parseAlt(0);
            self.skipSpace();
            if (self.peek() == '/') return self.fail(self.pos, "a pattern may contain only one trailing-context '/'");
            if (nullable(trail.?)) return self.fail(slash, "trailing context after '/' must not match the empty string");
        }
        if (self.pos < self.text.len) {
            const c = self.text[self.pos];
            if (c == ')') return self.fail(self.pos, "unbalanced ')'");
            return self.fail(self.pos, "unexpected character in pattern");
        }
        return .{ .main = main, .trail = trail };
    }

    fn parseAlt(self: *Parser, depth: u32) ParseError!*const Node {
        var branches: std.ArrayListUnmanaged(*const Node) = .empty;
        try branches.append(self.arena, try self.parseSeq(depth));
        while (true) {
            self.skipSpace();
            if (self.peek() != '|') break;
            self.pos += 1;
            try branches.append(self.arena, try self.parseSeq(depth));
        }
        if (branches.items.len == 1) return branches.items[0];
        return self.node(.{ .alt = try branches.toOwnedSlice(self.arena) });
    }

    fn parseSeq(self: *Parser, depth: u32) ParseError!*const Node {
        var items: std.ArrayListUnmanaged(*const Node) = .empty;
        while (true) {
            self.skipSpace();
            const c = self.peek() orelse break;
            if (c == '|' or c == ')' or c == '/') break;
            try items.append(self.arena, try self.parsePostfix(depth));
        }
        return switch (items.items.len) {
            0 => self.node(.empty),
            1 => items.items[0],
            else => self.node(.{ .concat = try items.toOwnedSlice(self.arena) }),
        };
    }

    fn parsePostfix(self: *Parser, depth: u32) ParseError!*const Node {
        var n = try self.parseAtom(depth);
        var quantified = false;
        while (self.pos < self.text.len) {
            const c = self.text[self.pos];
            if (c != '*' and c != '+' and c != '?' and c != '{') break;
            if (quantified) return self.fail(self.pos, "a quantifier cannot follow another quantifier; group the operand with ( )");
            if (n.* == .empty) return self.fail(self.pos, "quantifier applied to an empty pattern");
            quantified = true;
            var min: u32 = 0;
            var max: ?u32 = null;
            switch (c) {
                '*' => self.pos += 1,
                '+' => {
                    min = 1;
                    self.pos += 1;
                },
                '?' => {
                    max = 1;
                    self.pos += 1;
                },
                '{' => {
                    const open = self.pos;
                    self.pos += 1;
                    min = try self.parseCount(open);
                    if (self.peek() == ',') {
                        self.pos += 1;
                        if (self.peek() == '}') {
                            max = null;
                        } else {
                            max = try self.parseCount(open);
                        }
                    } else {
                        max = min;
                    }
                    if (self.peek() != '}') return self.fail(self.pos, "expected '}' to close the repeat count");
                    self.pos += 1;
                    if (max) |m| {
                        if (m < min) return self.fail(open, "repeat bound {n,m} requires n <= m");
                        if (m == 0) return self.fail(open, "repeat bound {0} matches nothing useful; remove the element");
                    }
                },
                else => unreachable,
            }
            n = try self.node(.{ .repeat = .{ .sub = n, .min = min, .max = max } });
        }
        return n;
    }

    fn parseCount(self: *Parser, open: usize) ParseError!u32 {
        const start = self.pos;
        while (self.pos < self.text.len and std.ascii.isDigit(self.text[self.pos])) self.pos += 1;
        if (self.pos == start) return self.fail(self.pos, "expected a number in the repeat count");
        const v = std.fmt.parseInt(u32, self.text[start..self.pos], 10) catch
            return self.fail(start, "repeat count is too large");
        if (v > maxRepeat) return self.fail(open, "repeat count exceeds 255");
        return v;
    }

    fn parseAtom(self: *Parser, depth: u32) ParseError!*const Node {
        const c = self.text[self.pos];
        switch (c) {
            '\'', '"' => return self.parseQuoted(),
            '[' => return self.node(.{ .set = try self.parseClass() }),
            '.' => {
                self.pos += 1;
                return self.node(.{ .set = ByteSet.full });
            },
            '(' => {
                const open = self.pos;
                self.pos += 1;
                if (depth > 64) return self.fail(open, "groups nested too deeply");
                const inner = try self.parseAlt(depth + 1);
                self.skipSpace();
                if (self.peek() == '/') return self.fail(self.pos, "trailing-context '/' is only allowed at the top level of a pattern");
                if (self.peek() != ')') return self.fail(open, "unclosed '('");
                self.pos += 1;
                return inner;
            },
            '\\' => {
                const start = self.pos;
                self.pos += 1;
                if (self.pos >= self.text.len) return self.fail(start, "pattern ends with a lone backslash");
                if (classEscape(self.text[self.pos])) |set| {
                    self.pos += 1;
                    return self.node(.{ .set = set });
                }
                const b = try self.parseEscape(start, .bare);
                return self.node(.{ .set = ByteSet.single(b) });
            },
            '*', '+', '?', '{' => return self.fail(self.pos, "quantifier with nothing to repeat"),
            ']' => return self.fail(self.pos, "unbalanced ']'"),
            '}' => return self.fail(self.pos, "unbalanced '}'"),
            else => {
                if (std.ascii.isAlphabetic(c) or c == '_') {
                    const start = self.pos;
                    var end = self.pos;
                    while (end < self.text.len and (std.ascii.isAlphanumeric(self.text[end]) or self.text[end] == '_')) end += 1;
                    const word = self.text[start..end];
                    if (std.mem.eql(u8, word, "counting") or std.mem.eql(u8, word, "matching")) {
                        return self.fail(start, "counting()/matching() describe balanced nesting, which no finite automaton can recognize; use trailing context '/' for bounded lookahead or handle nesting in the lang Lexer wrapper");
                    }
                    return self.fail(start, "bare word in pattern; quote literal text as 'x' or \"x\"");
                }
                return self.fail(self.pos, "unexpected character in pattern; quote literal text as 'x' or \"x\"");
            },
        }
    }

    const EscapeContext = enum { quoted, class, bare };

    /// Decode one escape at self.pos (just past the backslash).
    fn parseEscape(self: *Parser, backslash: usize, ctx: EscapeContext) ParseError!u8 {
        const e = self.text[self.pos];
        self.pos += 1;
        switch (e) {
            'n' => return '\n',
            'r' => return '\r',
            't' => return '\t',
            '0' => return 0,
            '\\', '\'', '"' => return e,
            'x' => {
                if (self.pos + 2 > self.text.len) return self.fail(backslash, "\\x needs two hex digits");
                const v = std.fmt.parseInt(u8, self.text[self.pos..][0..2], 16) catch
                    return self.fail(backslash, "\\x needs two hex digits");
                self.pos += 2;
                return v;
            },
            else => {},
        }
        switch (ctx) {
            .class => switch (e) {
                ']', '[', '^', '-' => return e,
                else => {},
            },
            .bare => switch (e) {
                '.', '(', ')', '[', ']', '{', '}', '|', '*', '+', '?', '/', '@', ' ' => return e,
                else => {},
            },
            .quoted => {},
        }
        return self.fail(backslash, "unknown escape sequence");
    }

    fn parseQuoted(self: *Parser) ParseError!*const Node {
        const open = self.pos;
        const delim = self.text[self.pos];
        self.pos += 1;
        var bytes: std.ArrayListUnmanaged(u8) = .empty;
        while (true) {
            if (self.pos >= self.text.len) return self.fail(open, "unterminated quoted literal");
            const c = self.text[self.pos];
            if (c == delim) {
                self.pos += 1;
                break;
            }
            if (c == '\\') {
                const bs = self.pos;
                self.pos += 1;
                if (self.pos >= self.text.len) return self.fail(open, "unterminated quoted literal");
                try bytes.append(self.arena, try self.parseEscape(bs, .quoted));
                continue;
            }
            if (c == '\n') return self.fail(open, "unterminated quoted literal");
            try bytes.append(self.arena, c);
            self.pos += 1;
        }
        if (bytes.items.len == 0) return self.fail(open, "empty literal; use ( ) for the empty string");
        return self.literalNode(bytes.items);
    }

    fn literalNode(self: *Parser, bytes: []const u8) ParseError!*const Node {
        if (bytes.len == 1) return self.node(.{ .set = ByteSet.single(bytes[0]) });
        const kids = try self.arena.alloc(*const Node, bytes.len);
        for (bytes, 0..) |b, i| kids[i] = try self.node(.{ .set = ByteSet.single(b) });
        return self.node(.{ .concat = kids });
    }

    fn parseClass(self: *Parser) ParseError!ByteSet {
        const open = self.pos;
        self.pos += 1;
        var negate = false;
        if (self.peek() == '^') {
            negate = true;
            self.pos += 1;
        }
        var set: ByteSet = .{};
        var first = true;
        while (true) {
            if (self.pos >= self.text.len) return self.fail(open, "unclosed '['");
            const c = self.text[self.pos];
            if (c == ']' and !first) {
                self.pos += 1;
                break;
            }
            first = false;
            const itemStart = self.pos;
            var lo: u8 = undefined;
            if (c == '\\') {
                self.pos += 1;
                if (self.pos >= self.text.len) return self.fail(open, "unclosed '['");
                if (classEscape(self.text[self.pos])) |cls| {
                    self.pos += 1;
                    set.merge(cls);
                    continue;
                }
                lo = try self.parseEscape(itemStart, .class);
            } else {
                if (c == '\n') return self.fail(open, "unclosed '['");
                lo = c;
                self.pos += 1;
            }
            // Range `lo-hi` (a '-' right before ']' is literal).
            if (self.pos + 1 < self.text.len and self.text[self.pos] == '-' and self.text[self.pos + 1] != ']') {
                self.pos += 1;
                var hi: u8 = undefined;
                if (self.text[self.pos] == '\\') {
                    const bs = self.pos;
                    self.pos += 1;
                    if (self.pos >= self.text.len) return self.fail(open, "unclosed '['");
                    if (classEscape(self.text[self.pos]) != null) return self.fail(bs, "a class shorthand cannot end a range");
                    hi = try self.parseEscape(bs, .class);
                } else {
                    hi = self.text[self.pos];
                    self.pos += 1;
                }
                if (hi < lo) return self.fail(itemStart, "range is out of order");
                set.addRange(lo, hi);
            } else {
                set.add(lo);
            }
        }
        if (negate) set = set.invert();
        if (set.isEmpty()) return self.fail(open, "character class matches no byte");
        return set;
    }
};

/// `\d \w \s` shorthands (inside or outside classes).
fn classEscape(c: u8) ?ByteSet {
    var s: ByteSet = .{};
    switch (c) {
        'd' => s.addRange('0', '9'),
        'w' => {
            s.addRange('a', 'z');
            s.addRange('A', 'Z');
            s.addRange('0', '9');
            s.add('_');
        },
        's' => {
            s.add(' ');
            s.add('\t');
            s.add('\n');
            s.add('\r');
        },
        else => return null,
    }
    return s;
}

// =============================================================================
// Queries
// =============================================================================

/// True if `n` matches the empty string.
pub fn nullable(n: *const Node) bool {
    return switch (n.*) {
        .empty => true,
        .set => false,
        .concat => |kids| for (kids) |k| {
            if (!nullable(k)) break false;
        } else true,
        .alt => |kids| for (kids) |k| {
            if (nullable(k)) break true;
        } else false,
        .repeat => |r| r.min == 0 or nullable(r.sub),
    };
}

/// Shortest match length.
pub fn minLen(n: *const Node) u32 {
    return switch (n.*) {
        .empty => 0,
        .set => 1,
        .concat => |kids| blk: {
            var t: u32 = 0;
            for (kids) |k| t +|= minLen(k);
            break :blk t;
        },
        .alt => |kids| blk: {
            var m: u32 = std.math.maxInt(u32);
            for (kids) |k| m = @min(m, minLen(k));
            break :blk m;
        },
        .repeat => |r| r.min *| minLen(r.sub),
    };
}

/// Longest match length; null = unbounded.
pub fn maxLen(n: *const Node) ?u32 {
    return switch (n.*) {
        .empty => 0,
        .set => 1,
        .concat => |kids| blk: {
            var t: u32 = 0;
            for (kids) |k| t +|= maxLen(k) orelse break :blk null;
            break :blk t;
        },
        .alt => |kids| blk: {
            var m: u32 = 0;
            for (kids) |k| m = @max(m, maxLen(k) orelse break :blk null);
            break :blk m;
        },
        .repeat => |r| blk: {
            const sub = maxLen(r.sub) orelse break :blk null;
            if (sub == 0) break :blk 0;
            const mx = r.max orelse break :blk null;
            break :blk mx *| sub;
        },
    };
}

/// The fixed match length, if every match has the same length.
pub fn fixedLen(n: *const Node) ?u32 {
    const mx = maxLen(n) orelse return null;
    return if (mx == minLen(n)) mx else null;
}

/// Bytes that can begin a non-empty match.
pub fn firstSet(n: *const Node) ByteSet {
    var s: ByteSet = .{};
    switch (n.*) {
        .empty => {},
        .set => |b| s = b,
        .concat => |kids| for (kids) |k| {
            s.merge(firstSet(k));
            if (!nullable(k)) break;
        },
        .alt => |kids| for (kids) |k| s.merge(firstSet(k)),
        .repeat => |r| s = firstSet(r.sub),
    }
    return s;
}

/// If `n` matches exactly one string, write it to `out` and return it.
pub fn literal(n: *const Node, out: *std.ArrayListUnmanaged(u8), gpa: Allocator) !?[]const u8 {
    out.clearRetainingCapacity();
    if (!try appendLiteral(n, out, gpa)) return null;
    return out.items;
}

fn appendLiteral(n: *const Node, out: *std.ArrayListUnmanaged(u8), gpa: Allocator) !bool {
    switch (n.*) {
        .empty => return true,
        .set => |b| {
            const c = b.only() orelse return false;
            try out.append(gpa, c);
            return true;
        },
        .concat => |kids| {
            for (kids) |k| if (!try appendLiteral(k, out, gpa)) return false;
            return true;
        },
        .alt => return false,
        .repeat => |r| {
            const mx = r.max orelse return false;
            if (mx != r.min) return false;
            var i: u32 = 0;
            while (i < r.min) : (i += 1) if (!try appendLiteral(r.sub, out, gpa)) return false;
            return true;
        },
    }
}

// =============================================================================
// Reference matcher (backtracking), used by the tests as an oracle
// =============================================================================

/// Every end position `e` such that input[start..e] matches `n`, as a bitmask
/// over positions (input.len <= 63).
pub fn matchEnds(n: *const Node, input: []const u8, start: usize) u64 {
    return ends(n, input, @as(u64, 1) << @intCast(start));
}

fn ends(n: *const Node, input: []const u8, from: u64) u64 {
    switch (n.*) {
        .empty => return from,
        .set => |b| {
            var r: u64 = 0;
            var f = from;
            while (f != 0) {
                const p = @ctz(f);
                f &= f - 1;
                if (p < input.len and b.has(input[p])) r |= @as(u64, 1) << @intCast(p + 1);
            }
            return r;
        },
        .concat => |kids| {
            var cur = from;
            for (kids) |k| cur = ends(k, input, cur);
            return cur;
        },
        .alt => |kids| {
            var r: u64 = 0;
            for (kids) |k| r |= ends(k, input, from);
            return r;
        },
        .repeat => |rep| {
            var cur = from;
            var i: u32 = 0;
            while (i < rep.min) : (i += 1) cur = ends(rep.sub, input, cur);
            var result = cur;
            var extra: u32 = 0;
            while (rep.max == null or extra < rep.max.? - rep.min) : (extra += 1) {
                const nxt = ends(rep.sub, input, cur);
                const grown = result | nxt;
                cur = nxt;
                if (grown == result and rep.max == null) break;
                result = grown;
                if (cur == 0) break;
            }
            return result;
        },
    }
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn expectParseError(text: []const u8, offset: usize, needle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: Diagnostic = .{};
    try testing.expectError(error.InvalidPattern, parse(arena.allocator(), text, &d));
    if (std.mem.indexOf(u8, d.message, needle) == null) {
        std.debug.print("message: {s}\n", .{d.message});
        return error.TestUnexpectedResult;
    }
    try testing.expectEqual(offset, d.offset);
}

fn expectMatch(text: []const u8, input: []const u8, expected: []const usize) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: Diagnostic = .{};
    const p = parse(arena.allocator(), text, &d) catch |e| {
        std.debug.print("parse failed at {d}: {s}\n", .{ d.offset, d.message });
        return e;
    };
    const full = try p.full(arena.allocator());
    var mask: u64 = 0;
    for (expected) |e| mask |= @as(u64, 1) << @intCast(e);
    try testing.expectEqual(mask, matchEnds(full, input, 0));
}

test "regex: literals and escapes" {
    try expectMatch("'abc'", "abcd", &.{3});
    try expectMatch("\"a\\nb\"", "a\nb", &.{3});
    try expectMatch("'\\\\' .", "\\\n", &.{2});
    try expectMatch("'\\x41'", "A", &.{1});
    try expectMatch("\"'\"", "'", &.{1});
    try expectMatch("'\"'", "\"", &.{1});
    try expectMatch("\\n", "\n", &.{1});
}

test "regex: classes" {
    try expectMatch("[a-c]+", "abcd", &.{ 1, 2, 3 });
    try expectMatch("[^\"\\n]*", "ab\"", &.{ 0, 1, 2 });
    try expectMatch("[\\w./-]+", "a/b-", &.{ 1, 2, 3, 4 });
    try expectMatch("[A-Za-z_./\\-+~@%!*?:,^]", "^", &.{1});
    try expectMatch("[]a]", "]", &.{1});
    try expectMatch("[a-]", "-", &.{1});
    try expectMatch("[\\d]+", "42x", &.{ 1, 2 });
    try expectMatch(".", "\n", &.{1});
}

test "regex: grouping, alternation, repeats" {
    try expectMatch("'\"' ([^\"\\n] | '\"\"')* '\"'", "\"a\"\"b\"", &.{ 3, 6 });
    try expectMatch("('+'|'-')? [0-9]+", "-12", &.{ 2, 3 });
    try expectMatch("[0-9]{2,3}", "12345", &.{ 2, 3 });
    try expectMatch("[0-9]{2}", "12345", &.{2});
    try expectMatch("[0-9]{2,}", "1234", &.{ 2, 3, 4 });
    try expectMatch("( )", "x", &.{0});
    try expectMatch("'a' ( | 'b')", "ab", &.{ 1, 2 });
}

test "regex: trailing context" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var d: Diagnostic = .{};
    const p = try parse(arena.allocator(), "'?' / [0-9]+ [A-Z]", &d);
    try testing.expect(p.trail != null);
    try testing.expectEqual(@as(?u32, 1), fixedLen(p.main));
    try testing.expectEqual(@as(?u32, null), fixedLen(p.trail.?));
    try testing.expectEqual(@as(u64, 1 << 4), matchEnds(try p.full(arena.allocator()), "?12A", 0));
}

test "regex: queries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diagnostic = .{};
    const p = try parse(a, "[0-9]* '.' [0-9]+", &d);
    try testing.expectEqual(@as(u32, 2), minLen(p.main));
    try testing.expectEqual(@as(?u32, null), maxLen(p.main));
    const fs = firstSet(p.main);
    try testing.expect(fs.has('.') and fs.has('7') and !fs.has('a'));
    try testing.expect(!nullable(p.main));

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const lit = try parse(a, "\"]]=\"", &d);
    try testing.expectEqualStrings("]]=", (try literal(lit.main, &buf, testing.allocator)).?);
    const lit2 = try parse(a, "'<' '<' [=]", &d);
    try testing.expectEqualStrings("<<=", (try literal(lit2.main, &buf, testing.allocator)).?);
    const notLit = try parse(a, "'<' [=>]", &d);
    try testing.expect((try literal(notLit.main, &buf, testing.allocator)) == null);
}

test "regex: located errors" {
    try expectParseError("'abc", 0, "unterminated");
    try expectParseError("[a-z", 0, "unclosed '['");
    try expectParseError("[z-a]", 1, "out of order");
    try expectParseError("('a'", 0, "unclosed '('");
    try expectParseError("'a')", 3, "unbalanced ')'");
    try expectParseError("*", 0, "nothing to repeat");
    try expectParseError("'a'**", 4, "cannot follow another quantifier");
    try expectParseError("'a'{3,2}", 3, "n <= m");
    try expectParseError("'a'{999}", 3, "exceeds 255");
    try expectParseError("abc", 0, "bare word");
    try expectParseError("'?' counting('(') [0-9]+", 4, "balanced nesting");
    try expectParseError("'a' / 'b' / 'c'", 10, "only one trailing-context");
    try expectParseError("('a' / 'b')", 5, "top level");
    try expectParseError("'a' / 'b'*", 4, "must not match the empty string");
    try expectParseError("'\\q'", 1, "unknown escape");
    try expectParseError("[^\\x00-\\xff]", 0, "matches no byte");
    try expectParseError("''", 0, "empty literal");
}
