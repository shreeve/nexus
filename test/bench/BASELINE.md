# Benchmark baseline

The numbers `test/bench/run` produces for this checkout. Re-run it after
any change that could affect speed, compare with these tables, and update
this file when a change moves them.

Recorded with `test/bench/run` (fast mode) on pup: Intel Core Ultra 9
185H, Linux, Zig 0.17.0, the whole run pinned to one P-core (`taskset -c
3`) while other jobs ran on the E-cores. Two full runs, interleaved with
two runs of the previous generator; differences between runs are under
0.1% for MUMPS parse throughput, about 3% for Rig's, and up to 1 ms for
generation. Compare runs from one machine only.

## Generation time

20 runs per grammar, wall clock of the nexus process (started from perl
without a shell, so the time includes the process start of nexus itself).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 11.8 | 11.4 | 8180 | 561 |
| ruby | 6.9 | 6.6 | 5575 | 418 |
| rig | 29.8 | 29.5 | 10923 | 806 |
| slash | 1.7 | 1.6 | 3493 | 173 |
| nexis | 0.9 | 0.9 | 2713 | 121 |
| nexus | 3.4 | 3.3 | 4827 | 248 |
| features | 0.9 | 0.9 | 2800 | 117 |
| basic | 0.8 | 0.8 | 2705 | 113 |
| lit_tags | 0.7 | 0.6 | 2650 | 109 |

Generated modules hold their parse tables as literal arrays, which makes
them larger than the code that builds them would be and quicker to
compile; the tables are compressed by row displacement
([INTERNALS.md, "The parse table"](../../docs/INTERNALS.md#the-parse-table)),
which costs generation a few milliseconds (mumps 8.4, ruby 4.2 and rig
21.5 ms with a dense table, interleaved with the rows above). A grammar whose `@infix` table folds (rig, basic, features) runs
the LR stage twice: once on the chain, which every check sees, and once
on the folded table it generates from.

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory. *lex* runs the lang
`Lexer` wrapper over the generated `BaseLexer` to EOF; *parse* is lexing +
LR parsing + tree building (the raw grammar tree: `parseRoutine` for
MUMPS, `parseTree` for Rig) with a new parser per file; *reset* is the
same with one parser `reset` before each file (`-` for Rig, whose lang
`Parser` wrapper has no `reset`).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB),
  parsed with em's schema-mode grammar (`grammars/mumps`); 24,646 parse to
  the end, the rest stop at gaps in the grammar.
- **rig**: Rig's behavior tests and examples that parse on their own
  (`~/Data/Code/rig`), listed again and again until the list holds about
  4 MB (6,168 small files). The per-file cost of a fresh parser weighs more
  on these short programs than on VistA's routines.

The MUMPS and Rig rows were recorded with the grammars `grammars/mumps` and
`grammars/rig` hold.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | reset ms | reset MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 35,634,361 | 265.7 | 325.7 | 1572.7 | 55.0 | 992.3 | 87.2 | 24646 |
| rig | 6168 | 4.9 | 1,209,984 | 36.8 | 132.7 | 94.1 | 51.9 | - | - | 6168 |

Parsing costs about 7x lexing on MUMPS (22 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

The lexing column moves with the layout of the binary around the lexer,
not only with its code: interleaved with the rows above, the parsers of
the previous generator, whose lexer is the same code (actions that
return their values through memory), lexed VistA in 258.0 ms and Rig's
programs in 36.2, and parsed them in 1620.3 (reset 1000.9) and 96.0 ms;
they generated in the same times. These rows were recorded on cpu 5
while other jobs loaded the machine at times; the comparison A/B of the
`prof` harness (three rotated orders, two runs) is in CHANGELOG.md.

## Reusing a parser

A new parser per file fills memory the process has not touched, and the
kernel faults each page in; a reset parser parses in memory it already
holds. The bench's harness, one parser reset per file against a new one
(three rotated orders, one P-core, `taskset -c 2`, best of 5 rounds),
over VistA, Rig's 704 sources (its wrapper given a `reset`) and Zig
0.17.0's source tree:

| input | new parser ms | reset ms | page faults, 5 rounds (new / reset) | held between files |
|---|---:|---:|---:|---:|
| mumps (24,704 files) | 1656.5 | 1039.2 (-37%) | 2,455,375 / 23,829 | 1.1 MB |
| rig (704 files) | 56.4 | 46.0 (-18%) | 40,465 / 2,758 | 1.2 MB |
| zig (2,620 files) | 612.9 | 487.9 (-20%) | 758,207 / 204,057 | 16 MB |

Peak RSS is the same either way (90, 17 and 185 MB: the input held in
memory, and for Zig its largest file's parse). `reset` keeps at most
`resetKeeps` (16 MiB); one that kept everything held 136 MB after Zig's
largest file and was 2.6% slower there (501.1 ms, 237,759 faults: growing
the kept buffer reallocates it, untouched); on VistA and Rig the two are
within 0.5%.

## Reading a difference

Run each side at least twice and compare minimums; interleave A/B runs of
two binaries when the difference is small. When wall time moves but the
work should not have, compare hardware counters: `/usr/bin/time -l` on
macOS reports instructions retired and cycles elapsed (`perf stat -e
instructions,cycles` on Linux). A build that retires fewer instructions in
more cycles is a code-generation or layout effect, not more work.

## Design measurements

The choices [PERFORMANCE.md](../../docs/PERFORMANCE.md) explains were each
measured against the alternative. All rows are from pup (Intel Core Ultra 9
185H, Linux, Zig 0.17.0, ReleaseFast) with the generated parsers of
`grammars/mumps` (24,704 VistA routines, 35.6 M tokens), `grammars/rig`
(704 of Rig's sources) and `grammars/zig` (Zig 0.17.0's source tree, 2,620
files, 71.5 MB, 12.8 M tokens), all input in memory. A build of each
alternative ran in turn on one pinned P-core (`taskset -c N`), in three
rotated orders, best of 5 rounds, with `perf stat` counting user
instructions and cycles. *parse* is a new parser per file, *reset* one
parser `reset` before each file, *lex* the lang `Lexer` wrapper alone. A
change is in cycles or milliseconds against the alternative, negative being
faster; trees, spans and errors were identical for every pair over all
three inputs.

### Layout noise

Identical code laid out differently moves the cycle count. Padding a
parser with an exported function of 320 or 2,112 bytes (same instructions,
other addresses) moved the generated lexer by -4.5% to +4.7% across the
three grammars, and two builds of the same lexer code ran 7% apart on
VistA. Lexing rows below that are within about 5% are layout, not code;
`lex` rows of an A/B whose lexer is the same code show the floor.

### Table dispatch against direct dispatch

A parse loop of one labeled `switch` with an arm per state and per-rule
reduce code (the state in the program counter, as the lexer does it),
against the table loop. Direct dispatch runs the same trees.

| ms (best) | table | direct | change |
|---|---:|---:|---:|
| mumps parse | 1614.8 | 1902.6 | +17.8% |
| mumps reset | 1037.9 | 1219.9 | +17.5% |
| rig parse | 54.3 | 60.3 | +11.0% |
| zig parse | 601.9 | 635.0 | +5.5% |
| zig reset | 486.2 | 507.2 | +4.3% |

Instructions barely change (mumps -2%, zig +3%); instruction-cache misses
per 1000 instructions grow 3 to 15 times (mumps reset 0.11 to 1.70, zig
reset 0.13 to 1.30) and IPC falls (mumps reset 2.93 to 2.43). The table
loop is 8.7 KB plus `executeAction` (51 KB on mumps); direct dispatch is
361 KB of `directParse` plus 305 KB of per-rule reduce code on mumps, and
1.33 MB plus 443 KB on zig. The generated parser grows from 1.06 to 1.60 MB
(mumps) and 2.22 to 4.10 MB (zig), and the ReleaseFast compile of zig's
driver from 17 to 79 s.

### Compressed table against the dense one

Row displacement with no default reductions, against the dense
`[state][symbol]i16` table, the parse loop's gotos read as a default per
nonterminal plus exceptions.

| | mumps | rig | zig |
|---|---:|---:|---:|
| table bytes, dense | 661,800 | 1,024,556 | 1,365,830 |
| table bytes, compressed | 93,528 | 102,996 | 485,872 |
| parse | -0.5% | +1.3% | +1.3% |
| reset | +0.1% | - | +2.6% |
| instructions | +6.8% | +2.2% | +5.0% |

Other lookup shapes cost more: exact comb gotos in the loop +1.2% to +4.0%
cycles; a table split into dense terminal-action rows and a goto form
-2.6% to +1.7% but 232 to 498 KiB; one goto word per rule (target and
exception base together) slower on all five rows; an error bitset added a
load per lookup and nothing else. Dense tables fit L2 on both machines
(L2 misses are nil); precise L1D-miss sampling put 50% (mumps), 34% (zig)
and 20% (rig) of L1D misses on the table load, which bounds what any table
layout could save at 3.6%, 1.7% and 1.6% of cycles.

### The packed Token

`Token` as a `packed struct(u64)` against a plain struct of the same
fields (returned through memory, written as four stores and read back as
one 8-byte load).

| | mumps | rig | zig |
|---|---:|---:|---:|
| reset | -3.7% | - | -25.7% |
| parse | -2.1% | -2.3% | -17.9% |
| lex alone | +5% (instructions -2%) | +0.9% | -16% |

An `extern struct` Token did not help (+0.7%). Store-to-load forwarding
blocks (`ld_blocks.store_forward`) per round, with the plain struct: 85 M
on mumps, 40 M on zig, 1.9 M on rig.

### Action values in registers

Each `executeAction` arm returning its list as one integer, with the tree
builders inline in optimized builds, against arms returning a `Sexp`
through memory.

| | mumps | rig | zig |
|---|---:|---:|---:|
| reset | -3.8% | - | -4.3% |
| parse | -5.2% | -0.9% | -4.3% |

The shared exit that copied the returned `Sexp` out held 62% of
`executeAction`'s cycle samples on mumps (13% of all cycles), 58% on zig
(11%) and 43% on rig (3%); store-forwarding blocks per round fell from
37.9 M to 6.7 M (mumps reset) and from 11.2 M to 3.7 M (zig reset). The
ReleaseFast compile of the three drivers takes 2 to 9 s longer (30.0 to
32.3, 32.9 to 41.4, 29.2 to 33.2 s). Builders called as functions in
Debug builds compile within 0.6 s of the alternative (5.9-6.4,
1.3, 0.8 s);
inline in Debug they cost Rig and Zig 58% and 63% more.

### The chain-end cache and the `@as` state mask

Measured on a parser without either (minimum ms of three interleaved
rotations, one P-core), against the same parser with it; the cache was
measured as a thread-local one of the same 2,048 entries and key.

| | mumps | rig | zig |
|---|---:|---:|---:|
| chain-end cache, parse | -0.9% | -11.8% | -26.8% |
| `@as` state mask, parse | -6.2% | -1.8% | -0.5% |

Pass-through steps per token: 1.0 on mumps (35.7 M for 35.5 M tokens), 3.3
on rig (2.70 M for 0.83 M) and 4.2 on zig (53.3 M for 12.8 M). `@as`
promotions on mumps: 11.5 M for 35.5 M tokens. The cache's size (2,048
entries) against a table of every end: zig's grammar has 497,000
(state, nonterminal, lookahead) chain triples.

### Lexer run scans

Run lengths of the generated lexers (calls per lex of each input):

| | mumps | rig | zig |
|---|---|---|---|
| `scanWhile` ending after 0 / 1-7 / 8-15 / 16+ bytes | 1.14 M / 4.52 M / 407 / 7 | 59K / 110K / 66K / 319 | 579K / 1.94 M / 412K / 211K |
| blank runs of 0 / 1 / 2-7 / 8+ bytes | 30.0 M / 5.40 M / 221K / 4.7K | 538K / 351K / 57K / 5.0K | 8.61 M / 4.25 M / 479K / 900K |

Variants of the scans against the 16-byte vector scan with a one-byte
probe, on the generated lexer alone (`BaseLexer.next` not inlined into the
wrapper, so the compiler's inlining choice does not enter), cycles on
mumps / rig / zig; the layout floor is -4.5% to +4.7%:

| variant | cycles | instructions |
|---|---|---|
| SWAR (u64 words) for every scan | +5.1 / +4.2 / +9.0 | +8.9 / +11.3 / +2.9 |
| SWAR for scans over a class, vectors for stops | -0.2 / +3.6 / +4.3 | +7.4 / +9.6 / +2.9 |
| SWAR for stops, vectors for classes | +2.3 / +1.2 / +0.2 | +6.3 / +1.4 / 0 |
| 8 SWAR words, then 16-byte vectors | +1.2 / +1.2 / +13.5 | +8.6 / +11.3 / +16.4 |
| 32-byte vectors from the first byte | +4.6 / +7.2 / +4.5 | +6.8 / +6.0 / +4.8 |
| no one-byte probe (SWAR) | +1.2 / +4.8 / +8.4 | +9.1 / +6.9 / +2.7 |
| blanks by SWAR after 1 byte, lexing and parsing | +6.9 / +2.0 / +4.1 (lex), +2.9 / +2.3 / +5.1 (parse) | |

No variant gains 3% on lexing or parsing for any grammar. On Apple M5
(arm64) the 32-byte vectors cost lexing +31.8% / +8.7% / +41.9%, two NEON
registers and no movemask. Scans over several byte ranges cost about 20
operations per 8-byte SWAR word for the identifier class (four ranges)
against about 12 vector operations per 16 bytes.

Vector scans against byte-at-a-time loops for the run classes and the
blank skip, with a probe of up to five bytes before the vectors (the
generator probes one, and scans blanks byte by byte): lexing Zig's source
-9.8% (instructions -18.6%), MUMPS +1.6% (its runs are short, and IPC
falls on short runs), Rig unchanged.

### Hardware counters of the table loop

User counters per 1000 instructions, one pinned P-core, for the table loop
with a dense table and a plain-struct Token, a new parser per file (parse)
and one reset per file (reset):

| run | IPC | branch misses | L1D misses | L2 misses | L1I misses |
|---|---:|---:|---:|---:|---:|
| mumps parse | 2.46 | 2.19 | 2.86 | 0.004 | 1.08 |
| mumps reset | 2.95 | 1.73 | 1.51 | 0.000 | 0.11 |
| rig parse | 2.37 | 3.25 | 2.09 | 0.009 | 0.80 |
| zig parse | 2.00 | 2.08 | 2.17 | 0.020 | 0.41 |
| zig reset | 2.16 | 1.93 | 1.43 | 0.013 | 0.12 |

Fresh memory costs page-fault zeroing, 25% to 33% of L1D misses, and about
30 times the data-TLB misses and 9 times the instruction-cache misses of
reused memory. Branch misses fall mostly in the lexer (zig 56%, mumps 34%),
then in the reduce actions (10%); table lookups cause 3% to 7% of them.
