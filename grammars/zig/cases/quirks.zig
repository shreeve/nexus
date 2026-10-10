//! Readings that follow from Parse.zig's choices.
fn quirks() void {
    _ = a[*T];
    _ = a[*c];
    _ = a[*const T..];
    _ = [*c]u8;
    _ = blk: {
        break :blk - x;
    };
    switch (x) {}.field = 1;
    {} - x;
    const S = struct { x: switch (a) {
        else => u8,
    } };
    _ = S;
    _ = a catch |e| return e;
    _ = a orelse return;
    _ = return orelse x;
    _ = fn () void{};
    _ = if (a) b else if (c) d else e;
    _ = [.x: {}]u8;
    _ = a[0..break :x: {}];
    _ = 0. ?;
    return - x;
}
