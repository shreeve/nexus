# Nexus test suite

```bash
./test/run                  # everything, in parallel (-j N workers; the default is the core count)
./test/run mumps            # only tests whose id contains "mumps"
./test/run -v known         # list each result, including known failures
./test/run --update rig     # rewrite goldens after an intended change, then review the diff
test/diff OLD_NEXUS NEW_NEXUS OLD.grammar NEW.grammar CORPUS   # trees from two generators over a corpus
test/bench/run              # generation time and parse throughput
```

The summary line reads `N passed, M failed, K known`. The suite is green
when nothing fails and no known-failing test has started passing. It
always rebuilds `bin/nexus` first (`zig build`), so a stale binary is never
tested. `zig build test` runs it too. It needs bash, perl, Node (for
the VS Code extension's checks, `test/lib/vscode`), python3 (for
`tools/lexfuzz`, the `highlight/*` checks and the language-server
sessions), Vim with `+syntax` (for `highlight/*`) and Zig 0.17, and runs
on macOS and Linux with the systems' own tools.

## What is checked

| Test id | Contract |
|---|---|
| `<grammar>/<case>` | the grammar generates, **compiles** with its `@lang` module and the tree driver, and parsing `<suite>/cases/<case>.*` prints exactly `<case>.tree` |
| `<grammar>/known/<case>` | same, for a case whose `.tree` is the correct output, which the parser does not produce |
| `known/<bug>` | a self-contained test of the correct behavior for one known bug (see below) |
| `regress/<bug>` | a fixed `known/<bug>`, kept as a regression test |
| `adverse/<name>` | `test/adverse/<name>.grammar` is rejected, by generation and by `nexus check`: exit status 1, no output file, a `file:line:col: error` diagnostic, and every `# error:` text in its header (case-insensitive) |
| `adverse/known/<name>` | same, for a rejection the generator gets wrong |
| `gen/<grammar>` | the generated parser (with the suite's `flags`) equals `test/golden/<grammar>.zig` byte for byte; every suite has one but `nexus`, whose generated parser is `src/frontend/parser.zig` (`bootstrap`) |
| `sexp/<grammar>` | `nexus --dump-sexp` (the frontend's tree of the grammar) equals `test/golden/<grammar>.sexp`; every grammar file has one, under the first suite that uses it |
| `determinism/<grammar>` | two generations (with the suite's `flags`), and two runs each of `--dump-sexp`, `--describe` and (with `@highlight`) every `--highlight` target, are identical |
| `messages/<grammar>` | for a grammar with `@messages`: `nexus check --messages` (its coverage report) equals `test/golden/<grammar>.messages.txt` |
| `describe/<grammar>` | `nexus --describe` equals `test/golden/<grammar>.describe.json`; every grammar file has one, under the first suite that uses it |
| `highlight/<grammar>/files` | for a grammar with `@highlight`: `nexus --highlight all` writes exactly its four files, each equal to `--highlight <target>` and to its golden (`test/golden/<grammar>.tmLanguage.json`, `.language-configuration.json`, `.hljs.js`, `.vim`), and the grammar without `@highlight` generates the same parser |
| `highlight/<grammar>/<sample>` | the grammar's TextMate grammar, highlight.js language and Vim syntax file colour `<suite>/highlight/<sample>` as `<sample>.hl` says (`test/lib/highlight`, see "Highlight checks") |
| `editor/<grammar>/files` | for a grammar with `@highlight`: `nexus --editor` (with the suite's lang module) writes exactly its files: the highlighting files equal to `--highlight all`'s, `parser.zig` equal to `--spans` output, `lsp.zig` the server template under its header, the lang module and its imports equal to their sources, and `language.zig` and `package.json` equal to their goldens (`test/golden/<grammar>.language.zig`, `.package.json`; for `editor`, `extension.js`, `identity.json`, `README.md`, `.vscodeignore`, `build.zig`, `main.zig` and `hooks.zig` too); `package.json`'s semantic token types agree with the server's legend (`test/lib/vscode legend`, see "The VS Code client"); a second run keeps an edited `hooks.zig` and `identity.json` (`Kept`) and writes every other file the same |
| `editor/<grammar>/server` | that server type checks (`zig build-exe -fno-emit-bin src/main.zig`) with the stub `hooks.zig` |
| `<grammar>/<dir>/<session>` | the language server built from `<suite>/<dir>/` (its `hooks.zig`, else the stub) answers `<suite>/<dir>/<session>.session` as `<session>.out` says (`test/lib/lsp`, see "Language-server sessions") |
| `<grammar>/client/<scenario>` | the extension `--editor` writes (with `<scenario>.identity.json` as its `identity.json` when there is one, and then `package.json`, `README.md` and `.vscodeignore` equal to `<scenario>.package.json`, `.readme.txt` and `.vscodeignore`), its `extension.js` run under Node against stubs of VS Code as `<suite>/client/<scenario>.js` says, makes the calls `<scenario>.out` lists (`test/lib/vscode client`, see "The VS Code client") |
| `bootstrap` | regenerating the frontend from `nexus.grammar` reproduces `src/frontend/parser.zig` |
| `wasm32/<grammar>` | the grammar's parser and the tree driver build for 32-bit WebAssembly (`zig build-exe -target wasm32-wasi -fno-emit-bin`: type checks and comptime asserts, no code generation) |
| `unit/<grammar>` | `zig test` of each `@lang` module file that has `test` blocks, against the generated parser |
| `unit/nexus` | the generator's own Zig unit tests (`zig build unit`) |
| `tools/diff` | `test/diff` finds no differences between a parser and itself on the MUMPS cases |
| `tools/fmt` | the `zig fmt --check` command of `AGENTS.md` passes |
| `tools/lexfuzz` | `test/lexfuzz/fuzz.py` with a fixed seed: generated lexers agree with its reference matcher (see "Lexer fuzzing") |
| `tools/messages` | every error the generator's source can print is printed by `nexus check` on some grammar under `grammars/` or `test/` (or in a doc) or by the `tools/cli` commands, unless `test/lib/messages.allow` lists it with a reason; an entry for a message a test prints, or one the source does not have, fails |
| `tools/readme` | `docs/index.html` shows README.md's tested `calc.grammar`, and every number in README.md's validated-languages table (lines, LR states, declared conflicts and cells, suite cases, mode) is this checkout's (`test/lib/readme`) |
| `tools/cli` | the command line: `--version`, `--help`, usage errors (exit 2: no grammar, no output file, the grammar as output, an output file for `check`, a missing or unknown `--highlight` target, `--highlight all` without a directory), unreadable and unwritable files, `-` as standard output, `check`, `--spans`, `--dump-sexp`, `--describe`, `--highlight` (one file, `all`, a grammar without `@highlight`), `--editor` and `--lang` (their usage errors, a grammar without `@highlight`, without parser rules, or with `@lang` and no `--lang`, a lang module that cannot be read, imports a file from outside its directory or brings a file the server has, and a lang module copied with its import), each mistake in the extension's `identity.json` (located, nothing written) and one that cannot be read, and the `Expanded:` progress line for an alternative of 32 rules and none for one of 16 (`test/cli/`) |
| `docs/<DOC>/L<line>-<name>` | a complete grammar in a Markdown document (`<DOC>` is its path without `.md` and a leading `docs/`: `GRAMMAR`, `test/README`) generates, compiles, and parses each of its inputs to its tree (or, marked `rejects`, fails with its errors) |
| `docs/<DOC>/L<line>-<name>/zig` | that grammar's `zig test` blocks pass against its parser |
| `docs/<DOC>/L<line>` | a grammar fragment parses (or: a malformed doc example) |
| `docs/<DOC>/L<line>-<name>/highlight/L<n>` | that grammar's editor files colour the ` ```sample ` at line `n` as the ` ```highlight ` after it says |

A compile failure fails every case of that grammar with the first compiler
error as the reason, so "generated but does not compile" can never pass.
A missing golden fails too; `--update` writes it.

## Grammar suites

Each directory `grammars/<grammar>/` (the real languages) and
`test/<grammar>/` (except `golden`, `adverse`, `known`, `regress`, `lib`,
`bench`, `lexfuzz`) is a suite, and one without a grammar fails. Nothing
needs registering: add a directory, a grammar, and cases.

```
grammars/mumps/
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

A case is any file in `cases/` except `*.tree`, `*.args`, `*.md` and
`README*`; its golden is the same name with the extension replaced by
`.tree`, and a `*.args` file of the same name holds extra driver
arguments for it. A
subdirectory `cases/<s>/` uses the start rule `parse<S>` (`expr/` →
`parseExpr`), or `<s>` itself when it starts with `parse`.

The suites under `test/`:

| Suite | Grammar | Corpus |
|---|---|---|
| `basic`, `features`, `lit_tags` | small feature grammars (no `@lang` module) | hand-written |
| `lists` | `X*`, `X+`, `L(X)`, `L(X, sep)`, `L(X?)` without a schema; its `lists.zig` parses 100,000-item lists in a fixed memory budget | hand-written |
| `lexer` | every @lexer-section construct; tokens printed with their `pre` | hand-written |
| `long_tokens` | `@longtokens` with `@schema`, `@trivia`, `@repair`, `@keywords` and a lang Lexer that reads ahead and joins tokens; its `long_tokens.zig` tests tokens of 65,534 bytes to 1 MB built in memory: categories, ends, text, spans, facts, tolerant repairs, `error.TokenEndUnknown`, and (in child processes) the panics of the helpers that have no parser | hand-written, short |
| `semantic` | a schema-mode grammar using every semantic feature; its `semantic.zig` tests the generated API | hand-written |
| `highlight` | Lamp, whose `@highlight` uses every construct and scope: metadata, literals and a caseless `@keywords` group, tokens, captures, every context (around several literals and a top-level alternation too), `line-start`, `line-end`, three regions | `highlight/sample.lamp`, coloured |
| `word_chars` | Mint, a small M-like language whose `@highlight` sets `word-chars [%A-Za-z0-9]` (`_` an operator, `%` part of a name) and puts contexts around `@keywords` groups and a `line-start` alternation | `highlight/sample.mint`, coloured |
| `spans` | the Ruby grammar generated with `--spans` (node spans without a schema) | the Ruby cases |
| `messages` | `@messages` with entries of every kind (`at`, `after`, a choice, a guard on an error token and its unguarded fallback, `name!:`, `{got}`, `{expected}`); its `messages.zig` tests the text of each error, from the strict parse and the tolerant one | hand-written |
| `keywords` | `@keywords` tables: caseless abbreviations, exact words, aliases, a base id, catch-all terminals, quoted words and terminal names; its `keywords.zig` tests the generated lookups | hand-written |
| `editor` | Tally, a small language with `@schema`, `@repair`, `@messages` and `@highlight`, whose language server the suite builds and drives: `full/` with a `hooks.zig` that writes every function but `references`, `stub/` with the stub `--editor` writes | `full/*.session` and `stub/*.session`, replayed on `project/`; `client/*.js`, the VS Code client's scenarios; two parse cases |
| `nexus` | `nexus.grammar` with `src/frontend/lang.zig` (the self-hosted frontend) | hand-written `@parser` sections covering every construct; `highlight/sample.txt`, coloured |

The suites under `grammars/`:

| Suite | Grammar | Corpus |
|---|---|---|
| `rig` | Rig's schema-mode grammar and its `rig.zig`, `diag.zig` (copied from Rig's main; `test.conf` names the commit) | 50 programs from Rig's examples and torture cases (raw tree, `parseTree`); `cases/program/` checks the IR after Rig's `Parser` wrapper |
| `mumps` | em's schema-mode MUMPS grammar and lang module (copied from em) | hand-written cases, 27 VistA routines, 22 MVTS-derived em compliance routines |
| `ruby`, `slash`, `nexis` | downstream grammars without a schema (`nexis`: copied from nexis's main; `test.conf` names the commit) | hand-written Ruby and Slash, a sample of Nexis tests and examples |
| `zig` | Zig 0.17.0: `std.zig.Tokenizer` as Nexus rules and a parser for all of Zig's syntax (lang `Lexer` wrapper for Parse.zig's lookahead and spacing decisions); its `tokens_test.zig` compares the lexer with `std.zig.Tokenizer` on the tokenizer's own test inputs, edge cases and random inputs, `grammars/zig/compare-tokens` does so over any corpus, and `grammars/zig/compare-accept` compares acceptance with `std.zig.Ast.parse` over a corpus, std.zig's parser test sources, or token-edit mutants | hand-written: every token kind and every way a token goes invalid; declarations, containers, statements, expressions, types, `asm`; inputs Ast.parse rejects beyond the PEG; `highlight/sample.zig`, coloured |

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
parses a corpus with both (parallel chunks, safe mode), and compares
trees file by file. Each nexus is a path to a binary or `current`, this
checkout's `bin/nexus` (rebuilt first).

```bash
# A generator change under review: the previous build against this checkout, over VistA
test/diff /tmp/nexus-before/bin/nexus current grammars/mumps/mumps.grammar grammars/mumps/mumps.grammar \
    --ext .m ~/Data/Code/em/misc/vista

# A grammar change under review, after a lang Parser wrapper, over Rig's
# test cases (written out first, in a Rig worktree RIG) and examples
(cd RIG && swarm test/rig.rip tree)
test/diff --start parseProgram current current OLD/rig.grammar NEW/rig.grammar \
    --ext .rig RIG/test RIG/.zig-cache/rig-tests/tree RIG/examples
```

Rig's tests are cases in `test/rig/*.rig.test` (Rig's
`docs/internals/tests.md`), not programs of their own. Rig's runner,
`swarm test/rig.rip tree`, writes each one out as the program it
compiles, under `.zig-cache/rig-tests/tree/behavior/` and `reject/`,
and builds and runs nothing.

Results are grouped as `same`, `same_error` (the same parse error),
`tree_differs`, `error_differs`, `new_fails`, `new_parses`, `new_crashes`,
`old_crashes`, and `expected` (paths listed in `--expect FILE`, for
documented intentional changes). The first `--show N` tree differences are
printed as diffs; `--keep DIR` keeps everything (`old.tsv`, `new.tsv`,
`<category>.tsv`, both builds). A file that crashes a parser is recorded as
a crash and the run continues. `@lang` files default to every `.zig` in the
directory of the grammar's `@lang` module (next to the grammar or in its
`src/`); override with `--lang-old` / `--lang-new`, and the start rule with
`--start`, `--start-old`, `--start-new`. The exit status is 0 when every
file gives the same tree or the same parse error with both parsers (apart
from `--expect`ed files), 1 otherwise, and 2 on a usage or build error.

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
| ` ```sample ` then ` ```highlight ` | the last complete grammar's editor files colour the sample as shown (the `.hl` format of "Highlight checks") |

A `grammar` or `zig` fence without one of these markers fails, and so does
an `input` without its `tree` or a `sample` without its `highlight`, so nothing in a document goes untested by
accident. Other fences (`text`, `bash`, ...) are not checked. The examples
are extracted into `.zig-cache/nexus-test/docs/` and run like any suite.

## Highlight checks

A suite whose grammar has `@highlight` may hold samples in
`<suite>/highlight/` (any file but `*.hl`), each with its expected
colouring in the file of its whole name followed by `.hl`
(`sample.lamp`, `sample.lamp.hl`). `test/lib/highlight` generates the
grammar's TextMate grammar, highlight.js language and Vim syntax file and
colours the sample with each:

- the TextMate grammar by a reference tokenizer that follows
  vscode-textmate (line by line; the earliest match wins, a tie goes to
  the pattern listed first; a begin/end rule is a region whose patterns are
  tried before its end with `applyEndPatternLast`), its regexes run by
  Python's `re`;
- the highlight.js language by a reference that follows highlight.js 11
  (over the whole text, the earliest of the mode's `contains` and its
  `end`, ties to the first listed; a `match` array colours each part), on
  the object the module's default export returns;
- the Vim syntax file by Vim itself (`vim -u NONE -es`), each byte's
  `synID`.

Each character gets the scope of the innermost item covering it, read
back through the scope table of `docs/GRAMMAR.md`, so the files must use
the documented names. The TextMate and Vim colourings must equal the
`.hl` file; highlight.js, whose classes are fewer, must give each
character the documented class of its expected scope. `--update` writes
the `.hl` file from the TextMate colouring (then checks the others
against it). The format: each line of the sample after `> `, then a line
per coloured run with `^` under its characters and the scope:

```text
> fun main(x)
  ^^^ keyword
      ^^^^ function
```

The references stand in for the editors' own engines (Oniguruma in VS
Code, highlight.js's JavaScript): the regexes Nexus writes use only what
Python's `re`, Oniguruma, JavaScript and Vim agree on.

## Language-server sessions

A subdirectory of a suite that holds `*.session` files is a language
server: the suite runs `nexus --editor` on the suite's grammar, puts the
subdirectory's `hooks.zig` in place of the stub when it has one, builds
the server with `zig build`, and replays each session against it with
`test/lib/lsp`, on the files of `<suite>/project/`. A session is one
command a line (`initialize`; `open`, with the file's text or, for an
`untitled:` document or a file not on disk, the `| ` lines after it;
`change` with its new text on `| ` lines; `hover FILE L:C`;
`rename FILE L:C NAME`; ...; `test/lib/lsp` lists them all), and its `.out` is each command after `> `, then what
the server answered or published, ranges as `L:C-L:C` and semantic tokens
as `L:C len scope`. `--update` writes the `.out` file.

## The VS Code client

`test/lib/vscode` checks the extension without VS Code, under Node.
`legend PACKAGE_JSON SERVER_TEMPLATE` (in every `editor/<grammar>/files`)
checks that `package.json`'s semantic token types agree with the legend
in `src/lsp/server_template.zig`: each type of the legend is one of VS
Code's standard types or one `package.json` declares, it declares no
other and no standard one, each `superType` is a standard type, and
`semanticTokenScopes` gives a scope to exactly the legend's types.
`client VSCODE_DIR SCENARIO` loads `extension.js` with stub `vscode` and
`vscode-languageclient/node` modules and runs a scenario, a CommonJS
module of steps (settings at user or workspace level, a trusted or
untrusted workspace, its folders, a bundled server, a start that fails or
waits, activation); it prints each call the extension makes, paths under
`<ext>` (the extension) and `<ws>` (the workspace). The stub gives
settings as VS Code does: a `machine` setting, and in an untrusted
workspace a restricted one, takes no workspace value. A setting the
extension reads that `package.json` does not declare fails the scenario.
`--update` writes the `.out` file.

## Lexer fuzzing

`test/lexfuzz/fuzz.py [--seed N] [--specs N] [--inputs N] [-O MODE]` generates random
lexer specs (random patterns, trailing context, the `skip`, `hold` and
`rewind(n)` actions, `{m++}`/`{m--}`, comparison guards, an `after` block), builds
them all with `bin/nexus` into one driver, lexes random inputs, and compares
every token (cat, pos, len, pre) with a reference computed from the lexer's
definition with its own set-of-positions matcher. A spec the generator
rejects passes only when the model confirms the rejection (a dead rule wins
in no configuration on any text up to one byte past its shortest match,
guards never hold together, held
rules can re-enable each other, ...), and an accepted spec whose held rules
can loop fails. The DFA itself is also checked
against a backtracking matcher by the unit tests (`src/lexgen/automaton.zig`).
`-O` picks the driver's optimize mode (default `debug`, which also checks
the generated lexers' safety). The suite runs a small fixed-seed round in
`debug` as `tools/lexfuzz`; larger seeds and counts are run by hand.

## Benchmarks

`test/bench/run` builds nexus (fast mode by default, `-O` to change,
`--nexus BIN` to time another generator), times generation of every
in-repo grammar, and measures lexing and lexing+parsing throughput on the
full VistA corpus and a synthetic Rig file of about 4 MB (falling back to the
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
| `test/lib/messages`, `test/lib/messages.allow` | the `tools/messages` check, and the messages no test prints |
| `test/lib/readme` | the `tools/readme` check |
| `test/lexfuzz/fuzz.py` | the lexer fuzzer |
| `test/lib/highlight` | the `highlight/*` checks: the TextMate and highlight.js references, the Vim run |
| `test/lib/lsp` | replays a session against a language server |
| `test/golden/` | generated-code (`.zig`), frontend-tree (`.sexp`), description (`.describe.json`) and editor-file goldens |

Builds and scratch output live in `.zig-cache/nexus-test/` (per-suite
builds in `build/<suite>/`, with `gen.log` and `compile.log`), so a failing
case's parser can be run by hand:
`.zig-cache/nexus-test/build/mumps/driver grammars/mumps/cases/hand_dots.m`.
A suite's compile is skipped when its inputs (the generated parser, its
lang files, the driver, the mode and the compiler) are byte for byte those
of its last build. One `test/run` runs per checkout at a time; a second
exits with status 2.
