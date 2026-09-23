# Benchmark baseline

The 0.10.3 numbers the 1.0 revamp was measured against, then the 1.0.0
numbers. Re-run `test/bench/run` after any change that could affect speed
and compare.

## Nexus 1.0.0

Recorded at `f4fe3f0` with `test/bench/run` (ReleaseFast), Apple M5, 10
cores, macOS 27.0, Zig 0.16.0, on a shared machine (load average 5-11).

Generation, 10 runs per grammar, wall clock including process start
(about 4.5 ms). The full pipeline now includes the DFA lexer generator
and the semantic checks:

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 17.2 | 16.6 | 4471 | 420 |
| ruby | 13.1 | 12.8 | 3425 | 274 |
| rig | 10.8 | 10.6 | 2978 | 180 |
| zag | 10.0 | 9.9 | 2850 | 189 |
| slash | 6.1 | 5.9 | 2185 | 101 |
| nexis | 5.5 | 5.2 | 2113 | 87 |
| nexus | 8.8 | 8.7 | 3553 | 155 |
| features | 4.9 | 4.7 | 1555 | 59 |
| basic | 4.8 | 4.6 | 1438 | 55 |
| lit_tags | 4.7 | 4.5 | 1385 | 52 |

Lexing and parsing, best of 3, the inputs described below:

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 32,130,205 | 248.5 | 348 | 1744.8 | 49.6 | 22709 |
| rig | 1 | 3.8 | 980,288 | 10.9 | 354 | 63.2 | 60.9 | 1 |

Against 0.10.3: lexing 5% (MUMPS) and 4% (Rig) faster, parsing 37% and 17%
faster. `test/diff` over the same VistA routines, 0.10.3 with em's grammar
against 1.0 with `test/mumps/mumps.grammar`: 22,709 identical trees and
1,995 identical parse errors, no differences.

## Nexus 0.10.3

Recorded with `test/bench/run` (ReleaseFast unless noted) before the 1.0
revamp, at `a52aa4f` (generator identical to v0.10.3). Apple M5, 10 cores,
macOS 27.0, Zig 0.16.0. Re-run after any change that could affect speed and
compare; 1.0 must not be slower (SPEC §1.9, §5).

### Generation time

20 runs per grammar, wall clock including process start. The largest
grammars spend ~85% of this in LALR lookahead propagation
(architecture.md §3.4).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 29.1 | 28.7 | 2679 | 342 |
| ruby | 31.2 | 31.0 | 2072 | 214 |
| rig | 12.1 | 11.7 | 1833 | 135 |
| zag | 17.4 | 17.0 | 1733 | 145 |
| slash | 5.4 | 5.1 | 1142 | 60 |
| nexis | 5.0 | 4.8 | 810 | 38 |
| nexus | 4.8 | 4.5 | 916 | 44 |
| features | 4.6 | 4.4 | 700 | 26 |
| basic | 4.5 | 4.3 | 622 | 23 |
| lit_tags | 4.5 | 4.1 | 586 | 21 |

ReleaseSafe: mumps 31.1, ruby 33.1, rig 13.5, zag 18.0 ms mean; the small
grammars are within 0.3 ms of the table.

With the DeRemer–Pennello lookaheads (1.0 LR core), same machine and
settings: mumps 7.6, ruby 7.8, rig 6.7, zag 7.0 ms mean; the small grammars
are unchanged (process start is ~4.5 ms). The lookahead phase itself went
from 23.7 ms to 0.3 ms on MUMPS and from 25.4 ms to 0.4 ms on Ruby.

### Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB);
  22,709 parse, the rest fail on known grammar gaps (capabilities.md §4.2).
- **rig**: one synthetic 3.8 MB file, the 362 Rig behavior tests and
  examples that parse on their own, concatenated and repeated.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 32,130,202 | 261.3 | 331 | 2380 | 36.3 | 22709 |
| rig | 1 | 3.8 | 980,288 | 11.3 | 341 | 73.6 | 52.2 | 1 |

ReleaseSafe: mumps lex 281 MB/s, parse 24.0 MB/s; rig lex 283 MB/s,
parse 33.0 MB/s.

Parsing costs about 9x lexing on MUMPS (13.5 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

### Node-store overhead

Measured at the codegen branch (after `f81d084`), ReleaseFast, the same
inputs as above: each grammar generated three ways (0.10.3; 1.0 plain; 1.0
with `--spans`), each parser run alternately, best parse time of 6-10
rounds of 3 (the machine was shared, load 6-8; single runs varied by ±3%).

| input | 0.10.3 ms | 1.0 plain ms | 1.0 `--spans` ms | spans overhead | nodes per byte |
|---|---:|---:|---:|---:|---:|
| mumps (VistA, 86.5 MB) | 2374 | 1747 | 1910 | +9.3% | 0.57 |
| rig (synthetic, 3.8 MB) | 72.8 | 62.1 | 64.1 | +3.2% | 0.12 |

The overhead is per list node (one 12-byte entry in the node store) plus
one start position per stack entry. MUMPS builds 46 M list nodes for 32 M
tokens (most of them untagged plumbing lists), so it pays about three
times Rig's rate; still, a MUMPS parser with spans is 20% faster than
0.10.3 without them. Trees are identical in all three builds (`--hash
--no-spans` over all 24,704 VistA routines and the 362 Rig sources, raw
tree and after Rig's `Parser` wrapper).

#### After reducing the store (1.0.0)

Three changes: an untagged list that is only ever spread into another list
(plumbing: the tails of `L(X)`, left-recursive lists spread into their
parent, ...) gets no node id, since nothing can reach it (the generator
decides per rule; MUMPS builds 27.7 M nodes instead of 49.0 M on VistA); a
reduction records only its rule and start (its end is `lastEnd`, and the
first element's start already sits on the span stack), with the span
stacks plain buffers sized with the value stack; node-store chunks of 128
entries instead of 1024 (most routines build ~1,100 nodes).

ReleaseFast, the same inputs, builds run alternately (min of 20 rounds for
MUMPS, 40 for Rig; the machine was shared, load 4-16, medians in
parentheses):

| input | 1.0 plain ms | `--spans` before ms | `--spans` now ms | overhead before | overhead now |
|---|---:|---:|---:|---:|---:|
| mumps (VistA, 86.5 MB) | 1735.9 (1831.1) | 1900.9 (1942.2) | 1816.5 (1855.6) | +9.5% | +4.6% |
| rig (synthetic, 3.8 MB) | 64.0 (68.8) | 66.5 (71.5) | 66.0 (70.3) | +3.9% | +3.1% |

Trees and spans are identical before and after on all 24,704 VistA
routines (`--hash`, with and without spans).

### Differential runs (for scale)

`test/diff legacy current` with the same MUMPS grammar over VistA + ORO
(50,976 routines, 179 MB): both parsers, 10 parallel chunks, 3 s of parsing,
14 s total including two ReleaseSafe parser builds. Rig's corpus (777 files):
5 s total.
