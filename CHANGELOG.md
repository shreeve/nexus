# Changelog

## 1.0.0 — 2026-09-23

Nexus 1.0 keeps what 0.10 did (one grammar file, one Zig module, a combined
lexer and LR parser, S-expression actions next to the rules) and rebuilds
everything underneath it. Porting a 0.10 grammar takes a few edits and keeps
its trees: see [docs/PORTING.md](docs/PORTING.md).

### Added

- **The semantic layer** (`@schema`): node kinds with named, typed roles;
  role-named actions (`→ (set target:1 value:3)`), pattern labels
  (`target:name "=" value:expr → (set)`), choices with labels, nested
  nodes, side-band roles; generation checks the tag inventory (and prints
  it, ready to paste), role filling, coverage of every value-bearing
  element (`!X`, `_:X`, `~ "reason"` to drop or opt out), and static result
  types by fixpoint. Nodes have fixed width. The module gets `Tag` and
  `Role` enums, `ir.get`/`ir.rest`/`ir.has`, compile-time `ir.slot`/
  `ir.width`, and per-kind views (`ir.Set.target`). See
  [docs/SEMANTICS.md](docs/SEMANTICS.md).
- **Spans and node ids**: every tree list carries a node id; `span()`,
  `ruleOf()`, `sideRole()`, `newNode()`, `writeFacts()`. On with `@schema`,
  or `--spans` for any grammar.
- **A lexer generator**: patterns compile through an NFA to one minimized
  DFA with a start state per guard configuration, emitted as direct-coded
  Zig with fast paths derived from the automaton (tight loops, byte tables,
  SIMD scans). New: trailing context `r1 / r2`, `hold`, `rewind(n)`,
  bounded repetition `r{n,m}`, class shorthands.
- **The conflict manifest**: `@conflicts` lists each remaining conflict with
  its cell count and a reason; any drift fails generation and prints the
  conflict's state, items and an example input, and the new manifest.
- **Diagnostics for generated parsers**: `writeError` gives `line:col:
  expected A or B, got C` from per-state expected sets, named by
  `@display` (tokens) and `@errors` (rules).
- `@trivia` (tokens kept aside with positions), `@repair` and
  `parseTolerant` (editor parsing with a generated repair table), `@tags`,
  `@as TOKEN via fn` and `[group via fn]`, `x! = x` to declare a start symbol.
- LALR(1) lookaheads by DeRemer and Pennello (the same tables, computed
  about 80 times faster on MUMPS).
- `nexus --version`, a consistent `--help`, usage errors with exit
  status 2; `nexus check` runs every check generation runs.
- Tested documentation: every grammar and Zig example in the docs is
  generated, compiled and run by `./test/run`.

### Changed (breaking)

- `@conflicts = N` is replaced by the `@conflicts` block.
- Lexer patterns are a real regular-expression language: anything outside
  it is an error, token names carry no behavior, `.` matches newline,
  shadowed rules and patterns starting with a blank are errors,
  `counting()`/`matching()` are rejected.
- `Sexp.list` is a `List` (`items()`, `id`) instead of a slice; `Sexp`
  stays 24 bytes and gains `kind()`, `isKind()`, `items()`, `listOf()`.
- `(tag ...N M)` keeps the written order.
- `@code LOCATION { ... }` blocks are gone (`@code = fn` remains).
- Every generation error is `file:line:col: error:` with exit status 1 and
  no output written.

### Fixed

- A start symbol with several alternatives parses all of them.
- Grammars without `@lang` generate parsers that compile.
- Action positions of any size.
- `X "c"` records every hinted character; a hint that decides nothing is an
  error.
- `>` applies to every expansion of an `[opt]` group.
- Lists with different separators are different lists.
- Conflict reports never mention start markers; list-separator conflicts
  are reported.
- Nothing dead is accepted silently: a literal no lexer rule produces, a
  token written both as a literal and by name, `...N` of a token, and an
  `@as` keyword no group's `Id` enum names are errors (the last one a
  compile error naming it). This exposed Ruby's default arguments and
  `**` splats (now parsed) and MUMPS's `"!!"` operator (removed).
- A grammar without a `name!` rule starts at its first rule.
- Every schema shape and `--spans` parser compiles, `writeFacts` included;
  more than 255 collected tags get a wider `Tag` enum.
- Without an action, an absent optional element is nil in the alternative's
  list however it is written (`[r]`, `r?`, `["x"]` dropped it before).
- `@repair` errors and accessor-name clashes are located; `@repair` may
  name a token by its literal.
- Generated parsers never hang or crash on their input: a cyclic grammar
  (a rule that derives itself) and zero-width lexer rules that could fire
  forever are generation errors; a match longer than 65535 bytes is an
  `err` token; an `X "c"` hint applies to the hinted token only (not to
  every token starting with `c`, nor to a token the tolerant parser
  inserts).
- Size limits (255 tokens, 32766 rules, 32767 states) are located errors
  instead of overflows.
- Spans nest: an empty node at the end of its parent lies inside it.
- `b:["+"]` labels the literal; `(!N ...M)` keeps its nil head when N is
  absent; a `( ... )` group with skipped elements keeps nil elements.

### Performance

Apple M5, ReleaseFast ([test/bench/BASELINE.md](test/bench/BASELINE.md)):
MUMPS generation 29 → 17 ms; VistA (86.5 MB) lexing 331 → 348 MB/s and
parsing 36 → 50 MB/s; Rig parsing 52 → 61 MB/s. The node store costs about
5% (MUMPS) and 3% (Rig) of parse time.

## 0.10.3

The last release of the 0.10 grammar format (tag `v0.10.3`).
