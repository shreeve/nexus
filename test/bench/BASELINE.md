# Benchmark baseline: Nexus 0.10.3

Recorded with `test/bench/run` (ReleaseFast unless noted) before the 1.0
revamp, at `a52aa4f` (generator identical to v0.10.3). Apple M5, 10 cores,
macOS 27.0, Zig 0.16.0. Re-run after any change that could affect speed and
compare; 1.0 must not be slower (SPEC §1.9, §5).

## Generation time

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

## Lexing and parsing throughput

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

## Node-store overhead

Not applicable: 0.10.3 records no node spans. When 1.0 adds the node store
(SPEC §4.2, target ≤ 5% parse-time overhead), measure it here by generating
the same grammar with and without spans.

## Differential runs (for scale)

`test/diff legacy current` with the same MUMPS grammar over VistA + ORO
(50,976 routines, 179 MB): both parsers, 10 parallel chunks, 3 s of parsing,
14 s total including two ReleaseSafe parser builds. Rig's corpus (777 files):
5 s total.
