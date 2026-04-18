# Zig 0.16.0 Updates

This document provides a comprehensive overview of the changes and new features in **Zig 0.16.0** (released April 16, 2026). If your knowledge of Zig stops at 0.15.x (or earlier), this is the fastest way to get up to speed on the latest language, standard library, build system, compiler, linker, and toolchain changes.

Zig 0.16.0 represents **8 months of work**, 244 contributors, and 1183 commits. The headline feature is **"I/O as an Interface"** — a massive, pervasive reworking comparable to 0.15.1's "Writergate" but arguably larger in surface area. Alongside it, there are substantial language changes, a new "Juicy Main" entry point, the removal of `@Type` in favor of focused builtins, `@cImport` migration to the build system, a new ELF linker, a Smith-based fuzzer, and much more.

---

## ⚠️ For AI assistants: read this BEFORE writing any Zig code

Most LLMs' training data is **pre-0.15**. If you are an AI tool writing Zig code and you have not read this document, you will almost certainly produce code that does not compile. These are the top patterns you will reflexively reach for that are **wrong** in 0.16:

| Your reflex (pre-0.15) | What actually works in 0.16 |
|---|---|
| `std.ArrayList(T){}` / `= .{}` | `= .empty` — both managed and unmanaged lost field defaults |
| `std.fs.cwd()` | `std.Io.Dir.cwd()` — and almost every method now takes `io: Io` as the first arg |
| `std.fs.File` / `std.fs.Dir` | `std.Io.File` / `std.Io.Dir` |
| `file.readToEndAlloc(gpa, max)` | `var fr = file.reader(io, &.{}); try fr.interface.allocRemaining(gpa, .limited(max))` |
| `file.writeAll(bytes)` | `file.writeStreamingAll(io, bytes)` |
| `std.time.Timer.start()` / `timer.read()` | `const t = std.Io.Clock.Timestamp.now(io, .awake); ... t.raw.durationTo(...).toNanoseconds()` |
| `std.time.timestamp()` / `milliTimestamp()` / `nanoTimestamp()` | `std.Io.Clock.Timestamp.now(io, .real).raw.toSeconds() / .toMilliseconds() / .toNanoseconds()` |
| `std.Thread.sleep(ns)` | `std.Io.sleep(io, std.Io.Duration.fromNanoseconds(ns), .awake)` |
| `std.Thread.Futex.wait / wake / timedWait` | Free functions: `std.Io.futexWait(io, T, ptr, expected)` / `futexWake(io, T, ptr, n)` / `futexWaitTimeout(io, T, ptr, expected, timeout)`. **There is no `std.Io.Futex` type.** Timeout expiry returns success (void), not `error.Timeout` — caller re-reads the word. |
| `std.Thread.{Mutex, Condition, ResetEvent, Semaphore, RwLock, WaitGroup, Pool}` | Moved under `std.Io.*` (`Event` for `ResetEvent`, `Group` for `WaitGroup`). `Pool` is gone — use `Io.async` / `Io.Group`. |
| `std.process.argsAlloc(gpa)` / `argsWithAllocator(gpa)` | `pub fn main(init: std.process.Init) !void` then `try init.minimal.args.toSlice(init.arena.allocator())` or `init.minimal.args.iterate()` |
| `std.heap.GeneralPurposeAllocator(.{}){}` | **Removed.** Use `init.gpa` (Debug = `DebugAllocator`), `init.arena.allocator()` (short-lived CLIs), or `std.heap.DebugAllocator(.{})` directly |
| `std.heap.ThreadSafeAllocator` | **Removed.** `std.heap.ArenaAllocator` is now threadsafe by default |
| `std.os.environ` (global) | **Gone.** Use `init.environ_map` (Juicy) or `init.minimal.environ` (raw). `std.posix.getenv` also gone — fall back to `std.c.getenv(name_cstr)` if you need a bridge. |
| `std.crypto.random.bytes(&buf)` / `std.posix.getrandom(&buf)` | `io.random(&buf)` (non-crypto) or `try io.randomSecure(&buf)` (crypto-grade) |
| `std.process.Child.init(argv, gpa).spawn()` | `var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .pipe, ... })`. For capturing output use `std.process.run(gpa, io, .{ ... })`. |
| `std.fs.selfExePathAlloc(gpa)` | `std.process.executablePathAlloc(io, gpa)` |
| `std.posix.close(fd)` / `fstat` / `ftruncate` / `fsync` / `unlink` / `open` / `write` / `isatty` / `pipe` / `fork` / `waitpid` / `exit` | **All removed from `std.posix`.** Drop to `std.c.*` with `std.c.errno(rc)` switches, or use `std.Io.File` / `std.Io.Dir` for the high-level form. (`std.posix.read`, `mmap`, `munmap`, `msync`, `madvise`, `openatZ`, `kill` with `SIG` enum, `fdatasync`, `poll`, `tcgetattr`, `tcsetattr`, `sigaction` all survive.) |
| `std.posix.PROT.READ \| std.posix.PROT.WRITE` | `.{ .READ = true, .WRITE = true }` — PROT is now a packed struct type (`macho.vm_prot_t` on macOS); `std.posix.mmap`'s `prot` parameter accepts the struct directly, not `u32` |
| `std.posix.kill(pid, 0)` for existence check | `std.c.kill(pid, @enumFromInt(0))` — `std.posix.kill`'s `sig` parameter is a typed `SIG` enum with no named `0` variant on macOS. Distinguish `.PERM` (alive, no permission) from `.SRCH` (dead) via `std.c.errno(rc)`. |
| `std.mem.trimLeft(u8, s, " ")` / `trimRight` | `std.mem.trimStart` / `trimEnd`. Plain `std.mem.trim` unchanged. |
| `std.io.fixedBufferStream(buf).writer()` / `.reader()` | `std.Io.Writer.fixed(buf)` / `std.Io.Reader.fixed(buf)` |
| `std.io.GenericReader` / `AnyReader` / `GenericWriter` / `AnyWriter` | All removed. Use `std.Io.Reader` / `std.Io.Writer` (interface types). |
| `ArrayList(u8).writer(gpa)` pattern for string building | `var out: std.Io.Writer.Allocating = .init(gpa); try out.writer.print(...);` — note: `writer` is a **field**, not a method (no `()`). Pass `&out.writer` to helpers that take `*std.Io.Writer`. |
| `@Type(.{ .int = .{ .signedness = ..., .bits = ... } })` | `@Int(.signed, N)` / `@Int(.unsigned, N)`. Also `@Struct`/`@Union`/`@Enum`/`@Pointer`/`@Fn`/`@Tuple`/`@EnumLiteral` — `@Type` is gone. |
| `@intFromFloat(f)` | `@trunc(f)` / `@floor(f)` / `@ceil(f)` / `@round(f)` — picks your rounding mode explicitly |
| `pub fn format(self, comptime fmt, options, writer)` | `pub fn format(self, writer: *std.Io.Writer) std.Io.Writer.Error!void` — single-arg signature, invoked via `{f}` format specifier. `{any}` skips the custom method. |
| `readFileAlloc(gpa, path, max_usize)` | `readFileAlloc(dir, io, path, gpa, .limited(max))` — cap is `std.Io.Limit`, not `usize`; the cap-breach error is `error.StreamTooLong` (not `error.FileTooBig`). |
| `/// doc comment` preceding a `test "..."` block | Rejected in 0.16 — use plain `//` comments before tests. Module-level `//!` at the top of the file is still fine. |
| `packed struct { ptr: *T }` | **Pointers in packed structs are no longer allowed.** Store as `usize` and convert with `@ptrFromInt` / `@intFromPtr`. Packed union fields must also all have the same `@bitSizeOf`. |
| `File.seekTo(0)` / `seekBy` / `seekFromEnd` / `getPos` | Moved to `Reader.seekTo` / `Reader.seekBy` / `Writer.seekTo` / `Reader.logicalPos` / `Writer.logicalPos`. For raw seek, drop to `std.c.lseek(fd, offset, whence)` where `SEEK_SET=0`, `SEEK_CUR=1`, `SEEK_END=2`. |
| `std.net.Stream` / `std.net.Server` / `std.net.Address` | `std.Io.net.Stream` / `std.Io.net.Server` / `std.Io.net.IpAddress` (with `.ip4` and `.ip6` union variants). `Ip4Address` is a plain struct: `.{ .bytes = .{ 0, 0, 0, 0 }, .port = p }`. `Stream` has no direct `read`/`writeAll`; use `stream.reader(io, buf)` / `stream.writer(io, buf)` or operate on `stream.socket.handle` directly. |
| `std.Io.File.Stat.atime` as `Timestamp` | Now `?Timestamp` (nullable — some filesystems don't track it). `.mtime` and `.ctime` are still non-null `Timestamp`; read the nanoseconds with `stat.mtime.nanoseconds`. |

### Why this list exists

Those are the ~30 traps a real migration of a 32k-line Zig codebase surfaced. All of them are mechanical if you know about them, and all of them will waste a compile-fix-recompile cycle per occurrence if you don't.

### ⚠️ One post-migration trap that doesn't surface at compile time

**`std.Io.Threaded.global_single_threaded.io()` is backed by an `Io` whose `allocator` field is `Allocator.failing`.** The stdlib doc comment says it "does not support concurrency or cancelation" — the less-obvious corollary is that **any Io vtable operation that allocates internally will return `error.OutOfMemory`**, even when the program has plenty of memory.

The singleton is appropriate for:
- clock ops (`Clock.Timestamp.now`, `Duration.fromMilliseconds`)
- sleep (`std.Io.sleep`)
- futex (`std.Io.futexWait`/`WaitTimeout`/`Wake`)
- entropy (`io.random`)
- simple syscall-ish `std.Io.Dir` / `std.Io.File` ops where the caller passes an explicit allocator parameter (`openFile`, `createFile`, `createDirPath`, `statFile`, `deleteFile`, `readFileAlloc(io, path, gpa, limit)`) — the vtable impls dispatch straight to syscalls

The singleton is **NOT** appropriate for:
- `std.process.spawn` / `run` / `replace` — these allocate argv/envp marshalling buffers through `io.allocator` and silently fail with `OutOfMemory` on the singleton
- Any `Io`-aware helper whose internals marshal into C-style pointer arrays or temp buffers through the `Io` allocator surface

**The lesson:** treat the singleton as "safe for leaf syscalls, not safe as a general `Io`". App-boundary code (anything that spawns, async-launches, or does networking of any real complexity) should thread a real `init.io` from Juicy Main through the call chain. Rule of thumb: if the `Io` operation you're calling returns `error.OutOfMemory` as a possible error, it allocates — don't hand it the singleton.

### What to do next

1. If you're about to write Zig code for this codebase, skim this document's **Migration Cheat Sheet** (section near the end) and **Common Bad Assumptions from 0.15.x** (final content section) for any patterns not covered above. Both are denser than this summary.
2. When in doubt, read the installed stdlib directly. `zig env` prints `std_dir`; grep or read the actual source. No amount of prose documentation is as authoritative as the types the compiler actually sees.
3. If you hit an API shape not covered anywhere in this document, it's probably still correct to just use the pre-0.15 shape — but verify against stdlib first.

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
19. [Migration Workflow Tactics (lessons from a real port)](#migration-workflow-tactics-lessons-from-a-real-0152--0160-port)
20. [Roadmap](#roadmap)

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

### Library leaf-code escape hatch: `std.Io.Threaded.global_single_threaded`

If you're library code that needs `Io` only for a few narrow calls (a single futex, a one-off timestamp read, a stat) and threading an `io: Io` parameter through your public API would be architectural damage, stdlib provides its own process-wide singleton at `Io/Threaded.zig:1704`:

```zig
pub const global_single_threaded: *Threaded = &global_single_threaded_instance;
```

With the doc comment explicitly sanctioning this use case:

> In general, the application is responsible for choosing the `Io` implementation and library code should accept an `Io` parameter rather than accessing this declaration. …However, in some cases such as debugging, it is desirable to hardcode a reference to this `Io` implementation. This instance does not support concurrency or cancelation.

Usage:

```zig
const io = std.Io.Threaded.global_single_threaded.io();
std.Io.futexWake(io, u32, futex_ptr, 1);
```

**What "does not support concurrency or cancelation" actually means:** no async submission queue, no internal worker pool, no cancel-safe operation tracking. It does **not** mean "unsafe to call from multiple OS threads." The vtable functions for futex/file/timestamp dispatch through to plain syscalls — `Threaded.futexWait` at `Io/Threaded.zig:2515` uses the `Threaded` pointer only to rebuild the `Io` struct for `Timeout` duration conversion, then drops straight to a bare `Thread.futexWait(ptr, expected, timeout_ns)` syscall. No `Threaded` state is touched across concurrent callers.

**When to use it:**
- Library code needing `Io` for narrow leaf operations (futex, stat, mkdir, timestamp) and not wanting to inflate its public API
- Debug / init-time code where threading `io` through would be noise
- Tests that need an `io` but don't want to set up their own `Threaded` (though `std.testing.io` is usually nicer)

**When NOT to use it:**
- Anywhere you need async/await, concurrent, or cancel-safe semantics
- Anywhere the library could plausibly be consumed by code that wants to swap in a different `Io` implementation — use a parameter instead

**Lifecycle:** no `deinit` required. The singleton's backing `init_single_threaded` is a pure const struct literal — `allocator = .failing`, `async_limit = .nothing`, `have_signal_handler = false`. The doc explicitly says `deinit` is safe but unnecessary to call.

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

**Migrating managed → unmanaged is not a pure rename.** If your code used the managed variant, callers must also:

- initialize with the `.empty` decl literal (not `.init(allocator)`)
- pass the allocator to every mutating op (`put`, `remove`, `ensureTotalCapacity`, …)
- pass the allocator to `deinit`

```zig
// 0.15 — managed
var m = std.StringArrayHashMap(V).init(allocator);
defer m.deinit();
try m.put("k", v);
_ = m.remove("k");

// 0.16 — unmanaged + rename
var m: std.array_hash_map.String(V) = .empty;
defer m.deinit(allocator);
try m.put(allocator, "k", v);
_ = m.orderedRemove(m.getIndex("k").?);
```

Read-only ops (`get`, `contains`, `count`, `keys`, `values`, `iterator`) do not require the allocator. The regular (non-array) hashmap family (`std.StringHashMap`, `std.AutoHashMap`) is **not** removed and still offers managed variants.

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
error.FileTooBig                  → error.StreamTooLong  (for readFileAlloc and friends)
```

Notable behavior changes:
- `std.Io.Dir.rename` now returns `error.DirNotEmpty` rather than `error.PathAlreadyExists`.
- `readFileAlloc` and similar limited-read APIs now signal "hit the limit" with `error.StreamTooLong` (not `error.FileTooBig`). The error type is part of `ReadFileAllocError` and the new error semantics unify "file exceeded limit" and "stream exceeded limit" into one error name.

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

### `Io.Limit` — the new "how many bytes" primitive

Many 0.16 APIs that used to take a bare `usize` max-size now take an `Io.Limit` instead (e.g., `readFileAlloc`, `streamDelimiterLimit`, `sendFileAll`, etc.). `Io.Limit` is an `enum(usize)` with open discriminants:

```zig
pub const Limit = enum(usize) {
    nothing = 0,
    unlimited = math.maxInt(usize),
    _,

    pub fn limited(n: usize) Limit { ... }
    pub fn limited64(n: u64) Limit { ... }       // clamps to maxInt(usize)
    pub fn countVec(data: []const []const u8) Limit { ... }
    pub fn min(a: Limit, b: Limit) Limit { ... }
    pub fn max(a: Limit, b: Limit) Limit { ... }
    pub fn minInt(l: Limit, n: usize) usize { ... }
    pub fn slice(l: Limit, s: []u8) []u8 { ... }
    pub fn sliceConst(l: Limit, s: []const u8) []const u8 { ... }
};
```

Common spellings at call sites:

```zig
.limited(1 << 20)   // at most 1 MiB (enum-literal method-call syntax)
.unlimited          // no cap
.nothing            // zero-byte cap (useful for "don't read anything")
```

Because the method is named `limited`, `.limited(N)` works wherever `Io.Limit` is the inferred target type. If the target type is ambiguous, write `std.Io.Limit.limited(N)` explicitly.

### `std.Io.Writer.Allocating` — the `ArrayList(u8).writer()` replacement

This is one of the most important 0.16 APIs in practice. If you had any 0.15-era code using the `ArrayList(u8).writer(allocator)` idiom for building strings, code-generating, or accumulating formatted output, this is your migration target.

**Struct shape (from `std/Io/Writer.zig`):**

```zig
pub const Allocating = struct {
    allocator: Allocator,
    writer: Writer,           // <-- FIELD (not a method). Use `alloc.writer.print(...)` directly.

    // Initializers
    pub fn init(allocator: Allocator) Allocating;
    pub fn initAligned(allocator: Allocator, alignment: std.mem.Alignment) Allocating;
    pub fn initCapacity(allocator: Allocator, capacity: usize) error{OutOfMemory}!Allocating;
    pub fn initOwnedSlice(allocator: Allocator, slice: []u8) Allocating;
    pub fn initOwnedSliceAligned(allocator: Allocator, slice: []u8, alignment: std.mem.Alignment) Allocating;
    pub fn fromArrayList(allocator: Allocator, array_list: *ArrayList(u8)) Allocating;

    // Teardown
    pub fn deinit(a: *Allocating) void;
    pub fn toArrayList(a: *Allocating) ArrayList(u8);   // resets Allocating to empty

    // Byte access
    pub fn toOwnedSlice(a: *Allocating) Allocator.Error![]u8;
    pub fn toOwnedSliceSentinel(a: *Allocating, comptime sentinel: u8) Allocator.Error![:sentinel]u8;
    pub fn written(a: *Allocating) []u8;                // borrowed view; slice invalidates on next write

    // Capacity / shape
    pub fn ensureUnusedCapacity(a: *Allocating, additional_count: usize) Allocator.Error!void;
    pub fn ensureTotalCapacity(a: *Allocating, new_capacity: usize) Allocator.Error!void;
    pub fn ensureTotalCapacityPrecise(a: *Allocating, new_capacity: usize) Allocator.Error!void;
    pub fn shrinkRetainingCapacity(a: *Allocating, new_len: usize) void;
    pub fn clearRetainingCapacity(a: *Allocating) void;
};
```

**Canonical migration pattern:**

```zig
// ❌ 0.15 style
var out: std.ArrayListUnmanaged(u8) = .{};
defer out.deinit(allocator);
const w = out.writer(allocator);
try w.print("hello {s}\n", .{name});
try w.writeAll("world");
const bytes = try out.toOwnedSlice(allocator);

// ✅ 0.16 style
var out: std.Io.Writer.Allocating = .init(allocator);
// Note: no `defer out.deinit()` if you return ownership via toOwnedSlice.
try out.writer.print("hello {s}\n", .{name});
try out.writer.writeAll("world");
const bytes = try out.toOwnedSlice();
```

**Passing the writer to helpers that expect `*std.Io.Writer`:**

```zig
fn emitHeader(w: *std.Io.Writer, name: []const u8) !void {
    try w.print("// {s}\n", .{name});
}

var out: std.Io.Writer.Allocating = .init(allocator);
try emitHeader(&out.writer, "mymodule");        // take address of the field
// or for `writer: anytype` helpers, either `&out.writer` or `out.writer` works
// depending on what the body does with it.
```

**Key facts to remember:**

1. `writer` is a **field, not a method**. Don't write `out.writer()` — that fails to compile. Write `out.writer.print(...)` or `&out.writer` when you need a pointer.
2. `.toOwnedSlice()` transfers ownership — the `Allocating` resets to empty and no `deinit` is needed afterward.
3. `.written()` returns a borrowed view into the current buffer. **The returned slice invalidates on the next write** — do not hold it across further `writer.print`/`writeAll` calls.
4. `.fromArrayList(allocator, *ArrayList(u8))` wraps an existing ArrayList so you can migrate incrementally without rebuilding accumulated state.
5. Under the hood, `Allocating.drain` / `sendFile` are the vtable hooks; you rarely touch them directly.

**Mid-build inspection (use with care):**

```zig
var out: std.Io.Writer.Allocating = .init(allocator);
try out.writer.writeAll("abcdef");
const view = out.written();       // "abcdef", borrowed
std.debug.assert(view.len == 6);
try out.writer.writeAll("ghi");
// view is NOW POTENTIALLY INVALID — do not use `view` past this line.
// Call out.written() again to get a fresh slice.
```

**Use case: streaming into an existing ArrayList and back:**

```zig
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);

var out = std.Io.Writer.Allocating.fromArrayList(allocator, &list);
try out.writer.print("appended: {d}\n", .{42});
list = out.toArrayList();          // resets Allocating, gives back the ArrayList

// or just toOwnedSlice() if you want the bytes detached from the list.
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

### `ArrayList(Unmanaged)` lost its field defaults — use `.empty`

This is one of the highest-impact-per-character 0.16 changes, and one I originally missed documenting. `std.ArrayListUnmanaged(T)` and `std.ArrayList(T)` no longer have default values for their `items` and `capacity` fields. That means every 0.15-era pattern like this stops compiling:

```zig
// ❌ 0.15 style — no longer works in 0.16
var list: std.ArrayListUnmanaged(T) = .{};
var list = std.ArrayListUnmanaged(T){};
const MyStruct = struct {
    items: std.ArrayListUnmanaged(T) = .{},   // field default
};
```

The 0.16 replacement is the `.empty` decl literal (consistent with `BitSet`, `EnumSet`, `PriorityQueue`, etc.):

```zig
// ✅ 0.16 style
var list: std.ArrayListUnmanaged(T) = .empty;
const MyStruct = struct {
    items: std.ArrayListUnmanaged(T) = .empty,
};
```

Definition in stdlib (`std/array_list.zig:591`):

```zig
pub const empty: Self = .{
    .items = &.{},
    .capacity = 0,
};
```

Also affects:

- `@splat(.{})` filling an array of ArrayListUnmanaged → `@splat(.empty)`.
- User-defined wrapper structs that hold an ArrayListUnmanaged field. If the wrapper previously worked with `Wrapper = .{}` (because all its fields had defaults), you need to either add `pub const empty: Wrapper = .{}` on the wrapper and switch callers to `.empty`, **or** update callers to write out the fields explicitly.

**Migration tactic:** `sed -i 's/= \.{}/= .empty/g' yourfile.zig` is usually safe because `= .{}` almost exclusively refers to container initialization. The few places it's not (e.g., `fn foo() .{} {}` return types) will compile-error loudly and can be hand-fixed.

### `std.mem.trimLeft` / `trimRight` renamed to `trimStart` / `trimEnd`

```
std.mem.trimLeft   → std.mem.trimStart
std.mem.trimRight  → std.mem.trimEnd
std.mem.trim       → std.mem.trim       (unchanged)
```

Mechanical sed: `sed -i -e 's/std\.mem\.trimLeft/std.mem.trimStart/g' -e 's/std\.mem\.trimRight/std.mem.trimEnd/g' yourfile.zig`.

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
// Return type: ![]const [:0]const u8 — slice of null-terminated slices.
// args[0] is the executable path; args[1..] are user arguments.
// Safe to pass elements to std.mem.eql(u8, arg, "--flag"), std.debug.print("{s}", .{arg}), etc.
```

Note: `toSlice` is fallible (allocates into the arena). Prefer `init.args.iterate()` on the `Minimal` path if you want a zero-allocation iterator.

### ⚠️ `init.gpa` is `DebugAllocator` in Debug — TWO big surprises

This is one of the most impactful 0.16 behavioral changes for programs migrating from `std.heap.page_allocator`. There are **two independent surprises**:

#### Surprise 1: Latent leaks now dump to stderr

`init.gpa` in Debug is a `std.heap.DebugAllocator` that performs leak detection at process exit. Exit code stays 0, but every un-freed allocation prints a stack trace. These are almost always **pre-existing bugs** that `page_allocator` silently masked. Common culprits:

- `const owned = try allocator.dupe(u8, s);` stored in a hashmap and never freed.
- `try xs.toOwnedSlice(allocator)` where the source `ArrayListUnmanaged` wasn't `deinit`-ed.
- Arena-style ad-hoc allocators layered over page_allocator that relied on process-exit cleanup.

#### Surprise 2 (much bigger): catastrophic slowdown on allocator-heavy workloads

**DebugAllocator's per-allocation bookkeeping is O(n) in the live-allocation count.** When that count grows — because your program has long-lived allocations, or (worse) leaks that don't free until exit — every subsequent allocation does a lookup against a larger tracking set. In practice this translates to **up to 1400× slowdown** for programs that do many small allocations and retain most of them.

Concrete data from a real migration (the `nexus` parser generator, 0.15.2 → 0.16.0):

| Workload | page_allocator (0.15) | init.gpa (0.16 Debug) | init.arena (0.16 Debug) | slowdown vs arena |
|---|---|---|---|---|
| Small grammar (basic) | ~instant | 0.55s | 0.34s | 1.6× |
| Medium grammar (features) | ~instant | 0.67s | 0.014s | **48×** |
| MUMPS grammar | ~instant | 23s | 0.28s | **82×** |
| `slash` grammar | ~instant | 8s | 0.05s | **160×** |
| `zag` grammar | ~instant | 27s | 0.20s | **1,421×** |
| Full test suite | ~5s | 187s | 1.73s | **108×** |

**A `ReleaseSafe` build of the same code**: MUMPS generation drops from 23s (Debug+init.gpa) to **0.033s** (ReleaseSafe+smp_allocator) — a 700× swing purely from the allocator change. So the slowdown is not "generally Zig 0.16" — it's specifically `DebugAllocator` in Debug.

#### Three handling strategies

1. **`init.arena.allocator()` at the top of `main()`.** Best choice for **short-lived CLIs**: read input, compute, emit output, exit. Nexus, code generators, grammar compilers, most build-time tools fit this shape. Arena has zero leak-tracking overhead and individual `.free()` calls become harmless no-ops. Silences both surprises.

   ```zig
   pub fn main(init: std.process.Init) !void {
       const allocator = init.arena.allocator();
       const io = init.io;
       // ... rest of main ...
   }
   ```

2. **Keep `init.gpa`; fix every leak.** Correct answer for **long-lived programs** (servers, LSPs, interactive tools, libraries). Large scope but delivers the right signal: leaks now have behavioral consequences.

3. **`init.gpa` with tests, `init.arena` in production.** Hybrid: keep the DebugAllocator signal for leak-hunting sessions and CI auditing, but default to arena for speed. Simplest implementation is a CLI flag or env var that swaps the allocator at startup.

#### How to decide which strategy applies

| If your program is… | Use |
|---|---|
| A one-shot CLI that reads input, computes, writes output, exits | **arena** |
| A long-running server, LSP, daemon, or REPL | **fix leaks** |
| A library consumed by other code | **fix leaks** (callers don't want your leaks) |
| A code generator / compiler with allocator-heavy codegen | **arena** |
| A build-time tool (e.g. build.zig scripts) | **arena** |

#### The migration-authoring heuristic

Post-mortem observation from a real migration: **allocator-behavior changes are invisible from release notes alone.** The 0.16 release notes tell you `std.heap.page_allocator` is no longer the recommended default and that `init.gpa` is a `DebugAllocator`. What they *cannot* tell you is how that interacts with your program's specific allocation pattern — and for allocation-heavy programs, the interaction can be catastrophic.

**Lesson:** when migrating, time a representative real workload in Debug mode before calling the migration "done." Cheap to do (`time ./your-tool <real-input>`), cheap to spot (any 10×+ regression vs 0.15 is almost certainly this).

#### Corollary: OOM paths may wake up

If your existing code relied on `page_allocator`'s "never fails" behavior, `init.gpa` may also surface OOM error paths that were previously dead code. That's generally good, but it's a real behavioral difference to watch for.

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
| `std.heap.GeneralPurposeAllocator(.{}){}` | `std.heap.DebugAllocator(.{})` (still does leak detection) or `init.gpa` from Juicy Main |
| `std.process.argsAlloc(allocator)` | `init.minimal.args.toSlice(arena)` or `init.args.iterate()` |
| `std.process.argsWithAllocator(allocator)` | same as above — both 0.15 spellings are gone |
| `file.readToEndAlloc(allocator, max)` | `var fr = file.reader(io, &.{}); try fr.interface.allocRemaining(allocator, .limited(max))` (caps via `Io.Limit`; cap-breach error is `error.StreamTooLong`) |
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
| `var out: std.ArrayList(u8) = ...; out.writer(allocator)` | `var out: std.Io.Writer.Allocating = .init(allocator); &out.writer` |
| `out.toOwnedSlice(allocator)` (on ArrayList(u8)) | `out.toOwnedSlice()` (on `Writer.Allocating`) |
| `var list: std.ArrayListUnmanaged(T) = .{}` | `var list: std.ArrayListUnmanaged(T) = .empty` |
| `std.ArrayListUnmanaged(T){}` | `std.ArrayListUnmanaged(T){ .items = &.{}, .capacity = 0 }` or `.empty` via type annotation |
| `field: std.ArrayListUnmanaged(T) = .{}` (struct field default) | `field: std.ArrayListUnmanaged(T) = .empty` |
| `@splat(.{})` filling `[N]std.ArrayListUnmanaged(T)` | `@splat(.empty)` |
| `std.mem.trimLeft(u8, s, " ")` | `std.mem.trimStart(u8, s, " ")` |
| `std.mem.trimRight(u8, s, " ")` | `std.mem.trimEnd(u8, s, " ")` |
| `std.fs.cwd()` | `std.Io.Dir.cwd()` |
| `std.fs.File.read` | `std.Io.File.readStreaming` |
| `std.fs.File.pread` | `std.Io.File.readPositional` |
| `std.fs.File.write` | `std.Io.File.writeStreaming` |
| `std.fs.File.pwrite` | `std.Io.File.writePositional` |
| `std.fs.File.writeAll` | `std.Io.File.writeStreamingAll` |
| `std.process.getCwd` | `std.process.currentPath(io, ...)` |
| `std.process.Child.run(...)` | `std.process.run(allocator, io, .{ ... })` |
| `std.process.execv(arena, argv)` | `std.process.replace(io, .{ .argv = argv })` |
Note: in 0.16, **`std.time` is just unit constants** (`ns_per_ms`, `ns_per_s`, `us_per_ms`, `ms_per_s`, etc.) plus the `epoch` submodule. `Instant`, `Timer`, `timestamp()`, `milliTimestamp()`, `nanoTimestamp()` — all gone. And `std.Thread` no longer exports sync primitives: `Mutex`, `Condition`, `ResetEvent`, `Semaphore`, `RwLock`, `WaitGroup`, `Pool`, **`Futex`** — all removed from `std.Thread`. The replacements live under `std.Io` (and `std.Io.futex*` for futex ops — see the Futex rows below; there is no `std.Io.Futex` type).

| `std.Thread.Mutex` | `std.Io.Mutex` |
| `std.Thread.Condition` | `std.Io.Condition` |
| `std.Thread.ResetEvent` | `std.Io.Event` |
| `std.Thread.WaitGroup` | `std.Io.Group` |
| `std.Thread.Semaphore` | `std.Io.Semaphore` |
| `std.Thread.RwLock` | `std.Io.RwLock` |
| `std.Thread.Futex.wait(ptr, expected)` | `std.Io.futexWait(io, T, ptr, expected)` (free fn; no `std.Io.Futex` type) |
| `std.Thread.Futex.timedWait(ptr, expected, ns)` | `std.Io.futexWaitTimeout(io, T, ptr, expected, Timeout)` |
| `std.Thread.Futex.wake(ptr, n)` | `std.Io.futexWake(io, T, ptr, n)` |
| `std.Thread.Pool` | `std.Io.async` / `std.Io.Group` |
| `std.Thread.sleep(ns)` | `std.Io.sleep(io, Clock.Duration.fromMilliseconds(N), .awake)` — sleep moved to the Io interface along with the sync primitives |
| `std.time.Instant.now()` + `.since(other)` | `std.Io.Clock.Timestamp.now(io, .awake)` + `.durationTo(other).raw.toNanoseconds()` |
| `std.time.Timer.start()` + `timer.read()` | same as `Instant` above |
| `std.time.timestamp()` | `std.Io.Clock.Timestamp.now(io, .real).raw.toSeconds()` |
| `std.time.milliTimestamp()` | `std.Io.Clock.Timestamp.now(io, .real).raw.toMilliseconds()` |
| `std.time.nanoTimestamp()` | `std.Io.Clock.Timestamp.now(io, .real).raw.toNanoseconds()` |
| `std.crypto.random.bytes(&buf)` | `io.random(&buf)` |
| `std.posix.getrandom(&buf)` | `io.random(&buf)` |
| `std.crypto.random` (interface) | `std.Random.IoSource{.io = io}.interface()` |
| `std.posix.mlock(slice)` | `std.process.lockMemory(slice, .{})` |
| `std.posix.mlockall(...)` | `std.process.lockMemoryAll(...)` |
| `std.posix.PROT.READ \| std.posix.PROT.WRITE` | `.{ .READ = true, .WRITE = true }` — **type change, not syntax rename**: `PROT` is now a packed struct (`macho.vm_prot_t` on macOS), not a namespace of integer decls. `posix.mmap`'s `prot` parameter is the struct type, not `u32`. |
| `std.posix.close(fd)` | Low-level: `_ = std.c.close(fd)` (returns `c_int`, ignored for the usual void contract). High-level: `std.Io.File.close(io, file)`. |
| `std.posix.fstat(fd)` | Low-level: `var st: std.c.Stat = undefined; if (std.c.fstat(fd, &st) != 0) return err;`. High-level: `file.stat(io)`. |
| `std.posix.ftruncate(fd, len)` | Low-level: `if (std.c.ftruncate(fd, len) != 0) return err;`. High-level: `file.setLength(io, len)`. |
| `std.posix.fsync(fd)` | Low-level: `if (std.c.fsync(fd) != 0) return err;`. High-level: `file.sync(io)`. (Note: `std.posix.fdatasync` **did** survive — Linux-optimized path.) |
| `std.posix.unlink(path)` | Low-level: `_ = std.c.unlink(path)` — takes `[*:0]const u8`, so `[:0]`-terminated slices work via `.ptr`. High-level: `std.Io.Dir.cwd().deleteFile(io, path)`. |
| `std.posix.kill(pid, 0)` | Low-level: `std.c.kill(pid, @enumFromInt(0))` — `std.posix.kill`'s `sig` parameter is the typed `SIG` enum with no named `0` variant on macOS; the `c.kill` extern takes the enum value by ABI so `@enumFromInt(0)` works for the POSIX null-signal existence check. |
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

The format specifier grammar (`{[pos][spec]:[fill][align][width].[prec]}`) and the set of specifiers (`{s} {c} {d} {x} {X} {o} {b} {e} {E} {u} {any} {f} {*}`) is unchanged from 0.15. Differences in 0.16:

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
| `tried to invoke non-function 'std.Io.Writer.Allocating.writer'` | `.writer` is a field, not a method | Use `alloc.writer.print(...)` or `&alloc.writer` (no parens) |
| `expected type 'std.Io.Limit', found 'comptime_int'` | Passing bare integer where `Io.Limit` expected | Use `.limited(N)` — enum literal method call |
| `unable to find error 'FileTooBig'` | Error renamed for limited reads | Switch to `error.StreamTooLong` |
| `type 'std.Io.File' has no member 'writeAll' with 1 argument` | 0.15-style one-arg writeAll | Use `file.writeStreamingAll(io, bytes)` |
| `missing struct field: items` (and/or `capacity`) on `std.ArrayListUnmanaged(T)` | `ArrayListUnmanaged` lost field defaults | Replace `= .{}` / `T(){}` with `= .empty` (decl literal) |
| `root source file struct 'mem' has no member named 'trimLeft'` | renamed in 0.16 | `std.mem.trimStart(...)` / `std.mem.trimEnd(...)` |
| `struct 'MyWrapper' has no member named 'empty'` | You ran a blanket `= .{}` → `= .empty` sed that hit a user-defined struct | Either add `pub const empty: MyWrapper = .{};` to the struct, or revert those specific sites to `= .{}` with explicit sub-field defaults |
| Stderr dump: `error(DebugAllocator): memory address 0x... leaked:` after process exit | `init.gpa` is DebugAllocator in Debug, surfacing pre-existing leaks | See the "⚠️ `init.gpa` is `DebugAllocator`" section under Juicy Main. Exit code stays 0; tests still pass. Fix in a follow-up PR. |

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
13. **"`std.Io.Writer.Allocating.writer()` is a method."** — It's a **field**. Use `alloc.writer.print(...)` or `&alloc.writer`, not `alloc.writer()`. (This is one of the easiest 0.16 compile errors to trigger when porting.)
14. **"`readFileAlloc`'s size cap is still a `usize`."** — No — it's now `Io.Limit`. Write `.limited(N)` at the call site, not a bare integer. The error for hitting the cap is now `error.StreamTooLong`, not `error.FileTooBig`.
15. **"`std.ArrayListUnmanaged(T) = .{}` still works for an empty list."** — Gone. Use `.empty`. Same for `ArrayList(T)`. Affects direct locals, struct-field defaults, and `@splat(.{})`.
16. **"`std.mem.trimLeft` / `trimRight` are still the names."** — They were renamed to `trimStart` / `trimEnd` in 0.16. Plain `trim` is unchanged.
17. **"If I migrate `page_allocator` → `init.gpa`, nothing runtime-visible changes."** — Wrong on **two** dimensions. (a) `init.gpa` is `DebugAllocator` in Debug and dumps leak traces to stderr at exit. Exit code stays 0 but stderr fills up. (b) DebugAllocator tracking is O(n) in live allocations, which can make allocation-heavy programs **hundreds to thousands of times slower** in Debug. For short-lived CLIs, `init.arena.allocator()` is the correct default. See the ⚠️ section under Juicy Main.
18. **"My short-lived CLI should use `init.gpa` because it's the idiomatic 0.16 default."** — Only if you actually need leak tracking. `init.arena.allocator()` is both **faster in Debug** (no per-allocation bookkeeping) and **cleaner** (no leak spam) for programs that do one computation and exit.
19. **"`std.Thread.Futex` just got renamed to `std.Io.Futex`."** — No — `std.Thread.Futex` was **removed**, and `std.Io.Futex` does not exist. The replacements are three **free functions** on `std.Io`: `futexWait`, `futexWaitTimeout`, `futexWake`. Each takes `io: Io` as the first argument and a `*align(@alignOf(u32)) const T` where `T` is 4 bytes. Library code without an `Io` to thread through can use `std.Io.Threaded.global_single_threaded.io()` for the futex call — stdlib's blessed singleton for exactly this purpose.
20. **"`std.posix.PROT.READ` still works, I just have to use struct syntax at the call site."** — The syntax change is the visible part, but the underlying story is a **type change**: on macOS `PROT` is now `macho.vm_prot_t = packed struct(u32) { READ: bool, WRITE: bool, ... }`. `PROT.READ` was a decl constant in 0.15; in 0.16 it's a field access on a struct type, which doesn't compile as a decl reference. And `std.posix.mmap`'s `prot` parameter is now the struct type itself, not `u32`, so `@intCast(PROT.READ)` no longer works either. The working form is `.{ .READ = true, .WRITE = true }` passed directly.
21. **"A bunch of `std.posix.*` functions just got renamed."** — No — several mid-level wrappers were **removed entirely**. Specifically: `close`, `fstat`, `ftruncate`, `fsync`, `unlink`, `kill`'s integer-sig form. `std.posix` in 0.16 is deliberately thinner. The two migration paths are: **high-level** — move the caller to `std.Io.File.*` / `std.Io.Dir.*` with an `io: Io` parameter (the idiomatic 0.16 shape), or **low-level** — drop to `std.c.*` externs (return `c_int` with POSIX 0/−1 contract, caller checks). The low-level path is appropriate when an OS-abstraction layer already exists and you don't want `io` plumbing to leak into it. Notably, **`std.posix.fdatasync`, `mmap`, `munmap`, `msync`, `madvise`, `openatZ`, and `kill` (with `SIG` enum)** survived as-is.
22. **"`std.posix.kill(pid, 0)` still checks if a process is alive."** — The `sig: SIG` parameter is now a typed enum (on macOS an open `enum(u32) { _, ... }` with no named `0` variant). The POSIX null-signal semantics are still valid at the syscall, but Zig's type surface rejects the bare `0`. The idiomatic workaround for the process-existence check is `std.c.kill(pid, @enumFromInt(0))` — the libc extern takes the enum value via the C ABI, and signal number 0 remains the null signal.
23. **"I can write `/// ...` documentation before a `test \"...\"` block."** — 0.15 allowed it; 0.16 rejects it with **"documentation comments cannot be attached to tests"**. Use plain `//` for comments preceding tests. Module-level `//!` at the top of a file is still fine. This is a small but common port regression — test files that had doc comments explaining each test block need a mechanical `///` → `//` on those lines only.

---

## Migration Workflow Tactics (lessons from a real 0.15.2 → 0.16.0 port)

This section captures the execution playbook for actually *doing* a 0.15 → 0.16 migration, informed by an end-to-end port of a ~7,300-line parser generator. It's aimed at a future AI (or human) undertaking the same work.

### Phase 0 — Empirical baseline before any edits

Don't trust release notes alone for exact API spellings. Before touching code:

```bash
zig build 2>&1 | tee /tmp/migration-baseline.log
```

Zig 0.16 compiles lazily and typically reports one error at a time, so this is a **probe, not a census**. That's fine — it tells you the first thing that breaks, which drives Phase 1.

### Phase 1 — Fix one API family at a time, compile between each

Going wide on multiple API families simultaneously makes error attribution hard. The sequence that worked best:

1. **`main()` signature + argv** (Juicy Main: `pub fn main(init: std.process.Init) !void`). Smallest diff, unblocks everything.
2. **File I/O** (`std.fs.*` → `std.Io.Dir` / `std.Io.File`, add `io` parameter). Mechanical.
3. **Writer-allocating pattern** (`ArrayListUnmanaged(u8).writer(alloc)` → `std.Io.Writer.Allocating`). Medium size.
4. **Misc renames** (`trimLeft`/`trimRight` → `trimStart`/`trimEnd`, etc.). Trivial.

Between each: `zig build`, read the next error, proceed. Don't batch.

### Phase 2 — Verify with compiler before trusting your memory of the API

0.16 has enough subtle API-shape changes (e.g., `Allocating.writer` is a field, not a method; `ArrayListUnmanaged(T){}` no longer works) that **even the release notes can mislead**. Before mass-editing, read the actual stdlib:

```bash
zig env  # find std_dir
# then for each API you'll touch, grep or read the actual source:
# e.g., /opt/homebrew/Cellar/zig/0.16.0/lib/zig/std/Io/Writer.zig
grep -n "pub const Allocating" <std_dir>/Io/Writer.zig
```

This is a 5-minute investment that eliminates ~3-5 compile-fix-recompile cycles.

### Phase 3 — Test with real workloads, not just "does it build"

After getting a green build, run the program on its **largest realistic input in Debug mode** and time it. If you see 10×+ regression vs 0.15:

- Check for `init.gpa` in a workload that allocates heavily or retains most allocations — this is the DebugAllocator slowdown (see the ⚠️ section under Juicy Main).
- Swap in `init.arena.allocator()` for short-lived CLIs; for long-running programs, actually fix the leaks.

### Useful grep-level safety nets

Before claiming a migration is complete, sweep for stragglers:

```bash
# Old APIs that should have no callers left:
rg "std\.fs\." --type zig                        # → should be 0
rg "std\.mem\.(trimLeft|trimRight)\b" --type zig  # → should be 0
rg "std\.io\.(fixedBufferStream|GenericWriter|GenericReader|AnyReader|AnyWriter)\b" --type zig
rg "std\.process\.argsAlloc\b" --type zig
rg "std\.heap\.ThreadSafeAllocator\b" --type zig
rg "std\.Thread\.Pool\b" --type zig

# Old container initialization syntax:
rg "ArrayListUnmanaged\([^)]*\) = \.\{\}" --type zig
rg "ArrayListUnmanaged\([^)]*\)\{\}" --type zig

# Old comments/docs (code may be migrated but comments stale):
rg "// .*std\.fs\." --type zig
rg "// .*std\.io\.(GenericWriter|GenericReader|fixedBufferStream)" --type zig
```

Zero matches on all = high confidence the diff is complete.

### Sed tactics that worked

For mass-migratable patterns, `sed` sweeps saved ~100 StrReplace calls:

```bash
# The big one - container default initialization:
sed -i '' 's/= \.{}/= .empty/g' yourfile.zig

# Specific renames:
sed -i '' -e 's/std\.mem\.trimLeft/std.mem.trimStart/g' \
          -e 's/std\.mem\.trimRight/std.mem.trimEnd/g' yourfile.zig
```

**Important caveats:**

- `= .{}` → `= .empty` is *nearly* always correct, but breaks if a non-container struct also uses `= .{}` as a default. Fix by adding `pub const empty: MyStruct = .{};` to the wrapper struct.
- After any sed sweep: `git diff` before recompiling, visually scan for obvious mistakes in the diff.
- `.{}` WITHOUT `= ` (e.g., in `@splat(.{})`, `createFile(path, .{})`, `std.debug.print("...", .{})`) is safe to leave as-is — only `= .{}` assignment form is the problem. The above sed only matches `= .{}` so it won't touch the others.

### Handling generated/vendored files

If your project contains code generated from some source (e.g., parser generators, protobuf output), think carefully about regeneration vs manual editing:

- **Templates in the generator must emit 0.16-compatible code** so regenerated files are correct.
- **Checked-in generated files may have 0.15 patterns** that won't compile standalone under 0.16. If the generator imports them lazily (via `@import` without field-level access), **Zig 0.16's lazy field analysis lets them coexist** — you don't need to edit the generated file, just fix the generator's templates and regenerate.
- After regeneration, diff against git. Diffs should be **exclusively the expected migrations** (e.g., `.{}` → `.empty`). Any unexpected drift is a bug.

### What release notes reliably *do* tell you

- API renames and signature shapes (trust them as starting points, verify exact argument order against stdlib).
- Removed items.
- Philosophy changes (e.g., "I/O as an Interface").

### What release notes *don't* tell you reliably

- Performance characteristics of new default allocators under specific workloads.
- Field-default removals on widely-used types (release notes often focus on APIs, not data-layout changes on heavily-used structs).
- Ergonomic papercuts like "this works in all cases *except* inside a template string for generated code."
- Which 0.15 program patterns that worked "by accident" will now break (e.g., page_allocator's never-fail behavior hiding OOM paths).

The migration heuristic: **release notes tell you what changed; real workloads tell you what matters.**

### Recommended peer-review hygiene

Migrations benefit from having a second AI or human review at least once **after initial drafting** and again **after execution**:

- Pre-execution review catches over-confident claims (e.g., "this API is definitely spelled X") and forces empirical verification.
- Post-execution review catches issues the executor was too close to notice (silent-failure `catch` blocks, dead imports, scope creep into unrelated cleanup).

Tools: the `user-ai` MCP's `discuss` conversation is a good fit — it preserves context across multiple rounds, so pre-migration critique, mid-migration status checks, and post-migration review can all share the same conversation thread.

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
