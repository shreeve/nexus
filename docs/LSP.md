# Editors and language servers

One command turns a grammar file into everything an editor needs for its
language: colouring in VS Code, Vim and highlight.js, a VS Code
extension, and a language server (LSP 3.17) that builds with `zig build`.

```bash
nexus --editor lang.grammar editors
```

The grammar alone gives the syntactic half of the server: syntax errors as
you type, semantic tokens, folding, selection ranges and keyword
completion. A grammar that declares its names and scopes (`@lsp`,
[GRAMMAR.md, "Names and scopes"](GRAMMAR.md#names-and-scopes)) gives
the outline, go to definition, references, highlights, rename, the
names in scope, the members after `.` and hover too, across the files
of the workspace: its imports, members, qualified names and names of
namespaces. The rest (types, the members of a value whose type needs
inference, type errors, signature help, formatting) needs to know what
the program means, which only the language knows. For that
the command writes `hooks.zig`, a file of functions to fill in, each
left as a stub. Writing a function turns on the features behind it, in
place of the grammar's; a stub left alone turns nothing on, and the
server never advertises a feature it cannot give.

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
        ├── scopes.zig                  with `@lsp`: the names of each file, across files
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
- `scopes.zig`, with `@lsp`, indexes the names of each file by the
  tables `language.zig` holds, and resolves imports, members and
  qualified names across files; like `lsp.zig`, it is Nexus's own, the
  same for every language.
- `language.zig` holds what the server needs to know about the grammar:
  the language's name and id, the `@highlight` scope of each token by its
  name or its text, and the words completion can offer. Those are each
  literal terminal, each token whose one rule is a literal, and each
  `@keywords` terminal that is a word, where `@highlight`'s `word-chars`
  says what a word is, and the words of `@lsp words`. With `@lsp`, it
  holds its lines too (`names`), each slot as the parser's `ir.slot` of
  its kind and role.
- `parser.zig` is the parser `--spans` generates, followed by the
  runtime's `complete` section, which only the server's parser has:
  `pauseAt` and `takesAt`, with which completion tests words against the
  parse table.
- With `--lang`, the lang module is copied beside `parser.zig`, as the
  parser imports it, with every file it imports by a relative path. A
  file it imports from outside its own directory, a file that cannot be
  read, and a file named like one of the server's own (`main.zig`,
  `lsp.zig`, `parser.zig`, `language.zig`, `scopes.zig`, `hooks.zig`)
  are errors.

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
grammar (in `standalone` mode), the semantic token types of the scopes
(each mapped to its TextMate scope, and each type VS Code does not know
given a standard `superType`, so a theme colours it either way:
`keywordControl`, `keywordOperator` and `storageModifier` are keywords,
`constantNumeric` a number, `constant` and `constantSymbol` enum members,
`stringEscape` a string, `functionBuiltin` a function,
`variableParameter` a parameter and `variableSpecial` a variable;
`punctuation` and `invalid` have none), and its settings. The 14 types
of LSP's own that the server also sends (`property`, `variable`, ...)
are standard types of VS Code's, which a theme colours by name or by the
TextMate scopes VS Code gives each, so `package.json` neither declares
them nor gives them a scope: no `@highlight` scope, and so no TextMate
scope of the grammar's, stands for them. The server's token modifiers are LSP's ten (`declaration`, `definition`, `readonly`,
`static`, `deprecated`, `abstract`, `async`, `modification`,
`documentation`, `defaultLibrary`), which VS Code knows, so
`package.json` declares none.

| Setting | Meaning |
|---|---|
| `PREFIX.server.path` | the server: a path, or a name on `PATH`; empty means the extension's `bin/LANG-lsp`, else `LANG-lsp` on `PATH` |
| `PREFIX.server.root` | the file the program starts from, which the server analyzes; a relative path is relative to the first workspace folder; empty means each file's own program ([The analysis](#the-analysis)) |
| `PREFIX.server.modules` | with `@lsp` `import` lines: the file of each module name an import names, as `{"std": "/path/to/lib/std/std.zig"}`; a relative path is relative to the first workspace folder ([Names across files](#names-across-files)) |

`server.path` names a program to run, so only the user's own settings
give it: it has `"scope": "machine"`, `package.json` lists it among the
settings an untrusted workspace may not set, and `extension.js` reads
only its user-level value. A workspace's `.vscode/settings.json` never
chooses the server, trusted or not.

`extension.js` starts the server with `vscode-languageclient` for the
language's documents of the `file` and `untitled` schemes (not the
`git:` or diff views of them), and passes `server.root` as the
`root` option, absolute, and `server.modules` as the `modules` option,
each file absolute. A relative root with no folder open is left
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

- **Syntax errors as you type.** On every change, every error the
  tolerant parse repairs past for a grammar with `@repair`
  ([SEMANTICS.md, "Tolerant parsing"](SEMANTICS.md#tolerant-parsing)),
  else the strict parse's error; each worded as `writeError` words it
  (with the grammar's message for it, when `@messages` has one;
  [GRAMMAR.md, "Messages"](GRAMMAR.md#messages)), at the token where the parse failed, or, when that token is on a
  later line than the one before it, zero width at the end of that one
  ([SEMANTICS.md, "Syntax errors"](SEMANTICS.md#syntax-errors)).
- **Semantic tokens.** Each token takes the scope `@highlight` gives its
  text (a literal or a `@keywords` word), else its token name. The token
  types are `@highlight`'s 19 scopes, then, always and in this order,
  the 14 types of LSP's that no scope stands for (`namespace`, `class`,
  `enum`, `interface`, `struct`, `typeParameter`, `variable`,
  `property`, `enumMember`, `event`, `method`, `macro`, `regexp`,
  `decorator`), which only `color` lines give. With `@lsp`'s `color`
  lines, a token they colour takes their scope and modifiers in place of
  it (or beside it, a name with none): a role's leaf, a node's first or
  last token, and each name, in the file or another, of a definition
  whose leaf a line colours, without `declaration` and `definition`.
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
- **Names, with `@lsp`.** Each request reads the names of the file's
  current text, indexed again after each change (a file with syntax
  errors through the tolerant parse, with `@repair`), and of the files
  its names lead to ([Names across files](#names-across-files)):
  - the outline: the definitions of the file's own scope, each with the
    definitions of the scope inside it (a function's parameters, the
    members of the container its `value:` opens), its detail
    (`detail`, else `type:`) beside it;
  - go to definition of the name at the position, in its file or
    another (a member, a qualified name), and of an import's name, the
    file; a name of a namespace (`nominal`) has none; an assignment that
    `bind` takes defines its name, or names the definition in sight;
  - references of the name across the workspace, and its highlights in
    the file; of an import's name, the imports of its file (in the files
    that hold the file's name without its extension, or a module name
    the `modules` option gives it);
  - hover: the definition's detail as code (its name, without one), its
    type, and its doc;
  - completion: after a member's `.` (and at a qualified name), the
    members of what is before it, alone; else the names in sight at the
    position, nearest first, then the keywords; none where the word
    there is a definition's or a skipped role's;
  - rename: the definition and every name of it in the workspace, or
    every name of a namespace's, refused (`-32803`, with the reason)
    when the new name is not one token of the old one's kind, for an
    import's name, and unless every file that holds either name, indexed
    again with the edits made, resolves every name as before, the
    renamed ones to the renamed definition: a rename that would capture
    another name, or that another name would capture, that defines the
    new name twice in one scope, that would make an assignment that
    defines a name assign one in sight, or that gives a namespace's name
    one it has already, is refused;
  - with `undefined error` or `warning`, a diagnostic at each use that
    nothing defines and no `builtin` names, unless the language writes
    `analyze`, whose diagnostics are its own.
- **Keyword completion.** The words of `language.zig` the language takes
  at the cursor as keywords. The text before the word the cursor is in
  is parsed once, through the lang module's `Parser` and `Lexer` when it
  has them, up to the blanks before the word; then the lexer reads each
  word from there, followed by the text after the word, and the word is
  tested against a copy of the parse stack (`parser.pauseAt`,
  `parser.takesAt`). A word is offered where the parser takes it as other
  than what a name that is no word (the word with its last letter again)
  would be, so a contextual keyword the parser takes there only as a name
  is not; a word the lang Lexer makes a keyword of only before a name is
  tested before one too. None when the text before that word already has
  an error, or is inside a token (a comment, a string).

### Names across files

With `@lsp`'s `import`, `member`, `qualify` and `nominal` lines, a name
leads to other files:

- **An import's file.** An import's name (a string's contents, or a
  name) is a module's when the client's `modules` option
  (`PREFIX.server.modules`) names its file, else when the language's
  `resolveImport` gives one; else it is a path relative to the importing
  file, made with `file "{}.ext"` when the line has it. A document
  without a path (`untitled:`) imports modules alone.
- **The text of a file.** An open document's text, saved or not, is the
  one every request reads; a file not open is read from disk, and its
  index kept while its text on disk is the one it read (the 256 used
  last).
- **The workspace.** References and rename search every open document
  and every file of the language's extensions (`@highlight`'s
  `extensions`) under the client's workspace folders (`workspaceFolders`,
  else `rootUri`), in no folder whose name starts with `.`, up to 20,000
  files; of those, only the files that hold the name are indexed.

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
`analyze` written is a compile error, and so is a `tokens` that does not
take the grammar's tokens.

With `@lsp`, a function the language writes replaces the grammar's
names for the features it turns on, one function at a time: `symbols`
the outline, `symbolAt` definition, references, highlights and rename,
`describe` hover, `visible` the names completion offers, `members` those
it offers after `.`; the others are still the grammar's. A function may
import `scopes.zig` and index a text itself (`scopes.index`), or
resolve across files (`scopes.Resolver` over a `scopes.World`), to
build on the grammar's names. `resolveImport` names the file of an
import's module when the `modules` option does not.

| Function | Turns on |
|---|---|
| `parseDiagnostics` | the language's own syntax errors, in place of the grammar's |
| `tokens` | the language's semantic tokens, in place of the grammar's, which it gets to adjust |
| `symbols` | the outline and breadcrumbs |
| `folds` | the language's folding ranges, in place of the grammar's |
| `format` | Format Document |
| `resolveImport` | with `@lsp` `import` lines: the file of a module's name, after the `modules` option |
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
pub fn tokens(arena: Allocator, path: []const u8, text: []const u8, grammar: []const lsp.Token) ![]const lsp.Token
pub fn symbols(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.OutlineItem
pub fn folds(arena: Allocator, path: []const u8, text: []const u8) ![]const lsp.Fold
pub fn format(arena: Allocator, path: []const u8, text: []const u8) !?[]const u8
```

Every offset is a byte offset into `text`. A `Token` is a start, a
length, a `Scope`, one of `@highlight`'s scopes, and `Modifiers`, a set
of LSP's token modifiers (`.{ .declaration = true, .readonly = true }`);
`tokens` gets the grammar's tokens of the file (its scopes and `@lsp`'s
colours, in order) to adjust or replace. An `OutlineItem` is a name, a
`SymbolKind`, its whole range, the range of its name, a one-line detail
and its children; a `Fold` is a range, of comments or not. `format`
returns the whole file formatted, or null when it is formatted already.
An error from any of them answers nothing.

`resolveImport` gives the file an import of `@lsp` names when its name
is a module's (`@import("std")`), not a path: the file's path, or null
to take the name as a path relative to the importing file `from`. The
client's `modules` option answers first. An error answers nothing.

```zig fragment
pub fn resolveImport(arena: Allocator, from: []const u8, name: []const u8) !?[]const u8
```

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
| `completion` | `members` when it gives a list (with `@lsp`, without it: the members after `.` or at a qualified name); else `modules` when it gives a list; else `visible` (with `@lsp`, without it: the names in sight), then the keywords the grammar takes there |
| `hover` | `describe` of `symbolAt`, else `describe` of `typeAt` (with `@lsp`, without `describe`: the name's detail, type and doc) |
| `definition` | the declaration of `symbolAt` (with `@lsp`, without it, the grammar's names give `definition`, `references`, `documentHighlight` and `rename` across the workspace) |
| `typeDefinition` | the declaration in `describe` of `typeAt` |
| `references` | `references` of `symbolAt`; without it, every token of every file the analysis read whose `symbolAt` has the same `id` |
| `documentHighlight` | those references in this file |
| `rename` | those references and the declaration, when `renamable` allows it (by default every symbol renames) and the new name lexes as one token of the same kind as the old name |
| `signatureHelp` | `signatures` |
| `documentSymbol` | `symbols` (with `@lsp`, without it: the grammar's outline) |
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

The editor suite (`test/editor`) builds Tally's server three times: in
`full/` with `full/hooks.zig`, which writes every function but
`references` so the server's own search runs too, and replaces Tally's
`@lsp` names; in `names/` with the `hooks.zig` that `--editor` writes,
so the names come from `@lsp` alone; in `modules/` with that
`hooks.zig` and `resolveImport` written; and in `stub/` with that
`hooks.zig` and the grammar without `@lsp` (a variant's `without` file
names the directives its server is built without), which gives only
what the syntax does. The Rote suite (`test/rote`) builds the server of
a language of routines whose names are qualified (`do add^math`) and
nominal (`$count`). `test/lib/lsp` replays each `.session` file of a
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
that the server compiles; for Zig's, `grammars/zig/compare-scopes` checks
the names its `@lsp` resolves against the compiler's, and
`grammars/zig/compare-members` its members and imports against a
resolution of its own over `std.zig.Ast`
([grammars/zig/README.md](../grammars/zig/README.md#names-and-scopes)).

The suite checks the extension under Node, without VS Code
(`test/lib/vscode`). For every grammar, `package.json`'s semantic token
types must agree with the server's legend: each type the server sends is
standard or declared, each declared type is one it sends, each
`superType` is standard, each type of a scope has a TextMate scope, and
LSP's 14 are standard types with none. The
scenarios of `test/editor/client/` run `extension.js` against stub
`vscode` and `vscode-languageclient` modules and compare every call it
makes with a golden: the server it runs (bundled, on `PATH`, from user
settings, never from a workspace's, trusted or not), the root and the
modules it passes,
the document selector, one output channel, restarts that wait for each
other and share a change, a server that does not start, and a
`companion` extension with an identity of its own. `tools/cli` checks
each mistake `identity.json` can have. Nothing in the suite runs VS Code
itself or `vsce`.
