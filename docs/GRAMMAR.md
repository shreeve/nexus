# The grammar file

This is the complete reference for Nexus 1.0 grammar files. Every example
marked with a file name below is a whole grammar that `./test/run` generates,
compiles, and runs; each `input` is parsed and must print exactly the `tree`
shown after it. Fragments are checked to parse. Trees are printed by the
test driver: a leaf is its text in backquotes (with `\` and `` ` ``
escaped), followed by `#n` when its id is not 0; `_` is nil.

Contents: [Layout](#layout) · [The @lexer section](#the-lexer-section) ·
[The @parser section](#the-parser-section) · [Actions](#actions) ·
[Conflicts and hints](#conflicts-and-hints) · [Directives](#directives) ·
[Errors](#errors)

The semantic layer (`@schema`, roles, labels, coverage, spans, the generated
`ir` API) has its own document: [SEMANTICS.md](SEMANTICS.md).

## Layout

A grammar file has an `@lexer` section followed by an `@parser` section.
Directives (`@lang`, `@schema`, ...) may also come before `@lexer`, in a
preamble. Both sections are required; an empty `@parser` section generates
a lexer-only module.

```grammar words.grammar
# A comment runs from # to the end of the line.

@lexer

tokens
    word, number, eof, err

'\n'                        → skip, skip
[a-z]+                      → word
[0-9]+                      → number
.                           → err

@parser

list! = item+                          → (list ...1)

item  = WORD                           → (word 1)
      | NUMBER                         → (number 1)
```

```input
hello 42
world
```

```tree
(list (word `hello`) (number `42`) (word `world`))
```

Conventions used throughout:

- `→` and `->` are the same arrow (`=>` also works in the @lexer section).
- A line that starts in column 1 begins a new entry. An indented line
  continues the entry above it: the lines of a block (`tokens`, `@schema`,
  ...) or the rest of an alternative. A line starting with `|` is the next
  alternative of the rule above.
- In the @parser section, lowercase names are rules, capitalized names are
  tokens, and `"..."` is a literal. `name:` directly followed by an element
  is a [label](SEMANTICS.md#labels).

## The @lexer section

### Tokens

The `tokens` block names every token category, in lowercase, on indented
lines (commas optional). It must declare `eof` (returned at the end of
input) and `err` (returned for a byte no rule matches). The generated
`TokenCat` enum has these names in this order, plus a built-in `skip`.

```grammar fragment lexer
tokens
    ident, integer, string
    newline, comment
    eof, err
```

Tokens that no lexer rule produces are fine: a lang `Lexer` wrapper can
emit them (layout tokens such as `indent`, keywords it classifies).

### Rules

```text
pattern [@ guard & guard ...]  →  token [, action ...]
```

Each call of the lexer's `next()`:

1. skips spaces and tabs and records how many it skipped (saturating at 255)
   as the token's `pre`;
2. tries the [zero-width rules](#zero-width-rules), in order;
3. returns `eof` at the end of input;
4. runs the DFA: the longest match among the rules whose guards hold wins,
   and a tie goes to the rule written first. With no match, one byte
   becomes an `err` token;
5. runs the `after` block and the rule's actions.

Only spaces and tabs are implicit; a newline is an ordinary byte, so a
grammar that does not care about lines skips them with a rule
(`'\n' → skip, skip`). Every rule must be able to win: a rule that an
earlier rule shadows on every text it matches is an error that names the
winning rule and an example text.

A token is 8 bytes: `pos: u32`, `len: u16`, `cat: TokenCat`, `pre: u8`.
Its text is a slice of the source; the lexer never allocates.

### Patterns

A pattern is a regular expression over bytes:

| Pattern | Meaning |
|---|---|
| `'abc'` `"abc"` | literal bytes; escapes `\n \r \t \0 \\ \' \" \xHH` |
| `[a-z_]` `[^"\n]` | a byte class: ranges, negation, escapes, `\d \w \s` |
| `.` | any byte, including newline |
| `\n` `\d` ... | a bare escape is a one-byte atom (or class) |
| `( r )` | grouping; `( )` is the empty string |
| `r1 r2` | concatenation (atoms may be juxtaposed or spaced) |
| `r1 \| r2` | alternation |
| `r*` `r+` `r?` | repetition |
| `r{n}` `r{n,}` `r{n,m}` | bounded repetition (bounds up to 255) |
| `r1 / r2` | trailing context: match `r1` only when `r2` follows; `r2` is not part of the token |

Bare words are errors (`quote literal text as 'x' or "x"`), and so is
anything else outside this language: a pattern is never silently
simplified. A pattern may not match the empty string, nor start only with a
space or tab (the lexer has already consumed those as `pre`; use a
zero-width rule guarded by `pre`).

Trailing context needs a fixed-length token (`r1`) or a fixed-length context
(`r2`). Longest match counts the context: below, `f(` makes `f` a `call`,
while `g (` (with a space) leaves `g` an `ident`.

```grammar lexing.grammar
@lexer

tokens
    ident, call, number, string, arrow, kw_if
    minus, gt, lparen, rparen, eof, err

'#' [^\n]*                     → skip, skip        # comments
'\n'                           → skip, skip
'"' ([^"\\\n] | '\\' .)* '"'   → string
[0-9]+ ('.' [0-9]+)?           → number
"->" [a-z]                     → arrow, rewind(2)  # `->` only before a name
'-'                            → minus
'>'                            → gt
'('                            → lparen
')'                            → rparen
"if"                           → kw_if             # before ident: wins the tie
[a-z]+ / '('                   → call              # a name touching `(`
[a-z]+                         → ident
.                              → err

@parser

tokens! = token*                       → (tokens ...1)

token   = IDENT                        → (ident 1)
        | CALL                         → (call 1)
        | NUMBER                       → (number 1)
        | STRING                       → (string 1)
        | ARROW                        → (arrow 1)
        | KW_IF                        → (if 1)
        | "-"                          → (minus 1)
        | ">"                          → (gt 1)
        | "("                          → (lparen 1)
        | ")"                          → (rparen 1)
```

```input
if f(x) g (3.5) iffy # a comment
"say \"hi\"" ->y ->
```

```tree
(tokens
  (if `if`)
  (call `f`)
  (lparen `(`)
  (ident `x`)
  (rparen `)`)
  (ident `g`)
  (lparen `(`)
  (number `3.5`)
  (rparen `)`)
  (ident `iffy`)
  (string `"say \\"hi\\""`)
  (arrow `->`)
  (ident `y`)
  (minus `-`)
  (gt `>`))
```

### Literals and token names in rules

A rule of the @parser section refers to a token by its name in capitals
(`IDENT` is the token `ident`) or by a literal (`"("`, `"if"`, `"->"`). A
literal stands for the token of the lexer rule whose pattern is exactly
that text (above, `"-"` is `minus`); `@op` maps a literal to a token
explicitly. A literal that no lexer rule produces is an error, and so is
naming one token both ways (`"-"` in one rule, `MINUS` in another): write
each token one way.

### State variables and guards

`state` declares small integer variables (`i8`; `true` is 1, `false` 0)
with their initial values. A guard after `@` makes a rule apply only when
it holds; `&` joins guards:

| Guard | Holds when |
|---|---|
| `v` / `!v` | `v` is non-zero / zero |
| `v == n`, `!=`, `<`, `<=`, `>`, `>=` | the comparison holds (`n` may be negative) |
| `pre > 0` ... | `pre`, the whitespace count, compared like a variable |

The generator compiles one DFA with a start state per combination of guard
values, so guards cost nothing at run time beyond selecting the start state.

`after` lists assignments that run after every token that consumes input,
unless the rule's own action sets the same variable.

### Actions

| Action | Effect |
|---|---|
| `{v = n}` | set a state variable (`n`, `true`, `false`) |
| `{v++}` `{v--}` | step a state variable (saturating) |
| `{pre = n}` | set the token's `pre` |
| `{v = counted('c')}` | on a zero-width rule: count the `c` bytes that follow (spaces and tabs between them allowed), consume them, and store the count in `v` (or `pre`) |
| `skip` | discard the token and scan on; its bytes count toward the next token's `pre` |
| `hold` | emit the token with zero width at the match start; nothing is consumed |
| `rewind(n)` | end the token after its first `n` bytes; the rest is scanned again |
| `simd_to 'c'` | accepted and checked: the pattern must contain a `[^c]*` run. The generator scans such runs with SIMD on its own, so this changes nothing |

`→ skip, skip` and `→ comment, skip` both discard what they match. A rule
whose token is `skip` without the `skip` action returns a token of the
built-in category `skip`, which a lang `Lexer` wrapper may act on (the
parser treats it as an error).

A rule that holds or rewinds to zero width consumes nothing, so it must
change a variable its guards test; otherwise it would match forever, which
is an error. `hold` with `rewind`, `hold` with `skip`, and `counted()` on a
consuming rule are errors. `counting()`/`matching()` (balanced nesting) are
rejected: no finite automaton recognizes them.

### Zero-width rules

A rule with guards and no pattern is tried before the DFA:

```text
@ guard & guard ...  →  token [, action ...]
```

Its token covers the leading whitespace just skipped (and whatever
`counted()` consumes); with `hold` it is empty and the whitespace is
scanned again. It must require whitespace (a guard false at
`pre = 0`) or change a variable its guards test.

Below, a line that starts with blanks gets an `indent` token whose `pre` is
the number of dots after the blanks (MUMPS block structure), a `?` starts a
pattern mode in which capitals are pattern codes, and a comma in pattern
mode ends it with a zero-width `patend` (`hold`) before being lexed again
as a comma. The lang `Lexer` wrapper passes the dot count to the parser
through the lexer's `aux` field, which the parser stores as the leaf's id
(printed `#n`).

```grammar lines.grammar
@lexer

state
    beg = 1         # at the start of a line
    pat = 0         # in a pattern

after
    beg = 0

tokens
    indent, word, quest, code, patend, comma, newline, eof, err

'\n'                    → newline, {beg = 1}
@ beg & pre > 0         → indent, {pre = counted('.')}
'?'                     → quest, {pat = 1}
[A-Z]      @ pat        → code
','        @ pat        → patend, hold, {pat = 0}
','                     → comma
[a-z]+                  → word
.                       → err

@parser

@lang = "lines"

lines! = body                          → (lines ...1)

body   = line                          → (1)
       | body NEWLINE line             → (...1 3)
       | body NEWLINE                  → 1

line   = INDENT L(item)                → (line 1 ...2)
       | L(item)                       → (line _ ...1)

item   = WORD
       | WORD QUEST CODE+ PATEND       → (match 1 ...3)
```

```zig lines.zig
const parser = @import("parser.zig");

pub const Tag = enum(u8) { lines, line, match };

/// Passes the dot count of an indent token to the parser as its id.
pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        const tok = self.base.next();
        if (tok.cat == .indent) self.base.aux = tok.pre;
        return tok;
    }
    pub fn text(self: *const Lexer, tok: parser.Token) []const u8 {
        return self.base.text(tok);
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};
```

```input
a, b
  . . c?AN, d
 e
```

```tree
(lines (line _ `a` `b`) (line `  . . `#2 (match `c` `A` `N`) `d`) (line ` ` `e`))
```

### @code

`@code = name` (in the @lexer section) adds a method
`pub fn name(self) bool` to the lexer that calls `lang.name(source, pos)`,
for a lang `Lexer` wrapper that needs a hand-written lookahead. It requires
`@lang`.

```grammar fragment lexer
@code = checkPatternMode
```

### The generated lexer

The module exports `TokenCat`, `Token`, and `BaseLexer` (`init`, `next`,
`text`, `reset`, `matchRules`, the state variables as fields, and
`aux: u16`). With `@lang`, `Lexer` is the lang module's `Lexer` when it
declares one (a wrapper that owns a `BaseLexer` and rewrites its token
stream: indentation, keyword classification, synthetic tokens), else
`BaseLexer`. Without `@lang` the lexer struct is `Lexer` itself.

## The @parser section

### Rules

```text
name = element element ...  [< | >]  [→ action]  [~ "reason"]
     | ...
```

A rule has one or more alternatives. A rule name may repeat: later blocks
add alternatives. An alternative may be empty (it matches nothing).

A rule of one alternative that is a single token or rule name, with no
action, is an **alias**: `name = IDENT` makes `name` another spelling of
`IDENT`, with no rule and no reduction of its own.

### Start symbols

`name! = ...` marks a start symbol. Each start symbol `x` gets a method
`parseX()` on the parser, a `Start` enum value for `parse(.x)`, and a
top-level `parseX(allocator, source)`. A grammar may have several; each
parses the whole input as that symbol, and its alternatives are ordinary
alternatives usable anywhere. `x! = x` only declares `x` a start symbol.
A grammar without any `name!` rule starts at its first rule.

```grammar starts.grammar
@lexer

tokens
    ident, eq, semi, eof, err

'\n'                        → skip, skip
'='                         → eq
';'                         → semi
[a-z]+                      → ident
.                           → err

@parser

program! = stmt+                       → (program ...1)
expr!    = expr

stmt     = IDENT "=" expr ";"          → (set 1 3)
expr     = name
         | name name                   → (apply 1 2)
name     = IDENT
```

```input
x = f y;
z = w;
```

```tree
(program (set `x` (apply `f` `y`)) (set `z` `w`))
```

```input start=expr
g h
```

```tree
(apply `g` `h`)
```

### Elements

| Element | Matches | Value |
|---|---|---|
| `name` | the rule | its value |
| `NAME` | the token | a leaf (`.src`: position, length, id) |
| `"lit"` | the literal's token | a leaf |
| `X?` | `X` or nothing | `X`'s value, or nil |
| `X*` `X+` | zero or more / one or more `X` | a list of the values |
| `[X]` | `X` or nothing | `X`'s value, or nil |
| `[A B C]` | all of them or nothing | one position per element; nil each when absent |
| `(A \| B)` | exactly one alternative | the chosen alternative's value |
| `(A \| B)?` `[A \| B]` | at most one | the value, or nil |
| `(A B)` | the sequence | a list of its values, `!` elements left out (one left: that value) |
| `(A \| B)*` `(A B)+` | repetitions of a group or choice | a list |
| `L(X)` | `X ("," X)*` | a list of the `X` values (separators dropped) |
| `L(X, sep)` | `X (sep X)*`, `sep` a literal or token | a list |
| `L(X?)` `L(X?, sep)` | items may be empty | a list, nil for empty items |
| `[L(X)]` `[X ...]` `[X, ...]` | an optional list | a list, or nil when absent |
| `!X` `!X?` ... | `X`, marked as carrying no value | still a position |
| `X "c"` | nothing: a [hint](#conflicts-and-hints) | none |
| `@infix` | the [operator chain](#infix) | its value |

`[...]` and choices are expanded into alternatives (one per combination), so
an action's positions stay the same whichever combination matched. A
choice inside a `[...]` group or another choice is not supported (use a
helper rule).

`X?` and `[X]` are the same. On a rule name the alternative is expanded
(one variant with the rule, one without); on a token a rule `TOKEN?` is
introduced. Generated rules are named in
source syntax (`L(expr)`, `L(expr).tail`, `IDENT*`, `(A | B)`), which is
how conflict reports and `@conflicts` entries name them.

A list rule is greedy: `L(expr) "," tail` can never reach its `tail`,
because every comma continues the list. Write such lists out as rules.

## Actions

The action after the arrow says what an alternative's match turns into. The
tree is made of `Sexp` values: nil (`_`), a tag, a leaf (a token), and
lists. Positions count the pattern's elements from 1; a multi-element
`[A B]` group counts one position per element, and everything else
(including a choice) counts one.

| Action | Value |
|---|---|
| none | nothing: nil; one element: that element; several: a list of all (nil for an absent optional element) |
| `N` | element N |
| `_` (or `nil`) | nil |
| `(tag a b ...)` | a list headed by the tag `tag` |
| `(a b ...)` | an untagged list |
| `...N` | the items of element N (a list), spliced in; a token is never a list, so `...N` of one is an error |
| `~N` | element N if it is a leaf (keeping its id), else an empty leaf |
| `(!N ...)` | a list headed by element N |
| `(tag ... (kind ...) ...)` | nested lists, as deep as needed |
| `role:v` | an item for a schema role (see [SEMANTICS.md](SEMANTICS.md#role-named-actions)) |

A tag is any word (`set`, `+=`, `@name`); in the tree it is a `Tag`
enum value. Without `@schema`, the `Tag` enum is the lang module's `Tag`
(with `@lang`) or is collected from the actions (without it), and a
`role:v` item is just `v` (except that a leading `role:v` in an untagged
list names its tag: `(ref:1 2)` is `(ref 1 2)`).

Without `@schema`, the lists an action writes drop trailing nils, so
optional elements at the end leave no trace; with `@schema`, every node
keeps all its slots.

```grammar shapes.grammar
@lexer

tokens
    kw_a, kw_b, kw_c, kw_d, kw_e, kw_f
    ident, num, comma, colon, eq, plus, eof, err

'\n'                        → skip, skip
','                         → comma
':'                         → colon
'='                         → eq
'+'                         → plus
"a"                         → kw_a
"b"                         → kw_b
"c"                         → kw_c
"d"                         → kw_d
"e"                         → kw_e
"f"                         → kw_f
[0-9]+                      → num
[a-z]+                      → ident
.                           → err

@parser

shapes! = shape+                                → (shapes ...1)

shape   = "a" IDENT ["=" NUM] [":" IDENT]       → (a 2 4 6)
        | "b" [IDENT ...]                       → (b ...2)
        | "c" (IDENT | NUM) L(IDENT?, "+")      → (c 2 ...3)
        | "d" (IDENT !":" NUM)+                 → (d ...2)
        | "e" IDENT NUM                         → (!2 3 (pair 3 2))
        | "f" IDENT? NUM*                       → (f ~2 3)
```

```input
a x = 1 : y
a x : y
a x
b
b x, y
c 5 u++v
d p:1 q:2
e k 7
f 1 2
```

```tree
(shapes
  (a `x` `1` `y`)
  (a `x` _ `y`)
  (a `x`)
  (b)
  (b `x` `y`)
  (c `5` `u` _ `v`)
  (d (`p` `1`) (`q` `2`))
  (`k` `7` (pair `7` `k`))
  (f `` (`1` `2`)))
```

### Infix

`@infix base` followed by one indented line per precedence level, loosest
first, generates an operator-precedence chain over `base`. Operators on
one line share a level; each is `left`, `right` or `none` (non-associative).
The element `@infix` in a rule refers to the whole chain. Each operator
builds `(op left right)` with the operator literal as the tag.

```grammar calc.grammar
@lexer

tokens
    number, plus, minus, star, slash, caret, lparen, rparen, eof, err

'\n'                        → skip, skip
'+'                         → plus
'-'                         → minus
'*'                         → star
'/'                         → slash
'^'                         → caret
'('                         → lparen
')'                         → rparen
[0-9]+                      → number
.                           → err

@parser

calc! = expr

expr  = @infix

atom  = NUMBER
      | "-" atom                       → (neg 2)
      | "(" expr ")"                   → 2

@infix atom
    "+" left, "-" left
    "*" left, "/" left
    "^" right
```

```input
1 - 2 - 3 * -4 ^ 5 ^ 6
```

```tree
(- (- `1` `2`) (* `3` (^ (neg `4`) (^ `5` `6`))))
```

The levels are rules named by their operators (`infix("+" "-")`), and
operator conflicts are resolved by construction, so they never appear in
`@conflicts`.

### @op

`@op` maps literals to tokens when no lexer rule's pattern is exactly the
literal (for example a token a lang wrapper produces):

```grammar fragment
@op = [ "'=" → "noteq", "'<" → "notlt" ]
```

### @as: keywords that are also names

`@as TOKEN = [group, ...]` lets identifiers become keywords only where the
parser can use them. For each `TOKEN` (the promotable token, e.g. `IDENT`)
the parser tries the groups in order and turns it into the first keyword
terminal the current state accepts; otherwise it stays `TOKEN`.

- With `@lang`, group `g` is looked up with `lang.gAs(text) ?lang.GId`
  (or `@as TOKEN via fn = [g]` / `[g via fn]`: `lang.fn(text)`), where `GId`
  is an enum whose field names are the grammar's keyword terminals
  (`IF`, `THEN`, ...). The enum value becomes the leaf's id (`src.id`),
  so give keywords values from 1 up to 511 (0 means "no id"). A terminal
  named like the group in capitals (`G`) receives every value that has no
  terminal of its own.
- Without `@lang`, group `g` is the single word `g`, promoted to `G`.
- Matching is strict (the state must shift the keyword) for groups before
  `self`, and permissive (any action, including a reduction first) for
  groups after `self` or written `g!`. `self` keeps `TOKEN` itself when the
  state accepts it.

A capitalized terminal the `tokens` block declares (or a lexer rule
produces) reaches the parser as its own token; any other capitalized
terminal is a keyword that reaches it only through `@as`. One grammar
promotes one token.

```grammar kw.grammar
@lexer

tokens
    ident, number, eq, eof, err

'\n'                        → skip, skip
'='                         → eq
[0-9]+                      → number
[a-z]+                      → ident
.                           → err

@parser

@lang = "kw"
@as IDENT = [kw]

prog! = stmt+                          → (prog ...1)

stmt  = PRINT expr                     → (print 2)
      | GOTO NUMBER                    → (goto 1 2)
      | IDENT "=" expr                 → (set 1 3)

expr  = IDENT
      | NUMBER
```

```zig kw.zig
const std = @import("std");

pub const Tag = enum(u8) { prog, print, goto, set };

/// The keywords, by grammar terminal name; the value becomes `src.id`.
pub const KwId = enum(u16) { PRINT = 1, GOTO = 2 };

pub fn kwAs(text: []const u8) ?KwId {
    if (std.mem.eql(u8, text, "print")) return .PRINT;
    if (std.mem.eql(u8, text, "goto")) return .GOTO;
    return null;
}
```

```input
print goto
goto 10
```

```tree
(prog (print `goto`) (goto `goto`#2 `10`))
```

`print goto` prints the variable `goto`: after `print` the state expects an
expression, so `goto` stays an identifier.

## Conflicts and hints

Nexus builds LALR(1) tables (`--slr` for SLR(1)). A shift/reduce conflict
resolves to the shift, a reduce/reduce conflict to the rule written first,
and every conflict a grammar leaves must be declared in `@conflicts`,
with a reason. Generation fails on any difference and prints each
undeclared conflict with its state, items, and an example input, then the
whole manifest ready to paste:

```grammar dangling.grammar rejects
@lexer

tokens
    ident, kw_if, kw_then, kw_else, eof, err

'\n'                        → skip, skip
"if"                        → kw_if
"then"                      → kw_then
"else"                      → kw_else
[a-z]+                      → ident
.                           → err

@parser

stmt! = KW_IF IDENT KW_THEN stmt                  → (if 2 4)
      | KW_IF IDENT KW_THEN stmt KW_ELSE stmt     → (if 2 4 6)
      | IDENT
```

```error
dangling.grammar:15:1: error: undeclared conflict: shift  stmt → KW_IF IDENT KW_THEN stmt  (1)
    state 8, on KW_ELSE
      stmt → KW_IF IDENT KW_THEN stmt •   (reduce)
      stmt → KW_IF IDENT KW_THEN stmt • KW_ELSE stmt   (shift)
      example: KW_IF IDENT KW_THEN stmt • KW_ELSE
@conflicts
    shift  stmt → KW_IF IDENT KW_THEN stmt  1  # <reason>
```

Declaring it (with a real reason) accepts the grammar:

```grammar dangling_declared.grammar
@lexer

tokens
    ident, kw_if, kw_then, kw_else, eof, err

'\n'                        → skip, skip
"if"                        → kw_if
"then"                      → kw_then
"else"                      → kw_else
[a-z]+                      → ident
.                           → err

@parser

@conflicts
    shift  stmt → KW_IF IDENT KW_THEN stmt  1  # else binds to the nearest if

stmt! = KW_IF IDENT KW_THEN stmt                  → (if 2 4)
      | KW_IF IDENT KW_THEN stmt KW_ELSE stmt     → (if 2 4 6)
      | IDENT
```

```input
if a then if b then x else y
```

```tree
(if `a` (if `b` `x` `y`))
```

A manifest entry is `shift <rule> N # reason` (a reduction that lost to the
default shift) or `reduce <winner> over <loser> N # reason` (a reduction
dropped for the rule written first), where `N` counts the table cells
(state, lookahead) the entry covers. Rules are written `lhs → rhs` over the
generated grammar. No `@conflicts` block, or an empty one, means the grammar
must be conflict-free.

Hints resolve a conflict on purpose; a hinted conflict is not a conflict:

| Hint | Where | Effect |
|---|---|---|
| `>` | after an alternative's elements | its reductions lose to shifts, silently |
| `<` | after an alternative's elements | its reductions win over shifts |
| `X "c"` | among an alternative's elements | its reduction wins over shifting the one-character literal `"c"`, except when `c` directly follows the previous token (no whitespace): then the parser shifts |

`<` makes a reduction win. Below, statements follow each other with no
separator, and `!` is both a postfix operator (factorial) and a prefix
(not). After an expression at statement level, `!` could continue it or
start the next statement; `<` on the `stmt` alternatives ends the
statement, so `a ! b` is two statements. Inside parentheses there is no such choice and
`!` is the postfix operator:

```grammar bang.grammar
@lexer

tokens
    ident, bang, lparen, rparen, eof, err

'\n'                        → skip, skip
'!'                         → bang
'('                         → lparen
')'                         → rparen
[a-z]+                      → ident
.                           → err

@parser

stmts! = stmt+                         → (stmts ...1)

stmt   = expr  <
       | "!" expr  <                   → (not 2)

expr   = expr "!"                      → (fact 1)
       | IDENT
       | "(" expr ")"                  → 2
```

```input
a ! b (c !)
```

```tree
(stmts `a` (not `b`) (fact `c`))
```

`X "c"` decides by spacing. Here `f(x)` is a call and `g (y)` a name
followed by a parenthesized expression:

```grammar adjacent.grammar
@lexer

tokens
    ident, lparen, rparen, eof, err

'\n'                        → skip, skip
'('                         → lparen
')'                         → rparen
[a-z]+                      → ident
.                           → err

@parser

exprs! = expr+                         → (exprs ...1)

expr   = IDENT X "("                   → (var 1)
       | IDENT "(" expr ")"            → (call 1 3)
       | "(" expr ")"                  → 2
```

```input
f(x) g (y)
```

```tree
(exprs (call `f` (var `x`)) (var `g`) (var `y`))
```

An `X "c"` hint that decides nothing is an error.

## Directives

| Directive | Section | Purpose |
|---|---|---|
| `@lang = "name"` | any | the lang module (`name.zig`, imported by the parser) |
| `@code = fn` | @lexer | a lexer method calling `lang.fn(source, pos)` |
| `@schema` | any | node kinds and their roles ([SEMANTICS.md](SEMANTICS.md)) |
| `@tags a b ...` | any | extra `Tag` values for a lang wrapper (needs `@schema`) |
| `@conflicts` | any | the declared conflicts |
| `@infix base` | any | an operator-precedence chain |
| `@op = [ "lit" → "token", ... ]` | any | literal-to-token mappings |
| `@as TOKEN [via fn] = [g, ...]` | any | contextual keywords |
| `@display` | any | reader names of tokens for syntax errors |
| `@errors` | any | reader names of rules for syntax errors |
| `@trivia T ...` | any | tokens kept on a side channel, never parsed |
| `@repair` | any | the tokens tolerant parsing may insert |

"Any" means the preamble or the @parser section.

```grammar fragment
@display
    IDENT: "a name", NEWLINE: "end of line"
    "=": "'='"

@errors
    expr: "an expression", stmt: "a statement"

@trivia COMMENT

@repair
    holes       IDENT
    structure   INDENT OUTDENT
    terminator  NEWLINE

@tags  flag  marker
```

- `@display` names tokens (`TOKEN: "name"` or `"lit": "name"`); `@errors`
  names rules. A syntax error then reads `expected an expression or ")",
  got end of line`: the named rules the state is waiting for, then the
  tokens none of them can begin with. Unnamed tokens print as their
  literal or their name in lower case.
- `@trivia` tokens are removed from the parse and kept, with positions, in
  `parser.trivia()`. A rule may not use a trivia token.
- `@repair` classes: `holes` (value tokens that may be inserted with empty
  text), `structure` (layout tokens), `terminator` (structure that ends a
  statement). See [tolerant parsing](SEMANTICS.md#tolerant-parsing).

## Errors

Every generation error is `file:line:col: error: message`, generation stops
with exit status 1, and no output file is written. A few that grammars meet
early:

| Message (abridged) | Cause |
|---|---|
| `the tokens block must declare 'eof'` | the `tokens` block lacks `eof` or `err` |
| `token 'x' is not declared in the tokens block` | a lexer rule names an undeclared token |
| `this rule can never match: ... goes to the rule on line N` | an earlier rule shadows it |
| `this pattern matches the empty string` | use `+` rather than `*`, or a zero-width rule |
| `undefined rule 'x'` / `undefined token 'X'` | a name nothing defines |
| `the literal "x" is no token` | no lexer rule's pattern is exactly `x` (and no `@op` maps it) |
| `"+" and PLUS are the same token` | one token written both ways |
| `` `...2` spreads a list, but element 2 (IDENT) is a token `` | write `2` |
| `rule x derives no finite input` | every alternative needs a rule that never completes |
| `undeclared conflict: ...` / `conflict count changed` | see [Conflicts](#conflicts-and-hints) |
| `position 5 is past the end of the pattern (2 elements)` | an action refers to a missing element |
| `X ":" on name ... has no effect` | a hint that decides nothing |
| `` `@conflicts = N` is not supported `` | the 0.10 count form; declare each conflict |

`nexus check grammar` runs all of them without writing anything.

