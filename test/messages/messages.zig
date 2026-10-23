//! The lang module of messages.grammar: it declares nothing, and its tests
//! check the text of each syntax error: the `@messages` entry that matches
//! it, or the automatic message where none does, the same from a strict
//! parse and from each of a tolerant parse's `failures`.
const std = @import("std");
const parser = @import("parser.zig");

/// The strict parse of `src` from `start` fails with `want`.
fn expectError(start: parser.Start, src: []const u8, want: []const u8) !void {
    var p = parser.BaseParser.init(std.testing.allocator, src);
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parse(start));
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try p.writeError(&out.writer);
    try std.testing.expectEqualStrings(want, out.written());
}

test "after: the construct being finished, whatever its last token" {
    try expectError(.program, "x = 1 y = 2;", "1:7: expected ';' after the value, got a name");
    try expectError(.program, "x = (a + b) print x;", "1:13: expected ';' after the value, got 'print'");
    try expectError(.program, "print a < b\nprint c;", "1:12: expected ';' after the value, got 'print'");
    // No entry for `x = 1 )`: the automatic message.
    try expectError(.program, "x = 1 )", "1:7: expected \";\" after an expression, got \")\"");
}

test "at: the state that rejects the token" {
    try expectError(.program, "x = a < b < c;", "1:11: comparison operators cannot be chained");
    try expectError(.program, "x = a > b < c;", "1:11: comparison operators cannot be chained");
    // The state after `a < b + c` is the one after `a < b`.
    try expectError(.program, "x = a < b + c > d;", "1:15: comparison operators cannot be chained");
    // A `)` there has no entry: the automatic message.
    try expectError(.program, "x = a < b );", "1:11: expected \";\" after an expression, got \")\"");
}

test "a guard on the token's text before the unguarded entry" {
    try expectError(.program, "x = 1; ?", "1:8: `?` is not an operator; write a comparison");
    try expectError(.program, "x = 1; !", "1:8: unexpected '!' after a statement");
    // After a second statement the parser is in another state.
    try expectError(.program, "x = 1; y = 2; ?", "1:15: expected a statement or end of input after a statement, got '?'");
}

test "name!: an example from another start symbol, and {expected}" {
    try expectError(.expr, "(a", "1:3: `(` is never closed: expected \")\"");
    // The parser is in the same state inside a statement: the entry keys
    // on the state, not on the start symbol.
    try expectError(.program, "x = (a", "1:7: `(` is never closed: expected \")\"");
}

test "a tolerant parse words each error as the strict parse does" {
    var p = parser.BaseParser.init(std.testing.allocator, "x = 1 y = 2;\nprint a < b < c;\nz = 3;");
    defer p.deinit();
    const r = try p.parseTolerant(.program, 16);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    for (r.failures) |f| {
        try p.writeFailure(&out.writer, f);
        try out.writer.writeByte('\n');
    }
    try std.testing.expectEqualStrings(
        \\1:7: expected ';' after the value, got a name
        \\2:13: comparison operators cannot be chained
        \\
    , out.written());
}
