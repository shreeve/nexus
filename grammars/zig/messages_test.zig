//! The syntax errors of the parser generated from zig.grammar, worded by
//! its @display and @errors. Each case names, in a comment, the message
//! std.zig.Ast.renderError gives for the same input (Zig 0.17.0).
const std = @import("std");
const parser = @import("parser.zig");

fn expectMessage(src: []const u8, want: []const u8) !void {
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
}

test "a missing expression" {
    // 1:11: expected expression, found ';'
    try expectMessage("const x = ;\n", "1:11: expected an expression, got ';'");
    // 3:13: expected expression, found ','
    try expectMessage("const S = struct {\n    a: u8,\n    b: u8 = ,\n};\n", "3:13: expected an expression, got ','");
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
    try expectMessage("fn f() void", "1:12: expected ';' or '{', got EOF");
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
    try expectMessage("const x = a == b == c;\n", "1:18: expected 'or', 'and', 'catch', '&', '^', '|' or 'orelse', got '=='");
}

test "after a complete operand, the whole lookahead set" {
    // 1:15: expected ',' after argument. The error is found in a state that
    // only completes a rule (here, after the identifier `a`), so the
    // expected set is every token that may follow it.
    const gpa = std.testing.allocator;
    const src = "const x = f(a b);\n";
    var p = parser.Parser.init(gpa, src);
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parseRoot());
    var a: std.Io.Writer.Allocating = .init(gpa);
    defer a.deinit();
    try p.writeError(&a.writer);
    const msg = a.written();
    try std.testing.expect(std.mem.startsWith(u8, msg, "1:15: expected EOF, ',', ';', "));
    try std.testing.expect(std.mem.endsWith(u8, msg, ", got an identifier"));
    try std.testing.expect(std.mem.count(u8, msg, ", ") > 50);
}
