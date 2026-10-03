# HANDOFF.md — the state of Nexus

Read [AGENTS.md](AGENTS.md) first (the rules), then this file (where the
work stands and what comes next). [docs/INTERNALS.md](docs/INTERNALS.md)
is the architecture; [test/README.md](test/README.md) is the suite.

## State

- **Nexus 2.0.0** (tag `v2.0.0`) is the current release. What it changes
  from 1.1.0, with migration steps for every downstream repository, is
  CHANGELOG.md's 2.0.0 section.
- **The suite is green on macOS (arm64) and Ubuntu 26.04 (x86_64):**
  `./test/run` → 730 passed, 0 failed, 0 known; the generated code is byte
  for byte the same on both.
- **Benchmarks** are in [test/bench/BASELINE.md](test/bench/BASELINE.md).

Verify before you change anything:

```bash
zig version                 # 0.17.0
zig build && ./test/run
git log --oneline -4
```

If `zig version` prints an older Zig, the shell's PATH was set before mise
installed 0.17; run `export PATH="$(mise where zig@0.17.0):$PATH"`.

## Open work

1. **Downstream moves to Zig 0.17 and this Nexus,** one repository at a
   time, each regenerating its parser once and applying its steps from
   CHANGELOG "Migrating":
   - **em:** the two `@conflicts` lines, the API renames;
     and in the same pass make `exprtails` (em's `mumps.grammar`,
     `exprtails = exprtail exprtails`) left-recursive or `exprtail*`: the
     right recursion is quadratic in memory (20,000 terms take 4.8 GB).
     Check with em's suite that every tree stays the same.
   - **rig:** its Zig 0.17 port applies its steps (the API renames, and
     `![","]` for five unused trailing commas) and regenerates its parser
     with `v2.0.0`; `test/rig` holds that port's grammar, lang module and
     test programs.
   - **nexis:** delete its `Tag` enum, the API renames.
   As em and nexis land, re-sync their copies here (`test/mumps`,
   `test/nexis`; [AGENTS.md, "Downstream"](AGENTS.md#downstream)) and keep
   `./test/run` green: until then the suite tests older grammars than the
   ones those projects run.
2. **Slash, Zag and nanoruby onto this Nexus.** Their repositories check in
   parsers from Nexus 0.10.3; their grammars and lang modules for this Nexus are
   `test/slash`, `test/zag` and `test/ruby` here. `test/diff` compares the
   trees of a 0.10.3 build (from tag `v0.10.3`) with this checkout's.
3. **Deferred by the owner until em's grammar work is done:** the
   schemaless tree rules for a leading `role:N` head (named only in
   unexpanded alternatives) and for `!X` in a rule's default action.
4. **Untested messages:** `test/lib/messages.allow` lists the generator
   messages no test prints, each with its reason; an adverse test that
   prints one deletes its line.
5. **Smaller items:**
   - `./test/run --update` does not write `.tree` files for
     `test/regress` suites; write them with the suite's built driver.
   - A lang `Parser` wrapper that returns `error.ParseError` on its own
     (rig does) leaves `lastError()` null, so the driver prints the error
     without a position.
   - A label on a non-token value in a rest role reports "is a spread of a
     value that is not a list", which names a spread the user did not write.
   - Doc tests list documents with `git ls-files '*.md'`: an untracked new
     document is not tested until it is added.
   - Generating a grammar of 4,000 chained levels peaks at about 1.4 GB;
     the dense `[state][symbol]` arrays of the lookahead stage dominate.

## Tips

- **Generated code comes from** the runtime template, the string templates
  in `src/codegen/` and the lexer emitter; only the first is seen by
  `zig fmt` and the compiler, so a mistake in the others shows up when a
  generated parser compiles
  ([INTERNALS.md, "Code generation"](docs/INTERNALS.md#code-generation)).
- **Run a subset while iterating:** `./test/run mumps`, `./test/run gen`,
  `./test/run -v regress`; `-j N` limits the workers on a busy machine. A
  failing case's parser stays built for rerunning by hand
  ([test/README.md](test/README.md#files)).
- **Mind the machine's load.** The full suite builds about 95 parsers;
  run it with `-j 2` or `-j 3` while other work is running, and do not run
  benchmarks, fuzzing or several suites at the same time.
- **Benchmark honestly** ([test/bench/BASELINE.md](test/bench/BASELINE.md),
  "Reading a difference").
- **The VistA corpus** (`~/Data/Code/em/misc/vista`, 24,704 routines) and
  Rig's sources (`~/Data/Code/rig`) feed `test/bench/run` and `test/diff`;
  without them the benchmark falls back to the committed cases.
