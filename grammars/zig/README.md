# Zig 0.17.0 in Nexus

`zig.grammar` is the syntax of Zig 0.17.0 written as one
[Nexus](../../README.md) grammar. Nexus generates from it a single
standalone Zig module, with no runtime dependency: a DFA lexer, an
LALR(1) parser, and a typed tree whose kinds and roles are those of
`std.zig.Ast`. The grammar is written to agree exactly with Zig's own
front end (`lib/std/zig/tokenizer.zig`, `Parse.zig`, `Ast.zig`), and the
tools in this directory check, input by input, that it does: the same
tokens, the same inputs accepted and rejected, and the same tree, node for
node and span for span.

This page is for the Zig team: what the grammar is, the evidence that it
is equivalent to `std.zig`, what it costs to run, and how it could be of
use to Zig.

## What is here

| File | Role |
|---|---|
| `zig.grammar` | the grammar: lexer, `@schema` (the tree), conflicts, rules in grammar.peg's sections and names |
| `zig.zig` | the lang module: a Lexer wrapper that skips a byte order mark and gives the token categories Parse.zig decides by looking past the next token |
| `cases/` | hand-written inputs and their expected trees (`reject_*`: inputs Ast.parse rejects, one per kind of mistake; `tolerant_*`: broken inputs parsed with `parseTolerant`, run with the `.args` file's `--tolerant N`); `cases/tokens/` the token stream |
| `tokens_test.zig` | the lexer against `std.zig.Tokenizer`, on inputs it holds |
| `trees_test.zig` | the tree against `std.zig.Ast`, on inputs that use every kind and role |
| `messages_test.zig` | the wording of syntax errors |
| `trees.zig` | the canonical form both trees are printed in, and the rules that map one onto the other |
| `compare-tokens`, `compare-accept`, `compare-trees` | the three comparisons, over any set of files (`tools/`) |
| `compare-scopes` | the names `@lsp` resolves against AstGen's resolution ([Names and scopes](#names-and-scopes)) |
| `compare-members` | the members and imports `@lsp` resolves against a resolution over std.zig.Ast ([Names and scopes](#names-and-scopes)) |
| `members/` | files that import each other and std, for `compare-members` |
| `editor/` | the language server's `hooks.zig`, `install` (the VS Code extension in one command), its sessions, and the tools that time it ([The language server](#the-language-server)) |
| `server/` | a session of the server with the stub `hooks.zig`: the colours of `@lsp` |
| `project/` | the files the sessions of `editor/` and `server/` open |

`./test/run zig` runs the cases, the three `_test.zig` files,
`compare-scopes` on the cases, `compare-members` on the cases and
`members/`, the sessions of `editor/` and `server/`, and
`editor/install` up to the package ([Installing it](#installing-it)); the
`compare-*` scripts run the same comparisons over a corpus. Each script
documents its options (`-h`).

## How the grammar is written

Rules follow `doc/langref/grammar.peg`, section by section (TOP LEVEL,
BLOCK LEVEL, EXPRESSION LEVEL, ASSEMBLY, HELPER GRAMMAR), and a rule for a
construct grammar.peg names takes its name in snake_case: `BoolOrExpr` is
`bool_or_expr`. Where grammar.peg and Parse.zig disagree, the grammar
follows Parse.zig, since it is what the compiler runs. grammar.peg is a
PEG over bytes: operator spacing, `&&` and the newline before a doc
comment are lookaheads on characters there, which the Lexer wrapper below
turns into token categories here; the `reject_*` cases cover each.

Parse.zig is predictive: it commits to a reading after a token or two and
never backtracks. Where LALR(1) would decide later and accept more, the
grammar writes the commitment as a restricted variant of a rule, named by
a suffix (`expr_s` for an expression statement, which starts with no
keyword a statement starts with; the `_k` operands, which do not end in an
open `return x`, `if` or loop; and so on, each explained where it is defined).
Where Parse.zig decides by looking further than one token, or at the bytes
around a token, the Lexer wrapper in `zig.zig` makes the decision and
names the token by it: an identifier before `:` and `{`, `while`, `for`,
`inline` or `switch` is a `label`; a binary operator with whitespace on
one side only is a prefix category or `bad_operator`; and five more, each
documented in `zig.zig`. Every LR conflict the grammar has is declared in
`@conflicts` with its reason in Zig terms (`return - x` returns `-x`; a
switch prong's leading `inline` is the prong's), and resolves as
Parse.zig does.

The heads of a for, a function and a variable declaration (grammar.peg
ForPrefix, FnProto, VarDeclProto) are rules of their own, each spread
into the roles of the node that holds it (`→ (for 1 3 ...4 5)`). The
heads of if and while are written out in each form: they end in parts
that may be absent, and as rules of their own they would make a syntax
error right after the `)` list every token any form can take, where
written out it names what that form waits for. Spans are Ast's: a span
mark leaves a statement's `;` (`-";"`) and the doc comments before a
declaration, field, parameter or error name (`-[docs]`) out of the span
of its node, and a statement that ends in another one ending in `;`
(`if (a) b else c;`) takes the `;` at the top, so no node spans it.

The grammar has 130 tokens (333 DFA states) and 218 rules, which expand
to 983; the parser has 1,871 LR states and 32 conflict cells in 9
declared entries. Nexus generates the 2.1 MB module in 0.11 s.

## Equivalence

Each comparison runs the Zig 0.17.0 standard library in process as the
reference, so the Zig that runs a script must be 0.17.0. The corpus is
every `.zig` file in the Zig 0.17.0 source tree (`lib/`, `src/`, `test/`,
`doc/`): 2,620 files, 71.47 MB.

| Check | Inputs | Differences |
|---|---|---|
| tokens: tag, start and end of every token, invalid tokens included | the corpus: 12,805,547 tokens; 4,000,000 random inputs (`--fuzz`, seeds 0 and 1) | 0 |
| accept: a whole file parses, or it does not (`Ast.parse` with `.recover = false`) | 3,134: the corpus, and the 514 sources `parser_test.zig` and `parser_fuzz.zig` pass to `testCanonical`, `testTransform`, `testError` and `checkAgainstOracle`; 150,000 token-edit mutants of them | 0 |
| trees: every node, its kind, roles and span | the 3,036 of those 3,134 that both accept; 300,000 token-edit mutants, of which 56,114 are accepted by both and compared | 0 |

A mutant is a piece of a seed file with one to four token edits (delete,
duplicate, swap, insert a keyword or operator); most mutants are
rejected, and the two parsers must agree on every one. The suite runs
the same token and tree comparisons on the inputs `tokens_test.zig` and
`trees_test.zig` hold, so a change that breaks either fails `./test/run`.

### How the two trees are compared

`std.zig.Ast` and the Nexus tree describe the same parse in different
representations, so `trees.zig` prints both in one canonical form (the
grammar's `@schema`: kinds, named roles, spans, `text@position` leaves)
and compares them as text. The Nexus tree is printed as it is, spans
included. Nine rules map Ast's onto it; each is a difference of
representation, stated in full in `trees.zig`:

- T1: the kinds Ast has no node for (`param`, `capture`, `field_init`,
  `error_name`) are built from Ast's tokens and `full*` helpers.
- T2: facts Ast keeps only as tokens (labels, `pub`, `extern "c"`,
  `inline`, `comptime`, pointer qualifiers, doc comments, ...) become roles.
- T3: a destructure's leading `comptime` is the destructure's.
- T4: one-token nodes (`identifier`, `number_literal`, ...) are leaves.
- T6: a pointer keeps every `const`, `volatile` and `allowzero` token, as
  Parse.zig accepts any number of each; `full.PtrType` keeps the last.
- T5, T7, T8, T9: four corrections to `std.zig.Ast` helpers that, on
  some inputs, report a node different from the one Parse.zig built: a
  `name:` after `.` or `break :` taken as a label (T5); the last token of
  an empty `enum(T) { //! ... }` (T7); a label found on a loop type after
  a parameter, field or variable `name:` (T8); a switch prong's `inline`
  credited to its first item (T9). These are bugs in the helpers, not in
  Parse.zig, and each makes `zig fmt` change or break the program it
  formats (`[.x: {}]u8` becomes `[.x.x: {}]u8`).

## Long tokens

A Nexus token's length is 16 bits, and `std.zig.Tokenizer` has no limit:
one corpus file, `test/cases/maximum_sized_integer_literal.zig`, has an
integer literal of 65,537 bytes. The grammar has `@longtokens`, so a token
over 65,534 bytes keeps its tag, and the parser has its whole extent: the
literal is one `number_literal`, as in std.zig, and the file's tokens,
acceptance and tree are std.zig's (`cases/maximum_sized_integer_literal.zig`,
and its token stream in `cases/tokens/`).

## Syntax errors

A Nexus parser stops at the first syntax error and reports
`line:col: expected X, Y or Z after R, got W`
([SEMANTICS.md, "Syntax errors"](../../docs/SEMANTICS.md#syntax-errors)):
what the parser can take once the constructs before the error are
complete, after the last one the grammar names, at the end of the line
before when the offending token starts a later line. The grammar names
tokens as `std.zig.Token.Tag.symbol()` does (`';'`, `'fn'`, `an
identifier`, `EOF`) and the places that wait for an expression, a type
expression, a statement, a block, a declaration or a parameter by that
name (`@display`, `@errors`). Where Parse.zig has a message of its own
for a mistake, the grammar gives it by example in `@messages`
([GRAMMAR.md, "Messages"](../../docs/GRAMMAR.md#messages)): 31 entries
for a statement, declaration, argument, parameter, field or switch prong
that runs into the next line, chained comparisons, bit ranges and
`align` where Zig forbids them, `==` for `=` in a declaration, a
parameter after `...`, a function prototype with no `;` or body,
declarations between fields, doc comments on nothing, on tests and on
`comptime` blocks, and an operator with whitespace on one side only
after a field. Side by side with Ast's message, for inputs of
`messages_test.zig`, which checks each one's line and column, and its
text where `@messages` gives it:

```text
const x = ;
  nexus  1:11: expected an expression, got ';'
  zig    1:11: expected expression, found ';'
const std = @import("std")
pub fn main() void {}
  nexus  1:27: expected ';' after declaration
  zig    1:27: expected ';' after declaration
test {
    f(a b);
}
  nexus  2:9: expected ',' after argument
  zig    2:9: expected ',' after argument
const x = a == b == c;
  nexus  1:18: comparison operators cannot be chained
  zig    1:18: comparison operators cannot be chained
```

Over the 98 inputs both parsers reject (39 corpus files and 59 inline
sources), `compare-accept --messages` prints both messages: 95 of
Nexus's name at most six expected items or are a message of
`@messages`, 88 are at the line and column Ast reports, and 43 are Ast's
text word for word (without `@messages`: 89, 88 and 0). The rest fall
short of Ast's in ways the grammar cannot change:

- **Position.** Ast reports some mistakes at an earlier token than the
  one the parser cannot take (a declaration between container fields, a
  doc comment on a test or a `comptime` block, an `extern` function with
  a body); `@messages` can name such a mistake, not move it.
- **One state, several mistakes.** A message keys on a parser state and
  a token. The items of `.{ 1, 2 }` are parsed in the states of an
  argument list, so they take its message, or none; an `if` statement
  whose `else` branch has an assignment body is one state whether Ast
  then expects `';'` or `';' or 'else'`; and an `&` before `&` (`&&`) is
  the same token as an `&` with whitespace on one side only, which Ast
  words differently, so neither has an entry. An operator with
  whitespace on one side only that the lexer cannot read as a prefix one
  is BAD_OPERATOR, whose text a message cannot name.
- **Recovery.** The strict parser stops at the first error, where
  Ast.parse can recover and go on; the grammar's `@repair` section gives
  Nexus's tolerant parser (`parseTolerant`) a different recovery, for
  editors, that reports every error it repairs past, each worded as the
  strict parse words it, as the `tolerant_*` cases show
  (`tolerant_errors`: three separate mistakes, three errors, though
  `g(a b c d)` deletes three tokens).

## Names and scopes

The grammar's `@lsp` ([GRAMMAR.md, "Names and
scopes"](../../docs/GRAMMAR.md#names-and-scopes)) declares Zig's
lexical names: a file and a container are unordered scopes, a function,
a test, a block and the nodes that hold captures are ordered ones; a
function's name belongs to the scope around it, its parameters to the
function; fields, enum and error names are members, never names in
scope; a builtin's name, an enum literal, a field initializer's name, an
asm operand's name and a label after `break`/`continue` are not looked
up. `@import("x.zig")` imports the file beside the importing one, and
`@import("std")` the file of a module, which the client's `modules`
setting names (`{"std": "/path/to/lib/std/std.zig"}`). A name after `.`
is a member of what is before it: a file, a container, or what a
constant's value or a name's declared type denotes, so `std.mem.eql`
resolves in three steps, through std.zig and mem.zig, and `p.x` with
`p: Point` through `Point`. A value whose type needs inference (a call's
result, a generic like `std.ArrayList(u8)`, a pointer, `@This()`)
answers nothing. The language server `nexus --editor` writes gives the
outline, definition, references, highlights, rename, the names in scope
and after `.`, and hover from it, across files, with no code of its
own.

`compare-scopes` checks every name the index resolves against the
compiler's own resolution, `std.zig.AstGen` (the Zig that runs it, which
must be 0.17.0). For each input AstGen accepts, it renames every
definition the index makes in a scope chain, and every use the index
resolves to it, to a name of its own (`_cs7`), and runs AstGen on the
renamed file: a use the index resolves elsewhere than the compiler does
makes AstGen report an undeclared or unused name there. A use the index
leaves unresolved must be a primitive (`std.zig.primitives`) or `_`.
Over the `.zig` files of Zig's source at tag 0.17.0 (2,713 files AstGen
accepts; the other 227 are compile-error tests):

| | count |
|---|---:|
| definitions in scope chains | 286,137 |
| member definitions (fields, enum and error names) | 108,466 |
| uses resolved, each to the definition AstGen resolves it to | 951,390 |
| uses that are builtins (the `builtin` names, `_`) | 452,582 |
| other primitives (`u7`, `i33`, ...), unresolved by design | 19,914 |
| names not looked up here (members, labels, enum literals, field names) | 1,623,669 |
| disagreements | 0 |

The index of all 72.1 MB took 1.3 s in safe mode, single thread.

`compare-members` checks every member and import the server resolves
across files, against a resolution of its own over `std.zig.Ast` that
never asks the engine: the declarations of each container, an
identifier as the nearest enclosing container's declaration of its
name, `@import` as a file (`std` the standard library of the Zig that
runs it, another name a path beside the importing file), and a
declaration's value, else its type, as what it denotes. A member the
engine resolves and the reference cannot reach (its chain starts at a
local or a parameter) must be a declaration of that name in the file it
names. Over the same 2,898 files Ast.parse accepts:

| | count |
|---|---:|
| members (names after `.`) | 517,626 |
| resolved in their own file, as the reference resolves them | 17,466 |
| resolved through imports into other files, as the reference resolves them | 126,481 |
| resolved where the reference cannot reach, each a declaration of its name | 47,834 |
| unresolved by design (a call's result, a generic, a pointer, `@This()`, a local's inferred type) | 325,845 |
| missed (the reference resolves them, the engine does not) | 0 |
| wrong | 0 |
| imports resolved, each to the reference's file | 4,809 |
| imports unresolved (`builtin`, `root`, `build_options` and other modules not given) | 688 |
| imports wrong | 0 |

Over std alone (563 files) 57,564 members resolve, 48,271 of them
through imports, and none is missed or wrong.

## The language server

`nexus --editor` turns the grammar into a VS Code extension and a
language server ([docs/LSP.md](../../docs/LSP.md)). The grammar alone
gives the server its colours, folds, selections, keywords and, from
`@lsp`, the names above. `editor/hooks.zig` adds what only Zig knows, by
running the standard library of the Zig that builds the server (0.17.0)
in process:

- **Zig's own errors as you type.** Every error `std.zig.Ast.parse`
  reports, with its recovery, in Zig's words and at Zig's positions (a
  missing `;` at the end of the token before it); in a file that
  parses, `std.zig.AstGen`'s errors, as `zig ast-check` reports them:
  unused and shadowing names, a `var` never mutated, an undeclared
  identifier, each with its notes. `zig ast-check` prints the first
  syntax error alone; the server shows every error Ast.parse's recovery
  reports.
- **Format Document** as `zig fmt` formats (`Ast.render`). It refuses a
  file with syntax errors, as `zig fmt` does, and any edit after which
  the grammar's parser rejects the text or builds another tree from it
  (spans aside, and a name unquoted and the blanks at the end of a doc
  comment dropped, as `zig fmt` writes them). That guard catches the four
  helper bugs T5, T7, T8 and T9 above, each of which makes `zig fmt`
  change the program. Over the 2,910 `.zig` files of Zig 0.17.0's
  source, each with its leading blanks halved, a blank at the end of
  every line and CRLF line ends, the 2,868 that parse are formatted but
  14, each refused for a rewrite `zig fmt` makes on purpose:
  `@intFromEnum` to `@backingInt`, `@enumFromInt(x)` to
  `@fromBackingInt(@intCast(x))` and `callconv(.@"inline")` to
  `inline` change the tree; `zig fmt` itself formats those.
- **`std` is Zig's own.** `@import("std")` is the `std.zig` of the Zig
  that built the server, in the `std_dir` of the `zig env` output that
  `editor/install` saves beside the server (`bin/zig-env.zon`), so it
  resolves when VS Code starts without `zig` on its `PATH` (from the
  Dock on macOS). Without that file, or when the Zig it names is gone,
  it is the `std_dir` of the `zig` on the server's `PATH`; the
  `nexus-zig.server.modules` setting overrides both. The server asks
  once, when it first meets the import. Definition, references, hover
  and completion go through it into the standard library: hover on
  `std.mem.eql` shows its prototype and doc. When neither gives one, the
  server logs it once in its output ("Zig (Nexus)"), with the setting
  to set and why: VS Code started from the Dock does not get a shell's
  `PATH`, so a `zig` that mise or a shell profile puts on it is not on
  the server's. `builtin` and `root`, the compilation's own modules,
  are never logged; another module a `build.zig` declares is, with the
  setting.

What it does not do: anything that needs types. A value's members
whose type needs inference (`list.` for an `std.ArrayList(u8)`, a
call's result, `@This()`), a value's type on hover, and
`@import` of a module a `build.zig` declares (unless `modules` names
its file) answer nothing, rather than guess; type errors come from the
check ([Type errors on save](#type-errors-on-save)). It is a demonstration
of what a grammar and a page of hooks give a large language, not a
replacement for ZLS, and the extension is not published.

`./test/run zig` builds this server and replays the sessions of
`editor/` on the files of `project/`: Zig's errors as you type
(`errors.session`), formatting and its guard on each of the four bugs
(`format.session`), and names across files and into std, with
completion after `list.` answering nothing (`names.session`). It runs
`editor/install --no-package` too (`zig/install`), into a directory of
its own, once in each mode: the server it builds, with no `zig` on its
`PATH`, answers `names.session` as above, std included, and without
`zig-env.zon` too logs that std names no file, with the hint
(`nozig.replay`, a session only that check replays); and without
`bin/nexus`, or with a `zig` that is not 0.17.0, it stops and writes
nothing. With `NEXUS_TEST_PACKAGE=1` set, that check packages the
extension too (`npm install` and `vsce`, which fetch from the network
the first time): `vsce` packages it without a warning, and the `.vsix`
holds 9 files, the client bundled into `dist/extension.js` (which loads
with only `vscode` outside it), and no `node_modules`.

### Installing it

```bash
grammars/zig/editor/install          # into ~/nexus-zig; `install DIR` names another directory
```

It needs Zig 0.17.0, Node.js (`node`, `npm`, `npx`) and VS Code's
`code` command on `PATH` (in VS Code, "Shell Command: Install 'code'
command in PATH"), and this checkout's `bin/nexus` (`zig build
-Doptimize=safe` at the repository root), which it never builds
itself. It says which one is missing, and stops, before it writes
anything. Then it prints a line for each step, writes each step's
output to `install.log` in the directory, and stops at the first that
fails, with the end of that log:

1. **mode**: `companion` when `code --list-extensions` lists the
   official Zig extension, `ziglang.vscode-zig`, else `standalone`
   (`--companion` and `--standalone` choose), written into
   `vscode/identity.json`, with `"provider": "ziglang.vscode-zig"` in
   `companion` mode;
2. **generate**: `bin/nexus --editor --lang zig.zig zig.grammar` into
   the directory;
3. **hooks**: `editor/hooks.zig` in place of the stub;
4. **build**: the server, `zig build -Doptimize=safe --prefix
   ../vscode`, into `vscode/bin/zig-lsp`, and that Zig's `zig env`
   beside it, `vscode/bin/zig-env.zon`, where the server finds std;
5. **npm** and **package**: `npm install --ignore-scripts` and `vsce
   package`, which bundles the client into `dist/extension.js` with
   esbuild first, into `vscode/nexus-zig-0.1.0.vsix` (`--no-package`
   stops before them);
6. **install**: `code --install-extension ... --force`
   (`--no-install` stops before it, and VS Code is not touched).

Each run does every step again, so after a `git pull` the same command
brings the installed extension up to date; then run "Developer: Reload
Window" in each VS Code window.

The extension is `nexus-local.nexus-zig`, "Zig (Nexus)", with settings
under `nexus-zig.`: none of it is the official extension's, so the two
install side by side. The recommended setup is beside it: install
`ziglang.vscode-zig` first, and `install` chooses `companion` mode,
in which the official extension keeps the language, its colouring,
its commands and ZLS, and this one adds its server. VS Code then runs
both servers on every Zig file and shows both servers' diagnostics;
`"zig.zls.enabled": "off"` in VS Code's settings shows this one's
alone. Without the official extension, in `standalone` mode, this one
contributes the `zig` language, its colouring and the server. A
`companion` installed after the official extension is uninstalled
(VS Code then knows no `zig` language, and calls a `.zig` file
whatever it guesses) says so when VS Code starts, and starts no
server: run `install` again, which chooses `standalone`.

By hand, the same steps are these (`companion` mode: `"mode":
"companion"` and `"provider": "ziglang.vscode-zig"` in
`~/nexus-zig/vscode/identity.json` before `--editor`):

```bash
cd grammars/zig
../../bin/nexus --editor --lang zig.zig zig.grammar ~/nexus-zig
cp editor/hooks.zig ~/nexus-zig/server/src/hooks.zig
cd ~/nexus-zig/server && zig build -Doptimize=safe --prefix ../vscode
zig env >../vscode/bin/zig-env.zon
cd ../vscode && npm install --ignore-scripts
npx @vscode/vsce package --skip-license --allow-missing-repository
code --install-extension nexus-zig-0.1.0.vsix --force
```

`--editor` writes `hooks.zig` and `identity.json` only when they are
missing, and every other file on each run, so `editor/hooks.zig` is
copied again whenever it changes. Without `zig-env.zon`, the server
takes std from the `zig` on its `PATH`, or from the setting
`"nexus-zig.server.modules": {"std": "/path/to/lib/std/std.zig"}`.

### Latency

On Zig 0.17.0's `src/Sema.zig` (1.55 MB, 35,648 lines), with the
server in safe mode (`-Doptimize=safe`) on an Apple M5, the
1-minute load average below 6, best of five:

| | ms |
|---|---:|
| `parseDiagnostics` (Ast.parse and AstGen) | 41 |
| `format`, the file formatted already (Ast.parse, Ast.render) | 17 |
| `format`, the whole file reformatted (and both parsed again for the guard) | 49 |
| open the file, to its diagnostics published | 66 |
| an edit, to its diagnostics published | 43 |
| hover, definition, document highlight | 1 to 2 |
| completion of the names in scope (735) | 2.3 |
| outline | 13 |
| folding ranges | 35 |
| semantic tokens, the whole file | 82 |
| Format Document, one blank removed | 52 |
| references of `Value` across `src/` (285) | 266 |

On `src/codegen/x86_64/CodeGen.zig`, 11.1 MB, `parseDiagnostics` takes
170 ms and `format` 233 ms, or 511 ms reformatting the whole file.
`editor/measure.zig` times the two hooks and counts what `format` does
over a corpus (the counts above); `editor/latency` times the server's
requests. With the editor files in `~/nexus-zig` as above, and `Z` a
checkout of Zig at tag 0.17.0:

```bash
cp editor/measure.zig ~/nexus-zig/server/src/
(cd ~/nexus-zig/server && zig build-exe -O safe src/measure.zig)
~/nexus-zig/server/measure -n 5 $Z/src/Sema.zig $Z/src/codegen/x86_64/CodeGen.zig
~/nexus-zig/server/measure -n 5 -r $Z/src/Sema.zig
find $Z/lib $Z/src $Z/test $Z/doc -name '*.zig' -print0 |
    xargs -0 -n 5000 ~/nexus-zig/server/measure -q -r -t -c
editor/latency ~/nexus-zig/vscode/bin/zig-lsp $Z/src Sema.zig
```

### Type errors on save

The compiler is the only source of Zig's type errors. The server asks it
through the check of the generated server ([docs/LSP.md, "The
check"](../../docs/LSP.md#the-check)): a command, set in user settings,
that it runs when a file opens or is saved, reading the compiler's
`file:line:col: error:` lines and their notes into diagnostics that
move with unsaved edits.

- A program built by `build.zig`: give it a `check` step, a compile step
  that emits no binary, and set
  `"nexus-zig.server.check": ["zig", "build", "check"]`.
- A file on its own:
  `"nexus-zig.server.check": ["zig", "build-obj", "-fno-emit-bin", "${file}"]`.

The check runs in the first workspace folder, only in a trusted
workspace (`zig build` runs the workspace's `build.zig`), and is stopped
after `nexus-zig.server.checkTimeout` milliseconds. The compiler analyzes
only what the program reaches, so a function nothing calls has no type
errors to report.

Zig 0.17.0's build server (`zig build --listen=-`) would answer faster,
but it builds with the `build.zig` it started with, panics on a second
request while it watches files, and ends when `build.zig` does not
compile; a command run on each save has none of these limits.

## Speed

Measured with `compare-tokens --bench 5` and `compare-accept --bench 5
[--no-schema]` over the corpus held in memory, single thread,
fast mode, best of 5 rounds, two interleaved runs, on an Apple M5
(10 cores) with the 1-minute load average below 6. Nexus is this
branch, which includes the parser speed work of Nexus 2.1.0. MB are 10^6
bytes.

| | run 1 | run 2 |
|---|---:|---:|
| Nexus lexer (with the `zig.zig` wrapper) | 739.5 MB/s | 744.8 MB/s |
| `std.zig.Tokenizer` | 760.5 MB/s | 751.7 MB/s |
| Nexus parse, with `@schema` (typed tree with spans) | 149.4 MB/s | 149.5 MB/s |
| Nexus parse, without `@schema` (plain tree) | 159.3 MB/s | 158.9 MB/s |
| `std.zig.Ast.parse` (tokenize and parse) | 444.3 / 441.0 MB/s | 443.4 / 440.5 MB/s |

The lexer runs at the tokenizer's speed: 12,805,547 tokens in 96.0 to
96.7 ms, against 94.0 to 95.1 ms. Parsing takes 3.0 times as long as
`Ast.parse` with the schema, and 2.8 times without it (the two
`Ast.parse` figures are its runs beside each). Ast.parse is a
hand-written recursive descent parser that fills a compact
struct-of-arrays tree; the Nexus parser is table-driven and builds a
general tree of nodes.

## Rerunning every check

Use Zig 0.17.0, and run these in a worktree of Nexus
([AGENTS.md, "Downstream"](../../AGENTS.md#downstream)): `./test/run`
builds `bin/nexus` in debug mode first, and the `bin/nexus` of the
checkout Rig, em and nexis build with must stay the safe build of main.
The `compare-*` tools need only an existing `bin/nexus`. `Z` is a
checkout of Zig at tag 0.17.0.

```bash
./test/run zig                                    # cases, tokens_test, trees_test, messages_test

P="--inline $Z/lib/std/zig/parser_test.zig --inline $Z/lib/std/zig/parser_fuzz.zig"
S="$Z/test/behavior $Z/test/cases/compile_errors $Z/lib/std/zig"

grammars/zig/compare-tokens $Z                        # tokens: 2,620 files, 12,805,547 tokens
grammars/zig/compare-tokens --fuzz 2000000 --seed 0   # tokens: random inputs
grammars/zig/compare-tokens --fuzz 2000000 --seed 1

grammars/zig/compare-accept $Z $P                     # accept: 3,134 inputs
grammars/zig/compare-accept --fuzz 60000 --seed 13 $Z/lib/std/zig $Z/test/behavior \
    $Z/test/cases/compile_errors --inline $Z/lib/std/zig/parser_test.zig
grammars/zig/compare-accept --fuzz 30000 --seed 21 $P
grammars/zig/compare-accept --fuzz 60000 --seed 22 $S

grammars/zig/compare-trees $Z $P                      # trees: the 3,036 inputs both accept
grammars/zig/compare-trees --fuzz 30000 --seed 11 $P
grammars/zig/compare-trees --fuzz 60000 --seed 12 $Z/lib/std/zig $Z/test/behavior
grammars/zig/compare-trees --fuzz 70000 --seed 31 $P
grammars/zig/compare-trees --fuzz 70000 --seed 32 $S
grammars/zig/compare-trees --fuzz 70000 --seed 33 $Z/lib/std/zig $Z/src/Sema.zig $Z/lib/std/mem.zig

grammars/zig/compare-scopes $Z                        # names: every use @lsp resolves, against AstGen
grammars/zig/compare-members $Z                       # members and imports, against std.zig.Ast
grammars/zig/compare-accept --messages $Z $P          # both syntax errors of every input both reject
grammars/zig/compare-tokens --bench 5 $Z              # lexer speed
grammars/zig/compare-accept --bench 5 $Z              # parse speed
grammars/zig/compare-accept --bench 5 --no-schema $Z  # parse speed, plain tree
```

Each comparison prints one line per input that differs and a summary,
and exits 1 when any input differs. After a change to `zig.grammar`,
`./test/run --update gen/zig sexp/zig` rewrites the generated-code and
grammar-tree goldens, whose diff is reviewed before a commit.

## How this could serve Zig

- **An executable specification.** grammar.peg describes Zig's syntax as
  a PEG over bytes, and is checked against Parse.zig only by the
  depth-limited fuzz test below. This grammar is a token-level LALR(1)
  grammar with Ast's tree, checked against Parse.zig on every corpus file
  and on mutants, for tokens, acceptance and trees; each place where
  Parse.zig decides by more than the next token is written down once,
  with its reason (a rule variant, a wrapper category, a declared
  conflict).
- **A stronger fuzzing oracle.** `std.zig`'s own fuzz test,
  `parser_fuzz.zig`, compares Ast.parse with `parser_generated_oracle.zig`,
  a recognizer generated from grammar.peg: it answers only accept or
  reject, and skips any input that takes more than 5 levels of recursion
  or 5 iterations of one rule (`max_depth = 5`, `error.MaxDepth`). The parser generated here has no depth limit (its
  LR stack grows on the heap) and agrees with Ast.parse on acceptance on
  every input checked above, so it can stand in for that oracle;
  `compare-accept --fuzz` runs such a comparison.
- **Tree-level differential testing.** Beyond acceptance, `compare-trees`
  checks that Ast.parse builds the right tree: kinds, roles and spans,
  through Ast's own `full*` helpers. It found the four helper bugs T5, T7,
  T8 and T9 above, which acceptance alone cannot see.
- **A base for tools.** The generated module is one file with no
  dependency: a lexer, a parser, and a typed tree with spans whose kinds
  are Ast's. An editor, a linter or a formatter in another code base can
  use it, or generate from the grammar with changes of its own.
