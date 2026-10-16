# Language servers

> **Design under review.** Part 1 (editor files) is built and tested.
> Part 2 (the language server) is a design: nothing in it exists until
> `./test/run` shows it, and this note leaves the document with the
> first phase that does.

One grammar file gives a language everything an editor needs: colouring
in VS Code, Vim and highlight.js, and a language server (LSP 3.17) with
diagnostics, an outline, folding, completion, hover, go to definition,
references, rename and signature help. The grammar alone gives the
syntactic half. A short `@lsp` section adds names and scopes. Eight
functions written beside the language's own checker add types. Wherever
the language's compiler already knows an answer, the language supplies
it and Nexus derives nothing: the grammar's answers are defaults, never a
second opinion.

| Feature | Comes from |
|---|---|
| colouring (TextMate, highlight.js, Vim) | `@highlight` ([GRAMMAR.md](GRAMMAR.md#editor-support)) |
| syntax errors as you type | the grammar, or the language's `parseDiagnostics` |
| semantic tokens | `@highlight` and the tree, or the language's `tokens` |
| outline, folding | `@schema` and `@lsp`, or the language's `symbols` and `folds` |
| selection ranges | `@schema` |
| keyword completion | the parser's expected tokens at the cursor |
| definition, references, rename, highlights, names in scope | the eight functions, or `@lsp` scopes for a language without them |
| member completion, hover with types, signature help, import completion | the eight functions |
| type errors as you type | the eight functions (`analyze`) |

## Part 1: colouring

`@highlight` lists how the language is coloured; `nexus --highlight`
writes the editor files from it, and `test/lib/highlight` checks that all
three engines colour a sample as its `.hl` file says.

1. Write `@highlight` in the grammar: metadata (`language`,
   `scope-name`, `extensions`, `line-comment`, ...) and entries
   `SCOPE targets [contexts] [within TOKEN]`
   ([GRAMMAR.md, "Editor support"](GRAMMAR.md#editor-support)).
2. Generate the files:

   ```bash
   nexus --highlight all lang.grammar editors
   ```

   This writes `editors/vscode/syntaxes/LANG.tmLanguage.json`,
   `editors/vscode/language-configuration.json`,
   `editors/highlightjs/LANG.js` and `editors/vim/syntax/LANG.vim`.
3. Write a sample program and pin its colouring (`--update` writes the
   `.hl` from the TextMate grammar; review it, then check without it):

   ```bash
   python3 nexus/test/lib/highlight --update nexus/docs/GRAMMAR.md \
     editors/vscode/syntaxes/LANG.tmLanguage.json editors/highlightjs/LANG.js \
     editors/vim/syntax/LANG.vim test/highlight/sample.EXT test/highlight/sample.EXT.hl
   ```

4. Add the hand-written files: a VS Code `package.json` that names the
   grammar and configuration, and Vim's `ftdetect` and `ftplugin`. em's,
   Rig's and nexis's `editors/` directories are working examples.

## Part 2: the language server

Nexus generates the server: the protocol, document sync, positions, the
error-tolerant tree, and every feature it can derive. The language
supplies meaning in its own terms (files, byte offsets, its symbols and
types) and never speaks LSP. Every question has one answerer: when the
lang module answers it, Nexus never derives its own answer, so the
server can never disagree with the compiler.

### Tier 1: from the grammar alone

A grammar with `@schema` (spans and node ids) and `@repair` (tolerant
parsing, [SEMANTICS.md](SEMANTICS.md#tolerant-parsing)) gets, with no
other input:

- **Diagnostics.** The strict parse's error, worded as `writeError`
  words it. The tolerant parse's repairs are not published: they serve
  the features below, and a repair is a guess, not an error the
  programmer made.
- **Semantic tokens.** Each token takes the scope `@highlight` gives
  its token name or literal; a name `@lsp` declares takes its
  declaration's kind. The legend is `@highlight`'s scopes.
- **Outline.** Every node `@lsp` declares, nested as the tree nests
  them, named by its name role.
- **Folding.** Every node of a kind `@lsp` folds that spans lines, and
  every run of comment lines (`@trivia`).
- **Selection ranges.** The spans of the nodes around the cursor, inner
  to outer.
- **Keyword completion.** The tolerant parse stops at the cursor, and
  `expected(state)` names the tokens the parser accepts there; a
  keyword or literal among them is offered as written, and so is each
  word of an `@as` group the parser accepts (a contextual keyword that
  lexes as a name).

A language whose compiler already produces any of these supplies it
instead, as an optional declaration of the lang module; each takes a
file and its text:

| Override | Replaces |
|---|---|
| `parseDiagnostics` | the parse diagnostics: the language's own wording, hints and notes, as many as it reports |
| `tokens` | the semantic tokens: kinds the compiler gives, such as a sigil told from an operator by the tree, a contextual keyword, a method told from a function |
| `symbols` | the outline |
| `folds` | the folding ranges |

### Tier 2: `@lsp`, names and scopes

`@lsp` maps the tree's kinds and roles to the parts a server needs. It
is written like `@highlight`, one entry per line:

```text
@lsp
    declare     fun     name    function        # a `fun` node declares its `name`, a function
    declare     obj     name    struct
    declare     field   name    field
    declare     param   name    parameter
    declare     let     name    variable  after # visible after its declaration, not before
    scope       fun body                        # these kinds open a scope
    scope       block
    refer       name    id                      # the `id` of a `name` node uses a symbol
    fold        block
```

| Entry | Meaning |
|---|---|
| `declare KIND ROLE SYMBOLKIND [after]` | a node of `KIND` declares the name in `ROLE`; `SYMBOLKIND` is one of LSP's (`function`, `method`, `struct`, `enum`, `enumMember`, `field`, `variable`, `constant`, `parameter`, `type`, `module`, `label`); visible throughout its scope, or from the declaration on with `after` |
| `scope KIND [ROLE]` | a node of `KIND` (or its `ROLE` child) opens a scope |
| `refer KIND ROLE` | the leaf in `ROLE` of a `KIND` node names a symbol |
| `fold KIND` | a node of `KIND` folds |

Every entry is checked against `@schema` at generation time: an unknown
kind, a role the kind lacks or a duplicate entry is a located error.

From these, with lexical scoping: **go to definition** (innermost scope
first), **references** and **document highlights**, **rename** (when
the new name lexes as the same token as the old one, checked with the
grammar's own lexer), **names in scope** for completion, and **hover**
showing a name's declaration line.

Tier 2 is for a language without a checker of its own. Lexical scoping
over the parsed tree cannot see what a compiler decides after it: a
plain assignment that declares or assigns depending on what is already
bound, a closure's captures that rename with the names they capture, a
member that needs a type, labels in their own namespace, the shared
names of a module split over several files. A language that implements
`symbolAt` writes no `declare`, `scope` or `refer` entries, and tier 2
does not run for it, not even when `analyze` fails.

### Tier 3: the eight functions

The language answers eight questions about a program it has checked.
Every position is a file and a byte offset in it, never a node of
Nexus's tree: the language's facts are keyed by its own nodes, after its
own rewrites.

| # | Function | Input → output | Powers |
|---|---|---|---|
| 1 | `analyze` | a program root and the open files' texts → an analysis: diagnostics per file and the files it read | type errors; the snapshot every other call reads |
| 2 | `symbolAt` | a file and offset → the symbol declared or used there | definition, references, rename, highlights |
| 3 | `typeAt` | a file and offset → the type of the innermost expression there | hover, go to type definition |
| 4 | `members` | a file and offset after a member access (`x.`) → the receiver's members, or none when the offset is not after one | member completion |
| 5 | `visible` | a file and offset → the symbols in scope there | completion of names, globals and imports included |
| 6 | `signatures` | a file and offset inside a call → its signatures, the active one and the active parameter | signature help |
| 7 | `describe` | a symbol or type → its Markdown and its declaration | hover, completion detail, go to type definition |
| 8 | `modules` | a file and offset in an import path → the modules that complete it, or none when the offset is not in one | import completion (`std/…`) |

Optional: `references(symbol)`, from an index the language keeps (else
Nexus asks `symbolAt` at each name token of every file the analysis
read); `format(file, text)`, a formatter the language has; and
`renamable(symbol)`, which refuses a builtin or a library symbol (by
default, a symbol declared in a workspace file renames).

The shapes:

- **Symbol**: `id`, `name`, `kind` (a `SYMBOLKIND` as above), `decl`
  (file and span), `detail` (one line: a signature or a type), `doc`
  (Markdown, optional). The `id` is the declaring file and the offset of
  the declaration, followed through re-exports and aliases to the
  original, so it is equal across files and across edits elsewhere; an
  index into a compiler's tables is not an id.
- **Signature**: `label`, `params` (each `name`, `type`, `doc`),
  `result`, `doc`.
- **Description**: `markdown`, the language's own text (a type, a
  signature, an ownership fact: whatever the language records), and
  `decl` when the subject has a declaration.
- **Diagnostic**: `file`, `span`, `severity` (`error`, `warning`,
  `info`, `hint`), `message`, and `related` notes, each a `file`, `span`
  and `message`. A note in a file no editor can open (a standard library
  built into the compiler) is folded into its diagnostic's message with
  its `path:line:col:`. A cap on the number of errors is the language's,
  applied before it returns them.

#### The program and when it is checked

`analyze` takes a root and an overlay: the path and text of every open
file. The language reads an overlaid file from the overlay and every
other file from disk, so unsaved edits in an imported file count. A
file is checked as part of its program, not alone, since imports
resolve from the root and a file of a module split over several files
needs its siblings. The root is the `LANG.lsp.root` setting when it is
set, else the file being checked.

The server runs `analyze` when a file opens and when it is saved; a
language that declares itself fast enough is analysed as you type too.
While the overlay hashes as it did, the last analysis stands. Its
diagnostics are published to every file they name, opened or not, and
cleared from a file when a later analysis names it no more or the file
closes.

#### How each request is answered

| Request | Answer |
|---|---|
| `completion` | `members(file, offset)` when it answers, else `modules(file, offset)` when it answers, else `visible(file, offset)` and the keywords the parser expects |
| `hover` | `describe(symbolAt(file, offset))`, else `describe(typeAt(file, offset))` |
| `definition` | `symbolAt(file, offset).decl` |
| `typeDefinition` | `describe(typeAt(file, offset)).decl` |
| `references`, `documentHighlight` | `references(symbol)`, or every name whose `symbolAt` has the same `id` |
| `rename` | those references, after the lexer check and `renamable` |
| `signatureHelp` | `signatures(file, offset)` |
| `documentSymbol`, `foldingRange`, `semanticTokens` | the overrides, else tier 1 |
| `publishDiagnostics` | `parseDiagnostics` (or the strict parse's error) as you type; `analyze`'s on open and save |

#### Broken code and stale analyses

At `x.` the file does not parse. A language implementing `analyze`
keeps to a written contract (Rig's lives in its `docs/INTERNALS.md`):

- it analyses the tolerant tree, in which a zero-width hole stands
  where a token was missing; a hole is a silent poison, typed as
  unknown, so it raises no error of its own and nothing that depends on
  it does;
- an import that fails falls back to its last good analysis, so one
  broken file does not blank the files that import it;
- nothing analysed from a tolerant tree reaches code generation.

When `analyze` fails outright, the server answers from the last
analysis that succeeded, its offsets mapped through the edits since,
and replaces it with the next that succeeds; a position the edits
removed answers nothing.

### The server's own duties

Whatever a language supplies, the generated server:

- negotiates positions in UTF-16 or UTF-8 (`positionEncodings`), and
  reads a byte order mark, a lone `\r` line break and invalid UTF-8
  without losing its place;
- serves an `untitled:` document its parse diagnostics only, since it
  has no path to analyse;
- advertises exactly the capabilities that exist for the language: a
  feature with neither an answerer nor a tier-1 default is not
  advertised;
- answers with LSP's error codes, and in a safety-checked build exits 1
  when it leaks memory.

### Writing the functions in Zig

The functions live beside the checker they wrap. For a language whose
compiler is written in Zig (Rig, nexis, em), they are declarations of
the lang module, read like `Lexer` and `Parser`
([SEMANTICS.md, "The lang module"](SEMANTICS.md#the-lang-module)):

```zig fragment
// lang.zig: what the generated server reads, each optional.
pub const Lsp = struct {
    pub const Analysis = rig.Program; // the language's own checked program

    // Tier 1 overrides.
    pub fn parseDiagnostics(gpa: Allocator, file: lsp.Path, text: []const u8, out: *lsp.Diagnostics) !void;
    pub fn tokens(gpa: Allocator, file: lsp.Path, text: []const u8, out: *lsp.Tokens) !void;
    pub fn symbols(gpa: Allocator, file: lsp.Path, text: []const u8, out: *lsp.Outline) !void;
    pub fn folds(gpa: Allocator, file: lsp.Path, text: []const u8, out: *lsp.Folds) !void;

    // Tier 3.
    pub fn analyze(gpa: Allocator, root: lsp.Path, overlay: lsp.Overlay) !lsp.Analyzed(Analysis);
    pub fn symbolAt(a: *Analysis, at: lsp.Pos) ?lsp.Symbol;
    pub fn typeAt(a: *Analysis, at: lsp.Pos) ?lsp.TypeId;
    pub fn members(a: *Analysis, at: lsp.Pos, out: *lsp.Symbols) !bool;
    pub fn visible(a: *Analysis, at: lsp.Pos, out: *lsp.Symbols) !void;
    pub fn signatures(a: *Analysis, at: lsp.Pos) !?lsp.SignatureHelp;
    pub fn describe(a: *Analysis, subject: lsp.Subject) !lsp.Description;
    pub fn modules(a: *Analysis, at: lsp.Pos, out: *lsp.Names) !bool;
};
```

`lsp.Pos` is a file and a byte offset. `nexus --lsp lang.grammar
lsp.zig` writes the server module; it imports `parser.zig` and the lang
module, and the language's binary serves it:

```zig fragment
// rig's `rig lsp` command.
const lsp = @import("lsp.zig");
pub fn main() !void {
    try lsp.serve(gpa, io, .stdin, .stdout);
}
```

A language without a binary of its own gets one:
`nexus --lsp-server lang.grammar dir` writes a buildable directory
(`build.zig`, `main.zig`, the parser and the server), and `zig build`
there gives `LANG-lsp`.

### Writing the functions in TypeScript or JavaScript

For a language whose checker is not Zig, or a prototype, the generated
server runs the functions in another process and talks to it in JSON
lines on its stdin and stdout:

```bash
LANG-lsp --hooks "bun hooks.ts"
```

Each request is one line; each answer is one line with the same `id`.
Positions are a file and a byte offset. `analyze` also receives each
overlaid file's tree as facts
([SEMANTICS.md, "Facts"](SEMANTICS.md#facts)), for a process that has
no parser of its own.

```json
{"id":1,"method":"analyze","params":{"root":"/w/main.tasks","overlay":{"/w/main.tasks":"task build: \"make\"\n"},"facts":{"/w/main.tasks":"(node 3 tasks 0 19)\n(role 3 items 2)\n..."}}}
{"id":1,"result":{"analysis":"a1","files":["/w/main.tasks"],"diagnostics":[]}}
{"id":2,"method":"members","params":{"analysis":"a1","at":{"file":"/w/main.tasks","offset":31}}}
{"id":2,"result":[{"id":"/w/lib.tasks:40","name":"name","kind":"field","decl":{"file":"/w/lib.tasks","start":40,"end":44},"detail":"name: String"}]}
```

A skeleton:

```ts
// hooks.ts: the functions for one language, served to LANG-lsp.
import * as readline from "node:readline";

type Pos = { file: string; offset: number };

const hooks: Record<string, (p: any) => unknown> = {
  analyze: ({ root, overlay, facts }) => check(root, overlay, facts), // { analysis, files, diagnostics }
  symbolAt: ({ analysis, at }) => resolve(analysis, at),              // Symbol | null
  typeAt: ({ analysis, at }) => typeAtPos(analysis, at),              // type handle | null
  members: ({ analysis, at }) => membersAfter(analysis, at),          // Symbol[] | null
  visible: ({ analysis, at }) => inScope(analysis, at),               // Symbol[]
  signatures: ({ analysis, at }) => callAt(analysis, at),             // SignatureHelp | null
  describe: ({ analysis, subject }) => describeOf(analysis, subject), // Description
  modules: ({ analysis, at }) => modulesAt(analysis, at),             // string[] | null
};

for await (const line of readline.createInterface({ input: process.stdin })) {
  const { id, method, params } = JSON.parse(line);
  const result = hooks[method]?.(params) ?? null;
  process.stdout.write(JSON.stringify({ id, result }) + "\n");
}
```

The functions it calls (`check`, `resolve`, ...) are the language's; a
small language can answer from a table (its standard library's members
and signatures as JSON) before it has a checker at all.

### The VS Code client

`nexus --highlight vscode lang.grammar editors/vscode` writes
`package.json` and `extension.js` beside the grammar files: the language,
its grammar and configuration, the `LANG.lsp.path` and `LANG.lsp.root`
settings, and a client that starts the server for the language's files
and says so when it cannot (the TextMate grammar colours the file either
way). Rig's `editors/vscode/extension.js` is the model. Then:

```bash
cd editors/vscode && npm install && npx -y @vscode/vsce package --skip-license
code --install-extension editors/vscode/vscode-LANG-0.1.0.vsix --force
```

### Tests

A feature exists when `./test/run` shows it. A suite's `lsp/` directory
holds scripts that drive the server with a cursor `‸` in the text and
the answer expected there:

```text
-- file main.tasks
task build: "make"
done bu‸

-- complete
build

-- hover main.tasks 1:6
task build
```

`test/lib/lsp` runs each script against the generated server (with the
suite's lang module, or a `--hooks` process) and compares every answer.
Every `@lsp` mistake gets an adverse test, as every grammar mistake
does.

## Phases

1. **Tier 1 and the overrides.** `nexus --lsp` and `--lsp-server`, the
   protocol and the server's own duties, document sync, the tier-1
   features, the four overrides, and the `lsp/` test scripts; checked
   along the way: that `expected(state)` names a contextual keyword the
   parser accepts, and that a node a repair completes gets a node id.
   `rig lsp` moves onto the generated server through the overrides and
   `analyze` when Rig's own `test/cli/lsp_check.sh` and `test/cli/lsp.sh`
   pass unchanged; em and nexis get servers from their grammars.
2. **Tier 2.** `@lsp`, its checks, and scope resolution, for languages
   without a checker.
3. **Tier 3.** The eight functions, `analyze`'s root and overlay, and the
   `--hooks` JSON protocol with a TypeScript example. Rig first adds the
   facts its checker does not record (the member `x.f` resolves to, a
   reference through a module name, the names of `from` and `keeps` as
   references, one table of built-in members that its type checker reads
   too) and its tolerant-analysis contract, then implements the
   functions: member completion, hover with types and ownership facts,
   signature help, `std/` completion.
4. **The VS Code client** generated with the editor files.
5. **Formatting**: the language's own `format`, or a printer driven by
   the grammar.

Each phase is a change to the generated API, so it lands as
[AGENTS.md](../AGENTS.md) rule 10 says: with every consumer copy in this
repository and a `CHANGELOG.md` entry with migration steps, after Rig, em
and nexis have heard of it.
