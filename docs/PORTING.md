# Porting a grammar from 0.10.3 to 1.0

Nexus 1.0 does not read 0.10 grammar files unchanged, but most grammars need
only a handful of edits, and their trees need none: without `@schema`, 1.0
builds the same trees from the same actions. `v0.10.3` is tagged; a
language keeps generating with it until its port is done.

The in-repo grammars (MUMPS, Zag, Ruby, Slash, Nexis, and Rig's 0.10-shape
grammar) run on 1.0 this way, schema-less. For MUMPS the claim is checked
at scale: over all 24,704 VistA routines, the parser Nexus 0.10.3
generates from em's grammar and the parser Nexus 1.0 generates from
`test/mumps/mumps.grammar` give the same tree (22,709 files) or the same
parse error (1,995 files).

The port has two independent steps: run on 1.0 (this list), then, when the
language wants it, adopt `@schema` ([SEMANTICS.md](SEMANTICS.md)).

## What changed

Generation tells you about every item below that affects a grammar: each is
a located error, or a difference `test/diff` shows.

### The @lexer section

| 0.10.3 | 1.0 | What to do |
|---|---|---|
| patterns read by shape; unsupported rules skipped with a warning | a real regular-expression compiler; anything outside the [pattern language](GRAMMAR.md#patterns) is an error | fix or delete the rules it names |
| `counting()`, `matching()`, `rewind()` rules kept as documentation of a wrapper | `counting()`/`matching()` are rejected; `rewind(n)`, `hold` and trailing context `r1 / r2` are compiled | express bounded lookahead with `/`; leave nesting to the wrapper |
| token names had behavior (`ident`, `integer`, `real`, `string_*`, `comment` got special scanners) | names carry no behavior; patterns say everything, escapes included | spell escapes in the pattern: `'"' ([^"\\\n] \| '\\' .)* '"'` |
| `.` was documented as any byte except newline | `.` matches any byte, newline included | write `[^\n]` where newline must not match |
| a rule shadowed by earlier ones was dead | an error naming the rule that wins and an example text | delete or reorder it |
| a pattern could start with a space or tab | an error: the lexer consumes those first, as `pre` | use a zero-width rule: `@ pat & pre > 0 → patend, hold, {pat = 0}, {pre = 0}` |

### The @parser section

| 0.10.3 | 1.0 | What to do |
|---|---|---|
| `@conflicts = N` | an `@conflicts` block: one entry per conflict, each with a `# reason` | delete the line, generate, paste the printed block, write the reasons |
| conflict counts included start-marker artifacts and missed list-separator conflicts | exact | the new counts differ; that is expected |
| `(tag ...N M)` built `(tag M ...N)` | the order written | to keep a 0.10 tree, write `(tag M ...N)` |
| action positions of two digits could be misread | any position | none |
| some `X "c"` hints were silently ignored | every hint is applied; one that decides nothing is an error | delete the dead hints it names |
| `>` was lost on the expansions of an `[opt]` group | kept | some conflicts disappear from the manifest |
| a start symbol with several alternatives parsed only the first | all | none |
| a grammar without `@lang` generated a parser that did not compile | compiles, and exports `Parser` | none |
| `@code LOCATION { zig }` injected code into the module | removed (a syntax error) | move the code into the lang module; `@code = fn` in the @lexer section remains |
| `@errors` names were not used | syntax errors name expected rules and tokens | add `@display` for tokens |
| generator errors in several formats, some with exit 0 | `file:line:col: error:`, exit 1, nothing written | none |

`@as`, `@op`, `@infix`, `@lang`, start symbols, aliases, `[opt]`, `L(X)`,
quantifiers, `!X`, `~N`, `<`, `>`, and lexer states, guards, `after`,
`counted()`, zero-width rules and `@code = fn` keep their meaning. `@as
ident = [...]` still works (the token may also be written `IDENT`), and
token classification is unchanged: a terminal declared in `tokens` (or
produced by a lexer rule) arrives directly, any other capitalized terminal
only through `@as`.

### The generated module

| 0.10.3 | 1.0 | What to do |
|---|---|---|
| `Sexp.list: []const Sexp` | `Sexp.list: List` (`items()`, and a node `id`) | `.list => \|items\|` becomes `.list => \|l\|` with `l.items()`, or use `sexp.items()`; `sexp.kind()` / `isKind(.tag)` read the head |
| `src.id` = the `@as` keyword's enum value, else the lexer's `aux` | the same | none |
| trailing nils dropped | the same without `@schema`; with `@schema`, nodes have fixed width | none (until `@schema`) |
| `parseX(allocator, source)`, `Parser`, `BaseParser`, `Lexer`, `BaseLexer`, `Tag` from the lang module | the same, plus `Role`, `Start`, `parse(start)`, `span`, `lastError`, `writeError` | none |

## Checking a port: test/diff

`test/diff` generates a parser from each of two (Nexus, grammar) pairs,
parses a corpus with both, and compares the trees file by file. Pair each
binary with its own grammar version: `legacy` (Nexus 0.10.3, built from the
tag on first use) reads only the old grammar, `current` only the new one.

```bash
test/diff --lang-old ~/Data/Code/em/src/mumps.zig --lang-new test/mumps/mumps.zig \
    legacy current ~/Data/Code/em/mumps.grammar test/mumps/mumps.grammar \
    --ext .m ~/Data/Code/em/misc/vista
```

```text
result            files
same              22709
same_error         1995

24704 files, 24704 same, 0 differ  (parse 1s, total 8s)
```

`--start` picks the start rule (`parseProgram` to compare after a lang
`Parser` wrapper), `--expect FILE` lists files that differ on purpose,
`--show N` prints tree diffs, `--keep DIR` keeps everything. See
[test/README.md](../test/README.md#differential-testing).

## How Rig was ported

Rig moved to 1.0 and to schema mode in one branch (`nexus-1.0` in the Rig
repository), in this order:

1. **The grammar.** `@schema` declares all of Rig's IR kinds; actions became
   role-named (`→ (set)`, `→ (set op:fixed)`) with labels in the patterns
   (`target:postfix "=" value:tail`); `@display` and `@errors` name tokens
   and rules for messages; `@conflicts = 0` went away (no block: no
   conflicts).
2. **The padding went.** Rig's `Parser` wrapper used to pad every node to a
   fixed arity (`src/ir.zig`); the schema guarantees that, so the file was
   deleted and slots that were always empty were dropped from the schema.
3. **Reads by role.** Every compiler pass reads the tree through
   `parser.ir` (`ir.Set.target(node)`, `ir.rest(node, .stmts)`) and
   `Sexp.kind()`, never by index.
4. **Spans.** Diagnostics are reported at node spans; sema keys its facts by
   node id; `rig check --facts` prints `writeFacts`.
5. **The wrapper builds through the contract.** The closure rewrite builds
   its `captures` node with `newNode` and places slots with `ir.slot`;
   a compound assignment's `op` tag comes from the matched operator
   (`op:("+=" | "-=" | ...)`).

The trees changed on purpose (dropped empty slots, nested nodes where the
wrapper used to build them), so a tree diff against the 0.10.3 grammar
shows differences by design; Rig's own suite, whose IR goldens
(`test/ir/*.sexp`) changed with the port, is the check.

## Checklist for MUMPS (em)

`test/mumps/mumps.grammar` is em's grammar ported to 1.0, and `test/diff`
above shows it builds the same trees. What remains is em's side:

1. Copy `test/mumps/mumps.grammar` over `em/mumps.grammar` (its differences
   from em's: `/` trailing-context rules instead of the documentation-only
   `counting()`/`matching()`/`rewind()` rules; a zero-width `patend` for
   whitespace in pattern mode; pattern-mode numbers guarded ahead of the
   others; the `@conflicts` block; `(setmulti value:5 ...2)`; dead `X ":"`
   hints removed; `posformat` split in two alternatives).
2. Regenerate `src/parser.zig` with 1.0 and fix em's reads of
   `Sexp.list` (now a `List`: `items()`); nothing else in the tree changed.
3. em reads nodes by position and relies on trailing nils being dropped
   (`(ref label offset routine)`): that is still the default without
   `@schema`, so these reads stay as they are.
4. `src.id` keeps its contract: a keyword's `CmdId`/`FnId`/`IsvId`/`SsvnId`
   value (the ranges tell them apart; values below 512), else the lexer's
   `aux`, which `mumps.zig` sets to the dot level of a line.
5. Run em's tests, and `test/diff` over VistA and ORO with em's own
   `mumps.zig` on both sides.
6. Later, and separately: `--spans` for node spans (no tree change), then
   `@schema` (fixed-width nodes: em's positional reads become `ir`
   accessors, as Rig's did).
