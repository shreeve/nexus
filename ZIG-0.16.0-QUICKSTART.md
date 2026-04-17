# Zig 0.15.x → 0.16.0 Migration — Quickstart Kit

This file is a **turn-key quickstart** for pointing an AI (or yourself) at a Zig codebase that needs a 0.15.x → 0.16.0 migration. It's small on purpose. The actual reference material lives in `ZIG-0.16.0.md` (1,800+ lines of changelog, patterns, decoder tables, and workflow playbook distilled from a real end-to-end port).

---

## What this kit is and isn't

**It IS:** A field-tested migration playbook that took a ~7,300-line Zig 0.15.2 parser generator to 0.16.0 in one session. Tests passed 40/40 afterwards. Performance went *up* (187s → 1.73s test runtime). It captures both the API changes *and* the surprises that aren't obvious from release notes alone — most importantly, `std.heap.DebugAllocator`'s up-to-1400× slowdown on allocator-heavy workloads in Debug builds.

**It ISN'T:** A substitute for running the compiler. Every migration surfaces one or two project-specific surprises that no generic doc can predict. Use this kit to go fast through the known 80%, and plan for compile-fix-compile cycles on the last 20%.

---

## Required inputs (what you must have)

1. **The code to migrate.** Obviously.
2. **Zig 0.16.0 installed locally.** The AI will verify API shapes against the installed stdlib source (much more reliable than trusting any prose doc).
   - Check with `zig version` — should print `0.16.0`.
   - Install via your package manager (`brew install zig` on macOS, etc.).
3. **A shell the AI can run** (`zig build`, `zig build test`, `rg`, `sed`).
4. **This file (`ZIG-0.16.0-QUICKSTART.md`) and its companion (`ZIG-0.16.0.md`).**

## Optional inputs (helpful but not required)

- **`ZIG-0.15.2.md`** — only if your code is *pre-0.15* (e.g., still uses `usingnamespace`, `async`/`await` keywords, old format string `{}` without `{f}`/`{any}`). If your code already compiled under 0.15.x, you don't need this.
- **A peer AI for review rounds** — the nexus migration benefited materially from pre-execution critique and post-execution review via the `user-ai` MCP's `discuss` tool. Not required; scales the quality bar.

---

## Copy-paste bootstrap prompt for a fresh AI chat

Paste this as your first message in a new chat. Replace the `<…>` fields.

```
I need to migrate a Zig codebase from 0.15.x to 0.16.0.

Reference files (both attached/available in this workspace):
- ZIG-0.16.0-QUICKSTART.md  (start here; this is the protocol)
- ZIG-0.16.0.md             (full changelog + decoder + playbook)

Codebase:
- Path: <absolute path to the project root>
- Primary source files: <list the .zig files or "the whole src/ tree">
- Has build.zig: <yes/no>
- Has a test harness: <yes/no + path to test runner if any>
- Uses generated code: <yes/no — if yes, describe briefly>

Zig 0.16.0 is installed locally (verified with `zig version`).

Please follow the "Migration Workflow Tactics" section at the end of
ZIG-0.16.0.md. Specifically:
1. Start with Phase 0 (empirical baseline — `zig build`, capture errors,
   do not edit code yet).
2. Migrate one API family at a time, compiling between each step.
3. Time a representative real workload after the build goes green
   (specifically watch for DebugAllocator slowdown — see the ⚠️
   section under "Juicy Main").
4. Before declaring done, run the grep safety-net sweep from the
   Workflow Tactics section.

Red flags specific to 0.16 I want you to check for:
- `= .{}` initializers on `ArrayListUnmanaged` / hashmaps (gone;
  use `.empty`).
- `std.mem.trimLeft` / `trimRight` (renamed to trimStart/trimEnd).
- `std.fs.*` (gone; use `std.Io.Dir`/`std.Io.File` with a threaded `io`).
- `std.process.argsAlloc` (gone; use `init.minimal.args.toSlice`).
- `ArrayList(u8).writer(allocator)` code-gen pattern (gone; use
  `std.Io.Writer.Allocating`).
- `init.gpa` in a short-lived CLI (consider `init.arena.allocator()`).

When you hit an API shape you're unsure about, read the installed
stdlib (`zig env` → std_dir → grep the relevant file) instead of
guessing. Don't trust my doc's API spellings blindly; they are a
starting point, not ground truth.

Go.
```

---

## Protocol the AI should follow (mirror of Workflow Tactics)

1. **Phase 0 — Empirical baseline.** `zig build` with no code changes. Capture the first error. Do not edit yet.
2. **Phase 1 — One API family at a time.** In this order: `main()` signature → file I/O → Writer/Reader pattern → misc renames. `zig build` between each.
3. **Phase 2 — Verify API shapes against stdlib.** Before mass-editing, grep the installed stdlib for exact signatures. 5 minutes saved ~10 compile-fix cycles on the nexus port.
4. **Phase 3 — Regenerate (if applicable).** For codebases with generated files (parser output, protobuf, etc.): fix the generator's emit templates to produce 0.16-compatible output, then regenerate. Diff against git — expect only the migrated patterns.
5. **Phase 4 — Test with a real workload.** `zig build test` plus any project-specific tests. Time a large input. If you see 10×+ slowdown vs 0.15, you've likely hit the DebugAllocator trap — see the ⚠️ section.
6. **Final sweep — grep safety nets.** Run the grep commands from Workflow Tactics. Zero matches on all = high confidence migration is complete.

---

## Red flags during execution (probe these immediately if you see symptoms)

| Symptom | Likely cause | Where to look |
|---|---|---|
| `missing struct field: items` on `ArrayListUnmanaged(T)` | Lost field defaults | "Common Bad Assumptions #15" in ZIG-0.16.0.md |
| `tried to invoke non-function 'writer'` on `Allocating` | It's a field, not a method | "Common Bad Assumptions #13" |
| `expected type 'std.Io.Limit'` with integer | `.limited(N)` needed | "Common Bad Assumptions #14" |
| `root source file struct 'mem' has no member 'trimLeft'` | Renamed 0.16 | "Std lib trim rename" subsection |
| `zig build` was fast on 0.15 but now takes 3+ minutes | DebugAllocator perf trap | ⚠️ section under Juicy Main |
| 400+ stderr lines on every `./my-program` run | `init.gpa` leak-checking | Same ⚠️ section; consider arena |
| Generated file has old `.{}` patterns but source doesn't | Fix generator's emit templates, then regenerate | "Handling generated/vendored files" in Workflow Tactics |

---

## Signs of success

- `zig build` → green, no output.
- `zig build test` (or equivalent) → all pass.
- Timed with a representative real workload — no order-of-magnitude slowdown vs 0.15.
- Grep safety-nets from Workflow Tactics return zero matches.
- No stderr spam on a clean `./my-program` run.
- `git diff` shows only the migrations you expected; nothing unexplained.

If all six are true, the migration is done.

---

## Honesty disclaimer

This kit was written from exactly one real migration. It worked for that project. It will probably work for yours with minor adaptations. But every codebase has its own quirks, and 0.16 made enough changes that something novel will almost certainly surface.

**When you hit something this kit doesn't cover:** log it, fix it, and if you feel generous, open a PR against this file (or its parent `ZIG-0.16.0.md`) to help the next person.
