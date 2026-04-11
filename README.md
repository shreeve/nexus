# Nexus

A universal, language-agnostic parser generator. One tool reads any `.grammar`
file and produces a combined lexer + SLR(1) parser module in Zig.

One tool. Any language. Install once, generate parsers for everything.

## Why Nexus

Most parser generators are tightly coupled to a single language or ecosystem.
Nexus takes a different approach: the **engine** is universal and the
**language** lives entirely in two files that you write:

- `{lang}.grammar` — declares tokens, patterns, guards, parser rules, actions
- `{lang}.zig` — provides language-specific helpers (keywords, tags, rewriter)

The grammar file is the single source of truth. The language module handles
anything too complex for declarative rules. Nexus itself contains zero
language-specific code.

## Quick Start

```bash
zig build                                    # build nexus
./bin/nexus zag.grammar   src/parser.zig     # generate parser for Zag
./bin/nexus slash.grammar src/parser.zig     # generate parser for Slash
./bin/nexus mumps.grammar src/parser.zig     # generate parser for MUMPS
```

Each generated `parser.zig` contains both the lexer and SLR(1) parser, ready
to compile into your project. The generated code imports the `@lang` module
for language-specific behavior.

## Validated Languages

| Language   | Grammar         | Lang Module | Rules | SLR Conflicts |
|------------|-----------------|-------------|-------|---------------|
| Zag        | `zag.grammar`   | `zag.zig`   |    56 |            18 |
| Slash      | `slash.grammar` | `slash.zig` |    53 |            16 |
| em (MUMPS) | `mumps.grammar` | `mumps.zig` |   115 |            44 |

## Architecture

```
{lang}.grammar + {lang}.zig
         ↓
    nexus (src/nexus.zig)
         ↓
    parser.zig (generated lexer + SLR(1) parser)
```

Nexus reads the grammar, builds SLR(1) parse tables, and emits a single Zig
module containing a fast switch-based lexer, table-driven parser, `Tag` enum,
`Sexp` type, and all reduction actions. The generated parser imports the
`@lang` module for keyword lookup, tag definitions, and optional token
rewriting.

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
@as = [ident, keyword]         # context-sensitive keyword promotion

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

Track lexer mode and context across tokens. All variables are `i32`.

```
state
    beg   = 1       # at beginning of line
    paren = 0       # parenthesis depth
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
| `@conflicts = N` | Declare expected SLR conflict count |
| `@as = [ident, keyword]` | Context-sensitive keyword promotion |
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
@as = [ident, keyword]
```

Enables the `@lang` module's `keyword_as()` function. Identifiers like `fun`,
`if`, `return` are promoted to keyword terminals **only when the current parser
state has a valid action for that keyword**. The same word can be a keyword in
one context and an identifier in another.

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

The parser produces S-expressions (Sexp) — a uniform, inspectable representation.

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
| **Error tests** | 8 | Bad grammars produce errors, not silent failures |

### Golden Grammars

| Grammar | Purpose |
|---------|---------|
| `basic` | Expression grammar (precedence, associativity, multiple start symbols) |
| `features` | State vars, after, guards, actions, strings, comments, lists |
| `zag` | Real-world: 56 rules, 18 conflicts |
| `slash` | Real-world: 53 rules, 16 conflicts |
| `mumps` | Real-world: 115 rules, 44 conflicts, @code, counted, empty-pattern guards |

---

## Known Constraints

### String Escape Semantics

- Single-quote delimiters use `''` doubled-quote escaping
- Double-quote delimiters use `\` backslash escaping
- Both stop on newline (no multiline strings)

### Parser Algorithm

SLR(1). Weaker than LALR(1) or LR(1) but sufficient for practical grammars.
Languages with significant context-sensitivity use `@lang` wrapper support.

### Token Limits

- Source: max ~4 GiB (`pos` is `u32`)
- Token length: max 65535 bytes (`len` is `u16`)
- Whitespace prefix: max 255 chars (`pre` is `u8`)
- Production RHS: max 32 symbols (`MAX_ARGS`)

### State Variables

All `i32`. Covers counters, booleans, and flags. Richer state (mode stacks,
delimiter stacks) requires `@lang` wrapper support.

---

## Building

```bash
zig build                    # build nexus to bin/nexus
zig build run -- <args>      # run with arguments
```

Requires Zig 0.15.x.

---

## License

MIT
