const Error = error{ Bad, Worse };

fn mayFail(x: u8) Error!u8 {
    if (x == 0) return error.Bad;
    return x;
}

fn handle() !void {
    const a = try mayFail(1);
    const b = mayFail(0) catch |err| switch (err) {
        error.Bad => 0,
        error.Worse => return err,
    };
    const c = mayFail(2) catch 7;
    errdefer std.log.err("failed", .{});
    defer {
        _ = a;
    }
    const d: ?u8 = null;
    const e = d orelse b orelse c;
    const f = d.?;
    _ = .{ e, f };
    mayFail(3) catch unreachable;
}

const std = @import("std");
