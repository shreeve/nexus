# Nexus internals

How Nexus turns a grammar file into a parser module, for people changing
Nexus. [GRAMMAR.md](GRAMMAR.md) and [SEMANTICS.md](SEMANTICS.md) describe
what the pieces do for a grammar author; this document describes how. The
rules every change follows are in [AGENTS.md](../AGENTS.md); the suite is
described in [test/README.md](../test/README.md).

## The pipeline

```text
grammar file
  │  frontend/     parser.zig (generated from nexus.grammar) + lang.zig
  ▼                → the S-expression tree of the file
  │  frontend/lower.zig
  ▼                → LexerSpec + GrammarIR          (meaning checks)
  ├─ lexgen/       regex AST → NFA → DFA → minimized DFA → direct-coded Zig
  │  semantics.zig resolve: schema, inventory, role placement, coverage
  │  expand.zig    → Grammar (plain BNF: symbols, rules, action trees)
  │  semantics.zig checkTypes: static result types
  │  check.zig     every symbol defined, every rule reachable, tokens bound, X hints resolved
  │  lr/           grammar facts → LR(0) → lookaheads → table → checks
  ▼  codegen/      generated sections + runtime template
parser module
```

`src/main.zig` runs the stages in this order. Every stage reports its own
errors as `file:line:col: error:` and returns an error; the run stops at
the first stage that failed, and nothing is written. Everything a run
allocates lives in the process arena, freed at exit. Output goes through a
temporary file that replaces the output file only when complete.

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
  and the rationale comment;
- a token longer than 65535 bytes, or `(` and `[` nested more than 64
  deep, is an `err` token with a message. This one cap bounds the depth of
  every tree the later stages recurse through.

`src/frontend/frontend.zig` reports a syntax error with the names the
failing state expects (`BaseParser.expectedNames`), or the scanner's own
message for a malformed pattern or literal. `nexus --dump-sexp` prints the
tree; `test/golden/*.sexp` pins it for every grammar file in the suite.

### Lowering

`src/frontend/lower.zig` builds the lexer spec (`LexerSpec`: state
variables, tokens, rules with guards and actions) and the grammar IR
(`GrammarIR`: rules, alternatives, elements, action trees, directives). It
reads the tree through the generated `parser.ir` accessors: generating the
frontend proves every node's slots and their types, so the lowerer
re-checks no shapes, and a schema change is a compile error here. It
checks meaning: what a well-formed tree can still get wrong (a position 0,
an unknown associativity, a value outside its variable's range, an unknown
escape, a directive given twice, `@code` without `@lang`, a `[...]` whose
body can match nothing, more than 65534 positions in an alternative), each
reported at its source position as `error.LowerError`.

### Lexer generation

`src/lexgen/regex.zig` parses each pattern into an AST (literals, classes,
groups, alternation, repetition, bounded repetition, trailing context),
with a located error for anything outside the pattern language.
`src/lexgen/automaton.zig` partitions the 256 bytes into classes no pattern
tells apart, builds a Thompson NFA per rule (at most 200,000 states), and
subset-constructs one DFA with a start state per guard configuration that
values can produce (each variable is tried over its range; at most 10
distinct guard conditions). Start states have no transitions on spaces and
tabs, which the scanner skips first. Construction stops at 4 × 65535 raw
states, so an exploding DFA is an error, not exhausted memory. Hopcroft's
algorithm minimizes the DFA, and states are renumbered breadth-first, so
the numbering depends only on the coarsest partition. A DFA state accepts
for the lowest-numbered rule among its NFA accept states, which gives
longest match with ties to the earlier rule.

`src/lexgen/lexgen.zig` checks the rules and emits the scanner:

- every rule must win somewhere, else the error names the rule that
  shadows it and an example text; a rule whose guards never hold together
  is dead too;
- tokens that consume nothing must not fire forever at one position: for
  each guarded variable the check follows the steps (rule, value) →
  (rule, value) through guards and actions, keeps the rules on a cycle
  (Tarjan) in every variable, and reports whatever survives;
- `hold`, `rewind`, trailing context and `counted()` combine only in
  sound ways.

The scanner is a labeled `switch` with one prong per DFA state, jumping
with `continue`. Fast paths are derived from the automaton, not from token
names: a self-loop becomes a tight loop (a range test, a comptime byte
table, or a SIMD scan when the loop excludes at most three bytes), and
transitions into states that cannot continue return the token in place.
Only a token that ends in a state some DFA cycle reaches can exceed 65535
bytes, so only those finishes test the length. The DFA is checked against
a backtracking reference matcher by unit tests, and `test/lexfuzz/fuzz.py`
checks random lexers against a model of the lexer's definition.

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

- aliases (`name = TOKEN`) are recorded and substituted, never reduced; a
  cycle of aliases is an error;
- `inlineForm` decides, once for every consumer, which elements are
  written inline: a top-level `[A B]` group, `[X]` on a rule or list, a
  non-repeated choice, and a non-repeated group with labels inside.
  `checkPatterns` walks every pattern before semantics or expansion and
  rejects what has no position (labels deeper down, a nested `[A B]`) and
  nesting beyond 64 levels;
- inline elements expand into one alternative per combination; `Layout`
  maps every action position to its element in each variant (or to
  absent), so actions keep their positions. Without a schema, an expanded
  action is cut after its last present position or nested node;
- `X?`, `X*`, `X+`, `L(X)`, `L(X?)`, `L(X, sep)`, other groups and choices
  become shared synthesized rules named in source syntax (`L(X)`,
  `(A | B)`), which is how reports and manifests name them. Lists are
  left-recursive (`X* → ε | X* X → (...1 2)`), so code generation extends
  them in place and the parse stack stays flat; their actions keep nils,
  one item per element;
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

`check.zig` runs on the expanded grammar too: every nonterminal has a rule
and every capitalized terminal a lexer token or an `@as` group (an
undefined name is located where it is written), and every rule is
reachable from a start symbol, where `@infix` and the synthesized rules
are real edges. An `@infix` table no rule uses is an error there as well.
It then binds each lexer token to the terminal it reaches the parser as
(`bindTokens`: a named terminal is the token of its name, unless `@as`
promotes it; a literal is its `@op` token, else the token of the lexer
rule whose pattern is exactly that text; one token, one terminal), the
table codegen emits as `tokenToSymbol`, and resolves each `X "c"` hint
to a terminal through it (`resolveHints`), so the LR stage receives
terminal ids and never sees the lexer.

### LR

`src/lr/lr.zig` first computes the grammar facts once: insert costs (the
fewest terminals each symbol derives, by Knuth's cheapest-first
algorithm), nullable as cost 0, and FIRST as a union over the left-corner
relation by the digraph algorithm, as bit sets (`bitset.zig`: one
allocation per family of equal-width sets). It rejects rules that derive
no finite input (reporting only the causes, the bottom strongly connected
components of the unproductive rules), cyclic grammars (A ⇒+ A through
rules whose other elements are nullable), and bad `@repair` names. It then
builds the LR(0) automaton (`automaton.zig`: one initial state per start
symbol; a state's advanced items go into per-symbol buckets in the order
the items first name each symbol, and states are numbered breadth-first as
transitions first reach them, so numbering depends only on the grammar)
and computes LALR(1) lookaheads (`lookahead.zig`): DeRemer and Pennello's
relations over the nonterminal transitions (direct reads, *reads*,
*includes*, *lookback*), both unions by the digraph algorithm, collapsing
strongly connected components. A unit test checks the result against
merged canonical LR(1) on random grammars.

`table.zig` resolves each (state, terminal) cell once from the shift (or
accept) and the reductions that want it: `<` and an `X "c"` hint naming
this terminal (resolved before LR) let a reduction win (an `X "c"` win also
records a run-time override that shifts that terminal when it touches the
previous token), `>` suppresses the report, a shift or accept otherwise
wins, and among reductions the lowest-numbered rule wins. The tables stay
dense (`[state][symbol]`): a row-displacement form makes the MUMPS parser
smaller and parsing slower. After the table is built, `lr.zig` rejects a
table that reduces forever on one lookahead, by simulating each reduce
chain from every empty-reduction cell on an explicit stack.

`conflicts.zig` aggregates the unresolved cells into manifest entries
(`shift rule` / `reduce winner over loser`, with cell counts), compares them
with `@conflicts` (both sides normalized as
[GRAMMAR.md](GRAMMAR.md#conflicts-and-hints) describes), and on any drift prints each new conflict with its state, items,
and a shortest symbol path from a start state (breadth-first over the
automaton), then the whole actual manifest. It also fails `X "c"` hints
that decide nothing. `expected.zig`
computes each state's expected list (the `@errors`-named rules it waits
for, then the terminals none of them starts), and `repair.zig` ranks the
`@repair` insertion candidates per state by class and by the minimum
number of further tokens the item needs.

### Code generation

`src/codegen/codegen.zig` writes the module in sections: header, the lexer
declarations from lexgen, `Tag`/`Role`/`Start`, the runtime, the
grammar-specific tables and functions, and the `Parser` alias with the
top-level `parseX` helpers. Tables are array literals, so a generated
module needs no comptime expansion. A `ruleValue` table says how each rule
takes its value: a rule whose value is nil or one of its elements needs no
call of `executeAction`. `src/codegen/actions.zig` compiles every other
action tree into the Zig expression `executeAction` returns for it: a list
whose items are elements, tags or nil is a comptime-known item array that
one builder reads, and `(...N x)` extends a left-recursive list in place
(amortized O(1) per element). It also decides, per rule, whether an
untagged list can reach the tree (and needs a node id) or is only ever
spliced (plumbing, no id).

The runtime is `src/codegen/runtime_template.zig`, a real Zig file that
compiles and has its own tests against a small hand-written fixture.
`runtime.zig` extracts its `// @section NAME ... // @end` blocks and fills
`// @slot NAME` lines; everything outside the sections (the fixture, the
tests) is never emitted. The template refers to a fixed set of generated
names (`parseTable`, `executeAction`, `tokenToSymbol`, `slotOf`, ...), listed
at its top.

At run time the parser keeps the state stack, the value stack, the spare
capacity of lists being extended (indexed like the value stack), and with
a node store the start of each stack entry (and its end, when side-band
labels or nested nodes need element extents). A reduction's span runs
from its first element's start to the end of the last token shifted. Node
store entries (span and rule, 12 bytes) live in chunks of 128 that never
move. Parse memory comes from a bump allocator over chunks of the arena
(the arena itself is threadsafe, and the parser needs no atomics). An
`@as` keyword is looked up once per token, per group; only the table
checks run again in each state. Every walk of a tree (`write`, `span`,
`writeFacts`, placing the empty leaf of `~N`) keeps its frames on an
explicit stack, so a tree as deep as its input is long never overflows the
native stack.

## Self-hosting and the bootstrap

`src/frontend/parser.zig` is generated from `nexus.grammar` by Nexus
itself, so the frontend is always the product of the current generator.
The `bootstrap` test regenerates it and requires the checked-in file to be
a fixed point. After any change to `nexus.grammar` or to generated code
(`src/codegen/`, `src/lexgen/`):

```bash
zig build
./bin/nexus nexus.grammar src/frontend/parser.zig
zig build                                     # the new frontend
./bin/nexus nexus.grammar src/frontend/parser.zig   # again: must not change
./test/run --update gen sexp                  # review every changed line of the goldens
./test/run
```

Review the golden diff by kind, so that every kind of change is one you
meant:

```bash
git diff -U0 test/golden | grep -E '^[-+][^-+]' | sed -E 's/[0-9]+/N/g; s/"[^"]*"/"S"/g' | sort | uniq -c | sort -rn | head -30
```

If the current frontend fails to build, regenerate it with the last good
`bin/nexus`. A syntax change the old frontend cannot parse goes in two
steps: first teach the generator (lowering, codegen) with the old syntax
still accepted, regenerate, then use the new syntax.

## Invariants

The rules in [AGENTS.md](../AGENTS.md) hold on every commit. These tests
check them:

| Rule | Checked by |
|---|---|
| tested features, tested docs | every suite, `docs/*` |
| nothing silent | `adverse/*` (every rejection), `tools/messages` (every message printed by some test), `known/*` |
| located errors, exit 1, nothing written | `adverse/*`, `tools/cli` |
| deterministic output | `determinism/*`, `gen/*` (byte-exact goldens) |
| the bootstrap converges | `bootstrap` |
| LALR is LALR | `unit/nexus` (lookaheads equal merged canonical LR(1)) |
| every generated parser compiles and runs | every suite and doc example |
| formatted source | `tools/fmt` |

## Releasing

1. Set the version in `src/version.zig`; it is stamped into every
   generated file's first line.
2. Regenerate the frontend (the bootstrap loop above) and the goldens
   (`./test/run --update gen`).
3. Head `CHANGELOG.md`'s section of unreleased changes with the version
   and the date.
4. Commit, and tag the commit `vX.Y.Z`.

## Performance

`test/bench/run` measures generation time and lexing and parsing
throughput; [test/bench/BASELINE.md](../test/bench/BASELINE.md) records the
current numbers and how to compare two builds.

## Source map

| Path | Role |
|---|---|
| `src/main.zig` | the command line and the pipeline |
| `src/diag.zig` | the diagnostic format, line and column lookup |
| `src/grammar.zig` | shared data: lexer spec, grammar IR, the desugared grammar; the escape decoder |
| `src/frontend/parser.zig` | the frontend parser, generated from `nexus.grammar` (never edit) |
| `src/frontend/lang.zig` | its lang module: layout, word classes, @lexer line scanning |
| `src/frontend/frontend.zig` | parse entry, syntax errors, `--dump-sexp` |
| `src/frontend/lower.zig` | lowering to LexerSpec and GrammarIR, meaning checks |
| `src/lexgen/regex.zig` | the pattern language |
| `src/lexgen/automaton.zig` | byte classes, NFA, DFA, minimization, reference matcher |
| `src/lexgen/lexgen.zig` | lexer checks and direct-coded emission |
| `src/semantics.zig` | schema, placement, coverage, static types |
| `src/expand.zig` | desugaring to BNF |
| `src/check.zig` | defined symbols, reachable rules, token binding, hint resolution |
| `src/lr/` | grammar facts, automaton, lookaheads, table, conflicts, expected sets, repair |
| `src/codegen/codegen.zig` | module composition and grammar-specific code |
| `src/codegen/actions.zig` | action trees to Zig |
| `src/codegen/runtime_template.zig`, `runtime.zig` | the runtime and its section extraction |
| `src/version.zig` | the version stamped into generated files |
| `nexus.grammar` | the grammar-file grammar |
| `build.zig` | `zig build` (bin/nexus), `zig build unit`, `zig build test` |
| `test/` | the suite ([test/README.md](../test/README.md)) |
