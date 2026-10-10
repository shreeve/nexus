const Point = struct {
    x: f32,
    y: f32 = 0,
    comptime tag: []const u8 = "point",
    z: f32 align(4) = 1,

    pub fn len(self: Point) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }
};

const Tuple = struct { u8, []const u8, comptime u32 = 3 };
const Color = enum(u8) { red = 1, green, blue, _ };
const Plain = enum { a, b };
const Value = union(enum) {
    int: i64,
    float: f64,
    none,
};
const Tagged = union(enum(u8)) { a: u8, b: void };
const Bare = union(Plain) { a: u8, b: u16 };
const Untagged = union { a: u8, b: u16 };
const Handle = opaque {};
const Flags = packed struct(u8) { a: bool, b: bool, rest: u6 };
const C = extern struct { a: c_int, b: extern union { x: u8, y: u16 } };
const Empty = struct {};
const Mixed = struct {
    const before = 1;
    a: u8,
    b: u16,
    const after = 2;
    fn method() void {}
};
const Inner = struct {
    //! A container doc comment inside a container.
    x: u8,
};
const ErrSet = error{ OutOfMemory, Overflow };
const Docs = error{
    /// Documented.
    A,
    B,
};
const Merged = ErrSet || error{Other};
