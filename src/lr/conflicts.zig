//! Conflict reporting: summarizes the unresolved conflicts recorded while
//! building the parse table and compares the total against `@conflicts`.

const std = @import("std");
const diag = @import("../diag.zig");
const Allocator = std.mem.Allocator;
const Table = @import("table.zig").Table;

pub const ConflictDetail = struct {
    kind: enum { shiftReduce, reduceReduce },
    nameA: []const u8,
    nameB: []const u8,
};

pub fn report(allocator: Allocator, table: *const Table, expectConflicts: ?u32) void {
    if (table.conflictDetails.items.len == 0) {
        if (expectConflicts) |expected| {
            if (expected != 0)
                diag.warn("0 conflicts (expected {d}; update @conflicts)", .{expected});
        }
        return;
    }

    const isAutoGen = struct {
        fn f(name: []const u8) bool {
            return std.mem.startsWith(u8, name, "_opt_") or
                std.mem.startsWith(u8, name, "_star_") or
                std.mem.startsWith(u8, name, "_tail_");
        }
    }.f;

    // Deduplicate and classify conflicts
    var benign: u32 = 0;
    var seen = std.StringHashMap(u32).init(allocator);
    defer seen.deinit();

    for (table.conflictDetails.items) |c| {
        const a = c.nameA;
        const b = c.nameB;
        const isBenign = (c.kind == .reduceReduce and isAutoGen(a) and isAutoGen(b)) or
            (c.kind == .shiftReduce and isAutoGen(a));
        if (isBenign) {
            benign += 1;
        } else {
            var buf: [256]u8 = undefined;
            const keyTag: []const u8 = if (c.kind == .shiftReduce) "S/R" else "R/R";
            const key = std.fmt.bufPrint(&buf, "{s}: {s} vs {s}", .{ keyTag, a, b }) catch continue;
            const owned = allocator.dupe(u8, key) catch continue;
            const gop = seen.getOrPut(owned) catch continue;
            if (gop.found_existing) {
                gop.value_ptr.* += 1;
                allocator.free(owned);
            } else {
                gop.value_ptr.* = 1;
            }
        }
    }

    // Print unique real conflicts with counts
    var iter = seen.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            std.debug.print("  {s} (x{d}) [REVIEW]\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        } else {
            std.debug.print("  {s} [REVIEW]\n", .{entry.key_ptr.*});
        }
        allocator.free(entry.key_ptr.*);
    }

    // Print benign summary
    if (benign > 0)
        std.debug.print("  {d} benign (auto-generated list/optional) [safe]\n", .{benign});

    // Check against @conflicts
    const total = table.conflicts;
    if (expectConflicts) |expected| {
        if (total == expected) {
            diag.info("   {d} conflicts (as expected)", .{total});
        } else {
            diag.warn("{d} conflicts (expected {d}; update @conflicts)", .{ total, expected });
        }
    } else if (total > 0) {
        diag.warn("{d} conflicts (add @conflicts = {d} if they are expected)", .{ total, total });
    }
}
