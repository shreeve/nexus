# Zig 0.16.0 Updates

This document provides a comprehensive overview of the changes and new features in **Zig 0.16.0** (released April 16, 2026). If your knowledge of Zig stops at 0.15.x (or earlier), this is the fastest way to get up to speed on the latest language, standard library, build system, compiler, linker, and toolchain changes.

Zig 0.16.0 represents **8 months of work**, 244 contributors, and 1183 commits. The headline feature is **"I/O as an Interface"** — a massive, pervasive reworking comparable to 0.15.1's "Writergate" but arguably larger in surface area. Alongside it, there are substantial language changes, a new "Juicy Main" entry point, the removal of `@Type` in favor of focused builtins, `@cImport` migration to the build system, a new ELF linker, a Smith-based fuzzer, and much more.

---

## Table of Contents

1. [The One Big Theme: I/O as an Interface](#the-one-big-theme-io-as-an-interface)
2. [Critical Breaking Changes (Quick Migration Checklist)](#critical-breaking-changes-quick-migration-checklist)
3. [Language Changes](#language-changes)
4. [Standard Library Changes](#standard-library-changes)
5. [I/O as an Interface (Deep Dive)](#io-as-an-interface-deep-dive)
6. ["Juicy Main" and Non-Global Env/Args](#juicy-main-and-non-global-envargs)
7. [File System, Networking, Process Migration](#file-system-networking-process-migration)
8. [Sync Primitives, Time, Entropy](#sync-primitives-time-entropy)
9. [Compression, Debug Info, Misc](#compression-debug-info-misc)
10. [Build System Changes](#build-system-changes)
11. [Compiler and Backends](#compiler-and-backends)
12. [Linker: New ELF Linker](#linker-new-elf-linker)
13. [Fuzzer: Smith](#fuzzer-smith)
14. [Toolchain](#toolchain)
15. [Target Support](#target-support)
16. [Migration Cheat Sheet](#migration-cheat-sheet)
17. [Compile-Error Decoder](#compile-error-decoder)
18. [Common Bad Assumptions from 0.15.x](#common-bad-assumptions-from-015x)
19. [Roadmap](#roadmap)

---

## The One Big Theme: I/O as an Interface

Starting with Zig 0.16.0, **all input and output functionality requires being passed an `Io` instance.** Generally, anything that potentially blocks control flow or introduces nondeterminism is now owned by the I/O interface.

```zig
const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    try std.Io.File.stdout().writeStreamingAll(io, "Hello, world!\n");
}
```

The `Io` parameter now flows through:

- File system operations (`std.Io.Dir`, `std.Io.File`)
- Networking (`std.Io.net`)
- Process management (`std.process.spawn`, `std.process.run`, `std.process.replace`)
- Sync primitives (mutex, condition, event, semaphore, rwlock, futex)
- Time / clocks (`std.Io.Timestamp`)
- Entropy (`io.random`, `io.randomSecure`)
- HTTP client (`std.http.Client`)
- Termination / cancelation (`error.Canceled`)
- Concurrency primitives (Future, Group, Batch, Select)

Implementations shipped with 0.16.0:

| Implementation | Status | Notes |
|---|---|---|
| `Io.Threaded` | **Feature-complete, recommended** | Thread-based; supports cancelation, concurrency. Default from Juicy Main. |
| `Io.Evented` | Experimental, WIP | M:N / green threads / stackful coroutines. Informs API evolution. |
| `Io.Uring` | Proof-of-concept | Linux io_uring backend; lacks networking, error handling, etc. |
| `Io.Kqueue` | Proof-of-concept | Just enough to validate design. |
| `Io.Dispatch` | Proof-of-concept | macOS Grand Central Dispatch. |
| `Io.failing` | Utility | Simulates a system that supports **no** I/O operations — every I/O call returns an error. Useful for unit-testing code paths that must gracefully refuse I/O. |

When you have no `Io` and need one:

```zig
var threaded: Io.Threaded = .init_single_threaded;
const io = threaded.io();
```

…but prefer to accept `io: Io` as a parameter (like `allocator: Allocator`). For tests, use `std.testing.io` (like `std.testing.allocator`).

---

## Critical Breaking Changes (Quick Migration Checklist)

If you're upgrading from Zig 0.15.x, expect to touch almost every file that does any I/O or uses `@Type`. Here's the top-level checklist:

- [ ] **Expect many std APIs to require an `Io` handle.** Propagate one through any call path that does I/O, concurrency, sync, time, or entropy. (You can still opt out in leaf code by constructing a local `Io.Threaded`.)
- [ ] **Consider "Juicy Main"** — `pub fn main() !void` still compiles; adopting `pub fn main(init: std.process.Init) !void` (or `Init.Minimal`) is optional but recommended, since it gives you a pre-initialized `io`, `gpa`, `arena`, `environ_map`, `preopens`, and argv.
- [ ] **Replace `@Type(...)`** with one of `@Int`, `@Struct`, `@Union`, `@Enum`, `@Pointer`, `@Fn`, `@Tuple`, `@EnumLiteral`. `@Type` and reifying error sets are gone.
- [ ] **`@cImport` is deprecated** — migrate to `b.addTranslateC(...)` in `build.zig`.
- [ ] **`std.fs.*` → `std.Io.Dir` / `std.Io.File`**, with an `Io` parameter added to most calls.
- [ ] **`std.net.*` → `std.Io.net.*`**.
- [ ] **`std.time.Instant` / `Timer` / `timestamp()` → `std.Io.Timestamp`**.
- [ ] **`std.Thread.Mutex` / `Condition` / `ResetEvent` / `Semaphore` / `RwLock` / `Futex` → `std.Io.*` equivalents.**
- [ ] **`std.process.getCwd` → `std.process.currentPath`**.
- [ ] **`std.posix.mlock*`, `mmap` flag style → `std.process.lockMemory*` and struct-field flag style.**
- [ ] **`std.process.Child.spawn` / `run` / `execv` → `std.process.spawn` / `run` / `replace`** (free-functions accepting `Io`).
- [ ] **`std.crypto.random` and `std.posix.getrandom` → `io.random(&buffer)`**; `std.Random` use → `std.Random.IoSource`.
- [ ] **`std.Thread.Pool` is gone** — switch to `Io.async` / `Io.Group`.
- [ ] **`std.ArrayHashMap`, `std.AutoArrayHashMap`, `std.StringArrayHashMap`** (managed) are gone; `*Unmanaged` renamed to `array_hash_map.{Custom, Auto, String}`.
- [ ] **`std.heap.ThreadSafeAllocator` is gone**; `ArenaAllocator` is now lock-free and threadsafe by default.
- [ ] **`std.io.fixedBufferStream` → `std.Io.Reader.fixed(data)` / `std.Io.Writer.fixed(buffer)`.**
- [ ] **`@intFromFloat` deprecated** — use `@trunc`/`@floor`/`@ceil`/`@round` to convert floats to ints.
- [ ] **Packed types:** enums/packed structs/packed unions with *implicit* backing ints are **no longer valid `extern` types** — add an explicit `(u8)`, `(u16)`, etc.
- [ ] **Pointers are no longer allowed in `packed struct` / `packed union`** — use `usize` + `@ptrFromInt`/`@intFromPtr`.
- [ ] **Packed union fields must all have the same `@bitSizeOf`.**
- [ ] **Returning `&local_var` is now a compile error** ("expired local variable").
- [ ] **Runtime vector indexing is forbidden** — coerce the vector to an array first.
- [ ] **Vector ↔ array `@ptrCast` is gone** — use coercion instead.
- [ ] **Legacy package hash format is removed** — all packages need `fingerprint` and enum-literal `name`.
- [ ] **`--prominent-compile-errors` removed** — use `--error-style minimal` instead.

---

## Language Changes

### 1. `@Type` Replaced With Individual Type-Creating Builtins

`@Type` is gone. Each "info category" now has a dedicated builtin with a more ergonomic signature:

```zig
@EnumLiteral() type
@Int(signedness, bits) type
@Tuple(field_types) type
@Pointer(size, attrs, Element, sentinel) type
@Fn(param_types, param_attrs, ReturnType, attrs) type
@Struct(layout, BackingInt, field_names, field_types, field_attrs) type
@Union(layout, ArgType, field_names, field_types, field_attrs) type
@Enum(TagInt, mode, field_names, field_values) type
```

Examples:

```zig
@Type(.{ .int = .{ .signedness = .unsigned, .bits = 10 } })
// ⬇️
@Int(.unsigned, 10)
```

```zig
@Type(.{ .pointer = .{ .size = .one, .is_const = true, .child = u32, ... } })
// ⬇️
@Pointer(.one, .{ .@"const" = true }, u32, null)
```

Tips:

- Use `&@splat(.{})` to pass "default" attributes for every field/param.
- `@Struct`/`@Union`/`@Fn`/`@Enum` use a "struct of arrays" layout — names, types, and attrs are separate arrays.
- **There is no `@Float`, `@Array`, `@Optional`, `@ErrorUnion`, `@Opaque`, `@ErrorSet`** — use native syntax (`f32`, `[N]T`, `?T`, `E!T`, `opaque {}`) or `std.meta.Float` where needed.
- **Reifying error sets is no longer possible.** Declare them explicitly via `error{ ... }`.
- Reifying tuple types with `comptime` fields is also no longer possible.

**Corresponding `std.meta` helpers are deprecated:**

- `std.meta.Int(signedness, bits)` → **`@Int(signedness, bits)`** (deprecated)
- `std.meta.Tuple(types)` → **`@Tuple(types)`** (deprecated)

`std.meta.Float` is retained because there is intentionally no `@Float` builtin (only 5 runtime float types exist).

### 2. `@cImport` Migrating to the Build System

`@cImport` is deprecated. Use `b.addTranslateC` in `build.zig`:

```zig
const translate_c = b.addTranslateC(.{
    .root_source_file = b.path("src/c.h"),
    .target = target,
    .optimize = optimize,
});
translate_c.linkSystemLibrary("glfw", .{});

const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{ .{ .name = "c", .module = translate_c.createModule() } },
    }),
});
```

And in your Zig code: `const c = @import("c");`

For more customization, use the [official `translate-c` package](https://codeberg.org/ziglang/translate-c).

### 3. `switch` Enhancements

- **`packed struct` and `packed union` are allowed as prong items** (compared by backing integer).
- **Decl literals / `@enumFromInt`** and anything needing a result type work as prong items.
- Union tag captures now allowed on **every** prong (not just `inline`).
- Prongs may contain **errors not in the switched error set** if they resolve to `=> comptime unreachable`.
- Prong captures may no longer all be discarded.
- Switching on `void` no longer requires `else`.
- Switching on one-possible-value types has far fewer bugs now.

### 4. Packed Type Rules Tightened

- **Forbid unused bits in packed unions**: all fields must share the same `@bitSizeOf` as a backing integer:

  ```zig
  const U = packed union { x: u8, y: u16 }; // ❌
  const U = packed union(u16) {
      x: packed struct(u16) { data: u8, padding: u8 = 0 },
      y: u16,
  }; // ✅
  ```

- **Packed unions can now declare explicit backing ints**: `packed union(u16) { ... }`.
- **Fields of `packed struct` / `packed union` can no longer be pointers.** Note: this restriction applies *only* inside `packed` types. Pointers are still fine in normal structs, `extern struct`/`extern union`, tagged unions, arrays, slices, optionals, etc. For tagged-pointer / NaN-boxing patterns, store a `usize` field and convert at use sites with `@ptrFromInt` / `@intFromPtr`. Rationale: non-byte-aligned pointers can't be represented in most binary formats, and some targets have fat pointers (extra metadata bits) that can't meaningfully be packed into an integer.
- **Enums with inferred tag types and packed types with inferred backing types are no longer valid `extern` types.** Always spell out the tag/backing int in extern contexts.

### 5. Small Integers Coerce to Floats

If every value of an integer type fits losslessly in a float, the coercion is implicit (no `@floatFromInt`):

```zig
var foo_int: u24 = 123;
var foo_float: f32 = foo_int; // ok — u24 fits in f32 significand

var bar_int: u25 = 123;
var bar_float: f32 = @floatFromInt(bar_int); // still required
```

### 6. Float → Int via `@floor`/`@ceil`/`@round`/`@trunc`

```zig
const actual: u8 = @round(12.5); // → 13
```

**`@intFromFloat` is now deprecated** (it's equivalent to `@trunc` + assignment).

### 7. Unary Float Builtins Forward Result Type

Builtins like `@sqrt`, `@sin`, `@cos`, `@exp`, `@log`, `@floor`, etc. now forward the result type, so this works:

```zig
const x: f64 = @sqrt(@floatFromInt(N));
```

### 8. Runtime Vector Indexing Forbidden

```zig
for (0..vector_len) |i| _ = vector[i]; // ❌
```

Instead, coerce to an array:

```zig
const vt = @typeInfo(@TypeOf(vector)).vector;
const array: [vt.len]vt.child = vector;
for (&array) |elem| _ = elem;
```

Also, **vectors and arrays no longer support in-memory coercion** (e.g. `@ptrCast` between `*[4]i32` and `*@Vector(4, i32)` is gone). Use coercion. If you have `anyerror![4]i32`, unwrap before coercing.

### 9. No Returning Pointers to Trivially-Local Addresses

```zig
fn foo() *i32 {
    var x: i32 = 1234;
    return &x; // error: returning address of expired local variable 'x'
}
```

More such diagnostics are planned ([issue #25312](https://github.com/ziglang/zig/issues/25312)).

### 10. Equality Comparisons on Packed Unions

Packed unions are now directly comparable by their backing integer without wrapping in a packed struct.

### 11. Lazy Field Analysis

`struct`, `union`, `enum`, and `opaque` types are now only resolved when their size or a field type is actually needed. **Files (which are structs) and types used purely as namespaces no longer trigger field analysis.** Non-dereferenced `*T` no longer requires `T` to be resolved.

### 12. Pointers to Comptime-Only Types Are No Longer Comptime-Only

`*comptime_int`, `[]comptime_int`, and similar can exist at runtime (they just can't be dereferenced at runtime, except for fields that have runtime types).

One practical consequence: you can pass a `[]const std.builtin.Type.StructField` to a runtime function and read the `.name` field at runtime.

### 13. `*T` Now Distinct from `*align(1) T` Where Natural Align ≠ 1

They still coerce to each other freely — but they print and compare as different types. Think of it like `u32` vs `c_uint`.

### 14. Simplified Dependency Loop Rules

New dependency loops are possible, but the error messages are now *far* clearer, with a numbered chain of "uses X here" notes. Zig 0.16 significantly reworks internal type resolution (see [Compiler → Reworked Type Resolution](#4-reworked-type-resolution)).

### 15. Zero-bit Tuple Fields No Longer Implicitly `comptime`

```zig
const S = struct { void };
@typeInfo(S).@"struct".fields[0].is_comptime
// 0.15: true
// 0.16: false  (but the value is still comptime-known in practice)
```

Types `struct { void }` and `struct { comptime void = {} }` are no longer equal.

---

## Standard Library Changes

### Added

- `Io.Dir.renamePreserve` — rename without clobbering destination.
- `Io.net.Socket.createPair`
- `Io.Dir.hardLink`, `Io.Dir.Reader`, `Io.Dir.setFilePermissions`, `Io.Dir.setFileOwner`
- `Io.File.NLink`
- `std.Io.Writer.Allocating` gained an `alignment: std.mem.Alignment` field.

### Removed

- `SegmentedList`
- `meta.declList`
- `Io.GenericWriter`, `Io.AnyWriter`, `Io.null_writer`, `Io.CountingReader`
- `Io.GenericReader`, `Io.AnyReader`, `FixedBufferStream`
- `std.Thread.Pool` (use `Io.async` / `Io.Group`)
- `std.Thread.Mutex.Recursive`
- `std.once` (hand-roll it, or avoid global state)
- `std.heap.ThreadSafeAllocator` (anti-pattern; pick a lock-free allocator)
- `fs.getAppDataDir` (see [known-folders](https://github.com/ziglibs/known-folders))
- `Thread.Pool.spawnWg` pattern → `Io.Group.async` + `Io.Group.wait`
- Windows networking via `ws2_32.dll` — replaced by direct AFD
- `std.builtin.subsystem` (detect at runtime if needed)
- Many `std.posix.*` and `std.os.windows.*` mid-level functions (go higher → `std.Io`, or lower → `std.posix.system`)
- `std.crypto.random`, `std.posix.getrandom` — use `io.random` / `io.randomSecure`
- `std.fs.wasi.Preopens` → `std.process.Preopens`

### Renamed

Container migrations (managed → unmanaged, then renamed):

```
std.ArrayHashMap              → (removed)
std.AutoArrayHashMap          → (removed)
std.StringArrayHashMap        → (removed)
std.ArrayHashMapUnmanaged     → std.array_hash_map.Custom
std.AutoArrayHashMapUnmanaged → std.array_hash_map.Auto
std.StringArrayHashMapUnmanaged → std.array_hash_map.String
```

`fmt` module renames:

```
std.fmt.Formatter      → std.fmt.Alt
std.fmt.format         → std.Io.Writer.print
std.fmt.FormatOptions  → std.fmt.Options
std.fmt.bufPrintZ      → std.fmt.bufPrintSentinel
```

Error set renames:

```
error.RenameAcrossMountPoints    → error.CrossDevice
error.NotSameFileSystem          → error.CrossDevice
error.SharingViolation           → error.FileBusy
error.EnvironmentVariableNotFound → error.EnvironmentVariableMissing
```

Notable behavior change: `std.Io.Dir.rename` now returns `error.DirNotEmpty` rather than `error.PathAlreadyExists`.

### `Io.Writer` / `Io.Reader` Conveniences

Fixed-buffer reader/writer replaces `FixedBufferStream`:

```zig
var reader: std.Io.Reader = .fixed(data);
var writer: std.Io.Writer = .fixed(buffer);
```

LEB128:

```
std.leb.readUleb128 → std.Io.Reader.takeLeb128
std.leb.readIleb128 → std.Io.Reader.takeLeb128
```

### `heap.ArenaAllocator` Now Threadsafe & Lock-Free

`ArenaAllocator` can now back an `Io` instance (because it no longer depends on mutexes). Single-thread perf is comparable; multi-thread ~up to 7 threads shows slight speedup vs previous "wrap in ThreadSafe" pattern. (`DebugAllocator` is planned to follow.)

### Other Standard Library Changes

- `math.sign` returns the smallest integer type that fits the possible outputs.
- `tar.extract` now sanitizes path traversal.
- `BitSet` / `EnumSet`: `initEmpty` / `initFull` → decl literals (`.empty`, `.full`).
- `std.crypto` gains **AES-SIV**, **AES-GCM-SIV**, and **Ascon-AEAD / Ascon-Hash / Ascon-CHash** (NIST SP 800-232).
- Certificate auto-fetching on Windows is now triggered automatically.
- `PriorityQueue` / `PriorityDequeue`: `init` → `.empty`, `add*` → `push*`, `remove*OrNull` → `pop*`.

---

## I/O as an Interface (Deep Dive)

### Futures

Task-level abstraction based on functions.

- `io.async(func, .{args...})` — creates `Future(T)`. Always infallible; may execute synchronously.
- `io.concurrent(func, .{args...})` — like `async`, but *must* be concurrent. Can fail with `error.ConcurrencyUnavailable`.
- `future.await(io)` — block until done; returns the function's return value.
- `future.cancel(io)` — request cancelation and await. Idempotent.

> ⚠️ **API-shape note.** The free-function spawn (`io.async(func, .{args...})`) passes the target function's args as the tuple — **`io` itself is not in the tuple** (it's the receiver). For `Io.Group`, by contrast, `io` is the **first argument**: `group.async(io, func, .{args...})`. The two shapes are intentional; don't mix them up.

Pattern for resource-returning futures:

```zig
var foo_future = io.async(foo, .{args});
defer if (foo_future.cancel(io)) |resource| resource.deinit() else |_| {};

const result = try foo_future.await(io);
```

If the task returns a bare `void`, `_ = foo_future.cancel(io) catch {};` is enough.

### Groups

For many tasks with the same lifetime — O(1) overhead per spawn.

```zig
var group: Io.Group = .init;
defer group.cancel(io);

for (items) |item| group.async(io, workItem, .{ io, item });

try group.await(io);
```

### Cancelation

> 🗒️ **Spelling note**: the Zig team explicitly spells it "**cancelation**" (single `l`) — adopt this in your APIs, docs, and tests to match the ecosystem.

- Cancelation requests may or may not be acknowledged.
- If acknowledged, I/O functions return `error.Canceled`.
- `io.checkCancel` — manual cancelation point (rarely needed).
- `io.recancel()` — re-arm after handling `error.Canceled`.
- `io.swapCancelProtection()` — declare that `error.Canceled` is unreachable in a block.

Handling rules:
1. Propagate `error.Canceled`, **or**
2. `io.recancel()` and don't propagate, **or**
3. Use `io.swapCancelProtection()` when it's definitively unreachable.

Only the requester can soundly ignore `error.Canceled`.

### Batch

A low-level concurrency primitive that works at an **operation** layer rather than the function layer. Eligible ops today:

- `FileReadStreaming`
- `FileWriteStreaming`
- `DeviceIoControl`
- `NetReceive`

Batch is efficient and portable but less ergonomic than Future. Use Future to prototype; drop to Batch later if task overhead matters. `operateTimeout` will eventually work on anything operation-backed.

### Select, Queue, Clock/Duration/Timestamp/Timeout

- `Select` — wait until one (or more) of a set of tasks finishes; task-level analogue of Batch.
- `Queue(T)` — MPMC, thread-safe, configurable buffer size; producers/consumers suspend when full/empty.
- `Clock`, `Duration`, `Timestamp`, `Timeout` — unit-safe time types.

### HTTP Client Example

```zig
var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
defer http_client.deinit();

var request = try http_client.request(.HEAD, .{
    .scheme = "http",
    .host = .{ .percent_encoded = host_name.bytes },
    .port = 80,
    .path = .{ .percent_encoded = "/" },
}, .{});
defer request.deinit();

try request.sendBodiless();

var redirect_buffer: [1024]u8 = undefined;
const response = try request.receiveHead(&redirect_buffer);
std.log.info("received {d} {s}", .{ response.head.status, response.head.reason });
```

This automatically:
- Fires async DNS queries to every configured nameserver.
- Attempts TCP connect to each result the moment it arrives.
- On first success, cancels all in-flight attempts (including DNS).
- Works with `-fsingle-threaded` too.
- Doesn't need `ws2_32.dll` on Windows.

---

## "Juicy Main" and Non-Global Env/Args

### New `main` Signature

Your `main` function may now declare one of three parameter shapes:

```zig
pub fn main() !void { ... }                         // no args / env access
pub fn main(init: std.process.Init.Minimal) !void   // raw argv + environ
pub fn main(init: std.process.Init) !void           // full "Juicy Main"
```

`std.process.Init`:

```zig
pub const Init = struct {
    minimal: Minimal,                      // argv + environ
    arena: *std.heap.ArenaAllocator,       // process-lifetime arena, threadsafe
    gpa: Allocator,                        // default-selected GPA (leak checked in Debug)
    io: Io,                                // target-appropriate Io (leak checked in Debug)
    environ_map: *Environ.Map,             // env as string→string map (not threadsafe)
    preopens: Preopens,                    // WASI preopens; void on other systems

    pub const Minimal = struct {
        environ: Environ,
        args: Args,
    };
};
```

### Environment Variables Are No Longer Global

- `std.os.environ` (previously a global that couldn't be populated without libc) is **gone**.
- Functions needing env should accept a `*const process.Environ.Map` parameter.

Accessing env:

```zig
for (init.environ_map.keys(), init.environ_map.values()) |k, v| {
    std.log.info("{s}={s}", .{ k, v });
}
```

With `Minimal`:

```zig
init.environ.contains(arena, "HOME")
init.environ.containsUnempty(arena, "HOME")
init.environ.containsConstant("EDITOR")
init.environ.getPosix("HOME")           // ?[]const u8
init.environ.getAlloc(arena, "EDITOR")  // ![]const u8
const environ_map = try init.environ.createMap(arena);
```

### CLI Args

Minimal:

```zig
var args = init.args.iterate();
while (args.next()) |arg| ...
```

Juicy:

```zig
const args = try init.minimal.args.toSlice(init.arena.allocator());
```

---

## File System, Networking, Process Migration

### File System: `std.fs.*` → `std.Io.Dir` / `std.Io.File`

Nearly every function gained an `io` parameter. Mechanical changes dominate:

```zig
file.close();  // ⬇️
file.close(io);
```

Absolute-path helpers:

```
fs.makeDirAbsolute       → std.Io.Dir.createDirAbsolute
fs.deleteDirAbsolute     → std.Io.Dir.deleteDirAbsolute
fs.openDirAbsolute       → std.Io.Dir.openDirAbsolute
fs.openFileAbsolute      → std.Io.Dir.openFileAbsolute
fs.accessAbsolute        → std.Io.Dir.accessAbsolute
fs.createFileAbsolute    → std.Io.Dir.createFileAbsolute
fs.deleteFileAbsolute    → std.Io.Dir.deleteFileAbsolute
fs.renameAbsolute        → std.Io.Dir.renameAbsolute
fs.readLinkAbsolute      → std.Io.Dir.readLinkAbsolute
fs.symLinkAbsolute       → std.Io.Dir.symLinkAbsolute
fs.copyFileAbsolute      → std.Io.Dir.copyFileAbsolute
```

Core types/APIs:

```
fs.Dir      → std.Io.Dir
fs.File     → std.Io.File
fs.cwd      → std.Io.Dir.cwd
fs.realpath → std.Io.Dir.realPathFileAbsolute
fs.rename   → std.Io.Dir.rename    (now accepts two Dir params + io)
fs.realpathAlloc → std.Io.Dir.realPathFileAbsoluteAlloc
```

Directory creation:

```
Dir.makeDir     → Dir.createDir
Dir.makePath    → Dir.createDirPath
Dir.makeOpenDir → Dir.createDirPathOpen
```

Self-executable:

```
fs.openSelfExe         → std.process.openExecutable
fs.selfExePath         → std.process.executablePath
fs.selfExePathAlloc    → std.process.executablePathAlloc
fs.selfExeDirPath      → std.process.executableDirPath
fs.selfExeDirPathAlloc → std.process.executableDirPathAlloc
fs.Dir.setAsCwd        → std.process.setCurrentDir
```

File I/O streaming/positional split (a big mental model shift):

```
File.read       → File.readStreaming
File.readv      → File.readStreaming
File.pread      → File.readPositional
File.preadv     → File.readPositional
File.preadAll   → File.readPositionalAll
File.write      → File.writeStreaming
File.writev     → File.writeStreaming
File.pwrite     → File.writePositional
File.pwritev    → File.writePositional
File.writeAll   → File.writeStreamingAll
File.pwriteAll  → File.writePositionalAll
File.copyRange, copyRangeAll → File.writer
```

Permissions & timestamps:

```
File.Mode / PermissionsWindows / PermissionsUnix → File.Permissions
File.default_mode        → File.Permissions.default_file
File.chmod               → File.setPermissions
File.chown               → File.setOwner
File.updateTimes         → File.setTimestamps / File.setTimestampsNow
File.setEndPos / getEndPos → File.setLength / File.length
File.seekTo/By/FromEnd   → Reader.seekTo / Reader.seekBy / Writer.seekTo
File.getPos              → Reader.logicalPos / Writer.logicalPos
File.mode                → File.stat().permissions.toMode
```

Atomic files — the API is reorganized to move random-number generation below the `Io` vtable and integrate with Linux `O_TMPFILE`:

```zig
var atomic_file = try dest_dir.createFileAtomic(io, dest_path, .{
    .permissions = actual_permissions,
    .make_path = true,
    .replace = true,
});
defer atomic_file.deinit(io);

var buffer: [1024]u8 = undefined;
var file_writer = atomic_file.file.writer(io, &buffer);
// ... write ...
try file_writer.flush();
try atomic_file.replace(io); // or set .replace = false and call link()
```

`Io.File.Stat.atime` is now **`?Timestamp`** (filesystems often don't want to / can't report it):

```zig
const atime = stat.atime orelse return error.FileAccessTimeUnavailable;
```

`setTimestamps` takes a struct with `UTIME_NOW`/`UTIME_OMIT`-like flexibility per field.

`fs.Dir.readFileAlloc`:

```zig
const contents = try std.Io.Dir.cwd().readFileAlloc(io, file_name, allocator, .limited(1234));
// error is error.StreamTooLong (not error.FileTooBig)
```

`fs.File.readToEndAlloc`:

```zig
var file_reader = file.reader(&.{});
const contents = try file_reader.interface.allocRemaining(allocator, .limited(1234));
```

Path utilities moved:

```
fs.path          → std.Io.Dir.path
fs.max_path_bytes → std.Io.Dir.max_path_bytes
fs.max_name_bytes → std.Io.Dir.max_name_bytes
```

`std.fs.path.relative` is now pure — pass cwd and env explicitly:

```zig
const cwd_path = try std.process.currentPathAlloc(io, gpa);
defer gpa.free(cwd_path);
const relative = try std.fs.path.relative(gpa, cwd_path, environ_map, from, to);
```

Windows path parsing has been reworked for consistency — `windowsParsePath`/`diskDesignator`/`diskDesignatorWindows` → `parsePath`, `parsePathWindows`, `parsePathPosix`, plus new `getWin32PathType`.

### Selective Directory Walks

New `std.Io.Dir.walkSelectively` avoids wasted `open`/`close` syscalls for directories you'd skip:

```zig
var walker = try dir.walkSelectively(gpa);
defer walker.deinit();

while (try walker.next(io)) |entry| {
    if (failsFilter(entry)) continue;
    if (entry.kind == .directory) try walker.enter(io, entry);
    // ...
}
```

`Walker` gains `depth()` on `Entry` and `leave()` for early-bailing from a subdir.

### Networking

All of `std.net.*` has been migrated to `std.Io.net.*`. Notable:
- **std's networking path on Windows** no longer routes through `ws2_32.dll` — it uses direct AFD access. (Your own code can of course still link and call `ws2_32.dll` if you want to; this is only about `std.Io.net.*`.)
- Cancelation and Batch work correctly.
- `Io.Evented` does not yet implement networking.
- Non-IP networking is still TODO ([#30892](https://codeberg.org/ziglang/zig/issues/30892)).

### Process

Spawn / run / replace are now free functions that take an `Io`:

```zig
// spawn
var child = try std.process.spawn(io, .{
    .argv = argv,
    .stdin = .pipe,
    .stdout = .pipe,
    .stderr = .pipe,
});

// run & capture output
const result = std.process.run(allocator, io, .{ ... });

// replace (execv)
const err = std.process.replace(io, .{ .argv = argv });
```

Memory lock/protect APIs moved to `std.process` with struct-field flag style:

```zig
try std.process.lockMemory(slice, .{ .on_fault = true });
try std.process.lockMemoryAll(.{ .current = true, .future = true });
// mmap / mprotect flags:
// PROT.READ|PROT.WRITE  →  .{ .READ = true, .WRITE = true }
```

CWD querying:

```
std.process.getCwd / getCwdAlloc → std.process.currentPath / currentPathAlloc
```

---

## Sync Primitives, Time, Entropy

### Sync Primitives (Threaded ↔ Evented Portability)

```
std.Thread.ResetEvent → std.Io.Event
std.Thread.WaitGroup  → std.Io.Group
std.Thread.Futex      → std.Io.Futex
std.Thread.Mutex      → std.Io.Mutex
std.Thread.Condition  → std.Io.Condition
std.Thread.Semaphore  → std.Io.Semaphore
std.Thread.RwLock     → std.Io.RwLock
std.once              → (removed; hand-roll or avoid global state)
```

Lock-free primitives (atomics, etc.) do **not** need the `Io` interface.

> ⚠️ `std.Io.Group` is **not just a renamed `WaitGroup`**. It is the task-orchestration primitive described under [Groups](#groups) — tied to `async`/`await`/cancelation semantics. If you were using `WaitGroup` purely as a counting latch, you may prefer `std.Io.Semaphore` or an atomic counter + `std.Io.Event`.

### Time

```
std.time.Instant   → std.Io.Timestamp
std.time.Timer     → std.Io.Timestamp
std.time.timestamp → std.Io.Timestamp.now
```

`Clock.resolution` is now separately queryable, allowing `error.ClockUnsupported` / `error.Unexpected` to be removed from timer error sets (systems with "infinite" resolution are handled gracefully).

### Entropy

```zig
// Bytes from the Io's RNG:
io.random(&buffer);

// std.Random interface on top of Io:
const rng_impl: std.Random.IoSource = .{ .io = io };
const rng = rng_impl.interface();

// Cryptographically secure, always from outside the process:
try io.randomSecure(&buffer); // may fail with error.EntropyUnavailable
```

`std.Options.crypto_always_getrandom` and `crypto_fork_safety` are gone — use `io.randomSecure` when you need process-memory-free entropy.

---

## Compression, Debug Info, Misc

### Deflate: Compression Is Back

Zig 0.16 ships a from-scratch **deflate compressor** (plus `Raw` store-only and `Huffman`-only variants), along with a simplified `flate` decompressor:

- Default-level: ~10% **faster** than zlib, ~1% worse ratio.
- Best-level: on par with zlib on perf, ~0.8% worse ratio.
- Decompression: ~10% faster than Zig 0.15.

Other compression: `lzma`, `lzma2`, `xz` updated to the new `Io.Reader`/`Io.Writer` world.

### Debug Info / Stack Traces Reworked

New, unified debug-info API:

```zig
pub fn writeStackTrace(st: *const StackTrace, t: Io.Terminal) Writer.Error!void
pub fn captureCurrentStackTrace(options: StackUnwindOptions, addr_buf: []usize) StackTrace
pub fn writeCurrentStackTrace(options: StackUnwindOptions, t: Io.Terminal) Writer.Error!void
pub fn dumpCurrentStackTrace(options: StackUnwindOptions) void
pub fn dumpStackTrace(st: *const StackTrace) void
```

`StackUnwindOptions`:

```zig
pub const StackUnwindOptions = struct {
    first_address: ?usize = null,
    context: ?CpuContextPtr = null,   // for signal handlers
    allow_unsafe_unwind: bool = false,
};
```

Highlights:
- Safe unwinding (unwind info) used by default; falls back only if `allow_unsafe_unwind = true`.
- `std.debug.StackIterator` is no longer `pub`.
- `std.debug.SelfInfo` is overridable via `@import("root").debug.SelfInfo` — even on freestanding targets.
- Renamed/merged: `captureStackTrace` → `captureCurrentStackTrace`, `dumpStackTraceFromBase` → `dumpCurrentStackTrace`, `walkStackWindows` → `captureCurrentStackTrace`, `writeStackTraceWindows` → `writeCurrentStackTrace`.
- Inline callers now resolved from PDB on Windows (and error-return traces include them everywhere).
- **Almost all Tier 2+ targets now produce stack traces on crashes.**

### `std.debug` / `std.Progress` / Windows

- `std.Progress` now reports child-process progress across process boundaries on Windows.
- Max progress-node label length raised 40 → 120.
- `ucontext_t` and friends removed from the standard library (roll your own if you need it in a signal handler).

### `mem` Cut Functions & Naming

`std.mem` gained cut functions:

- `cut`, `cutPrefix`, `cutSuffix`, `cutScalar`, `cutLast`, `cutLastScalar`

And standardizes on short, composable concept words:

- `find` — index of a substring
- `pos` — starting-index parameter
- `last` — search from end
- `linear` — naive loop vs. fancy algorithm
- `scalar` — substring is a single element

(Expect gradual renames of `indexOf*` callsites over time.)

### `Target.SubSystem` Moved

`std.Target.SubSystem` → `std.zig.Subsystem` (with a deprecated alias and field-name aliases to keep `exe.subsystem = .Windows` working).

---

## Build System Changes

### `--fork=[path]` — Override Packages Locally

```bash
zig build --fork=/home/andy/dev/dvui
```

- Path points to a directory containing `build.zig.zon` with `name` and `fingerprint`.
- Any time the dependency tree resolves a package with matching name+fingerprint, it's replaced with the local path — anywhere in the tree.
- Ignores `version`. Resolves **before** any fetch.
- Ephemeral: drop the flag → pristine dependencies again.
- Errors out if nothing matches; prints an info line listing matches so you don't get confused.

**Caveat:** depends on the new hash format — legacy hash format support has been removed.

### Packages Fetched Into Project-Local `zig-pkg/`

Packages now land in a `zig-pkg/` directory next to `build.zig`, not in the global cache. After fetching and applying `paths` filters, each package is **re-tarballed** into `$GLOBAL_ZIG_CACHE/p/$HASH.tar.gz` so other projects can reuse it.

Requirements now enforced:
- `build.zig.zon` **must** have `fingerprint`.
- `name` must be an enum literal (not a string).
- Having the same `fingerprint`+`version` with a different hash in the tree is a hard error.

`ZIG_BTRFS_WORKAROUND` is no longer observed (upstream Linux bug long fixed).

### `--test-timeout`

```bash
zig build test --test-timeout 500ms
```

Forces each test to finish within real time; slow/hung tests are killed and reported. Useful for CI; be mindful of heavy-load false positives.

### `--error-style <verbose | minimal | verbose_clear | minimal_clear>`

- `verbose` (default): full context + step dep tree + failed commands.
- `minimal`: just step name + error message. (Replaces removed `--prominent-compile-errors`.)
- `*_clear` variants: with `--watch`, clear the terminal on each rebuild — great for incremental workflows.
- Environment override: `ZIG_BUILD_ERROR_STYLE`.

### `--multiline-errors <indent | newline | none>`

Controls multi-line error formatting. Default: `indent`. Env override: `ZIG_BUILD_MULTILINE_ERRORS`.

### Temporary Files

- `RemoveDir` step: **removed**.
- `Build.makeTempPath`: **removed** (it ran in the wrong phase).
- `WriteFile` gained **tmp mode** and **mutate mode**.
  - `Build.addTempFiles` — placed under `tmp/`, uncached; cleaned on success.
  - `Build.addMutateFiles` — operates in-place on a tmp dir.
  - `Build.tmpPath` — shortcut for `addTempFiles` + `WriteFile.getDirectory`.

Upgrade: `makeTempPath` + `addRemoveDirTree` → `addTempFiles` + the new `WriteFile` API.

### Misc

- `std.Build.Step.ConfigHeader` now handles leading whitespace for CMake-style configs.

---

## Compiler and Backends

### 1. C Translation Now Uses Aro

Translate-C is now powered by [Vexu/arocc](https://github.com/Vexu/arocc/) and [translate-c](https://codeberg.org/ziglang/translate-c) — **5,940 lines of C++** dropped from the compiler tree. Compiled lazily on first `@cImport`. This is a big step toward the broader goal of switching from a *library* LLVM dependency to a *process* Clang dependency.

Technically non-breaking, but any difference between Aro and Clang is a bug — report it.

### 2. LLVM Backend

- **Experimental incremental compilation support** — speeds up bitcode gen (not final `EmitObject`).
- 3–7% smaller LLVM bitcode.
- ~3% faster compile in some cases.
- Debug info: fixed for zero-bit-payload unions; type names complete; error set types lowered as enums so error names survive to runtime.
- Internal groundwork laid toward parallelizing LLVM IR generation across functions.
- Passes 2004/2010 (100%) of behavior tests — still the correctness reference.

(LLDB bug prevents using DWARF variant types for tagged unions / error unions for now.)

### 3. Reworked Byval Syntax Lowering

The frontend now lowers expressions "byref" until the final load. Fixes:
- Array access performance issues.
- Surprising aliasing after explicit copy.
- Extremely poor codegen in degenerate cases.

### 4. Reworked Type Resolution

A huge internal change that:
- Simplifies the (still in-progress) Zig language spec.
- Fixes many bugs — especially around incremental compilation.
- Is generally *more* permissive than before.
- Makes dependency-loop errors much clearer (with numbered notes that read like a story).
- Causes some previously accepted programs (e.g. a struct using `@alignOf(@This())`) to fail with a clear dep-loop error.

### 5. Incremental Compilation

- Incremental updates are substantially faster (changes that used to redo most of a build now complete in milliseconds).
- No longer produces ghost "dependency loop" errors that don't happen in full builds.
- The **New ELF Linker** (below) is the default for `-fincremental` targeting ELF.
- LLVM backend now supports incremental — meaning compile-error feedback is near-instant even when you're using LLVM.
- Usage: `zig build -fincremental --watch`.
- Still off by default (known bugs remain).

### 6. x86 Backend

- 11 bug fixes.
- Better constant memcpy codegen.
- **Still the default for Debug mode** on several x86_64 targets; faster compile, better debug info, inferior codegen vs LLVM.
- **Self-hosted backend is now the Debug-mode default on more targets in 0.16.0** — in 0.15.x this was just `x86_64-linux`. In 0.16.0, it expanded to include `x86_64-macos`, `x86_64-maccatalyst`, `x86_64-haiku`, and `x86_64-serenity` (look for `🖥️⚡` in the target support table). Other x86_64 targets (freebsd/netbsd/openbsd/windows) still go through LLVM by default. Use `-fllvm` / `-fno-llvm` to override.

### 7. aarch64 Backend

Progress paused for the I/O-interface work. Currently crashes on behavior tests. Expected to pick up after the std churn settles.

### 8. WebAssembly Backend

Passing 1813/1970 (92%) of behavior tests vs LLVM.

### 9. `.def` → Import Library Without LLVM

Zig can now generate MinGW-w64 import libraries from `.def` files without depending on LLVM — another step toward cutting the LLVM library dependency.

### 10. Better For-Loop Safety Check Codegen

Looping over slices generates ~30% less code for the safety checks.

### 11. Windows: Completed Migration to NtDll

All std-lib functionality on Windows now goes through the stable syscall API. The *only* remaining extern DLL imports are `CreateProcessW` and the `crypt32` cert-chain functions. This yields fewer bugs, less overhead, and full Batch + Cancelation for Windows networking.

Consequence: XP / old-Windows targeting requires a third-party Io implementation that uses higher-level DLLs.

---

## Linker: New ELF Linker

- Flag: `-fnew-linker` on CLI, or `exe.use_new_linker = true` in `build.zig`.
- **Default for `-fincremental` + ELF**.
- Benchmark (Zig compiler, single-line change):
  - Old linker: 14s / 194ms / 191ms
  - New linker: 14s / 65ms / 64ms (~66% faster incremental updates)
  - Skip linking: 14s / 62ms / 62ms (~68% faster)

Not yet feature-complete: executables lack DWARF information. Old linker + LLD remain available for now.

Performance is now good enough that `-Dno-bin` is rarely worth it — you can keep linking always on and still get instant feedback.

---

## Fuzzer: Smith

Fuzz tests' `[]const u8` input was replaced with `*std.testing.Smith`, a structured value generator.

Base methods:
- `value(T)` — produce any type.
- `eos()` — end-of-stream marker (guaranteed to eventually return `true`).
- `bytes(buf)` — fill a byte array.
- `slice(buf)` — fill part of a buffer; returns length.

Weighting:
- `[]const Smith.Weight` — biases selection probability (up to 64-bit types).
- `baselineWeights(T)` — all possible values of a type.
- `boolWeighted`, `eosSimpleWeighted` — convenience.
- `valueRangeAtMost`, `valueRangeLessThan` — ranged integers.

Example upgrade:

```zig
fn fuzzTest(_: void, smith: *std.testing.Smith) !void {
    var sum: u64 = 0;
    while (!smith.eosWeightedSimple(7, 1)) sum += smith.value(u8);
    try std.testing.expect(sum != 1234);
}
```

Other improvements:
- **Multiprocess fuzzing** — `-j N` flag.
- **Infinite mode** picks the most interesting tests automatically; old/explored tests get less time.
- **Crash dumps** — crashing inputs are saved and can be replayed via `std.testing.FuzzInputOptions.corpus` + `@embedFile`.
- AST Smith found **20 new bugs** in `zig fmt` alone, plus several Parser/PEG inconsistencies.

---

## Toolchain

### Library Versions

| Library | Version |
|---|---|
| LLVM / Clang | 21.1.0 / 21.1.8 |
| musl | 1.2.5 (+ backported security) |
| glibc (cross) | 2.43 |
| Linux headers | 6.19 |
| macOS headers | 26.4 |
| FreeBSD libc | 15.0 |
| WASI libc | commit `c89896107d7b` |
| MinGW-w64 | commit `38c8142f660b` |

### Loop Vectorization Disabled

An LLVM 21 regression miscompiles Zig itself in common configs. As a safety measure, **loop vectorization is disabled entirely** until we move to a fixed LLVM. Expect this to persist through 0.17, be fixed in 0.18.

### zig libc Expansion

Zig's own libc now provides many more functions (including `malloc` and friends, plus a big chunk of `math`). C source files shipped with Zig dropped from **2,270 → 1,873 (-17%)**:

- 331 fewer musl sources.
- 99 fewer MinGW-w64 sources.
- WASI actually gained 32 due to newer pthread shims.

If you hit bugs in "musl" or "MinGW-w64" through Zig, report them to **Zig's** issue tracker — many are now Zig's responsibility.

### `zig cc` / `zig c++`

- Now Clang 21.1.8-based.
- 9 bugs fixed.

### OS Version Requirements

| OS | Minimum |
|---|---|
| DragonFly BSD | 6.0 |
| FreeBSD | 14.0 |
| Linux | 5.10 |
| NetBSD | 10.1 |
| OpenBSD | 7.8 |
| macOS | 13.0 |
| Windows | 10 |

### OpenBSD Cross-Compile Support

Dynamic libc stubs + most system headers for OpenBSD 7.8+.

---

## Target Support

### New / Updated

- **Natively tested in CI**: `aarch64-freebsd`, `aarch64-netbsd`, `loongarch64-linux`, `powerpc64le-linux`, `s390x-linux`, `x86_64-freebsd`, `x86_64-netbsd`, `x86_64-openbsd`. (Thanks OSUOSL, IBM.)
- **Cross-compile**: `aarch64-maccatalyst`, `x86_64-maccatalyst` (free from existing `libSystem.tbd`).
- **New Tier 3/4**: `loongarch32-linux` (syscalls only), plus Alpha, KVX, MicroBlaze, OpenRISC, PA-RISC, SuperH as Tier 4 stepping stones.
- **Removed**: Oracle Solaris, IBM AIX, IBM z/OS (proprietary OSes with inaccessible headers). illumos remains supported.

### Reliability & BE Fixes

- Weakly-ordered arch reliability fixes (AArch64 especially w/o LSE, LoongArch, Power).
- Big-endian host bugs fixed.
- Big-endian ARM now emits BE8 (ARMv6+), not legacy BE32.
- Stack tracing improved across the board; most Tier 2+ targets get tracebacks on crashes.

### Tier Summary (Goalposts for 1.0)

- **Tier 1**: all non-experimental language features correct; codegen without LLVM.
- **Tier 2**: cross-platform std abstractions, debug info, libc cross-compile, CI per-push.
- **Tier 3**: codegen via LLVM; linker works; not LLVM-experimental.
- **Tier 4**: assembly output via LLVM only.

Currently only `x86_64-linux` is Tier 1.

---

## Migration Cheat Sheet

A concentrated "what do I grep for?" table:

| 0.15 symbol | 0.16 replacement |
|---|---|
| `@Type(.{ .int = .{ ... } })` | `@Int(sign, bits)` |
| `@Type(.{ .@"struct" = .{...} })` | `@Struct(...)` |
| `@Type(.{ .@"union" = .{...} })` | `@Union(...)` |
| `@Type(.{ .@"enum" = .{...} })` | `@Enum(...)` |
| `@Type(.{ .pointer = .{...} })` | `@Pointer(...)` |
| `@Type(.{ .@"fn" = .{...} })` | `@Fn(...)` |
| `@Type(.enum_literal)` | `@EnumLiteral()` |
| `@intFromFloat(f)` | `@trunc(f)` (or `@round`/`@floor`/`@ceil`) |
| `@cImport({ ... })` | `b.addTranslateC(...)` |
| `std.io.fixedBufferStream(x).reader()` | `std.Io.Reader.fixed(x)` |
| `std.io.fixedBufferStream(x).writer()` | `std.Io.Writer.fixed(x)` |
| `std.fs.cwd()` | `std.Io.Dir.cwd()` |
| `std.fs.File.read` | `std.Io.File.readStreaming` |
| `std.fs.File.pread` | `std.Io.File.readPositional` |
| `std.fs.File.write` | `std.Io.File.writeStreaming` |
| `std.fs.File.pwrite` | `std.Io.File.writePositional` |
| `std.fs.File.writeAll` | `std.Io.File.writeStreamingAll` |
| `std.process.getCwd` | `std.process.currentPath(io, ...)` |
| `std.process.Child.run(...)` | `std.process.run(allocator, io, .{ ... })` |
| `std.process.execv(arena, argv)` | `std.process.replace(io, .{ .argv = argv })` |
| `std.Thread.Mutex` | `std.Io.Mutex` |
| `std.Thread.Condition` | `std.Io.Condition` |
| `std.Thread.ResetEvent` | `std.Io.Event` |
| `std.Thread.WaitGroup` | `std.Io.Group` |
| `std.Thread.Semaphore` | `std.Io.Semaphore` |
| `std.Thread.RwLock` | `std.Io.RwLock` |
| `std.Thread.Futex` | `std.Io.Futex` |
| `std.Thread.Pool` | `std.Io.async` / `std.Io.Group` |
| `std.time.Instant` | `std.Io.Timestamp` |
| `std.time.Timer` | `std.Io.Timestamp` |
| `std.time.timestamp` | `std.Io.Timestamp.now` |
| `std.crypto.random.bytes(&buf)` | `io.random(&buf)` |
| `std.posix.getrandom(&buf)` | `io.random(&buf)` |
| `std.crypto.random` (interface) | `std.Random.IoSource{.io = io}.interface()` |
| `std.posix.mlock(slice)` | `std.process.lockMemory(slice, .{})` |
| `std.posix.mlockall(...)` | `std.process.lockMemoryAll(...)` |
| `std.posix.PROT.READ | std.posix.PROT.WRITE` | `.{ .READ = true, .WRITE = true }` |
| `std.ArrayHashMap(...)` | *(removed; use unmanaged)* |
| `std.AutoArrayHashMapUnmanaged` | `std.array_hash_map.Auto` |
| `std.StringArrayHashMapUnmanaged` | `std.array_hash_map.String` |
| `std.ArrayHashMapUnmanaged` | `std.array_hash_map.Custom` |
| `std.heap.ThreadSafeAllocator` | *(removed; use a lock-free allocator)* |
| `std.once` | *(removed; avoid global state)* |
| `std.fmt.Formatter` | `std.fmt.Alt` |
| `std.fmt.format` | `std.Io.Writer.print` |
| `std.fmt.FormatOptions` | `std.fmt.Options` |
| `std.fmt.bufPrintZ` | `std.fmt.bufPrintSentinel` |
| `std.leb.readUleb128` | `std.Io.Reader.takeLeb128` |
| `std.leb.readIleb128` | `std.Io.Reader.takeLeb128` |
| `error.RenameAcrossMountPoints` | `error.CrossDevice` |
| `error.NotSameFileSystem` | `error.CrossDevice` |
| `error.SharingViolation` | `error.FileBusy` |
| `error.EnvironmentVariableNotFound` | `error.EnvironmentVariableMissing` |
| `--prominent-compile-errors` | `--error-style minimal` |
| `std.fs.wasi.Preopens` | `std.process.Preopens` |
| `std.Target.SubSystem` | `std.zig.Subsystem` |
| `std.builtin.subsystem` | *(removed; detect at runtime if needed)* |
| `std.Io.GenericReader` | `std.Io.Reader` |
| `std.Io.AnyReader` | `std.Io.Reader` |
| `std.Io.GenericWriter` | `std.Io.Writer` |
| `std.Io.AnyWriter` | `std.Io.Writer` |

---

## Canonical Patterns

### "Standard" `main`

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    _ = args;

    try std.Io.File.stdout().writeStreamingAll(io, "hello\n");
    _ = gpa;
}
```

### Writing to stdout (Zig 0.16 I/O model)

```zig
// Simple one-shot write (uses Io under the hood):
try std.Io.File.stdout().writeStreamingAll(io, "text\n");

// Buffered writes:
var buf: [4096]u8 = undefined;
var fw = std.Io.File.stdout().writer(io, &buf);
const w = &fw.interface;
try w.print("x = {d}\n", .{42});
try w.flush();
```

### Reading a whole file, capped

```zig
const contents = try std.Io.Dir.cwd().readFileAlloc(io, "input.txt", gpa, .limited(1 << 20));
defer gpa.free(contents);
```

### Concurrent HTTP

```zig
var client: std.http.Client = .{ .allocator = gpa, .io = io };
defer client.deinit();
var req = try client.request(.GET, uri, .{});
defer req.deinit();
try req.sendBodiless();
var redir: [1024]u8 = undefined;
const resp = try req.receiveHead(&redir);
var rbuf: [4096]u8 = undefined;
const body = resp.reader(&rbuf);
// ... read body ...
```

### Spawning & Waiting on Tasks

```zig
var group: Io.Group = .init;
defer group.cancel(io);

for (urls) |url| group.async(io, fetchOne, .{ io, url });

try group.await(io);
```

### Mutex / Condition (Io-aware)

```zig
var m: std.Io.Mutex = .{};
var c: std.Io.Condition = .{};

{
    m.lock(io);
    defer m.unlock(io);
    while (!ready) c.wait(io, &m);
}
```

---

## Custom Format Methods

The format-method signature from 0.15 carries forward unchanged. You still use `{f}` to invoke a custom `format`, and `{any}` to skip it:

```zig
const MyType = struct {
    value: i32,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("MyType({d})", .{self.value});
    }
};

std.debug.print("{f}\n", .{MyType{ .value = 42 }});
std.debug.print("{any}\n", .{MyType{ .value = 42 }});
```

Naming changes you may encounter in helper code:

- `std.fmt.Formatter` → `std.fmt.Alt` (stateful formatter helper)
- `std.fmt.format` → `std.Io.Writer.print`
- `std.fmt.FormatOptions` → `std.fmt.Options`

The format specifier grammar (`{[pos][spec]:[fill][align][width].[prec]}`) and the set of specifiers (`{s} {c} {d} {x} {X} {o} {b} {e} {E} {u} {any} {f} {*}`) is unchanged from 0.15. See the "Zig Format Specifiers Guide" at the bottom of `ZIG-0.15.2.md` — it still applies verbatim in 0.16, except:

- If you were using `std.io.fixedBufferStream`, switch to `std.Io.Reader.fixed` / `std.Io.Writer.fixed`.
- If you were using `std.fmt.format` to a writer, that's `std.Io.Writer.print` now.
- Anywhere you wrote to stdout via `std.fs.File.stdout().writer(&buf)` — you now write it through `std.Io.File.stdout()` with an `Io` parameter.

---

## Compile-Error Decoder

Common 0.16 errors when porting from 0.15.x and what they usually mean:

| Error fragment | Likely cause | Fix |
|---|---|---|
| `no field or declaration 'cwd' in std.fs` (or similar) | You're still calling `std.fs.*` | Use `std.Io.Dir` / `std.Io.File` |
| `expected 2 arguments, found 1` on `file.close()` | Missing `Io` parameter | Thread `io` through, call `file.close(io)` |
| `expected type 'std.Io', found ...` | Function signature needs an `Io` param | Add `io: std.Io` and pass through |
| `use of undeclared identifier 'std.Thread.Pool'` | Thread pool removed | Use `std.Io.async` / `std.Io.Group` |
| `use of undeclared identifier 'std.io.fixedBufferStream'` | Removed | `std.Io.Reader.fixed(x)` / `std.Io.Writer.fixed(x)` |
| `pointer not allowed in packed struct/union` | Field is a pointer in a `packed` type | Store as `usize`; convert with `@ptrFromInt` / `@intFromPtr` |
| `integer tag type of enum is inferred` in `extern` context | Implicit enum tag in extern | Spell it out: `enum(u8) { ... }` |
| `inferred backing integer of packed ... has unspecified signedness` | Implicit backing int in extern | Use `packed struct(u8)` / `packed union(u16)` etc. |
| `returning address of expired local variable '...'` | `return &x;` where `x` is local | Return by value, or allocate and return the pointer |
| `indexing a vector at runtime is not allowed` | `vector[runtime_i]` | Coerce: `const arr: [N]E = vector;` |
| `lossy conversion from comptime_int to f32` | Integer literal too big for float | Use explicit `123.0` literal or `@floatFromInt` at comptime |
| `type '...' depends on itself for alignment query here` | Struct field alignment references `@alignOf(@This())` | Break the cycle (compute alignment differently) |
| `dependency loop with length N` (multiple notes) | New type resolution caught a cycle | Read the numbered notes top-to-bottom; break any one link |
| `use of undeclared identifier '@Type'` | `@Type` removed | Use `@Int`/`@Struct`/`@Union`/`@Enum`/`@Pointer`/`@Fn`/`@Tuple`/`@EnumLiteral` |
| `no field or declaration 'ArrayHashMap'` | Managed hash maps removed | Use `std.array_hash_map.{Custom, Auto, String}` |
| `expected *std.testing.Smith, found []const u8` | Fuzz test signature changed | `fn fuzzTest(_: void, smith: *std.testing.Smith) !void` |

---

## Common Bad Assumptions from 0.15.x

Things that *were* true in 0.15 and are **no longer** true in 0.16 — these are the ones AI agents and muscle-memory humans get wrong most often:

1. **"I can call `std.fs.cwd()` anywhere."** — No, you need `std.Io.Dir.cwd()` and an `Io`.
2. **"`std.Thread.WaitGroup` is a lightweight counter."** — `std.Io.Group` replaces it, but is a task orchestrator tied to async semantics. Use `Semaphore` or atomics if you just want a counter.
3. **"`std.Thread.Pool` is the way to parallelize."** — Gone. Use `Io.async` / `Io.Group`.
4. **"`@cImport` is the right way to use C code."** — Still works today (it's deprecated, not removed), but the blessed path is `b.addTranslateC` in `build.zig`.
5. **"Packed structs can hold pointers."** — No longer. Use `usize` + `@ptrFromInt` / `@intFromPtr`.
6. **"`std.os.environ` is a global."** — Gone. Env lives on `init.environ_map` (Juicy) or `init.environ` (Minimal).
7. **"`std.crypto.random.bytes` gets me entropy anywhere."** — Replaced by `io.random(&buf)` / `io.randomSecure(&buf)`.
8. **"Evented I/O is the default."** — `Io.Threaded` is the default. `Io.Evented` is experimental.
9. **"`@intFromFloat` is the float→int conversion."** — Use `@trunc`/`@floor`/`@ceil`/`@round` instead.
10. **"`@Type(.{.int=...})` is how I make an integer type at comptime."** — Use `@Int(.unsigned, N)`.
11. **"Custom `format` uses a comptime format-string parameter."** — That was 0.14 and earlier; since 0.15, the signature is `pub fn format(self, writer: *std.Io.Writer) !void`, invoked via `{f}`.
12. **"`*T` and `*align(1) T` are the same type."** — They coerce freely, but compare as distinct.

---

## Roadmap

Upcoming (per release notes):

- **0.17** — short cycle; upgrade to LLVM 22; finish separating the "make" phase (build runner) from the "configure" phase (`build.zig`).
- **Beyond**:
  1. Complete and stabilize the language.
  2. Finish the **aarch64** backend; make it the default for Debug.
  3. Enhance linkers, remove **LLD** dependency, full incremental support.
  4. Improve the fuzzer to be competitive with AFL et al.
  5. Switch from LLVM **library** dependency to Clang **process** dependency.
  6. **1.0** — Tier 1 targets will require a formal bug policy.

---

## Key Takeaways

1. **"Juicy Main" + `Io` is the new mental model.** Threading an `Io` through your code is like threading an `Allocator`. Embrace it; don't fight it.
2. **Mechanical diffs dominate.** Most file-system changes are just adding `io` as the first arg. Lean on the compiler.
3. **Dependency-loop errors get much better.** If you see one, read the numbered notes — they're a story.
4. **`@Type` is gone.** Replace with the new focused builtins; they read more like the syntax they produce.
5. **`@cImport` will eventually disappear entirely.** Move to `b.addTranslateC` now.
6. **Packed types are stricter.** Explicit backing integers in `extern` contexts, no pointers, equal-width fields.
7. **Incremental + new ELF linker are genuinely usable.** `zig build -fincremental --watch` is a different experience.
8. **Network code on Windows is fundamentally faster** (direct AFD, no `ws2_32.dll`).
9. **Cancel**ation is spelled with a single 'l'. Adopt it in your APIs.
10. **Expect bugs.** 0.16 contains 345 fixed bugs and still plenty remaining — "zig 1.0" is the target for stability guarantees. Report early, report often.

Welcome to Zig 0.16!
