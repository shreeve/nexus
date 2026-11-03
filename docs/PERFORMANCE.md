# Performance

How generated lexers and parsers are made fast and small, and why each
choice was made over its alternative. [INTERNALS.md](INTERNALS.md) says how
the generator works; this document says why the code it writes looks as it
does. The measurements behind every comparison are in
[test/bench/BASELINE.md](../test/bench/BASELINE.md), "Design measurements";
this document says which approach is faster and where to find by how much.
A change that could affect speed is benchmarked before and after
([AGENTS.md](../AGENTS.md), rule 9), and a faster parser gives the same
trees, spans, errors and messages as a slower one.

What costs time in a generated parser, from profiles of three grammars
(MUMPS, Rig, Zig), is one of five things: the lexer, the table lookups and
dispatch of the LR loop, shifting and pushing, reducing (running the
action, building lists), and memory (page faults on fresh memory). The
sections follow that order.

## The lexer

### The scanner

The scanner is a labeled `switch` with one prong per DFA state, jumping
with `continue` ([INTERNALS.md, "Lexer generation"](INTERNALS.md#lexer-generation)).
A state's transitions are direct jumps, a transition into a state that
cannot continue returns the token in place, and keywords that a grammar
writes as literal rules are DFA states too, so a reserved word costs no
lookup after the scan (the Zig grammar). Every byte test is guarded by the
end of the input (`p < n`); the scanner does not rely on a sentinel byte,
so it runs over any `[]const u8` without a copy.

### Run scans

A self-loop of the automaton (an identifier's letters, a comment's text, a
string's body) is the hot part of a scan. The generator picks a form from
the loop's byte class, not from token names:

- A loop that excludes at most three bytes (a comment ends at a newline, a
  string at a quote) calls `scanUntil`, which compares 16 bytes at a time
  against each stop byte and takes the first hit with a count of trailing
  zeros.
- A loop over a class of at most four byte ranges tests its first byte
  inline (the *probe*, one byte), and only when that byte is in the class
  calls `scanWhile`, which tests 16 bytes at a time against the ranges. On
  a little-endian target the mask is read as two `u64` lanes of the
  inverted result, so the code needs no movemask instruction; on a
  big-endian one it is a 16-bit mask. The bytes after the last full block
  are tested one at a time.
- A loop over a class of more ranges is a plain loop over a membership
  test.
- The blanks before a token (spaces and tabs, counted into `pre`) are a
  plain loop.

Why these shapes, from the measurements:

- Almost every run ends within 8 or 16 bytes (nearly all of MUMPS's class
  scans end within the first 8), so what decides the cost is one iteration
  of the scan, not how fast it streams. Vectors win where runs are long
  (Zig's identifiers, comments and strings) and cost little where they are
  short.
- The one-byte probe is the cheapest that avoids a vector load on every
  empty run: a longer probe (2, 4, 8 bytes) costs more than it saves on
  short runs, and no probe retires more instructions for no gain in cycles.
- SWAR (8-byte words in integer registers) loses to the 16-byte vectors on
  every grammar. A class test is a set of ranges, and per range SWAR needs
  two additions and an and-not per word, then a mask, an inversion and a
  count: about 20 operations per 8 bytes for a four-range class against
  about 12 vector operations per 16. SWAR is at its best on a search for
  one or a few equal bytes, where a byte costs an xor and a subtraction,
  and `scanUntil` with SWAR still ties or loses, because its runs are as
  short.
- 32-byte vectors cost more than 16 on both machines measured: no gain on
  x86, and on arm64, which has no movemask, two registers per test make
  lexing up to 40% slower.
- Blanks stay a plain loop because most runs are zero or one byte (35.4 M
  of MUMPS's 35.6 M blank runs); a vector or SWAR scan after the first
  byte made lexing and parsing slower on every grammar, Zig included,
  although Zig has runs of eight or more blanks in indentation.
- A mixed form (SWAR for the first words, vectors after) has no cutoff at
  which it beats vectors from the start, so there is no per-architecture
  cutoff to choose.

([BASELINE.md, "Lexer run scans"](../test/bench/BASELINE.md#lexer-run-scans).)

### Tokens

`Token` is a `packed struct(u64)`: `pos`, `len`, `cat`, `pre`. A token is
passed and returned in one register. A plain struct of the same fields is
returned through memory: written as four narrow stores and read back as one
8-byte load, which cannot be forwarded from the stores and waits for them
to reach the cache (a store-forwarding stall). The packed form is the
largest single speedup measured in the parser (Zig parsing 18% faster, MUMPS
2%), because every lang `Lexer.next` returns one
([BASELINE.md, "The packed Token"](../test/bench/BASELINE.md#the-packed-token)).
On a little-endian target the fields keep their byte offsets (0, 4, 6, 7);
a `@bitCast` between `Token` and `u64` is defined.

### What a lang Lexer wrapper costs

A lang module's `Lexer` wraps `BaseLexer` and runs once per token on top of
the scanner. A wrapper that looks ahead, classifies or keeps layout state
has a cost of its own, which a profile finds: in Rig's and Zig's, most of
their lexing time was in the wrapper rather than the scanner.

## The parser's loop

### Table dispatch, not code dispatch

The strict parse loop (`BaseParser.parse`) reads an action from the table
for (state, lookahead symbol) and shifts, reduces, accepts or fails. It
keeps the state, the symbol and the next action in locals. Code per state
(a `switch` arm per state with the shifts and reductions of the state
inlined, so that the state lives in the program counter as it does in the
lexer and in a recursive-descent parser) was built and measured: it retires
about the same instructions but runs 4% to 18% slower on every grammar,
because the code it generates (hundreds of kilobytes to megabytes per
grammar) no longer fits the instruction cache. The table loop is a few
kilobytes of hot code and one load from a table in L2 per action; the
instruction-cache miss rate of direct dispatch is 3 to 15 times higher and
IPC falls with it. A direct-dispatch parser is also much larger, and much
slower to compile for Zig and Rig ([BASELINE.md, "Table dispatch against direct
dispatch"](../test/bench/BASELINE.md#table-dispatch-against-direct-dispatch)).
The tables stay the single source of what errors, expected sets, `@messages`
and tolerant repairs read, so one representation serves every mode.

### The tables are compressed, and keep every cell

`src/codegen/comb.zig` stores the action and goto rows by row displacement
into one array ([INTERNALS.md, "The parse table"](INTERNALS.md#the-parse-table)).
The dense table (`[states][symbols]i16`) is 646 KiB for MUMPS and 1.3 MiB
for Zig; the compressed one is 91 KiB and 475 KiB. Two choices matter:

- **No default reductions.** A state with one reduction can reduce on any
  lookahead, which saves cells but changes what the parser does at an
  error: it reduces before it notices the token is wrong, and the state it
  fails in, the expected set and the repairs a tolerant parse tries are
  no longer those of the grammar's table. Every cell keeps its action, so
  the error machinery reads the same table as the loop, and the generator
  decodes every cell against the dense table before it writes the module.
- **The loop's gotos use a second form**: the most common target of each
  nonterminal plus the exceptions, because a goto always exists and needs
  no check. Terminal lookups read the action row alone.

The compressed table costs the loop 2% to 7% more instructions and 0 to 3%
more time than the dense one on the grammars measured, because the dense
table already lives in L2 (L2 misses are nil) and a lookup that checks a
cell costs about what the misses it avoids would. It is kept for size: the
table is the largest part of a generated module, and the MUMPS and Rig
tables fit the 128 KiB L1 data cache of Apple's M5 performance cores. Other
lookup shapes (a split table with dense terminal rows, per-rule goto words,
an error bitset) were larger or no faster on all grammars ([BASELINE.md, "Compressed table against the
dense one"](../test/bench/BASELINE.md#compressed-table-against-the-dense-one)).
Packing time is a few milliseconds per grammar, which union-find "next free"
arrays for slots and bases and a resume rule for dense rows keep down.

### Pass-through chains and the chain-end cache

A rule `A → B` whose value is its one element builds nothing. A grammar
with precedence levels or a chain of expression types (Zig, Rig) reduces an
operand through a run of them (4.2 per token on Zig). The loop
([INTERNALS.md, "The parse table"](INTERNALS.md#the-parse-table)) handles a
run in one step: where it ends depends only on the state below, the first
rule's nonterminal and the lookahead, so each parser keeps the ends it has
climbed in a direct-mapped cache of 2,048 entries (16 KiB when the key fits
in a `u32`, which it does for every grammar measured), keyed by those three.
A hit replaces the walk of gotos and action reads with one probe; a miss
walks the chain once (`climb`) and stores the end. Runs through a cell that
an `X "c"` hint overrides are not stored, because the cell's action depends
on the spacing of the token. The cache is kept across `reset`.

A cache rather than a table of every end: the full set for Zig's grammar
holds about 500,000 entries, far more than a cache of 2,048. The cache hits
often enough that walking chains (`climb`) is under 2.5% of cycles. It cut
Zig parsing by a quarter and Rig's by a tenth, and helps MUMPS little,
whose chains are short. An `@infix` table that folds (see
[INTERNALS.md, "LR"](INTERNALS.md#lr)) removes the per-level chain from the
parser altogether and gives the one-lookup precedence of a precedence-climbing
parser: an operator's shift or reduce is decided in the table cell.

### The `@as` state mask

A token that `@as` can promote to a keyword is looked up once per token and
group (a switch on the first byte, then a comparison per entry with that
byte), but only in a state that takes some symbol of the group: the
generator computes a bitset per group at compile time from the table
(`statesTaking`), and `tryPromote` returns before the lookup in every other
state. In MUMPS the lookup was 13% of parsing before the mask and the mask
cut parsing time by 6%. Since a state change after a reduction can change
the answer, a promotable token is promoted again after each reduction.

## Shifting and reducing

### Values in registers

An `executeAction` arm returns its value as an `ActionValue`, a
`packed struct(u128)` of the list's pointer, length and node id, and
`reduce` writes it straight into the reduction's slot on the value stack.
Anything else (an empty list, nil) goes through a field of the parser. In
an optimized build the tree builders (`buildOf`, `build`, `finishItems`,
`keepExtended`, ...) are `inline`, so a value is built in registers. The
reason is the one behind the packed `Token`: a `Sexp` returned through
memory is written field by field (8, 4, 4 and 1 bytes) and copied out by
16- and 8-byte loads that cannot be forwarded from those stores, and the
shared exit of `executeAction` that did the copy held 40% to 60% of its
cycle samples. Registers make parsing 1% to 5% faster, at the price of a
slower optimized build (inline builders unroll every arm; the generator
sets the eval branch quota to 1000 plus the bytes of the arms). A Debug
build calls the builders (`builderCall` is `.auto`), because inlining them
there costs Rig and Zig 60% more compile time and Debug speed is not the
point ([BASELINE.md, "Action values in registers"](../test/bench/BASELINE.md#action-values-in-registers)).

The stalls that remain (a few million per round) come from a leaf or list
written field by field and copied whole by a later builder. Removing them
needs a `Sexp` written with stores as wide as the loads that copy it, a
change of its layout and so of the generated API, for at most 2% to 4% of
cycles.

### Lists

A list built from items that are elements, tags or nil is a comptime-known
array one builder unrolls; a list with spreads is allocated once at its
length and filled; a left-recursive list (`(...N x)`) is extended in place
with spare capacity, amortized O(1) per element
([INTERNALS.md, "Code generation"](INTERNALS.md#code-generation)). A rule
whose value is nil or one of its elements takes no call of `executeAction`
(`ruleValue`).

## Memory

Parse memory is a bump allocator over arena chunks: the stacks, the node
store and the trees. A new parser per file starts in memory the process has
not touched, and the kernel zero-fills each page on its first use: on
VistA that is half a million page faults and more than a third of the
parsing time. `reset(source)` starts a parser over in the memory it holds,
already touched, and takes almost none; it also keeps the chain-end cache
([SEMANTICS.md, "The generated API"](SEMANTICS.md#the-generated-api)). Peak
resident memory is the same either way.

`reset` keeps at most `BaseParser.resetKeeps` (16 MiB) of the arena and
returns the rest to the backing allocator. A parser reused over many files
therefore holds no more than that whatever its largest input needed.
Keeping everything is slower as well as larger: over Zig's source it held
136 MB after the largest file and was 2.6% slower, because growing the kept
buffer reallocates it, untouched. Debug builds overwrite what `reset` keeps, so a tree
held across a reset reads no value of its parse
([BASELINE.md, "Reusing a parser"](../test/bench/BASELINE.md#reusing-a-parser)).

A language with a lang `Parser` wrapper gets the speedup by giving the
wrapper a `reset` that calls the base's.

## Zig's front end

`std.zig.Ast.parse` is the reference for how fast a Zig parser can be. What
makes it fast, and what a generated parser does about each:

| Zig's front end | A generated parser |
|---|---|
| The tokenizer is a labeled-switch state machine with direct jumps. | The same: the lexer is a labeled `switch` over DFA states. |
| Keywords are reserved and recognized in the scan. | The same when a grammar writes them as lexer rules (the Zig grammar); `@keywords` and `@as` give a lookup for languages whose keywords depend on context, restricted by the state mask. |
| The source is sentinel-terminated, so a byte test needs no length check. | Each test is guarded by `p < n`; a sentinel would need a padded copy of the source or a signature that requires one. |
| The parser is recursive descent: the state is the program counter and a pass-through costs a call. | The parser is LR: table dispatch (above), and the chain-end cache and folded `@infix` stand in for cheap pass-throughs. Code dispatch was measured and is slower. |
| Operator precedence is one table lookup per operator. | A folded `@infix` table decides it in the table cell; a chain that does not fold costs one reduction per level. |
| The whole file is tokenized first into struct-of-arrays, with an estimated capacity, then parsed. | Tokens are pulled one at a time. The lexer can be stateful, a lang wrapper can depend on the parser's state, and `BaseParser.lexer` is the lexer as it stood at an error; a token list ahead of the parser would change each. |
| A token stores only its start; its end is found by re-lexing. | A token stores its length and the parser keeps the end of the last token for spans. Re-lexing is wrong for a stateful lexer. |
| The tree is struct-of-arrays: a node is a tag, a main token and two `u32`s, indexed by `u32`, plus an extra-data array. | The tree is `Sexp` values, 24 bytes on 64-bit targets, in contiguous lists, with a 12-byte node record for spans, so a tree is larger and moves more bytes per node. A flat tree would replace the generated API, which all consumers share ([SEMANTICS.md](SEMANTICS.md#the-generated-api)); it is not a speed knob. |
| Spans are computed on demand from node tags. | Spans are stored per node (eager), so `span()` is a lookup for generic code with no per-kind knowledge. |
| Lists are built on one shared scratch stack and copied once. | Lists are allocated at their final length and filled, or extended in place; there is no scratch stack. |
| Error paths are cold. | The strict loop records a failure only on its error branch; repair belongs to `parseTolerant`, and a strict parse pays nothing for it. |
| Recursion on the native stack. | Explicit stacks: a tree as deep as its input never overflows the native stack. |

What bounds a generated Zig parser against `Ast.parse` is therefore
structural: a table lookup per step against a branch on a token tag, a
wrapper between lexer and parser, and a 24-byte `Sexp` leaf pushed per
token against 5 bytes of token and a 13-byte node. The speedups above
close part of that gap; the rest is the price of a generated parser with a
schema, spans for generic consumers, tolerant parsing and a stable API.

## Measuring

- `test/bench/run` measures generation time and lexing and parsing
  throughput, with a new parser per file and with `reset`; `--nexus BIN`
  benchmarks another generator on the same inputs, so two builds are
  compared by one script ([BASELINE.md](../test/bench/BASELINE.md)).
- Pin the process to one core and keep other jobs off its sibling
  (`taskset -c N` on Linux), compare the best of at least five rounds, and
  run the builds in rotated orders (A B, B A, ...) so that drift and warm-up
  fall on both.
- Count before explaining. `perf stat -e instructions,cycles,...` on Linux
  and `/usr/bin/time -l` on macOS report user instructions and cycles; a
  change that retires fewer instructions in more cycles is a layout or
  code-generation effect, not less work. Useful events: L1D and L1I
  misses, branch misses, page faults, and on Intel
  `ld_blocks.store_forward` (store-forwarding stalls), whose samples by
  source line found both the `Token` and the `executeAction` exit.
- Run the same corpus under both builds and compare the trees, spans and
  errors of every file (`driver --hash`); a speedup that changes a tree is
  a bug.
- Control for code layout. Moving a function changes the addresses of the
  code around it and so its speed: identical lexer code ran 7% apart
  between two builds, and padding a parser with an exported function of a
  few hundred bytes moved the lexer by -4.5% to +4.7%. A lexing difference
  below that, between builds whose lexer is the same code, is layout. To
  tell, add a pad function of two different sizes to the baseline build
  and see how far identical instructions move; to isolate the scanner from
  the compiler's inlining choice, call `BaseLexer.next` through
  `.never_inline`, which stops the generated lexer from being inlined into
  the wrapper in one build and not in another.
- Check what grows: the generated module (`wc -c`), the binary's `.text`
  and `.rodata`, the ReleaseFast and Debug compile times of a driver, and
  generation time. A faster parser that doubles the compile is a cost the
  suite pays at every case.
- A comparison on a machine with other jobs running is not one: Apple's
  cores under a load of 5 or more moved wall-clock by tens of percent;
  read cycles there, and trust a comparison from one quiet machine.
