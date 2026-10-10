//! Compares the trees the parser generated from zig.grammar builds with
//! std.zig.Ast's (trees.zig) over a corpus. Built by grammars/zig/compare-trees
//! next to the generated parser.zig, zig.zig, trees.zig and inputs.zig;
//! see that script for usage.
//!
//!   compare_trees [--list FILE] [--inline FILE] [--dump DIR] [--show] PATH...
//!   compare_trees --fuzz N [--seed S] [--list FILE] [--inline FILE] PATH...
//!
//! Inputs that either parser rejects are not compared (compare-accept
//! checks those). Prints one line per input whose trees differ, with the
//! first differing line of each side and the line before it, and a
//! summary; exits 1 when any differ. --dump DIR writes both forms of each
//! differing input to DIR (N.nexus, N.std); --show prints the form of
//! each input whose trees agree. --fuzz N compares on N inputs made from
//! the given ones by token edits (inputs.Mutator), the same inputs
//! compare-accept --fuzz makes with the same seed.

const std = @import("std");
const Io = std.Io;
const parser = @import("parser.zig");
const trees = @import("trees.zig");
const inputs = @import("inputs.zig");
const Input = inputs.Input;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();

    var paths: std.ArrayList([]const u8) = .empty;
    var inline_inputs: std.ArrayList(Input) = .empty;
    var dump: ?[]const u8 = null;
    var show = false;
    var fuzz: usize = 0;
    var seed: u64 = 0;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const value = i + 1 < args.len;
        if (std.mem.eql(u8, arg, "--list") and value) {
            i += 1;
            const data = try cwd.readFileAlloc(io, args[i], arena, .unlimited);
            var it = std.mem.tokenizeScalar(u8, data, '\n');
            while (it.next()) |line| try paths.append(arena, line);
        } else if (std.mem.eql(u8, arg, "--inline") and value) {
            i += 1;
            try inputs.inlineInputs(io, arena, args[i], &inline_inputs);
        } else if (std.mem.eql(u8, arg, "--fuzz") and value) {
            i += 1;
            fuzz = try std.fmt.parseUnsigned(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--seed") and value) {
            i += 1;
            seed = try std.fmt.parseUnsigned(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--show")) {
            show = true;
        } else if (std.mem.eql(u8, arg, "--dump") and value) {
            i += 1;
            dump = args[i];
        } else if (arg.len > 1 and arg[0] == '-') {
            std.process.fatal("unknown option or missing value: {s}", .{arg});
        } else {
            try paths.append(arena, arg);
        }
    }

    var buf: [64 * 1024]u8 = undefined;
    var fw = Io.File.stdout().writerStreaming(io, &buf);
    const w = &fw.interface;
    defer w.flush() catch {};

    var p = parser.Parser.init(gpa, "");
    defer p.deinit();
    var nexus_out: Io.Writer.Allocating = .init(gpa);
    defer nexus_out.deinit();
    var std_out: Io.Writer.Allocating = .init(gpa);
    defer std_out.deinit();

    if (fuzz != 0) {
        for (paths.items) |path| {
            const src = cwd.readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            try inline_inputs.append(arena, .{ .name = path, .src = src });
        }
        if (inline_inputs.items.len == 0) std.process.fatal("--fuzz needs seed inputs", .{});
        var mutator: inputs.Mutator = .init(seed);
        defer mutator.deinit(gpa);
        var counts: [3]usize = .{ 0, 0, 0 };
        for (0..fuzz) |k| {
            const from, const src = try mutator.next(gpa, inline_inputs.items);
            const outcome = try trees.compare(gpa, &p, src, &nexus_out, &std_out);
            counts[@backingInt(outcome)] += 1;
            if (outcome != .differ) continue;
            const d = trees.firstDiff(nexus_out.written(), std_out.written());
            try w.print("DIFF fuzz #{d} (from {s}): line {d}\n  after: {s}\n  nexus: {s}\n  std:   {s}\n  input: ", .{ k, from.name, d.line, d.prev, d.a, d.b });
            try inputs.writeQuoted(w, src);
            try w.writeByte('\n');
        }
        try w.print("{d} mutants of {d} seeds: {d} trees compared, {d} differ; {d} not accepted by both (not compared)\n", .{
            fuzz, inline_inputs.items.len, counts[0] + counts[1], counts[1], counts[2],
        });
        try w.flush();
        if (counts[1] != 0) std.process.exit(1);
        return;
    }

    var counts: [3]usize = .{ 0, 0, 0 };
    const total = paths.items.len + inline_inputs.items.len;
    for (0..total) |k| {
        var owned: ?[:0]u8 = null;
        defer if (owned) |o| gpa.free(o);
        const input: Input = if (k < paths.items.len) blk: {
            const path = paths.items[k];
            const src = cwd.readFileAllocOptions(io, path, gpa, .unlimited, .of(u8), 0) catch |err|
                std.process.fatal("{s}: {t}", .{ path, err });
            owned = src;
            break :blk .{ .name = path, .src = src };
        } else inline_inputs.items[k - paths.items.len];

        const outcome = try trees.compare(gpa, &p, input.src, &nexus_out, &std_out);
        counts[@backingInt(outcome)] += 1;
        if (show and outcome == .same) try w.print("# {s}\n{s}", .{ input.name, nexus_out.written() });
        if (outcome != .differ) continue;
        const d = trees.firstDiff(nexus_out.written(), std_out.written());
        try w.print("DIFF {s}: line {d}\n  after: {s}\n  nexus: {s}\n  std:   {s}\n", .{ input.name, d.line, d.prev, d.a, d.b });
        if (dump) |dir| {
            const n = counts[1];
            try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/{d}.nexus", .{ dir, n }), .data = nexus_out.written() });
            try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/{d}.std", .{ dir, n }), .data = std_out.written() });
        }
    }
    try w.print("{d} inputs: {d} trees compared, {d} differ; {d} not accepted by both (not compared)\n", .{
        total, counts[0] + counts[1], counts[1], counts[2],
    });
    try w.flush();
    if (counts[1] != 0) std.process.exit(1);
}
