# Benchmark baseline

The numbers `test/bench/run` produces for this checkout. Re-run it after
any change that could affect speed, compare with these tables, and update
this file when a change moves them.

Recorded with `test/bench/run` (ReleaseFast), Apple M5, 10 cores, macOS
27.0, Zig 0.17.0. Two full runs; differences between runs are about 0.5%
for parse throughput and 0.3 ms for generation.

## Generation time

20 runs per grammar, wall clock including process start (about 4.5 ms).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 19.1 | 18.7 | 4562 | 420 |
| ruby | 14.1 | 13.7 | 3479 | 271 |
| rig | 14.5 | 14.0 | 4903 | 233 |
| zag | 10.9 | 10.6 | 2948 | 195 |
| slash | 6.6 | 6.2 | 2252 | 101 |
| nexis | 5.7 | 5.4 | 2169 | 87 |
| nexus | 9.8 | 9.6 | 3609 | 156 |
| features | 5.2 | 4.9 | 1611 | 61 |
| basic | 5.1 | 4.8 | 1494 | 57 |
| lit_tags | 5.0 | 4.8 | 1441 | 54 |

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB);
  22,709 parse, the rest fail on known grammar gaps.
- **rig**: one synthetic 3.8 MB file, Rig's behavior tests and examples
  that parse on their own, concatenated and repeated.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 32,130,205 | 251.2 | 344.4 | 1706.0 | 50.7 | 22709 |
| rig | 1 | 3.8 | 954,993 | 10.5 | 366.4 | 65.0 | 59.0 | 1 |

Parsing costs about 7x lexing on MUMPS (18.8 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

## Reading a difference

Run each side at least twice and compare minimums; interleave A/B runs of
two binaries when the difference is small. When wall time moves but the
work should not have, compare hardware counters: `/usr/bin/time -l` on
macOS reports instructions retired and cycles elapsed (`perf stat -e
instructions,cycles` on Linux). A build that retires fewer instructions in
more cycles is a code-generation or layout effect, not more work.
