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
functions written beside the language's own checker add types.

| Feature | Comes from |
|---|---|
| colouring (TextMate, highlight.js, Vim) | `@highlight` ([GRAMMAR.md](GRAMMAR.md#editor-support)) |
| syntax errors as you type, with recovery | the grammar and `@repair` |
| semantic tokens | `@highlight` and the tree |
| outline, folding, selection ranges | `@schema` and `@lsp` |
| keyword completion | the parser's expected tokens at the cursor |
| definition, references, rename, highlights, names in scope | `@lsp` scopes |
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

Nexus generates the server: the protocol, document sync, positions in
UTF-16 or UTF-8, the error-tolerant tree, and every feature it can
derive. The language supplies meaning in its own terms (nodes, byte
spans, its symbols and types) and never speaks LSP.

### Tier 1: from the grammar alone

A grammar with `@schema` (spans and node ids) and `@repair` (tolerant
parsing, [SEMANTICS.md](SEMANTICS.md#tolerant-parsing)) gets, with no
other input:

- **Diagnostics.** The strict parse's first error, worded as
  `writeError` words it, and the tolerant parse's repairs, each at its
  span.
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
  keyword or literal among them is offered as written.

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
    member      member  receiver name           # x.name: completed and resolved by type
    call        call    callee  args            # for signature help
    import      use     path                    # for import completion
    fold        block
```

| Entry | Meaning |
|---|---|
| `declare KIND ROLE SYMBOLKIND [after]` | a node of `KIND` declares the name in `ROLE`; `SYMBOLKIND` is one of LSP's (`function`, `method`, `struct`, `enum`, `enumMember`, `field`, `variable`, `constant`, `parameter`, `type`, `module`, `label`); visible throughout its scope, or from the declaration on with `after` |
| `scope KIND [ROLE]` | a node of `KIND` (or its `ROLE` child) opens a scope |
| `refer KIND ROLE` | the leaf in `ROLE` of a `KIND` node names a symbol |
| `member KIND RECEIVER NAME` | member access: `NAME` is looked up in the type of `RECEIVER` (tier 3) |
| `call KIND CALLEE ARGS` | a call, for signature help |
| `import KIND PATH` | an import, for module completion |
| `fold KIND` | a node of `KIND` folds |

Every entry is checked against `@schema` at generation time: an unknown
kind, a role the kind lacks or a duplicate entry is a located error.

From these, with lexical scoping:

- **Go to definition**: the declaration a reference resolves to,
  innermost scope first.
- **References** and **document highlights**: every reference that
  resolves to the same declaration.
- **Rename**: those references, when the new name lexes as the same
  token as the old one (checked with the grammar's own lexer).
- **Names in scope** for completion, and **hover** showing a name's
  declaration line.

A member, an imported name or anything that needs a type resolves
through tier 3; without it, a member is left unresolved, never guessed.

### Tier 3: the eight functions

The language answers eight questions. Each takes an *analysis*, the
language's own result of checking a program, and nodes of the tree
Nexus built.

| # | Function | Input → output | Powers |
|---|---|---|---|
| 1 | `analyze` | a file's text and tree → an analysis, its diagnostics and the files it read | type errors as you type; the snapshot every other call reads |
| 2 | `symbolAt` | a name node → the symbol it declares or uses | definition, references, rename, highlights (overriding tier 2) |
| 3 | `typeOf` | an expression node → its type | hover, member completion, go to type definition |
| 4 | `members` | a type → its member symbols | completion after `x.` |
| 5 | `visible` | a node → the symbols in scope there | completion of names, globals and imports included |
| 6 | `signatures` | a callee node → its signatures | signature help |
| 7 | `describe` | a symbol or type → its text and declaration | hover, completion detail, go to type definition |
| 8 | `modules` | an import path prefix → the modules that complete it | import completion (`std/…`) |

Optional: `format(text, tree) → text`, a formatter the language already
has, and `renamable(symbol) → bool`, which refuses a builtin or a
library symbol (by default anything declared in an open workspace file
renames).

The shapes they return:

- **Symbol**: `id` (opaque, equal across files for one declaration;
  "declaring file and span" is enough), `name`, `kind` (a `SYMBOLKIND`
  as above), `decl` (file and span), `detail` (one line: a signature or
  a type), `doc` (Markdown, optional).
- **Signature**: `label`, `params` (each `name`, `type`, `doc`),
  `result` (the return type's text), `doc`.
- **Description**: `markdown`, and `decl` when the subject has a
  declaration.
- **Diagnostic**: `span`, `severity` (`error`, `warning`, `info`),
  `message`, and `related` notes (`span` and `message`).

Types are opaque handles: Nexus compares them and passes them back.

#### How each request is answered

| Request | Answer |
|---|---|
| `completion` after a `member` receiver | `members(typeOf(receiver))` |
| `completion` in an `import` path | `modules(prefix)` |
| `completion` elsewhere | `visible(node)`, then the keywords the parser expects (tier 1) |
| `hover` on a name | `describe(symbolAt(node))` |
| `hover` on an expression | `describe(typeOf(node))` |
| `definition` | `symbolAt(node).decl` |
| `typeDefinition` | `describe(typeOf(node)).decl` |
| `references`, `documentHighlight` | every name node in the program whose `symbolAt` has the same `id` |
| `rename` | those references, after the lexer check and `renamable` |
| `signatureHelp` | `signatures(callee)` of the innermost `call` around the cursor; the active parameter is the `args` child holding it |
| `documentSymbol`, `workspace/symbol` | the `declare` nodes, with `describe` for detail |
| `publishDiagnostics` | the parse diagnostics, then `analyze`'s |

#### Broken code and stale analyses

At `x.` the file does not parse. The tolerant parse supplies a tree with
a zero-width hole where the name goes, and `analyze` must still type
what it can: a checker that stops at the first error answers nothing
useful. When `analyze` fails, Nexus answers from the last analysis that
succeeded, its spans mapped through the edits since, and replaces it
with the next one that succeeds; a node the edits removed answers
nothing.

### Writing the functions in Zig

The functions live beside the checker they wrap. For a language whose
compiler is written in Zig (Rig, nexis, em), they are declarations of
the lang module, read like `Lexer` and `Parser`
([SEMANTICS.md, "The lang module"](SEMANTICS.md#the-lang-module)):

```zig fragment
// lang.zig: what the generated server reads, each optional.
pub const Lsp = struct {
    pub const Analysis = rig.Program; // the language's own checked program

    pub fn analyze(gpa: std.mem.Allocator, doc: lsp.Document) !lsp.Analyzed(Analysis);
    pub fn symbolAt(a: *Analysis, node: parser.Sexp) ?lsp.Symbol;
    pub fn typeOf(a: *Analysis, node: parser.Sexp) ?lsp.TypeId;
    pub fn members(a: *Analysis, t: lsp.TypeId, out: *lsp.Symbols) !void;
    pub fn visible(a: *Analysis, node: parser.Sexp, out: *lsp.Symbols) !void;
    pub fn signatures(a: *Analysis, callee: parser.Sexp, out: *lsp.Signatures) !void;
    pub fn describe(a: *Analysis, subject: lsp.Subject) !lsp.Description;
    pub fn modules(a: *Analysis, prefix: []const u8, out: *lsp.Names) !void;
};
```

`nexus --lsp lang.grammar lsp.zig` writes the server module; it imports
`parser.zig` and the lang module, and the language's binary serves it:

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
server runs the eight functions in another process and talks to it in
JSON lines on its stdin and stdout:

```bash
LANG-lsp --hooks "bun hooks.ts"
```

Each request is one line; each answer is one line with the same `id`.
Nodes are the node ids of the tree, which `analyze` receives as facts
([SEMANTICS.md, "Facts"](SEMANTICS.md#facts)); spans are byte offsets.

```json
{"id":1,"method":"analyze","params":{"file":"/w/main.tasks","text":"task build: \"make\"\n","facts":"(node 3 tasks 0 19)\n(role 3 items 2)\n(node 2 task 0 18)\n..."}}
{"id":1,"result":{"analysis":"a1","files":["/w/main.tasks"],"diagnostics":[]}}
{"id":2,"method":"members","params":{"analysis":"a1","type":"t:Task"}}
{"id":2,"result":[{"id":"s:Task.name","name":"name","kind":"field","decl":{"file":"/w/lib.tasks","start":40,"end":44},"detail":"name: String"}]}
```

A skeleton:

```ts
// hooks.ts: the eight functions for one language, served to LANG-lsp.
import * as readline from "node:readline";

type Span = { file: string; start: number; end: number };
type Symbol = { id: string; name: string; kind: string; decl: Span; detail: string; doc?: string };

const hooks: Record<string, (p: any) => unknown> = {
  analyze: ({ file, text, facts }) => ({ analysis: check(file, text, facts), files: [file], diagnostics: [] }),
  symbolAt: ({ analysis, node }) => resolve(analysis, node),     // Symbol | null
  typeOf: ({ analysis, node }) => typeOfNode(analysis, node),    // type handle | null
  members: ({ analysis, type }) => membersOf(analysis, type),    // Symbol[]
  visible: ({ analysis, node }) => inScope(analysis, node),      // Symbol[]
  signatures: ({ analysis, callee }) => signaturesOf(analysis, callee),
  describe: ({ analysis, subject }) => describeOf(analysis, subject),
  modules: ({ analysis, prefix }) => modulesUnder(analysis, prefix),
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
its grammar and configuration, a `LANG.lsp.path` setting, and a client
that starts the server for the language's files and says so when it
cannot (the TextMate grammar colours the file either way). Rig's
`editors/vscode/extension.js` is the model. Then:

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

1. **Tier 1.** `nexus --lsp` and `--lsp-server`, the protocol, document
   sync, diagnostics, semantic tokens, outline, folding, selection
   ranges and keyword completion; the `lsp/` test scripts. Rig's
   hand-written `rig lsp` moves onto the generated server with its
   features unchanged; em and nexis get servers from their grammars.
2. **Tier 2.** `@lsp`, its checks, and scope resolution: definition,
   references, highlights, rename, names in scope.
3. **Tier 3.** The eight functions in the lang module, and the `--hooks`
   JSON protocol with a TypeScript example; Rig implements them around
   its checker (member completion, hover with types, signature help,
   `std/` completion).
4. **The VS Code client** generated with the editor files.
5. **Formatting**: the language's own `format`, or a printer driven by
   the grammar.

Each phase is a change to the generated API, so it lands as
[AGENTS.md](../AGENTS.md) rule 10 says: with every consumer copy in this
repository and a `CHANGELOG.md` entry with migration steps, after Rig, em
and nexis have heard of it.
