# Changelog

All notable changes to Nexus are documented in this file.

## [0.10.1] — 2026-05-15

### Renamed `BaseSexer` / `Sexer` → `BaseParser` / `Parser`

The v0.10.0 bump introduced the optional sex-stage wrapper under the
names `BaseSexer` / `Sexer`. This release renames them to the
conventional `BaseParser` / `Parser`. The two-stage architecture and
both auto-wires are otherwise unchanged.

### Changed (breaking)

- Emitted `pub const BaseSexer = struct { ... }` → `pub const BaseParser = struct { ... }`.
- Emitted `pub const Sexer = if (@hasDecl(lang, "Sexer")) lang.Sexer else BaseSexer;` →
  `pub const Parser = if (@hasDecl(lang, "Parser")) lang.Parser else BaseParser;`.
- Top-level helper signature: `!struct { sexer: Sexer, sexp: Sexp }` →
  `!struct { parser: Parser, sexp: Sexp }`. Caller pattern changes
  from `defer result.sexer.deinit()` to `defer result.parser.deinit()`.
- The optional `@lang` module export is now `Parser` (not `Sexer`).

### Migration from v0.10.0

For downstream code that adopted v0.10.0 in the last hours:

1. Regenerate `parser.zig`: `./bin/nexus {lang}.grammar src/parser.zig`.
2. Rename references: `parser.BaseSexer` → `parser.BaseParser`,
   `parser.Sexer` → `parser.Parser`, `result.sexer` → `result.parser`.
3. If your `@lang` module defined a custom `Sexer`, rename it to
   `Parser`. The contract is otherwise identical.

For code still on v0.9.1, the combined v0.9.1 → v0.10.1 migration is
to rename `parser.Parser` → `parser.BaseParser` (or adopt the new
`parser.Parser` auto-wire / `parser.parse{Start}` top-level pattern).

### What did *not* change vs v0.10.0

- The two-stage architecture: still `BaseLexer + Lexer` then
  `BaseParser + Parser` with both auto-wires.
- Top-level `parse{Start}(allocator, source)` convenience helpers.
- The "parser is returned by value, must be safely movable"
  contract on custom wrappers.
- Parse tables, action emissions, lowerer, `.sexp` golden output —
  all byte-stable.

The bump is purely a renaming of the parse-stage types from
`Sexer`-flavored to `Parser`-flavored, plus a brief consolidation of
the `Parser` auto-wire emit shape to match `Lexer`'s.

## [0.10.0] — 2026-05-14

### Symmetric Lex / Sex architecture

Nexus now emits a fully symmetric two-stage parser. Every generated
`parser.zig` exposes:

- `BaseLexer` (Nexus-generated) + optional `Lexer` wrapper (from `@lang`)
- `BaseSexer` (Nexus-generated) + optional `Sexer` wrapper (from `@lang`)

Conceptually:

```
BaseLexer → Lexer    →    BaseSexer → Sexer
(Nexus)     (lang, opt)   (Nexus)     (lang, opt)
─────────────────         ─────────────────
   lex stage                 sex stage
```

The lex stage turns source text into tokens. The sex stage turns tokens
into S-expressions. Both stages auto-wire from the `@lang` module — if
the module exports a custom `Lexer` (or `Sexer`), the generated parser
routes through it; otherwise the `Base*` type is used directly. The
conceptual term "parser" survives in prose and filenames; the type
names reflect what each stage actually does.

### Added

- `pub const BaseSexer = struct { ... }` — the raw parser, generated
  from the grammar's `@parser` section.
- `pub const Sexer = if (@hasDecl(lang, "Sexer")) lang.Sexer else BaseSexer;`
  — auto-wire, emitted only when `@lang` is set. Mirrors the existing
  `Lexer` auto-wire.
- Top-level `pub fn parse{Start}(allocator, source) !struct { sexer: Sexer, sexp: Sexp }`
  convenience helper per declared start symbol. The returned `Sexp`
  references arena memory owned by `result.sexer`, so the caller must
  `defer result.sexer.deinit()` to keep the tree alive.

### Changed (breaking)

- The emitted parser type is renamed: `Parser` → `BaseSexer`. Downstream
  code that referenced `parser.Parser` must rename to `parser.BaseSexer`
  (or migrate to `parser.Sexer` / `parser.parse{Start}` for the
  recommended pattern). All per-start-symbol methods (`parseProgram`,
  `parseExpr`, etc.) keep their names but are now declared on
  `BaseSexer`.

### Migration

For a downstream project vendoring a generated `parser.zig`:

1. Run `./bin/nexus {lang}.grammar src/parser.zig` to regenerate.
2. Rename `parser.Parser` references to `parser.BaseSexer`.
3. (Recommended) Adopt the top-level helper:

   ```zig
   var result = try parser.parseProgram(allocator, source);
   defer result.sexer.deinit();
   // use result.sexp
   ```

4. (Optional) Add a custom `Sexer` to your `@lang` module if you want
   post-parse rewriting. It must mirror the `BaseSexer` surface:
   `init(allocator, source) -> Self`, `deinit`, and one
   `parse{Start}() !Sexp` method per start symbol. Because the
   top-level helpers return the sexer by value, the custom type must
   also be safely movable (no self-referential storage).

### What did *not* change

- The grammar DSL syntax in `*.grammar` files. No language has to
  change its grammar.
- The `Sexp`, `Token`, `TokenCat`, `Tag` types or their emit code.
- The `BaseLexer` + `Lexer` (token rewriter) auto-wire — already
  correct, untouched.
- LR(1) parse-table generation, action emissions, or any semantic
  behavior of parsing.
- The lowerer, conflict reporting, or `--dump-sexp` output.

The bump is structural at the emitted-module surface; nothing about
*how* parsing works has changed.
