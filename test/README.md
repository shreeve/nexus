# Nexus test suite

```bash
./test/run                  # everything (parallel, ~10 s)
./test/run mumps            # only tests whose id contains "mumps"
./test/run -v known         # list each result, including known failures
./test/run --update rig     # rewrite goldens after an intended change, then review the diff
test/diff legacy current A.grammar B.grammar CORPUS   # old-vs-new trees over a corpus
test/bench/run              # generation time and parse throughput
```

The summary line reads `N passed, M failed, K known`. The suite is green
when nothing fails and no known-failing test has started passing. It
always rebuilds `bin/nexus` first (`zig build`), so a stale binary is never
tested. `zig build test` runs it too.

## What is checked

| Test id | Contract |
|---|---|
| `<grammar>/<case>` | the grammar generates, **compiles** with its `@lang` module and the tree driver, and parsing `test/<grammar>/cases/<case>.*` prints exactly `<case>.tree` |
| `<grammar>/known/<case>` | same, for a case whose correct tree is not produced today |
| `known/<bug>` | a self-contained test of the correct behavior for one known bug (see below) |
| `regress/<bug>` | a fixed `known/<bug>`, kept as a regression test |
| `adverse/<name>` | `test/adverse/<name>.grammar` is rejected: non-zero exit, a `file:line:col: error` diagnostic, and every `# error:` text in its header (case-insensitive) |
| `adverse/known/<name>` | same, for rejections that are wrong today |
| `gen/<grammar>` | the generated parser equals `test/golden/<grammar>.zig` byte for byte |
| `sexp/<grammar>` | `nexus --dump-sexp` (the frontend's tree of the grammar) equals `test/golden/<grammar>.sexp` |
| `determinism/<grammar>` | two generations, and two `--dump-sexp` runs, are identical |
| `bootstrap` | regenerating the frontend from `nexus.grammar` reproduces `src/parser.zig` (or `src/frontend/parser.zig`) |
| `unit/<grammar>` | `zig test` of each `@lang` module file that has `test` blocks, against the generated parser |
| `unit/nexus` | the generator's own Zig unit tests (`zig build test-unit`, `unit`, or `test-lowerer`, whichever exists) |
| `tools/diff` | `test/diff` finds no differences between a parser and itself on the MUMPS cases |

A compile failure fails every case of that grammar with the first compiler
error as the reason, so "generated but does not compile" can never pass.

## Grammar suites

Each directory `test/<grammar>/` holding a `*.grammar` is a suite (except
`golden`, `adverse`, `known`, `regress`, `lib`, `bench`). Nothing needs
registering: add a directory, a grammar, and cases.

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
  known/                cases whose .tree is the correct output, not today's
```

`test.conf` is a bash snippet run in the suite directory; every key is
optional:

| Key | Default | Meaning |
|---|---|---|
| `grammar` | the only `*.grammar` in the directory | grammar path |
| `lang` | every `*.zig` in the directory | `@lang` module files (space-separated) |
| `start` | the parser's first `parse*` method | start rule for `cases/*` |
| `generator` | `current` | `legacy` generates with Nexus 0.10.3 instead of `bin/nexus` (for grammars still in the old format once 1.0 no longer reads it); `gen/`, `sexp/` and `determinism/` are then skipped |

A case is any file in `cases/` except `*.tree`, `*.md` and `README*`; its
golden is the same name with the extension replaced by `.tree`. A
subdirectory `cases/<s>/` uses the start rule `parse<S>` (`expr/` →
`parseExpr`), or `<s>` itself when it starts with `parse`.

The in-repo suites:

| Suite | Grammar | Corpus |
|---|---|---|
| `basic`, `features`, `lit_tags` | small feature grammars | hand-written; all in `known/` because the parsers do not compile today |
| `nexus` | `nexus.grammar` with `src/lang.zig` (the self-hosted frontend) | hand-written `@parser` sections covering every construct |
| `rig` | the live Rig grammar and its `rig.zig`, `ir.zig`, `diag.zig` (synced from the rig repo) | 132 programs from Rig's tests and examples (raw tree, `parseTree`); `cases/program/` checks the IR after Rig's `Parser` wrapper |
| `mumps` | em's MUMPS grammar | hand-written cases, 27 VistA routines (4 that fail today), 22 MVTS-derived em compliance routines |
| `zag`, `ruby`, `slash`, `nexis` | downstream grammars (old format) | the Zag examples, hand-written Ruby and Slash, a sample of Nexis tests and examples |

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
(…)@12..40           a list's node span, printed automatically once the parser has span()
!error ParseError at 3:5 unexpected newline
```

The driver adapts at compile time: `Parser` (or `BaseParser` when a
grammar has no `@lang`), lists as slices (0.10.x) or as a struct with
`items()` (1.0), and every `pub fn parseX(*Parser) !Sexp` as a start rule.
When 1.0 adds spans, `./test/run --update` records them in every golden;
review that diff once.

## Known bugs

`test/known/` is the work queue. Each bug is a directory with a grammar
whose header says what is correct and what goes wrong today, and either:

- `cases/` with inputs and `.tree` files: the grammar must generate, compile
  and produce every tree; or
- `# error: <text>` lines: the grammar must be rejected like an adverse test.

Other header directives:

| Directive | Meaning |
|---|---|
| `# error: <text>` | generation must fail (non-zero exit, `file:line:col: error`) and print `<text>` |
| `# absent: <text>` | the generator's output must not contain `<text>` |
| `# generated-has: <text>` | the generated parser must contain `<text>` |

Give each bug test its own `@lang` module with a pass-through `Lexer`
wrapper unless the bug is about grammars without one, so that one bug
never hides another.

When a known test starts passing it is reported as **FIXED** (a failure),
with the move to make: `known/<bug>` to `test/regress/`, a
`<grammar>/known/<case>` into `cases/`, an `adverse/known/<name>` into
`test/adverse/`. Make the move in the same commit as the fix, and drop the
"Today:" paragraph from the header: tests outside `known/` describe
current behavior only. The known tests are written in the 0.10.3 grammar
format; port them along with the other grammars.

## Differential testing

`test/diff` generates a parser from each of two (nexus, grammar) pairs,
parses a corpus with both (parallel chunks, ReleaseSafe), and compares
trees file by file. `legacy` names Nexus 0.10.3 (built from the `v0.10.3`
tag on first use, or `$NEXUS_LEGACY`), `current` this checkout's
`bin/nexus`.

```bash
# The Rig port: 1.0 grammar vs 0.10.3 grammar, both after Rig's Parser wrapper
test/diff --start parseProgram legacy current ~/Data/Code/rig/rig.grammar test/rig/rig.grammar \
    --ext .rig ~/Data/Code/rig/test ~/Data/Code/rig/examples

# MUMPS over VistA + ORO (51k routines, ~3 s of parsing)
test/diff legacy current test/mumps/mumps.grammar NEW/mumps.grammar \
    --ext .m ~/Data/Code/em/misc/vista ~/Data/Code/em/misc/foia/oro
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

## Lexer fuzzing

`test/lexfuzz/fuzz.py [--seed N] [--specs N] [--inputs N]` generates random
lexer specs (random patterns, trailing context, the `skip` action), builds
them all with `bin/nexus` into one driver, lexes random inputs, and compares
every token (cat, pos, len, pre) with a reference computed from the lexer's
definition using Python's `re.fullmatch`. The DFA itself is also checked
against a backtracking matcher by the unit tests (`src/lexgen/automaton.zig`).

## Benchmarks

`test/bench/run` builds nexus (ReleaseFast by default, `-O` to change,
`--nexus BIN|legacy` to time another generator), times generation of every
in-repo grammar, and measures lexing and lexing+parsing throughput on the
full VistA corpus and a synthetic 4 MB Rig file (falling back to the
committed cases when those repos are absent). `test/bench/BASELINE.md` holds
the 0.10.3 numbers; update it when a change moves them.

## Files

| Path | Role |
|---|---|
| `test/run` | the suite |
| `test/diff` | differential mode |
| `test/bench/run`, `test/bench/BASELINE.md` | benchmarks |
| `test/lib/driver.zig` | tree driver compiled into every generated parser |
| `test/lib/build-grammar` | generate + compile one grammar with a given nexus |
| `test/lib/legacy-nexus` | find or build Nexus 0.10.3 |
| `test/golden/` | generated-code (`.zig`) and frontend-tree (`.sexp`) goldens |

Builds and scratch output live in `.zig-cache/nexus-test/` (per-suite
builds in `build/<suite>/`, with `gen.log` and `compile.log`), so a failing
case's parser can be run by hand:
`.zig-cache/nexus-test/build/mumps/driver test/mumps/cases/hand_dots.m`.
