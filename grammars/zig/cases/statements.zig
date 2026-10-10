test {
    var x: u32 = 1;
    x = 2;
    x += 1;
    x -%= 1;
    x <<|= 1;
    const a, var b = .{ 1, 2 };
    a, b = .{ b, a };
    var arr: [2]u32 = undefined;
    arr[0], arr[1] = .{ 3, 4 };
    {
        defer x = 0;
        errdefer x = 1;
        defer {}
    }
    suspend {}
    nosuspend foo();
    blk: {
        break :blk;
    }
    _ = &b;
    if (x > 0) x = 0;
    if (x > 0) x = 0 else x = 1;
    while (x < 3) x += 1;
    for (arr) |v| x += v;
    lbl: for (arr) |v| {
        if (v == 0) break :lbl;
    }
    return;
}
