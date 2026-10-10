# Zig 0.17.0 in Nexus

`zig.grammar` is the syntax of Zig 0.17.0 written as one
[Nexus](../../README.md) grammar. Nexus generates from it a single
standalone Zig module, with no runtime dependency: a DFA lexer, an
LALR(1) parser, and a typed tree whose kinds and roles are those of
`std.zig.Ast`. The grammar is written to agree exactly with Zig's own
front end (`lib/std/zig/tokenizer.zig`, `Parse.zig`, `Ast.zig`), and the
tools in this directory check, input by input, that it does: the same
tokens, the same inputs accepted and rejected, and the same tree, node for
node and span for span.

This page is for the Zig team: what the grammar is, the evidence that it
is equivalent to `std.zig`, what it costs to run, and how it could be of
use to Zig.

## What is here

| File | Role |
|---|---|
| `zig.grammar` | the grammar: lexer, `@schema` (the tree), conflicts, rules in grammar.peg's sections and names |
| `zig.zig` | the lang module: a Lexer wrapper that skips a byte order mark and gives the token categories Parse.zig decides by looking past the next token |
| `cases/` | hand-written inputs and their expected trees (`reject_*`: inputs Ast.parse rejects, one per kind of mistake); `cases/tokens/` the token stream |
| `known/` | the one known difference (below) |
| `tokens_test.zig` | the lexer against `std.zig.Tokenizer`, on inputs it holds |
| `trees_test.zig` | the tree against `std.zig.Ast`, on inputs that use every kind and role |
| `messages_test.zig` | the wording of syntax errors |
| `trees.zig` | the canonical form both trees are printed in, and the rules that map one onto the other |
| `compare-tokens`, `compare-accept`, `compare-trees` | the three comparisons, over any set of files (`tools/`) |

`./test/run zig` runs the cases and the three `_test.zig` files; the
`compare-*` scripts run the same comparisons over a corpus. Each script
documents its options (`-h`).

## How the grammar is written

Rules follow `doc/langref/grammar.peg`, section by section (TOP LEVEL,
BLOCK LEVEL, EXPRESSION LEVEL, ASSEMBLY, HELPER GRAMMAR), and a rule for a
construct grammar.peg names takes its name in snake_case: `BoolOrExpr` is
`bool_or_expr`. Where grammar.peg and Parse.zig disagree, the grammar
follows Parse.zig, since it is what the compiler runs. grammar.peg is a
PEG over bytes: operator spacing, `&&` and the newline before a doc
comment are lookaheads on characters there, which the Lexer wrapper below
turns into token categories here; the `reject_*` cases cover each.

Parse.zig is predictive: it commits to a reading after a token or two and
never backtracks. Where LALR(1) would decide later and accept more, the
grammar writes the commitment as a restricted variant of a rule, named by
a suffix (`expr_s` for an expression statement, which starts with no
keyword a statement starts with; the `_k` operands, which do not end in an
open `return x`, `if` or loop; and so on, each explained where it is defined).
Where Parse.zig decides by looking further than one token, or at the bytes
around a token, the Lexer wrapper in `zig.zig` makes the decision and
names the token by it: an identifier before `:` and `{`, `while`, `for`,
`inline` or `switch` is a `label`; a binary operator with whitespace on
one side only is a prefix category or `bad_operator`; and five more, each
documented in `zig.zig`. Every LR conflict the grammar has is declared in
`@conflicts` with its reason in Zig terms (`return - x` returns `-x`; a
switch prong's leading `inline` is the prong's), and resolves as
Parse.zig does.

The heads of a for, a function and a variable declaration (grammar.peg
ForPrefix, FnProto, VarDeclProto) are rules of their own, each spread
into the roles of the node that holds it (`→ (for 1 3 ...4 5)`). The
heads of if and while are written out in each form: they end in parts
that may be absent, and as rules of their own they would make a syntax
error right after the `)` list every token any form can take, where
written out it names what that form waits for. Spans are Ast's: a span
mark leaves a statement's `;` (`-";"`) and the doc comments before a
declaration, field, parameter or error name (`-[docs]`) out of the span
of its node, and a statement that ends in another one ending in `;`
(`if (a) b else c;`) takes the `;` at the top, so no node spans it.

The grammar has 130 tokens (333 DFA states) and 218 rules, which expand
to 984; the parser has 1,872 LR states and 32 conflict cells in 9
declared entries. Nexus generates the 2.1 MB module in 0.11 s.

## Equivalence

Each comparison runs the Zig 0.17.0 standard library in process as the
reference, so the Zig that runs a script must be 0.17.0. The corpus is
every `.zig` file in the Zig 0.17.0 source tree (`lib/`, `src/`, `test/`,
`doc/`): 2,620 files, 71.47 MB.

| Check | Inputs | Differences |
|---|---|---|
| tokens: tag, start and end of every token, invalid tokens included | the corpus: 12,805,547 tokens; 4,000,000 random inputs (`--fuzz`, seeds 0 and 1) | 0, besides the long token below |
| accept: a whole file parses, or it does not (`Ast.parse` with `.recover = false`) | 3,134: the corpus, and the 514 sources `parser_test.zig` and `parser_fuzz.zig` pass to `testCanonical`, `testTransform`, `testError` and `checkAgainstOracle`; 150,000 token-edit mutants of them | 0, besides the long token below |
| trees: every node, its kind, roles and span | the 3,035 of those 3,134 that both accept; 300,000 token-edit mutants, of which 56,114 are accepted by both and compared | 0 |

A mutant is a piece of a seed file with one to four token edits (delete,
duplicate, swap, insert a keyword or operator); most mutants are
rejected, and the two parsers must agree on every one. The suite runs
the same token and tree comparisons on the inputs `tokens_test.zig` and
`trees_test.zig` hold, so a change that breaks either fails `./test/run`.

### How the two trees are compared

`std.zig.Ast` and the Nexus tree describe the same parse in different
representations, so `trees.zig` prints both in one canonical form (the
grammar's `@schema`: kinds, named roles, spans, `text@position` leaves)
and compares them as text. The Nexus tree is printed as it is, spans
included. Nine rules map Ast's onto it; each is a difference of
representation, stated in full in `trees.zig`:

- T1: the kinds Ast has no node for (`param`, `capture`, `field_init`,
  `error_name`) are built from Ast's tokens and `full*` helpers.
- T2: facts Ast keeps only as tokens (labels, `pub`, `extern "c"`,
  `inline`, `comptime`, pointer qualifiers, doc comments, ...) become roles.
- T3: a destructure's leading `comptime` is the destructure's.
- T4: one-token nodes (`identifier`, `number_literal`, ...) are leaves.
- T6: a pointer keeps every `const`, `volatile` and `allowzero` token, as
  Parse.zig accepts any number of each; `full.PtrType` keeps the last.
- T5, T7, T8, T9: four corrections to `std.zig.Ast` helpers that, on
  some inputs, report a node different from the one Parse.zig built: a
  `name:` after `.` or `break :` taken as a label (T5); the last token of
  an empty `enum(T) { //! ... }` (T7); a label found on a loop type after
  a parameter, field or variable `name:` (T8); a switch prong's `inline`
  credited to its first item (T9). These are bugs in the helpers, not in
  Parse.zig, and each makes `zig fmt` change or break the program it
  formats (`[.x: {}]u8` becomes `[.x.x: {}]u8`).

## The one known difference

A Nexus token holds at most 65,535 bytes. `std.zig.Tokenizer` has no such
limit, and one corpus file has a longer token:
`test/cases/maximum_sized_integer_literal.zig`, whose integer literal is
65,537 bytes. Nexus lexes it as an `err` token, which no rule takes, and
rejects the file; Ast accepts it. The file is a known case
(`known/maximum_sized_integer_literal.zig`) and the comparison tools list
it apart (LONG). There is no other difference.

## Syntax errors

A Nexus parser stops at the first syntax error and reports
`line:col: expected X, Y or Z, got W`, the expected set computed per LR
state at generation time. The grammar names tokens as
`std.zig.Token.Tag.symbol()` does (`';'`, `'fn'`, `an identifier`, `EOF`)
and the places that wait for an expression, a type expression, a
statement, a block, a declaration or a parameter by that name
(`@display`, `@errors`). Side by side with Ast's message, for inputs
of `messages_test.zig`:

```text
const x = ;
  nexus  1:11: expected an expression, got ';'
  zig    1:11: expected expression, found ';'
const T = *:0 u8;
  nexus  1:12: expected a type expression, 'const', 'align', 'volatile', 'allowzero' or 'addrspace', got ':'
  zig    1:12: expected type expression, found ':'
fn f() void
  nexus  1:12: expected ';' or '{', got EOF
  zig    1:12: expected ';' or block after function prototype
test {
    if (a);
}
  nexus  2:11: expected a block, an assignment or '|', got ';'
  zig    2:11: expected block or assignment, found ';'
```

Over the 98 inputs both parsers reject (39 corpus files and 59 inline
sources), `compare-accept --messages` prints both messages: 47 of Nexus's
name at most six expected items, and 62 are at the line and column Ast
reports. The rest fall short of Ast's in three ways that the grammar
cannot change:

- **The whole lookahead set.** When the offending token comes where a rule
  could end (after an operand, a closing `)` or a payload's `|`), the
  state that finds the error is one that would only reduce, and its
  expected set is every token that may follow, often fifty or more,
  where Parse.zig says `expected ';' after statement` or `expected ','
  after argument`. Reporting the expectations of the state reached after
  the pending reductions, as a parser with default reductions does, could
  make these short; that is a change to Nexus, not to the grammar.
- **Position.** For a missing `;` Ast points just after the previous
  token; Nexus points at the token it could not take, often on the next
  line.
- **Specific diagnoses.** Ast has messages for particular mistakes
  (`declarations are not allowed between container fields`, `extern
  functions have no body`, `comparison operators cannot be chained`,
  `binary operator '+' has whitespace on one side, but not the other`).
  Nexus rejects the same inputs at a token, with an expected set; a
  grammar has no way to attach a message to a mistake. The strict parser
  also stops at the first error, where Ast.parse can recover and go on
  (Nexus's tolerant parser, `@repair`, is not set up for this grammar).

## Speed

Measured with `compare-tokens --bench 5` and `compare-accept --bench 5
[--no-schema]` over the corpus held in memory, single thread,
ReleaseFast, best of 5 rounds, two interleaved runs, on an Apple M5
(10 cores) with the 1-minute load average below 6. Nexus is this
branch, which includes the parser speed work of Nexus 2.1.0. MB are 10^6
bytes.

| | run 1 | run 2 |
|---|---:|---:|
| Nexus lexer (with the `zig.zig` wrapper) | 739.5 MB/s | 744.8 MB/s |
| `std.zig.Tokenizer` | 760.5 MB/s | 751.7 MB/s |
| Nexus parse, with `@schema` (typed tree with spans) | 149.4 MB/s | 149.5 MB/s |
| Nexus parse, without `@schema` (plain tree) | 159.3 MB/s | 158.9 MB/s |
| `std.zig.Ast.parse` (tokenize and parse) | 444.3 / 441.0 MB/s | 443.4 / 440.5 MB/s |

The lexer runs at the tokenizer's speed: 12,805,547 tokens in 96.0 to
96.7 ms, against 94.0 to 95.1 ms. Parsing takes 3.0 times as long as
`Ast.parse` with the schema, and 2.8 times without it (the two
`Ast.parse` figures are its runs beside each). Ast.parse is a
hand-written recursive descent parser that fills a compact
struct-of-arrays tree; the Nexus parser is table-driven and builds a
general tree of nodes.

## Rerunning every check

Build Nexus (`zig build` at the repository root) and use Zig 0.17.0. `Z`
is a checkout of Zig at tag 0.17.0.

```bash
./test/run zig                                    # cases, tokens_test, trees_test, messages_test

P="--inline $Z/lib/std/zig/parser_test.zig --inline $Z/lib/std/zig/parser_fuzz.zig"
S="$Z/test/behavior $Z/test/cases/compile_errors $Z/lib/std/zig"

test/zig/compare-tokens $Z                        # tokens: 2,620 files, 12,805,547 tokens
test/zig/compare-tokens --fuzz 2000000 --seed 0   # tokens: random inputs
test/zig/compare-tokens --fuzz 2000000 --seed 1

test/zig/compare-accept $Z $P                     # accept: 3,134 inputs
test/zig/compare-accept --fuzz 60000 --seed 13 $Z/lib/std/zig $Z/test/behavior \
    $Z/test/cases/compile_errors --inline $Z/lib/std/zig/parser_test.zig
test/zig/compare-accept --fuzz 30000 --seed 21 $P
test/zig/compare-accept --fuzz 60000 --seed 22 $S

test/zig/compare-trees $Z $P                      # trees: the 3,035 inputs both accept
test/zig/compare-trees --fuzz 30000 --seed 11 $P
test/zig/compare-trees --fuzz 60000 --seed 12 $Z/lib/std/zig $Z/test/behavior
test/zig/compare-trees --fuzz 70000 --seed 31 $P
test/zig/compare-trees --fuzz 70000 --seed 32 $S
test/zig/compare-trees --fuzz 70000 --seed 33 $Z/lib/std/zig $Z/src/Sema.zig $Z/lib/std/mem.zig

test/zig/compare-accept --messages $Z $P          # both syntax errors of every input both reject
test/zig/compare-tokens --bench 5 $Z              # lexer speed
test/zig/compare-accept --bench 5 $Z              # parse speed
test/zig/compare-accept --bench 5 --no-schema $Z  # parse speed, plain tree
```

Each comparison prints one line per input that differs and a summary,
and exits 1 when any input differs. After a change to `zig.grammar`,
`./test/run --update gen/zig sexp/zig` rewrites the generated-code and
grammar-tree goldens, whose diff is reviewed before a commit.

## How this could serve Zig

- **An executable specification.** grammar.peg describes Zig's syntax as
  a PEG over bytes, and is checked against Parse.zig only by the
  depth-limited fuzz test below. This grammar is a token-level LALR(1)
  grammar with Ast's tree, checked against Parse.zig on every corpus file
  and on mutants, for tokens, acceptance and trees; each place where
  Parse.zig decides by more than the next token is written down once,
  with its reason (a rule variant, a wrapper category, a declared
  conflict).
- **A stronger fuzzing oracle.** `std.zig`'s own fuzz test,
  `parser_fuzz.zig`, compares Ast.parse with `parser_generated_oracle.zig`,
  a recognizer generated from grammar.peg: it answers only accept or
  reject, and skips any input that takes more than 5 levels of recursion
  or 5 iterations of one rule (`max_depth = 5`, `error.MaxDepth`). The parser generated here has no depth limit (its
  LR stack grows on the heap) and agrees with Ast.parse on acceptance on
  every input checked above, so it can stand in for that oracle;
  `compare-accept --fuzz` runs such a comparison.
- **Tree-level differential testing.** Beyond acceptance, `compare-trees`
  checks that Ast.parse builds the right tree: kinds, roles and spans,
  through Ast's own `full*` helpers. It found the four helper bugs T5, T7,
  T8 and T9 above, which acceptance alone cannot see.
- **A base for tools.** The generated module is one file with no
  dependency: a lexer, a parser, and a typed tree with spans whose kinds
  are Ast's. An editor, a linter or a formatter in another code base can
  use it, or generate from the grammar with changes of its own.
