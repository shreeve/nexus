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
│   ├── identity.json                   the extension's name and mode: written once
│   ├── package.json                    the extension: the language, its grammar, its settings
│   ├── extension.js                    the client: starts the server
│   ├── README.md                       the extension's page: its settings, building it
│   ├── language-configuration.json     comments, brackets, indentation
│   ├── syntaxes/LANG.tmLanguage.json   the TextMate grammar
│   ├── .vscodeignore                   what `vsce package` leaves out
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

Every file but `hooks.zig` and `identity.json` belongs to Nexus. Running
the command again writes each of them again from the grammar, so a change
to the grammar reaches every editor file. `hooks.zig` and `identity.json`
belong to the language: the command writes each when it is missing and
never again. It prints `Wrote` for each file it writes and `Kept` for a
`hooks.zig` or `identity.json` it leaves.

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

### The extension's identity

`vscode/identity.json` names the extension. The command writes it with
the defaults, which name no official extension, so that the generated one
installs beside the language's own extension without clashing:

```json
{
  "name": "nexus-LANG",
  "displayName": "Language (Nexus)",
  "description": "Language: highlighting and its language server.",
  "publisher": "nexus-local",
  "version": "0.1.0",
  "license": "UNLICENSED",
  "repository": "",
  "settings": "nexus-LANG",
  "mode": "standalone"
}
```

Every key is optional; one left out takes its default. `settings` is the
prefix of the extension's settings (`PREFIX` below); `repository`, a URL,
is left out of `package.json` when it is empty. Every run reads the file
before it writes anything, and a mistake in it is an error at its line
and column, after which nothing is written: a file that is not a JSON
object of strings, an unknown or repeated key, and a value that breaks
its key's rule:

| Key | Rule |
|---|---|
| `name` | lowercase letters, digits and `-`, starting with a letter or digit |
| `publisher` | letters, digits and `-`, starting with a letter or digit |
| `displayName`, `license` | not empty |
| `version` | three numbers joined by dots |
| `settings` | names of letters, digits, `_` and `-`, joined by dots |
| `mode` | `standalone` or `companion` |

`mode` says what the extension contributes. `standalone` contributes the
language (its id, file extensions and language configuration), the
TextMate grammar and the client. `companion` contributes the client
alone, for a language another extension already contributes: the other
extension keeps the language and its colouring, and this one adds the
server. Both activate on the language's files and declare the semantic
token types and the settings.

### The extension

The extension's `package.json` declares its identity, the language and
grammar (in `standalone` mode), the semantic token types the server sends
(each mapped to its TextMate scope, and each type VS Code does not know
given a standard `superType`, so a theme colours it either way:
`keywordControl`, `keywordOperator` and `storageModifier` are keywords,
`constantNumeric` a number, `constant` and `constantSymbol` enum members,
`stringEscape` a string, `functionBuiltin` a function,
`variableParameter` a parameter and `variableSpecial` a variable;
`punctuation` and `invalid` have none), and two settings:

| Setting | Meaning |
|---|---|
| `PREFIX.server.path` | the server: a path, or a name on `PATH`; empty means the extension's `bin/LANG-lsp`, else `LANG-lsp` on `PATH` |
| `PREFIX.server.root` | the file the program starts from, which the server analyzes; a relative path is relative to the first workspace folder; empty means each file's own program ([The analysis](#the-analysis)) |

`server.path` names a program to run, so only the user's own settings
give it: it has `"scope": "machine"`, `package.json` lists it among the
settings an untrusted workspace may not set, and `extension.js` reads
only its user-level value. A workspace's `.vscode/settings.json` never
chooses the server, trusted or not.

`extension.js` starts the server with `vscode-languageclient` for the
language's documents of the `file` and `untitled` schemes (not the
`git:` or diff views of them), and passes `server.root` as the
`root` option, absolute. A relative root with no folder open is left
out, and the extension says so. A change to a `PREFIX.server` setting
restarts the server: one restart at a time, each after the one before
has finished, and changes that come before a restart begins share it,
so two changes in a row start one server. Every server writes to one
output channel. When the server does not start, the extension disposes
of the client and says how to set `server.path`; in `standalone` mode
the TextMate grammar colours the files anyway.

### Build, package and install

```bash
cd editors/server && zig build --prefix ../vscode
```

builds the server into `editors/vscode/bin/LANG-lsp`, inside the
extension. A plain `zig build` puts it in `editors/server/zig-out/bin/`.
VS Code's own tools package and install the extension:

```bash
cd editors/vscode && npm install
npx @vscode/vsce package --skip-license --allow-missing-repository
code --install-extension nexus-LANG-0.1.0.vsix
```

`.vscodeignore` packages `extension.js`, the TextMate grammar and
language configuration (in `standalone` mode), `bin/`, the dependencies
and a `LICENSE` file; `vsce` adds `package.json` and `README.md`. `vsce`
asks before it packages an extension without a `LICENSE` file or a
`repository`; the two flags answer for it. A language that sets
`repository` in `identity.json` and puts its `LICENSE` in `vscode/`
(the command never writes or removes it) packages with plain `npx
@vscode/vsce package`. Commit `package-lock.json`, which `npm install`
writes, so that the client's own dependencies stay fixed.

## What the grammar gives

With every function of `hooks.zig` a stub, the server gives:

- **Syntax errors as you type.** On every change, the strict parse's
  error, worded as `writeError` words it, at the token where the parse
  failed, or, when that token is on a later line than the one before
  it, zero width at the end of that one
  ([SEMANTICS.md, "Syntax errors"](SEMANTICS.md#syntax-errors)).
- **Semantic tokens.** Each token takes the scope `@highlight` gives its
  text (a literal or a `@keywords` word), else its token name. The token
  types are `@highlight`'s 19 scopes.
- **Folding.** Each node of the tree whose solid tokens span lines, and
  each run of comment tokens on consecutive lines. A solid token is one
  with text other than blanks and line ends that is not a comment; a
  node's span runs on to the next token, over the blank lines, comments
  and zero-width layout tokens after it, and its fold ends at its last
  solid token. A grammar with `@repair` is parsed
  tolerantly here ([SEMANTICS.md, "Tolerant
  parsing"](SEMANTICS.md#tolerant-parsing)), so a file that does not
  parse still folds.
- **Selection ranges.** The solid token the cursor is in (else the one
  it ends), then the nodes around it, inner to outer, each from its first
  solid token to its last and inside the one after it.
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
program starts from: the client's `root` option (`PREFIX.server.root`) when
it gives one; else the root of the newest analysis that covers the file
opened or saved (its root, a file it read, or a file its diagnostics
name); else that file itself. `overlay.read(arena, path)`
reads a file the way the editor sees it: an open file's text, unsaved
edits and all, else the file on disk. `Analyzed(Analysis)` is the
analysis, its diagnostics in every file, and the files it read.

The server runs `analyze` when a file opens and when it is saved, never
as you type, and holds the result in an arena of its own until the next
analysis of the same root replaces it. It runs on a task of its own, one
analysis at a time, over a copy of the open documents, while the server
goes on answering from the analyses it holds; one asked for while
another runs waits, once per root, and the file whose opening or saving
asked for it is published when it lands. So `analyze` runs on another
thread than the other functions, and shares no mutable state with them.
Where the platform cannot run tasks concurrently, it runs when asked. It holds one analysis per root,
so separate programs open side by side keep theirs, up to eight; a ninth
drops the one a request or an analysis used least recently, and the
diagnostics it gave. Requests on a file read the analysis of its program:
the root's, with a `root` option, else the newest that covers the file. An analysis that fails (`analyze` returns an error)
leaves the one before in place, and says so: the server logs "the
analysis of ROOT failed: ERROR" (`window/logMessage`), and the file whose
opening or saving ran it has an error at its start, "the analysis failed:
ERROR", until an analysis succeeds. Until one succeeds, the requests that
read the analysis answer nothing, and a rename is refused with "no
analysis yet: save the file". A document without a path, such as an
unsaved `untitled:` one, is parsed and coloured but never analyzed, so
those requests answer nothing in it.

Diagnostics are published to every file they name, opened or not. An
open file shows its syntax errors and the diagnostics of the analysis
of its program that read it, which move with the edits made since: one
whose text an edit replaced is dropped, until the next save. A file no held analysis names any more is
cleared. A file's diagnostics are sent only when they differ from the
ones last sent to it, and an empty list only to clear some. A diagnostic's `notes` are its related locations.

The functions that read the analysis take a position, a `Pos`: a path and
a byte offset in that file's text, the text the analysis read. The client
sends each change as a range and its new text, and the server keeps the
edits since each analysis: it moves a request's position back into the
text the analysis read, and each span the functions return forward into
the text now. A position in text written since has no answer, a span
whose text an edit replaced is left out, and a rename is refused until
every file of the program the analysis read is saved.

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
- answers `nexus/idle`, a request of its own, once every analysis asked
  for has landed and published: a client that needs to know, such as
  the test driver, asks it after a notification;
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

The suite checks the extension under Node, without VS Code
(`test/lib/vscode`). For every grammar, `package.json`'s semantic token
types must agree with the server's legend: each type the server sends is
standard or declared, each declared type is one it sends, each
`superType` is standard, and each type has a TextMate scope. The
scenarios of `test/editor/client/` run `extension.js` against stub
`vscode` and `vscode-languageclient` modules and compare every call it
makes with a golden: the server it runs (bundled, on `PATH`, from user
settings, never from a workspace's, trusted or not), the root it passes,
the document selector, one output channel, restarts that wait for each
other and share a change, a server that does not start, and a
`companion` extension with an identity of its own. `tools/cli` checks
each mistake `identity.json` can have. Nothing in the suite runs VS Code
itself or `vsce`.
