# HANDOFF.md — the state of Nexus

Read [AGENTS.md](AGENTS.md) first (the rules), then this file (where the
work stands and what comes next). [docs/INTERNALS.md](docs/INTERNALS.md)
is the architecture; [test/README.md](test/README.md) is the suite.

## State

- The current release and what changed since are in
  [CHANGELOG.md](CHANGELOG.md); the "Unreleased" section is the revamp on
  branch `revamp`, which lands on `main` when the owner merges it.
- Benchmark numbers are in [test/bench/BASELINE.md](test/bench/BASELINE.md).
- `./test/run` is green; `test/known/` holds the open bugs.

Verify before you change anything:

```bash
zig version                 # 0.17.0
zig build && ./test/run
git log --oneline -4
```

If `zig version` prints an older Zig, the shell's PATH was set before mise
installed 0.17; run `export PATH="$(mise where zig@0.17.0):$PATH"`.

## Open work

1. **Release.** Bump `src/version.zig`, regenerate, and date the
   CHANGELOG section ([INTERNALS.md, "Releasing"](docs/INTERNALS.md#releasing)).
2. **Downstream moves to Zig 0.17 and this API.** em, rig and nexis use
   Nexus 1.x through `zig build parser` with `../nexus/bin/nexus`; each
   regenerates and applies its CHANGELOG migration steps. As each one
   lands, re-sync its copy here (`test/mumps`, `test/rig`, `test/nexis`)
   and keep `./test/run` green. The `test/mumps` grammar differs from em's
   by the `simd_to` line em still has to delete.
3. **Slash and Zag onto Nexus 1.x.** Their repositories check in parsers
   from Nexus 0.10.3; their 1.x grammars and lang modules are `test/slash`
   and `test/zag` here. `test/diff` compares the trees of a 0.10.3 build
   (from tag `v0.10.3`) with this checkout's over their corpora.
4. **Known bug:** `test/known/x_hint_named_token` (an `X "c"` hint whose
   token the grammar names, `LPAREN` for `"("`, needs the lexer's literal
   map in the LR stage).
5. **Untested messages:** `test/lib/messages.allow` lists the generator
   messages no test prints yet; each needs an adverse test or stays with
   its reason.
6. **Deferred by the owner:** the schemaless tree rules for a leading
   `role:N` head and for `!X` in default actions wait until em's grammar
   work is done.

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
- **Benchmark honestly** ([test/bench/BASELINE.md](test/bench/BASELINE.md),
  "Reading a difference").
- **The VistA corpus** (`~/Data/Code/em/misc/vista`, 24,704 routines) and
  Rig's sources (`~/Data/Code/rig`) feed `test/bench/run` and `test/diff`;
  without them the benchmark falls back to the committed cases.
- **The owner's conventions:** timeless comments and docs (AGENTS.md rule
  7), no compatibility code, no AI attribution in commits, short imperative
  commit messages, a failing test before every fix.
