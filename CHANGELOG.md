# Changelog

## Unreleased

### Added

- `@lsp` (preamble or @parser section), its lexical lines: a language's
  names and scopes in terms of its `@schema`, so that the language
  server `nexus --editor` writes gives the outline, go to definition,
  references, document highlights, rename, completion of the names in
  scope and hover with no code in `hooks.zig`
  ([GRAMMAR.md, "Names and scopes"](docs/GRAMMAR.md#names-and-scopes)).
  `scope KIND ... [unordered]` opens scopes; `define KIND.ROLE
  SYMBOLKIND` makes a leaf a definition, with `when ROLE ["text"]` and
  `when ^KIND.ROLE ["text"]` (a role's text or presence, the node's or
  its parent's), `outer`, `member`|`lexical`, `value:`, `type:`,
  `doc:ROLE`|`doc:leading`, `export:ROLE`|`export:^KIND` and
  `detail`|`detail:..ROLE`; `use TOKEN ...` makes the other leaves of a
  token uses; `skip KIND.ROLE ... [when ...]`, `builtin "name" ... |
  TOKEN`, `doc TOKEN [strip "text"]`, and `undefined error|warning`,
  diagnostics at the names nothing defines. Every mistake is a located
  error. With
  `@lsp`, `--editor` writes `server/src/scopes.zig`, the names engine,
  and the tables in `language.zig`; the server indexes each open file's
  current text, after every change.
  A rename is checked: refused unless the renamed texts, indexed again,
  resolve every name as before.
  A function `hooks.zig` writes (`symbols`, `symbolAt`, `describe`,
  `visible`, `members`) replaces the grammar's names for its features. The
  generated parser is the same with or without `@lsp`. The Zig grammar
  declares Zig's names, and `grammars/zig/compare-scopes` checks them
  against the compiler's (std.zig.AstGen): over the 2,713 files of Zig
  0.17.0's source AstGen accepts, 951,390 resolved uses and no
  disagreement
  ([grammars/zig/README.md](grammars/zig/README.md#names-and-scopes)).
  Tally, the editor suite's language, has `@schema` and `@lsp`; its
  `names/` server answers from `@lsp` alone, `stub/` is built without
  it.
- `@lsp`'s lines of files and members
  ([GRAMMAR.md, "Names and scopes"](docs/GRAMMAR.md#names-and-scopes)):
  `import KIND.ROLE [when ...] [file "{}.ext"]` (a node imports the file
  its leaf names, a string's contents or a name: a module's file, else
  that path relative to the importing file), `member KIND.ROLE of:ROLE`
  (`a.b`: `b` among the members of what `a` denotes), `qualify
  KIND.ROLE in:ROLE` (`LABEL^ROUTINE`: a name of the file an import
  names) and `nominal TOKEN [ns:NAME]` (names of a namespace, one per
  text across the workspace, with no declaration). What a definition's
  `value:` denotes (an import, a container, an alias), else its `type:`,
  gives its members; an ordered scope (a block's) has none; a value
  whose type needs inference answers nothing. Every mistake is a located
  error, each with an adverse test. The server resolves across files:
  definition, hover and completion of members (`std.mem.eql`), of
  qualified names and of imports; references and rename across the
  workspace (the open documents and the files of the language's
  extensions under the workspace folders), a rename checked over every
  file that holds either name; files not open read from disk and their
  indexes kept while their text is the one read. A module's name
  (`@import("std")`) finds its file through the client's `modules`
  option (`PREFIX.server.modules` in the extension, written for a
  grammar with `import` lines), else the language's `resolveImport`
  (a new function of `hooks.zig`). A builtin's name may be a `member`
  definition (an enum's field `true`). Without `export:`, other files
  see every name they reach. The Zig grammar's `member field_access.name
  of:operand` and `import builtin_call.args when name "@import"` resolve
  `std.mem.eql`, and `grammars/zig/compare-members` checks every member
  and import against a resolution of its own over std.zig.Ast: over the
  2,898 files of Zig 0.17.0's source, 143,947 members resolved (126,481
  through imports), 47,834 more each a declaration of its name, 325,845
  unresolved by design, none missed, none wrong; 4,809 imports
  resolved, none wrong. A definition on a 1.5 MB file (Sema.zig) that
  leads into std, and completion after `std.mem.`, take about 1 ms once
  the files are indexed (safe mode); the first that reads std.zig and
  mem.zig, 7 ms. Rote (`test/rote`) is the language of the sessions of
  `qualify` and `nominal`.
- `@lsp`'s lines of assignment, colours and words
  ([GRAMMAR.md, "Assignment, colours and words"](docs/GRAMMAR.md#assignment-colours-and-words)):
  `bind KIND.ROLE SYMBOLKIND [when ...]` (an assignment's target defines
  its name unless a definition of it is in sight there, which it then
  uses; the binds resolve in the order of the text, after the walk);
  `color KIND.ROLE SCOPE [MODIFIER ...] [when ...]` and `color KIND
  start|end SCOPE ...` (the semantic token of a role's leaf, and of every
  name of the definition it makes, or of a node's first or last token;
  SCOPE one of `@highlight`'s, MODIFIER one of LSP's ten); `words "lit"
  ...` (completion words beside the grammar's, for the keywords a lang
  Lexer makes). `when ROLE:KIND` (the role holds a KIND node) joins the
  conditions of every line that takes `when`. Every mistake is a located
  error, each with an adverse test. The server's semantic tokens carry
  the colours, a use and a member (in another file too) its
  definition's, without `declaration` and `definition`; the legend has
  LSP's token modifiers. Jot (`test/jot`) is the language of the
  sessions of `bind`, `color` and `words`, with a lang Lexer that reads
  `loop` as a keyword where it starts a line and `local` before a name;
  Tally colours its
  functions and parameters, and the Zig grammar its functions,
  parameters, constants (`readonly`), the types it defines (`const S =
  struct {...}`, by `when init:container_decl`), enum fields, error
  names, enum literals and error values (`grammars/zig/server/`).
- A `color` line's SCOPE may be one of the 14 semantic token types of
  LSP that no `@highlight` scope stands for, spelled as LSP spells them:
  `namespace`, `class`, `enum`, `interface`, `struct`, `typeParameter`,
  `variable`, `property`, `enumMember`, `event`, `method`, `macro`,
  `regexp`, `decorator`
  ([GRAMMAR.md, "The lines"](docs/GRAMMAR.md#the-lines)). An LSP type
  that a scope of another name stands for is a located error that names
  the scope to write (`number`: `constant.numeric`; `parameter`:
  `variable.parameter`; `modifier`: `storage.modifier`). The server's
  legend is the 19 scopes, then the 14, always, in that order; the
  editor files of `@highlight` are unchanged, so the 14 colour only
  through semantic tokens. VS Code knows each, so `package.json`
  declares none and gives none a TextMate scope. The Zig grammar colours
  a struct's fields `property` and its `var`s `variable`.
- Keyword completion parses once to the cursor, then tests each word
  against a copy of the parse stack: the generated server's `parser.zig`
  is the module `--spans` generates followed by the runtime's `complete`
  section (`pauseAt`, `takesAt`, written only there). The lexer reads
  each word from where the parse left off, through the lang module's
  `Lexer` and `Parser` when it has them, followed by the text after the
  cursor or by a name. On Zig 0.17.0's lib/std/zig/Parse.zig (safe
  mode) a completion takes 1.8 ms where it took 36 ms, and on
  src/Sema.zig 17 ms where it took 509 ms; over 1,732 positions of the
  two files the keywords are the same but in comments, where none are
  offered now, and at one position after a binary operator at the end of
  a line.
- `nexus --describe` writes `@lsp` as read (`lsp`, null without it;
  [GRAMMAR.md, "Describing a grammar"](docs/GRAMMAR.md#describing-a-grammar)).
  `format` stays 1: a key is added.
- Doc tests: a ` ```session ` block, then an ` ```out ` block, is a
  session the last grammar's language server must answer as shown;
  `test/lib/lsp` takes `initialize quiet`, which prints nothing of the
  result.
- `@messages` (preamble or @parser section): syntax errors a grammar
  knows to be common get messages of their own, by example
  ([GRAMMAR.md, "Messages"](docs/GRAMMAR.md#messages)). Each line is
  `at|after [start!:] sentence → "message"`: the sentence is grammar
  symbols as rules write them, its last element the token the parser
  cannot take, or a choice `( A | B )`; `TOKEN("text")` guards on the
  token's text; `{got}` and `{expected}` are the automatic message's
  token and list. Generation runs each example through the parse table
  as the parser runs input and keys it on the failure state (`at`) or on
  the anchor of the error's reduction chain (`after`), checked on every
  generation: an example the parser takes, one it rejects early, two
  entries for one key, an unknown name or placeholder, a guard on a rule
  or with a text the lexer never gives the token are located errors.
  `writeFailure` (so `writeError`, every one of a tolerant parse's
  `failures`, and the generated language server) uses the matching
  entry: `at` first, then `after`, a guarded entry before an unguarded
  one. Only the error path looks; a grammar without `@messages`
  generates the same bytes as before. `nexus check --messages grammar`
  prints the coverage: each place an `after` entry can key on that has
  none, with its shortest example and automatic message, then how many
  have one. The Zig grammar has 31 entries: over the 98 inputs both it
  and std.zig.Ast reject, 43 errors are now Ast's text word for word
  ([grammars/zig/README.md](grammars/zig/README.md#syntax-errors)).
- Clause rules: a rule with no actions whose every alternative labels the
  same roles in the same order fills those roles of the node of every
  alternative that uses it, as if its labels were written there, and is
  parsed by one set of states wherever it is used
  ([SEMANTICS.md](docs/SEMANTICS.md#clause-rules)). A grammar that
  repeats a run of optional parts across rules writes it once:
  `sig = [params:params] [result:result]`, then `"fn" name:IDENT sig
  body:block → (fn)`. Such a rule was an error ("label fills a role, but
  the action builds no schema node"), so no grammar changes meaning.
- The progress output of generation and `nexus check` names the
  alternative whose `[...]` groups and choices make the most rules when
  it makes 32 or more (`Expanded: rule 'x' (line N): one alternative
  makes M rules, ...`).
- `nexus --editor [--lang <file>] <grammar> <dir>`: a language's VS Code
  extension and language server, from a grammar with `@highlight`
  ([LSP.md](docs/LSP.md)). `<dir>` gets the files of `--highlight all`,
  the extension's `vscode/package.json` and `vscode/extension.js`, and
  `server/`, a Zig project that builds `LANG-lsp`: the grammar's parser
  with spans, the server (`lsp.zig`), the grammar's table for it
  (`language.zig`), with `--lang` the lang module and the files it
  imports, and `hooks.zig`, written only when missing. From the grammar
  alone the server gives syntax errors, semantic tokens, folding,
  selection ranges and keyword completion. Each function of `hooks.zig`
  a language fills in turns on the features it serves: over one file's
  parse (`parseDiagnostics`, `tokens`, `symbols`, `folds`, `format`), its
  own diagnostics and tokens, the outline, folds and formatting; over an
  analysis of the program (`analyze`, `symbolAt`, `typeAt`, `describe`,
  `members`, `modules`, `visible`, `signatures`, `references`,
  `renamable`), diagnostics across files, hover, definition, type
  definition, references, highlights, rename, member, module and scope
  completion, and signature help. A function left as written
  (`lsp.todo`) is not advertised. The server holds one analysis per
  program root, up to eight, so separate programs keep theirs side by
  side; folds and selection ranges end at a node's last solid token, not
  the blank lines and comments after it; the innermost selection range is
  the token at the cursor; a file's diagnostics are sent only when
  they change; `analyze` runs on a task of its own while requests are
  answered; and edits arrive as ranges, so positions and diagnostics move
  with unsaved edits. The suite builds every grammar's server and drives two
  through sessions (`test/lib/lsp`, `test/editor/`).

- `@highlight` (preamble or @parser section): how editors colour the
  language. Metadata lines (`language "Rig"`, `scope-name source.rig`,
  `extensions rig`, optional `line-comment`, `block-comment`, `indent`,
  `dedent`) and entries `SCOPE targets [contexts] [within TOKEN]`, one of
  19 scopes (each mapped in GRAMMAR.md to a TextMate scope, a
  highlight.js class and a Vim group). Targets are literals, token names
  and `@keywords` groups, or one pattern in the @lexer syntax with
  `scope:( ... )` captures; contexts are `after P`, `not after P`,
  `before P`, `not before P` (fixed length), `line-start` and
  `line-end`; `within TOKEN` colours text inside a token, which becomes a
  region (literal prefix, body, literal-ended suffix). A line indented
  further than the block's first continues the entry above. Every
  mistake is a located error (GRAMMAR.md, "Editor support", "Checks").
  `@highlight` changes nothing in the generated parser: a grammar
  generates the same module with or without it.
- `nexus --highlight <target> <grammar> [out]`, targets `textmate`
  (.tmLanguage.json), `language-configuration` (VS Code),
  `highlightjs` (an ES module: `export const extensions`, and
  `export default function (hljs)` returning `name`, `aliases`,
  `keywords`, `contains`) and `vim` (a syntax file), and
  `nexus --highlight all <grammar> <dir>`, which writes
  `vscode/syntaxes/<id>.tmLanguage.json`,
  `vscode/language-configuration.json`, `vim/syntax/<id>.vim` and
  `highlightjs/<id>.js`, `<id>` the last part of the scope name. The
  recommended place is `editors/` beside the grammar.
- `nexus --describe <grammar> [out]`: the grammar as JSON (`"format": 1`,
  fixed key order): tokens with their parser terminal and display name,
  lexer rules with a portable regex, state variables, keyword tables,
  trivia, `@highlight` and the schema (GRAMMAR.md, "Describing a
  grammar"). It works with or without `@highlight`.
- `nexus.grammar` and the Zig grammar have `@highlight`; the suite checks
  each grammar's editor files by what they colour (`test/lib/highlight`:
  reference TextMate and highlight.js tokenizers, and Vim itself, which
  the suite now needs) and pins `--describe` for every grammar.
- More than one syntax error per file. `Tolerant.failures` holds every
  error `parseTolerant` repairs past, in source order, the first being
  `failure`, each worded and placed as the strict parse words and places
  its error; a later error is reported once `Tolerant.cascade` (3)
  tokens of the input have been shifted since the last one reported, so
  the errors one mistake sets off are one, and at most
  `Tolerant.maxFailures` (100) are
  ([SEMANTICS.md, "Tolerant parsing"](docs/SEMANTICS.md#tolerant-parsing)).
  `writeFailure(w, failure)` writes any of them as `writeError` writes
  the first; each `Failure` carries what it expected (`expectation`).
  The generated language server reports every one for a grammar with
  `@repair`, and the strict parse's one error otherwise; a
  `parseDiagnostics` hook still replaces them. Strict parsing is
  unchanged.
- `word-chars C`, an optional `@highlight` metadata line: the characters
  of words, one character class (`word-chars [A-Za-z0-9%]`), by default
  `[A-Za-z0-9_]`. A literal that starts or ends with one does not match
  next to another, in every editor file; `--describe` gives it as
  `highlight.word_chars` (`"format"` stays 1: the key is new).

### Changed

- The language server (`lsp.zig`) is the same file for every grammar,
  and serves the names of `@lsp` when `language.zig` declares them; a
  server without `@lsp` answers as before. `scopes.zig` is a file of the
  server, so a lang module named so (or importing one) is not copied
  into it.
- `hooks.tokens` takes the grammar's tokens to adjust:
  `tokens(arena, path, text, grammar: []const lsp.Token)`; one with three
  parameters is a compile error that says so. `lsp.Token` has
  `modifiers` (`lsp.Modifiers`, LSP's ten, all off by default), which the
  server sends; its legend lists them (`modifier_legend`).
- Keyword completion offers a word where the parser takes it as other
  than a name: a contextual keyword (`@as ... [ctx!]`) the parser takes
  at the cursor only as a name is no longer offered there, nor is any
  word inside a comment or a string.
- `--describe`'s `lsp` has `binds`, `colors` and `words`, and each
  `when` a `kind` (null but for `ROLE:KIND`). `format` stays 1.
- Syntax errors of every generated parser are short and placed where a
  reader looks ([SEMANTICS.md, "Syntax errors"](docs/SEMANTICS.md#syntax-errors)).
  `writeError` lists what the parser can take after the reductions it
  would make without the offending token, from the last `@errors`-named
  rule they complete onward (every module has `namedRules`), and names
  that rule:
  `expected ';' after an expression, got 'pub'` where it listed every
  token that could follow the operand, 65 for Zig. A token that is not
  the grammar's (`err`) shows its text, `got ';'`. When the offending
  token starts on a later line than the end of the token before it, the
  error is at that end, zero width: `Failure` has `at`, where the error
  is reported (`span` is still the token), and the generated language
  server's diagnostic range is `at`. Only a failed parse does this
  work; parsing speed is unchanged. `expected(state)`,
  `expectedNames(state, buf)` and `maxExpected` are unchanged.
- An `@highlight` entry with a context, `line-start` or `line-end` may
  name a literal, token or `@keywords` group that another entry lists
  (`storage.modifier '*' not before … after …` beside `operator "*"`);
  only entries without contexts claim a target. Rig's workaround of
  writing `[*]` (a pattern) keeps working.
- The VS Code extension of `nexus --editor` has an identity of the
  language's own, `vscode/identity.json` (written with the defaults when
  missing, then `Kept` like `hooks.zig`; every mistake in it a located
  error): `name`, `displayName`, `description`, `publisher`, `version`,
  `license`, `repository`, the settings prefix `settings`, and `mode`.
  The defaults clash with no official extension: `nexus-LANG`,
  `Language (Nexus)`, publisher `nexus-local`, settings
  `nexus-LANG.server.*`. `mode: "companion"` contributes no language and
  no grammar, only the client, beside another extension that contributes
  the language ([LSP.md](docs/LSP.md#the-extensions-identity)).
- The extension's client: `server.path` comes from user settings only
  (`"scope": "machine"`, restricted in untrusted workspaces, and read at
  user level), so a workspace never chooses the program that runs; a
  relative `server.root` is relative to the first workspace folder; the
  documents are those of the `file` and `untitled` schemes; restarts
  share one output channel, dispose of a client that did not start, and
  run one at a time, changes that come together sharing one. Each
  semantic token type VS Code does not know has a standard `superType`
  (`keywordControl` a keyword, `constantNumeric` a number, ...), so
  themes colour it. `vscode/` gets a `README.md`, a `.vscodeignore`
  and a `license` (and, when set, `repository`) in `package.json`, for
  `vsce package`.
- The suite needs Node: it checks every grammar's `package.json` against
  the server's legend, and runs `extension.js` against stub `vscode`
  modules (`test/lib/vscode`, `test/editor/client/`).

### Fixed

- The Vim syntax file gives each region a `matchgroup`, so a contained
  escape can't overlap its opening delimiter. An empty string in a
  language whose strings double their quote (M's `""`, Rig's `''`) was
  read as an escape, and the string ran on into the following lines.
  Migration: regenerate `editors/` (`nexus --highlight all`).
- A context on an entry with several targets (literals, a `@keywords`
  group) binds to every target: the editor files group the alternation,
  `(?<=…)(?:a|b|…)(?!…)`, where it bound only the first and the last.
- A pattern's top-level alternation stays whole when a context, a token's
  trailing context, `line-start` or `line-end` stands around it:
  `line-start ([a-z]+ | [0-9]+)` is `^(?:[a-z]+|[0-9]+)`, where the
  number matched anywhere.

Additive, but for the fourth parameter of a `hooks.zig`'s `tokens`.
Downstream:
- Rig, em, nexis: `@lsp` is new syntax (`@lsp` was an error), so no
  grammar changes meaning, and generated parsers are byte for byte the
  same; a server written by `--editor` without `@lsp` answers as before.
  Optional: declare a language's names, then drop the `hooks.zig`
  functions they serve. It needs `@schema` (Rig, em; nexis would add
  one). For instance `scope KIND unordered` for a file or module kind,
  `scope` for the kinds of functions and blocks, `define fun.name
  function outer detail:..body` for a function's name, `define
  label.name function doc:leading` for an M label, `use IDENT`, and
  `member` for the leaf after a member operator. No lang module of
  theirs is named `scopes.zig`.
- Rig, em, nexis: the lines of files and members are new syntax (each
  was an error), so no grammar changes meaning and generated parsers are
  byte for byte the same. Optional, each in its own repository:
  - Rig: `member member.name of:object` for `a.b`, `import use.name`
    (with `file "{}.rig"`) for `use`, and `type:` on the definitions
    whose declared type gives their members; methods resolve through a
    receiver's declared type, not its inferred one.
  - em (MUMPS): `scope routine unordered`, `define label.name function
    doc:leading`, `import ref.routine file "{}.m"` and `qualify
    ref.label in:routine` for `DO LABEL^ROUTINE` (a `ref` without a
    routine stays a label of its own routine), `nominal GVAR
    ns:globals` for globals (one name across the workspace, renamed
    everywhere at once), and a `resolveImport` in `hooks.zig` for
    VistA's file names (`%` to `_`) and search path, or the client's
    `modules` setting for a fixed map. Locals, scoped by `NEW`, stay
    unnamed or `nominal LVAR ns:locals`.
  - nexis: with a `@schema`, the same lines as Rig's for its imports
    and members.
  - All: a `hooks.zig` written by an earlier `--editor` lacks
    `resolveImport`, which is then not written (no change needed); add
    `pub const resolveImport = lsp.todo;` to keep the stub's list whole.
    A `PREFIX.server.modules` setting appears in `package.json` once
    the grammar has an `import` line.
- Rig, em, nexis: `bind`, `color`, `words` and `when ROLE:KIND` are new
  syntax (each was an error), so no grammar changes meaning, and
  generated parsers are byte for byte the same (only the server's
  `parser.zig` has the `complete` section). A `hooks.zig` that writes
  `tokens` adds the fourth parameter, `grammar: []const lsp.Token`
  (return it to keep the grammar's tokens). Optional, each in its own
  repository:
  - Rig: `bind set.target variable` for its assignments (a shadowing
    `set` binds as another does: its `op` is a tag, and `when` reads a
    leaf's text); `color` lines for the roles its classifier
    (src/editor.zig) colours: `color fun.name function declaration`
    and the same of `sub.name`, `variable.parameter declaration` for
    parameters and captures, `type declaration` for the names of
    `struct`, `enum` and `type`, `constant` for enum literals and
    symbols, `label` for labels, `function.builtin` for builtins, and
    `color KIND start|end storage.modifier` for its sigils (`move
    start`, `propagate end`, ...); a method and a property take LSP's
    `method` and `property` (below), and the `control` modifier, which
    LSP lacks, stays with the `tokens` hook, which now gets the
    grammar's tokens to adjust. And
    `words "obj" "rarely" "new" "of" "called" "inline"` (`else` is a
    word of the grammar already): checked on a copy of Rig's grammar,
    the server offers `obj`, `new` and `rarely` at the start of a
    statement and none of them inside an expression, and stops offering
    `from`, `keeps`, `once`, `static` and `unique` where they would be
    names.
  - em (MUMPS): `color` for labels (`color label.name label
    declaration`) and for the name of a `DO`'s routine; `words` for any
    command the lang Lexer makes from a name.
  - nexis: with a `@schema`, `bind` for its assignments and `color` for
    its functions and parameters.
- Rig, em, nexis: a `color` line's LSP types are new syntax (each was an
  error), so no grammar changes meaning, generated parsers are byte for
  byte the same, and `package.json` is unchanged. The server's
  `lsp.Scope` gains the 14 after `invalid`: a `hooks.zig` that switches
  over it exhaustively adds them or an `else`. Optional: Rig's methods
  and properties (`color ... method`, `color ... property`) in place of
  its `tokens` hook's; em and nexis, any name LSP's types fit better
  than a scope.
- Rig, em, nexis: `@messages` is new syntax (`@messages` was an error),
  so no grammar changes meaning, and a grammar without it generates the
  same parser. Optional: write the messages a language words by hand in
  its grammar, as examples, and drop the hand-written code:
  `nexus check --messages GRAMMAR` lists the places that have none, each
  with an example to complete. A token the parser grammar does not use
  (Rig's `err`) is written by its name, `ERR`, with a guard for its text:
  Rig's `after stmt ERR(";") → "…"` needs `stmt` in `@errors` (it is).
  An entry keys on a parser state, and one construct may be parsed in
  several (the first statement of a body and a later one): the coverage
  lists each place, and each needs an example of its own.
- Rig, em, nexis: every syntax error `writeError` writes changes text,
  and many move to the end of the line before; tests that pin its text
  or position change with it. A lang module that words its own message
  from `lastError()` may report it at `at` for the same placement.
- Rig, em, nexis: optional; a language server or tool that reports
  `parseTolerant`'s first error (`failure`) may report each of
  `failures` with `writeFailure(w, f)`. A `parseDiagnostics` hook that
  runs the strict parse keeps its one error; to report every error
  instead, return one diagnostic per entry of
  `parseTolerant(start, budget).failures`, as the generated server does.
  `BaseParser` has no `expectation` field: it is each `Failure`'s.
- Rig, em, nexis: rewrite `editors/` with `nexus --highlight all`. Rig's
  files change in one entry, `("called" | "rarely" | "inline") after
  …`, which coloured `called` and `rarely` anywhere; its sample colours
  as before. em: add `word-chars [A-Za-z0-9%]` to `mumps.grammar`'s
  `@highlight`, so that `_` is an operator next to names and numbers.
- Rig: add `@highlight` to `rig.grammar` (the sample of every token and
  context Rig needs colours as intended with entries of every kind:
  captures for `fun`/`sub` names, `after`/`not before` for the contextual
  `new`, `obj`, `called`, `rarely` and the sigils, `within` for both
  string styles), and write `editors/` with `nexus --highlight all
  rig.grammar editors`.
- em, nexis: optional; the same when wanted.
- Rig, em, nexis: optional; `nexus --editor` writes a VS Code extension
  and a language server (Rig: `--lang rig.zig`, em: `--lang mumps.zig`).
  A project that keeps one checks in `hooks.zig` and
  `vscode/identity.json` and regenerates the rest.
- Rig, em, nexis, with an `editors/` written by an earlier `--editor` of
  this release: run `--editor` again; it writes `vscode/identity.json`.
  The extension is then `nexus-local.nexus-LANG` and its settings
  `nexus-LANG.server.path` and `nexus-LANG.server.root`: uninstall the
  old `LANG.vscode-LANG`, and move `LANG.server.path` to user settings
  (a workspace's is ignored) under the new name. To keep a project's own
  names, set `name`, `publisher`, `displayName` and `settings` in
  `identity.json` (Rig: `"settings": "rig"`); beside an extension that
  already gives the language (Zig's), set `"mode": "companion"`.

## 2.3.0 — 2026-10-15

### Added

- `@longtokens`, a line of the @lexer section: a match longer than 65534
  bytes keeps its category, its `len` is 65535 (standing for "longer"),
  and the lexer records its end as it finishes it (`LongEnds`, the last
  16); the parser copies each long token's end when it reads the token.
  Spans, node and side-band spans, facts, syntax errors, tolerant repairs,
  `@as` lookups and the `pre` of the next token use the real end. Every
  generated module has `longTokens` and the new `BaseParser.tokenEnd(tok)`,
  `tokenText(tok)`, `leafEnd(src)` and `leafText(sexp)` (`pos + len` and
  the source slice without the directive), and `BaseLexer.token(cat, pre,
  start, end)` (`makeToken` without it). With the directive,
  `Sexp.getText`, `Sexp.write` and `BaseLexer.makeToken` panic on a token
  over 65534 bytes rather than give part of it, `BaseLexer.text` reads the
  lexer's record, and a long token whose end the lexer does not hold fails
  the parse with `error.TokenEndUnknown`. Grammars without the directive
  lex and parse as before. The Zig
  grammar opts in: `maximum_sized_integer_literal.zig` (a 65,537-byte
  literal) lexes, parses and builds its tree as std.zig does, and the Zig
  grammar has no known difference left. Migration:
  - Rig: add `@longtokens` to `rig.grammar`'s @lexer section; read a
    token's or leaf's text with `p.tokenText(tok)` / `p.leafText(leaf)` (or
    `base.text(tok)` in the Lexer wrapper, for its last tokens) instead of
    slicing `pos..pos + len` or `getText`, build computed tokens with
    `self.base.token(...)` instead of `BaseLexer.makeToken`, and drop the
    `too_long` error and the 65535-byte comment skip (a comment of any
    length is one token); handle `error.TokenEndUnknown` where the parse's
    errors are switched on.
  - em, nexis: nothing required.

- `Span.text(source)`: the source a span covers, clamped to the source,
  so a span a lang wrapper builds past the end (or a reversed one) gives
  the empty string instead of an out-of-bounds slice. Additive; Rig can
  replace `diag.textOf` and `diag.textBetween` with it.
- `@keywords`: keyword tables declared in the grammar. Each indented line
  is a group, `name [caseless] [base N] entry ...`, with entries `word`,
  `PRE[REST]` (every prefix of PREREST at least as long as PRE),
  `"quoted word"`, `entry:NAME` (its terminal) and `entry=NAME` (an alias
  of the group's terminal NAME). The module exports, per group `g`,
  `pub const GId = enum(u16)` (the terminals in order, ids from 1 or `N`)
  and `pub fn gAs(text) ?GId`, and `@as TOKEN = [g]` uses them with or
  without `@lang`. Generation rejects two entries that accept one word,
  and every other malformed table (GRAMMAR.md, "@keywords"). The Ruby and
  Slash grammars here declare their keywords this way; their lang modules'
  tables are gone. Additive: grammars without `@keywords` generate the
  same parsers. No migration required.

  A downstream grammar may replace a hand-written `GId`/`gAs` table: list
  the words in `@keywords`, delete the lang module's enum and lookup (or
  re-export the generated ones, `pub const GId = parser.GId;`; a lang
  module that declares its own for a `@keywords` group fails to build),
  and read ids from `parser.GId`. em's MUMPS tables map one to one:
  `keywords(CmdId, &.{ "B[REAK]", "HALT", "ZT=ZTIME", ... })` with
  `CmdId = enum(u16) { BREAK = 100, ... }` is the line
  `cmd caseless base 100 B[REAK] ... HALT ... ZT=ZTIME`, with the entries
  in the enum's order (ids follow the order of the entries that are not
  aliases); likewise `fn` (base 200), `isv` (300) and `ssvn` (400), and
  em's overlap proof is the generator's. Rig's reserved-word table maps
  words to token categories for its lexer wrapper, not to `@as` ids, and
  stays as it is.

- `writeExcerpt(w, span)`: the source line holding a span and a line
  marking it with `^~~`, for a diagnostic under `writeError`'s message.
- Tolerant parsing returns `pieces` when it cannot complete: the finished
  subtrees and leaves it had built, in source order, where `sexp` stays
  `.nil`. `Tolerant.drops` counts the new drop repair (below).
- `hasRepair` is public: whether the grammar has `@repair`.
- The Zig grammar has `@repair`; its `tolerant_*` cases show recovery.
  On every fourth corpus file cut off at a random point, 89.5% of the
  broken inputs get a full tree (68.2% with a minimal repair set and no
  drops), and with a 1-20 byte hole in the middle, 89.8% (74.5%).
- The test driver's `--tolerant N` parses with `parseTolerant`, so
  recovery has cases and trees like any parse.

### Changed

- The real-language grammars live in `grammars/` (`grammars/zig`,
  `grammars/rig`, `grammars/mumps`, `grammars/nexis`, `grammars/ruby`,
  `grammars/slash`), apart from the feature suites in `test/`.
  `./test/run` runs both; test ids are unchanged (`rig/...`, `gen/zig`).
  Generated code is unchanged. Migration: Rig, em and nexis re-sync their
  copies into `grammars/<name>/` instead of `test/<name>/`.
- Tolerant parsing drops unfinished constructs to resume at a real
  `structure` or `terminator` token that no insertion makes acceptable,
  where it deleted that token and the ones after it (SEMANTICS.md,
  "Tolerant parsing", rule 5). Grammars without `@repair` are unaffected;
  none of Rig, em or nexis has one. Migration: none.

### Fixed

- Generated parsers compile for 32-bit targets, WebAssembly among them:
  the runtime's size check on `Sexp` asserted 24 bytes, which holds only
  with 64-bit pointers (a `Sexp` is 16 bytes on 32-bit targets). Every
  grammar suite checks a `wasm32-wasi` build (`wasm32/<grammar>`). One
  generated line changes; migration: regenerate the parser.

## 2.2.0 — 2026-10-10

### Added

- Spreads into fixed roles (schema mode): when element N names a rule
  whose every alternative builds an untagged list of one length k, a
  positional `...N` fills the next k roles of a node and `role:...N`
  fills `role` and the k − 1 after it, so a head shared by several kinds
  (`if`/`while` conditions and captures, a declaration's modifiers) is
  written once, in one rule. Generation checks the length, the roles
  available, and each item's type against its role; an absent optional
  head leaves its roles nil. Additive: both forms were errors before, and
  grammars that do not use them generate the same parsers. No migration.
- Span marks: `-X` on a leading or trailing element of a pattern leaves
  that element out of the span of the node the alternative builds (and of
  the nested nodes of its action), so a
  statement's node can exclude its `;` and the doc comments before it
  (`stmt = -doc:DOC* "var" name:IDENT "=" value:expr -";" → (var)`). The
  element keeps its position and value, and the parent node still spans
  it. Generation rejects a mark inside a group, on a middle element, on an
  alternative that builds no node, or one that leaves the node no element
  that is always there. Applies with `@schema`, and with `--spans` without
  one. Additive: grammars without marks generate the same parsers. No
  migration.

## 2.1.0 — 2026-10-10

### Changed

- Faster generated parsers, with the same trees and the same API.
  Downstream repositories need no edits; regenerate the parsers to get
  the speed.
  - An `@infix` table is generated folded when it parses the same as its
    chain: one rule per operator, decided by precedence in the parse
    table, so an operand no longer reduces once per level. Conflict
    reports and `@conflicts` still name the levels (`infix("+" "-")`).
    Rule and state numbers of such a parser change, and so may the
    expected list of an error inside an expression.
  - A pass-through rule (`A → B`) only replaces the top state, and a run
    of them is climbed in an inner loop; the strict loop keeps the state
    and the token's symbol in locals.
  - Lists with spreads are allocated once at their length; left-recursive
    lists grow without `std.ArrayList`; static lists are unrolled.
  - `X "c"` overrides are marked in the parse table (`xExcludes` entries
    gain the overridden reduction).

## 2.0.0 — 2026-10-03

Changes marked **Breaking** need edits in a grammar or a lang module;
[Migrating](#migrating) lists them per downstream repository.

### Added

- `BaseLexer.makeToken(cat, pre, start, end)` builds a token the way the
  scanner does: a match longer than 65535 bytes is an `err` token 65535
  bytes long, and scanning resumes after the whole match.
- `BaseParser.expectedNames(state, &buf)` gives the reader names of what a
  state expects, each once, in a `[parser.maxExpected][]const u8` buffer.
- `BaseParser.allocator()`, the allocator that holds the trees, for what a
  lang `Parser` wrapper builds. It is a single-threaded bump allocator:
  unlike the arena's own allocator, it is not thread-safe.
- `BaseParser.reset(source)` parses new input in the memory the parser
  holds (the arena keeps its capacity), for loops that parse many inputs.
- `-` as the output file writes the module to standard output.
- Labels inside a top-level `( ... )` or `( ... )?` group fill roles; a
  choice inside a `[...]` group or another choice becomes a rule of its
  own. Both were errors.
- One role may be labeled in different alternatives of a choice (whichever
  matched fills it); an optional choice of literals can fill a tag role
  (`op:("+=" | "-=")?`); labeled tokens in a rest role are one item each
  (`items:IDENT "," items:IDENT`, also through a name that aliases the
  token). All three were errors. A labeled token that can be absent
  there (optional, or in a choice alternative) is an error that says so.
- `@tags` works without `@schema`.
- Rules have no length limit of their own: an alternative has at most
  65534 elements, counting those in its groups and choices at any depth, and
  a grammar at most 65535 symbols, both located errors.

### Changed

Generated API:

- **Breaking: `Tag` is always generated.** Without `@schema` it holds the
  tags the actions produce, in first-seen order, then the `@tags` names;
  it is exhaustive (`_` only when empty). A lang module's `Tag` is not
  read.
- **Breaking: one lexer contract.** Every module has `BaseLexer`, the
  generated scanner, and `Lexer`, the lexer the parser drives (`BaseLexer`
  unless the lang module declares a `Lexer` wrapper). The scanner is
  `BaseLexer.next()`. A lang `Lexer` wrapper holds the generated lexer as
  `base: BaseLexer` (any other field is a compile error, where the parser
  silently lost `aux`) and needs only `init(source)` and `next()`: the
  parser calls nothing else.
- `writeError` names each expected symbol once, so tokens sharing an
  `@display` name are listed once. Locate an error with `lastError()`
  (`span`, `cat`, `state`) rather than the parser's `current` token.
- `NodeInfo`, `SideEntry`, `SideLabel` and `RepairClass` are private.
- A syntax error names the unexpected token by its `@display` name too
  (`unexpected name 'x'`, `unexpected end of line`).

Grammar files:

- **Breaking: `X*`, `X+` and `L(X)` are left-recursive.** A list of n
  items costs O(n) time and memory in the generated parser, where each item
  copied the rest of the list. Trees are unchanged. The `L(X).tail` rules
  are gone, and conflicts that involve a list move to the rule that ends
  it: regenerate and replace the manifest entries `nexus check` reports. A
  list followed by its own separator (`L(X) "," "*"`) needs no declared
  conflict.
- **Breaking: the coverage gate counts presence, repetition and choice.**
  An unused `T?`, `[A B]`, `T*` or choice between fixed texts (`","?`,
  `[","]`, `("+=" | "-=")`) is an error, since leaving it out lets
  different inputs build the same node. Use it, label it, drop it with
  `!X` (an insignificant trailing comma is `![","]`), or opt out with
  `~ "reason"`.
  Coverage errors show groups, choices and lists in source syntax.
- **Breaking: a label that cannot fill a role is an error**, where it was
  ignored: one inside a repeated group or choice (`(A | x:B)*`), or inside
  a group nested in a group or choice. So is a label on a choice with an
  alternative of several elements (`eq:("=" | ":" "=")`), which a
  side-band role dropped for that alternative. Move that part into a named
  rule, or label the elements.
- **Breaking: an unreachable rule is an error** in every run, where `nexus
  check` printed a warning (none with `@as`) and generation emitted the
  dead rule. An `@infix` table no rule uses is an error, and so is a rule
  named `infix` beside one.
- **Breaking: each directive appears once** (`duplicate @x`), except
  `@as`; `@schema`, `@tags`, `@trivia`, `@conflicts`, `@errors`,
  `@display` and `@op` merged repeated blocks. A name given twice in
  `@tags` or `@trivia` is an error.
- **Breaking: every string decodes escapes one way.** Parser literals, list
  separators, `X "c"` hints, `@infix`, `@op`, `@display`, `@errors` and
  `@repair` strings, tag literals, quoted kind names, `tag(...)` values and
  `@tags` names take the escapes of a pattern literal
  (`\n \r \t \0 \\ \' \" \xHH`); any other escape is an error at its
  backslash, where `\c` read as `c` and quoted names kept their
  backslashes. `\xHH` needs two hex digits (`'\x+A'` read as 0x0A).
- **Breaking: a `[...]` whose body can match nothing is an error**
  (`[X?]`, `[X*]`, `[A | B?]`, `[[X]]`), where it surfaced as an undeclared
  conflict, and `[...]` takes no quantifier (`![X]*` silently replaced its
  `?`). `[L(X?)]` remains: it tells an absent list from a list of one empty
  item.
- **Breaking: guard values must fit their variable** (-128..127, `pre`
  0..255), like assigned values, and a rule (or zero-width rule) whose
  guards never hold together is an error: start states are built only for
  the guard configurations values can produce. `{pre = 200}` is allowed
  and `{pre = -1}` rejected.
- **Breaking: a rule that can win only after a leading blank is dead**
  (the scanner skips blanks first), and so reported. A space before a
  quantifier (`'a' +`) says to remove the space.
- **Breaking: a rule a zero-width rule shadows is dead**, and so
  reported: a zero-width rule whose guards hold only where an earlier
  zero-width rule's do (`@ pre > 1` after `@ pre > 0`), and a rule with a
  pattern live only where a zero-width rule fires first.
- **Breaking: an endless reduce chain is a generation error**, including
  an empty reduction alternating with a unit reduction (`d → b`,
  `b → ε`), whose generated parser pushed forever.
- **Breaking: the lexer automata have size limits**: an NFA over 200,000
  states, or subset construction past 4 × 65535 states, is a located
  error, where a pattern whose DFA doubles with each repeat ran out of
  memory (11 GB) without a diagnostic.
- **Breaking: an `X "c"` hint names the terminal its one-byte text stands
  for**, whether the grammar writes that token as the literal `"c"` or by
  name (`LPAREN`, the token the lexer gives exactly `"c"` or `@op` maps it
  to), where only a literal matched; its escapes are decoded. A `"c"` that
  names no token, a token the grammar does not use, text that lexer states
  or guards make two terminals, the `@as` token, another literal's
  terminal, or one terminal named twice on an alternative is a located
  error. Hints group by alternative, so a dead hint beside a used one on
  the same line is reported, and an `X "c"` inside a group is an error.
  Tokens are bound to terminals before the LR stage, so `"(" and LPAREN
  are the same token` is reported before conflicts.
- **Breaking: a capitalized name is a token only if the lexer declares it
  or an `@as` group produces it**: `EXPR` for a rule `expr` is an undefined
  token.
- A lexer action's argument is a number (`rewind(n)`); `word 'c'` is a
  syntax error.
- **Breaking: `after` runs only for tokens the DFA matches that consume
  input** (and `err` bytes), as documented: not after `hold`, `rewind(0)`
  or `( ) / r2` tokens, which reset the variables for the token at their
  own position, nor after zero-width rules. em's `mumps.grammar` has
  `after beg = 0` with held rules; every MUMPS case parses as before.
- A count stored by `counted()` in a state variable saturates at 127 (200
  dots stored -56).
- The zero-width check follows (rule, value) steps: a rule that steps a
  variable toward a false guard is accepted, and a held rule with a pattern
  guarded only by `pre > 0` is accepted.
- A conflict report shows a shortest symbol path to the state, and reports
  of rules that derive no finite input name only the causes. Every LR
  error is located at its alternative's column.
- LR(0) states are numbered breadth-first by first use, independent of
  hashing and the host, so every generated parser's states are
  renumbered: a downstream regeneration shows a large diff in its tables
  (trees are unchanged).
- Manifest entries match rules with `->` in quoted literals and with blank
  runs, and a manifest line may be of any length; a second `over` and a
  count too large for 32 bits are errors.
- Escapes in a tag literal (`op:("\x2b=" | "\n")`) name the decoded text.
- `@code` without `@lang` is reported at the `@code` line.
- An undefined rule or token is reported where it is written.
- Quoted source text in messages is clipped to 60 bytes, a non-ASCII byte
  is shown in hex, and a UTF-8 byte order mark at the start of a grammar
  file is an error naming it.

Command line and build:

- **Breaking: the output file is required**: `nexus g.grammar` without one
  is a usage error (exit 2) where it wrote `src/parser.zig`.
- An output path that names the grammar file (through any spelling or
  link) is a usage error, and nothing is written.
- Output replaces its file atomically: a failed write leaves the previous
  file intact. Through a symlink, the file it names is replaced, and the
  file keeps its mode; other hard links to it keep the old contents. A
  device or pipe (`/dev/null`) is written in place.
- `check` is the command wherever it is the first non-option argument;
  `--dump-sexp` with `check`, `--spans` or `-c` is a usage error; a failed
  write to standard output is an error, not a stack trace (a broken pipe is
  no error).
- `zig build unit` runs the generator's unit tests (the step was
  `test-lowerer`); `zig build test` runs `./test/run`, from any directory.

Tests:

- `./test/run` pins every suite's generated code and every grammar file's
  frontend tree, checks formatting (`tools/fmt`), fuzzes the lexer
  generator (`tools/lexfuzz`, whose rejections its model confirms), checks
  that every generator message is printed by a test (`tools/messages`), and
  checks the README's numbers and the project page's example
  (`tools/readme`). Doc tests cover every tracked Markdown file.
- An adverse test requires exit status 1 and no output file; one suite run
  per checkout (a lock); compiles are skipped when their inputs are
  unchanged; the suite runs with the system's own tools (no GNU
  `timeout`).

### Removed

- **Breaking:** `--slr`. Nexus builds LALR(1) tables only.
- **Breaking:** the `simd_to 'c'` lexer action, which changed nothing (the
  lexer scans `[^c]*` runs with SIMD on its own). Writing it is a syntax
  error.
- **Breaking:** the `@conflicts = N` form, which was parsed only to reject
  it. It is a syntax error.
- **Breaking:** `matchRules` (use `next`), `BaseLexer.reset`, and the
  `text` and `reset` methods of lang `Lexer` wrappers, which nothing called.
- The default output path.

### Fixed

- Start states had transitions on blanks the scanner never feeds them,
  which hid dead rules (`(' ' 'x') | 'x'` after `'x'`).
- An `@lexer` section with tokens and no rules (a lang `Lexer` that scans
  everything) panicked the generator; it generates a lexer that returns
  only `eof` and `err`.
- Printing a tree, a span of a list without a node id, `writeFacts` and
  the test driver recursed per tree level and overflowed the stack on deep
  trees (a long operator chain); every walk uses a heap
  stack.
- The span of a list without a node id ran from its first child's start
  to its last child's end, so it was inverted (start > end) when an action
  put children out of source order (MUMPS `(setmulti value:5 ...2)`); it
  is the least start to the greatest end. `span` panics if its walk runs
  out of memory; `write` and `writeFacts` report that as
  `error.WriteFailed`.
- A grammar-file token longer than 65535 bytes panicked the frontend, and a
  few thousand nested groups overflowed the stack; both are located
  errors (64 levels of nesting).
- Lang lexers that built tokens with `@intCast` panicked on a match over
  65535 bytes (MUMPS indents, Ruby symbols, nexis identifiers and strings,
  Slash heredocs); they use `makeToken`.
- An `@as` keyword whose Id value is 512 or more read past the group's
  symbol map (a panic in safe builds); the maps are sized from the Id
  enum, so any `u16` value works (an Id enum is `enum(u8)` or
  `enum(u16)`).
- An `@as` keyword ordinal matched before a reduction stayed on the token
  when the next state took it as itself.
- `@lang` and the token names of `@op` skipped escape checking
  (`@lang = "l\q"` generated an import Zig cannot read), and an `@op`
  literal written with an escape (`"\x27="`) never matched its literal;
  both are decoded like every string, with located errors.
- A syntax error showed a control byte (a NUL) raw; every byte that is
  not printable ASCII is shown in hex. A repeated directive or section is
  located at its `@`, not at the first name inside it.
- Tolerant repair could choose an insertion that the parse then rejected
  (it simulated the next token without its `X "c"` override) and repeat
  it at the same place until the budget ran out.
- A lexer id (`aux`) set for a token that took an `@as` keyword ordinal,
  or for a token tolerant parsing deleted, became the next token's id.
- A tag named `pass`, a tag literal written with an escape (`op:"\x41"`),
  and a grammar past about 100,000 table entries (a comptime quota)
  generated parsers that did not compile.
- A start symbol named with 255 or more bytes was dropped from `Start`.
- `printError` cut a long expected list at 512 bytes.
- A list extension nested in another (`(...1 (...2 3))`) gave the outer
  list a fresh node id.
- The empty leaf of `~N` was placed at 1:1; it is placed where its element
  starts.
- Tolerant parsing at end of input took O(budget²) time; insertions that
  only nest a construct deeper are bounded.
- A multi-element `[A B]` group inside a group or a choice crashed the
  generator; it is a located error.
- Aliases that form a cycle (`x = y`, `y = x`) are reported as an alias
  cycle, not as an undefined rule.
- An `@infix` base that aliases a token used nowhere else gave a false
  "undefined rule".
- The coverage gate judged a name defined in two blocks as an alias of its
  last block's token; it is a rule, as for expansion.
- A declared kind built only inside an undeclared kind was reported as
  unbuilt and left out of the paste-ready `@schema` block.
- Two labels on one slot role report "labeled twice", not "filled by the
  label and by the action".
- Without a schema, a nested node after an absent optional element was cut
  with the trailing nils: `"a" [b] → (p 1 2 (q 1))` gave `(p a)` for `a`;
  it gives `(p a _ (q a))`.

### Performance

Apple M5, ReleaseFast, against 1.1.0 ([test/bench/BASELINE.md](test/bench/BASELINE.md)):
generating the MUMPS parser takes 4.8 ms instead of about 16.5 ms, and the
generated parsers parse VistA at 65 MB/s instead of 51 MB/s and Rig at
67 MB/s instead of 58 MB/s (one 4 MB file of the test programs of 1.1.0's
Rig grammar).

- Generation: lowering indexes line starts (it was quadratic in file size:
  a 249 KB grammar 2.7 → 0.1 s); the LR(0) builder
  uses dense buckets and the grammar facts are computed once (11% fewer
  instructions on MUMPS); the lexer DFA is minimized with Hopcroft's
  algorithm (a chain-shaped DFA of 5102 states 9.4 s and 1.3 GB → 0.14 s
  and 13 MB).
- Generated parsers: lists are linear (a 40,000-line MUMPS routine 2.5 to
  3.2 s and 5 to 13 GB → 0.01 s and 26 MB); pass-through rules skip
  `executeAction`; static action lists are read-only data; parse memory
  comes from a bump allocator; an `@as` keyword is looked up once per
  token; only tokens that can grow long test their length (19% fewer
  instructions per token when lexing VistA). Parsing all of VistA (86.5 MB)
  takes 1.32 s instead of 1.71 s, Rig 57 ms instead of 65 ms.
- The parse table is an array literal: the MUMPS parser compiles in 0.25 s
  instead of 0.61 s (Debug, semantic analysis).

### Migrating

Regenerate every parser. Then, in each lang module:

- **Tag**: delete a hand-written `Tag` enum. A tag the generated enum
  lacks is one no action builds: list it in `@tags` if the lang code
  needs it. Code elsewhere that names the lang module's `Tag` uses
  `pub const Tag = parser.Tag;`.
- **Lexer wrapper**: delete its `text` and `reset` (nothing calls them),
  rename `base.matchRules()` to `base.next()`, and read a token's text
  with `base.text(tok)`.
- **Hand-built tokens**: build a token whose length is computed with
  `parser.BaseLexer.makeToken(cat, pre, start, end)`, not
  `.len = @intCast(end - start)`.
- **Errors**: take the failing token from `lastError()` (`span`, `cat`,
  `state`) instead of `current`, and the expected names from
  `BaseParser.expectedNames(state, &buf)` with
  `var buf: [parser.maxExpected][]const u8`.
- **Parser wrapper**: allocate with `self.base.allocator()`, not
  `self.base.arena.allocator()` (from one thread: it is not thread-safe).
- **Build**: pass the output file (`nexus g.grammar src/parser.zig`).

Per repository:

- **rig** (`src/rig.zig`): delete `Lexer.text`; `matchRules()` → `next()`
  (21 sites); the identifier probe's `.len = @intCast(end - pos)` →
  `makeToken`; `diagnostic` and the bracket probes read `lastError()`
  instead of `base.current`; `expectedHint` loops over `expectedNames`
  and drops its dedupe; `allocator()` returns `self.base.allocator()`.
  `pub const Tag = parser.Tag;` stays (rig's code names it). In
  `rig.grammar`, the five trailing commas `[","]` (`params`, `tparams`,
  `tatom`, `patatom`, `bars`) become `![","]`.
- **em** (`mumps.grammar`, `src/mumps.zig`): in `@conflicts`,
  `shift L(expr).tail → ε 2` becomes `shift viewarg → expr ":" L(expr) 1`,
  and `shift IDENT* → ε 2` becomes `shift patatom → repcount IDENT+ 1`.
  Delete `Lexer.text` and `Lexer.reset`; `frontend.zig`'s `writeExpected`
  can take its names from `expectedNames`.
- **nexis** (`src/nexis.zig`): replace the `Tag` enum with
  `pub const Tag = parser.Tag;` (`reader.zig` names `nexis.Tag`); delete
  `Lexer.text` and `Lexer.reset`; `loader.zig` (and two parse-error tests
  in `reader.zig`) locate a parse error with `lastError().?.span`, not
  `current`. Its scanner keeps its own long-token encoding through
  `aux` (`srcLen`).
- **slash, nanoruby** check in Nexus 0.10.3 parsers. Porting one of
  them from 0.10.3 starts from this repository's port of its grammar
  and lang module (`test/slash`, `test/ruby`), the reference
  that carries every change below; each item says what changed in that
  port since 1.1.0.
- **slash** (`test/slash`): delete `Tag`, `Lexer.text` and `Lexer.reset`;
  the heredoc, string-definition and UTF-8 identifier and variable tokens
  use `makeToken`.
- **nanoruby** (`test/ruby`): delete `Tag`, `Lexer.text` and
  `Lexer.reset`; `matchRules()` → `next()` (4 sites); symbols, `%w`/`%i`
  arrays, number extension and string segments use `makeToken`.

## 1.1.0 — 2026-10-02

### Changed

- **Zig 0.17.** Nexus builds with Zig 0.17, and the parsers it generates are
  Zig 0.17 code: `@backingInt` and `@fromBackingInt`, `std.ArrayList`,
  `last()`, `@splat` table initializers, struct-of-arrays `@typeInfo`, and a
  non-exhaustive `Role` enum when a grammar has no roles. Regenerate parsers
  with Zig 0.17.
- String literals in generated code keep UTF-8 text as written.
- The generation summary reports the lexer's DFA states:
  `Lexer: 65 tokens, 25 rules, 32 DFA states`.

### Removed

- The `legacy` generator (Nexus 0.10.3) in `test/run`, `test/diff` and
  `test/bench/run`, and `docs/PORTING.md` (it remains at tag `v1.0.0`).

### Performance

Apple M5, ReleaseFast: generated parsers parse VistA 2% and Rig 4% faster;
generating a large grammar's parser takes about 1 ms longer.

## 1.0.0 — 2026-09-23

Nexus 1.0 keeps what 0.10 did (one grammar file, one Zig module, a combined
lexer and LR parser, S-expression actions next to the rules) and rebuilds
everything underneath it. Porting a 0.10 grammar takes a few edits and keeps
its trees: see [docs/PORTING.md](https://github.com/shreeve/nexus/blob/v1.0.0/docs/PORTING.md).

### Added

- **The semantic layer** (`@schema`): node kinds with named, typed roles;
  role-named actions (`→ (set target:1 value:3)`), pattern labels
  (`target:name "=" value:expr → (set)`), choices with labels, nested
  nodes, side-band roles; generation checks the tag inventory (and prints
  it, ready to paste), role filling, coverage of every value-bearing
  element (`!X`, `_:X`, `~ "reason"` to drop or opt out), and static result
  types by fixpoint. Nodes have fixed width. The module gets `Tag` and
  `Role` enums, `ir.get`/`ir.rest`/`ir.has`, compile-time `ir.slot`/
  `ir.width`, and per-kind views (`ir.Set.target`). See
  [docs/SEMANTICS.md](docs/SEMANTICS.md).
- **Spans and node ids**: every tree list carries a node id; `span()`,
  `ruleOf()`, `sideRole()`, `newNode()`, `writeFacts()`. On with `@schema`,
  or `--spans` for any grammar.
- **A lexer generator**: patterns compile through an NFA to one minimized
  DFA with a start state per guard configuration, emitted as direct-coded
  Zig with fast paths derived from the automaton (tight loops, byte tables,
  SIMD scans). New: trailing context `r1 / r2`, `hold`, `rewind(n)`,
  bounded repetition `r{n,m}`, class shorthands.
- **The conflict manifest**: `@conflicts` lists each remaining conflict with
  its cell count and a reason; any drift fails generation and prints the
  conflict's state, items and an example input, and the new manifest.
- **Diagnostics for generated parsers**: `writeError` gives `line:col:
  expected A or B, got C` from per-state expected sets, named by
  `@display` (tokens) and `@errors` (rules).
- `@trivia` (tokens kept aside with positions), `@repair` and
  `parseTolerant` (editor parsing with a generated repair table), `@tags`,
  `@as TOKEN via fn` and `[group via fn]`, `x! = x` to declare a start symbol.
- LALR(1) lookaheads by DeRemer and Pennello (the same tables, computed
  about 80 times faster on MUMPS).
- `nexus --version`, a consistent `--help`, usage errors with exit
  status 2; `nexus check` runs every check generation runs.
- Tested documentation: every grammar and Zig example in the docs is
  generated, compiled and run by `./test/run`.

### Changed (breaking)

- `@conflicts = N` is replaced by the `@conflicts` block.
- Lexer patterns are a real regular-expression language: anything outside
  it is an error, token names carry no behavior, `.` matches newline,
  shadowed rules and patterns starting with a blank are errors,
  `counting()`/`matching()` are rejected.
- `Sexp.list` is a `List` (`items()`, `id`) instead of a slice; `Sexp`
  stays 24 bytes and gains `kind()`, `isKind()`, `items()`, `listOf()`.
- `(tag ...N M)` keeps the written order.
- `@code LOCATION { ... }` blocks are gone (`@code = fn` remains).
- Every generation error is `file:line:col: error:` with exit status 1 and
  no output written.

### Fixed

- A start symbol with several alternatives parses all of them.
- Grammars without `@lang` generate parsers that compile.
- Action positions of any size.
- `X "c"` records every hinted character; a hint that decides nothing is an
  error.
- `>` applies to every expansion of an `[opt]` group.
- Lists with different separators are different lists.
- Conflict reports never mention start markers; list-separator conflicts
  are reported.
- Nothing dead is accepted silently: a literal no lexer rule produces, a
  token written both as a literal and by name, `...N` of a token, and an
  `@as` keyword no group's `Id` enum names are errors (the last one a
  compile error naming it). This exposed Ruby's default arguments and
  `**` splats (now parsed) and MUMPS's `"!!"` operator (removed).
- A grammar without a `name!` rule starts at its first rule.
- Every schema shape and `--spans` parser compiles, `writeFacts` included;
  more than 255 collected tags get a wider `Tag` enum.
- Without an action, an absent optional element is nil in the alternative's
  list however it is written (`[r]`, `r?`, `["x"]` dropped it before).
- `@repair` errors and accessor-name clashes are located; `@repair` may
  name a token by its literal.
- Generated parsers never hang or crash on their input: a cyclic grammar
  (a rule that derives itself) and zero-width lexer rules that could fire
  forever are generation errors; a match longer than 65535 bytes is an
  `err` token; an `X "c"` hint applies to the hinted token only (not to
  every token starting with `c`, nor to a token the tolerant parser
  inserts).
- Size limits (255 tokens, 32766 rules, 32767 states) are located errors
  instead of overflows.
- Spans nest: an empty node at the end of its parent lies inside it.
- `b:["+"]` labels the literal; `(!N ...M)` keeps its nil head when N is
  absent; a `( ... )` group with skipped elements keeps nil elements.

### Performance

Apple M5, ReleaseFast ([test/bench/BASELINE.md](test/bench/BASELINE.md)):
MUMPS generation 29 → 17 ms; VistA (86.5 MB) lexing 331 → 348 MB/s and
parsing 36 → 50 MB/s; Rig parsing 52 → 61 MB/s. The node store costs about
5% (MUMPS) and 3% (Rig) of parse time.

## 0.10.3

The last release of the 0.10 grammar format (tag `v0.10.3`).
