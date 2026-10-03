# Nexus test suite

```bash
./test/run                  # everything, in parallel
./test/run mumps            # only tests whose id contains "mumps"
./test/run -v known         # list each result, including known failures
./test/run --update rig     # rewrite goldens after an intended change, then review the diff
test/diff OLD_NEXUS NEW_NEXUS OLD.grammar NEW.grammar CORPUS   # trees from two generators over a corpus
test/bench/run              # generation time and parse throughput
```

The summary line reads `N passed, M failed, K known`. The suite is green
when nothing fails and no known-failing test has started passing. It
always rebuilds `bin/nexus` first (`zig build`), so a stale binary is never
tested. `zig build test` runs it too. It needs bash, perl, python3 (for
`tools/lexfuzz`) and Zig 0.17, and runs on macOS and Linux with the
systems' own tools.

## What is checked

| Test id | Contract |
|---|---|
| `<grammar>/<case>` | the grammar generates, **compiles** with its `@lang` module and the tree driver, and parsing `test/<grammar>/cases/<case>.*` prints exactly `<case>.tree` |
| `<grammar>/known/<case>` | same, for a case whose `.tree` is the correct output, which the parser does not produce |
| `known/<bug>` | a self-contained test of the correct behavior for one known bug (see below) |
| `regress/<bug>` | a fixed `known/<bug>`, kept as a regression test |
| `adverse/<name>` | `test/adverse/<name>.grammar` is rejected, by generation and by `nexus check`: exit status 1, no output file, a `file:line:col: error` diagnostic, and every `# error:` text in its header (case-insensitive) |
| `adverse/known/<name>` | same, for a rejection the generator gets wrong |
| `gen/<grammar>` | the generated parser (with the suite's `flags`) equals `test/golden/<grammar>.zig` byte for byte; every suite has one but `nexus`, whose generated parser is `src/frontend/parser.zig` (`bootstrap`) |
| `sexp/<grammar>` | `nexus --dump-sexp` (the frontend's tree of the grammar) equals `test/golden/<grammar>.sexp`; every grammar file has one, under the first suite that uses it |
| `determinism/<grammar>` | two generations (with the suite's `flags`), and two `--dump-sexp` runs, are identical |
| `bootstrap` | regenerating the frontend from `nexus.grammar` reproduces `src/frontend/parser.zig` |
| `unit/<grammar>` | `zig test` of each `@lang` module file that has `test` blocks, against the generated parser |
| `unit/nexus` | the generator's own Zig unit tests (`zig build unit`) |
| `tools/diff` | `test/diff` finds no differences between a parser and itself on the MUMPS cases |
| `tools/fmt` | the `zig fmt --check` command of `AGENTS.md` passes |
| `tools/lexfuzz` | `test/lexfuzz/fuzz.py` with a fixed seed: generated lexers agree with its reference matcher (see "Lexer fuzzing") |
| `tools/messages` | every error and warning the generator's source can print is printed by `nexus check` on some grammar under `test/` (or in a doc) or by the `tools/cli` commands, unless `test/lib/messages.allow` lists it with a reason; an entry for a message a test prints, or one the source does not have, fails |
| `tools/cli` | the command line: `--version`, `--help`, usage errors (exit 2: no grammar, no output file, the grammar as output, an output file for `check`), unreadable and unwritable files, `-` as standard output, `check`, `--spans`, `--dump-sexp` |
| `docs/<DOC>/L<line>-<name>` | a complete grammar in a Markdown document (`<DOC>` is its path without `.md` and a leading `docs/`: `GRAMMAR`, `test/README`) generates, compiles, and parses each of its inputs to its tree (or, marked `rejects`, fails with its errors) |
| `docs/<DOC>/L<line>-<name>/zig` | that grammar's `zig test` blocks pass against its parser |
| `docs/<DOC>/L<line>` | a grammar fragment parses (or: a malformed doc example) |

A compile failure fails every case of that grammar with the first compiler
error as the reason, so "generated but does not compile" can never pass.
A missing golden fails too; `--update` writes it.

## Grammar suites

Each directory `test/<grammar>/` is a suite (except `golden`, `adverse`,
`known`, `regress`, `lib`, `bench`, `lexfuzz`), and one without a grammar
fails. Nothing needs registering: add a directory, a grammar, and cases.

```
test/mumps/
  mumps.grammar         the grammar
  mumps.zig             its @lang module (every *.zig here is copied next to the parser)
  test.conf             optional settings
  cases/                inputs + goldens, expected to pass
    hand_dots.m
    hand_dots.tree
    expr/               cases parsed with parseExpr instead of the default start
      pattern.m
      pattern.tree
  known/                cases whose .tree is the correct output, not the parser's
```

`test.conf` is a bash snippet run in the suite directory; every key is
optional:

| Key | Default | Meaning |
|---|---|---|
| `grammar` | the only `*.grammar` in the directory (several, and no `grammar`, fail) | grammar path |
| `lang` | every `*.zig` in the directory | `@lang` module files (space-separated) |
| `start` | the parser's first `parse*` method | start rule for `cases/*` |
| `flags` | none | extra generator options, e.g. `--spans` |

A case is any file in `cases/` except `*.tree`, `*.md` and `README*`; its
golden is the same name with the extension replaced by `.tree`. A
subdirectory `cases/<s>/` uses the start rule `parse<S>` (`expr/` →
`parseExpr`), or `<s>` itself when it starts with `parse`.

The in-repo suites:

| Suite | Grammar | Corpus |
|---|---|---|
| `basic`, `features`, `lit_tags` | small feature grammars (no `@lang` module) | hand-written |
| `lists` | `X*`, `X+`, `L(X)`, `L(X, sep)`, `L(X?)` without a schema; its `lists.zig` parses 100,000-item lists in a fixed memory budget | hand-written |
| `lexer` | every @lexer-section construct; tokens printed with their `pre` | hand-written |
| `semantic` | a schema-mode grammar using every semantic feature; its `semantic.zig` tests the generated API | hand-written |
| `spans` | the MUMPS grammar generated with `--spans` | MUMPS cases |
| `nexus` | `nexus.grammar` with `src/frontend/lang.zig` (the self-hosted frontend) | hand-written `@parser` sections covering every construct |
| `rig` | Rig's schema-mode grammar and its `rig.zig`, `diag.zig` (synced from the rig repo) | 132 programs from Rig's tests and examples (raw tree, `parseTree`); `cases/program/` checks the IR after Rig's `Parser` wrapper |
| `mumps` | em's MUMPS grammar | hand-written cases, 27 VistA routines (4 pinned at their parse error), 22 MVTS-derived em compliance routines |
| `zag`, `ruby`, `slash`, `nexis` | downstream grammars without a schema | the Zag examples, hand-written Ruby and Slash, a sample of Nexis tests and examples |

Parse errors are part of the output (`!error …`), so a case may pin down
where and how an input fails.

## Tree format

`test/lib/driver.zig` prints trees one way everywhere (cases, `test/diff`):

```
(tag child …)        a list; long lists break one child per line, indented 2
`text`               a .src leaf (escapes: \\ \` \n \r \t \xHH)
`text`#7             a .src leaf with a non-zero src.id (@as ordinal, MUMPS dot level, …)
"text"               a .str value
name                 a .tag value
_                    nil
(…)@12..40           a list's node span, when the parser records spans (@schema or --spans)
!error ParseError at 3:5 unexpected newline
```

The driver finds every `pub fn parseX(*Parser) !Sexp` at compile time and
offers it as a start rule. `--no-spans` omits the spans.

## Known bugs

`test/known/` is the work queue. Each bug is a directory with a grammar
whose header says what is correct and what goes wrong, and either:

- `cases/` with inputs and `.tree` files: the grammar must generate, compile
  and produce every tree; or
- `# error: <text>` lines: the grammar must be rejected like an adverse test.

Other header directives:

| Directive | Meaning |
|---|---|
| `# error: <text>` | generation must fail (exit 1, nothing written, `file:line:col: error`) and print `<text>` |
| `# absent: <text>` | the generator's output must not contain `<text>` |
| `# generated-has: <text>` | the generated parser must contain `<text>` |
| `# compile-error: <text>` | the grammar generates, but its parser must fail to compile with `<text>` |

Give each bug test its own `@lang` module with a pass-through `Lexer`
wrapper unless the bug is about grammars without one, so that one bug
never hides another.

When a known test starts passing it is reported as **FIXED** (a failure),
with the move to make: `known/<bug>` to `test/regress/`, a
`<grammar>/known/<case>` into `cases/`, an `adverse/known/<name>` into
`test/adverse/`. Make the move in the same commit as the fix, and drop the
"Today:" paragraph from the header: tests outside `known/` describe
current behavior only.

## Differential testing

`test/diff` generates a parser from each of two (nexus, grammar) pairs,
parses a corpus with both (parallel chunks, ReleaseSafe), and compares
trees file by file. Each nexus is a path to a binary or `current`, this
checkout's `bin/nexus` (rebuilt first).

```bash
# A generator change under review: the previous build against this checkout, over VistA
test/diff /tmp/nexus-before/bin/nexus current test/mumps/mumps.grammar test/mumps/mumps.grammar \
    --ext .m ~/Data/Code/em/misc/vista

# A grammar change under review, after a lang Parser wrapper
test/diff --start parseProgram current current OLD/rig.grammar NEW/rig.grammar \
    --ext .rig ~/Data/Code/rig/test ~/Data/Code/rig/examples
```

Results are grouped as `same`, `same_error` (the same parse error),
`tree_differs`, `error_differs`, `new_fails`, `new_parses`, `new_crashes`,
`old_crashes`, and `expected` (paths listed in `--expect FILE`, for
documented intentional changes). The first `--show N` tree differences are
printed as diffs; `--keep DIR` keeps everything (`old.tsv`, `new.tsv`,
`<category>.tsv`, both builds). A file that crashes a parser is recorded as
a crash and the run continues. `@lang` files default to every `.zig` in the
directory of the grammar's `@lang` module (next to the grammar or in its
`src/`); override with `--lang-old` / `--lang-new`, and the start rule with
`--start`, `--start-old`, `--start-new`. The exit status is 0 only when
nothing differs.

## Doc tests

Every Markdown document in the repository (every `*.md` file git tracks)
is split into examples by `test/lib/doctest`, which marks them by their
fence's info string:

| Fence | Checked |
|---|---|
| ` ```grammar NAME.grammar ` | a complete grammar: generates and compiles (with `--spans` etc. after the name as generator options) |
| ` ```grammar NAME.grammar rejects ` | generation fails, and the output contains every line of the next ` ```error ` block |
| ` ```grammar fragment ` / ` ```grammar fragment lexer ` | parses (`nexus --dump-sexp`), as @parser-section or @lexer-section text |
| ` ```input [start=RULE] ` then ` ```tree [no-spans] ` | the last complete grammar parses the input to exactly this tree |
| ` ```zig NAME.zig ` | a file next to the last grammar's parser (its lang module) |
| ` ```zig test ` | `zig test` against the last grammar's parser |
| ` ```zig fragment ` | illustration only |

A `grammar` or `zig` fence without one of these markers fails, and so does
an `input` without its `tree`, so nothing in a document goes untested by
accident. Other fences (`text`, `bash`, ...) are not checked. The examples
are extracted into `.zig-cache/nexus-test/docs/` and run like any suite.

## Lexer fuzzing

`test/lexfuzz/fuzz.py [--seed N] [--specs N] [--inputs N] [-O MODE]` generates random
lexer specs (random patterns, trailing context, the `skip`, `hold` and
`rewind(n)` actions, `{m++}`/`{m--}`, comparison guards, an `after` block), builds
them all with `bin/nexus` into one driver, lexes random inputs, and compares
every token (cat, pos, len, pre) with a reference computed from the lexer's
definition with its own set-of-positions matcher. The DFA itself is also checked
against a backtracking matcher by the unit tests (`src/lexgen/automaton.zig`).
`-O` picks the driver's optimize mode (default `Debug`, which also checks
the generated lexers' safety). The suite runs a small fixed-seed round in
`Debug` as `tools/lexfuzz`; larger seeds and counts are run by hand.

## Benchmarks

`test/bench/run` builds nexus (ReleaseFast by default, `-O` to change,
`--nexus BIN` to time another generator), times generation of every
in-repo grammar, and measures lexing and lexing+parsing throughput on the
full VistA corpus and a synthetic 4 MB Rig file (falling back to the
committed cases when those repos are absent). `test/bench/BASELINE.md` holds
the current numbers; update it when a change moves them.

## Files

| Path | Role |
|---|---|
| `test/run` | the suite |
| `test/diff` | differential mode |
| `test/bench/run`, `test/bench/BASELINE.md` | benchmarks |
| `test/lib/driver.zig` | tree driver compiled into every generated parser |
| `test/lib/build-grammar` | generate + compile one grammar with a given nexus |
| `test/lib/doctest` | extract the doc examples into suites |
| `test/lib/messages`, `test/lib/messages.allow` | the `tools/messages` check, and the messages no test prints yet |
| `test/golden/` | generated-code (`.zig`) and frontend-tree (`.sexp`) goldens |

Builds and scratch output live in `.zig-cache/nexus-test/` (per-suite
builds in `build/<suite>/`, with `gen.log` and `compile.log`), so a failing
case's parser can be run by hand:
`.zig-cache/nexus-test/build/mumps/driver test/mumps/cases/hand_dots.m`.
A suite's compile is skipped when its inputs (the generated parser, its
lang files, the driver, the mode and the compiler) are byte for byte those
of its last build. One `test/run` runs per checkout at a time; a second
exits with status 2.
