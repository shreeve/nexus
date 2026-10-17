# Editors and language servers

One command turns a grammar file into everything an editor needs for its
language: colouring in VS Code, Vim and highlight.js, a VS Code
extension, and a language server (LSP 3.17) that builds with `zig build`.

```bash
nexus --editor lang.grammar editors
```

The grammar alone gives the syntactic half of the server: syntax errors as
you type, semantic tokens, folding, selection ranges and keyword
completion. The rest (the outline, hover, go to definition, references,
rename, completion of names and members, signature help, type errors,
formatting) needs to know what the program means, which only the language
knows. For that the command writes `hooks.zig`, a file of functions to
fill in, each left as a stub. Writing a function turns on the features
behind it; a stub left alone turns nothing on, and the server never
advertises a feature it cannot give.

[test/editor](../test/editor) is a worked example: Tally, a small
language, with a `hooks.zig` that writes every function
(`test/editor/full/hooks.zig`), and the sessions `./test/run` replays
against its server.

## The command

```bash
nexus --editor [--lang lang.zig] lang.grammar editors
```

The grammar needs `@highlight` ([GRAMMAR.md, "Editor
support"](GRAMMAR.md#editor-support)) and parser rules. A grammar with
`@lang` has a lang module ([SEMANTICS.md, "The lang
module"](SEMANTICS.md#the-lang-module)), and `--lang` names its file.
`LANG` below is the language id, the last part of `@highlight`'s
`scope-name`.

```text
editors/
├── vscode/
│   ├── package.json                    the extension: the language, its grammar, its settings
│   ├── extension.js                    the client: starts the server
│   ├── language-configuration.json     comments, brackets, indentation
│   ├── syntaxes/LANG.tmLanguage.json   the TextMate grammar
│   └── .gitignore
├── vim/syntax/LANG.vim
├── highlightjs/LANG.js
└── server/
    ├── build.zig                       `zig build` → zig-out/bin/LANG-lsp
    ├── .gitignore
    └── src/
        ├── main.zig                    serves standard input and output
        ├── lsp.zig                     the server
        ├── parser.zig                  the grammar's parser, with spans
        ├── language.zig                the grammar's table for the server
        ├── hooks.zig                   the language's functions: written once
        └── lang.zig ...                with --lang, the lang module and the files it imports
```

Every file but `hooks.zig` belongs to Nexus. Running the command again
writes each of them again from the grammar, so a change to the grammar
reaches every editor file. `hooks.zig` belongs to the language: the
command writes it when it is missing and never again. It prints `Wrote`
for each file it writes and `Kept` for a `hooks.zig` it leaves.

- The highlighting files are those of `nexus --highlight all`
  ([GRAMMAR.md, "The files"](GRAMMAR.md#the-files)).
- `parser.zig` is the grammar's parser as `nexus --spans` writes it.
- `language.zig` holds what the server needs to know about the grammar:
  the language's name and id, the `@highlight` scope of each token by its
  name or its text, and the words completion can offer. Those are each
  literal terminal, each token whose one rule is a literal, and each
  `@keywords` terminal that is a word, where `@highlight`'s `word-chars`
  says what a word is.
- With `--lang`, the lang module is copied beside `parser.zig`, as the
  parser imports it, with every file it imports by a relative path. A
  file it imports from outside its own directory, a file that cannot be
  read, and a file named like one of the server's own (`main.zig`,
  `lsp.zig`, `parser.zig`, `language.zig`, `hooks.zig`) are errors.

### Build and install

```bash
cd editors/server && zig build --prefix ../vscode
```

builds the server into `editors/vscode/bin/LANG-lsp`, inside the
extension. A plain `zig build` puts it in `editors/server/zig-out/bin/`.

The extension's `package.json` declares the language, its file
extensions, the TextMate grammar and language configuration, the semantic
token types the server sends (each mapped to its TextMate scope, so a
theme colours them), and two settings:

| Setting | Meaning |
|---|---|
| `LANG.server.path` | the server: a path, or a name on `PATH`; empty means the extension's `bin/LANG-lsp`, else `LANG-lsp` on `PATH` |
| `LANG.server.root` | the file the program starts from, which the server analyzes; empty means the file opened or saved |

`extension.js` starts the server for the language's files with
`vscode-languageclient` and restarts it when a setting changes. When the
server does not start, it says so, and the TextMate grammar colours the
files anyway. VS Code's own tools package and install it:

```bash
cd editors/vscode && npm install && npx @vscode/vsce package
code --install-extension vscode-LANG-0.1.0.vsix
```

## What the grammar gives

With every function of `hooks.zig` a stub, the server gives:

- **Syntax errors as you type.** On every change, the strict parse's
  error, worded as `writeError` words it, at the token where the parse
  failed.
- **Semantic tokens.** Each token takes the scope `@highlight` gives its
  text (a literal or a `@keywords` word), else its token name. The token
  types are `@highlight`'s 19 scopes.
- **Folding.** Each node of the tree that spans lines, and each run of
  comment tokens on consecutive lines. A grammar with `@repair` is parsed
  tolerantly here ([SEMANTICS.md, "Tolerant
  parsing"](SEMANTICS.md#tolerant-parsing)), so a file that does not
  parse still folds.
- **Selection ranges.** The spans of the nodes around the cursor, inner
  to outer.
- **Keyword completion.** The words of `language.zig` that the parser
  takes at the cursor: each word that, put in place of the word the
  cursor is in, the parse reads past. None when the text before that word
  already has an error.

## The functions of `hooks.zig`

Each function starts as a stub that names its signature and the features
it turns on:

```zig fragment
/// Markdown for a symbol or a type, and where the type is declared.
/// Turns on hover.
/// pub fn describe(a: *Analysis, arena: std.mem.Allocator, subject: lsp.Subject) !?lsp.Description
pub const describe = lsp.todo;
```

To turn it on, replace the stub with the function:

```zig fragment
pub fn describe(a: *Analysis, arena: std.mem.Allocator, subject: lsp.Subject) !?lsp.Description {
    _ = a;
    return switch (subject) {
        .symbol => |s| .{ .markdown = try arena.print("```tally\n{s}\n```", .{s.detail}), .decl = s.decl },
        .type => |t| .{ .markdown = try arena.print("`{s}`", .{typeName(t)}) },
    };
}
```

The server asks at compile time which functions are written: a
declaration of type `lsp.Todo` is not, and its features are neither
advertised nor ever called. A function that reads the analysis without
`analyze` written is a compile error.

| Function | Turns on |
|---|---|
| `parseDiagnostics` | the language's own syntax errors, in place of the strict parse's one error |
| `tokens` | the language's semantic tokens, in place of each token's `@highlight` scope |
| `symbols` | the outline and breadcrumbs |
| `folds` | the language's folding ranges, in place of the grammar's |
| `format` | Format Document |
| `analyze` | the analysis's diagnostics; every function below reads the analysis |
| `symbolAt` | go to definition, references, document highlight, rename |
| `typeAt` | with `describe`: hover over an expression, go to type definition |
| `describe` | with `symbolAt` or `typeAt`: hover |
| `members` | completion after a member access |
| `modules` | completion in an import |
| `visible` | completion of the names in scope |
| `signatures` | signature help |
| `references` | the uses of a symbol from the language's own index |
| `renamable` | refusing a rename |
| `completionTriggers` | the characters that open completion besides word characters (a constant, empty by default) |

### The parse

The first five functions read one file, its path and its text, and
return their answer in `arena`, which lives until the request is
answered.

```zig fragment
pub fn parseDiagnostics(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Diagnostic
pub fn tokens(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Token
pub fn symbols(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.OutlineItem
pub fn folds(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Fold
pub fn format(arena: Allocator, path: []const u8, text: []const u8) !?[]const u8
```

Every offset is a byte offset into `text`. A `Token` is a start, a length
and a `Scope`, one of `@highlight`'s scopes; an `OutlineItem` is a name, a
`SymbolKind`, its whole range, the range of its name, a one-line detail
and its children; a `Fold` is a range, of comments or not. `format`
returns the whole file formatted, or null when it is formatted already.
An error from any of them answers nothing.

### The analysis

```zig fragment
pub const Analysis = struct { ... };
pub fn analyze(arena: Allocator, root: []const u8, overlay: lsp.Overlay) !lsp.Analyzed(Analysis)
```

`analyze` checks a program as a whole and keeps what the other functions
need in `Analysis`, a type the language declares. `root` is the file the
program starts from: the client's `root` option (`LANG.server.root`) when
it gives one, else the file opened or saved. `overlay.read(arena, path)`
reads a file the way the editor sees it: an open file's text, unsaved
edits and all, else the file on disk. `Analyzed(Analysis)` is the
analysis, its diagnostics in every file, and the files it read.

The server runs `analyze` when a file opens and when it is saved, never
as you type, and holds the result in an arena of its own until the next
analysis replaces it. An analysis that fails (`analyze` returns an error)
leaves the one before in place. Until one succeeds, the requests that
read the analysis answer nothing, and a rename is refused with "no
analysis yet: save the file". A document without a path, such as an
unsaved `untitled:` one, is parsed and coloured but never analyzed, so
those requests answer nothing in it.

Diagnostics are published to every file they name, opened or not. An
open file shows its syntax errors and, while its text is the text the
analysis read, the analysis's diagnostics; an edit hides those until the
next save. A file the last analysis named and the new one does not is
cleared. A diagnostic's `notes` are its related locations.

The functions that read the analysis take a position, a `Pos`: a path and
a byte offset in that file's text. In a file edited since the analysis,
the offset is in the edited text, so until the next save an answer there
can be missing or misplaced.

```zig fragment
pub fn symbolAt(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.Symbol
pub fn typeAt(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.TypeId
pub fn describe(a: *Analysis, arena: Allocator, subject: lsp.Subject) !?lsp.Description
pub fn members(a: *Analysis, arena: Allocator, at: lsp.Pos) !?[]const lsp.Symbol
pub fn modules(a: *Analysis, arena: Allocator, at: lsp.Pos) !?[]const []const u8
pub fn visible(a: *Analysis, arena: Allocator, at: lsp.Pos) ![]const lsp.Symbol
pub fn signatures(a: *Analysis, arena: Allocator, at: lsp.Pos) !?lsp.SignatureHelp
pub fn references(a: *Analysis, arena: Allocator, symbol: lsp.Symbol) ![]const lsp.Span
pub fn renamable(a: *Analysis, symbol: lsp.Symbol) bool
```

- A **`Symbol`** is a declaration: `id`, `name`, `kind` (a `SymbolKind`,
  LSP's), `decl` (the span of its name), a one-line `detail` (a signature
  or a type) and `doc` (Markdown). Its `id` must be the same wherever the
  declaration is seen, in any file: the declaring file and the offset of
  the declaration serve.
- A **`TypeId`** is a `u64` that the language gives meaning to.
- A **`Description`** is Markdown, and the span of the declaration when
  the subject has one.
- A **`SignatureHelp`** is the signatures of the call, the one that
  applies, and the parameter the position is in.

### How each request is answered

| Request | Answer |
|---|---|
| `completion` | `members` when it gives a list; else `modules` when it gives a list; else `visible`, then the keywords the grammar takes there |
| `hover` | `describe` of `symbolAt`, else `describe` of `typeAt` |
| `definition` | the declaration of `symbolAt` |
| `typeDefinition` | the declaration in `describe` of `typeAt` |
| `references` | `references` of `symbolAt`; without it, every token of every file the analysis read whose `symbolAt` has the same `id` |
| `documentHighlight` | those references in this file |
| `rename` | those references and the declaration, when `renamable` allows it (by default every symbol renames) and the new name lexes as one token of the same kind as the old name |
| `signatureHelp` | `signatures` |
| `documentSymbol` | `symbols` |
| `foldingRange`, `semanticTokens` | `folds` and `tokens`, else the grammar's |
| `formatting` | `format` |

## The server's own duties

Whatever the language writes, the server:

- counts positions in UTF-16 code units, or in bytes when the client
  offers `utf-8`, and keeps them in place across a byte order mark, a
  lone `\r`, a `\r\n` and characters of every length;
- answers a request before `initialize` with `ServerNotInitialized`
  (-32002), a request it does not advertise with `MethodNotFound`
  (-32601), a request on a document that is not open with
  `InvalidParams` (-32602), and a rename it refuses with `RequestFailed`
  (-32803) and the reason;
- exits 0 on `exit` after `shutdown`, else 1.

## Tests

The editor suite (`test/editor`) builds Tally's server twice: in `full/`
with `full/hooks.zig`, which writes every function but `references` so
the server's own search runs too, and in `stub/` with the `hooks.zig`
that `--editor` writes. `test/lib/lsp` replays each `.session` file of a
directory against its server, on the files of `project/`, and compares
what the server answers with the `.out` file beside it. A session is one
command a line:

```text
initialize root main.tally
open main.tally
hover main.tally 4:5
rename main.tally 8:9 z
```

and its `.out` is each command after `> `, then the answer, one item a
line:

```text
> rename main.tally 8:9 z
{"changes":{"main.tally":[{"newText":"z","range":"8:9-8:10"},{"newText":"z","range":"9:24-9:25"}]}}
```

`test/lib/lsp` lists every command. For every other grammar with
`@highlight`, the suite runs `--editor` and checks the files it writes
against the highlighting files, the parser and the goldens, and checks
that the server compiles.
