//! The syntax errors of the parser generated from zig.grammar, worded by
//! its @display and @errors. Each case is at the line and column
//! std.zig.Ast reports for the same input (Zig 0.17.0, checked in
//! process), and names Ast's message in a comment.
const std = @import("std");
const parser = @import("parser.zig");

/// Nexus's message for `src` is `want`, at Ast's line and column.
fn expectMessage(src: [:0]const u8, want: []const u8) !void {
    const gpa = std.testing.allocator;
    var p = parser.Parser.init(gpa, src);
    defer p.deinit();
    if (p.parseRoot()) |_| {
        std.debug.print("input {f}: accepted\n", .{std.zig.fmtString(src)});
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.ParseError => {},
        else => return err,
    }
    var a: std.Io.Writer.Allocating = .init(gpa);
    defer a.deinit();
    try p.writeError(&a.writer);
    try std.testing.expectEqualStrings(want, a.written());

    var tree = try std.zig.Ast.parse(gpa, src, .{ .recover = false, .mode = .zig });
    defer tree.deinit(gpa);
    try std.testing.expect(tree.errors.len > 0);
    const e = tree.errors[0];
    const loc = tree.tokenLocation(0, e.token);
    var buf: [32]u8 = undefined;
    const at = try std.fmt.bufPrint(&buf, "{d}:{d}:", .{ loc.line + 1, loc.column + 1 + tree.errorOffset(e) });
    try std.testing.expectEqualStrings(at, want[0..at.len]);
}

test "a missing expression" {
    // 1:11: expected expression, found ';'
    try expectMessage("const x = ;\n", "1:11: expected an expression, got ';'");
    // 3:13: expected expression, found ','
    try expectMessage("const S = struct {\n    a: u8,\n    b: u8 = ,\n};\n", "3:13: expected an expression, got ','");
    // 1:15: expected expression, found 'EOF'
    try expectMessage("const x = f(a,\n", "1:15: expected an expression or ')', got EOF");
}

test "a missing operand after a prefix operator" {
    // 1:12: expected prefix expression, found ';'
    try expectMessage("const x = -;\n", "1:12: expected an expression, got ';'");
}

test "a missing type expression" {
    // 1:12: expected type expression, found ':'
    try expectMessage("const T = *:0 u8;\n", "1:12: expected a type expression, 'const', 'align', 'volatile', 'allowzero' or 'addrspace', got ':'");
    // 1:21: expected type expression, found '...'
    try expectMessage("fn f(x: anytype, y: ...) void {}\n", "1:21: expected a type expression or 'anytype', got '...'");
}

test "a missing body" {
    // 2:11: expected block or assignment, found ';'
    try expectMessage("test {\n    if (a);\n}\n", "2:11: expected a block, an assignment or '|', got ';'");
    // 2:15: expected block or assignment, found '}'
    try expectMessage("test {\n    while (a) }\n", "2:15: expected a block, an assignment, ':' or '|', got '}'");
    // 2:23: expected expression or assignment, found '}'
    try expectMessage("test {\n    switch (x) { 1 => }\n}\n", "2:23: expected an assignment or '|', got '}'");
    // expected_semi_or_lbrace, from @messages.
    try expectAst("fn f() void");
}

test "a destructure" {
    // 2:23: expected expression or var decl, found '='
    try expectMessage("test {\n    const a, const b, = .{ 1, 2 };\n}\n", "2:23: expected an expression, 'const' or 'var', got '='");
}

test "a container member" {
    // 1:21: expected type expression, found ','
    try expectMessage("const U = enum(u8) {,};\n", "1:21: expected a container field, a declaration, a document comment or '}', got ','");
}
/// Nexus's message for `src` is Ast's, word for word, at Ast's line and
/// column: zig.grammar's `@messages` gives it.
fn expectAst(src: [:0]const u8) !void {
    const gpa = std.testing.allocator;
    var tree = try std.zig.Ast.parse(gpa, src, .{ .recover = false, .mode = .zig });
    defer tree.deinit(gpa);
    try std.testing.expect(tree.errors.len > 0);
    const e = tree.errors[0];
    const loc = tree.tokenLocation(0, e.token);
    var want: std.Io.Writer.Allocating = .init(gpa);
    defer want.deinit();
    try want.writer.print("{d}:{d}: ", .{ loc.line + 1, loc.column + 1 + tree.errorOffset(e) });
    try tree.renderError(e, &want.writer);
    try expectMessage(src, want.written());
}

// After a complete operand the parser has only reductions left: the error
// is worded after the construct the reductions complete. When the next
// token is on a later line, the error is at the end of the line before.
// zig.grammar's @messages words the common ones as Parse.zig does.

test "a missing ';' at the end of a line" {
    // expected_semi_after_decl
    try expectAst("const std = @import(\"std\")\npub fn main() void {}\n");
    try expectAst("const x = 1\nconst y = 2;\n");
    // expected_semi_after_stmt: an assignment, a declaration, an
    // expression statement, `comptime`, `defer`, an if-else statement.
    try expectAst("test {\n    x = 1\n}\n");
    try expectAst("test {\n    var a = 1;\n    a += 2\n    _ = a;\n}\n");
    try expectAst("test {\n    const x = 1\n    const y = 2;\n}\n");
    try expectAst("test {\n    ({})\n    var b = 1;\n}\n");
    try expectAst("test {\n    comptime a & b\n    c & d;\n}\n");
    try expectAst("test {\n    defer x()\n    y();\n}\n");
    try expectAst("test {\n    if (c) {} else x()\n    y();\n}\n");
    // expected_semi_or_else: if, while and for statements.
    try expectAst("test {\n    if (c) x()\n    y();\n}\n");
    try expectAst("test {\n    while (c) x()\n    y();\n}\n");
    try expectAst("test {\n    for (a) |b| x()\n    y();\n}\n");
    // A token no entry lists: the automatic message.
    try expectMessage("test {\n    x = 1\n    \"s\";\n}\n", "2:10: expected ';' after an expression, got a string literal");
}

test "a missing ',' in a list" {
    try expectAst("test {\n    f(a b);\n}\n");
    try expectAst("fn f(a: u8 b: u8) void {}\n");
    try expectAst("const S = struct {\n    a: u8\n    b: u8,\n};\n");
    try expectAst("test {\n    switch (x) {\n        1 => a\n        2 => b,\n    }\n}\n");
    // 2:23: expected ',' after initializer. Inside a block, the items of
    // `.{ ... }` have no entry.
    try expectMessage("test {\n    const a = .{ 1, 2 3 };\n}\n", "2:23: expected ',' or '}' after an expression, got a number literal");
}

test "a mistake Parse.zig names" {
    try expectAst("const x = a == b == c;\n");
    try expectAst("test {\n    return a < b < c;\n}\n");
    try expectAst("var x: [*]align(0:0:0)u8 = bar;\n");
    try expectAst("const a: *align(4) align(8) u8;\n");
    try expectAst("var a: [10]align(10) u8 = e;\n");
    try expectAst("comptime {\n    var z: u32 == 12 + 1;\n}\n");
    try expectAst("extern fn f(a: u32, ..., b: u32) void;\n");
    try expectAst("fn()0");
    try expectAst("_ = 2 -1,\n");
}

/// Nexus's message for `src` is `want`, where Ast reports the mistake at
/// an earlier token than the parser can find it.
fn expectEarlier(src: [:0]const u8, want: []const u8) !void {
    const gpa = std.testing.allocator;
    var p = parser.Parser.init(gpa, src);
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parseRoot());
    var a: std.Io.Writer.Allocating = .init(gpa);
    defer a.deinit();
    try p.writeError(&a.writer);
    try std.testing.expectEqualStrings(want, a.written());
}

test "a mistake Parse.zig finds a token earlier" {
    // 3:5: declarations are not allowed between container fields. The
    // parser finds it at the field after the declaration.
    try expectEarlier("const S = struct {\n    a: u8,\n    const b = 1;\n    c: u8,\n};\n", "3:17: declarations are not allowed between container fields");
    // 1:1: documentation comments cannot be attached to tests
    try expectEarlier("///\ntest {}\n", "1:4: documentation comments cannot be attached to tests");
}
