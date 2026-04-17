# Zig 0.15.2 Updates

This document provides a comprehensive overview of the changes and new features in Zig 0.15.1/0.15.2 that you may not have known about if your knowledge cutoff was January 2025.

## Critical Breaking Changes

### 1. **`usingnamespace` Removed** (MAJOR BREAKING CHANGE)

The `usingnamespace` keyword has been **completely removed** from the language. This was a significant decision to improve code clarity and enable better tooling.

**Why it was removed:**
- Made it difficult to trace where declarations came from
- Broke autodoc functionality
- Encouraged poor namespacing practices
- Made incremental compilation more complex

**Migration strategies:**

For conditional inclusion:
```zig
// OLD (won't compile):
pub usingnamespace if (have_foo) struct {
    pub const foo = 123;
} else struct {};

// NEW - Option 1: Just include unconditionally
pub const foo = 123;

// NEW - Option 2: Use @compileError for unsupported features
pub const foo = if (have_foo)
    123
else
    @compileError("foo not supported on this target");

// NEW - Option 3: Use void sentinel for feature detection
pub const foo = if (have_foo) 123 else {};
```

For implementation selection:
```zig
// OLD:
pub usingnamespace switch (target) {
    .windows => struct { pub fn init() T { ... } },
    else => struct { pub fn init() T { ... } },
};

// NEW: Make definitions conditional
pub const init = switch (target) {
    .windows => initWindows,
    else => initOther,
};
```

For mixins (important pattern):
```zig
// OLD:
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn incrementCounter(x: *T) void { x.count += 1; }
    };
}
pub const Foo = struct {
    count: u32 = 0,
    pub usingnamespace CounterMixin(Foo);
};

// NEW: Use zero-bit fields and @fieldParentPtr
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn increment(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x.count += 1;
        }
    };
}
pub const Foo = struct {
    count: u32 = 0,
    counter: CounterMixin(Foo) = .{},
};
// Usage: foo.counter.increment() instead of foo.incrementCounter()
```

### 2. **async/await Keywords Removed**

The `async` and `await` keywords have been removed. They will return as library features under the new I/O system, not as language keywords.

Also removed: `@frameSize`

### 3. **Major I/O Overhaul: "Writergate"**

Zig 0.15.1 introduces a **massive breaking change** to all I/O operations. This is called "Writergate" in the release notes.

**Key changes:**
- `std.Io.Reader` and `std.Io.Writer` are now **non-generic** types
- The buffer is now **above the vtable** (in the interface, not the implementation)
- This enables optimization while being non-generic
- **All old readers/writers are deprecated**

**Migration example:**
```zig
// OLD:
const stdout_file = std.fs.File.stdout().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();
try stdout.print("text\n", .{});
try bw.flush();

// NEW:
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;
try stdout.print("text\n", .{});
try stdout.flush();
```

**New reader/writer patterns:**
```zig
// File reader with buffer
var read_buffer: [4096]u8 = undefined;
var file_reader = file.reader(&read_buffer);
const reader: *std.Io.Reader = &file_reader.interface;

// For full piping, use empty buffer:
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &.{});
const n = try decompress.streamRemaining(writer);
```

**Important file API changes:**
- `fs.Dir.copyFile` no longer can fail with `error.OutOfMemory`
- `fs.Dir.atomicFile` now requires a `write_buffer` in options
- `fs.AtomicFile` now has a `File.Writer` field rather than `File` field
- Removed: `writeFileAll`, `writeFileAllUnseekable`
- Removed: `posix.sendfile` in favor of `fs.File.Reader.sendFile`

### 4. **Format String Changes**

Format strings now require explicit specification for custom `format` methods:

```zig
// OLD: {} was ambiguous
std.debug.print("{}", .{my_value});

// NEW: Must specify intent
std.debug.print("{f}", .{my_value});  // Call format method
std.debug.print("{any}", .{my_value}); // Skip format method
```

**Custom format method signature changed:**
```zig
// OLD:
pub fn format(
    this: @This(),
    comptime format_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void { ... }

// NEW:
pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void { ... }
```

### 5. **Inline Assembly Clobbers**

Clobbers now use struct syntax instead of string arrays:

```zig
// OLD:
: "rcx", "r11"

// NEW:
: .{ .rcx = true, .r11 = true }
```

Auto-upgrade: `zig fmt` will handle this automatically.

### 6. **Data Structure Changes**

**ArrayList changes:**
```zig
// std.ArrayList -> std.array_list.Managed
// std.ArrayListAligned -> std.array_list.AlignedManaged
// Both will eventually be removed - prefer ArrayListUnmanaged
```

**Removed:**
- `std.fifo.LinearFifo` - poorly designed, use new I/O instead
- `std.RingBuffer` - use new I/O instead
- `std.BoundedArray` - see migration guide below

**BoundedArray migration:**
```zig
// OLD:
var stack = try std.BoundedArray(i32, 8).fromSlice(initial_stack);

// NEW:
var buffer: [8]i32 = undefined;
var stack = std.ArrayListUnmanaged(i32).initBuffer(&buffer);
try stack.appendSliceBounded(initial_stack);
```

**DoublyLinkedList changes:**
```zig
// OLD:
std.DoublyLinkedList(T).Node

// NEW:
struct {
    node: std.DoublyLinkedList.Node,
    data: T,
}
// Then use @fieldParentPtr to get from node to data
```

### 7. **Compression API Changes**

`std.compress.flate` completely restructured:
- Compression functionality **removed** (copy old code if needed)
- Decompression API changed significantly

```zig
// NEW decompression API:
var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &decompress_buffer);
const decompress_reader: *std.Io.Reader = &decompress.reader;
```

### 8. **HTTP Client and Server Changes**

Complete overhaul - no longer depends on `std.net`:

```zig
// OLD:
var server_header_buffer: [1024]u8 = undefined;
var req = try client.open(.GET, uri, .{
    .server_header_buffer = &server_header_buffer,
});
try req.send();
try req.wait();

// NEW:
var req = try client.request(.GET, uri, .{});
try req.sendBodiless();
var response = try req.receiveHead(&.{});
var reader_buffer: [100]u8 = undefined;
const body_reader = response.reader(&reader_buffer);
```

### 9. **Build System Changes**

**Removed deprecated fields** from `std.Build.ExecutableOptions`:
- No more `root_source_file` - must use `root_module` field
- This was deprecated in 0.14.0 and removed in 0.15.x

**`--watch` flag**:
- Now works correctly on macOS (was broken in 0.14.0)
- Uses File System Events API for fast, reliable watching

**New `--webui` flag**:
- Exposes web interface for build system
- Shows build step progress
- Includes fuzzer interface with `--fuzz`
- NEW: `--time-report` shows detailed timing information

### 10. **Undefined Behavior Rules**

New standardization around `undefined` operands:
- Only operators that can never trigger Illegal Behavior permit `undefined` as operand
- All other operators trigger Illegal Behavior if operand is `undefined`

```zig
const a: u32 = 0;
const b: u32 = undefined;
_ = a + b;  // Now a compile error at comptime!
```

## New Language Features

### 1. **Non-Exhaustive Enum Switch Improvements**

Can now mix explicit tags with `_` prong:
```zig
switch (enum_val) {
    .special_case_1 => foo(),
    .special_case_2 => bar(),
    _, .special_case_3 => baz(),  // NEW: _ can appear with other cases
}
```

Can have both `else` and `_`:
```zig
switch (value) {
    .A => {},
    .C => {},
    else => {}, // Named tags (like .B)
    _ => {},    // Unnamed tags
}
```

### 2. **Vector Boolean Operations**

Binary and boolean operators now work on vectors of `bool`:
- Binary not, and, or, xor
- Boolean not

### 3. **`@ptrCast` Extensions**

Can now cast single-item pointer to slice:
```zig
const val: u32 = 1;
const bytes: []const u8 = @ptrCast(&val);
// Returns slice with same number of bytes
```

**Future change planned:** This will move to `@memCast` for safety.

### 4. **Lossy Int-to-Float Coercion Now an Error**

At comptime, int-to-float coercions that lose precision now error:
```zig
const val: f32 = 123_456_789;  // Compile error!
const val: f32 = 123_456_789.0; // OK - explicit float
```

### 5. **Switch Continue**

Can now `continue` to a labeled switch:
```zig
sw: switch (@as(i32, 5)) {
    5 => continue :sw 4,
    2...4 => |v| {
        if (v > 3) continue :sw 2;
        continue :sw 1;
    },
    1 => return,
    else => unreachable,
}
```

This is like a state machine - useful for dispatch loops.

### 6. **Inline `else` Prongs**

Type-safe alternative to inline for loops:
```zig
fn withSwitch(any: AnySlice) usize {
    return switch (any) {
        inline else => |slice| slice.len,
    };
}
```

Can capture union tag:
```zig
switch (u) {
    inline else => |num, tag| {
        if (tag == .b) return @intFromFloat(num);
        return num;
    },
}
```

## Backend and Compiler Changes

### 1. **Self-Hosted x86_64 Backend Now Default (Debug Mode)**

**HUGE CHANGE:** Zig's self-hosted x86_64 backend is now the default for Debug builds!

**Benefits:**
- **~5x faster compilation** than LLVM
- Supports incremental compilation
- More correct than LLVM (1984/2008 vs 1977/2008 behavior tests)
- Fixes 60+ LLVM bugs

**Caveats:**
- Not available on NetBSD, OpenBSD, Windows yet (linker limitations)
- Machine code is slower than LLVM (but compiles faster)
- Some bugs still exist

**Override if needed:**
```bash
zig build-exe -fllvm  # Use LLVM instead
```

### 2. **New aarch64 Backend (Work in Progress)**

New self-hosted backend for ARM64:
- Currently 84% complete (1656/1972 tests)
- Not yet usable for real code
- Expected to be faster than x86_64 backend
- Will be default in future release

### 3. **Incremental Compilation Progress**

Now stable with `-fno-emit-bin`:
```bash
zig build --watch -fincremental -Dno-bin
```

**Great for compile error checking in large projects!**

### 4. **Better Parallelization**

- Semantic Analysis, Code Generation, and Linking now run in parallel
- Code generation can use multiple threads
- ~27% faster builds for Zig compiler itself (13.8s → 10.0s)

### 5. **UBSan Control**

More control over C undefined behavior sanitizer:
```bash
-fsanitize-c=trap   # SIGILL on UB, smaller code
-fsanitize-c=full   # Runtime with messages, larger code
```

In std.Build: `sanitize_c` field now takes `.off`, `.trap`, or `.full`

## Standard Library Changes

### 1. **Progress Status API**

New terminal integration:
```zig
std.Progress.setStatus(.working)  // or .success, .failure, .failure_working
```

Integrates with `--watch` to show build status in terminal!

### 2. **Test Object Files**

New ability to build tests as objects instead of executables:
```bash
zig test-obj file.zig  # CLI
```

```zig
// Build system:
const tests = b.addTest(.{
    .emit_object = true,
    // ... other options
});
```

Useful for linking tests into external harnesses.

### 3. **`zig init` Templates**

- Default template now shows module + executable pattern
- New `--minimal` / `-m` flag for experienced users

## C Interop Changes

### 1. **FreeBSD Cross-Compilation**

Zig now provides:
- Stub libraries for dynamic libc
- All system and libc headers
- For FreeBSD 14+

### 2. **NetBSD Cross-Compilation**

Zig now provides:
- Stub libraries for dynamic libc
- All system and libc headers
- For NetBSD 10.1+

### 3. **glibc 2.42 Available**

### 4. **Static glibc Linking**

Now allowed natively (but not recommended):
```bash
zig build-exe -target native-linux-gnu -static
```

### 5. **zig cc Improvements**

Now properly respects `-static` and `-dynamic` flags.

### 6. **New "zig libc" Library**

Zig is beginning to unify common code between musl, wasi-libc, and MinGW-w64:
- Rewriting common functions in Zig
- Long-term goal: eliminate upstream C code dependency
- Contributor-friendly (see issue #2879)

### 7. **Zig C++ Support Removed**

Sorry! The code wasn't up to quality standards. Errors with "unimplemented" now.

## Important Deprecations and Removals

### Functions/Types Removed:
- `@frameSize`
- `std.io.SeekableStream`
- `std.io.BitReader` / `std.io.BitWriter`
- `std.Io.LimitedReader`
- `std.Io.BufferedReader`
- All old `std.io.*` readers/writers (use new API)

### Build System:
- Removed: `root_source_file` field (use `root_module`)

### Data Structures:
- `std.BoundedArray` (see migration above)
- `std.fifo.LinearFifo`
- Multiple ring buffer implementations

## Critical New Concepts

### Result Location Semantics

Zig codifies "Result Location Semantics" - every expression has optional:
1. **Result type** - what type the expression should have
2. **Result location** - where the value should be placed

Example:
```zig
const x: u32 = 42;
// The type annotation provides result type u32 to the expression `42`
```

This enables:
- Type inference
- Cast builtins like `@intCast` without explicit type arguments
- Avoiding intermediate copies
- Preventing temporary values for pinned types

**Important for aggregate initialization:**
```zig
foo = .{ .a = x, .b = y };
// Desugars to:
// foo.a = x;
// foo.b = y;
// This means you CAN'T swap struct fields this way!
```

## Migration Checklist

If you're updating code from pre-0.15.1:

1. ✅ **Remove all `usingnamespace`** - See migration patterns above
2. ✅ **Update all I/O code** - Reader/Writer API completely changed
3. ✅ **Update custom `format` methods** - New signature
4. ✅ **Change `{}` to `{f}` or `{any}`** in format strings
5. ✅ **Update inline assembly clobbers** (or run `zig fmt`)
6. ✅ **Migrate away from `BoundedArray`**
7. ✅ **Update compression code** if using zlib/gzip
8. ✅ **Update HTTP client/server code** if applicable
9. ✅ **Fix build.zig** if using deprecated fields
10. ✅ **Update `ArrayList` usage** (consider `ArrayListUnmanaged`)
11. ✅ **Check for undefined arithmetic** compile errors

## Performance Tips

1. **Try the self-hosted backend** for development (5x faster compiles)
2. **Use `--watch -fincremental -Dno-bin`** for fast error checking
3. **Use `--time-report`** to find slow compilation points
4. **Consider making stdout buffer global** (common pattern)

## Documentation and Learning

- Use `zig std` to browse standard library docs locally
- Release notes are comprehensive (much more than this summary!)
- Most breaking changes have compile errors that guide you
- Use `-freference-trace` to find all format string breakage

## What's Next (0.16.0 Roadmap)

The next release will focus on:
1. **Async I/O** - New `std.Io` interface for event loops
2. **aarch64 backend** - Making it production-ready
3. **Linker improvements** - For incremental compilation

## Key Takeaways

This release represents Zig's largest breaking changes before 1.0, particularly:
- Removal of `usingnamespace` (improves language simplicity)
- Complete I/O overhaul (better performance, simpler API)
- Self-hosted backend becoming default (much faster compilation)

The pain is intentional and temporary - these changes are necessary to reach a stable 1.0 language.

---

## Quick Reference: Common Patterns

### Modern I/O Pattern
```zig
var buffer: [4096]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buffer);
const w: *std.Io.Writer = &writer.interface;
try w.print("text\n", .{});
try w.flush();
```

### Mixin Pattern (post-usingnamespace)
```zig
pub fn Mixin(comptime T: type) type {
    return struct {
        pub fn method(m: *@This()) void {
            const parent: *T = @alignCast(@fieldParentPtr("mixin_field", m));
            // work with parent
        }
    };
}
const Foo = struct {
    data: u32,
    mixin_field: Mixin(Foo) = .{},
};
// Usage: foo.mixin_field.method()
```

### Feature Detection (post-usingnamespace)
```zig
pub const feature = if (have_feature) actual_value else {};
// Test:
if (@TypeOf(module.feature) == void) return error.SkipZigTest;
```

Good luck! The Zig language is getting cleaner and faster.

# Zig Format Specifiers Guide

## Overview

In Zig, format strings use `{}` placeholders with optional format specifiers. The format is:
```
{[argument][specifier]:[fill][alignment][width].[precision]}
```

## Basic Format Specifiers

### Common Specifiers

| Specifier | Type | Description | Example |
|-----------|------|-------------|---------|
| `{s}` | String/Slice | String or slice of u8 | `"hello"`, `[]const u8` |
| `{c}` | Character | Single u8 as ASCII character | `'A'`, `65` |
| `{d}` | Integer | Decimal (base 10) | `1234` → "1234" |
| `{x}` | Integer | Lowercase hexadecimal | `255` → "ff" |
| `{X}` | Integer | Uppercase hexadecimal | `255` → "FF" |
| `{o}` | Integer | Octal (base 8) | `8` → "10" |
| `{b}` | Integer | Binary (base 2) | `5` → "101" |
| `{e}` | Float | Lowercase scientific notation | `1000.0` → "1.0e+03" |
| `{E}` | Float | Uppercase scientific notation | `1000.0` → "1.0E+03" |
| `{}` | Any | Default formatting (see note) | Various |
| `{any}` | Any | Debug formatting | Any type |
| `{f}` | Custom | Call custom `format()` method | Types with format() |
| `{*}` | Pointer | Pointer address | `0x7fff1234` |
| `{u}` | Unicode | Unicode code point | `'⚡'` → "⚡" |

### Important Note on `{}`
In Zig 0.15.x, `{}` is now **ambiguous** if the type has a custom `format()` method:
- You must use `{f}` to explicitly call the format method
- Or use `{any}` to skip the format method
- This prevents accidental behavior changes when adding/removing format methods

## Detailed Examples

### String Formatting (`{s}`)
```zig
const std = @import("std");

// String literals
std.debug.print("Name: {s}\n", .{"Alice"});
// Output: Name: Alice

// Slices
const slice: []const u8 = "world";
std.debug.print("Hello, {s}!\n", .{slice});
// Output: Hello, world!

// Multiple strings
std.debug.print("{s} + {s} = {s}\n", .{"Hello", "World", "Hello World"});
// Output: Hello + World = Hello World
```

### Character Formatting (`{c}`)
```zig
// Single character
std.debug.print("Letter: {c}\n", .{'A'});
// Output: Letter: A

// Integer as ASCII character
std.debug.print("Code 65: {c}\n", .{65});
// Output: Code 65: A

// Useful for displaying bytes
const byte: u8 = 0x41;
std.debug.print("Byte as char: {c}\n", .{byte});
// Output: Byte as char: A
```

### Integer Formatting

#### Decimal (`{d}`)
```zig
std.debug.print("Count: {d}\n", .{42});
// Output: Count: 42

std.debug.print("Signed: {d}\n", .{@as(i32, -123)});
// Output: Signed: -123
```

#### Hexadecimal (`{x}` and `{X}`)
```zig
std.debug.print("Lowercase hex: 0x{x}\n", .{255});
// Output: Lowercase hex: 0xff

std.debug.print("Uppercase hex: 0x{X}\n", .{255});
// Output: Uppercase hex: 0xFF

// Useful for memory addresses and byte dumps
std.debug.print("Address: 0x{x:0>16}\n", .{0x7fff_1234_5678});
// Output: Address: 0x00007fff12345678
```

#### Octal (`{o}`)
```zig
std.debug.print("Octal: {o}\n", .{64});
// Output: Octal: 100

std.debug.print("Permissions: 0o{o}\n", .{0o755});
// Output: Permissions: 0o755
```

#### Binary (`{b}`)
```zig
std.debug.print("Binary: 0b{b}\n", .{5});
// Output: Binary: 0b101

std.debug.print("Flags: {b:0>8}\n", .{0b1010});
// Output: Flags: 00001010
```

### Float Formatting

#### Default Float
```zig
std.debug.print("Float: {d}\n", .{3.14159});
// Output: Float: 3.14159
```

#### Scientific Notation (`{e}` and `{E}`)
```zig
std.debug.print("Scientific: {e}\n", .{1234.5});
// Output: Scientific: 1.2345e+03

std.debug.print("Scientific: {E}\n", .{1234.5});
// Output: Scientific: 1.2345E+03
```

### Pointer Formatting (`{*}`)
```zig
const x: i32 = 42;
const ptr = &x;
std.debug.print("Pointer: {*}\n", .{ptr});
// Output: Pointer: i32@7fff1234
```

### Any/Debug Formatting (`{any}`)
```zig
// Works with any type - uses debug representation
const Point = struct { x: i32, y: i32 };
const p = Point{ .x = 10, .y = 20 };

std.debug.print("Point: {any}\n", .{p});
// Output: Point: Point{ .x = 10, .y = 20 }

// Arrays
std.debug.print("Array: {any}\n", .{[_]i32{1, 2, 3}});
// Output: Array: { 1, 2, 3 }

// Slices
const items = [_]u32{10, 20, 30};
std.debug.print("Slice: {any}\n", .{items[0..]});
// Output: Slice: { 10, 20, 30 }
```

### Unicode (`{u}`)
```zig
std.debug.print("Lightning: {u}\n", .{'⚡'});
// Output: Lightning: ⚡

std.debug.print("Emoji: {u}\n", .{'🎉'});
// Output: Emoji: 🎉
```

## Positional Arguments

You can reference arguments by position:

```zig
std.debug.print("{0} {1} {0}\n", .{"echo", "chamber"});
// Output: echo chamber echo

std.debug.print("{1} comes before {0}\n", .{"second", "first"});
// Output: first comes before second
```

## Width, Alignment, and Fill

### Width
```zig
// Minimum width of 10 characters
std.debug.print("'{d:10}'\n", .{42});
// Output: '        42'

std.debug.print("'{s:10}'\n", .{"hi"});
// Output: 'hi        '
```

### Alignment
- `<` - Left align (default for strings)
- `>` - Right align (default for numbers)
- `^` - Center align

```zig
std.debug.print("'{s:<10}'\n", .{"left"});
// Output: 'left      '

std.debug.print("'{s:>10}'\n", .{"right"});
// Output: '     right'

std.debug.print("'{s:^10}'\n", .{"center"});
// Output: '  center  '
```

### Fill Character
```zig
std.debug.print("'{s:*<10}'\n", .{"fill"});
// Output: 'fill******'

std.debug.print("'{d:0>8}'\n", .{42});
// Output: '00000042'

std.debug.print("'{s:=>10}'\n", .{"pad"});
// Output: '=======pad'
```

### Combined
```zig
// Zero-padded hex, width 8, right aligned
std.debug.print("0x{x:0>8}\n", .{0xABCD});
// Output: 0x0000abcd

// Space-padded decimal, width 6, right aligned
std.debug.print("Value: {d: >6}\n", .{123});
// Output: Value:    123
```

## Precision

For floating-point numbers, precision controls decimal places:

```zig
std.debug.print("{d:.2}\n", .{3.14159});
// Output: 3.14

std.debug.print("{d:.4}\n", .{3.14159});
// Output: 3.1416

// Combined with width
std.debug.print("{d:8.2}\n", .{3.14159});
// Output: '    3.14'
```

## Custom Format Functions (0.15.x)

To create a type with custom formatting:

```zig
const MyType = struct {
    value: i32,

    // NEW signature in Zig 0.15.x
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("MyType({})", .{self.value});
    }
};

const obj = MyType{ .value = 42 };

// Must explicitly use {f} to call format method
std.debug.print("Object: {f}\n", .{obj});
// Output: Object: MyType(42)

// Use {any} to skip format method and get debug output
std.debug.print("Debug: {any}\n", .{obj});
// Output: Debug: MyType{ .value = 42 }
```

### Alternative Pattern: Using `std.fmt.Alt`

For stateful formatting:

```zig
pub fn formatHex(value: MyType) std.fmt.Alt(F, F.format) {
    return .{ .data = .{ .value = value.value, .hex = true } };
}

const F = struct {
    value: i32,
    hex: bool,

    pub fn format(
        self: F,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        if (self.hex) {
            try writer.print("0x{x}", .{self.value});
        } else {
            try writer.print("{d}", .{self.value});
        }
    }
};

// Usage:
std.debug.print("{f}\n", .{value.formatHex()});
```

## Common Patterns

### Byte Arrays / Memory Dumps
```zig
const bytes = [_]u8{ 0x48, 0x65, 0x6C, 0x6C, 0x6F };

// As hex
for (bytes) |byte| {
    std.debug.print("{x:0>2} ", .{byte});
}
// Output: 48 65 6c 6c 6f

// As characters
for (bytes) |byte| {
    std.debug.print("{c}", .{byte});
}
// Output: Hello
```

### Error Messages
```zig
const char: u8 = '!';
std.debug.print("Unexpected character: '{c}' (0x{x:0>2})\n", .{char, char});
// Output: Unexpected character: '!' (0x21)
```

### Logging with Context
```zig
const file = "input.txt";
const line: usize = 42;
const col: usize = 15;
std.debug.print("{s}:{d}:{d}: error: {s}\n",
    .{file, line, col, "unexpected token"});
// Output: input.txt:42:15: error: unexpected token
```

### Table Formatting
```zig
const names = [_][]const u8{"Alice", "Bob", "Charlie"};
const scores = [_]i32{95, 87, 92};

std.debug.print("Name       Score\n", .{});
std.debug.print("----------------\n", .{});
for (names, scores) |name, score| {
    std.debug.print("{s:<10} {d:>5}\n", .{name, score});
}
// Output:
// Name       Score
// ----------------
// Alice         95
// Bob           87
// Charlie       92
```

## Complete Reference Table

| Format | Type | Alignment | Notes |
|--------|------|-----------|-------|
| `{s}` | []const u8, string | Left | For text |
| `{c}` | u8 | N/A | ASCII character |
| `{u}` | u21 | N/A | Unicode code point |
| `{d}` | Integer | Right | Decimal |
| `{d:.N}` | Float | Right | N decimal places |
| `{x}` | Integer | Right | Hex lowercase |
| `{X}` | Integer | Right | Hex uppercase |
| `{o}` | Integer | Right | Octal |
| `{b}` | Integer | Right | Binary |
| `{e}` | Float | Right | Scientific lowercase |
| `{E}` | Float | Right | Scientific uppercase |
| `{*}` | Pointer | Right | Address |
| `{any}` | Any | Varies | Debug representation |
| `{f}` | Custom | Varies | Call format() method |
| `{}` | - | - | Ambiguous, prefer {any} or {f} |

## Modifiers Summary

```
{[position][specifier]:[fill][alignment][width].[precision]}
```

- **position**: `0`, `1`, `2`, ... (argument index)
- **specifier**: `s`, `c`, `d`, `x`, `X`, `o`, `b`, `e`, `E`, `*`, `u`, `any`, `f`
- **fill**: Any character (default is space)
- **alignment**: `<` (left), `>` (right), `^` (center)
- **width**: Minimum field width
- **precision**: Decimal places for floats (`.2`, `.4`, etc.)

## Examples for Your Case

For your error message:
```zig
const unexpected_char: u8 = '!';

// Basic
std.debug.print("Unexpected character: '{c}'\n", .{unexpected_char});
// Output: Unexpected character: '!'

// With hex code
std.debug.print("Unexpected character: '{c}' (0x{x:0>2})\n",
    .{unexpected_char, unexpected_char});
// Output: Unexpected character: '!' (0x21)

// With decimal code
std.debug.print("Unexpected character: '{c}' (code {d})\n",
    .{unexpected_char, unexpected_char});
// Output: Unexpected character: '!' (code 33)

// Full error message
std.debug.print("Error at position {d}: unexpected character '{c}'\n",
    .{42, unexpected_char});
// Output: Error at position 42: unexpected character '!'
```

## Tips

1. **Use `{s}` for strings/slices** - This is the most common format specifier
2. **Use `{c}` for single bytes as characters** - Useful in parsers/lexers
3. **Use `{any}` for debugging** - Shows structure of any type
4. **Use `{x}` for hex dumps** - Common in low-level code
5. **Use `{d}` for numbers** - Both integers and floats
6. **Pad with zeros using `:0>`** - `{d:0>8}` for fixed-width numbers
7. **In 0.15.x, always specify `{f}` or `{any}`** for types with format methods

## Common Mistakes

```zig
// ❌ DON'T: Using {} for custom types (ambiguous in 0.15.x)
std.debug.print("{}\n", .{my_custom_type});

// ✅ DO: Be explicit
std.debug.print("{f}\n", .{my_custom_type});  // Call format()
std.debug.print("{any}\n", .{my_custom_type}); // Debug output

// ❌ DON'T: Using {s} for integers
std.debug.print("{s}\n", .{42}); // Type error!

// ✅ DO: Use {d} for numbers
std.debug.print("{d}\n", .{42});

// ❌ DON'T: Forget the colon before modifiers
std.debug.print("{d10}\n", .{42}); // Error!

// ✅ DO: Include the colon
std.debug.print("{d:10}\n", .{42});
```

Hope this helps! The format string system is very powerful once you understand the specifiers.
