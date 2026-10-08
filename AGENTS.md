# AGENTS.md — working on Nexus

Read this before changing anything. It is short on purpose. The state of
the work and what comes next are in [HANDOFF.md](HANDOFF.md).

## North star

Nexus turns one grammar file into one standalone Zig module: a DFA lexer,
an LALR(1) parser, and (with `@schema`) a verified semantic layer. The
grammar is the single source of truth for syntax, tree shape, spans and
diagnostics; generated code is fast, deterministic, and has no runtime
dependency. Nexus parses its own grammar files with a parser it generates.

## Rules

1. **We test and verify everything we say.** A feature exists when a test
   in `./test/run` shows it working; a rejection exists when an adverse
   test proves it. Docs make no claims the suite does not check, and every
   grammar and Zig example in the docs is checked by `./test/run` (see
   `test/README.md`, "Doc tests").
2. **Nothing silent.** A mistake in a grammar is an error, never a skipped
   rule, a guessed default, or a dead alternative. Every message the
   generator can print is printed by some test (`tools/messages`;
   `test/lib/messages.allow` lists the exceptions with a reason, and only
   shrinks). Every known exception is a failing test in `test/known/`, and
   fixing one moves it to `test/regress/`.
3. **Located errors.** Every generation error is
   `file:line:col: error: message`, exits 1, and writes nothing.
4. **Deterministic output.** The same grammar gives the same bytes, every
   run, on every machine. Every suite's generated code and every grammar
   file's frontend tree are pinned by `test/golden/`.
5. **The bootstrap converges.** `src/frontend/parser.zig` is generated from
   `nexus.grammar` and must be a fixed point; never edit it by hand.
6. **The engine knows no language.** No language-specific code in `src/`
   outside the frontend; token names carry no behavior. Behavior belongs in
   the grammar, or in a language's lang module.
7. **Timeless code and docs.** Comments and docs say how things work, in the
   present tense. No "now", "no longer", "used to", "previously", "legacy",
   "for now", version-by-version narration, or compatibility code kept for
   an older Zig or an older Nexus. History belongs in git and
   `CHANGELOG.md`; superseded files are deleted, not kept.
8. **Zig 0.17, all in.** Nexus, and every parser it generates, is Zig 0.17
   code in its current idioms (`@backingInt`, `std.ArrayList`, `last()`,
   `gpa.print`, `std.mem.find*`, `@splat`, `std.lang`). Read
   [ZIG-0.17.md](https://raw.githubusercontent.com/shreeve/zig-agent-docs/main/ZIG-0.17.md)
   before writing Zig, and check a std API in its source (`zig env` prints
   `std_dir`) rather than from memory.
9. **Measure speed.** A change that could affect speed is benchmarked
   before and after with `test/bench/run`, on the same machine; a
   regression is explained, not hidden (`test/bench/BASELINE.md`).
10. **One API for every consumer.** Every generated module has the API of
    [SEMANTICS.md, "The generated API"](docs/SEMANTICS.md#the-generated-api),
    and a lang module declares only what "The lang module" lists. A change
    to the grammar language or that API lands in one commit with every
    consumer copy in this repository (`src/frontend/lang.zig`, the lang
    modules under `test/`, `test/lib/driver.zig`, the doc examples) and a
    `CHANGELOG.md` entry with migration steps per downstream repository.

## Workflow

```bash
zig build                                   # bin/nexus
./test/run                                  # the whole suite; green before every commit
./test/run -j 2 docs mumps                  # only ids containing docs or mumps, two workers
zig build unit                              # the generator's unit tests alone
./test/run --update gen                     # rewrite goldens after an intended change; review the diff
./bin/nexus check some.grammar              # every check, nothing written
./bin/nexus --dump-sexp some.grammar        # the frontend's tree of a grammar file
./bin/nexus nexus.grammar src/frontend/parser.zig   # regenerate the frontend
test/bench/run                              # generation time and parse throughput
zig fmt --check build.zig src/*.zig src/{codegen,lexgen,lr} src/frontend/{lang,lower,frontend}.zig test/lib
```

- Fixing a bug starts with a failing test that reproduces it (`test/known/`).
- A new rejection gets an adverse test; a new feature gets a suite case
  and, if user-visible, a tested doc example.
- A change to `nexus.grammar` or to generated code (`src/codegen/`,
  `src/lexgen/`) runs the bootstrap loop of
  [INTERNALS.md](docs/INTERNALS.md#self-hosting-and-the-bootstrap) and
  reviews every changed line of the goldens. Zig inside string templates
  is invisible to `zig fmt`; the runtime lives in
  `src/codegen/runtime_template.zig`, a real Zig file, for that reason.
- A message the generator can print gets a test that prints it, or an
  entry with a reason in `test/lib/messages.allow`.
- Commit messages are short, imperative, and describe the change. No AI
  attribution lines.

## Downstream

Rig, em (MUMPS) and nexis check in parsers that Nexus generates
(`zig build parser` in each, using `../nexus/bin/nexus`). A change to
generated code reaches them when they regenerate; their suites are the
final check. Slash, Zag and nanoruby check in parsers from Nexus 0.10.3;
their grammars for this Nexus are `test/slash/slash.grammar`,
`test/zag/zag.grammar` and `test/ruby/ruby.grammar` here. `test/rig`,
`test/mumps` and `test/nexis` hold the grammar and lang module of Rig, em
and nexis as their main branches have them, copied verbatim, with case
programs copied from their tests and examples; each `test.conf` names the
source commit. A copy is re-synced, in its own commit, when its project
changes its grammar or lang module. The edits a release asks of each
downstream repository are in `CHANGELOG.md`.

## Map

| Path | Role |
|---|---|
| `nexus.grammar` | the grammar-file grammar (schema mode) |
| `src/` | the generator; [INTERNALS.md](docs/INTERNALS.md#source-map) maps every file |
| `test/` | the suite, `test/diff`, `test/bench/`, `test/lexfuzz/` ([test/README.md](test/README.md)) |
| `docs/GRAMMAR.md` | the grammar-file reference |
| `docs/SEMANTICS.md` | the semantic layer, the generated API, the lang-module contract |
| `docs/INTERNALS.md` | architecture, the bootstrap, invariants, releasing |
| `docs/index.html` | the project page; `docs/assets/` holds its images and `nexus.fig`, the logo source |
| `CHANGELOG.md` | every release, and the migration steps for downstream |
| `HANDOFF.md` | current state, open work, tips |
| [ZIG-0.17.md](https://raw.githubusercontent.com/shreeve/zig-agent-docs/main/ZIG-0.17.md) | the Zig 0.17 reference (shreeve/zig-agent-docs) |
