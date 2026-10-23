//! Checks the members and imports the grammar's `@lsp` resolves
//! (scopes.zig's `Resolver`, the generated language server's) against a
//! resolution of its own over std.zig.Ast, over a corpus. Built by
//! grammars/zig/compare-members beside the server `nexus --editor`
//! writes; see that script for usage.
//!
//!   compare_members [--list FILE] [--module NAME=PATH]... [--show] PATH...
//!
//! The reference reads each file with Ast.parse and finds what a name
//! after `.` names by itself: the declarations of every container (a
//! file, `struct`, `enum`, `union`, `opaque`), an identifier as the
//! nearest enclosing container's declaration of its name, `@import` as a
//! file (a module of `--module`, else a path beside the importing file),
//! and a declaration's value (else its type) as what it denotes; a `pub`
//! declaration is seen from other files. It never asks the engine.
//!
//! For each member (a field access's name) of each input, the engine's
//! answer and the reference's are compared:
//!   - both name the same declaration: resolved (in the file itself, or
//!     through an import into another);
//!   - the engine names a declaration the reference cannot reach (its
//!     chain starts at a local, a parameter or a field's type): checked
//!     only to be a declaration of that name in that file;
//!   - neither answers: unresolved by design (a call's result, a generic,
//!     a pointer, `@This()`: values whose type needs inference);
//!   - the reference answers and the engine does not: missed;
//!   - anything else, or a declaration that is no declaration of the
//!     name: wrong.
//! Each `@import` is compared the same way, by the file it names. Prints
//! each wrong answer and a summary; exits 1 when there is any.

const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const scopes = @import("scopes.zig");

const Counts = struct {
    files: usize = 0,
    rejected: usize = 0,
    members: usize = 0,
    same_file: usize = 0,
    through_imports: usize = 0,
    engine_only: usize = 0,
    by_design: usize = 0,
    missed: usize = 0,
    wrong: usize = 0,
    imports: usize = 0,
    imports_resolved: usize = 0,
    imports_unresolved: usize = 0,
    imports_wrong: usize = 0,
    index_ns: u64 = 0,
    resolve_ns: u64 = 0,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();

    var paths: std.ArrayList([]const u8) = .empty;
    var modules: std.StringHashMapUnmanaged([]const u8) = .empty;
    var show = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--list") and i + 1 < args.len) {
            i += 1;
            const data = try cwd.readFileAlloc(io, args[i], arena, .unlimited);
            var it = std.mem.tokenizeScalar(u8, data, '\n');
            while (it.next()) |line| try paths.append(arena, line);
        } else if (std.mem.eql(u8, arg, "--module") and i + 1 < args.len) {
            i += 1;
            const eq = std.mem.findScalar(u8, args[i], '=') orelse return error.BadModule;
            try modules.put(arena, args[i][0..eq], try std.fs.path.resolveAlloc(arena, &.{args[i][eq + 1 ..]}));
        } else if (std.mem.eql(u8, arg, "--show")) {
            show = true;
        } else try paths.append(arena, arg);
    }

    var buf: [64 * 1024]u8 = undefined;
    var fw = Io.File.stdout().writerStreaming(io, &buf);
    const out = &fw.interface;
    var disk: Disk = .{ .arena = arena, .io = io, .modules = &modules };
    var ref: Ref = .{ .arena = arena, .io = io, .modules = &modules };
    var r: scopes.Resolver = .init(arena, disk.world());
    var c: Counts = .{};
    for (paths.items) |p| {
        const path = try std.fs.path.resolveAlloc(arena, &.{p});
        try compareFile(&r, &disk, &ref, out, path, &c, show);
    }

    const wrong = c.wrong + c.imports_wrong;
    try out.print(
        \\{d} files ({d} skipped: not read or not accepted by Ast.parse)
        \\members: {d}; resolved {d} in their own file and {d} through imports; {d} more the reference cannot reach, each a declaration of its name
        \\unresolved by design (values whose type needs inference): {d}; missed (the reference resolves them): {d}; wrong: {d}
        \\imports: {d}; resolved {d}, unresolved {d} (modules not given), wrong {d}
        \\wrong in all: {d}
        \\index: {d} ms; resolution: {d} ms
        \\
    , .{
        c.files,                           c.rejected,           c.members,       c.same_file, c.through_imports,
        c.engine_only,                     c.by_design,          c.missed,        c.wrong,     c.imports,
        c.imports_resolved,                c.imports_unresolved, c.imports_wrong, wrong,       c.index_ns / std.time.ns_per_ms,
        c.resolve_ns / std.time.ns_per_ms,
    });
    try out.flush();
    if (wrong > 0) std.process.exit(1);
}

fn compareFile(r: *scopes.Resolver, disk: *Disk, ref: *Ref, out: *Io.Writer, path: []const u8, c: *Counts, show: bool) !void {
    const parsed = (try ref.parsed(path)) orelse {
        c.rejected += 1;
        return;
    };
    if (parsed.tree.errors.len > 0) {
        c.rejected += 1;
        return;
    }
    const t0 = Io.Clock.awake.now(disk.io);
    const f = (try r.load(path)) orelse {
        c.rejected += 1;
        return;
    };
    c.index_ns += @intCast(t0.untilNow(disk.io, .awake).toNanoseconds());
    c.files += 1;
    const tree = &parsed.tree;
    const arena = ref.arena;
    var problems: std.ArrayList(u8) = .empty;

    // Ast's field accesses, by the start of the name.
    var accesses: std.AutoHashMapUnmanaged(u32, Ast.Node.Index) = .empty;
    var calls: std.AutoHashMapUnmanaged(u32, Ast.Node.Index) = .empty;
    for (0..tree.nodes.len) |n| {
        const node: Ast.Node.Index = @fromBackingInt(@as(u32, @intCast(n)));
        switch (tree.nodeTag(node)) {
            .field_access => try accesses.put(arena, tree.tokenStart(tree.nodeData(node).node_and_token[1]), node),
            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {
                if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import")) continue;
                var pb: [2]Ast.Node.Index = undefined;
                const params = tree.builtinCallParams(&pb, node).?;
                if (params.len != 1 or tree.nodeTag(params[0]) != .string_literal) continue;
                try calls.put(arena, tree.tokenStart(tree.nodeMainToken(params[0])), node);
            },
            else => {},
        }
    }

    const t1 = Io.Clock.awake.now(disk.io);
    for (f.ix.members, 0..) |m, n| {
        if (m.start == m.end) continue;
        c.members += 1;
        const name = f.ix.text[m.start..m.end];
        const line = lineOf(f.ix.text, m.start);
        const engine = try r.memberDef(f, @intCast(n), 0);
        const node = accesses.get(m.start) orelse {
            c.wrong += 1;
            try problems.print(arena, "{s}:{d}: the engine's member '{s}' is no field access to Ast\n", .{ path, line, name });
            continue;
        };
        const want = try ref.memberAt(path, node, 0);
        if (engine) |g| {
            const got: Decl = .{ .path = g.file.path, .start = g.file.ix.defs[g.def].start };
            if (want) |w| {
                if (std.mem.eql(u8, w.path, got.path) and w.start == got.start) {
                    if (std.mem.eql(u8, got.path, path)) c.same_file += 1 else c.through_imports += 1;
                } else {
                    c.wrong += 1;
                    try problems.print(arena, "{s}:{d}: '{s}' names {s}:{d}; the reference, {s}:{d}\n", .{ path, line, name, got.path, try ref.lineAt(got), w.path, try ref.lineAt(w) });
                }
            } else if (try ref.isDecl(got, name)) {
                c.engine_only += 1;
            } else {
                c.wrong += 1;
                try problems.print(arena, "{s}:{d}: '{s}' names {s}:{d}, which declares no '{s}'\n", .{ path, line, name, got.path, try ref.lineAt(got), name });
            }
        } else if (want) |w| {
            c.missed += 1;
            if (show) try problems.print(arena, "{s}:{d}: '{s}' is unresolved; the reference names {s}:{d}\n", .{ path, line, name, w.path, try ref.lineAt(w) });
        } else c.by_design += 1;
    }
    for (f.ix.imports, 0..) |im, n| {
        const node = calls.get(im.start) orelse continue;
        c.imports += 1;
        const engine = if (try r.importFile(f, @intCast(n))) |file| file.path else null;
        const want = try ref.importOf(path, node);
        const wantPath: ?[]const u8 = if (want) |w| w.path else null;
        if (engine == null and wantPath == null) {
            c.imports_unresolved += 1;
        } else if (engine != null and wantPath != null and std.mem.eql(u8, engine.?, wantPath.?)) {
            c.imports_resolved += 1;
        } else {
            c.imports_wrong += 1;
            try problems.print(arena, "{s}:{d}: @import(\"{s}\") is {s}; the reference's, {s}\n", .{ path, lineOf(f.ix.text, im.start), im.name, engine orelse "nothing", wantPath orelse "nothing" });
        }
    }
    c.resolve_ns += @intCast(t1.untilNow(disk.io, .awake).toNanoseconds());
    try out.writeAll(problems.items);
    if (show and problems.items.len == 0) try out.print("{s}: {d} members, {d} imports agree\n", .{ path, f.ix.members.len, f.ix.imports.len });
}

/// The engine's files: each read from disk and indexed once.
const Disk = struct {
    arena: std.mem.Allocator,
    io: Io,
    modules: *const std.StringHashMapUnmanaged([]const u8),
    files: std.StringHashMapUnmanaged(?*const scopes.Index) = .empty,

    const vtable: scopes.World.VTable = .{ .load = load, .module = module };

    fn world(d: *Disk) scopes.World {
        return .{ .ptr = d, .vtable = &vtable };
    }

    fn load(ptr: *anyopaque, path: []const u8) error{OutOfMemory}!?*const scopes.Index {
        const d: *Disk = @ptrCast(@alignCast(ptr));
        if (d.files.get(path)) |ix| return ix;
        const text = Io.Dir.cwd().readFileAlloc(d.io, path, d.arena, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
        var ix: ?*scopes.Index = null;
        if (text) |t| {
            ix = try d.arena.create(scopes.Index);
            ix.?.* = try scopes.index(d.arena, t);
        }
        try d.files.put(d.arena, try d.arena.dupe(u8, path), ix);
        return ix;
    }

    fn module(ptr: *anyopaque, from: []const u8, name: []const u8) error{OutOfMemory}!?[]const u8 {
        _ = from;
        const d: *Disk = @ptrCast(@alignCast(ptr));
        return d.modules.get(name);
    }
};

/// A declaration of a file: where its name starts.
const Decl = struct { path: []const u8, start: u32 };

/// A container of a file.
const Place = struct { parsed: *Parsed, container: u32 };

const Parsed = struct {
    path: []const u8,
    text: [:0]const u8,
    tree: Ast,
    containers: []const Container,
};

/// A container's node, its tokens, and its declarations by name.
const Container = struct {
    node: Ast.Node.Index,
    first: u32,
    last: u32,
    decls: std.StringHashMapUnmanaged(Member),
};

const Member = struct {
    node: Ast.Node.Index,
    name_token: Ast.TokenIndex,
    public: bool,
    field: bool,
};

/// The reference resolution, over std.zig.Ast alone.
const Ref = struct {
    arena: std.mem.Allocator,
    io: Io,
    modules: *const std.StringHashMapUnmanaged([]const u8),
    files: std.StringHashMapUnmanaged(?*Parsed) = .empty,

    fn parsed(ref: *Ref, path: []const u8) !?*Parsed {
        if (ref.files.get(path)) |p| return p;
        const got = try ref.parse(path);
        try ref.files.put(ref.arena, try ref.arena.dupe(u8, path), got);
        return got;
    }

    fn parse(ref: *Ref, path: []const u8) !?*Parsed {
        const text = Io.Dir.cwd().readFileAllocOptions(ref.io, path, ref.arena, .unlimited, .of(u8), 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        const p = try ref.arena.create(Parsed);
        p.* = .{ .path = path, .text = text, .tree = try Ast.parse(ref.arena, text, .{}), .containers = &.{} };
        const tree = &p.tree;
        var containers: std.ArrayList(Container) = .empty;
        for (0..tree.nodes.len) |n| {
            const node: Ast.Node.Index = @fromBackingInt(@as(u32, @intCast(n)));
            var cb: [2]Ast.Node.Index = undefined;
            const cd = tree.fullContainerDecl(&cb, node) orelse continue;
            var decls: std.StringHashMapUnmanaged(Member) = .empty;
            for (cd.ast.members) |member| {
                const m = memberOf(tree, member) orelse continue;
                const gop = try decls.getOrPut(ref.arena, tree.tokenSlice(m.name_token));
                if (!gop.found_existing) gop.value_ptr.* = m;
            }
            const first: u32 = if (n == 0) 0 else tree.firstToken(node);
            const last: u32 = if (n == 0) @intCast(tree.tokens.len - 1) else tree.lastToken(node);
            try containers.append(ref.arena, .{ .node = node, .first = first, .last = last, .decls = decls });
        }
        p.containers = containers.items;
        return p;
    }

    /// What `member` of a container declares: a variable, a function, a
    /// field; null for a test, a comptime block, a nameless field.
    fn memberOf(tree: *const Ast, member: Ast.Node.Index) ?Member {
        if (tree.fullVarDecl(member)) |v| return .{ .node = member, .name_token = v.ast.mut_token + 1, .public = v.visib_token != null, .field = false };
        var fb: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&fb, member)) |f| {
            const name = f.name_token orelse return null;
            return .{ .node = member, .name_token = name, .public = f.visib_token != null, .field = false };
        }
        if (tree.fullContainerField(member)) |field| {
            if (tree.tokenTag(field.ast.main_token) != .identifier) return null;
            return .{ .node = member, .name_token = field.ast.main_token, .public = true, .field = true };
        }
        return null;
    }

    /// The declaration field access `node` of the file at `path` names.
    fn memberAt(ref: *Ref, path: []const u8, node: Ast.Node.Index, depth: u32) !?Decl {
        if (depth > 64) return null;
        const p = (try ref.parsed(path)).?;
        const data = p.tree.nodeData(node).node_and_token;
        const place = (try ref.denote(p, data[0], depth + 1)) orelse return null;
        const m = lookup(place, p.tree.tokenSlice(data[1]), path) orelse return null;
        return .{ .path = place.parsed.path, .start = place.parsed.tree.tokenStart(m.name_token) };
    }

    /// The container expression `node` of `p` denotes.
    fn denote(ref: *Ref, p: *Parsed, node: Ast.Node.Index, depth: u32) error{OutOfMemory}!?Place {
        if (depth > 64) return null;
        const tree = &p.tree;
        switch (tree.nodeTag(node)) {
            .identifier => {
                const tok = tree.nodeMainToken(node);
                const at = lexical(p, tok, tree.tokenSlice(tok)) orelse return null;
                return ref.denoteMember(at, depth + 1);
            },
            .field_access => {
                const data = tree.nodeData(node).node_and_token;
                const place = (try ref.denote(p, data[0], depth + 1)) orelse return null;
                const m = lookup(place, tree.tokenSlice(data[1]), p.path) orelse return null;
                return ref.denoteMember(.{ .parsed = place.parsed, .member = m }, depth + 1);
            },
            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {
                const file = (try ref.importOf(p.path, node)) orelse return null;
                return .{ .parsed = file, .container = 0 };
            },
            else => {
                for (p.containers, 0..) |c, i| if (c.node == node) return .{ .parsed = p, .container = @intCast(i) };
                return null;
            },
        }
    }

    const At = struct { parsed: *Parsed, member: Member };

    /// The container a declaration's value denotes, else its type.
    fn denoteMember(ref: *Ref, at: At, depth: u32) error{OutOfMemory}!?Place {
        const tree = &at.parsed.tree;
        if (tree.fullVarDecl(at.member.node)) |v| {
            if (v.ast.init_node.unwrap()) |init| if (try ref.denote(at.parsed, init, depth + 1)) |place| return place;
            if (v.ast.type_node.unwrap()) |t| return ref.denote(at.parsed, t, depth + 1);
            return null;
        }
        if (tree.fullContainerField(at.member.node)) |field| {
            if (field.ast.type_expr.unwrap()) |t| if (!field.ast.tuple_like) return ref.denote(at.parsed, t, depth + 1);
        }
        return null;
    }

    /// The file `@import` call `node` of the file at `path` names.
    fn importOf(ref: *Ref, path: []const u8, node: Ast.Node.Index) error{OutOfMemory}!?*Parsed {
        const p = (try ref.parsed(path)).?;
        const tree = &p.tree;
        if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import")) return null;
        var pb: [2]Ast.Node.Index = undefined;
        const params = tree.builtinCallParams(&pb, node) orelse return null;
        if (params.len != 1 or tree.nodeTag(params[0]) != .string_literal) return null;
        const name = std.zig.string_literal.parseAlloc(ref.arena, tree.tokenSlice(tree.nodeMainToken(params[0]))) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        const file = ref.modules.get(name) orelse try std.fs.path.resolveAlloc(ref.arena, &.{ std.fs.path.dirname(path) orelse "/", name });
        return ref.parsed(file);
    }

    /// Whether a declaration of `name` starts at `d`.
    fn isDecl(ref: *Ref, d: Decl, name: []const u8) !bool {
        const p = (try ref.parsed(d.path)) orelse return false;
        for (p.containers) |c| if (c.decls.get(name)) |m| {
            if (p.tree.tokenStart(m.name_token) == d.start) return true;
        };
        return false;
    }

    fn lineAt(ref: *Ref, d: Decl) !usize {
        const p = (try ref.parsed(d.path)) orelse return 0;
        return lineOf(p.text, d.start);
    }
};

/// The declaration of `name` in `place` that the file at `from` sees.
fn lookup(place: Place, name: []const u8, from: []const u8) ?Member {
    const m = place.parsed.containers[place.container].decls.get(name) orelse return null;
    if (!m.public and !std.mem.eql(u8, place.parsed.path, from)) return null;
    return m;
}

/// The declaration identifier `tok` of `p` names among those of the
/// containers around it, the nearest first; fields are never in sight.
fn lexical(p: *Parsed, tok: Ast.TokenIndex, name: []const u8) ?Ref.At {
    var best: ?Member = null;
    var width: u32 = std.math.maxInt(u32);
    for (p.containers) |c| {
        if (tok < c.first or tok > c.last or c.last - c.first >= width) continue;
        const m = c.decls.get(name) orelse continue;
        if (m.field) continue;
        best = m;
        width = c.last - c.first;
    }
    return .{ .parsed = p, .member = best orelse return null };
}

fn lineOf(text: []const u8, pos: u32) usize {
    return std.mem.count(u8, text[0..@min(pos, text.len)], "\n") + 1;
}
