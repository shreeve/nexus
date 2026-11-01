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
| mumps | 9.6 | 8.9 | 8130 | 1031 |
| ruby | 4.9 | 4.7 | 4678 | 451 |
| rig | 22.8 | 22.1 | 11706 | 1579 |
| slash | 1.5 | 1.4 | 3358 | 168 |
| nexis | 0.8 | 0.8 | 2605 | 111 |
| nexus | 3.0 | 2.9 | 4959 | 351 |
| features | 0.8 | 0.8 | 2698 | 111 |
| basic | 0.8 | 0.7 | 2602 | 107 |
| lit_tags | 0.7 | 0.6 | 2540 | 103 |

Generated modules hold their parse tables as literal arrays, which makes
them larger than the code that builds them would be and quicker to
compile. A grammar whose `@infix` table folds (rig, basic, features) runs
the LR stage twice: once on the chain, which every check sees, and once
on the folded table it generates from.

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB),
  parsed with em's schema-mode grammar (`grammars/mumps`); 24,646 parse to
  the end, the rest stop at gaps in the grammar.
- **rig**: Rig's behavior tests and examples that parse on their own
  (`~/Data/Code/rig`), listed again and again until the list holds about
  4 MB (6,168 small files). The per-file cost of a fresh parser weighs more
  on these short programs than on VistA's routines.

The MUMPS and Rig rows were recorded with the grammars `grammars/mumps` and
`grammars/rig` hold.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 35,634,361 | 232.3 | 372.5 | 1628.1 | 53.1 | 24646 |
| rig | 6168 | 4.9 | 1,209,984 | 35.3 | 138.7 | 95.0 | 51.4 | 6168 |

Parsing costs about 7x lexing on MUMPS (22 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

## Reading a difference

Run each side at least twice and compare minimums; interleave A/B runs of
two binaries when the difference is small. When wall time moves but the
work should not have, compare hardware counters: `/usr/bin/time -l` on
macOS reports instructions retired and cycles elapsed (`perf stat -e
instructions,cycles` on Linux). A build that retires fewer instructions in
more cycles is a code-generation or layout effect, not more work.
