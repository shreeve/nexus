<p align="center">
  <img src="docs/nexus-logo-720w.png" alt="Nexus Logo" width="400">
</p>

<div align="center">
  <strong>Generate a standalone Zig lexer + LR parser from one grammar file. Self-hosting, no runtime.</strong>
</div>

# Nexus

Nexus reads a `.grammar` file and emits a single Zig module containing a
combined lexer and LR parser — LALR(1) by default, SLR(1) via `--slr`. Drop
the generated `parser.zig` into your project and build. No parser runtime,
no extra support library, no language-specific code in the engine.

Nexus is self-hosting: it parses its own grammar format with a parser
generated from `nexus.grammar` itself. The bootstrap is guarded by three
CI checks — golden AST snapshots, a fixed-point regeneration test, and a
lowerer negative-shape suite — which catch accidental pipeline drift early.

## Why Nexus

Nexus is for language tools that want their entire frontend in Zig without
gluing together separate lexer and parser generators or shipping a parser
runtime.

You write two files:

- `{lang}.grammar` — tokens, lexer states, parser rules, precedence, actions
- `{lang}.zig` — only the language-specific helpers that don't fit declarative rules

Nexus emits one combined parser module. The grammar stays the source of
truth; the Zig side is an escape hatch, not the center of the design.

### What you get

- **Single generated Zig file** — vendor it, audit it, ship it
- **Combined lexer + LR parser** — one grammar drives both
- **LALR(1) default, SLR(1) via `--slr`** — ~3× faster generation when you need it, no measured runtime speed difference
- **Zero-copy 8-byte tokens** — no allocations during lexing
- **Declarative S-expression output** — write `(assign 1 3)` next to a grammar rule and that's the tree the parser emits. No visitor classes, no AST type file, no builder boilerplate. Uniform `Sexp` union with tag-based O(1) dispatch, ready for compiler passes
- **Small, readable codebase** — ~7,300 lines of Zig you can read end to end
- **Proven by self-hosting** — Nexus's own frontend is Nexus-generated

## Quick Start

```bash
zig build -Doptimize=ReleaseSafe             # build nexus (recommended)
./bin/nexus zag.grammar   src/parser.zig     # generate parser for Zag
./bin/nexus slash.grammar src/parser.zig     # generate parser for Slash
./bin/nexus mumps.grammar src/parser.zig     # generate parser for MUMPS
```

Each generated `parser.zig` contains the lexer, LR parse tables, `Tag` enum,
`Sexp` type, and reduction actions — ready to compile into your project.
The generated code imports the `@lang` module for keyword lookup, tag
definitions, and optional token rewriting.

## Validated Languages

| Language   | Grammar         | Lang Module | Rules | Conflicts |
|------------|-----------------|-------------|-------|-----------|
| Zag        | `zag.grammar`   | `zag.zig`   |    56 |        19 |
| Slash      | `slash.grammar` | `slash.zig` |    53 |        16 |
| em (MUMPS) | `mumps.grammar` | `mumps.zig` |   115 |        44 |

## Architecture

```
{lang}.grammar + {lang}.zig
         ↓
    nexus (src/nexus.zig)
         ↓
    parser.zig (generated lexer + LALR(1) parser)
```

Nexus reads the grammar, builds LALR(1) parse tables, and emits a single Zig
module containing a fast switch-based lexer, table-driven parser, `Tag` enum,
`Sexp` type, and all reduction actions. The generated parser imports the
`@lang` module for keyword lookup, tag definitions, and optional token
rewriting.

### Self-Hosting

Nexus eats its own dog food. The frontend parser it uses to read every
`.grammar` file — including `nexus.grammar` itself — is a Nexus-generated
LALR(1) parser. The pipeline is:

```
nexus.grammar → parser.zig (generated, checked in)
              → Sexp → GrammarLowerer → GrammarIR → ParserGenerator → parser.zig
```

The canonical S-expression schema the frontend emits is documented as a
block comment at the top of `nexus.grammar` and serves as the authoritative
contract with the strict `GrammarLowerer` in `src/nexus.zig`. Every lowering
entry point either receives exactly the documented shape or raises a hard
error pointing at the source line; there is no heuristic shape inference.

Three CI guards protect the pipeline:

- `test/golden/*.sexp` pins the canonical AST for every in-repo grammar
  (nexus, basic, features, zag, slash, mumps). A drift fails the golden.
- A bootstrap fixed-point test regenerates `src/parser.zig` from
  `nexus.grammar` on every run and diffs it against the checked-in file.
- A lowerer negative-shape suite (Zig `test "..."` blocks in
  `src/nexus.zig`) feeds hand-crafted malformed Sexps to
  `GrammarLowerer` and asserts each one is rejected with
  `error.ShapeError` — proving the "exact shape or hard error"
  contract directly, independent of what well-formed grammars happen to
  produce. These tests compile into a separate test binary via
  `zig build test-lowerer` and are absent from the shipped `./bin/nexus`.

### Repository Structure

```
src/
├── nexus.zig        # Generator engine
├── parser.zig       # Self-hosted frontend, generated from nexus.grammar
└── lang.zig         # Lang module for the frontend (Tag enum + lexer wrapper)
nexus.grammar        # Grammar DSL described in its own grammar format
build.zig            # Build configuration
test/
├── run              # Test runner (32 tests)
├── basic/           # Expression grammar
├── features/        # Feature-test grammar
├── mumps/           # MUMPS language grammar
├── zag/             # Zag language grammar
├── slash/           # Slash language grammar
├── golden/          # Byte-exact golden output files, including nexus.sexp
└── adverse/         # Error-case grammars
```

---

## Grammar File Format

A `.grammar` file has two sections: `@lexer` and `@parser`.

```
@lexer

state                          # state variables
    ...
after                          # post-token resets
    ...
tokens                         # token type declarations
    ...
<pattern> → <token>            # lexer rules
<pattern> @ <guard> → <token>, {action}

@parser

@lang = "name"                 # language module
@conflicts = N                 # expected SLR conflict count
@as ident = [keyword]           # context-sensitive keyword promotion

<rule> = <elements> → (action) # parser rules

@infix <base>                  # operator precedence table
    ...
```

All block declarations (`state`, `after`, `tokens`, `@infix`) use
indentation. No braces or brackets. The arrow separator accepts both
`→` (Unicode) and `->` (ASCII).

---

## Lexer Section

### State Variables

Track lexer mode and context across tokens. All variables are `i8`.

```
state
    beg   = 1       # at beginning of line
    paren = 0       # parenthesis depth
```

Inline form is also accepted:

```
state beg = 1
state paren = 0
```

### After (Post-Token Reset)

Default actions applied after every token, unless a rule overrides:

```
after
    beg = 0         # clear line-start flag after each token
```

### Token Types

Declare every token type the lexer can produce:

```
tokens
    ident           # identifiers
    integer         # whole numbers
    string_dq       # "double-quoted strings"
    plus            # +
    newline         # line terminator
    comment         # # to end of line
    eof             # end of input
    err             # lexer error
```

Generates a `TokenCat` enum in the output.

#### Token Classification Rule

Every terminal symbol in the grammar is classified as either **direct** or
**promoted**, which determines how the parser maps incoming tokens:

- **Direct tokens** get a `tokenToSymbol` entry — the parser maps the token
  category directly to a parser symbol. The lexer or rewriter emits these
  with their own `TokenCat` value.

- **Promoted tokens** go through the `@as` keyword promotion system — they
  arrive as `ident` and the parser promotes them based on text and state.

**The rule is simple: if you declare a token in the `tokens` block, the
parser will expect the lexer/rewriter to emit it directly. If you don't
declare it, the parser will expect it to arrive through `@as` promotion.**

This means:
- Rewriter-classified tokens (like `if_mod`, `then_sep`, `do_block`) must
  be declared in `tokens` even though they have no lexer regex rule.
- Keywords that exist only as grammar nonterminals (like `if`, `else`, `fn`
  in languages using `@as ident = [keyword]`) should NOT be in `tokens`.

If a terminal has no `tokens` declaration and no `@as` promotion path, it
will be unreachable and should be treated as a grammar error.

### Token Structure

The generated lexer produces 8-byte tokens:

```zig
pub const Token = struct {
    pos: u32,      // byte offset in source (max ~4 GiB)
    len: u16,      // token length (max 65535 bytes)
    cat: TokenCat, // token category (1 byte)
    pre: u8,       // preceding whitespace count (0-255)
};
```

Zero-copy: token text is retrieved by slicing into the original source.

### Lexer Rules

```
<pattern>                        → <token>
<pattern>                        → <token>, {action}
<pattern>  @ <guard>             → <token>, {action}
```

#### Patterns

Regex-like syntax for matching input:

| Syntax | Meaning |
|--------|---------|
| `'x'` | Literal character |
| `"xy"` | Literal string |
| `[abc]` | Character class |
| `[a-z]` | Character range |
| `[^x]` | Negated class |
| `.` | Any character (except newline) |
| `X*` | Zero or more |
| `X+` | One or more |
| `X?` | Optional |
| `(X)` | Grouping |

Examples:

```
'#' [^\n]*                                  → comment
'"' ([^"\\$\n] | '\\' . | '$')* '"'         → string_dq
"'" ([^'\n] | "''")* "'"                    → string_sq
[0-9]+                                      → integer
[a-zA-Z_][a-zA-Z0-9_]* '?'?                 → ident
"**"                                        → power
.                                           → err
```

#### Guards

Conditional rules based on state:

| Guard | Meaning |
|-------|---------|
| `@ beg` | When `beg` is non-zero |
| `@ !beg` | When `beg` is zero |
| `@ pre > 0` | When preceded by whitespace |
| `@ pat & dep > 0` | Multiple conditions (AND) |

`pre` is a pseudo-variable — the whitespace count computed at the start of
each `matchRules()` call. It can be read in guards but is not a state variable.

```
'!' @ pre > 0                               → exclaim_ws
'!' @ pre == 0                              → exclaim
'\n'                                        → newline, {beg = 1}
'(' @ pat                                   → lparen, {dep++}
```

#### Actions

| Action | Effect |
|--------|--------|
| `{var = val}` | Set variable to value |
| `{var++}` | Increment variable |
| `{var--}` | Decrement variable |
| `{var = counted('x')}` | Count occurrences of char `x` in consumed input |
| `skip` | Don't emit token (discard) |
| `simd_to 'x'` | SIMD-accelerated scan to character |

Examples:

```
'\n'                                        → newline, {beg = 1}
'('                                         → lparen, {paren++}
';' [^\n]*                                  → comment, simd_to '\n'
@ beg & pre > 0                             → indent, {pre = counted('.')}
```

### The `counted('x')` Action

Counts occurrences of a specific character in consumed input. Typically used
with empty-pattern guard rules to count structural markers like dots:

```
@ beg & pre > 0                             → indent, {pre = counted('.')}
```

The generated code scans forward, counting each `.` (skipping whitespace
between them), and stores the count in the token's `pre` field.

### Empty-Pattern Guard Rules

Rules with no pattern and only guards emit zero-width tokens based on state.
These run before character dispatch in the generated lexer:

```
@ beg & pre > 0                             → indent, {pre = counted('.')}
@ !beg & pre > 1                            → spaces, {pre = 0}
```

### The `@code` Directive (Lexer Section)

Import a function from the `@lang` module into the generated lexer:

```
@code = checkPatternMode
```

The generated lexer emits a wrapper that calls into the language module. This
handles complex, language-specific logic that doesn't fit declarative rules.

### Rewriter-Classified Tokens

The `@lang` module's `Lexer` wrapper (rewriter) can reclassify tokens based
on context that the grammar alone cannot see. This is a core technique for
resolving ambiguities without complicating the grammar.

The rewriter sits between the generated `BaseLexer` and the parser. It sees
every token and can change its category, fuse adjacent tokens, or inject
synthetic tokens based on spacing, surrounding tokens, or lookahead.

**Pattern**: when the same keyword or operator means different things in
different contexts, the rewriter classifies it into distinct token types.
The grammar sees different symbols and stays conflict-free.

Examples from Zag:

| Source token | Rewriter classifies as | When | Why grammar can't |
|-------------|----------------------|------|-------------------|
| `-` | `minus_prefix` | Tight (no space before) | Depends on spacing |
| `-` | `minus` (infix) | Spaced | Depends on spacing |
| `if` | `post_if` | After `return`/`break`/`continue` | Depends on preceding keyword |
| `if` | `ternary_if` | Mid-expression with `else` ahead | Depends on lookahead for `else` |
| `if` | `if` (prefix) | At statement start | Default |
| `\|` | `bar_capture` | In `\|name\|` capture context | Depends on surrounding tokens |
| `.{` | `dot_lbrace` | Dot immediately before `{` | Depends on adjacency |

This technique is not Zag-specific. Any `@lang` module can implement a
`Lexer` wrapper that reclassifies tokens for its language's needs. The
grammar engine generates a `BaseLexer`; the `@lang` module optionally wraps
it with context-sensitive logic.

**When to use this pattern**:

- Same operator means different things based on spacing (`-` prefix vs infix)
- Same keyword means different things based on context (`if` as prefix, guard, or ternary)
- Token meaning depends on lookahead the grammar can't express declaratively

---

## Parser Section

### Rule Syntax

```
rulename = element1 element2                → (action)
         | alternative                      → (action)
```

- **Lowercase** names = nonterminals (grammar rules)
- **UPPERCASE** names = terminals (lexer tokens)
- **`"literal"`** = match exact token value

### Start Symbols

Mark entry points with `!`:

```
program! = body                             → (module ...1)
expr!    = expr                             → 1
```

Each generates a `parseProgram()`, `parseExpr()`, etc. Multiple start symbols
allow parsing different contexts (full program, single expression, REPL).

### Aliases

```
name = IDENT
```

Zero-cost redirect — `name` is treated as `IDENT` everywhere.

### Lists

`L(X)` matches a comma-separated list (one or more):

```
params = L(field)                           → (...1)
args   = L(expr)                            → (...1)
```

| Syntax | Meaning |
|--------|---------|
| `L(X)` | Required comma-separated list, items required |
| `L(X?)` | Required comma-separated list, items can be empty (`a,,b`) |
| `L(X, sep)` | List with custom separator |

### Optional Groups

`[...]` marks optional groups that expand into 2^N alternatives at compile
time, keeping action positions stable:

```
ref = label [offset] [routine]              → (ref 1 2 3)

# Expands to:
ref = label offset routine                  → (ref 1 2 3)
ref = label offset                          → (ref 1 2)
ref = label routine                         → (ref 1 _ 2)
ref = label                                 → (ref 1)
```

### Quantifiers

| Syntax | Meaning |
|--------|---------|
| `X?` | Optional (zero or one) |
| `X*` | Zero or more |
| `X+` | One or more |

### Actions (S-Expression Output)

Actions specify what S-expression to emit. Numbers reference matched elements
by position (1-based):

```
assign = name "=" expr                      → (= 1 3)
         ↑    ↑   ↑
         1    2   3
```

| Syntax | Meaning |
|--------|---------|
| `N` | Element N by position |
| `...N` | Spread list elements into parent |
| `key:N` | Element N with schema key |
| `key:_` | Explicit nil with schema key |
| `_` | Nil (absent value) |
| `~N` | Unwrap symbol ID into `src.id` |
| `0` | Rule name as tag |
| `(tag ...)` | Nested S-expression |
| `→ N` | Pass through element N (no wrapping) |

Trailing nils are automatically stripped: `(ref 1 2 3)` with only element 1
present produces `(ref 1)`, not `(ref 1 nil nil)`.

### `!` — Skip Elements

On the left side, `!` parses an element but excludes it from position numbering:

```
block = !INDENT body !OUTDENT               → (block ...2)
```

### `~N` — Symbol Unwrap

Stores the resolved identity (enum value) of element N in `src.id`, enabling
O(1) integer-switch dispatch without string comparison:

```
binop = expr operator expr                  → (binop ~2 1 3)
```

### `<` — Tight Binding

Parser hint that forces reduce over shift on S/R conflicts. Makes a construct
atomic:

```
atom = "@" < atom                           → (@name 2)    # @X+1 parses as (@X)+1
atom = "(" expr ")" <                       → 2             # parens are atomic
```

### `X "c"` — Character Exclusion

Peek at the next raw character. If it matches, this alternative fails:

```
nameind = "@" atom X "@"                    → (@ name 2)   # not followed by @
subsind = "@" atom "@" subs                 → (@ subs 2 4) # followed by @
```

---

## Parser Directives

| Directive | Purpose |
|-----------|---------|
| `@lang = "name"` | Import language module (`name.zig`) |
| `@conflicts = N` | Declare expected conflict count |
| `@as ident = [keyword]` | Context-sensitive keyword promotion |
| `@op = [...]` | Operator literal-to-token mappings |
| `@infix base` | Auto-generate precedence chain |
| `@errors` | Human-readable rule names for diagnostics |
| `@code location { ... }` | Inject raw Zig at `imports`, `sexp`, `parser`, or `bottom` |

### `@infix` — Operator Precedence

Auto-generates a binary operator precedence chain:

```
@infix unary
    "|>"  left
    "||"  left
    "&&"  left
    "=="  none, "!=" none, "<" none, ">" none
    "+"   left, "-"  left
    "*"   left, "/"  left, "%"  left
    "**"  right
```

- First line names the base expression (`unary`)
- Each subsequent line is one precedence level (lowest first)
- Comma-separated operators share precedence
- Associativity: `left`, `right`, or `none`
- Generates a nonterminal called `infix`, referenced as `@infix`

### `@op` — Operator Mappings

Maps multi-character operator literals to lexer token types:

```
@op = [
  "'=" → "noteq",  "'<" → "notlt",   "'>" → "notgt",
  "**" → "starstar", "]]" → "sortsafter",
]
```

When the grammar uses `"'="` in a rule, the parser maps it to the lexer's
`.noteq` token. Combined with `~N`, this enables O(1) operator dispatch.

### `@as` — Context-Sensitive Keywords

```
@as ident = [keyword]
@as ident = [fn, isv, ssvn, self, cmd]
@as ident = [keyword!]
```

Defines ordered resolution for context-sensitive keyword promotion. When the
lexer produces `ident`, the parser tries each candidate in list order. Each
candidate calls the `@lang` module's lookup function (e.g., `keywordAs()`,
`cmdAs()`) and checks if the current parser state accepts that keyword.

`self` is a priority checkpoint: if plain `ident` is valid in the current
parser state, return it immediately without trying later candidates. This
controls disambiguation when both a keyword and an identifier are valid:

- Candidates **before** `self`: strict matching (`> 0`, shift actions only)
- Candidates **after** `self`: permissive matching (`!= 0`, any action)
- Implicit `ident` fallback at the end if nothing matches

#### Reduce-Aware Matching (`!` suffix)

Append `!` to any group name for reduce-aware matching:

```
@as ident = [keyword!]
```

By default, keyword promotion requires a **shift action** (`> 0`) in the
current parser state. This fails for reserved keywords that appear after
expressions, where the parser must reduce before the keyword becomes
shiftable (e.g., Ruby's `else`, `end`, `elsif`, `when`).

The `!` suffix enables **reduce-aware matching** (`!= 0`), which promotes
the keyword whenever the parser has any valid action for it — shift or
reduce. This eliminates the need for manual keyword force-classification
in the lang module.

Mode resolution per group:

| Syntax | Mode | Condition |
|--------|------|-----------|
| `group!` | permissive | explicit, always `!= 0` |
| `group` before `self` | strict | default, `> 0` (shift only) |
| `group` after `self` | permissive | positional, `!= 0` |
| `self!` | **rejected** | syntax error |

#### Examples

For single-keyword languages (e.g., Zag), `self` is not needed:

```
@as ident = [keyword]
```

For languages where commands overlap with variable names (e.g., MUMPS),
`self` ensures identifiers win over commands in expression contexts:

```
@as ident = [fn, isv, ssvn, self, cmd]
```

For languages with reserved keywords that appear in reduce states (e.g.,
Ruby), use `!` for reduce-aware matching:

```
@as ident = [keyword!]
```

### `@errors` — Human-Readable Rule Names

Provides readable names for diagnostics:

```
@errors
    expr = "expression"
    stmt = "statement"
```

### `@lang` — Language Module

```
@lang = "zag"
```

The generated `parser.zig` imports `zag.zig` and uses it for:

1. **`Tag` enum** — semantic node types for S-expression output
2. **`keyword_as()`** — maps identifier text to keyword IDs
3. **Lexer wrapper** — optional rewriter for indentation, token reclassification

---

## S-Expression Output

The grammar file is also the AST spec. An action like `(assign 1 3)` next to
a rule *is* the tree the parser emits — no visitor classes, no separate AST
type file, no builder boilerplate. You get a uniform `Sexp` algebra with
tag-based O(1) dispatch, stable positional access, and trivially composable
compiler passes.

### Sexp Variants

```zig
pub const Sexp = union(enum) {
    nil:  void,                                    // absent value
    tag:  Tag,                                     // semantic type (1 byte)
    src:  struct { pos: u32, len: u16, id: u16 },  // source ref + identity
    str:  []const u8,                              // embedded string
    list: []const Sexp,                            // compound: (tag child1 ...)
};
```

| Variant | Purpose |
|---------|---------|
| `.nil` | Absent/missing value (shown as `_` in text) |
| `.tag` | Node type tag (enum, O(1) dispatch) |
| `.src` | Source reference + resolved identity |
| `.str` | Embedded string |
| `.list` | Compound: `[.tag, child1, child2, ...]` |

### Access Pattern

```zig
switch (sexp) {
    .list => |items| {
        switch (items[0].tag) {
            .assign => {
                const target = items[1];
                const value = items[2];
            },
        }
    },
}
```

All access is positional. Positions never shift — absent optional elements
get `.nil`, they don't collapse the list.

---

## Generated Code

### Lexer Architecture

The generated lexer uses a three-tier dispatch strategy:

| Tier | Strategy | Driven By |
|------|----------|-----------|
| 1. Single-char switch | O(1) per character | Single-char literal patterns |
| 2. Multi-char prefix dispatch | Peek-ahead | Multi-char literal patterns |
| 3. Scanner functions | Inline loops | Complex patterns (ident, number, string) |

All behavior is derived from the grammar:

- **Character classification** (`char_flags[256]`) — derived from ident/number patterns
- **Operator switch arms** — generated from literal rules
- **Newline handling** — compiled from `\n`/`\r\n` rules with guards and actions
- **Comment scanning** — with optional SIMD acceleration via `simd_to`
- **String/number/ident scanners** — generated from pattern shapes

### Well-Known Token Names

The generator recognizes certain token names and provides optimized scanners:

| Token Name | What Happens |
|------------|-------------|
| `ident` | Generates `scanIdent()`, drives `@as` routing |
| `integer`, `real` | Generates `scanNumber()` with prefix detection |
| `string`, `string_*` | Generates inline string scanning per delimiter |
| `comment` | Generates comment scanning, skipped in operator switch |
| `skip` | Skipped in prefix scanner |
| `err`, `eof` | Hardcoded in fallback returns |

### Parser Architecture

The generated parser uses:

- **Sparse action/goto tables** — per-state `(symbol, action)` pairs
- **Action encoding**: `0` = error, `> 0` = shift to state N, `-1` = accept, `< -1` = reduce by rule `(-action - 2)`
- **Semantic actions** — tag-based dispatch builds Sexp from matched elements
- **Multiple start symbols** — each gets a unique accept rule and marker token

### Performance

| Technique | Benefit |
|-----------|---------|
| Comptime `char_flags[256]` | O(1) character classification |
| Switch dispatch | Branch-predictable token selection |
| Inline scanners | No function call overhead |
| SIMD comment scanning | 16 bytes at a time |
| Zero-copy tokens | No string allocations during lexing |
| 8-byte packed Token | Cache-friendly |
| Sparse parse tables | Compact, fast lookup |

---

## Language Module Contract

The `@lang` module (e.g., `zag.zig`) provides:

1. **`Tag` enum** — `pub const Tag = enum(u8) { module, fun, ... }` for S-expression node types
2. **`keyword_as(text, symbol) -> ?u16`** — maps identifier text to keyword token IDs when the parser state expects them
3. **Lexer wrapper** (optional) — `pub const Lexer = ...` that wraps `BaseLexer` for indentation tracking, token reclassification, or other rewriting

If the `@lang` module exports a `Lexer` type, the generated code uses it.
Otherwise it uses `BaseLexer` directly.

---

## Testing

```bash
./test/run              # run all tests (~1s)
./test/run --update     # regenerate golden files after intentional changes
```

### Test Layers

| Layer | Count | What it tests |
|-------|-------|---------------|
| **Golden files** | 5 | Full pipeline: grammar → parser.zig, byte-exact diff |
| **Compile checks** | 5 | `zig ast-check` on generated output |
| **Determinism** | 5 | Same input → identical output across runs |
| **Adverse tests** | 8 | Bad grammars produce errors, not silent failures |

### Golden Grammars

| Grammar | Purpose |
|---------|---------|
| `basic` | Expression grammar (precedence, associativity, multiple start symbols) |
| `features` | State vars, after, guards, actions, strings, comments, lists |
| `zag` | Real-world: 56 rules, 19 conflicts |
| `slash` | Real-world: 53 rules, 16 conflicts |
| `mumps` | Real-world: 115 rules, 44 conflicts, @code, counted, empty-pattern guards |

---

## Known Constraints

### String Escape Semantics

- Single-quote delimiters use `''` doubled-quote escaping
- Double-quote delimiters use `\` backslash escaping
- Both stop on newline (no multiline strings)

### Parser Algorithm: LALR(1) vs SLR(1)

Nexus defaults to **LALR(1)**, with SLR(1) available via `--slr`. Both
algorithms produce the *same parser states* and the *same runtime parse
speed* — they differ only in how lookahead sets are computed, which
affects generation time and (occasionally) conflict counts.

**Two things matter when choosing a mode:**

#### 1. Generation-time cost (LALR is ~3× slower)

Wall-clock time to generate a parser, averaged over 5 runs after 2
warmups (ReleaseSafe build, Apple Silicon):

| Grammar | Rules | States | LALR time | SLR time | LALR/SLR |
|---------|------:|-------:|----------:|---------:|---------:|
| basic    |  20  |   33  |   3.2 ms  |   2.4 ms |   1.32× |
| features |  26  |   42  |   2.2 ms  |   2.1 ms |   1.06× |
| nexus    |  97  |  149  |   2.2 ms  |   2.1 ms |   1.05× |
| slash    | 230  |  351  |   4.5 ms  |   2.8 ms |   1.59× |
| zag      | 251  |  478  |  14.9 ms  |   3.8 ms |   3.96× |
| mumps    | 529  |  832  |  28.0 ms  |   5.1 ms |   5.45× |
| **total**|      |       | **54.9 ms** | **18.3 ms** | **3.01×** |

The penalty scales with grammar complexity. Small grammars see ~5-10%
overhead; large grammars see 5×+ slowdowns. The root cause is LALR's
per-state per-item lookahead propagation, which grows super-linearly
with state count.

The *runtime* parser built from either mode runs at identical speed.
The output tables have the same shape; only the lookahead entries
used during conflict resolution at generation-time differ.

#### 2. Conflict count (LALR occasionally resolves more)

Conflict counts per grammar:

| Grammar | LALR conflicts | SLR conflicts | LALR wins? |
|---------|---------------:|--------------:|:---------- |
| basic    |  0  |  0  | — (both conflict-free) |
| features |  0  |  0  | — (both conflict-free) |
| nexus    | 16  | 16  | — (identical) |
| slash    | 16  | 16  | — (identical) |
| zag      | 19  | 19  | — (identical) |
| mumps    | **44**  | **46**  | **2 fewer** (the win) |

**On 5 of 6 grammars in this repo, LALR and SLR produce the same
number of conflicts.** LALR's extra precision only resolved 2 additional
conflicts in MUMPS.

#### Recommendation

- **Default `zig build test` iteration:** `--slr` is fine for fast
  feedback (3× faster generation, same runtime parsers, same conflict
  count on most grammars).
- **When LALR matters:** if your grammar reports conflicts that turn
  out to be spurious (resolvable by more precise lookahead), try LALR
  and see if the count drops. MUMPS is the repo's current example.
- **Absolute numbers are small.** Even MUMPS LALR (the slowest case)
  is ~28ms in ReleaseSafe. Pick the mode that gives you the cleanest
  grammar and don't over-optimize generation time.

---

### Token Limits

- Source: max ~4 GiB (`pos` is `u32`)
- Token length: max 65535 bytes (`len` is `u16`)
- Whitespace prefix: max 255 chars (`pre` is `u8`)
- Production RHS: max 32 symbols (`MAX_ARGS`)

### State Variables

All `i8`. Covers counters, booleans, and flags. Richer state (mode stacks,
delimiter stacks) requires `@lang` wrapper support.

---

## Building

```bash
zig build                              # Debug build (fast compile, slow runtime)
zig build -Doptimize=ReleaseSafe       # fast + safety-checked (recommended)
zig build -Doptimize=ReleaseFast       # fast, safety checks stripped
zig build test                         # run all 32 tests
zig build run -- <args>                # run with arguments
```

Requires Zig 0.16.0.

### Which optimize mode to use

Generation time varies **~8× between Debug and Release** modes. Totals
for generating all 6 in-repo parsers (LALR + SLR combined, 12 runs):

| Mode | Binary size | Total time | Speedup vs Debug |
|------|-----------:|-----------:|-----------------:|
| Debug        | 3.1 M | ~540 ms | 1.0× (baseline) |
| ReleaseSafe  | 795 K |  ~73 ms | **7.7× faster** |
| ReleaseFast  | 813 K |  ~72 ms | **7.7× faster** |

**ReleaseSafe and ReleaseFast are indistinguishable** (~2% apart, well
within noise). This workload is dominated by hashmap operations, string
allocation, and LR automaton construction — none of which are
bounds-check-heavy, so the checks ReleaseFast strips are already cheap.

**Recommendation:** use `ReleaseSafe` for any shipped binary. You get
the full ~8× speedup over Debug while keeping runtime safety. Use
`Debug` only when actively debugging nexus itself.

### Regenerating the Self-Hosted Frontend

When modifying `nexus.grammar`, regenerate the checked-in frontend parser
and commit both:

```bash
./bin/nexus nexus.grammar src/parser.zig
```

If the AST shape changes, also refresh the canonical S-expression golden:

```bash
./test/run --update
```

The bootstrap fixed-point test and the six canonical S-expression
snapshots all run on every `zig build test` — a broken invariant fails
the build with a pointer to what drifted.

For debugging the frontend, the binary can print its canonical
S-expression tree for any grammar:

```bash
./bin/nexus --dump-sexp <grammar>       # print the canonical Sexp tree
```

---

## License

MIT
