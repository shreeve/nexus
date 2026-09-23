//! The fixed part of every generated parser module, taken from
//! runtime_template.zig: a compiled, unit-tested Zig file whose sections
//! codegen.zig emits by name.
//!
//! Template markup (each marker is a whole line, leading spaces allowed):
//!
//!   // @section NAME     starts section NAME; it runs to the next `// @end`
//!   // @slot NAME        inside a section: replaced by generated code
//!
//! Lines outside every section (the template's own imports, its test
//! fixture, and its tests) are never emitted.

const std = @import("std");

pub const template = @embedFile("runtime_template.zig");

/// Generated text for one `// @slot NAME` line.
pub const Slot = struct { name: []const u8, text: []const u8 };

pub const Error = error{ UnknownSection, UnfilledSlot, UnknownSlot } || std.Io.Writer.Error;

/// Write section `name`, replacing each slot line with the text `slots`
/// gives for it. Every slot of the section must be given, and every given
/// slot must occur in the section.
pub fn writeSection(w: *std.Io.Writer, name: []const u8, slots: []const Slot) Error!void {
    const body = section(name) orelse return error.UnknownSection;
    var used: usize = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        if (marker(line, "// @slot ")) |slotName| {
            const slot = for (slots) |s| {
                if (std.mem.eql(u8, s.name, slotName)) break s;
            } else return error.UnfilledSlot;
            used += 1;
            try w.writeAll(slot.text);
            continue;
        }
        try w.writeAll(line);
        if (lines.index != null) try w.writeByte('\n');
    }
    if (used != slots.len) return error.UnknownSlot;
}

/// The text of section `name`: the lines between its `// @section` line
/// and the next `// @end`, each ending in a newline.
pub fn section(name: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < template.len) {
        const end = std.mem.indexOfScalarPos(u8, template, pos, '\n') orelse template.len;
        const line = template[pos..end];
        pos = @min(end + 1, template.len);
        const found = marker(line, "// @section ") orelse continue;
        if (!std.mem.eql(u8, found, name)) continue;
        const start = pos;
        while (pos < template.len) {
            const e = std.mem.indexOfScalarPos(u8, template, pos, '\n') orelse template.len;
            if (marker(template[pos..e], "// @end") != null) return template[start..pos];
            pos = @min(e + 1, template.len);
        }
        return null;
    }
    return null;
}

/// The rest of `line` after `prefix` (leading spaces ignored), or null.
fn marker(line: []const u8, prefix: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    return std.mem.trim(u8, trimmed[prefix.len..], " ");
}

// =============================================================================
// Tests
// =============================================================================

test "every section is present and ends" {
    for ([_][]const u8{ "sexp", "parser", "ir" }) |name| {
        const body = section(name) orelse return error.MissingSection;
        try std.testing.expect(body.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, body, "// @section") == null);
        try std.testing.expect(std.mem.indexOf(u8, body, "// @end") == null);
    }
    try std.testing.expectEqual(@as(?[]const u8, null), section("nope"));
}

test "sections exclude the fixture and its tests" {
    for ([_][]const u8{ "sexp", "parser", "ir" }) |name| {
        const body = section(name).?;
        try std.testing.expect(std.mem.indexOf(u8, body, "test \"") == null);
        try std.testing.expect(std.mem.indexOf(u8, body, "@import(\"std\")") == null);
    }
}

test "slots are replaced and must all be filled" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeSection(&out.writer, "parser", &.{.{ .name = "startMethods", .text = "    // START\n" }});
    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "    // START\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@slot") == null);

    var sink: std.Io.Writer.Discarding = .init(&.{});
    try std.testing.expectError(error.UnfilledSlot, writeSection(&sink.writer, "parser", &.{}));
    try std.testing.expectError(error.UnknownSlot, writeSection(&sink.writer, "sexp", &.{.{ .name = "x", .text = "" }}));
    try std.testing.expectError(error.UnknownSection, writeSection(&sink.writer, "nope", &.{}));
}

test "the template's runtime tests" {
    _ = @import("runtime_template.zig");
}
