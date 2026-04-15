# Nexus — Universal Parser Generator

Nexus reads `.grammar` files and generates combined `parser.zig` modules (lexer + LALR(1) parser). One tool, any language, zero language-specific code in the engine.

## Architecture

```
{lang}.grammar + {lang}.zig  →  nexus (src/nexus.zig)  →  parser.zig
```

- `src/nexus.zig` — the generator engine (~6300 lines, single file)
- `src/parser.zig` — generated bootstrap parser (self-hosting artifact)
- `src/lang.zig` — lang module for self-hosted grammar parsing
- `nexus.grammar` — self-hosting grammar definition
- `test/{lang}/` — grammar + lang module per language
- `test/golden/` — byte-exact golden files for generated output
- `test/adverse/` — bad grammars that must produce errors
- `test/run` — 23 tests: golden, compile checks, determinism, adverse tests

## Validated Languages

| Language | Grammar | Lang Module | Lexer Wrapper |
|----------|---------|-------------|---------------|
| MUMPS | `test/mumps/mumps.grammar` | `test/mumps/mumps.zig` | Yes — pattern mode, indent dots, spaces exclusion |
| Zag | `test/zag/zag.grammar` | `test/zag/zag.zig` | Yes — indent/outdent, token reclassification |
| Slash | `test/slash/slash.grammar` | `test/slash/slash.zig` | Yes — heredocs, regex, indent/outdent |

## Extension Mechanism

Generated `parser.zig` emits: `pub const Lexer = if (@hasDecl(lang, "Lexer")) lang.Lexer else BaseLexer;`

Lang modules can export a `pub const Lexer` struct wrapping `BaseLexer` for language-specific scanning. The wrapper has full access to `base.pos`, `base.source`, `base.aux`, state variables, and `base.matchRules()`.

### `aux` — Lexer-to-Parser Metadata

`BaseLexer` has an `aux: u16 = 0` field that language wrappers can set per-token. On shift, the parser copies `aux` into `src.id` (when `lastMatchedId` is 0), then resets it. This provides a generic channel for passing lexer-computed metadata (e.g., MUMPS dot-level count) through to the compiler without hand-patching `parser.zig`.

## Token Classification (Critical for Grammar Authors)

Every terminal symbol is classified as **direct** or **promoted**:

- **Direct**: declared in `tokens` block → gets `tokenToSymbol` entry → lexer/rewriter emits it with its own `TokenCat`
- **Promoted**: NOT in `tokens` → arrives as `ident` text → promoted via `@as` based on parser state

**Rule**: If you declare it in `tokens`, the parser expects direct emission. If you don't, the parser expects `@as` promotion.

Rewriter-classified tokens (e.g., `if_mod`, `then_sep`, `do_block`) MUST be in the `tokens` block even without lexer rules. Keywords used only through `@as` (e.g., `if`, `else`, `fn`) should NOT be in `tokens`.

The classification logic in `nexus.zig` (`tokenToSymbol` generation) checks in order:
1. Matches `@as` directive rule name? → promoted
2. Declared in `tokens` block? → **direct** (this takes priority over name matching)
3. Case-insensitive match with a nonterminal name? → promoted
4. `@as` exists but no lexer token? → promoted
5. Otherwise → direct

Step 2 is the key gate: **explicit `tokens` declarations always win over name-based inference.** This prevents rewriter-classified tokens like `THEN_SEP` from being misclassified as keywords just because a nonterminal `then_sep` shares its name.

## Key Grammar Features

### `@as` — Context-Sensitive Keyword Resolution

Unified syntax with ordered resolution and `self` priority checkpoint:

```
@as ident = [fn, isv, ssvn, self, cmd]
```

- Items before `self`: strict matching (`> 0`, shift only)
- `self`: check if IDENT is valid in current parser state; if so, return it
- Items after `self`: permissive matching (`!= 0`, any action)
- Implicit IDENT fallback at end

#### Reduce-Aware Matching (`!` suffix)

Append `!` to a group name for reduce-aware (permissive) matching:

```
@as ident = [keyword!]
```

This generates `getAction(state, sym) != 0` instead of `> 0`, allowing keyword promotion in states where only reduce actions exist. Required for languages with reserved keywords that appear after expressions (e.g., Ruby's `else`, `end`, `elsif`).

Without `!`, those keywords fail to promote because the parser needs to reduce before shifting them. With `!`, promotion succeeds in reduce-only states.

Mode resolution per group:
- `group!` — always permissive (explicit)
- `group` before `self` — strict (shift only)
- `group` after `self` — permissive (positional default)
- `self!` — syntax error (rejected)

### `@code` — Lexer Function Import

```
@code = checkPatternMode
```

Imports a function from the lang module into the generated lexer.

## Coding Standards

Follow `/Users/shreeve/Data/Code/em/CODING.md`:
- Functions/methods: camelCase
- Variables/fields/parameters: camelCase
- Constants: camelCase (not ALL_CAPS)
- Types (structs, enums): PascalCase
- File names: lowercase

Both the generator internals AND generated output follow these conventions.

## Downstream Deployments

- **em** (`/Users/shreeve/Data/Code/em/`) — MUMPS engine. Copy `mumps.grammar` → `em/mumps.grammar`, `mumps.zig` → `em/src/mumps.zig`, run `nexus mumps.grammar src/parser.zig`
- **Zag** (`/Users/shreeve/Data/Code/zag/`) — copy grammar + lang module, run `nexus zag.grammar src/parser.zig`
- **Slash** (`/Users/shreeve/Data/Code/slash/`) — copy grammar + lang module, run `nexus slash.grammar src/parser.zig`

## String Literal Scanning

The inline string scanner generator detects the escape convention from the grammar pattern. If the pattern contains a doubled delimiter literal (e.g., `'""'` or `"''"`), it generates doubled-quote escape handling. Otherwise, it generates backslash escape handling. This is a heuristic based on pattern text, not full structural parsing.

## Self-Hosting Bootstrap

`src/parser.zig` is a checked-in generated parser for `nexus.grammar`. Nexus uses this parser to parse ALL `.grammar` files, including `nexus.grammar` itself.

Grammar-language changes must respect bootstrap discipline:

1. **Backward-compatible changes** — edit `nexus.grammar`, regenerate with `./bin/nexus nexus.grammar src/parser.zig`, commit both.
2. **Breaking grammar-language changes** — stage through a backward-compatible intermediate: first let the current parser accept both old and new syntax, regenerate, then switch to the new syntax, regenerate again.

Do not reintroduce a handwritten parser for bootstrap. The checked-in generated parser is the canonical frontend.

## Test Workflow

```bash
zig build                    # build nexus
zig build test               # run all 23 tests
./test/run --update          # regenerate golden files after intentional changes
```
