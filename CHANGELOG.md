# Changelog

## Unreleased

### Changed

- The real-language grammars live in `grammars/` (`grammars/zig`,
  `grammars/rig`, `grammars/mumps`, `grammars/nexis`, `grammars/ruby`,
  `grammars/slash`), apart from the feature suites in `test/`.
  `./test/run` runs both; test ids are unchanged (`rig/...`, `gen/zig`).
  Generated code is unchanged. Migration: Rig, em and nexis re-sync their
  copies into `grammars/<name>/` instead of `test/<name>/`.

## 2.2.0 — 2026-10-10

### Added

- Spreads into fixed roles (schema mode): when element N names a rule
  whose every alternative builds an untagged list of one length k, a
  positional `...N` fills the next k roles of a node and `role:...N`
  fills `role` and the k − 1 after it, so a head shared by several kinds
  (`if`/`while` conditions and captures, a declaration's modifiers) is
  written once, in one rule. Generation checks the length, the roles
  available, and each item's type against its role; an absent optional
  head leaves its roles nil. Additive: both forms were errors before, and
  grammars that do not use them generate the same parsers. No migration.
- Span marks: `-X` on a leading or trailing element of a pattern leaves
  that element out of the span of the node the alternative builds (and of
  the nested nodes of its action), so a
  statement's node can exclude its `;` and the doc comments before it
  (`stmt = -doc:DOC* "var" name:IDENT "=" value:expr -";" → (var)`). The
  element keeps its position and value, and the parent node still spans
  it. Generation rejects a mark inside a group, on a middle element, on an
  alternative that builds no node, or one that leaves the node no element
  that is always there. Applies with `@schema`, and with `--spans` without
  one. Additive: grammars without marks generate the same parsers. No
  migration.

## 2.1.0 — 2026-10-10

### Changed

- Faster generated parsers, with the same trees and the same API.
  Downstream repositories need no edits; regenerate the parsers to get
  the speed.
  - An `@infix` table is generated folded when it parses the same as its
    chain: one rule per operator, decided by precedence in the parse
    table, so an operand no longer reduces once per level. Conflict
    reports and `@conflicts` still name the levels (`infix("+" "-")`).
    Rule and state numbers of such a parser change, and so may the
    expected list of an error inside an expression.
  - A pass-through rule (`A → B`) only replaces the top state, and a run
    of them is climbed in an inner loop; the strict loop keeps the state
    and the token's symbol in locals.
  - Lists with spreads are allocated once at their length; left-recursive
    lists grow without `std.ArrayList`; static lists are unrolled.
  - `X "c"` overrides are marked in the parse table (`xExcludes` entries
    gain the overridden reduction).

## 2.0.0 — 2026-10-03

Changes marked **Breaking** need edits in a grammar or a lang module;
[Migrating](#migrating) lists them per downstream repository.

### Added

- `BaseLexer.makeToken(cat, pre, start, end)` builds a token the way the
  scanner does: a match longer than 65535 bytes is an `err` token 65535
  bytes long, and scanning resumes after the whole match.
- `BaseParser.expectedNames(state, &buf)` gives the reader names of what a
  state expects, each once, in a `[parser.maxExpected][]const u8` buffer.
- `BaseParser.allocator()`, the allocator that holds the trees, for what a
  lang `Parser` wrapper builds. It is a single-threaded bump allocator:
  unlike the arena's own allocator, it is not thread-safe.
- `BaseParser.reset(source)` parses new input in the memory the parser
  holds (the arena keeps its capacity), for loops that parse many inputs.
- `-` as the output file writes the module to standard output.
- Labels inside a top-level `( ... )` or `( ... )?` group fill roles; a
  choice inside a `[...]` group or another choice becomes a rule of its
  own. Both were errors.
- One role may be labeled in different alternatives of a choice (whichever
  matched fills it); an optional choice of literals can fill a tag role
  (`op:("+=" | "-=")?`); labeled tokens in a rest role are one item each
  (`items:IDENT "," items:IDENT`, also through a name that aliases the
  token). All three were errors. A labeled token that can be absent
  there (optional, or in a choice alternative) is an error that says so.
- `@tags` works without `@schema`.
- Rules have no length limit of their own: an alternative has at most
  65534 elements, counting those in its groups and choices at any depth, and
  a grammar at most 65535 symbols, both located errors.

### Changed

Generated API:

- **Breaking: `Tag` is always generated.** Without `@schema` it holds the
  tags the actions produce, in first-seen order, then the `@tags` names;
  it is exhaustive (`_` only when empty). A lang module's `Tag` is not
  read.
- **Breaking: one lexer contract.** Every module has `BaseLexer`, the
  generated scanner, and `Lexer`, the lexer the parser drives (`BaseLexer`
  unless the lang module declares a `Lexer` wrapper). The scanner is
  `BaseLexer.next()`. A lang `Lexer` wrapper holds the generated lexer as
  `base: BaseLexer` (any other field is a compile error, where the parser
  silently lost `aux`) and needs only `init(source)` and `next()`: the
  parser calls nothing else.
- `writeError` names each expected symbol once, so tokens sharing an
  `@display` name are listed once. Locate an error with `lastError()`
  (`span`, `cat`, `state`) rather than the parser's `current` token.
- `NodeInfo`, `SideEntry`, `SideLabel` and `RepairClass` are private.
- A syntax error names the unexpected token by its `@display` name too
  (`unexpected name 'x'`, `unexpected end of line`).

Grammar files:

- **Breaking: `X*`, `X+` and `L(X)` are left-recursive.** A list of n
  items costs O(n) time and memory in the generated parser, where each item
  copied the rest of the list. Trees are unchanged. The `L(X).tail` rules
  are gone, and conflicts that involve a list move to the rule that ends
  it: regenerate and replace the manifest entries `nexus check` reports. A
  list followed by its own separator (`L(X) "," "*"`) needs no declared
  conflict.
- **Breaking: the coverage gate counts presence, repetition and choice.**
  An unused `T?`, `[A B]`, `T*` or choice between fixed texts (`","?`,
  `[","]`, `("+=" | "-=")`) is an error, since leaving it out lets
  different inputs build the same node. Use it, label it, drop it with
  `!X` (an insignificant trailing comma is `![","]`), or opt out with
  `~ "reason"`.
  Coverage errors show groups, choices and lists in source syntax.
- **Breaking: a label that cannot fill a role is an error**, where it was
  ignored: one inside a repeated group or choice (`(A | x:B)*`), or inside
  a group nested in a group or choice. So is a label on a choice with an
  alternative of several elements (`eq:("=" | ":" "=")`), which a
  side-band role dropped for that alternative. Move that part into a named
  rule, or label the elements.
- **Breaking: an unreachable rule is an error** in every run, where `nexus
  check` printed a warning (none with `@as`) and generation emitted the
  dead rule. An `@infix` table no rule uses is an error, and so is a rule
  named `infix` beside one.
- **Breaking: each directive appears once** (`duplicate @x`), except
  `@as`; `@schema`, `@tags`, `@trivia`, `@conflicts`, `@errors`,
  `@display` and `@op` merged repeated blocks. A name given twice in
  `@tags` or `@trivia` is an error.
- **Breaking: every string decodes escapes one way.** Parser literals, list
  separators, `X "c"` hints, `@infix`, `@op`, `@display`, `@errors` and
  `@repair` strings, tag literals, quoted kind names, `tag(...)` values and
  `@tags` names take the escapes of a pattern literal
  (`\n \r \t \0 \\ \' \" \xHH`); any other escape is an error at its
  backslash, where `\c` read as `c` and quoted names kept their
  backslashes. `\xHH` needs two hex digits (`'\x+A'` read as 0x0A).
- **Breaking: a `[...]` whose body can match nothing is an error**
  (`[X?]`, `[X*]`, `[A | B?]`, `[[X]]`), where it surfaced as an undeclared
  conflict, and `[...]` takes no quantifier (`![X]*` silently replaced its
  `?`). `[L(X?)]` remains: it tells an absent list from a list of one empty
  item.
- **Breaking: guard values must fit their variable** (-128..127, `pre`
  0..255), like assigned values, and a rule (or zero-width rule) whose
  guards never hold together is an error: start states are built only for
  the guard configurations values can produce. `{pre = 200}` is allowed
  and `{pre = -1}` rejected.
- **Breaking: a rule that can win only after a leading blank is dead**
  (the scanner skips blanks first), and so reported. A space before a
  quantifier (`'a' +`) says to remove the space.
- **Breaking: a rule a zero-width rule shadows is dead**, and so
  reported: a zero-width rule whose guards hold only where an earlier
  zero-width rule's do (`@ pre > 1` after `@ pre > 0`), and a rule with a
  pattern live only where a zero-width rule fires first.
- **Breaking: an endless reduce chain is a generation error**, including
  an empty reduction alternating with a unit reduction (`d → b`,
  `b → ε`), whose generated parser pushed forever.
- **Breaking: the lexer automata have size limits**: an NFA over 200,000
  states, or subset construction past 4 × 65535 states, is a located
  error, where a pattern whose DFA doubles with each repeat ran out of
  memory (11 GB) without a diagnostic.
- **Breaking: an `X "c"` hint names the terminal its one-byte text stands
  for**, whether the grammar writes that token as the literal `"c"` or by
  name (`LPAREN`, the token the lexer gives exactly `"c"` or `@op` maps it
  to), where only a literal matched; its escapes are decoded. A `"c"` that
  names no token, a token the grammar does not use, text that lexer states
  or guards make two terminals, the `@as` token, another literal's
  terminal, or one terminal named twice on an alternative is a located
  error. Hints group by alternative, so a dead hint beside a used one on
  the same line is reported, and an `X "c"` inside a group is an error.
  Tokens are bound to terminals before the LR stage, so `"(" and LPAREN
  are the same token` is reported before conflicts.
- **Breaking: a capitalized name is a token only if the lexer declares it
  or an `@as` group produces it**: `EXPR` for a rule `expr` is an undefined
  token.
- A lexer action's argument is a number (`rewind(n)`); `word 'c'` is a
  syntax error.
- **Breaking: `after` runs only for tokens the DFA matches that consume
  input** (and `err` bytes), as documented: not after `hold`, `rewind(0)`
  or `( ) / r2` tokens, which reset the variables for the token at their
  own position, nor after zero-width rules. em's `mumps.grammar` has
  `after beg = 0` with held rules; every MUMPS case parses as before.
- A count stored by `counted()` in a state variable saturates at 127 (200
  dots stored -56).
- The zero-width check follows (rule, value) steps: a rule that steps a
  variable toward a false guard is accepted, and a held rule with a pattern
  guarded only by `pre > 0` is accepted.
- A conflict report shows a shortest symbol path to the state, and reports
  of rules that derive no finite input name only the causes. Every LR
  error is located at its alternative's column.
- LR(0) states are numbered breadth-first by first use, independent of
  hashing and the host, so every generated parser's states are
  renumbered: a downstream regeneration shows a large diff in its tables
  (trees are unchanged).
- Manifest entries match rules with `->` in quoted literals and with blank
  runs, and a manifest line may be of any length; a second `over` and a
  count too large for 32 bits are errors.
- Escapes in a tag literal (`op:("\x2b=" | "\n")`) name the decoded text.
- `@code` without `@lang` is reported at the `@code` line.
- An undefined rule or token is reported where it is written.
- Quoted source text in messages is clipped to 60 bytes, a non-ASCII byte
  is shown in hex, and a UTF-8 byte order mark at the start of a grammar
  file is an error naming it.

Command line and build:

- **Breaking: the output file is required**: `nexus g.grammar` without one
  is a usage error (exit 2) where it wrote `src/parser.zig`.
- An output path that names the grammar file (through any spelling or
  link) is a usage error, and nothing is written.
- Output replaces its file atomically: a failed write leaves the previous
  file intact. Through a symlink, the file it names is replaced, and the
  file keeps its mode; other hard links to it keep the old contents. A
  device or pipe (`/dev/null`) is written in place.
- `check` is the command wherever it is the first non-option argument;
  `--dump-sexp` with `check`, `--spans` or `-c` is a usage error; a failed
  write to standard output is an error, not a stack trace (a broken pipe is
  no error).
- `zig build unit` runs the generator's unit tests (the step was
  `test-lowerer`); `zig build test` runs `./test/run`, from any directory.

Tests:

- `./test/run` pins every suite's generated code and every grammar file's
  frontend tree, checks formatting (`tools/fmt`), fuzzes the lexer
  generator (`tools/lexfuzz`, whose rejections its model confirms), checks
  that every generator message is printed by a test (`tools/messages`), and
  checks the README's numbers and the project page's example
  (`tools/readme`). Doc tests cover every tracked Markdown file.
- An adverse test requires exit status 1 and no output file; one suite run
  per checkout (a lock); compiles are skipped when their inputs are
  unchanged; the suite runs with the system's own tools (no GNU
  `timeout`).

### Removed

- **Breaking:** `--slr`. Nexus builds LALR(1) tables only.
- **Breaking:** the `simd_to 'c'` lexer action, which changed nothing (the
  lexer scans `[^c]*` runs with SIMD on its own). Writing it is a syntax
  error.
- **Breaking:** the `@conflicts = N` form, which was parsed only to reject
  it. It is a syntax error.
- **Breaking:** `matchRules` (use `next`), `BaseLexer.reset`, and the
  `text` and `reset` methods of lang `Lexer` wrappers, which nothing called.
- The default output path.

### Fixed

- Start states had transitions on blanks the scanner never feeds them,
  which hid dead rules (`(' ' 'x') | 'x'` after `'x'`).
- An `@lexer` section with tokens and no rules (a lang `Lexer` that scans
  everything) panicked the generator; it generates a lexer that returns
  only `eof` and `err`.
- Printing a tree, a span of a list without a node id, `writeFacts` and
  the test driver recursed per tree level and overflowed the stack on deep
  trees (a long operator chain); every walk uses a heap
  stack.
- The span of a list without a node id ran from its first child's start
  to its last child's end, so it was inverted (start > end) when an action
  put children out of source order (MUMPS `(setmulti value:5 ...2)`); it
  is the least start to the greatest end. `span` panics if its walk runs
  out of memory; `write` and `writeFacts` report that as
  `error.WriteFailed`.
- A grammar-file token longer than 65535 bytes panicked the frontend, and a
  few thousand nested groups overflowed the stack; both are located
  errors (64 levels of nesting).
- Lang lexers that built tokens with `@intCast` panicked on a match over
  65535 bytes (MUMPS indents, Ruby symbols, nexis identifiers and strings,
  Slash heredocs); they use `makeToken`.
- An `@as` keyword whose Id value is 512 or more read past the group's
  symbol map (a panic in safe builds); the maps are sized from the Id
  enum, so any `u16` value works (an Id enum is `enum(u8)` or
  `enum(u16)`).
- An `@as` keyword ordinal matched before a reduction stayed on the token
  when the next state took it as itself.
- `@lang` and the token names of `@op` skipped escape checking
  (`@lang = "l\q"` generated an import Zig cannot read), and an `@op`
  literal written with an escape (`"\x27="`) never matched its literal;
  both are decoded like every string, with located errors.
- A syntax error showed a control byte (a NUL) raw; every byte that is
  not printable ASCII is shown in hex. A repeated directive or section is
  located at its `@`, not at the first name inside it.
- Tolerant repair could choose an insertion that the parse then rejected
  (it simulated the next token without its `X "c"` override) and repeat
  it at the same place until the budget ran out.
- A lexer id (`aux`) set for a token that took an `@as` keyword ordinal,
  or for a token tolerant parsing deleted, became the next token's id.
- A tag named `pass`, a tag literal written with an escape (`op:"\x41"`),
  and a grammar past about 100,000 table entries (a comptime quota)
  generated parsers that did not compile.
- A start symbol named with 255 or more bytes was dropped from `Start`.
- `printError` cut a long expected list at 512 bytes.
- A list extension nested in another (`(...1 (...2 3))`) gave the outer
  list a fresh node id.
- The empty leaf of `~N` was placed at 1:1; it is placed where its element
  starts.
- Tolerant parsing at end of input took O(budget²) time; insertions that
  only nest a construct deeper are bounded.
- A multi-element `[A B]` group inside a group or a choice crashed the
  generator; it is a located error.
- Aliases that form a cycle (`x = y`, `y = x`) are reported as an alias
  cycle, not as an undefined rule.
- An `@infix` base that aliases a token used nowhere else gave a false
  "undefined rule".
- The coverage gate judged a name defined in two blocks as an alias of its
  last block's token; it is a rule, as for expansion.
- A declared kind built only inside an undeclared kind was reported as
  unbuilt and left out of the paste-ready `@schema` block.
- Two labels on one slot role report "labeled twice", not "filled by the
  label and by the action".
- Without a schema, a nested node after an absent optional element was cut
  with the trailing nils: `"a" [b] → (p 1 2 (q 1))` gave `(p a)` for `a`;
  it gives `(p a _ (q a))`.

### Performance

Apple M5, ReleaseFast, against 1.1.0 ([test/bench/BASELINE.md](test/bench/BASELINE.md)):
generating the MUMPS parser takes 4.8 ms instead of about 16.5 ms, and the
generated parsers parse VistA at 65 MB/s instead of 51 MB/s and Rig at
67 MB/s instead of 58 MB/s (one 4 MB file of the test programs of 1.1.0's
Rig grammar).

- Generation: lowering indexes line starts (it was quadratic in file size:
  a 249 KB grammar 2.7 → 0.1 s); the LR(0) builder
  uses dense buckets and the grammar facts are computed once (11% fewer
  instructions on MUMPS); the lexer DFA is minimized with Hopcroft's
  algorithm (a chain-shaped DFA of 5102 states 9.4 s and 1.3 GB → 0.14 s
  and 13 MB).
- Generated parsers: lists are linear (a 40,000-line MUMPS routine 2.5 to
  3.2 s and 5 to 13 GB → 0.01 s and 26 MB); pass-through rules skip
  `executeAction`; static action lists are read-only data; parse memory
  comes from a bump allocator; an `@as` keyword is looked up once per
  token; only tokens that can grow long test their length (19% fewer
  instructions per token when lexing VistA). Parsing all of VistA (86.5 MB)
  takes 1.32 s instead of 1.71 s, Rig 57 ms instead of 65 ms.
- The parse table is an array literal: the MUMPS parser compiles in 0.25 s
  instead of 0.61 s (Debug, semantic analysis).

### Migrating

Regenerate every parser. Then, in each lang module:

- **Tag**: delete a hand-written `Tag` enum. A tag the generated enum
  lacks is one no action builds: list it in `@tags` if the lang code
  needs it. Code elsewhere that names the lang module's `Tag` uses
  `pub const Tag = parser.Tag;`.
- **Lexer wrapper**: delete its `text` and `reset` (nothing calls them),
  rename `base.matchRules()` to `base.next()`, and read a token's text
  with `base.text(tok)`.
- **Hand-built tokens**: build a token whose length is computed with
  `parser.BaseLexer.makeToken(cat, pre, start, end)`, not
  `.len = @intCast(end - start)`.
- **Errors**: take the failing token from `lastError()` (`span`, `cat`,
  `state`) instead of `current`, and the expected names from
  `BaseParser.expectedNames(state, &buf)` with
  `var buf: [parser.maxExpected][]const u8`.
- **Parser wrapper**: allocate with `self.base.allocator()`, not
  `self.base.arena.allocator()` (from one thread: it is not thread-safe).
- **Build**: pass the output file (`nexus g.grammar src/parser.zig`).

Per repository:

- **rig** (`src/rig.zig`): delete `Lexer.text`; `matchRules()` → `next()`
  (21 sites); the identifier probe's `.len = @intCast(end - pos)` →
  `makeToken`; `diagnostic` and the bracket probes read `lastError()`
  instead of `base.current`; `expectedHint` loops over `expectedNames`
  and drops its dedupe; `allocator()` returns `self.base.allocator()`.
  `pub const Tag = parser.Tag;` stays (rig's code names it). In
  `rig.grammar`, the five trailing commas `[","]` (`params`, `tparams`,
  `tatom`, `patatom`, `bars`) become `![","]`.
- **em** (`mumps.grammar`, `src/mumps.zig`): in `@conflicts`,
  `shift L(expr).tail → ε 2` becomes `shift viewarg → expr ":" L(expr) 1`,
  and `shift IDENT* → ε 2` becomes `shift patatom → repcount IDENT+ 1`.
  Delete `Lexer.text` and `Lexer.reset`; `frontend.zig`'s `writeExpected`
  can take its names from `expectedNames`.
- **nexis** (`src/nexis.zig`): replace the `Tag` enum with
  `pub const Tag = parser.Tag;` (`reader.zig` names `nexis.Tag`); delete
  `Lexer.text` and `Lexer.reset`; `loader.zig` (and two parse-error tests
  in `reader.zig`) locate a parse error with `lastError().?.span`, not
  `current`. Its scanner keeps its own long-token encoding through
  `aux` (`srcLen`).
- **slash, nanoruby** check in Nexus 0.10.3 parsers. Porting one of
  them from 0.10.3 starts from this repository's port of its grammar
  and lang module (`test/slash`, `test/ruby`), the reference
  that carries every change below; each item says what changed in that
  port since 1.1.0.
- **slash** (`test/slash`): delete `Tag`, `Lexer.text` and `Lexer.reset`;
  the heredoc, string-definition and UTF-8 identifier and variable tokens
  use `makeToken`.
- **nanoruby** (`test/ruby`): delete `Tag`, `Lexer.text` and
  `Lexer.reset`; `matchRules()` → `next()` (4 sites); symbols, `%w`/`%i`
  arrays, number extension and string segments use `makeToken`.

## 1.1.0 — 2026-10-02

### Changed

- **Zig 0.17.** Nexus builds with Zig 0.17, and the parsers it generates are
  Zig 0.17 code: `@backingInt` and `@fromBackingInt`, `std.ArrayList`,
  `last()`, `@splat` table initializers, struct-of-arrays `@typeInfo`, and a
  non-exhaustive `Role` enum when a grammar has no roles. Regenerate parsers
  with Zig 0.17.
- String literals in generated code keep UTF-8 text as written.
- The generation summary reports the lexer's DFA states:
  `Lexer: 65 tokens, 25 rules, 32 DFA states`.

### Removed

- The `legacy` generator (Nexus 0.10.3) in `test/run`, `test/diff` and
  `test/bench/run`, and `docs/PORTING.md` (it remains at tag `v1.0.0`).

### Performance

Apple M5, ReleaseFast: generated parsers parse VistA 2% and Rig 4% faster;
generating a large grammar's parser takes about 1 ms longer.

## 1.0.0 — 2026-09-23

Nexus 1.0 keeps what 0.10 did (one grammar file, one Zig module, a combined
lexer and LR parser, S-expression actions next to the rules) and rebuilds
everything underneath it. Porting a 0.10 grammar takes a few edits and keeps
its trees: see [docs/PORTING.md](https://github.com/shreeve/nexus/blob/v1.0.0/docs/PORTING.md).

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
