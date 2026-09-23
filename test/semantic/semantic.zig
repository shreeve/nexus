//! @lang module of the schema-mode test grammar: re-exports the Tag enum and
//! provides a Lexer wrapper that turns keyword identifiers into keyword
//! tokens. Its tests exercise the schema-mode runtime: accessors, spans,
//! the role store, facts, trivia, diagnostics and tolerant repair.
const std = @import("std");
const parser = @import("parser.zig");

/// The tags, generated from the grammar's @schema.
pub const Tag = parser.Tag;

const keywords = std.StaticStringMap(parser.TokenCat).initComptime(.{
    .{ "let", .let },    .{ "if", .@"if" },     .{ "unless", .unless },
    .{ "then", .then },  .{ "else", .@"else" }, .{ "return", .@"return" },
    .{ "for", .@"for" }, .{ "ptr", .ptr },      .{ "in", .in },
    .{ "do", .do },      .{ "call", .call },    .{ "swap", .swap },
    .{ "with", .with },  .{ "pass", .pass },    .{ "yield", .yield },
});

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        var tok = self.base.next();
        if (tok.cat == .ident) {
            if (keywords.get(self.base.text(tok))) |cat| tok.cat = cat;
        }
        return tok;
    }
    pub fn text(self: *const Lexer, tok: parser.Token) []const u8 {
        return self.base.text(tok);
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};

// =============================================================================
// Tests (run against the generated parser)
// =============================================================================

const testing = std.testing;
const ir = parser.ir;
const Sexp = parser.Sexp;

fn parse(source: []const u8) !struct { p: parser.Parser, tree: Sexp } {
    var p = parser.Parser.init(testing.allocator, source);
    errdefer p.deinit();
    const tree = try p.parseProgram();
    return .{ .p = p, .tree = tree };
}

fn spanText(p: *const parser.Parser, s: Sexp) []const u8 {
    const sp = p.span(s);
    return p.source[sp.start..sp.end];
}

test "accessors: roles by name, per-kind views, fixed positions" {
    var r = try parse("x = 1 + 2 * 3\nlet b : t = -2");
    defer r.p.deinit();
    const stmts = ir.rest(r.tree, .stmts);
    try testing.expectEqual(@as(usize, 2), stmts.len);
    try testing.expectEqualSlices(Sexp, stmts, ir.Module.stmts(r.tree));

    const set = stmts[0];
    try testing.expect(set.isKind(.set));
    try testing.expect(ir.get(set, .op) == .nil);
    try testing.expect(ir.Set.target(set).isKind(.name));
    const sum = ir.Set.value(set);
    try testing.expect(sum.isKind(.@"+"));
    try testing.expect(ir.@"+".right(sum).isKind(.@"*"));
    try testing.expectEqualStrings("1", ir.Num.value(ir.@"+".left(sum)).getText(r.p.source));

    // `let` without a type keeps the slot: positions never shift.
    const let = stmts[1];
    try testing.expectEqual(@as(usize, 4), let.items().len);
    try testing.expectEqualStrings("b", ir.Let.name(let).getText(r.p.source));
    try testing.expectEqualStrings("t", spanText(&r.p, ir.Let.type(let)));
    try testing.expect(ir.get(ir.Let.value(let), .value).isKind(.num));

    try testing.expect(ir.has(.set, .target));
    try testing.expect(!ir.has(.set, .body));
    try testing.expect(ir.has(.module, .stmts));
}

test "spans: reductions cover their tokens; nested nodes their elements" {
    const src = "x = (1 + 2)\nlet z += 5";
    var r = try parse(src);
    defer r.p.deinit();
    const stmts = ir.rest(r.tree, .stmts);
    try testing.expectEqualStrings("x = (1 + 2)", spanText(&r.p, stmts[0]));
    // `(1 + 2)` passes the `+` node through: its span excludes the parens.
    try testing.expectEqualStrings("1 + 2", spanText(&r.p, ir.Set.value(stmts[0])));
    try testing.expectEqualStrings("let z += 5", spanText(&r.p, stmts[1]));
    // (set op:+= target:(name 2) value:4): the nested `name` spans `z`.
    try testing.expectEqualStrings("z", spanText(&r.p, ir.Set.target(stmts[1])));
    try testing.expectEqualStrings(src, spanText(&r.p, r.tree));
    try testing.expect(r.p.ruleOf(stmts[0]) != null);
    try testing.expect(r.p.ruleOf(stmts[0]).? != r.p.ruleOf(stmts[1]).?);
    try testing.expect(stmts[0].list.id != 0 and stmts[0].list.id <= r.p.nodeCount());
}

test "the role store records side-band roles" {
    var r = try parse("x  =  1\ny += 2");
    defer r.p.deinit();
    const stmts = ir.rest(r.tree, .stmts);
    const eq = r.p.sideRole(stmts[0], .eq).?;
    try testing.expectEqual(@as(u32, 3), eq.start);
    try testing.expectEqual(@as(u32, 1), eq.len());
    // The `+=` alternative labels no `eq`.
    try testing.expectEqual(@as(?parser.Span, null), r.p.sideRole(stmts[1], .eq));
}

test "facts export" {
    var r = try parse("x = 1");
    defer r.p.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try r.p.writeFacts(&out.writer, r.tree);
    const set = ir.rest(r.tree, .stmts)[0];
    const name = ir.Set.target(set);
    const num = ir.Set.value(set);
    var want: std.Io.Writer.Allocating = .init(testing.allocator);
    defer want.deinit();
    try want.writer.print(
        \\(node {d} module 0 5)
        \\(role {d} stmts {d})
        \\(node {d} set 0 5)
        \\(role {d} target {d})
        \\(role {d} value {d})
        \\(side {d} eq 2 1)
        \\(node {d} name 0 1)
        \\(role {d} id leaf 0 1)
        \\(node {d} num 4 5)
        \\(role {d} value leaf 4 1)
        \\
    , .{
        r.tree.list.id, r.tree.list.id, set.list.id,
        set.list.id,    set.list.id,    name.list.id,
        set.list.id,    num.list.id,    set.list.id,
        name.list.id,   name.list.id,   num.list.id,
        num.list.id,
    });
    try testing.expectEqualStrings(want.written(), out.written());
}

test "trivia tokens are kept with their spans" {
    var r = try parse("x = 1 # one\n# two\ny = 2");
    defer r.p.deinit();
    try testing.expectEqual(@as(usize, 2), ir.rest(r.tree, .stmts).len);
    const t = r.p.trivia();
    try testing.expectEqual(@as(usize, 2), t.len);
    try testing.expectEqualStrings("# one", r.p.source[t[0].pos..][0..t[0].len]);
    try testing.expectEqualStrings("# two", r.p.source[t[1].pos..][0..t[1].len]);
}

test "parse errors name the expected set (@display, @errors)" {
    var p = parser.Parser.init(testing.allocator, "x = )");
    defer p.deinit();
    try testing.expectError(error.ParseError, p.parseProgram());
    const f = p.lastError().?;
    try testing.expectEqual(@as(u32, 4), f.span.start);
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try p.writeError(&out.writer);
    try testing.expectEqualStrings("1:5: expected an expression, got \")\"", out.written());
}

test "tolerant parsing inserts declared tokens and records the first error" {
    var p = parser.Parser.init(testing.allocator, "x = \ny = 2");
    defer p.deinit();
    const r = try p.parseTolerant(.program, 16);
    try testing.expect(r.complete);
    try testing.expectEqual(@as(u32, 1), r.repairs);
    try testing.expectEqual(parser.TokenCat.newline, r.failure.?.cat);
    const stmts = ir.rest(r.sexp, .stmts);
    try testing.expectEqual(@as(usize, 2), stmts.len);
    // The hole is a zero-width IDENT: `(name ``)` right before the newline.
    const hole = ir.Name.id(ir.Set.value(stmts[0]));
    try testing.expectEqual(@as(u16, 0), hole.src.len);
    try testing.expectEqual(@as(u32, 4), hole.src.pos);

    // A missing statement separator is inserted as structure.
    var q = parser.Parser.init(testing.allocator, "x = 1 y = 2");
    defer q.deinit();
    const s = try q.parseTolerant(.program, 16);
    try testing.expect(s.complete);
    try testing.expectEqual(@as(usize, 2), ir.rest(s.sexp, .stmts).len);

    // Strict parsing of the same input fails.
    var strict = parser.Parser.init(testing.allocator, "x = 1 y = 2");
    defer strict.deinit();
    try testing.expectError(error.ParseError, strict.parseProgram());
}
