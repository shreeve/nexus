# Nexus internals

How Nexus turns a grammar file into a parser module, for people changing
Nexus. [GRAMMAR.md](GRAMMAR.md) and [SEMANTICS.md](SEMANTICS.md) describe
what the pieces do for a grammar author; this document describes how.

## The pipeline

```text
grammar file
  │  frontend/     parser.zig (generated from nexus.grammar) + lang.zig
  ▼                → the S-expression tree of the file
  │  frontend/lower.zig
  ▼                → LexerSpec + GrammarIR          (strict: shapes and meaning)
  ├─ lexgen/       regex AST → NFA → DFA → minimized DFA → direct-coded Zig
  │  semantics.zig resolve: schema, inventory, role placement, coverage
  │  expand.zig    → Grammar (plain BNF: symbols, rules, action trees)
  │  semantics.zig checkTypes: static result types
  │  check.zig     every symbol defined
  │  lr/           LR(0) → lookaheads → table → conflicts, expected sets, repair
  ▼  codegen/      generated sections + runtime template
parser module
```

`src/main.zig` runs the stages in this order and stops at the first stage
that reports an error. Every stage reports `file:line:col: error:` itself
and returns an error; nothing continues past a failed stage, and nothing
is written.

### Frontend

A grammar file is parsed by the parser Nexus generates from
[`nexus.grammar`](../nexus.grammar), which is itself a schema-mode grammar:
its `@schema` block is the contract between the frontend and the lowerer.
`src/frontend/lang.zig` is its lang module. Its `Lexer` wrapper owns
everything that depends on layout or context, turning the generated
`BaseLexer`'s tokens into the stream `nexus.grammar` parses:

- line breaks become `newline`, `cont` (an indented continuation) or
  `next_alt` (a line starting with `|`); inside `[ ... ]` they are blanks;
- words are classified: `name:` is a label, capitalized words are tokens,
  `X "c"` and `L(` are keywords, directive keywords after `@`;
- after an arrow, the rest of the line is scanned in action mode;
- the @lexer section is scanned line by line: a pattern is taken verbatim
  up to an unquoted `@`, arrow or `#` (`src/lexgen/regex.zig` parses it
  later), the rest of the line into tokens;
- `@conflicts` entry lines are split into kind, rule text, `over`, count,
  and the rationale comment.

`src/frontend/frontend.zig` reports a syntax error with the expected set of
the failing state (the generated `BaseParser.expected`), or the scanner's
own message for a malformed pattern or literal. `nexus --dump-sexp` prints
the tree; `test/golden/*.sexp` pins it for every in-repo grammar.

### Lowering

`src/frontend/lower.zig` walks the tree and builds the lexer spec
(`LexerSpec`: state variables, tokens, rules with guards and actions) and
the grammar IR (`GrammarIR`: rules, alternatives, elements, action trees,
directives). It accepts exactly the shapes the schema declares, every list
at full width, and reports anything else as `error.ShapeError` at a source
position; meaning errors that a well-formed tree can still express (a
position 0, an unknown associativity, a `shift` entry with `over`) are
`error.LowerError`. Its unit tests feed it hand-built malformed trees.

### Lexer generation

`src/lexgen/regex.zig` parses each pattern into an AST (literals, classes,
groups, alternation, repetition, bounded repetition, trailing context),
with a located error for anything outside the pattern language.
`src/lexgen/automaton.zig` partitions the 256 bytes into classes no pattern
tells apart, builds a Thompson NFA per rule, subset-constructs one DFA with
a start state per guard configuration (at most 10 distinct guard
conditions, so at most 1024 configurations), and minimizes it by Moore
partition refinement, renumbering states canonically. A DFA state accepts
for the lowest-numbered rule among its NFA accept states, which gives
longest match with ties to the earlier rule.

`src/lexgen/lexgen.zig` checks each rule (zero-width rules must make
progress: their actions falsify a guard, and no cycle of them re-enables
itself; `hold`, `rewind`, trailing context and `counted()` combine only
in sound ways; every rule must win somewhere, else it names the rule that
shadows it and an example text) and emits the scanner as a labeled
`switch` with one prong per DFA state, jumping with `continue`. Fast paths
are derived from the automaton, not from token names: a self-loop becomes a
tight loop (a range test, a comptime byte table, or a SIMD scan when the
loop excludes at most three bytes), and transitions into states that
cannot continue return the token in place. The DFA is checked against a
backtracking reference matcher by unit tests, and `test/lexfuzz/fuzz.py`
compares random lexers with Python's `re`.

### Semantics, before expansion

With `@schema`, `semantics.resolve` checks the schema (role types name
declared kinds) and the tag inventory, places every action's items into
their slots in schema order (positional items, `role:` items, pattern
labels; nil for the unfilled; rest children last), records side-band
labels, and runs the coverage gate. It works on the source alternatives, so
every message names the rule as written. Positions it produces may be
"internal" positions of elements inside choice alternatives, which only the
expander resolves.

### Expansion

`src/expand.zig` produces the plain BNF grammar the LR stages consume:

- aliases (`name = TOKEN`) are recorded and substituted, never reduced;
- `[...]` groups, `[X]` on a rule name or list, and choices are expanded
  into one alternative per combination; `Layout` maps every action position
  to its element in each variant (or to absent), so actions keep their
  positions. Without a schema, an expanded action is cut before a trailing
  absent position;
- `X?`, `X*`, `X+`, `L(X)`, `L(X?)`, `L(X, sep)`, `( ... )` groups and
  repeated choices become shared synthesized rules named in source syntax
  (`L(X).tail`, `(A | B)`), which is how reports and manifests name them;
- `@infix` becomes one rule per precedence level (`infix("+" "-")`) with
  left, right or no associativity built into the recursion;
- each start symbol `x` gets a marker terminal `x!` and an accept rule
  `$accept_x → x! x $end`; `parseX` pushes the marker first, which selects
  the start symbol without adding conflicts.

`semantics.checkTypes` then computes, by fixpoint over the expanded rules,
the set of values each symbol can produce (nil, leaf, tag, untagged list,
one bit per kind) and the values its lists can hold, and checks every role
of every node construction against its declared type, naming a production
that yields the offending value.

### LR

`src/lr/` builds the LR(0) automaton (one initial state per start symbol),
rejects rules that derive no finite input, and computes lookaheads:

- nullable and FIRST sets as bit sets (`bitset.zig`: one allocation per
  family of equal-width sets);
- SLR(1): FOLLOW sets (`--slr`);
- LALR(1) (the default): DeRemer and Pennello's relations over the
  nonterminal transitions (direct reads, *reads*, *includes*, *lookback*),
  with both unions computed by the digraph algorithm, collapsing strongly
  connected components. A unit test checks the result against merged
  canonical LR(1) on random grammars.

`table.zig` resolves each (state, terminal) cell once from the shift and
the reductions that want it: `<` and `X "c"` let a reduction win (an
`X "c"` win also records a run-time override that shifts that terminal when
it touches the previous token), `>` suppresses the report, a shift otherwise
wins, and among reductions the lowest-numbered rule wins. The tables stay
dense (`[state][symbol]`); a row-displacement form was measured and made
the MUMPS parser 256 KB smaller but 5-10% slower.

`conflicts.zig` aggregates the unresolved cells into manifest entries
(`shift rule` / `reduce winner over loser`, with cell counts), compares them
with `@conflicts` (rule texts normalized: `->` is `→`, `ε` for an empty
right-hand side), and on any drift prints each new conflict with its state,
items, and a shortest symbol path from a start state (breadth-first over
the automaton), then the whole actual manifest. It also fails `X "c"` hints
that decide nothing. `expected.zig` computes each state's expected list
(the `@errors`-named rules it waits for, then the terminals none of them
starts), and `repair.zig` ranks the `@repair` insertion candidates per
state by class and by the minimum number of further tokens the item needs.

### Code generation

`src/codegen/codegen.zig` writes the module in sections: header, the lexer
declarations from lexgen, `Tag`/`Role`/`Start`, the runtime, the
grammar-specific tables and functions, and the `Parser` alias with the
top-level `parseX` helpers. `src/codegen/actions.zig` compiles each rule's
action tree into the Zig expression `executeAction` returns for it, using
dedicated builders for common shapes (`(tag ...N)`, `(tag N ...M)`), and
extending a left-recursive list in place when the action is `(...N x)`
(amortized O(1) per element). It also decides, per rule, whether an
untagged list can reach the tree (and needs a node id) or is only ever
spliced (plumbing, no id).

The runtime is `src/codegen/runtime_template.zig`, a real Zig file that
compiles and has its own tests against a small hand-written fixture.
`runtime.zig` extracts its `// @section NAME ... // @end` blocks and fills
`// @slot NAME` lines; everything outside the sections (the fixture, the
tests) is never emitted. The template refers to a fixed set of generated
names (`getAction`, `executeAction`, `tokenToSymbol`, `slotOf`, ...), listed
at its top.

At run time the parser keeps the state stack, the value stack, and with a
node store the start of each stack entry (and its end, when side-band
labels or nested nodes need element extents). A reduction's span runs from
its first element's start to the end of the last token shifted. Node store
entries (span and rule, 12 bytes) live in chunks of 128 that never move.

## Self-hosting and the bootstrap

`src/frontend/parser.zig` is generated from `nexus.grammar` by Nexus
itself, so the frontend is always the product of the current generator.
The `bootstrap` test regenerates it and requires the checked-in file to be
a fixed point. To change the grammar-file syntax:

```bash
$EDITOR nexus.grammar                         # and lang.zig / lower.zig as needed
./bin/nexus nexus.grammar src/frontend/parser.zig
zig build                                     # the new frontend
./bin/nexus nexus.grammar src/frontend/parser.zig   # again: must not change
./test/run --update sexp                      # review the golden diffs
./test/run
```

A change the old frontend cannot parse goes in two steps: first teach the
generator (lowering, codegen) with the old syntax still accepted,
regenerate, then use the new syntax.

## Invariants

These hold on every commit; the suite checks each one.

- **Deterministic output.** The same grammar gives the same bytes on every
  run (`determinism/*`); generated code is pinned by `test/golden/*.zig`.
- **The bootstrap converges** (`bootstrap`).
- **Nothing silent.** A grammar mistake is a located error with a non-zero
  exit (`adverse/*`); nothing is skipped, simplified or defaulted without
  saying so. A gap found is a failing test in `test/known/` until fixed.
- **Strict lowering.** The lowerer accepts exactly the schema's shapes.
- **Language-agnostic engine.** No language-specific code in `src/` outside
  the frontend (which is Nexus's own language). Token names carry no
  behavior; behavior comes from patterns and directives.
- **Every generated parser compiles and runs.** Every grammar in the suite
  is generated, compiled with its lang module, and run over its cases.
- **LALR is LALR.** The lookaheads equal merged canonical LR(1)
  (`unit/nexus`).
- **Docs are tested.** Every example in the docs runs (`docs/*`).

## Performance

Measured with `test/bench/run` and recorded in
[test/bench/BASELINE.md](../test/bench/BASELINE.md) (Apple M5, ReleaseFast):

| | 0.10.3 | 1.0.0 |
|---|---:|---:|
| generate MUMPS (909 lines, 831 states), ms | 29.1 | 17.2 |
| lex VistA (86.5 MB), MB/s | 331 | 348 |
| parse VistA, MB/s | 36.3 | 49.6 |
| lex Rig (3.8 MB), MB/s | 341 | 354 |
| parse Rig, MB/s | 52.2 | 60.9 |

The node store (`@schema` or `--spans`) costs about 5% of parse time on
MUMPS and 3% on Rig. LALR lookahead computation went from 24 ms to 0.3 ms
on MUMPS with DeRemer-Pennello.

## Tests

`./test/run` (see [test/README.md](../test/README.md)) is the whole suite:

| Check | What it proves |
|---|---|
| grammar suites (`test/<name>/`) | the grammar generates, compiles with its lang module, and parses every case to its golden tree |
| `gen/*`, `sexp/*`, `determinism/*` | byte-exact generated code and frontend trees, identical across runs |
| `adverse/*` | a bad grammar fails with its expected located message |
| `known/*`, `regress/*` | open bugs (must still fail) and fixed ones (must pass) |
| `unit/nexus` | the generator's Zig unit tests: lowering, regex and automata, LR core, semantics, runtime template |
| `unit/<grammar>` | the `test` blocks of a grammar's lang module, against its parser |
| `bootstrap`, `tools/diff`, `tools/cli` | the fixed point, the differential tool, the command line |
| `docs/*` | every example in the Markdown docs |

`test/diff` compares two (Nexus, grammar) pairs over a corpus; `test/bench/run`
measures; `test/lexfuzz/fuzz.py` fuzzes the lexer generator.

## Source map

| Path | Role |
|---|---|
| `src/main.zig` | the command line and the pipeline |
| `src/diag.zig` | the diagnostic format |
| `src/grammar.zig` | shared data: lexer spec, grammar IR, the desugared grammar |
| `src/frontend/parser.zig` | the frontend parser, generated from `nexus.grammar` (never edit) |
| `src/frontend/lang.zig` | its lang module: layout, word classes, @lexer line scanning |
| `src/frontend/frontend.zig` | parse entry, syntax errors, `--dump-sexp` |
| `src/frontend/lower.zig` | strict lowering to LexerSpec and GrammarIR |
| `src/lexgen/regex.zig` | the pattern language |
| `src/lexgen/automaton.zig` | byte classes, NFA, DFA, minimization, reference matcher |
| `src/lexgen/lexgen.zig` | lexer checks and direct-coded emission |
| `src/semantics.zig` | schema, placement, coverage, static types |
| `src/expand.zig` | desugaring to BNF |
| `src/check.zig` | undefined symbols, the `check` lint |
| `src/lr/` | automaton, lookaheads, table, conflicts, expected sets, repair |
| `src/codegen/codegen.zig` | module composition and grammar-specific code |
| `src/codegen/actions.zig` | action trees to Zig |
| `src/codegen/runtime_template.zig`, `runtime.zig` | the runtime and its section extraction |
| `nexus.grammar` | the grammar-file grammar |
| `test/` | the suite ([test/README.md](../test/README.md)) |
| `docs/zig-0.16/` | Zig 0.16 notes for contributors |
