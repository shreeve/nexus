# HANDOFF.md — the state of Nexus

Read [AGENTS.md](AGENTS.md) first (the rules), then this file (where the
work stands and what comes next). [docs/INTERNALS.md](docs/INTERNALS.md)
is the architecture; [test/README.md](test/README.md) is the suite.

## State

- **Zig 0.17.0, all in.** Nexus builds with Zig 0.17.0 and every parser it
  generates is Zig 0.17 code. Nothing supports an older Zig.
- **Nexus 1.1.0** (`src/version.zig`, `CHANGELOG.md`): the Zig 0.17 release.
  Grammar files are those of 1.0; the generated code is Zig 0.17.
- **Branch `zig-0.17`** on top of `main` (`c7543cc`): the Zig 0.17 port,
  the removal of the 0.10.3 legacy tooling with a docs refresh, this file,
  the lexer's DFA size in the generation summary, and the 1.1.0 release.
  It lands on `main` through a pull request the owner reviews; `v1.1.0` is
  tagged on `main` after the merge.
- **The suite is green:** `./test/run` → 517 passed, 0 failed, 0 known.
  The frontend is a fixed point; every golden was regenerated and reviewed.
- **Benchmarks** are current in [test/bench/BASELINE.md](test/bench/BASELINE.md):
  MUMPS generation 18.7 ms (the `test/bench/run` minimum, process start
  included), VistA parsing 50.7 MB/s, Rig parsing 59.0 MB/s.

Verify before you change anything:

```bash
zig version                 # 0.17.0
zig build && ./test/run     # 517 passed
git log --oneline -4
```

If `zig version` prints 0.16.0, the shell's PATH was set before mise
installed 0.17 (mise's default is `latest`); run
`export PATH="$(mise where zig@0.17.0):$PATH"`. Building with Zig 0.16 fails
in `build.zig` on `addPassthruArgs`.

## Open work, in order

1. **Merge `zig-0.17` and tag `v1.1.0`.** The owner reviews and merges the
   pull request; tag `v1.1.0` on the merge commit and push the tag.
2. **Downstream moves to Zig 0.17.** em, rig and nexis use Nexus 1.x through
   `zig build parser` with `../nexus/bin/nexus`. This Nexus emits Zig 0.17
   code, so each project moves to Zig 0.17 before it regenerates its parser.
   As each one lands, re-sync its copy here (`test/mumps/mumps.zig`,
   `test/rig/rig.zig` and `diag.zig`, `test/nexis/nexis.zig`) and check that
   `./test/run` stays green. The copies here already compile on 0.17; the
   downstream originals are the source of truth.
3. **Slash and Zag onto Nexus 1.x.** Their repositories check in parsers
   from Nexus 0.10.3. Their 1.x grammars are `test/slash/slash.grammar` and
   `test/zag/zag.grammar` here, with lang modules that compile on 0.17. The
   0.10 → 1.0 porting guide is `docs/PORTING.md` at tag `v1.0.0`. To prove
   a port keeps the trees, build Nexus 0.10.3 from tag `v0.10.3` with the
   Zig it needs, then compare the old grammar under it with the 1.x grammar
   under this checkout:
   ```bash
   test/diff --lang-old ~/Data/Code/zag/src/zag.zig --lang-new test/zag/zag.zig \
       /tmp/nexus-0.10.3/bin/nexus current ~/Data/Code/zag/zag.grammar test/zag/zag.grammar \
       --ext .zag ~/Data/Code/zag/test/examples
   test/diff --lang-old ~/Data/Code/slash/src/slash.zig --lang-new test/slash/slash.zig \
       /tmp/nexus-0.10.3/bin/nexus current ~/Data/Code/slash/slash.grammar test/slash/slash.grammar \
       --ext .sh test/slash/cases
   ```
   The lang files are named explicitly because each repository's `src/`
   holds more than its lang module. The corpora are small (3 Zag examples,
   7 Slash cases); add the projects' own sources and tests as they grow.
4. **Generation is about 8% slower on Zig 0.17 than it was on 0.16** for
   large grammars: MUMPS medians 15.1 → 16.3 ms over 60 interleaved direct
   runs of each binary (a different harness from `test/bench/run`, so
   compare these only with each other). The 0.17 build retires 14% fewer
   instructions in 8% more cycles: a code-generation or layout effect of
   LLVM 22, not extra work. Generated parsers got faster (VistA +2.4%, Rig
   +3.7%). Worth a profile only if generation time starts to matter.

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
- **The bootstrap loop.** After any emitter change: `zig build`, then
  `./bin/nexus nexus.grammar src/frontend/parser.zig`, `zig build`, and the
  same regeneration again; the second one must change nothing. If the
  current frontend no longer compiles, regenerate it with the last good
  `bin/nexus` before rebuilding.
- **Review goldens by kind.** After `./test/run --update gen`, bucket the
  changed lines so every kind is a change you meant:
  `git diff -U0 test/golden | grep -E '^[-+][^-+]' | sed -E 's/[0-9]+/N/g; s/"[^"]*"/"S"/g' | sort | uniq -c | sort -rn | head`
- **Run a subset while iterating:** `./test/run mumps`, `./test/run gen`,
  `./test/run -v regress`. A failing case's parser stays built:
  `.zig-cache/nexus-test/build/<suite>/driver FILE` reruns it by hand, with
  `gen.log` and `compile.log` next to it.
- **Benchmark honestly.** `test/bench/run` twice before and twice after;
  compare minimums; for small differences interleave A/B binaries and read
  instructions and cycles from `/usr/bin/time -l`.
- **The VistA corpus** (`~/Data/Code/em/misc/vista`, 24,704 routines) and
  Rig's sources (`~/Data/Code/rig`) feed `test/bench/run` and `test/diff`;
  without them the benchmark falls back to the committed cases.
- **The owner's conventions:** timeless comments and docs (AGENTS.md rule
  7), no compatibility code, no AI attribution in commits, short imperative
  commit messages, a failing test before every fix.
