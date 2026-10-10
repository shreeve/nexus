# Benchmark baseline

The numbers `test/bench/run` produces for this checkout. Re-run it after
any change that could affect speed, compare with these tables, and update
this file when a change moves them.

Recorded with `test/bench/run` (ReleaseFast), Apple M5, 10 cores, macOS
27.0, Zig 0.17.0, under a light load (about 3.6). Two full runs;
differences between runs are under 0.1% for MUMPS parse throughput, about
2% for Rig's, and up to 0.4 ms for generation.

## Generation time

20 runs per grammar, wall clock of the nexus process (started from perl
without a shell, so the time includes the process start of nexus itself).

| grammar | mean ms | min ms | output lines | output KB |
|---|---:|---:|---:|---:|
| mumps | 6.9 | 6.3 | 6745 | 896 |
| ruby | 4.6 | 4.4 | 3916 | 422 |
| rig | 6.0 | 5.8 | 5950 | 530 |
| slash | 2.8 | 2.6 | 2707 | 143 |
| nexis | 2.3 | 2.1 | 1995 | 84 |
| nexus | 3.4 | 3.1 | 4003 | 269 |
| features | 2.4 | 2.3 | 2061 | 82 |
| basic | 2.3 | 2.2 | 1965 | 79 |
| lit_tags | 2.2 | 2.1 | 1903 | 75 |

The process start of nexus is about 0.7 ms of each run (`nexus
--version`). Generated modules hold their parse tables as literal arrays,
which makes them larger than the code that builds them would be and
quicker to compile. A grammar whose `@infix` table folds (rig, basic,
features) runs the LR stage twice: once on the chain, which every check
sees, and once on the folded table it generates from.

## Lexing and parsing throughput

Best of 5 rounds, one thread, all input in memory, a fresh parser per file.
*lex* runs the lang `Lexer` wrapper over the generated `BaseLexer` to EOF;
*parse* is lexing + LR parsing + tree building (the raw grammar tree:
`parseRoutine` for MUMPS, `parseTree` for Rig).

- **mumps**: every routine in `em/misc/vista` (24,704 files, 86.5 MB),
  parsed with em's schema-mode grammar (`grammars/mumps`); 24,603 parse to
  the end, the rest stop at gaps in the grammar.
- **rig**: Rig's behavior tests and examples that parse on their own
  (`~/Data/Code/rig`), listed again and again until the list holds about
  4 MB (6,474 small files). The per-file cost of a fresh parser weighs more
  on these short programs than on VistA's routines.

The MUMPS and Rig rows were recorded with the grammars `grammars/mumps` and
`grammars/rig` hold.

| input | files | MB | tokens | lex ms | lex MB/s | parse ms | parse MB/s | parsed ok |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mumps | 24704 | 86.5 | 35,634,361 | 200.8 | 430.9 | 985.3 | 87.8 | 24636 |
| rig | 6474 | 3.9 | 1,208,142 | 22.7 | 170.0 | 52.9 | 72.9 | 6474 |

Parsing costs about 4.9x lexing on MUMPS (36 M tokens/s end to end), so
parser-side work (tables, reductions, tree building) dominates.

## Reading a difference

Run each side at least twice and compare minimums; interleave A/B runs of
two binaries when the difference is small. When wall time moves but the
work should not have, compare hardware counters: `/usr/bin/time -l` on
macOS reports instructions retired and cycles elapsed (`perf stat -e
instructions,cycles` on Linux). A build that retires fewer instructions in
more cycles is a code-generation or layout effect, not more work.
