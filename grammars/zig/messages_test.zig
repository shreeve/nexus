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
    // 1:12: expected ';' or block after function prototype
    try expectMessage("fn f() void", "1:12: expected ';' or '{' after a type expression, got EOF");
}

test "a destructure" {
    // 2:23: expected expression or var decl, found '='
    try expectMessage("test {\n    const a, const b, = .{ 1, 2 };\n}\n", "2:23: expected an expression, 'const' or 'var', got '='");
}

test "a container member" {
    // 1:21: expected type expression, found ','
    try expectMessage("const U = enum(u8) {,};\n", "1:21: expected a container field, a declaration, a document comment or '}', got ','");
}

test "a chained comparison" {
    // 1:18: comparison operators cannot be chained
    try expectMessage("const x = a == b == c;\n", "1:18: expected 'or' after an expression, got '=='");
}

// After a complete operand the parser has only reductions left: the error
// lists what the construct the reductions complete can take, after it.
// When the next token is on a later line, the error is at the end of the
// line before.

test "a missing ';' at the end of a line" {
    // 1:27: expected ';' after declaration
    try expectMessage("const std = @import(\"std\")\npub fn main() void {}\n", "1:27: expected ';' after an expression, got 'pub'");
    // 2:10: expected ';' after statement
    try expectMessage("test {\n    x = 1\n}\n", "2:10: expected ';' after an expression, got '}'");
    // 3:11: expected ';' after statement
    try expectMessage("test {\n    var a = 1;\n    a += 2\n    _ = a;\n}\n", "3:11: expected ';' after an expression, got an identifier");
    // 2:15: expected ';' or 'else' after statement
    try expectMessage("test {\n    if (c) x()\n    y();\n}\n", "2:15: expected ';' or 'else' after an assignment, got an identifier");
    // 2:9: expected ';' after statement. An expression statement may go
    // on as an assignment: the list names each assignment operator.
    try expectMessage("test {\n    ({})\n    var b = 1;\n}\n", "2:9: expected ',', ';', '=', '*=', '*|=', '/=', '%=', '+=', '+|=', '-=', '-|=', '<<=', '<<|=', '>>=', '&=', '^=', '|=', '*%=', '+%=' or '-%=' after an expression, got 'var'");
}

test "a missing ',' in a list" {
    // 2:9: expected ',' after argument
    try expectMessage("test {\n    f(a b);\n}\n", "2:9: expected ',' or ')' after an expression, got an identifier");
    // 1:12: expected ',' after parameter
    try expectMessage("fn f(a: u8 b: u8) void {}\n", "1:12: expected ',' or ')' after a parameter, got an identifier");
    // 2:10: expected ',' after field
    try expectMessage("const S = struct {\n    a: u8\n    b: u8,\n};\n", "2:10: expected ',' or '}' after a container field, got an identifier");
    // 3:15: expected ',' after switch prong
    try expectMessage("test {\n    switch (x) {\n        1 => a\n        2 => b,\n    }\n}\n", "3:15: expected ',' or '}' after a switch prong, got a number literal");
    // 2:23: expected ',' after initializer
    try expectMessage("test {\n    const a = .{ 1, 2 3 };\n}\n", "2:23: expected ',' or '}' after an expression, got a number literal");
}
