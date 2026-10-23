//! hooks.zig: what the Tally language server knows beyond the grammar.
//!
//! The editor suite's hooks: every function written but `references`, so
//! the server's own search for references runs too. Tally's program is a
//! file and the files its `use` lines name, each `<name>.tally` beside it;
//! a name is a parameter or local of the function around it, else a
//! declaration of its file.

const std = @import("std");
const Allocator = std.mem.Allocator;
const lsp = @import("lsp.zig");
const parser = @import("parser.zig");
const language = @import("language.zig");
const Sexp = parser.Sexp;

// --- The parse ---------------------------------------------------------------

/// The strict parse's error, then a warning on each line a tab indents.
pub fn parseDiagnostics(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Diagnostic {
    var out: std.ArrayList(lsp.Diagnostic) = .empty;
    var p = parser.BaseParser.init(arena, text);
    if (p.parse(.program)) |_| {} else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (p.lastError()) |f| {
            var w: std.Io.Writer.Allocating = .init(arena);
            try p.writeError(&w.writer);
            // `line:col: message`: the position is the diagnostic's range.
            const message = w.written();
            const at = std.mem.findScalar(u8, message, ' ').? + 1;
            try out.append(arena, .{ .span = .{ .path = path, .start = f.span.start, .end = f.span.end }, .message = message[at..] });
        }
    }
    var line: u32 = 0;
    while (line < text.len) {
        const end: u32 = @intCast(std.mem.findScalarPos(u8, text, line, '\n') orelse text.len);
        if (text[line..end].len > 0 and text[line] == '\t')
            try out.append(arena, .{ .span = .{ .path = path, .start = line, .end = line + 1 }, .severity = .warning, .message = "a tab indents this line; Tally indents with spaces" });
        line = end + 1;
    }
    return out.items;
}

/// Each token's scope, but a name before `(` is a function.
pub fn tokens(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Token {
    _ = path;
    var out: std.ArrayList(lsp.Token) = .empty;
    var lexer = parser.Lexer.init(text);
    var last: ?parser.Token = null;
    while (true) {
        const t = lexer.next();
        if (t.cat == .eof) break;
        if (t.cat == .lparen) if (last) |l| if (l.cat == .ident)
            try out.append(arena, .{ .start = l.pos, .len = l.len, .scope = .function });
        if (language.wordScope(text[t.pos..][0..t.len]) orelse language.tokenScope(t.cat)) |scope|
            try out.append(arena, .{ .start = t.pos, .len = t.len, .scope = scope });
        last = t;
    }
    return out.items;
}

/// The outline: each function, with its parameters, and each `let`.
pub fn symbols(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.OutlineItem {
    _ = path;
    var p = parser.BaseParser.init(arena, text);
    const root = p.parse(.program) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else &.{};
    var out: std.ArrayList(lsp.OutlineItem) = .empty;
    for (root.items()[1..]) |stmt| {
        const tag = stmt.kind() orelse continue;
        if (tag != .@"fn" and tag != .let) continue;
        const span = p.span(stmt);
        const name = stmt.items()[1].src;
        switch (tag) {
            .@"fn" => {
                var params: std.ArrayList(lsp.OutlineItem) = .empty;
                for (stmt.items()[2].items()[1..]) |param| try params.append(arena, .{ .name = param.getText(text), .kind = .variable, .start = param.src.pos, .end = param.src.pos + param.src.len, .name_start = param.src.pos, .name_end = param.src.pos + param.src.len });
                try out.append(arena, .{ .name = stmt.items()[1].getText(text), .kind = .function, .start = span.start, .end = span.end, .name_start = name.pos, .name_end = name.pos + name.len, .detail = try signature(arena, text, stmt), .children = params.items });
            },
            .let => try out.append(arena, .{ .name = stmt.items()[1].getText(text), .kind = .variable, .start = span.start, .end = span.end, .name_start = name.pos, .name_end = name.pos + name.len }),
            else => unreachable,
        }
    }
    return out.items;
}

/// A fold for each `{` to its `}`.
pub fn folds(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Fold {
    _ = path;
    var out: std.ArrayList(lsp.Fold) = .empty;
    var open: std.ArrayList(u32) = .empty;
    var lexer = parser.Lexer.init(text);
    while (true) {
        const t = lexer.next();
        switch (t.cat) {
            .eof => break,
            .lbrace => try open.append(arena, t.pos),
            .rbrace => if (open.pop()) |start| try out.append(arena, .{ .start = start, .end = t.pos + 1 }),
            else => {},
        }
    }
    return out.items;
}

/// Each line trimmed of trailing spaces and indented four spaces a brace;
/// null when the text is so already.
pub fn format(arena: Allocator, path: []const u8, text: []const u8) !?[]const u8 {
    _ = path;
    var out: std.ArrayList(u8) = .empty;
    var depth: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |raw| {
        if (!first) try out.append(arena, '\n');
        first = false;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len > 0 and line[0] == '}') depth -|= 1;
        if (line.len > 0) try out.appendNTimes(arena, ' ', 4 * depth);
        try out.appendSlice(arena, line);
        if (line.len > 0 and line[line.len - 1] == '{') depth += 1;
    }
    return if (std.mem.eql(u8, out.items, text)) null else out.items;
}

/// Tally has no modules: every `use` names `<name>.tally` beside the file,
/// as the grammar's `import` line says.
pub fn resolveImport(arena: Allocator, from: []const u8, name: []const u8) !?[]const u8 {
    _ = arena;
    _ = from;
    _ = name;
    return null;
}

// --- The analysis --------------------------------------------------------------

const Type = enum(lsp.TypeId) { unknown, int, str, @"fn" };

const Decl = struct {
    name: []const u8,
    kind: lsp.SymbolKind,
    span: lsp.Span,
    /// Functions: the parameter names.
    params: []const []const u8 = &.{},
    type: Type = .unknown,
    detail: []const u8 = "",
    doc: []const u8 = "",
    /// Modules: the file's index.
    file: u32 = 0,
};

/// A name in the text and the declaration it names.
const Ref = struct { span: lsp.Span, decl: u32 };

/// An expression and its type.
const Expr = struct { span: lsp.Span, type: Type };

/// The parentheses of a call to a known function, and its commas.
const Call = struct { path: []const u8, open: u32, close: u32, callee: u32, commas: []const u32 };

const File = struct {
    path: []const u8,
    text: []const u8,
    root: Sexp,
    p: *parser.BaseParser,
    /// The declarations of the file: its functions, `let`s and `use`s.
    top: std.ArrayList(u32) = .empty,
};

pub const Analysis = struct {
    files: []File,
    decls: []const Decl,
    refs: []const Ref,
    exprs: []const Expr,
    calls: []const Call,
    /// The files of the root's directory a `use` can name.
    modules: []const []const u8,
};

const Builder = struct {
    arena: Allocator,
    overlay: lsp.Overlay,
    dir: []const u8,
    files: std.ArrayList(File) = .empty,
    decls: std.ArrayList(Decl) = .empty,
    refs: std.ArrayList(Ref) = .empty,
    exprs: std.ArrayList(Expr) = .empty,
    calls: std.ArrayList(Call) = .empty,
    diagnostics: std.ArrayList(lsp.Diagnostic) = .empty,

    /// The index of the file of module `name`, read and parsed once; null
    /// when it cannot be read or does not parse.
    fn load(b: *Builder, path: []const u8) error{OutOfMemory}!?u32 {
        for (b.files.items, 0..) |f, i| if (std.mem.eql(u8, f.path, path)) return @intCast(i);
        const text = b.overlay.read(b.arena, path) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        const p = try b.arena.create(parser.BaseParser);
        p.* = parser.BaseParser.init(b.arena, text);
        const root = p.parse(.program) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        const index: u32 = @intCast(b.files.items.len);
        try b.files.append(b.arena, .{ .path = path, .text = text, .root = root, .p = p });
        try b.declare(index);
        return index;
    }

    fn span(b: *Builder, file: u32, s: Sexp) lsp.Span {
        const f = b.files.items[file];
        return switch (s) {
            .src => |leaf| .{ .path = f.path, .start = leaf.pos, .end = leaf.pos + leaf.len },
            else => blk: {
                const sp = f.p.span(s);
                break :blk .{ .path = f.path, .start = sp.start, .end = sp.end };
            },
        };
    }

    fn add(b: *Builder, d: Decl) !u32 {
        try b.decls.append(b.arena, d);
        const index: u32 = @intCast(b.decls.items.len - 1);
        try b.refs.append(b.arena, .{ .span = d.span, .decl = index });
        return index;
    }

    /// The file's declarations; each `use` loads its module.
    fn declare(b: *Builder, file: u32) error{OutOfMemory}!void {
        const root = b.files.items[file].root;
        const text = b.files.items[file].text;
        for (root.items()[1..]) |stmt| {
            const tag = stmt.kind() orelse continue;
            const name = stmt.items()[1];
            const at = b.span(file, name);
            const decl: Decl = switch (tag) {
                .@"fn" => blk: {
                    var params: std.ArrayList([]const u8) = .empty;
                    for (stmt.items()[2].items()[1..]) |param| try params.append(b.arena, param.getText(text));
                    break :blk .{ .name = name.getText(text), .kind = .function, .span = at, .params = params.items, .type = .@"fn", .detail = try b.arena.print("fn {s}", .{try signature(b.arena, text, stmt)}), .doc = docAbove(text, at.start) };
                },
                .let => .{ .name = name.getText(text), .kind = .variable, .span = at, .doc = docAbove(text, at.start) },
                .use => blk: {
                    const path = try std.fs.path.join(b.arena, &.{ b.dir, try b.arena.print("{s}.tally", .{name.getText(text)}) });
                    const module = try b.load(path) orelse {
                        try b.diagnostics.append(b.arena, .{ .span = at, .message = try b.arena.print("no module {s}: {s} cannot be read or does not parse", .{ name.getText(text), path }) });
                        continue;
                    };
                    break :blk .{ .name = name.getText(text), .kind = .module, .span = at, .detail = try b.arena.print("module {s}", .{name.getText(text)}), .file = module };
                },
                else => continue,
            };
            const index = try b.add(decl);
            try b.files.items[file].top.append(b.arena, index);
        }
    }

    fn find(b: *Builder, scope: []const u32, name: []const u8) ?u32 {
        var i = scope.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, b.decls.items[scope[i]].name, name)) return scope[i];
        }
        return null;
    }

    /// Resolve the names of every statement of the file.
    fn resolve(b: *Builder, file: u32) !void {
        const root = b.files.items[file].root;
        var scope: std.ArrayList(u32) = .empty;
        try scope.appendSlice(b.arena, b.files.items[file].top.items);
        for (root.items()[1..]) |stmt| try b.statement(file, stmt, &scope, true);
    }

    fn statement(b: *Builder, file: u32, stmt: Sexp, scope: *std.ArrayList(u32), top: bool) error{OutOfMemory}!void {
        const tag = stmt.kind() orelse return;
        const text = b.files.items[file].text;
        switch (tag) {
            .@"fn" => {
                const mark = scope.items.len;
                for (stmt.items()[2].items()[1..]) |param| {
                    const index = try b.add(.{ .name = param.getText(text), .kind = .variable, .span = b.span(file, param), .detail = try b.arena.print("parameter {s}", .{param.getText(text)}) });
                    try scope.append(b.arena, index);
                }
                for (stmt.items()[3].items()[1..]) |inner| try b.statement(file, inner, scope, false);
                scope.items.len = mark;
            },
            .let => {
                const t = try b.expression(file, stmt.items()[2], scope.items);
                const name = stmt.items()[1];
                if (top) {
                    const index = b.find(scope.items, name.getText(text)).?;
                    b.decls.items[index].type = t;
                    b.decls.items[index].detail = try letDetail(b.arena, name.getText(text), t);
                } else {
                    const index = try b.add(.{ .name = name.getText(text), .kind = .variable, .span = b.span(file, name), .type = t, .detail = try letDetail(b.arena, name.getText(text), t) });
                    try scope.append(b.arena, index);
                }
            },
            .@"return" => _ = try b.expression(file, stmt.items()[1], scope.items),
            .use => {},
            else => _ = try b.expression(file, stmt, scope.items),
        }
    }

    fn expression(b: *Builder, file: u32, e: Sexp, scope: []const u32) error{OutOfMemory}!Type {
        const text = b.files.items[file].text;
        const tag = e.kind() orelse return .unknown;
        const t: Type = switch (tag) {
            .num => .int,
            .str => .str,
            .name => blk: {
                const leaf = e.items()[1];
                const index = b.find(scope, leaf.getText(text)) orelse {
                    try b.diagnostics.append(b.arena, .{ .span = b.span(file, leaf), .message = try b.arena.print("undefined name {s}", .{leaf.getText(text)}) });
                    break :blk .unknown;
                };
                try b.refs.append(b.arena, .{ .span = b.span(file, leaf), .decl = index });
                break :blk b.decls.items[index].type;
            },
            .member => blk: {
                const base = e.items()[1];
                const field = e.items()[2];
                _ = try b.expression(file, base, scope);
                const module = b.moduleOf(file, base, scope) orelse break :blk .unknown;
                for (b.files.items[module].top.items) |index| if (std.mem.eql(u8, b.decls.items[index].name, field.getText(text))) {
                    try b.refs.append(b.arena, .{ .span = b.span(file, field), .decl = index });
                    break :blk b.decls.items[index].type;
                };
                try b.diagnostics.append(b.arena, .{ .span = b.span(file, field), .message = try b.arena.print("{s} has no {s}", .{ base.items()[1].getText(text), field.getText(text) }) });
                break :blk .unknown;
            },
            .call => blk: {
                const callee = e.items()[1];
                _ = try b.expression(file, callee, scope);
                const args = e.items()[2..];
                for (args) |arg| _ = try b.expression(file, arg, scope);
                const index = b.calleeOf(file, callee, scope) orelse break :blk .unknown;
                const d = b.decls.items[index];
                if (d.kind != .function) break :blk .unknown;
                if (args.len != d.params.len)
                    try b.diagnostics.append(b.arena, .{ .span = b.span(file, e), .message = try b.arena.print("{s} takes {d} argument{s}, not {d}", .{ d.name, d.params.len, if (d.params.len == 1) "" else "s", args.len }), .notes = try b.arena.dupe(lsp.Note, &.{.{ .span = d.span, .message = "declared here" }}) });
                // The parentheses and commas, from the tokens after the callee.
                const all = b.span(file, e);
                const open: u32 = @intCast(std.mem.findScalarPos(u8, text, b.span(file, callee).end, '(').?);
                var commas: std.ArrayList(u32) = .empty;
                var depth: u32 = 0;
                for (text[open + 1 .. all.end - 1], open + 1..) |c, i| switch (c) {
                    '(' => depth += 1,
                    ')' => depth -= 1,
                    ',' => if (depth == 0) try commas.append(b.arena, @intCast(i)),
                    else => {},
                };
                try b.calls.append(b.arena, .{ .path = all.path, .open = open, .close = all.end - 1, .callee = index, .commas = commas.items });
                break :blk .unknown;
            },
            else => blk: {
                // An operator: both sides ints, or for `+` both strings.
                const left = try b.expression(file, e.items()[1], scope);
                const right = try b.expression(file, e.items()[2], scope);
                if (left == .int and right == .int) break :blk .int;
                if (tag == .@"+" and left == .str and right == .str) break :blk .str;
                break :blk .unknown;
            },
        };
        try b.exprs.append(b.arena, .{ .span = b.span(file, e), .type = t });
        return t;
    }

    /// The file of the module a `name` expression names.
    fn moduleOf(b: *Builder, file: u32, e: Sexp, scope: []const u32) ?u32 {
        if (!e.isKind(.name)) return null;
        const index = b.find(scope, e.items()[1].getText(b.files.items[file].text)) orelse return null;
        const d = b.decls.items[index];
        return if (d.kind == .module) d.file else null;
    }

    fn calleeOf(b: *Builder, file: u32, callee: Sexp, scope: []const u32) ?u32 {
        const text = b.files.items[file].text;
        if (callee.isKind(.name)) return b.find(scope, callee.items()[1].getText(text));
        if (!callee.isKind(.member)) return null;
        const module = b.moduleOf(file, callee.items()[1], scope) orelse return null;
        for (b.files.items[module].top.items) |index| if (std.mem.eql(u8, b.decls.items[index].name, callee.items()[2].getText(text))) return index;
        return null;
    }
};

/// `let name: type`, or `let name` when the type is not known.
fn letDetail(arena: Allocator, name: []const u8, t: Type) error{OutOfMemory}![]const u8 {
    if (t == .unknown) return arena.print("let {s}", .{name});
    return arena.print("let {s}: {s}", .{ name, @tagName(t) });
}

/// `name(a, b)` of a `fn` statement.
fn signature(arena: Allocator, text: []const u8, stmt: Sexp) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, stmt.items()[1].getText(text));
    try out.append(arena, '(');
    for (stmt.items()[2].items()[1..], 0..) |param, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        try out.appendSlice(arena, param.getText(text));
    }
    try out.append(arena, ')');
    return out.items;
}

/// The comment on the line above the line of `at`, without its `# `.
fn docAbove(text: []const u8, at: u32) []const u8 {
    const line = if (std.mem.findScalarLast(u8, text[0..at], '\n')) |i| i + 1 else 0;
    if (line == 0) return "";
    const above = if (std.mem.findScalarLast(u8, text[0 .. line - 1], '\n')) |i| i + 1 else 0;
    if (!std.mem.startsWith(u8, text[above..], "# ")) return "";
    return text[above + 2 .. line - 1];
}

pub fn analyze(arena: Allocator, root: []const u8, overlay: lsp.Overlay) !lsp.Analyzed(Analysis) {
    var b: Builder = .{ .arena = arena, .overlay = overlay, .dir = std.fs.path.dirname(root) orelse "." };
    // A program whose root cannot be read or parsed has no analysis.
    _ = try b.load(root) orelse return error.NoProgram;
    // A module before the files that use it, so its types are known.
    var i = b.files.items.len;
    while (i > 0) {
        i -= 1;
        try b.resolve(@intCast(i));
    }
    var names: std.ArrayList([]const u8) = .empty;
    if (std.Io.Dir.cwd().openDir(overlay.io, b.dir, .{ .iterate = true })) |dir| {
        defer dir.close(overlay.io);
        var it = dir.iterate();
        while (try it.next(overlay.io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".tally")) continue;
            try names.append(arena, try arena.dupe(u8, entry.name[0 .. entry.name.len - ".tally".len]));
        }
    } else |_| {}
    std.mem.sort([]const u8, names.items, {}, lessThan);
    var files: std.ArrayList([]const u8) = .empty;
    for (b.files.items) |f| try files.append(arena, f.path);
    return .{
        .analysis = .{ .files = b.files.items, .decls = b.decls.items, .refs = b.refs.items, .exprs = b.exprs.items, .calls = b.calls.items, .modules = names.items },
        .diagnostics = b.diagnostics.items,
        .files = files.items,
    };
}

fn lessThan(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.order(u8, x, y) == .lt;
}

/// A declaration as a symbol; its id is its file and offset.
fn symbolOf(a: *Analysis, arena: Allocator, index: u32) !lsp.Symbol {
    const d = a.decls[index];
    return .{ .id = try arena.print("{s}:{d}", .{ d.span.path, d.span.start }), .name = d.name, .kind = d.kind, .decl = d.span, .detail = d.detail, .doc = d.doc };
}

pub fn symbolAt(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.Symbol {
    for (a.refs) |r| if (std.mem.eql(u8, r.span.path, at.path) and r.span.start <= at.offset and at.offset < r.span.end)
        return try symbolOf(a, arena, r.decl);
    return null;
}

pub fn typeAt(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.TypeId {
    _ = arena;
    var best: ?Expr = null;
    for (a.exprs) |e| if (std.mem.eql(u8, e.span.path, at.path) and e.span.start <= at.offset and at.offset < e.span.end and e.type != .unknown) {
        if (best == null or e.span.end - e.span.start < best.?.span.end - best.?.span.start) best = e;
    };
    return if (best) |e| @backingInt(e.type) else null;
}

pub fn describe(a: *Analysis, arena: Allocator, subject: lsp.Subject) !?lsp.Description {
    _ = a;
    switch (subject) {
        .symbol => |s| {
            const code = try arena.print("```tally\n{s}\n```", .{s.detail});
            return .{ .markdown = if (s.doc.len > 0) try arena.print("{s}\n\n{s}", .{ code, s.doc }) else code, .decl = s.decl };
        },
        .type => |t| return .{ .markdown = try arena.print("`{s}`", .{@tagName(@as(Type, @fromBackingInt(@intCast(t))))}) },
    }
}

/// The word before `at` and the byte before it.
fn wordBefore(text: []const u8, at: u32) struct { start: u32, before: ?u8 } {
    var i: u32 = @min(at, @as(u32, @intCast(text.len)));
    while (i > 0 and language.isWord(text[i - 1])) i -= 1;
    return .{ .start = i, .before = if (i > 0) text[i - 1] else null };
}

fn fileOf(a: *Analysis, path: []const u8) ?*File {
    for (a.files) |*f| if (std.mem.eql(u8, f.path, path)) return f;
    return null;
}

pub fn members(a: *Analysis, arena: Allocator, at: lsp.Pos) !?[]const lsp.Symbol {
    const f = fileOf(a, at.path) orelse return null;
    const w = wordBefore(f.text, at.offset);
    if (w.before != '.') return null;
    const base = wordBefore(f.text, w.start - 1);
    const name = f.text[base.start .. w.start - 1];
    var out: std.ArrayList(lsp.Symbol) = .empty;
    for (f.top.items) |index| {
        const d = a.decls[index];
        if (d.kind != .module or !std.mem.eql(u8, d.name, name)) continue;
        for (a.files[d.file].top.items) |m| try out.append(arena, try symbolOf(a, arena, m));
    }
    return out.items;
}

pub fn modules(a: *Analysis, arena: Allocator, at: lsp.Pos) !?[]const []const u8 {
    _ = arena;
    const f = fileOf(a, at.path) orelse return null;
    const w = wordBefore(f.text, at.offset);
    const line = if (std.mem.findScalarLast(u8, f.text[0..w.start], '\n')) |i| i + 1 else 0;
    if (!std.mem.eql(u8, std.mem.trim(u8, f.text[line..w.start], " \t"), "use")) return null;
    return a.modules;
}

pub fn visible(a: *Analysis, arena: Allocator, at: lsp.Pos) ![]const lsp.Symbol {
    const f = fileOf(a, at.path) orelse return &.{};
    var out: std.ArrayList(lsp.Symbol) = .empty;
    for (f.top.items) |index| try out.append(arena, try symbolOf(a, arena, index));
    // The parameters of the function around `at`.
    for (f.root.items()[1..]) |stmt| {
        if (!stmt.isKind(.@"fn")) continue;
        const sp = f.p.span(stmt);
        if (at.offset < sp.start or at.offset > sp.end) continue;
        for (stmt.items()[2].items()[1..]) |param| {
            for (a.refs) |r| if (std.mem.eql(u8, r.span.path, f.path) and r.span.start == param.src.pos) {
                try out.append(arena, try symbolOf(a, arena, r.decl));
                break;
            };
        }
    }
    return out.items;
}

pub fn signatures(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.SignatureHelp {
    var best: ?Call = null;
    for (a.calls) |c| if (std.mem.eql(u8, c.path, at.path) and c.open < at.offset and at.offset <= c.close) {
        if (best == null or c.open > best.?.open) best = c;
    };
    const c = best orelse return null;
    const d = a.decls[c.callee];
    var params: std.ArrayList(lsp.Param) = .empty;
    for (d.params) |p| try params.append(arena, .{ .name = p });
    var param: u32 = 0;
    for (c.commas) |comma| {
        if (comma < at.offset) param += 1;
    }
    const sig: lsp.Signature = .{ .label = d.detail["fn ".len..], .params = params.items, .doc = d.doc };
    return .{ .signatures = try arena.dupe(lsp.Signature, &.{sig}), .param = param };
}

/// `references` is left to lsp.zig, which asks `symbolAt` at each name.
pub const references = lsp.todo;

/// A module is its file's name, so it is not renamed here.
pub fn renamable(a: *Analysis, s: lsp.Symbol) bool {
    _ = a;
    return s.kind != .module;
}

pub const completionTriggers: []const []const u8 = &.{"."};
