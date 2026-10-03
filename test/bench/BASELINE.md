# Benchmark baseline

The numbers `test/bench/run` produces for this checkout. Re-run it after
any change that could affect speed, compare with these tables, and update
this file when a change moves them.

Recorded with `test/bench/run` (ReleaseFast), Apple M5, 10 cores, macOS
27.0, Zig 0.17.0. Two full runs; differences between runs are about 0.5%
for parse throughput and 0.3 ms for generation.

## Generation time

20 runs per grammar, wall clock of the nexus process (started from perl
without a shell, so the time includes the process start of nexus itself).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 8.7 | 8.1 | 4562 | 420 |
| ruby | 8.5 | 8.0 | 3479 | 271 |
| rig | 8.4 | 7.6 | 4903 | 233 |
| zag | 7.6 | 7.0 | 2948 | 195 |
| slash | 5.8 | 5.6 | 2252 | 101 |
| nexis | 5.6 | 5.4 | 2169 | 87 |
| nexus | 6.2 | 6.0 | 3609 | 156 |
| features | 5.2 | 4.9 | 1611 | 61 |
| basic | 5.0 | 4.7 | 1494 | 57 |
| lit_tags | 4.9 | 4.6 | 1441 | 54 |

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB);
  22,709 parse to the end, the rest stop at gaps in em's MUMPS grammar.
- **rig**: one synthetic file of about 4 MB, Rig's behavior tests and
  examples that parse on their own, concatenated and repeated.

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
