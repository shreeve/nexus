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
   grammar and Zig example in the docs is generated, compiled and run by
   `./test/run` (see `test/README.md`, "Doc tests").
2. **Nothing silent.** A mistake in a grammar is an error, never a skipped
   rule, a guessed default, or a dead alternative. Every known exception is
   a failing test in `test/known/`, and fixing one moves it to
   `test/regress/`.
3. **Located errors.** Every generation error is
   `file:line:col: error: message`, exits 1, and writes nothing.
4. **Deterministic output.** The same grammar gives the same bytes, every
   run, on every machine. Generated code is pinned by `test/golden/`.
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

## Workflow

```bash
zig build                                   # bin/nexus
./test/run                                  # the whole suite; green before every commit
./test/run docs mumps                       # only ids containing docs or mumps
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
- An emitter change: edit `src/codegen/` or `src/lexgen/`, then `zig build`,
  regenerate the frontend, `zig build` again, regenerate again (no diff),
  `./test/run --update gen`, and review every changed line of the goldens.
  Zig inside string templates is invisible to `zig fmt`; the runtime lives
  in `src/codegen/runtime_template.zig`, a real Zig file, for that reason.
- Commit messages are short, imperative, and describe the change. No AI
  attribution lines.

## Downstream

Rig, em (MUMPS) and nexis check in parsers that Nexus 1.x generates
(`zig build parser` in each, using `../nexus/bin/nexus`). A change to
generated code reaches them when they regenerate; their suites are the
final check. Slash and Zag check in parsers from Nexus 0.10.3; their 1.x
grammars are `test/slash/slash.grammar` and `test/zag/zag.grammar` here.
`test/rig`, `test/mumps`, `test/nexis` and the other suites hold copies of
downstream grammars and lang modules: when a downstream grammar changes,
re-sync the copy here in its own commit.

## Map

| Path | Role |
|---|---|
| `nexus.grammar` | the grammar-file grammar (schema mode) |
| `src/main.zig` | the command line and the pipeline |
| `src/frontend/` | the generated frontend parser, its lang module, strict lowering |
| `src/lexgen/` | patterns, automata, lexer emission |
| `src/semantics.zig` | schema, role placement, coverage, static types |
| `src/expand.zig` | desugaring to plain BNF |
| `src/lr/` | LR(0), LALR lookaheads, tables, conflicts, expected sets, repair |
| `src/codegen/` | module composition, actions, the runtime template |
| `test/` | the suite, `test/diff`, `test/bench/` ([test/README.md](test/README.md)) |
| `docs/GRAMMAR.md` | the grammar-file reference |
| `docs/SEMANTICS.md` | the semantic layer and the generated API |
| `docs/INTERNALS.md` | architecture, invariants, performance, the bootstrap |
| `docs/index.html` | the project page (with its images and `nexus.fig`, the logo source) |
| `HANDOFF.md` | current state, open work, tips |
| [ZIG-0.17.md](https://raw.githubusercontent.com/shreeve/zig-agent-docs/main/ZIG-0.17.md) | the Zig 0.17 reference (shreeve/zig-agent-docs) |
