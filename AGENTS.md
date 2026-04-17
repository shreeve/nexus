# Nexus — Universal Parser Generator

Nexus reads `.grammar` files and generates combined `parser.zig` modules (lexer + LALR(1) parser). One tool, any language, zero language-specific code in the engine.

## Architecture

```
{lang}.grammar + {lang}.zig  →  nexus (src/nexus.zig)  →  parser.zig
```

- `src/nexus.zig` — the generator engine
- `src/parser.zig` — Nexus's own frontend parser, generated from `nexus.grammar` by running Nexus
- `src/lang.zig` — lang module consumed by `src/parser.zig` (Tag enum + lexer wrapper)
- `nexus.grammar` — the grammar DSL described in its own grammar format; begins with the canonical S-expression schema block comment
- `test/golden/*.sexp` — canonical S-expression tree for each in-repo grammar; any AST drift fails the golden
- `test/{lang}/` — grammar + lang module per language
- `test/golden/` — byte-exact golden files for generated output
- `test/adverse/` — bad grammars that must produce errors
- `test/run` — 32 tests: golden parsers, compile checks, determinism, adverse grammars, self-hosted Sexp golden across every in-repo grammar, bootstrap fixed point, and a lowerer negative-shape suite that feeds hand-crafted malformed Sexps and asserts each is rejected with error.ShapeError

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

## Self-Hosting

`src/parser.zig` is the frontend Nexus uses for every `.grammar` file, including `nexus.grammar` itself. It is generated by Nexus from `nexus.grammar`, paired with `src/lang.zig` as its companion lang module. The strict `GrammarLowerer` in `src/nexus.zig` consumes the S-expression tree the frontend emits and produces `GrammarIR`, which the parser generator turns into the emitted `parser.zig`.

The S-expression shape the frontend emits is governed by the canonical schema documented at the top of `nexus.grammar`. The lowerer dispatches on tag alone against that schema; any shape mismatch raises a hard error with a line/column pointer into the @parser section. There are no silent defaults and no heuristic unwrapping.

### Trust ladder

Three CI checks guard the pipeline end-to-end:

1. `test/golden/*.sexp` — canonical S-expression snapshots for every in-repo grammar (nexus, basic, features, zag, slash, mumps). Any AST drift fails the golden with a line-count diff.
2. Bootstrap fixed point — regenerating `src/parser.zig` from `nexus.grammar` with the current binary must reproduce the checked-in file exactly.
3. Lowerer negative-shape tests — 24 hand-crafted malformed S-expression trees fed directly to `GrammarLowerer`, each asserted to be rejected with `error.ShapeError` and a precise diagnostic. This proves the lowerer's strictness claim independent of what the frontend can actually emit. Invoke directly with `./bin/nexus --test-lowerer`.

### Making a grammar change

1. Edit `nexus.grammar`.
2. Run `./bin/nexus nexus.grammar src/parser.zig` to regenerate the frontend.
3. Run `zig build test`. If `nexus-sexp` drifted, run `./test/run --update` to refresh the golden, then commit.
4. Commit grammar, parser, and golden together.

Debugging a frontend issue? Run `./bin/nexus --dump-sexp <grammar>` to inspect the S-expression tree the frontend emits.

## Test Workflow

```bash
zig build                              # Debug build (fast compile, slow runtime)
zig build -Doptimize=ReleaseSafe       # ~8x faster runtime, safety kept (recommended)
zig build test                         # run all 32 tests
./test/run --update                    # regenerate golden files after intentional changes
```

## Performance Notes

- **Generation time scales with grammar complexity.** Small grammars
  finish in a couple ms; MUMPS (529 rules, 832 states) takes ~30ms in
  ReleaseSafe and ~190ms in Debug.
- **`--slr` is ~3× faster than the default LALR(1)** and produces
  identical conflict counts on 5 of 6 repo grammars. Only MUMPS
  benefits from LALR's extra precision (2 fewer conflicts). See
  README's "Parser Algorithm: LALR(1) vs SLR(1)" section for the data.
- **ReleaseSafe ≈ ReleaseFast** for this workload (~2% apart). Use
  ReleaseSafe for shipped binaries — the safety checks are essentially
  free here.
- **Runtime parsers produced by LALR and SLR run at identical speed.**
  The only difference is generation time and (occasionally) conflict
  count.
