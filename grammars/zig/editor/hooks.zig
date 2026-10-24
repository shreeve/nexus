//! hooks.zig: what the Zig language server knows beyond the grammar.
//!
//! The grammar's `@lsp` gives the names: the outline, definition,
//! references, highlights, rename, the names in scope and after `.`, and
//! hover, across files. These functions add what only Zig itself knows,
//! by running the Zig standard library of the Zig that builds the server
//! (which must be 0.17.0) in process:
//!
//! - `parseDiagnostics`: Zig's own errors as you type, in Zig's words and
//!   at Zig's positions. Every error `std.zig.Ast.parse` reports, with its
//!   recovery; a file that parses gets `std.zig.AstGen`'s errors instead,
//!   as `zig ast-check` reports them (unused and shadowing names, an
//!   undeclared identifier, a `var` never mutated, ...).
//! - `format`: Format Document as `zig fmt` formats, by `Ast.render`. It
//!   refuses a file with syntax errors, and any edit after which the
//!   grammar's parser builds another tree (spans aside): the guard that
//!   keeps the four `std.zig.Ast` helper bugs grammars/zig/README.md
//!   names (T5, T7, T8, T9) from changing the program.
//! - `resolveImport`: `@import("std")` is the std.zig of the Zig that
//!   built the server, as the `zig env` output saved beside the server
//!   (`zig-env.zon`, which `editor/install` writes) names its `std_dir`,
//!   else of the `zig` on the server's PATH, unless the client's
//!   `modules` setting names the file.
//!
//! What a value's type is, the members of a value whose type needs
//! inference (`list.` for an `std.ArrayList(u8)`), and type errors need
//! the compiler's analysis, which nothing here runs.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const lsp = @import("lsp.zig");
const parser = @import("parser.zig");

// --- The parse ---------------------------------------------------------------

/// Ast.parse's errors when the file has any, each with the notes after
/// it; else AstGen's, each with its notes.
pub fn parseDiagnostics(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Diagnostic {
    const source = try arena.dupeSentinel(u8, text, 0);
    const tree = try Ast.parse(arena, source, .{});
    var out: std.ArrayList(lsp.Diagnostic) = .empty;
    if (tree.errors.len > 0) {
        var notes: std.ArrayList(lsp.Note) = .empty;
        var i = tree.errors.len;
        // Backwards, so the notes after an error are in hand at the error.
        while (i > 0) {
            i -= 1;
            const err = tree.errors[i];
            const span = astErrorSpan(tree, path, err);
            var msg: std.Io.Writer.Allocating = .init(arena);
            tree.renderError(err, &msg.writer) catch return error.OutOfMemory;
            if (err.is_note) {
                try notes.insert(arena, 0, .{ .span = span, .message = msg.written() });
                continue;
            }
            try out.insert(arena, 0, .{ .span = span, .message = msg.written(), .notes = try notes.toOwnedSlice(arena) });
        }
        return out.items;
    }
    const zir = try std.zig.AstGen.generate(arena, tree);
    if (!zir.hasCompileErrors()) return &.{};
    var wip: std.zig.ErrorBundle.Wip = try .init(arena);
    try wip.addZirErrorMessages(zir, tree, source, path);
    const bundle = try wip.toOwnedBundle("");
    for (bundle.getMessages()) |m| {
        const em = bundle.getErrorMessage(m);
        const notes = bundle.getNotes(m);
        const list = try arena.alloc(lsp.Note, notes.len);
        for (list, notes) |*n, ni| {
            const note = bundle.getErrorMessage(ni);
            n.* = .{ .span = bundleSpan(bundle, path, note.src_loc), .message = bundle.nullTerminatedString(note.msg) };
        }
        try out.append(arena, .{ .span = bundleSpan(bundle, path, em.src_loc), .message = bundle.nullTerminatedString(em.msg), .notes = list });
    }
    return out.items;
}

/// Where Ast reports a parse error: its token, or, when the error is after
/// the token before (`expected ';' after declaration`), the end of that one.
fn astErrorSpan(tree: Ast, path: []const u8, err: Ast.Error) lsp.Span {
    const start = tree.tokenStart(err.token);
    const len: u32 = @intCast(tree.tokenSlice(err.token).len);
    if (err.token_is_prev) return .{ .path = path, .start = start + len, .end = start + len };
    return .{ .path = path, .start = start, .end = start + len };
}

fn bundleSpan(bundle: std.zig.ErrorBundle, path: []const u8, loc: std.zig.ErrorBundle.SourceLocationIndex) lsp.Span {
    if (loc == .none) return .{ .path = path, .start = 0, .end = 0 };
    const sl = bundle.getSourceLocation(loc);
    return .{ .path = path, .start = sl.span_start, .end = sl.span_end };
}

/// The file as `zig fmt` formats it; null when it is formatted already.
/// error.SyntaxErrors when Ast.parse reports an error, as `zig fmt`
/// refuses such a file; error.TreeChanged when the grammar's parser
/// rejects the formatted text, or builds another tree from it than from
/// the text.
pub fn format(arena: Allocator, path: []const u8, text: []const u8) !?[]const u8 {
    _ = path;
    const source = try arena.dupeSentinel(u8, text, 0);
    const tree = try Ast.parse(arena, source, .{});
    if (tree.errors.len > 0) return error.SyntaxErrors;
    const formatted = try tree.renderAlloc(arena);
    if (std.mem.eql(u8, formatted, text)) return null;
    const before = try canonicalTree(arena, text);
    const after = canonicalTree(arena, formatted) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TreeChanged,
    };
    if (!std.mem.eql(u8, before, after)) return error.TreeChanged;
    return formatted;
}

/// The grammar's tree of `text` without its spans: kinds, roles in slot
/// order and leaves, each leaf as `zig fmt` writes its token when the
/// program is the same: a quoted identifier (`@"name"`) as the name it
/// stands for, since `zig fmt` unquotes one that needs no quotes, and a
/// doc comment without the blanks at its end, which `zig fmt` drops.
/// error.ParseError when the grammar's parser rejects the text.
pub fn canonicalTree(arena: Allocator, text: []const u8) ![]const u8 {
    var r = try parser.parseRoot(arena, text);
    const base: *parser.BaseParser = if (parser.Parser == parser.BaseParser) &r.parser else &r.parser.base;
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    // An explicit stack: a long operator chain is a tree as deep as it is long.
    var stack: std.ArrayList([]const parser.Sexp) = .empty;
    try stack.append(arena, &.{r.sexp});
    while (stack.items.len > 0) {
        const top = &stack.items[stack.items.len - 1];
        if (top.len == 0) {
            _ = stack.pop();
            if (stack.items.len > 0) w.writeAll(")") catch return error.OutOfMemory;
            continue;
        }
        const s = top.*[0];
        top.* = top.*[1..];
        w.writeAll(" ") catch return error.OutOfMemory;
        switch (s) {
            .nil => w.writeAll("_") catch return error.OutOfMemory,
            .tag => |t| w.writeAll(@tagName(t)) catch return error.OutOfMemory,
            .str => |x| w.print("\"{s}\"", .{x}) catch return error.OutOfMemory,
            .src => {
                const leaf = base.leafText(s);
                const name = if (std.mem.startsWith(u8, leaf, "@\""))
                    std.zig.string_literal.parseAlloc(arena, leaf[1..]) catch leaf
                else if (std.mem.startsWith(u8, leaf, "///") or std.mem.startsWith(u8, leaf, "//!"))
                    std.mem.trimEnd(u8, leaf, &std.ascii.whitespace)
                else
                    leaf;
                w.print("{s}#{d}", .{ name, s.src.id }) catch return error.OutOfMemory;
            },
            .list => |l| {
                w.writeAll("(") catch return error.OutOfMemory;
                try stack.append(arena, l.items());
            },
        }
    }
    return out.written();
}

/// `std` is the standard library `stdDir` names; every other module name
/// is a path beside the importing file.
pub fn resolveImport(arena: Allocator, from: []const u8, name: []const u8) !?[]const u8 {
    _ = from;
    if (!std.mem.eql(u8, name, "std")) return null;
    const dir = stdDir() orelse return null;
    return try std.fs.path.join(arena, &.{ dir, "std.zig" });
}

/// The `std_dir` of the Zig that built the server, from the `zig env`
/// output saved beside the server's executable as `zig-env.zon`, when its
/// std.zig exists; else the `std_dir` that `zig env` prints for the `zig`
/// on PATH. Asked once; null when neither names one.
fn stdDir() ?[]const u8 {
    const lock_io = std.Options.debug_io;
    std_dir_lock.lockUncancelable(lock_io);
    defer std_dir_lock.unlock(lock_io);
    if (!std_dir_asked) {
        std_dir_asked = true;
        // The hooks take no `Io`. Start-up gives the process's environment
        // to std's debug `Io` (std.Options.debug_threaded_io), which cannot
        // run a process itself (it allocates nothing), so an `Io` of its
        // own, with that environment, finds `zig` on the server's PATH.
        var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{
            .environ = std.Options.debug_threaded_io.?.environ.process_environ,
        });
        defer threaded.deinit();
        const io = threaded.io();
        std_dir = savedStdDir(io) orelse (askStdDir(io) catch null);
    }
    return std_dir;
}

var std_dir_lock: std.Io.Mutex = .init;
var std_dir_asked = false;
var std_dir: ?[]const u8 = null;

/// The `std_dir` that `zig-env.zon` beside the executable names, when its
/// std.zig exists: a Zig removed since the build names none.
fn savedStdDir(io: std.Io) ?[]const u8 {
    const gpa = std.heap.page_allocator;
    const exe_dir = std.process.executableDirPathAlloc(io, gpa) catch return null;
    defer gpa.free(exe_dir);
    const path = std.fs.path.join(gpa, &.{ exe_dir, "zig-env.zon" }) catch return null;
    defer gpa.free(path);
    const zon = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20)) catch return null;
    defer gpa.free(zon);
    const dir = envStdDir(gpa, zon) orelse return null;
    const std_zig = std.fs.path.join(gpa, &.{ dir, "std.zig" }) catch return null;
    defer gpa.free(std_zig);
    std.Io.Dir.cwd().access(io, std_zig, .{}) catch {
        gpa.free(dir);
        return null;
    };
    return dir;
}

fn askStdDir(io: std.Io) !?[]const u8 {
    const gpa = std.heap.page_allocator;
    const run = try std.process.run(gpa, io, .{ .argv = &.{ "zig", "env" }, .stdout_limit = .limited(1 << 20) });
    defer gpa.free(run.stderr);
    defer gpa.free(run.stdout);
    if (run.term != .exited or run.term.exited != 0) return null;
    return envStdDir(gpa, run.stdout);
}

/// The `std_dir` of the ZON `zig env` prints: `.std_dir = "/path/to/lib/std",`.
fn envStdDir(gpa: Allocator, zon: []const u8) ?[]const u8 {
    const key = ".std_dir = ";
    const at = std.mem.find(u8, zon, key) orelse return null;
    const rest = zon[at + key.len ..];
    const end = std.mem.findScalar(u8, rest, '\n') orelse rest.len;
    const literal = std.mem.trimEnd(u8, rest[0..end], ",");
    return std.zig.string_literal.parseAlloc(gpa, literal) catch null;
}

// --- The grammar's answers: semantic tokens, the outline and folds ------------

pub const tokens = lsp.todo;
pub const symbols = lsp.todo;
pub const folds = lsp.todo;

// --- The analysis: none, so no type errors, types or members of values ------

pub const Analysis = struct {};
pub const analyze = lsp.todo;
pub const symbolAt = lsp.todo;
pub const typeAt = lsp.todo;
pub const describe = lsp.todo;
pub const members = lsp.todo;
pub const modules = lsp.todo;
pub const visible = lsp.todo;
pub const signatures = lsp.todo;
pub const references = lsp.todo;
pub const renamable = lsp.todo;
pub const completionTriggers: []const []const u8 = &.{};
