//! json.zig: JSON strings for the files Nexus writes by hand (the editor
//! files, `--describe`), whose key order is fixed.

const std = @import("std");
const Writer = std.Io.Writer;

/// `s` as a JSON string: `"` `\` and control characters escaped, UTF-8
/// characters as they are, and a byte that is no part of one as `\u00XX`
/// (its Latin-1 character).
pub fn string(w: *Writer, s: []const u8) Writer.Error!void {
    try w.writeByte('"');
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0...8, 11, 12, 14...0x1f, 0x7f => try w.print("\\u{x:0>4}", .{c}),
            0x20...0x21, 0x23...0x5b, 0x5d...0x7e => try w.writeByte(c),
            0x80...0xff => {
                const n = std.unicode.utf8ByteSequenceLength(c) catch 0;
                if (n > 0 and i + n <= s.len and std.unicode.utf8ValidateSlice(s[i..][0..n])) {
                    try w.writeAll(s[i..][0..n]);
                    i += n;
                    continue;
                }
                try w.print("\\u{x:0>4}", .{c});
            },
        }
        i += 1;
    }
    try w.writeByte('"');
}

/// A JSON string, or `null`.
pub fn optString(w: *Writer, s: ?[]const u8) Writer.Error!void {
    if (s) |t| return string(w, t);
    try w.writeAll("null");
}

test "json strings" {
    var buf: [64]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try string(&w, "a\"b\\\n\x01\u{2192}\xff");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\\\n\\u0001\u{2192}\\u00ff\"", w.buffered());
}
