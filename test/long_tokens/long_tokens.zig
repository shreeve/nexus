//! @lang module of the long-token grammar: a Lexer wrapper that reads
//! ahead and joins adjacent strings (see the grammar's header), and tests
//! on tokens of 65,534 bytes to 1 MB, built in memory.
const std = @import("std");
const parser = @import("parser.zig");
const Token = parser.Token;
const ir = parser.ir;

/// The `len` of a token over 65534 bytes.
const long = std.math.maxInt(u16);

pub const Lexer = struct {
    base: parser.BaseLexer,
    /// Tokens read from `base` ahead of the one returned: ahead[0..n].
    ahead: [48]Token = undefined,
    n: u8 = 0,
    /// How many tokens stay read ahead: 1, or 40 after a leading `>`.
    depth: u8 = 1,
    /// After a leading `<`: return the first long string again, scanned
    /// with `cut` set.
    rescan: bool = false,

    pub fn init(source: []const u8) Lexer {
        var self: Lexer = .{ .base = parser.BaseLexer.init(source) };
        if (std.mem.startsWith(u8, source, ">")) {
            self.base.pos = 1;
            self.depth = 40;
        } else if (std.mem.startsWith(u8, source, "<")) {
            self.base.pos = 1;
            self.rescan = true;
        }
        return self;
    }

    pub fn next(self: *Lexer) Token {
        var tok = self.take();
        if (self.rescan and tok.cat == .string and tok.len == long) {
            // The same string again, as `cut` scans it: up to its first `|`.
            self.rescan = false;
            self.base.pos = tok.pos;
            self.base.cut = 1;
            self.ahead[0] = self.base.next();
            self.base.cut = 0;
            self.n = 1;
            return tok;
        }
        // Adjacent strings are one string token: `"ab""cd"`.
        while (tok.cat == .string and self.peek().cat == .string and self.peek().pre == 0) {
            const second = self.take();
            const end = second.pos + self.base.text(second).len;
            tok = self.base.token(.string, tok.pre, tok.pos, end);
        }
        return tok;
    }

    /// The next token read ahead, keeping `depth` more read ahead of it.
    fn take(self: *Lexer) Token {
        self.fill();
        const tok = self.ahead[0];
        std.mem.copyForwards(Token, self.ahead[0 .. self.n - 1], self.ahead[1..self.n]);
        self.n -= 1;
        return tok;
    }

    fn peek(self: *Lexer) Token {
        self.fill();
        return self.ahead[0];
    }

    fn fill(self: *Lexer) void {
        while (self.n <= self.depth) : (self.n += 1) self.ahead[self.n] = self.base.next();
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;
const gpa = testing.allocator;

/// Text built from parts: literal text, a run of one byte, or a string
/// `n` bytes long, quotes included (`"aaa…"`, with `|` at `at` for `cut`).
const Part = union(enum) {
    text: []const u8,
    run: struct { u8, usize },
    string: usize,
    cut: struct { len: usize, at: usize },
};

fn build(parts: []const Part) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (parts) |part| switch (part) {
        .text => |t| try out.appendSlice(gpa, t),
        .run => |r| @memset(try out.addManyAsSlice(gpa, r[1]), r[0]),
        .string => |n| {
            @memset(try out.addManyAsSlice(gpa, n), 'a');
            out.items[out.items.len - n] = '"';
            out.items[out.items.len - 1] = '"';
        },
        .cut => |c| {
            const string = try out.addManyAsSlice(gpa, c.len);
            @memset(string, 'a');
            string[0] = '"';
            string[c.len - 1] = '"';
            string[c.at] = '|';
        },
    };
    return out.toOwnedSlice(gpa);
}

const sizes = [_]usize{ 65534, 65535, 65536, 1 << 20 };

/// The `len` of a token `n` bytes long.
fn lenOf(n: usize) u16 {
    return if (n < long) @intCast(n) else long;
}

const panic_var = "LONG_TOKENS_PANIC";

/// What each child process of the first test does: something that would
/// give part of a long token's text, which panics instead.
fn panicking(what: []const u8) !void {
    const source = try build(&.{ .{ .text = "x = " }, .{ .string = 70_000 } });
    defer gpa.free(source);
    var p = parser.Parser.init(gpa, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const leaf = ir.Str.value(ir.Set.value(ir.Program.stmts(tree)[0]));
    if (std.mem.eql(u8, what, "getText")) {
        _ = leaf.getText(source);
    } else if (std.mem.eql(u8, what, "write")) {
        var discard: std.Io.Writer.Discarding = .init(&.{});
        try tree.write(source, &discard.writer);
    } else if (std.mem.eql(u8, what, "makeToken")) {
        _ = parser.BaseLexer.makeToken(.string, 0, 0, 70_000);
    } else if (std.mem.eql(u8, what, "text")) {
        // One more long token than the lexer keeps ends for.
        var parts: [2 * (parser.LongEnds.capacity + 1)]Part = undefined;
        for (0..parser.LongEnds.capacity + 1) |i| parts[2 * i] = .{ .string = 70_000 };
        for (0..parser.LongEnds.capacity + 1) |i| parts[2 * i + 1] = .{ .text = " " };
        const many = try build(&parts);
        defer gpa.free(many);
        var lx = parser.BaseLexer.init(many);
        const first = lx.next();
        for (0..parser.LongEnds.capacity) |_| _ = lx.next();
        _ = lx.text(first);
    } else if (std.mem.eql(u8, what, "leafEnd")) {
        // A leaf no token this parser read gave.
        _ = p.leafEnd(.{ .pos = 1, .len = long, .id = 0 });
    }
}

// First, so that each child process reaches it before any other test.
test "without the ends the parser keeps, helpers panic rather than give part of a text" {
    if (testing.environ.getPosix(panic_var)) |what| {
        try panicking(what);
        return error.DidNotPanic;
    }
    const io = testing.io;
    const exe = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(exe);
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "getText", "Sexp.getText: the leaf of a token over 65534 bytes holds no end (BaseParser.leafText has its text)" },
        .{ "write", "Sexp.write: the leaf of a token over 65534 bytes holds no end" },
        .{ "makeToken", "BaseLexer.makeToken: a token over 65534 bytes needs its end recorded (build it with BaseLexer.token)" },
        .{ "text", "BaseLexer.text: the lexer holds no one end for this token over 65534 bytes (BaseParser.tokenText has it)" },
        .{ "leafEnd", "no token over 65534 bytes this parser read starts here" },
    };
    for (cases) |c| {
        var env = try testing.environ.createMap(gpa);
        defer env.deinit();
        try env.put(panic_var, c[0]);
        const r = try std.process.run(gpa, io, .{ .argv = &.{exe}, .environ_map = &env });
        defer gpa.free(r.stdout);
        defer gpa.free(r.stderr);
        if (r.term != .signal or std.mem.find(u8, r.stderr, c[1]) == null) {
            std.debug.print("{s}: {f}; stderr:\n{s}\n", .{ c[0], r.term, r.stderr });
            return error.TestUnexpectedResult;
        }
    }
}

test "the lexer keeps a long token's category and records its end" {
    for (sizes) |n| {
        const source = try build(&.{ .{ .string = n }, .{ .text = "   x" } });
        defer gpa.free(source);
        var lx = parser.BaseLexer.init(source);
        const t = lx.next();
        try testing.expectEqual(parser.TokenCat.string, t.cat);
        try testing.expectEqual(@as(u32, 0), t.pos);
        try testing.expectEqual(lenOf(n), t.len);
        try testing.expectEqual(n, lx.text(t).len);
        // The scan goes on after the whole token; the blanks after it are
        // the next token's `pre`.
        try testing.expectEqual(n, lx.pos);
        const x = lx.next();
        try testing.expectEqual(parser.TokenCat.name, x.cat);
        try testing.expectEqual(@as(u32, @intCast(n + 3)), x.pos);
        try testing.expectEqual(@as(u8, 3), x.pre);
    }
    // A long name, after an unterminated quote (an `err` byte).
    const source = try build(&.{ .{ .text = "\"" }, .{ .run = .{ 'a', 70_000 } } });
    defer gpa.free(source);
    var lx = parser.BaseLexer.init(source);
    try testing.expectEqual(parser.TokenCat.err, lx.next().cat);
    const t = lx.next();
    try testing.expectEqual(parser.TokenCat.name, t.cat);
    try testing.expectEqual(@as(u16, long), t.len);
    try testing.expectEqual(@as(usize, 70_000), lx.text(t).len);
}

test "the parser reads a long token whole: its leaf, its spans, the token after it" {
    for (sizes) |n| {
        const source = try build(&.{ .{ .text = "x = " }, .{ .string = n }, .{ .text = "   # note\n" } });
        defer gpa.free(source);
        var p = parser.Parser.init(gpa, source);
        defer p.deinit();
        const tree = try p.parseProgram();
        const set = ir.Program.stmts(tree)[0];
        const value = ir.Set.value(set);
        const leaf = ir.Str.value(value);
        const end: u32 = @intCast(4 + n);
        try testing.expectEqual(lenOf(n), leaf.src.len);
        try testing.expectEqual(end, p.leafEnd(leaf.src));
        try testing.expectEqualStrings(source[4..end], p.leafText(leaf));
        try testing.expectEqual(parser.Span{ .start = 4, .end = end }, p.span(leaf));
        try testing.expectEqual(parser.Span{ .start = 4, .end = end }, p.span(value));
        try testing.expectEqual(parser.Span{ .start = 0, .end = end }, p.span(set));
        try testing.expectEqual(parser.Span{ .start = 2, .end = 3 }, p.sideRole(set, .eq).?);
        // The comment after it: its position and blanks, through the trivia.
        const comment = p.trivia()[0];
        try testing.expectEqual(end + 3, comment.pos);
        try testing.expectEqual(@as(u8, 3), comment.pre);
        try testing.expectEqualStrings("# note", p.tokenText(comment));
        try testing.expectEqual(end + 9, p.tokenEnd(comment));
        // A short leaf reads as it always does.
        try testing.expectEqualStrings("x", ir.Set.name(set).getText(source));
        try testing.expectEqualStrings("x", p.leafText(ir.Set.name(set)));
    }
}

test "side-band roles, nested nodes and facts take a long token's end" {
    const n1 = 70_000;
    const n2 = 100_000;
    const source = try build(&.{ .{ .text = ": " }, .{ .string = n1 }, .{ .text = "\nf(-" }, .{ .string = n2 }, .{ .text = ", 1)" } });
    defer gpa.free(source);
    var p = parser.Parser.init(gpa, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const stmts = ir.Program.stmts(tree);
    try testing.expectEqual(parser.Span{ .start = 2, .end = 2 + n1 }, p.sideRole(stmts[0], .text).?);
    const at = 2 + n1 + 4; // the second string
    const neg = ir.Call.args(stmts[1])[0];
    try testing.expectEqual(parser.Span{ .start = at - 1, .end = at + n2 }, p.span(neg));
    // `(str 2)` nested in `(neg ...)` spans its element alone.
    try testing.expectEqual(parser.Span{ .start = at, .end = at + n2 }, p.span(ir.Neg.value(neg)));
    try testing.expectEqual(parser.Span{ .start = 2 + n1 + 1, .end = @intCast(source.len) }, p.span(stmts[1]));
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try p.writeFacts(&out.writer, stmts[0]);
    const note = stmts[0].list.id;
    var want = try std.fmt.allocPrint(gpa, "(node {d} note 0 {d})\n(side {d} text 2 {d})\n", .{ note, 2 + n1, note, n1 });
    try testing.expectEqualStrings(want, out.written());
    gpa.free(want);
    out.clearRetainingCapacity();
    try p.writeFacts(&out.writer, ir.Neg.value(neg));
    const str = ir.Neg.value(neg).list.id;
    want = try std.fmt.allocPrint(gpa, "(node {d} str {d} {d})\n(role {d} value leaf {d} {d})\n", .{ str, at, at + n2, str, at, n2 });
    defer gpa.free(want);
    try testing.expectEqualStrings(want, out.written());
}

test "several long tokens in one input, and a keyword lookup on a long name" {
    const lens = [_]usize{ 65535, 200_000, 66_000 };
    const source = try build(&.{
        .{ .text = "let " },    .{ .run = .{ 'b', 70_000 } }, .{ .text = " = 1\nlet let = 2\nf(" },
        .{ .string = lens[0] }, .{ .text = ", " },            .{ .string = lens[1] },
        .{ .text = "," },       .{ .string = lens[2] },       .{ .text = ")\n" },
    });
    defer gpa.free(source);
    var p = parser.Parser.init(gpa, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const stmts = ir.Program.stmts(tree);
    // The long name is no keyword; after `let` the state takes a name.
    const name = ir.Set.name(stmts[0]);
    try testing.expectEqual(@as(u16, long), name.src.len);
    try testing.expectEqualStrings(source[4..][0..70_000], p.leafText(name));
    try testing.expect(std.mem.allEqual(u8, p.leafText(name), 'b'));
    try testing.expectEqualStrings("let", p.leafText(ir.Set.name(stmts[1])));
    var at: u32 = @intCast(4 + 70_000 + " = 1\nlet let = 2\nf(".len);
    for (ir.Call.args(stmts[2]), lens, [_]u32{ 2, 1, 0 }) |arg, n, gap| {
        const leaf = ir.Str.value(arg);
        try testing.expectEqual(at, leaf.src.pos);
        try testing.expectEqual(at + @as(u32, @intCast(n)), p.leafEnd(leaf.src));
        try testing.expectEqual(n, p.leafText(leaf).len);
        at += @as(u32, @intCast(n)) + gap;
    }
    try testing.expectEqual(parser.Span{ .start = @intCast(source.len - 2 - 2 - lens[0] - 2 - lens[1] - 1 - lens[2]), .end = @intCast(source.len - 1) }, p.span(stmts[2]));
}

test "a long token through the wrapper: adjacent strings join into one" {
    for ([_][2]usize{ .{ 40_000, 40_000 }, .{ 70_000, 70_000 }, .{ 3, 65_535 } }) |pair| {
        const source = try build(&.{ .{ .text = "x = " }, .{ .string = pair[0] }, .{ .string = pair[1] }, .{ .text = "\ny = 1" } });
        defer gpa.free(source);
        var p = parser.Parser.init(gpa, source);
        defer p.deinit();
        const tree = try p.parseProgram();
        const stmts = ir.Program.stmts(tree);
        const leaf = ir.Str.value(ir.Set.value(stmts[0]));
        const n = pair[0] + pair[1];
        try testing.expectEqual(@as(u16, long), leaf.src.len);
        try testing.expectEqual(n, p.leafText(leaf).len);
        try testing.expectEqual(parser.Span{ .start = 0, .end = @intCast(4 + n) }, p.span(stmts[0]));
        try testing.expectEqual(parser.Span{ .start = @intCast(5 + n), .end = @intCast(source.len) }, p.span(stmts[1]));
    }
}

test "a long token whose end the lexer no longer holds fails the parse" {
    // `>`: the wrapper reads 40 tokens ahead, 20 of them long: the ends of
    // the first ones are gone when the parser reads them.
    var parts: [42]Part = undefined;
    parts[0] = .{ .text = ">f(" };
    for (0..20) |i| {
        parts[1 + 2 * i] = .{ .string = 70_000 };
        parts[2 + 2 * i] = .{ .text = "," };
    }
    parts[41] = .{ .text = "1)" };
    const source = try build(&parts);
    defer gpa.free(source);
    var p = parser.Parser.init(gpa, source);
    defer p.deinit();
    try testing.expectError(error.TokenEndUnknown, p.parseProgram());
    // Reading one token ahead, the same call parses.
    var q = parser.Parser.init(gpa, source[1..]);
    defer q.deinit();
    const tree = try q.parseProgram();
    try testing.expectEqual(@as(usize, 21), ir.Call.args(ir.Program.stmts(tree)[0]).len);
}

test "two long tokens at one position with different ends fail the parse" {
    // `<`: the wrapper scans the first long string again, cut at its `|`
    // and still long, before it returns the first: neither has one end.
    const source = try build(&.{ .{ .text = "<x = " }, .{ .cut = .{ .len = 150_000, .at = 80_000 } } });
    defer gpa.free(source);
    var p = parser.Parser.init(gpa, source);
    defer p.deinit();
    try testing.expectError(error.TokenEndUnknown, p.parseProgram());
    // Cut short of 65535 bytes, the second token is a short one at that
    // position: no ambiguity, a syntax error.
    const short = try build(&.{ .{ .text = "<x = " }, .{ .cut = .{ .len = 150_000, .at = 1_000 } } });
    defer gpa.free(short);
    var q = parser.Parser.init(gpa, short);
    defer q.deinit();
    try testing.expectError(error.ParseError, q.parseProgram());
    try testing.expectEqual(parser.Span{ .start = 5, .end = 5 + 1_000 }, q.lastError().?.span);
}

test "tolerant parsing next to long tokens keeps their spans" {
    const n = 70_000;
    // `)` after a long value is deleted; `y =` gets a hole.
    {
        const source = try build(&.{ .{ .text = "x = " }, .{ .string = n }, .{ .text = " )\ny =\n" } });
        defer gpa.free(source);
        var p = parser.Parser.init(gpa, source);
        defer p.deinit();
        const r = try p.parseTolerant(.program, 8);
        try testing.expect(r.complete);
        try testing.expectEqual(@as(u32, 1), r.deletions);
        try testing.expectEqual(@as(u32, 1), r.insertions);
        try testing.expectEqual(parser.Span{ .start = 4 + n + 1, .end = 4 + n + 2 }, r.failure.?.span);
        const stmts = ir.Program.stmts(r.sexp);
        try testing.expectEqual(parser.Span{ .start = 0, .end = 4 + n }, p.span(stmts[0]));
        const hole = ir.Ref.id(ir.Set.value(stmts[1]));
        try testing.expectEqual(parser.Src{ .pos = 4 + n + 6, .len = 0, .id = 0 }, hole.src);
        try testing.expectEqual(parser.Span{ .start = 4 + n + 3, .end = 4 + n + 6 }, p.span(stmts[1]));
    }
    // A long string where none fits is deleted; the first error spans it
    // whole. The strict parse first, then a tolerant one that reads the
    // input again.
    {
        const source = try build(&.{ .{ .text = "x = 1 " }, .{ .string = n }, .{ .text = "\ny = 2" } });
        defer gpa.free(source);
        var p = parser.Parser.init(gpa, source);
        defer p.deinit();
        try testing.expectError(error.ParseError, p.parseProgram());
        try testing.expectEqual(parser.Span{ .start = 6, .end = 6 + n }, p.lastError().?.span);
        const r = try p.parseTolerant(.program, 8);
        try testing.expect(r.complete);
        try testing.expectEqual(@as(u32, 1), r.deletions);
        try testing.expectEqual(parser.Span{ .start = 6, .end = 6 + n }, r.failure.?.span);
        const stmts = ir.Program.stmts(r.sexp);
        try testing.expectEqual(@as(usize, 2), stmts.len);
        try testing.expectEqual(parser.Span{ .start = 0, .end = 5 }, p.span(stmts[0]));
        try testing.expectEqual(parser.Span{ .start = 7 + n, .end = 12 + n }, p.span(stmts[1]));
    }
    // An unfinished call: the pieces span the long string whole.
    {
        const source = try build(&.{ .{ .text = "f(" }, .{ .string = n } });
        defer gpa.free(source);
        var p = parser.Parser.init(gpa, source);
        defer p.deinit();
        const r = try p.parseTolerant(.program, 8);
        try testing.expect(!r.complete);
        const last = r.pieces[r.pieces.len - 1];
        try testing.expectEqual(parser.Span{ .start = 2, .end = 2 + n }, p.span(last));
        try testing.expectEqual(n, p.leafText(ir.Str.value(last)).len);
    }
}

test "reset reads a new source; a long token's end is the new one's" {
    const first = try build(&.{ .{ .text = "x = " }, .{ .string = 80_000 } });
    defer gpa.free(first);
    const second = try build(&.{ .{ .text = "x = " }, .{ .string = 90_000 } });
    defer gpa.free(second);
    var p = parser.Parser.init(gpa, first);
    defer p.deinit();
    _ = try p.parseProgram();
    p.reset(second);
    const tree = try p.parseProgram();
    const leaf = ir.Str.value(ir.Set.value(ir.Program.stmts(tree)[0]));
    try testing.expectEqual(@as(u32, 4 + 90_000), p.leafEnd(leaf.src));
}
