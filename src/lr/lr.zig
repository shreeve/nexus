//! The LR stage: LR(0) automaton, lookaheads, parse table, and the checks
//! on them (`@repair` names, `X "c"` hints, the conflict manifest). Every
//! failure prints a located diagnostic and returns `error.GenerationFailed`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Grammar = grammar.Grammar;
pub const automaton = @import("automaton.zig");
pub const lookahead = @import("lookahead.zig");
pub const table = @import("table.zig");
pub const conflicts = @import("conflicts.zig");
pub const expected = @import("expected.zig");
pub const repair = @import("repair.zig");

pub const ParseMode = lookahead.ParseMode;

pub const Options = struct {
    mode: ParseMode = .lalr,
    /// The grammar file, for located messages.
    path: []const u8,
};

pub const Result = struct {
    automaton: automaton.Automaton,
    lookaheads: lookahead.Lookaheads,
    table: table.Table,
};

pub const Error = error{ GenerationFailed, OutOfMemory };

pub fn run(g: *Grammar, opts: Options) Error!Result {
    const a = g.allocator;
    var auto = automaton.build(g) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.NoAcceptRule => {
            std.debug.print("{s}: error: the grammar has no start symbol\n", .{opts.path});
            return error.GenerationFailed;
        },
    };
    errdefer auto.deinit(a);

    // LALR lookaheads (and any parse) assume every rule can complete.
    const costs = try repair.insertCosts(a, g);
    var unproductive = false;
    for (g.symbols.items, 0..) |sym, i| {
        if (sym.kind != .nonterminal or sym.rules.items.len == 0 or costs[i] != repair.infinite) continue;
        unproductive = true;
        const line = g.rules.items[sym.rules.items[0]].line;
        if (line > 0) std.debug.print("{s}:{d}:1: ", .{ opts.path, line }) else std.debug.print("{s}: ", .{opts.path});
        var name: std.Io.Writer.Allocating = .init(a);
        defer name.deinit();
        conflicts.writeSymbol(&name.writer, g, @intCast(i)) catch return error.OutOfMemory;
        std.debug.print("error: rule {s} derives no finite input (each of its alternatives needs a rule that never completes)\n", .{name.written()});
    }
    a.free(costs);
    if (unproductive) return error.GenerationFailed;

    const la = try lookahead.compute(g, &auto, opts.mode);

    if (g.repair) |spec| {
        if (repair.validate(g, spec)) |bad| {
            std.debug.print("{s}: error: @repair: {s} {s}\n", .{ opts.path, bad.name, bad.reason });
            return error.GenerationFailed;
        }
    }

    const tbl = table.build(g, &auto, la) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRepairToken => unreachable, // validated above
    };

    const copts: conflicts.Options = .{ .path = opts.path };
    conflicts.checkHints(a, g, &tbl, copts) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GenerationFailed,
    };
    conflicts.check(a, g, &auto, &tbl, copts) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GenerationFailed,
    };

    return .{ .automaton = auto, .lookaheads = la, .table = tbl };
}

test {
    _ = @import("bitset.zig");
    _ = @import("tests.zig");
}
