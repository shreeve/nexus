fn List(comptime T: type) type {
    return struct {
        items: []T,
        len: usize = 0,

        const Self = @This();

        pub fn append(self: *Self, item: T) !void {
            self.items[self.len] = item;
            self.len += 1;
        }
    };
}

fn max(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a > b) a else b;
}

fn typed(comptime n: usize, comptime anytype) [n]u8 {
    return @splat(0);
}

const ListU8 = List(u8);
const f: fn (u8) callconv(.c) u8 = undefined;
const g: *const fn (comptime type, anytype) void = undefined;
const anon = fn () void{};
