//! Container-level declarations: every kind of decl and field order.
//! A second container doc comment line.

/// A documented constant.
pub const answer: u32 = 42;
var counter: usize align(8) = 0;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, len: usize) isize;
extern fn exit(code: c_int) noreturn;
export fn exported() callconv(.c) void {}
pub inline fn twice(x: anytype) @TypeOf(x) {
    return x + x;
}
noinline fn slow() void {}
fn proto(u8) void;
threadlocal var tls: u32 = 1;
pub extern "kernel32" threadlocal var tls2: u32;
export var exported_var: i32 linksection(".data") = 3;
const in_addrspace: u32 addrspace(.generic) = 0;
fn modifiers() align(16) addrspace(.generic) linksection(".text") callconv(.c) !void {}

test "a string name" {}
test ident_name {}
test {}

comptime {
    _ = answer;
}

fn varargs(fmt: [*:0]const u8, ...) callconv(.c) c_int;
fn documented(
    /// The first parameter.
    comptime T: type,
    noalias out: *T,
    /// Trailing varargs may be documented too.
    ...,
) void;
