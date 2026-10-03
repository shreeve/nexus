# HANDOFF.md — the state of Nexus

Read [AGENTS.md](AGENTS.md) first (the rules), then this file (where the
work stands and what comes next). [docs/INTERNALS.md](docs/INTERNALS.md)
is the architecture; [test/README.md](test/README.md) is the suite.

## State

- **`main` holds the revamp of Nexus 1.1.0** (tag `v1.1.0`), merged from
  [shreeve/nexus#5](https://github.com/shreeve/nexus/pull/5). What it
  changes, with migration steps for every downstream repository, is
  CHANGELOG.md's "Unreleased" section; it is unreleased until Open work 1.
- **Zig 0.17.0 only.** Nexus and every parser it generates are Zig 0.17
  code.
- **The suite is green on macOS (arm64) and Ubuntu 26.04 (x86_64):**
  `./test/run` → 737 passed, 0 failed, 0 known; the generated code is byte
  for byte the same on both.
- **Benchmarks** are in [test/bench/BASELINE.md](test/bench/BASELINE.md).
- `src/version.zig` says `1.1.0` until the release (Open work 1).

Verify before you change anything:

```bash
zig version                 # 0.17.0
zig build && ./test/run
git log --oneline -4
```

If `zig version` prints an older Zig, the shell's PATH was set before mise
installed 0.17; run `export PATH="$(mise where zig@0.17.0):$PATH"`.

## Open work

1. **Release.** The owner picks the version: the generated API and the
   grammar language change in breaking ways, which suggests 2.0.0. Then bump
   `src/version.zig`, regenerate, date the CHANGELOG section and tag
   ([INTERNALS.md, "Releasing"](docs/INTERNALS.md#releasing)).
2. **Downstream moves to Zig 0.17 and this Nexus,** one repository at a
   time, each regenerating its parser once and applying its steps from
   CHANGELOG "Migrating":
   - **em:** the two `@conflicts` lines, delete `simd_to`, the API renames;
     and in the same pass make `exprtails` (em's `mumps.grammar`,
     `exprtails = exprtail exprtails`) left-recursive or `exprtail*`: the
     right recursion is quadratic in memory (20,000 terms take 4.8 GB).
     Check with em's suite that every tree stays the same.
   - **rig:** the API renames, and `![","]` for its five unused trailing
     commas (the coverage gate counts an unused optional token).
   - **nexis:** delete its `Tag` enum, the API renames.
   As each one lands, re-sync its copy here (`test/mumps`, `test/rig`,
   `test/nexis`) and keep `./test/run` green. The copies are older than the
   downstream originals, so the suite tests older grammars than the ones
   those projects run: re-syncing is what makes it test theirs.
3. **Slash, Zag and nanoruby onto Nexus 1.x.** Their repositories check in
   parsers from Nexus 0.10.3; their 1.x grammars and lang modules are
   `test/slash`, `test/zag` and `test/ruby` here. `test/diff` compares the
   trees of a 0.10.3 build (from tag `v0.10.3`) with this checkout's.
4. **Deferred by the owner until em's grammar work is done:** the
   schemaless tree rules for a leading `role:N` head (named only in
   unexpanded alternatives) and for `!X` in a rule's default action.
5. **Untested messages:** `test/lib/messages.allow` lists the generator
   messages no test prints, each with its reason; an adverse test that
   prints one deletes its line.
6. **Smaller items:**
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

- **Your Zig knowledge is older than this code.** Check every std API in
  `$(zig env | grep std_dir)` or in
  [ZIG-0.17.md](https://raw.githubusercontent.com/shreeve/zig-agent-docs/main/ZIG-0.17.md)
  §25 and §23.5 (code generators) before writing it.
- **Generated code comes from three places:** `src/codegen/runtime_template.zig`
  (a real Zig file, cut into `// @section` blocks), string templates in
  `src/codegen/codegen.zig` and `actions.zig`, and the lexer emitter in
  `src/lexgen/lexgen.zig`. `zig fmt` and the compiler see only the first;
  a mistake in a string template shows up when a generated parser compiles.
- **After any emitter change** run the bootstrap loop and review the
  goldens by kind ([INTERNALS.md](docs/INTERNALS.md#self-hosting-and-the-bootstrap)).
- **Run a subset while iterating:** `./test/run mumps`, `./test/run gen`,
  `./test/run -v regress`; `-j N` limits the workers on a busy machine. A
  failing case's parser stays built:
  `.zig-cache/nexus-test/build/<suite>/driver FILE` reruns it by hand, with
  `gen.log` and `compile.log` next to it.
- **Mind the machine's load.** The full suite builds about 95 parsers;
  run it with `-j 2` or `-j 3` while other work is running, and do not run
  benchmarks, fuzzing or several suites at the same time.
- **Benchmark honestly** ([test/bench/BASELINE.md](test/bench/BASELINE.md),
  "Reading a difference").
- **The VistA corpus** (`~/Data/Code/em/misc/vista`, 24,704 routines) and
  Rig's sources (`~/Data/Code/rig`) feed `test/bench/run` and `test/diff`;
  without them the benchmark falls back to the committed cases.
- **The owner's conventions:** timeless comments and docs (AGENTS.md rule
  7), no compatibility code, no AI attribution in commits, short imperative
  commit messages, a failing test before every fix.
