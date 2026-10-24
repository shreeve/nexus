//! identity.zig: `vscode/identity.json`, the extension's identity, which
//! belongs to the language (docs/LSP.md, "The extension's identity").
//! `nexus --editor` writes it with the defaults when it is missing and
//! never again; every run reads it and names the extension, its settings
//! and its contributions after it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const diag = @import("../diag.zig");
const json = @import("../json.zig");
const Highlight = @import("../highlight/highlight.zig").Highlight;

/// What the extension contributes: the language, its grammar and the
/// client (`standalone`), or the client alone, beside another extension
/// that contributes the language (`companion`).
pub const Mode = enum { standalone, companion };

pub const Identity = struct {
    /// The extension's name, the first part of its file name.
    name: []const u8,
    displayName: []const u8,
    description: []const u8,
    publisher: []const u8,
    version: []const u8,
    /// An SPDX expression, or `UNLICENSED`.
    license: []const u8,
    /// The repository's URL; empty for none.
    repository: []const u8,
    /// The prefix of the settings: `<settings>.server.path`.
    settings: []const u8,
    mode: Mode,
    /// In `companion` mode, the id of the extension that contributes the
    /// language (`publisher.name`), which the extension names when no
    /// extension contributes it; empty for none.
    provider: []const u8,
};

/// The keys of identity.json, in the order the file and package.json
/// give them.
pub const keys = [_][]const u8{ "name", "displayName", "description", "publisher", "version", "license", "repository", "settings", "mode", "provider" };

const key_list = list: {
    var s: []const u8 = "";
    for (keys, 0..) |k, i| s = s ++ (if (i > 0) ", " else "") ++ k;
    break :list s;
};

/// The defaults, none of them a name an official extension uses:
/// `nexus-<id>`, `<Language> (Nexus)`, publisher `nexus-local`.
pub fn defaults(allocator: Allocator, h: *const Highlight) Allocator.Error!Identity {
    const prefixed = try std.mem.concat(allocator, u8, &.{ "nexus-", h.id });
    return .{
        .name = prefixed,
        .displayName = try allocator.print("{s} (Nexus)", .{h.language}),
        .description = try allocator.print("{s}: highlighting and its language server.", .{h.language}),
        .publisher = "nexus-local",
        .version = "0.1.0",
        .license = "UNLICENSED",
        .repository = "",
        .settings = prefixed,
        .mode = .standalone,
        .provider = "",
    };
}

/// The file as `nexus --editor` writes it when it is missing: every key,
/// with its default.
pub fn write(allocator: Allocator, id: Identity) Writer.Error![]const u8 {
    var out: Writer.Allocating = .init(allocator);
    const w = &out.writer;
    try w.writeAll("{");
    inline for (keys, 0..) |key, i| {
        try w.writeAll(if (i > 0) ",\n  " else "\n  ");
        try json.string(w, key);
        try w.writeAll(": ");
        const value = @field(id, key);
        try json.string(w, if (@TypeOf(value) == Mode) @tagName(value) else value);
    }
    try w.writeAll("\n}\n");
    return out.written();
}

pub const Error = Allocator.Error || error{Reported};

/// identity.json's `text` over the defaults: a JSON object whose keys are
/// some of `keys`, each a string. Each mistake is reported at its place
/// in `path` (`error.Reported`).
pub fn parse(allocator: Allocator, path: []const u8, text: []const u8, base: Identity) Error!Identity {
    const source = try diag.Source.init(allocator, path, text);
    var id = base;
    var seen: [keys.len]bool = @splat(false);
    // Where `provider` is given: only `companion` mode takes one.
    var provider_at: ?usize = null;
    var scanner: std.json.Scanner = .initCompleteInput(allocator, text);
    var at = startOfNext(text, 0);
    const first = scanner.next() catch |err| return syntax(source, &scanner, err);
    if (first != .object_begin) {
        diag.errAt(source, at, "the identity is not a JSON object of strings", .{});
        return error.Reported;
    }
    while (true) {
        at = startOfNext(text, scanner.cursor);
        const key = switch (scanner.nextAlloc(allocator, .alloc_if_needed) catch |err| return syntax(source, &scanner, err)) {
            .object_end => break,
            .string, .allocated_string => |s| s,
            else => unreachable, // the scanner gives only a key or the end in an object
        };
        const index = for (keys, 0..) |k, i| {
            if (std.mem.eql(u8, k, key)) break i;
        } else {
            diag.errAt(source, at, "unknown key \"{s}\"; the keys are {s}", .{ key, key_list });
            return error.Reported;
        };
        if (seen[index]) {
            diag.errAt(source, at, "\"{s}\" is given twice", .{key});
            return error.Reported;
        }
        seen[index] = true;
        at = startOfNext(text, scanner.cursor);
        if (std.mem.eql(u8, key, "provider")) provider_at = at;
        const value = switch (scanner.nextAlloc(allocator, .alloc_if_needed) catch |err| return syntax(source, &scanner, err)) {
            .string, .allocated_string => |s| s,
            else => {
                diag.errAt(source, at, "the value of \"{s}\" is not a string", .{key});
                return error.Reported;
            },
        };
        if (rule(key, value)) |must| {
            diag.errAt(source, at, "\"{s}\": \"{s}\" is not valid: it {s}", .{ key, value, must });
            return error.Reported;
        }
        inline for (keys) |k| if (std.mem.eql(u8, k, key)) {
            if (@TypeOf(@field(id, k)) == Mode) {
                @field(id, k) = std.meta.stringToEnum(Mode, value).?;
            } else @field(id, k) = value;
        };
    }
    _ = scanner.next() catch |err| return syntax(source, &scanner, err);
    if (provider_at) |p| if (id.provider.len > 0 and id.mode != .companion) {
        diag.errAt(source, p, "\"provider\" is for companion mode, and the mode is standalone", .{});
        return error.Reported;
    };
    return id;
}

/// What `value` must be when it is not a valid value of `key`, else null.
fn rule(key: []const u8, value: []const u8) ?[]const u8 {
    const eql = std.mem.eql;
    if (eql(u8, key, "name")) {
        if (!isName(value, false)) return "must be lowercase letters, digits and '-', starting with a letter or digit";
    } else if (eql(u8, key, "publisher")) {
        if (!isName(value, true)) return "must be letters, digits and '-', starting with a letter or digit";
    } else if (eql(u8, key, "displayName") or eql(u8, key, "license")) {
        if (value.len == 0) return "must not be empty";
    } else if (eql(u8, key, "version")) {
        if (!isVersion(value)) return "must be three numbers joined by dots, such as 0.1.0";
    } else if (eql(u8, key, "settings")) {
        if (!isPrefix(value)) return "must be names of letters, digits, '_' and '-', joined by dots";
    } else if (eql(u8, key, "mode")) {
        if (std.meta.stringToEnum(Mode, value) == null) return "must be standalone or companion";
    } else if (eql(u8, key, "provider")) {
        if (value.len > 0 and !isExtensionId(value)) return "must be an extension's id, its publisher and name joined by a dot, such as ziglang.vscode-zig";
    }
    return null;
}

fn isName(s: []const u8, upper: bool) bool {
    if (s.len == 0 or s[0] == '-') return false;
    for (s) |c| switch (c) {
        'a'...'z', '0'...'9', '-' => {},
        'A'...'Z' => if (!upper) return false,
        else => return false,
    };
    return true;
}

/// `publisher.name`: a publisher and a name, each of letters, digits and
/// `-`, starting with a letter or digit.
fn isExtensionId(s: []const u8) bool {
    const dot = std.mem.findScalar(u8, s, '.') orelse return false;
    return isName(s[0..dot], true) and isName(s[dot + 1 ..], true);
}

fn isVersion(s: []const u8) bool {
    var parts = std.mem.splitScalar(u8, s, '.');
    var n: usize = 0;
    while (parts.next()) |part| : (n += 1) {
        if (part.len == 0) return false;
        for (part) |c| if (!std.ascii.isDigit(c)) return false;
    }
    return n == 3;
}

fn isPrefix(s: []const u8) bool {
    var parts = std.mem.splitScalar(u8, s, '.');
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |c| if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

/// The offset of the next token after `from`: past blanks, `,` and `:`.
fn startOfNext(text: []const u8, from: usize) usize {
    var i = from;
    while (i < text.len) : (i += 1) switch (text[i]) {
        ' ', '\t', '\r', '\n', ',', ':' => {},
        else => break,
    };
    return i;
}

fn syntax(source: diag.Source, scanner: *const std.json.Scanner, err: anyerror) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    diag.errAt(source, scanner.cursor, "the identity is not valid JSON", .{});
    return error.Reported;
}
