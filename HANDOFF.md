# HANDOFF.md — the state of Nexus

Read [AGENTS.md](AGENTS.md) first (the rules), then this file (where the
work stands and what comes next). [docs/INTERNALS.md](docs/INTERNALS.md)
is the architecture; [test/README.md](test/README.md) is the suite.

## State

- **Nexus 2.3.0** (tag `v2.3.0`) is the current release: 2.0.0's grammar
  language and generated API, with faster generated parsers (2.1.0),
  fixed-role spreads and span marks (2.2.0), and in 2.3.0 keyword tables
  in the grammar (`@keywords`), tokens of any length (`@longtokens`), both
  opt-in, better tolerant parsing, `Span.text` and `writeExcerpt`, and
  generated parsers that build for 32-bit targets and WebAssembly.
  CHANGELOG.md has each release and the migration steps for every
  downstream repository.
- **Unreleased on main:** `@highlight` (editor support from the grammar:
  `nexus --highlight <target|all>`), `nexus --describe` (the grammar as
  JSON), clause rules, and `nexus --editor` (a VS Code extension and a
  language server whose features a language turns on in `hooks.zig`,
  [docs/LSP.md](docs/LSP.md)), `@messages` (syntax-error messages
  given by example, keyed on parser states, with `nexus check
  --messages` for coverage; the Zig grammar has 31), and `@lsp`'s
  lexical lines, its lines of files and members, and its lines of
  assignment, colours and words (names, scopes, imports, members, binding
  by assignment, colours by meaning and completion words in the grammar,
  which give the server the outline, definition, references, highlights,
  checked rename, the names in scope and after `.`, hover and semantic
  tokens by meaning, across files; the Zig grammar's agree with AstGen on
  every name of the corpus, and with a resolution over std.zig.Ast on
  every member and import); keyword completion tests each word against
  one parse to the cursor; CHANGELOG.md, "Unreleased".
- **The suite is green on macOS (arm64):** `./test/run` → 1106 passed, 0
  failed, 0 known; the generated code is byte for byte the same on Ubuntu
  26.04 (x86_64). The `highlight/*` checks need Vim with `+syntax`.
- **Benchmarks** are in [test/bench/BASELINE.md](test/bench/BASELINE.md).

Verify before you change anything:

```bash
zig version                 # 0.17.0
git log --oneline -4
git worktree add --detach ../nexus-check main   # never test in this checkout
cd ../nexus-check && zig build && ./test/run
```

This checkout's `bin/nexus` is part of every Rig, em and nexis build, and
`./test/run` rebuilds it in debug mode first, so the suite runs in a
worktree ([AGENTS.md, "Downstream"](AGENTS.md#downstream)).

If `zig version` prints an older Zig, the shell's PATH was set before mise
installed 0.17; run `export PATH="$(mise where zig@0.17.0):$PATH"`.

## Open work

1. **Keep the downstream copies current.** Rig, em and nexis run Zig 0.17
   and follow this Nexus's main ([AGENTS.md, "Downstream"](AGENTS.md#downstream));
   `grammars/rig`, `grammars/mumps` and `grammars/nexis`
   hold their grammars and lang modules as their main branches have them, and each
   `test.conf` names the source commit. When one of them changes its
   grammar or lang module, re-sync its copy in its own commit
   ([AGENTS.md, "Downstream"](AGENTS.md#downstream)) and keep
   `./test/run` green. Rig's next grammar change is a `<<%` operator, and
   its `@highlight` with the sample of its highlighting; its re-sync adds
   `grammars/rig/highlight/`.
2. **Slash and nanoruby onto this Nexus.** Their repositories check in
   parsers from Nexus 0.10.3; their grammars and lang modules for this Nexus are
   `grammars/slash` and `grammars/ruby` here. `test/diff` compares the
   trees of a 0.10.3 build (from tag `v0.10.3`) with this checkout's.
3. **Deferred by the owner until em's grammar work is done:** the
   schemaless tree rules for a leading `role:N` head (named only in
   unexpanded alternatives) and for `!X` in a rule's default action. em's
   grammar uses `@schema`, so these rules no longer shape em's trees.
4. **Editors and language servers** ([docs/LSP.md](docs/LSP.md)):
   - The suite drives the server through sessions and the VS Code
     client under Node against stub `vscode` modules
     (`test/editor/client/`), but not the client in VS Code, nor `vsce
     package`; the extension's files are pinned by goldens. The packaging
     recipe of docs/LSP.md (`.vscodeignore`, `--skip-license`,
     `--allow-missing-repository`) has not been run; the opt-in
     `test/vscode/run` of the LSP plan is to check it.
   - A generated lexer reads a byte order mark as text; the server keeps
     positions right after it, but the parse fails there.
   - `@lsp` has every line of the approved plan
     (`.git/lsp/panel/lsp-approved.md`): definition, references, rename
     and member completion across files, through imports (the client's
     `modules` setting, else `resolveImport`), members, qualified names
     and names of namespaces; binding by assignment (`bind`), semantic
     tokens by meaning (`color`) and completion words (`words`). Next:
     hooks in TypeScript or JavaScript over JSON lines; `rig lsp` onto
     the generated server, then servers for em and nexis; a formatter
     from the grammar.
   - Step 3 reads `when ROLE:KIND` (a role holds a node of a kind)
     beyond the approved syntax, for Zig's types (`const S = struct
     {...}`), and `when` on `color`. `color`'s scopes are `@highlight`'s
     19 and the 14 LSP types no scope stands for (`property`,
     `variable`, `method`, ...; `.git/lsp/panel/color-proposed.md`),
     which colour only through semantic tokens: Zig's struct fields are
     `property` and its `var`s `variable`; Rig's methods and properties
     can leave its `tokens` hook for `color` lines.
   - Keyword completion keeps the parse before the last token whose
     lexer had not read past the cursor's word (`pauseAt`), and replays
     from there; a lang Lexer that reads ahead (Zig's) costs a token or
     two of replay. A word a lang Lexer makes a keyword of only by what
     follows it is tested before the text after the cursor and before a
     name: Rig's `called` and `inline`, keywords before `fun` or `sub`,
     are offered only where `fun` or `sub` follows already.
   - Step 1 reads `when` beyond the approved syntax (repeated, `^KIND.ROLE`
     of the parent, a role's presence), `skip ... when`, `define` and
     `skip` on untyped roles, and bare `detail`: Zig needs each to agree
     with AstGen (enum fields kept in Ast's type slot, function types'
     and extern functions' parameters, `_`).
   - The server indexes the open file again on every change (63 ms for
     Sema.zig's 1.5 MB in safe mode, 510 ms in debug); a request after
     that takes about 1 ms (safe), cross-file ones included. Workspace
     references and rename read every file of the workspace that holds
     the name; a very large workspace (VistA's 24,704 routines) reads
     them all from disk on each such request.
5. **`@messages`, deferred by the owner:** a `then` guard that looks one
   token past the error (Rig's `;` before another statement, Zig's `&&`
   against an `&` with whitespace on one side only, which are one token
   to the parser). An `after` example keys on the state its rule names
   reach; a construct parsed in several states (a first statement and a
   later one) needs one example for each, as the coverage report lists.
6. **Untested messages:** `test/lib/messages.allow` lists the generator
   messages no test prints, each with its reason; an adverse test that
   prints one deletes its line.
7. **Smaller items:**
   - `./test/run --update` does not write `.tree` files for
     `test/regress` suites; write them with the suite's built driver.
   - A lang `Parser` wrapper that returns `error.ParseError` on its own
     (rig does) leaves `lastError()` null, so the driver prints the error
     without a position.
   - A label on a non-token value in a rest role reports "is a spread of a
     value that is not a list", which names a spread the user did not write.
   - Doc tests list documents with `git ls-files '*.md'`: an untracked new
     document is not tested until it is added.
   - Generating a grammar of 4,000 chained levels peaks at about 1.4 GB;
     the dense `[state][symbol]` arrays of the lookahead stage dominate.

## Tips

- **Generated code comes from** the runtime template, the string templates
  in `src/codegen/` and the lexer emitter; only the first is seen by
  `zig fmt` and the compiler, so a mistake in the others shows up when a
  generated parser compiles
  ([INTERNALS.md, "Code generation"](docs/INTERNALS.md#code-generation)).
- **Run a subset while iterating:** `./test/run mumps`, `./test/run gen`,
  `./test/run -v regress`; `-j N` limits the workers on a busy machine. A
  failing case's parser stays built for rerunning by hand
  ([test/README.md](test/README.md#files)).
- **Mind the machine's load.** The full suite builds about 95 parsers;
  run it with `-j 2` or `-j 3` while other work is running, and do not run
  benchmarks, fuzzing or several suites at the same time.
- **Benchmark honestly** ([test/bench/BASELINE.md](test/bench/BASELINE.md),
  "Reading a difference").
- **The VistA corpus** (`~/Data/Code/em/misc/vista`, 24,704 routines) and
  Rig's sources (`~/Data/Code/rig`) feed `test/bench/run` and `test/diff`;
  without them the benchmark falls back to the committed cases.
