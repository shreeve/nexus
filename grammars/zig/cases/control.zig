fn control(xs: []const u8, opt: ?u8, n: u32) u32 {
    var total: u32 = 0;
    if (opt) |v| total += v else total += 1;
    if (opt) |*v| {
        _ = v;
    } else if (n > 2) {
        total = 2;
    } else {}
    if (n == 0) return 0;
    while (total < n) : (total += 1) {}
    while (opt) |v| : (total += v) break else |e| _ = e;
    var i: usize = 0;
    outer: while (i < 10) : (i += 1) {
        inner: for (xs, 0..) |x, j| {
            if (x == 0) continue :outer;
            if (j > 3) break :inner;
        }
    }
    for (xs, 0..xs.len, 1..) |x, a, b| total += x + a + b;
    for (0..3) |_| {} else {}
    const found = for (xs) |x| {
        if (x == 1) break true;
    } else false;
    _ = found;
    inline for (.{ 1, 2 }) |c| total += c;
    const r = blk: {
        if (n == 1) break :blk @as(u32, 1);
        break :blk 2;
    };
    total += switch (n) {
        0 => 1,
        1, 2 => |v| v,
        3...5 => 2,
        inline 6, 7 => |v, tag| v + tag,
        else => r,
    };
    sw: switch (n) {
        0 => continue :sw 1,
        1 => break :sw,
        else => {},
    }
    switch (opt orelse 0) {
        inline else => |v| total += v,
    }
    return total;
}
