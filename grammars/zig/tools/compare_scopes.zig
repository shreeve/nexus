//! Compares the names the grammar's `@lsp` resolves (scopes.zig, the
//! index the generated language server keeps) with the compiler's own
//! name resolution, std.zig.AstGen's, over a corpus. Built by
//! grammars/zig/compare-scopes beside the server `nexus --editor` writes;
//! see that script for usage.
//!
//!   compare_scopes [--list FILE] [--show] PATH...
//!
//! For each input AstGen accepts, every definition the index makes that
//! is in its scope chain (not a member) gets a name of its own, `_csN`,
//! and so does every use the index resolves to it; AstGen must accept the
//! renamed file too, as it does a file renamed by the compiler's own
//! resolution. An error in the renamed file is a use the index resolves
//! elsewhere than the compiler does (or a definition it misses), at that
//! error. A use the index leaves unresolved must be a primitive
//! (std.zig.primitives) or `_`; any other is a name the compiler resolves
//! and the index does not. Prints each disagreement and a summary; exits
//! 1 when there is any.

const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const AstGen = std.zig.AstGen;
const Zir = std.zig.Zir;
const scopes = @import("scopes.zig");

const Counts = struct {
    files: usize = 0,
    rejected: usize = 0,
    defs: usize = 0,
    members: usize = 0,
    resolved: usize = 0,
    builtin: usize = 0,
    primitive: usize = 0,
    discard: usize = 0,
    unresolved: usize = 0,
    discard_resolved: usize = 0,
    identifiers: usize = 0,
    errors: usize = 0,
    bytes: usize = 0,
    index_ns: u64 = 0,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();

    var paths: std.ArrayList([]const u8) = .empty;
    var show = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--list") and i + 1 < args.len) {
            i += 1;
            const data = try cwd.readFileAlloc(io, args[i], arena, .unlimited);
            var it = std.mem.tokenizeScalar(u8, data, '\n');
            while (it.next()) |line| try paths.append(arena, line);
        } else if (std.mem.eql(u8, arg, "--show")) {
            show = true;
        } else try paths.append(arena, arg);
    }

    var buf: [64 * 1024]u8 = undefined;
    var fw = Io.File.stdout().writerStreaming(io, &buf);
    const out = &fw.interface;
    var c: Counts = .{};
    for (paths.items) |path| {
        const text = cwd.readFileAllocOptions(io, path, gpa, .unlimited, .of(u8), 0) catch |err| {
            try out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            c.rejected += 1;
            continue;
        };
        defer gpa.free(text);
        try compareFile(gpa, io, out, path, text, &c, show);
    }

    const disagree = c.unresolved + c.errors + c.discard_resolved;
    try out.print(
        \\{d} files ({d} skipped: not accepted by AstGen), {d} bytes
        \\definitions: {d} in scope chains, {d} members
        \\uses: {d} resolved, {d} builtins, {d} primitives, {d} `_`, {d} unresolved names the compiler resolves
        \\other identifiers (members, labels, enum literals, field names: not looked up): {d}
        \\AstGen errors in the renamed files: {d}; `_` resolved to a definition: {d}
        \\disagreements: {d}
        \\index: {d} ms in all
        \\
    , .{
        c.files,            c.rejected,                                                                                              c.bytes,
        c.defs,             c.members,                                                                                               c.resolved,
        c.builtin,          c.primitive,                                                                                             c.discard,
        c.unresolved,       c.identifiers -| (c.resolved + c.builtin + c.primitive + c.discard + c.unresolved + c.defs + c.members), c.errors,
        c.discard_resolved, disagree,                                                                                                c.index_ns / std.time.ns_per_ms,
    });
    try out.flush();
    if (disagree > 0) std.process.exit(1);
}

const AstError = struct { pos: u32, msg: []const u8 };

/// AstGen's errors of `text`: each one's offset and message; null when
/// Ast.parse rejects it.
fn astgenErrors(gpa: std.mem.Allocator, arena: std.mem.Allocator, text: [:0]const u8) !?[]const AstError {
    var tree = try Ast.parse(gpa, text, .{});
    defer tree.deinit(gpa);
    if (tree.errors.len > 0) return null;
    var zir = try AstGen.generate(gpa, tree);
    defer zir.deinit(gpa);
    var list: std.ArrayList(AstError) = .empty;
    if (!zir.hasCompileErrors()) return &.{};
    const payload = zir.extra[@backingInt(Zir.ExtraIndex.compile_errors)];
    const header = zir.extraData(Zir.Inst.CompileErrors, payload);
    var extra = header.end;
    for (0..header.data.items_len) |_| {
        const item = zir.extraData(Zir.Inst.CompileErrors.Item, extra);
        extra = item.end;
        const pos: u32 = if (item.data.node.unwrap()) |node| tree.nodeToSpan(node).main else if (item.data.token.unwrap()) |tok| tree.tokenStart(tok) + item.data.byte_offset else 0;
        try list.append(arena, .{ .pos = pos, .msg = try arena.dupe(u8, zir.nullTerminatedString(item.data.msg)) });
    }
    return list.items;
}

fn compareFile(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, path: []const u8, text: [:0]const u8, c: *Counts, show: bool) !void {
    var state: std.heap.ArenaAllocator = .init(gpa);
    defer state.deinit();
    const arena = state.allocator();

    const before = (try astgenErrors(gpa, arena, text)) orelse {
        c.rejected += 1;
        return;
    };
    if (before.len > 0) {
        c.rejected += 1;
        return;
    }
    c.files += 1;
    c.bytes += text.len;

    const t0 = Io.Clock.awake.now(io);
    const ix = try scopes.index(arena, text);
    c.index_ns += @intCast(t0.untilNow(io, .awake).toNanoseconds());

    // Every identifier the compiler's tokenizer sees.
    var tokenizer = std.zig.Tokenizer.init(text);
    while (true) {
        const tok = tokenizer.next();
        if (tok.tag == .eof) break;
        if (tok.tag == .identifier) c.identifiers += 1;
    }

    // The renamed text: each definition in a scope chain, but `_`, and
    // each use the index resolves to one.
    const Edit = struct { start: u32, end: u32, def: u32 };
    var edits: std.ArrayList(Edit) = .empty;
    for (ix.defs, 0..) |d, n| {
        if (isMember(d)) {
            c.members += 1;
            continue;
        }
        c.defs += 1;
        if (std.mem.eql(u8, d.name, "_")) continue;
        try edits.append(arena, .{ .start = d.start, .end = d.end, .def = @intCast(n) });
    }
    var problems: std.ArrayList(u8) = .empty;
    for (ix.uses) |u| {
        const name = text[u.start..u.end];
        switch (u.res) {
            .def => |d| {
                if (std.mem.eql(u8, ix.defs[d].name, "_")) {
                    c.discard_resolved += 1;
                    try problems.print(arena, "{s}:{d}: `_` resolves to a definition on line {d}\n", .{ path, lineOf(text, u.start), lineOf(text, ix.defs[d].start) });
                    continue;
                }
                c.resolved += 1;
                try edits.append(arena, .{ .start = u.start, .end = u.end, .def = d });
            },
            .builtin => c.builtin += 1,
            .unresolved => if (std.zig.primitives.isPrimitive(name)) {
                c.primitive += 1;
            } else if (std.mem.eql(u8, name, "_")) {
                c.discard += 1;
            } else {
                c.unresolved += 1;
                try problems.print(arena, "{s}:{d}: '{s}' is unresolved\n", .{ path, lineOf(text, u.start), name });
            },
        }
    }
    std.mem.sort(Edit, edits.items, {}, struct {
        fn lt(_: void, x: Edit, y: Edit) bool {
            return x.start < y.start;
        }
    }.lt);
    var renamed: std.ArrayList(u8) = .empty;
    var from: u32 = 0;
    for (edits.items) |e| {
        try renamed.appendSlice(arena, text[from..e.start]);
        try renamed.print(arena, "_cs{d}", .{e.def});
        from = e.end;
    }
    try renamed.appendSlice(arena, text[from..]);
    const renamedText = try arena.dupeSentinel(u8, renamed.items, 0);
    const after = (try astgenErrors(gpa, arena, renamedText)) orelse {
        c.errors += 1;
        try problems.print(arena, "{s}: the renamed file does not parse\n", .{path});
        try out.writeAll(problems.items);
        return;
    };
    for (after) |e| {
        c.errors += 1;
        try problems.print(arena, "{s}:{d}: renamed: {s}\n", .{ path, lineOf(renamedText, e.pos), e.msg });
    }
    try out.writeAll(problems.items);
    if (show and problems.items.len == 0) try out.print("{s}: {d} definitions, {d} uses agree\n", .{ path, ix.defs.len, ix.uses.len });
}

/// Whether a definition is in its scope's member table alone.
fn isMember(d: scopes.Def) bool {
    return @import("language.zig").names.defines[d.line].visibility == .member;
}

fn lineOf(text: []const u8, pos: u32) usize {
    return std.mem.count(u8, text[0..@min(pos, text.len)], "\n") + 1;
}
