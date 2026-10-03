# Benchmark baseline

The numbers `test/bench/run` produces for this checkout. Re-run it after
any change that could affect speed, compare with these tables, and update
this file when a change moves them.

Recorded with `test/bench/run` (ReleaseFast), Apple M5, 10 cores, macOS
27.0, Zig 0.17.0. Two full runs; differences between runs are about 0.5%
for parse throughput and 0.1 ms for generation.

## Generation time

20 runs per grammar, wall clock of the nexus process (started from perl
without a shell, so the time includes the process start of nexus itself).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 5.2 | 4.8 | 4693 | 691 |
| ruby | 4.3 | 4.1 | 3844 | 421 |
| rig | 4.0 | 3.7 | 5185 | 399 |
| zag | 3.8 | 3.5 | 3331 | 324 |
| slash | 2.6 | 2.5 | 2635 | 139 |
| nexis | 2.5 | 2.3 | 2566 | 104 |
| nexus | 3.1 | 2.9 | 3931 | 265 |
| features | 2.2 | 2.0 | 1991 | 79 |
| basic | 2.2 | 2.1 | 1880 | 74 |
| lit_tags | 2.1 | 1.9 | 1831 | 71 |

The process start of nexus is about 0.7 ms of each run (`nexus
--version`). Generated modules hold their parse tables as literal arrays,
which makes them larger than the code that builds them would be and
quicker to compile.

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB);
  22,709 parse to the end, the rest stop at gaps in the suite's MUMPS
  grammar (`test/mumps`).
- **rig**: one synthetic file of about 4 MB, Rig's behavior tests and
  examples that parse on their own, concatenated and repeated.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 32,130,205 | 249.2 | 347.2 | 1323.3 | 65.4 | 22709 |
| rig | 1 | 3.9 | 958,815 | 10.9 | 354.0 | 57.2 | 67.5 | 1 |

Parsing costs about 5x lexing on MUMPS (24 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

## Reading a difference

Run each side at least twice and compare minimums; interleave A/B runs of
two binaries when the difference is small. When wall time moves but the
work should not have, compare hardware counters: `/usr/bin/time -l` on
macOS reports instructions retired and cycles elapsed (`perf stat -e
instructions,cycles` on Linux). A build that retires fewer instructions in
more cycles is a code-generation or layout effect, not more work.
