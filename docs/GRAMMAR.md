# The grammar file

This is the complete reference for the grammar file. Every example
marked with a file name below is a whole grammar that `./test/run` generates,
compiles, and runs; each `input` is parsed and must print exactly the `tree`
shown after it. Fragments are checked to parse. Trees are printed by the
test driver: a leaf is its text in backquotes (with `\` and `` ` ``
escaped), followed by `#n` when its id is not 0; `_` is nil.

Contents: [Layout](#layout) · [The @lexer section](#the-lexer-section) ·
[The @parser section](#the-parser-section) · [Actions](#actions) ·
[Operators and keywords](#operators-and-keywords) ·
[Conflicts and hints](#conflicts-and-hints) · [Directives](#directives) ·
[Messages](#messages) · [Editor support](#editor-support) ·
[Names and scopes](#names-and-scopes) ·
[Describing a grammar](#describing-a-grammar) · [Limits](#limits) ·
[Errors](#errors)

The semantic layer (`@schema`, roles, labels, coverage, spans, the generated
`ir` API) has its own document: [SEMANTICS.md](SEMANTICS.md).

## Layout

A grammar file has an `@lexer` section followed by an `@parser` section.
Directives (`@lang`, `@schema`, ...) may also come before `@lexer`, in a
preamble. Both sections are required; an empty `@parser` section generates
a lexer-only module. A UTF-8 byte order mark at the start of the file is
an error.

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
lines (commas optional), each once. It must declare `eof` (returned at the
end of input) and `err` (returned for a byte no rule matches). The
generated `TokenCat` enum has these names in this order, plus a built-in
`skip`.

```grammar fragment lexer
tokens
    ident, integer, string
    newline, comment
    eof, err
```

Tokens that no lexer rule produces are fine: a lang `Lexer` wrapper can
emit them (layout tokens such as `indent`, keywords it classifies). A
section with no rules at all generates a lexer that returns only `eof`
and `err`, for a wrapper that scans everything itself.

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
   becomes an `err` token, and so does a match longer than a token can
   hold (65535 bytes: the token covers its first 65535, the scan resumes
   after the match), unless the grammar has
   [`@longtokens`](#long-tokens);
5. runs the `after` block (only for a token the DFA matched that consumes
   input, or an `err` byte), then the rule's actions.

Only spaces and tabs are implicit; a newline is an ordinary byte, so a
grammar that does not care about lines skips them with a rule
(`'\n' → skip, skip`). Every rule must be able to win: a rule that an
earlier rule shadows on every text it matches is an error that names the
winning rule and an example text.

A token is 8 bytes: `pos: u32`, `len: u16`, `cat: TokenCat`, `pre: u8`.
Its text is a slice of the source; the lexer never allocates.
[Long tokens](#long-tokens) are longer than `len` can say.

### Patterns

A pattern is a regular expression over bytes:

| Pattern | Meaning |
|---|---|
| `'abc'` `"abc"` | literal bytes; escapes `\n \r \t \0 \\ \' \" \xHH` (two hex digits) |
| `[a-z_]` `[^"\n]` | a byte class: ranges, negation, escapes, `\d \w \s` |
| `.` | any byte, including newline |
| `\n` `\d` ... | a bare escape is a one-byte atom (or class) |
| `( r )` | grouping; `( )` is the empty string |
| `r1 r2` | concatenation (atoms may be juxtaposed or spaced) |
| `r1 \| r2` | alternation |
| `r*` `r+` `r?` | repetition |
| `r{n}` `r{n,}` `r{n,m}` | bounded repetition (bounds up to 255; `r` is copied that many times) |
| `r1 / r2` | trailing context: match `r1` only when `r2` follows; `r2` is not part of the token |

Bare words are errors (`quote literal text as 'x' or "x"`), and so is
anything else outside this language: a pattern is never silently
simplified. A pattern may not match the empty string, nor start only with a
space or tab (the lexer has already consumed those as `pre`; use a
zero-width rule guarded by `pre`). A quantifier follows what it repeats
with no space between, and never another quantifier. The automata have
size limits (see [Limits](#limits)): a pattern whose DFA explodes is an
error, not a slow generation.

Trailing context appears at most once in a pattern, at its top level.
`r2` may not match the empty string; `r1` matches it always (`( ) / r2`, a
zero-width token) or never; and one side has a fixed length. Longest match
counts the context: below, `f(` makes `f` a `call`, while `g (` (with a
space) leaves `g` an `ident`.

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

Every string in the @parser section and in directives (literals, list
separators, `X "c"` hints, `@infix`, `@op`, `@display`, `@errors` and
`@repair` names, tag literals) takes the escapes of a pattern literal:
`\n \r \t \0 \\ \' \" \xHH`. Any other escape is an error at its
backslash. A literal matches the lexer rule whose pattern decodes to the
same bytes, so `"\x2b"` is the token of `'+'`.

### State variables and guards

`state` declares small integer variables (`i8`, -128 to 127; `true` is 1,
`false` 0) with their initial values, each once (`pre` is built in). A
guard after `@` makes a rule apply only when it holds; `&` joins guards:

| Guard | Holds when |
|---|---|
| `v` / `!v` | `v` is non-zero / zero |
| `v == n`, `!=`, `<`, `<=`, `>`, `>=` | the comparison holds (`n` may be negative) |
| `pre > 0` ... | `pre`, the whitespace count (0 to 255), compared like a variable |

Every value written in a guard or an assignment must fit its variable. The
generator compiles one DFA with a start state per combination of guard
values that can occur, so guards cost nothing at run time beyond selecting
the start state. A rule whose guards can never all hold is an error.

`after` lists assignments that run after every token the DFA matches and
that consumes input (and after an `err` byte), unless the rule's own
action sets or counts into the same variable. Tokens that consume nothing
never run it, and neither do zero-width rules, even when their token
covers blanks or `counted()` bytes.

### Lexer actions

| Action | Effect |
|---|---|
| `{v = n}` | set a state variable (`n`, `true`, `false`) |
| `{v++}` `{v--}` | step a state variable (saturating at 127 and -128) |
| `{pre = n}` | set the token's `pre` |
| `{v = counted('c')}` | on a zero-width rule: count the `c` bytes that follow (spaces and tabs between them allowed), consume them, and store the count in `v` (saturating at 127) or `pre` (at 255) |
| `skip` | discard the token and scan on; its bytes count toward the next token's `pre` |
| `hold` | emit the token with zero width at the match start; nothing is consumed |
| `rewind(n)` | end the token after its first `n` bytes (a number, at most the rule's shortest match); the rest is scanned again |

`→ skip, skip` and `→ comment, skip` both discard what they match. A rule
whose token is `skip` without the `skip` action returns a token of the
built-in category `skip`, which a lang `Lexer` wrapper may act on (the
parser treats it as an error).

A token that consumes nothing (from a zero-width rule, `hold`, `rewind(0)`,
or `( ) / r2`) leaves the lexer where it was. Generation rejects any such
rule, and any chain of them, that could fire again and again at one
position: its actions must make one of its guards false, or it must need
whitespace it consumes (a guard false at `pre = 0`). `hold` with
`rewind`, `skip` on a token that consumes nothing, trailing context with
`rewind`, and `counted()` on a consuming rule are errors.

### Zero-width rules

A rule with guards and no pattern is tried before the DFA:

```text
@ guard & guard ...  →  token [, action ...]
```

Its token covers the leading whitespace just skipped (and whatever
`counted()` consumes); with `hold` it is empty and the whitespace is
scanned again, so a guard on `pre` alone cannot stop it. It must require
whitespace (a guard false at `pre = 0`) or change a variable its guards
test. It fires whenever its guards hold, so a zero-width rule whose
guards hold only where an earlier one's do, or a rule with a pattern live
only where a zero-width rule fires, is dead, and an error.

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

### Long tokens

A token's length is a `u16`. Without `@longtokens`, a match longer than
65535 bytes is an `err` token of length 65535, and the scan goes on after
the whole match:

```grammar capped.grammar
@lexer

tokens
    word, string, eof, err

'\n'                        → skip, skip
'"' [^"]* '"'               → string
[a-z]+                      → word
.                           → err

@parser

list! = item+                          → (list ...1)

item  = WORD | STRING
```

```zig test
const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");

test "a match over 65535 bytes is an err token" {
    // `say "aaa…"`, the string 100,000 bytes long.
    const source = try testing.allocator.alloc(u8, 100_004);
    defer testing.allocator.free(source);
    @memcpy(source[0..5], "say \"");
    @memset(source[5 .. source.len - 1], 'a');
    source[source.len - 1] = '"';

    var lx = parser.BaseLexer.init(source);
    _ = lx.next();
    const t = lx.next();
    try testing.expectEqual(parser.TokenCat.err, t.cat);
    try testing.expectEqual(65535, t.len);
    try testing.expectEqual(source.len, lx.pos);
}
```

`@longtokens`, a line of the @lexer section, lifts the limit: a match
longer than 65534 bytes keeps its category, its `len` is 65535, which
stands for "longer", and the lexer records where it ends as it finishes
it. The end is never found again by scanning, as state variables, guards
and a lang `Lexer` can make a later scan from the token's start match
differently.

```grammar long.grammar
@lexer

tokens
    word, string, eof, err

@longtokens

'\n'                        → skip, skip
'"' [^"]* '"'               → string
[a-z]+                      → word
.                           → err

@parser

list! = item+                          → (list ...1)

item  = WORD | STRING
```

```input
say "hi"
```

```tree
(list `say` `"hi"`)
```

```zig test
const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");

test "a string of 100,000 bytes is one token" {
    const source = try testing.allocator.alloc(u8, 100_004);
    defer testing.allocator.free(source);
    @memcpy(source[0..5], "say \"");
    @memset(source[5 .. source.len - 1], 'a');
    source[source.len - 1] = '"';

    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseList();
    const string = tree.items()[2];
    try testing.expectEqual(65535, string.src.len); // "longer"
    try testing.expectEqual(100_004, p.leafEnd(string.src));
    try testing.expectEqualStrings(source[4..], p.leafText(string));
    try testing.expectEqual(parser.Span{ .start = 0, .end = 100_004 }, p.span(tree));
}
```

The parser copies the end of each long token it reads, and everything it
derives from a token uses it: `span`, node spans, side-band roles, facts,
syntax errors, tolerant repairs, `@as` lookups.
`BaseParser.tokenEnd(token)` and `tokenText(token)` (for any token it
read, trivia included), `leafEnd(src)` and `leafText(sexp)` give the end
and the text. A leaf or a token holds no more than its `len`, so the
helpers that have no parser never give part of a long token's text:
`Sexp.getText` and `Sexp.write` panic on a long leaf, and
`BaseLexer.makeToken` on a range over 65534 bytes.
`BaseLexer.text(token)` reads the end from the lexer, which holds the
ends of its last 16 long tokens (`LongEnds`), and panics when it holds no
one end for the token. A lang `Lexer` builds a token whose length it
computes with `BaseLexer.token(cat, pre, start, end)`, which records the
end of a long one in place of any recorded at `start`. A long token the
lexer holds no one end for when the parser reads it (a wrapper read more
than 16 long tokens ahead, scanned one position twice, or made a token of
length 65535 itself), or one at the position of an earlier long token
with another end, fails the parse with `error.TokenEndUnknown`; the parser
never guesses an end.

### The generated lexer

The module exports `TokenCat`, `Token`, `BaseLexer` and `Lexer`.
`BaseLexer` is the generated scanner: `init(source)`, `next()`,
`text(token)`, `makeToken(cat, pre, start, end)`, `token(cat, pre, start,
end)`, and the fields `source`, `pos`, `aux: u16` and the state variables
(and `longEnds` with `@longtokens`; `longTokens` says which). A token is
at most 65535 bytes: a longer match is an `err` token of that length, and
`makeToken` and `token` build tokens the same way; with `@longtokens`, see
[Long tokens](#long-tokens). `Lexer` is the lexer the parser drives: the lang
module's `Lexer` when it declares one (a wrapper that holds a
`base: BaseLexer` and rewrites its token stream: indentation, keyword
classification, synthetic tokens; it has `init(source)` and `next()`),
else `BaseLexer`. [The lang module](SEMANTICS.md#the-lang-module) lists
everything a lang module may declare.

## The @parser section

### Rules

```text
name = element element ...  [< | >]  [→ action]  [~ "reason"]
     | ...
```

A rule has one or more alternatives. A rule name may repeat: later blocks
add alternatives. An alternative may be empty (it matches nothing). Every
rule must be reachable from a start symbol; an unreachable rule is an
error.

A rule of one alternative that is a single token or rule name, with no
action, is an **alias**: `name = IDENT` makes `name` another spelling of
`IDENT`, with no rule and no reduction of its own. Aliases that form a
cycle (`x = y`, `y = x`) are an error.

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
| `-X` | `X`, left out of the span of the node the alternative builds (a leading or trailing element; see [SEMANTICS.md](SEMANTICS.md#span-marks)) | its value |
| `X "c"` | nothing: a [hint](#conflicts-and-hints) | none |
| `@infix` | the [operator chain](#infix) | its value |

`[...]` and choices at the top level of a pattern are expanded into
alternatives (one per combination), so an action's positions stay the same
whichever combination matched. A choice inside a group or another choice
becomes a rule of its own, as a repeated choice does. A multi-element
`[A B]` group is allowed only at the top level (elsewhere, use a helper
rule). Groups and choices nest at most 64 deep.

Each combination is a rule, and the parser gives each its own states:
an alternative with five optional parts is 32 rules, and a run of
optional parts written in several rules is copied into every one of
them. Written once as a clause rule
([SEMANTICS.md](SEMANTICS.md#clause-rules)), the run is parsed by one
set of states wherever it is used. The progress output of generation and
`nexus check` names the alternative that makes the most rules when it
makes 32 or more:

```text
   Expanded: rule 'item' (line 15): one alternative makes 32 rules, one per combination of its [...] groups and choices
```

`[...]` is already optional: it takes no quantifier, and its body must
match something. `[X?]`, `[X*]` and `[A | B?]` are errors (an absent
body and an empty one would look alike); write `[X]` or `X?`. `L(X?)` counts as matching
something, a list of one empty item, so `[L(X?)]` tells an absent list
from that one. An element takes one quantifier, and an `X "c"` hint
belongs to the whole alternative, outside `( )` and `[ ]`.

`X?` and `[X]` are the same. On a rule name the alternative is expanded
(one variant with the rule, one without); on a token a rule `TOKEN?` is
introduced. Generated rules are named in
source syntax (`L(expr)`, `IDENT*`, `(A | B)`), which is how conflict
reports and `@conflicts` entries name them.

`X*`, `X+` and `L(X)` are left-recursive (`L(X) → X | L(X) sep X`): the
parser builds each list in place, in time and memory linear in its length,
and a list ends where the next tokens cannot continue it: in
`L(IDENT) "," "*"`, the comma before `*` follows the list.

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

A tag is any word (`set`, `+=`, `@name`); in the tree it is a value of
the generated `Tag` enum. Without `@schema`, `Tag` has the tags the
actions produce, in first-seen order, then the `@tags` names, and a
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

## Operators and keywords

### @infix

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
`@conflicts`. An `@infix` table that no rule names (`@infix` as an
element) is an error, and so is a rule named `infix` beside it.

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

- A group declared in [`@keywords`](#keywords-keyword-tables) is looked
  up in the table generated from it, `gAs(text) ?GId`, with or without
  `@lang`.
- Otherwise, with `@lang`, group `g` is looked up with
  `lang.gAs(text) ?lang.GId`, where `GId` is an enum whose field names are
  the grammar's keyword terminals (`IF`, `THEN`, ...).
- Otherwise (without `@lang`), group `g` is the single word `g`, promoted
  to `G`.
- `@as TOKEN via fn = [g]` / `[g via fn]` looks group `g` up with
  `lang.fn(text)` instead, which returns `?GId` (`?parser.GId` for a
  `@keywords` group).
- The enum value becomes the leaf's id (`src.id`, a `u16`), so keywords
  have values from 1 (0 means "no id"). A terminal named like the group in
  capitals (`G`) receives every value that has no terminal of its own.
- Matching is strict (the state must shift the keyword) for groups before
  `self`, and permissive (any action, including a reduction first) for
  groups after `self` or written `g!`. `self` keeps `TOKEN` itself when the
  state accepts it.

A capitalized terminal the `tokens` block declares (or a lexer rule
produces) reaches the parser as its own token; any other capitalized
terminal is a keyword that reaches it only through `@as`. A keyword no
group can produce is an error: at generation when every group is a
`@keywords` group or a one-word group, and otherwise a compile error of
the generated parser naming it and the lang module's `GId` enums. One grammar promotes one token; several `@as` lines for it add
their groups in order.

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

### @keywords: keyword tables

`@keywords` declares keyword groups and generates each group's table into
the module, for the `@as` groups of those names. Each indented line is a
group: its name, its options, then its entries. A line indented further
than the block's first group line continues the group above.

```text
@keywords
    group  [caseless] [base N]  entry entry ...
```

| Entry | Accepts | Terminal (and id) |
|---|---|---|
| `word` | the word | `WORD`, the word in capitals |
| `PRE[REST]` | every prefix of `PREREST` at least as long as `PRE` (`H[ANG]`: `H`, `HA`, `HAN`, `HANG`) | `PREREST` |
| `"word"` | the word, for one that is not a name (a string with the escapes of a literal, no blanks) | the word in capitals, which must be a terminal name |
| `entry:NAME` | as `entry` | `NAME` |
| `entry=NAME` | as `entry`: an alias | the terminal `NAME` of another entry of the group |

A bare word is a name (letters, digits and `_`, not starting with a
digit); any other word is quoted, and so is a keyword spelled like an
option. The options:

- `caseless`: words match with ASCII case folded;
- `base N`: the first terminal's id is `N` (1 to 65535) rather than 1, so
  that the ids of several groups differ.

For each group `g` the module exports `pub const GId = enum(u16)`, whose
fields are the group's terminals in the order written (aliases have none)
with ids from 1 or `N`, and `pub fn gAs(text: []const u8) ?GId`, the
lookup `@as` uses, which a lang wrapper may call too. The lookup switches
on the word's first byte, then compares the word with each entry starting
with it; it allocates nothing. The order of entries does not matter, since
no two entries may accept one word.

Below, `w` is an abbreviation of `WRITE` with no terminal of its own, so it
becomes `CMD`; `zq` is an alias of `QUIT`; `HALT` must be written in full,
and `ha` is `HANG`. The `lit` group is case-sensitive (`TRUE` stays a
name), and `nil?` is a quoted word with its own terminal name. After `set` the state expects a
name, so the second `set` stays an identifier.

```grammar keywords.grammar
@lexer

tokens
    ident, number, newline, eof, err

'\n'                            → newline
[0-9]+                          → number
[a-zA-Z_][a-zA-Z0-9_]* '?'?     → ident
.                               → err

@parser

@keywords
    cmd   caseless  S[ET] W[RITE] H[ANG] HALT Q[UIT] ZQ=QUIT
    lit   true false "nil?":NIL_P

@as IDENT = [cmd!, lit!]

prog! = line+                          → (prog ...1)

line  = SET IDENT value NEWLINE        → (set 1 2 3)
      | CMD value* NEWLINE             → (cmd 1 ...2)

value = IDENT | NUMBER | TRUE | FALSE
      | NIL_P value                    → (nil? 1 2)
```

```input
s x 10
SET y true
w x Y
ha 5
halt
zq
write nil? false TRUE
set set 1
```

```tree
(prog
  (set `s`#1 `x` `10`)
  (set `SET`#1 `y` `true`#1)
  (cmd `w`#2 `x` `Y`)
  (cmd `ha`#3 `5`)
  (cmd `halt`#4)
  (cmd `zq`#5)
  (cmd `write`#2 (nil? `nil?`#3 `false`#2) `TRUE`)
  (set `set`#1 `set` `1`))
```

The module has, for the `cmd` group:

```zig fragment
pub const CmdId = enum(u16) { SET = 1, WRITE, HANG, HALT, QUIT };
pub fn cmdAs(text: []const u8) ?CmdId { ... }
```

Generation rejects two entries that accept one word (after case folding,
abbreviations included; the error names both and the word), two entries
of one terminal (write the second as an alias), an alias of a name that is
no terminal of its group, a malformed abbreviation (`A[`, `[X]`, `A[]`),
an unquoted word that is not a name, a word whose capitals are no terminal
name (`__FILE__` needs `__FILE__:NAME`), an option given twice or after an
entry, `base` without a number from 1 to 65535, ids past 65535, an empty
group, a group declared twice, a group named `node` (its enum would be the
module's `NodeId`), a group that is the group of no `@as` (`self` and the
promoted token's name are never groups), and `@keywords` in a grammar
without parser rules. A lang module that declares its own `GId` or `gAs`
for a `@keywords` group makes the generated parser fail to build, naming
the group; it may re-export the generated ones
(`pub const GId = parser.GId;`).

## Conflicts and hints

Nexus builds LALR(1) tables. A shift/reduce conflict resolves to the
shift, a reduce/reduce conflict to the lowest-numbered rule of the
generated grammar (rules in the order written, each helper rule numbered
where it is first used), and the accept action always wins over
reductions on end of input. Every conflict a grammar leaves must be
declared in `@conflicts`, with a reason. Generation fails on any
difference and prints each undeclared conflict with its state, items, and
a shortest symbol path to that state (grammar symbols, not input), then
the whole manifest ready to paste:

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
dangling.grammar:15:9: error: undeclared conflict: shift  stmt → KW_IF IDENT KW_THEN stmt  (1)
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
dropped for a lower-numbered rule), where `N` counts the table cells
(state, lookahead) the entry covers. Rules are written `lhs → rhs` over the
generated grammar (`->` matches `→`, runs of blanks match one space, `ε`
is an empty right-hand side, quoted literals compare as written). No
`@conflicts` block, or an empty one, means the grammar must be
conflict-free.

Hints resolve a conflict on purpose; a hinted conflict is not a conflict:

| Hint | Where | Effect |
|---|---|---|
| `>` | after an alternative's elements | its reductions lose to shifts, silently |
| `<` | after an alternative's elements | its reductions win over shifts |
| `X "c"` | among an alternative's elements | its reduction wins over shifting the terminal `"c"` names (one byte, escapes as in literals), except when that token directly follows the previous token (no whitespace): then the parser shifts. `"c"` names a terminal the way a literal in a rule does: the literal `"c"` if the parser grammar writes it, else the token the lexer gives exactly `"c"` (or `@op` maps it to), written by name (`LPAREN`) |

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

An `X "c"` hint that decides nothing is an error. So is one whose `"c"`
names no terminal: no lexer rule's pattern is exactly `"c"` and no `@op`
maps it; the parser grammar uses none of its tokens; lexer rules in
different states, or under different guards, make `"c"` two tokens the
grammar uses; it is the token `@as` promotes; or the grammar writes that
token as another literal. Two hints of one alternative must name
different terminals. A hint applies to its
terminal, so to every lexeme of that token: with `'(' → open` and
`'[' → open`, `X "("` also shifts a touching `[`. A hint counts as used
when it decides a cell for any rule its alternative expands into.

## Directives

| Directive | Section | Purpose |
|---|---|---|
| `@lang = "name"` | any | the lang module (`name.zig`, imported by the parser; see [SEMANTICS.md](SEMANTICS.md#the-lang-module)) |
| `@code = fn` | @lexer | a lexer method calling `lang.fn(source, pos)` |
| `@longtokens` | @lexer | tokens of any length ([Long tokens](#long-tokens)) |
| `@schema` | any | node kinds and their roles ([SEMANTICS.md](SEMANTICS.md)) |
| `@tags a b ...` | any | extra `Tag` values for a lang wrapper |
| `@conflicts` | any | the declared conflicts |
| `@infix base` | any | an operator-precedence chain |
| `@op = [ "lit" → "token", ... ]` | any | literal-to-token mappings |
| `@as TOKEN [via fn] = [g, ...]` | any | contextual keywords |
| `@keywords` | any | keyword tables for `@as` groups |
| `@display` | any | reader names of tokens for syntax errors |
| `@errors` | any | reader names of rules for syntax errors |
| `@trivia T ...` | any | tokens kept on a side channel, never parsed |
| `@repair` | any | the tokens tolerant parsing may insert |
| `@highlight` | any | how editors colour the language ([Editor support](#editor-support)) |
| `@messages` | any | messages of their own for syntax errors, by example ([Messages](#messages)) |
| `@lsp` | any | names and scopes, for the language server ([Names and scopes](#names-and-scopes)) |

"Any" means the preamble or the @parser section; a directive of the
@lexer section anywhere else is an error. Each directive appears at most
once (`duplicate @x`), except `@as` and `@code`, and each name appears
once in its directive. The fragment below shows the syntax;
[SEMANTICS.md](SEMANTICS.md#an-example) has a complete, tested grammar
that uses `@display`, `@errors`, `@trivia` and `@repair`.

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

## Messages

`@messages` (in the preamble or the @parser section, at most once) gives
the syntax errors a grammar knows to be common messages of their own.
Each indented line is an example of the mistake and its message:

```text
at | after   [start!:]   sentence   →   "message"
```

The sentence is grammar symbols, written as rules write them: rule
names, token names and literals. Its last element is the token the
parser cannot take, or a choice of such tokens, `( A | B )`. A token
written against a `(` takes a text guard, `ERR("?")`: the entry matches
only when the offending token's text is `?`. The arrow and the message
may go on an indented line of their own.

```grammar sums.grammar
@lexer

tokens
    ident, number, kw_print, eq, semi, lt, plus, lparen, rparen, eof, err

'\n'                        → skip, skip
'='                         → eq
';'                         → semi
'<'                         → lt
'+'                         → plus
'('                         → lparen
')'                         → rparen
"print"                     → kw_print
[a-z]+                      → ident
[0-9]+                      → number
.                           → err

@parser

@display
    IDENT: "a name", NUMBER: "a number", KW_PRINT: "'print'"

@errors
    stmt: "a statement", expr: "an expression"

@messages
    after  IDENT "=" expr (IDENT | KW_PRINT)
                                    → "expected ';' after the value, got {got}"
    at     IDENT "=" IDENT "<" IDENT "<"
                                    → "comparison operators cannot be chained"
    after  stmt ERR("?")            → "`?` is no operator here"
    after  stmt ERR                 → "unexpected {got}; expected {expected}"
    at     expr!: "(" IDENT EOF     → "`(` is never closed"

program! = stmt+                    → (program ...1)
expr!    = expr

stmt     = IDENT "=" expr ";"       → (set 1 3)
         | KW_PRINT expr ";"        → (print 2)

expr     = sum
         | sum "<" sum              → (lt 1 3)

sum      = term
         | sum "+" term             → (add 1 3)

term     = IDENT
         | NUMBER
         | "(" expr ")"             → 2
```

```zig test
const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");

fn expectError(start: parser.Start, src: []const u8, want: []const u8) !void {
    var p = parser.BaseParser.init(testing.allocator, src);
    defer p.deinit();
    try testing.expectError(error.ParseError, p.parse(start));
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try p.writeError(&out.writer);
    try testing.expectEqualStrings(want, out.written());
}

test "@messages words the errors it has examples of" {
    // `after`: the value is complete, whatever it ends in.
    try expectError(.program, "x = (a + 1) y = 2;", "1:13: expected ';' after the value, got a name");
    // `at`: the state that rejects the second `<`.
    try expectError(.program, "x = a < b + c < d;", "1:15: comparison operators cannot be chained");
    // A guard before the unguarded entry; {got} and {expected}.
    try expectError(.program, "x = 1; ?", "1:8: `?` is no operator here");
    try expectError(.program, "x = 1; !", "1:8: unexpected '!'; expected a statement or end of input");
    // An `at` entry keys on a state, whichever start symbol reached it.
    try expectError(.expr, "(a", "1:3: `(` is never closed");
    try expectError(.program, "x = (a", "1:7: `(` is never closed");
    // Without an entry, the automatic message.
    try expectError(.program, "x = 1 )", "1:7: expected \";\" after an expression, got \")\"");
}
```

How an example is read:

- **Symbols, not text.** A rule name stands for any derivation of it:
  the generator takes the rule's goto (after the reductions the parser
  makes on a token that can begin the rule, when the state has no goto
  on it). A token the lexer gives but the parser grammar does not use
  (an `err` token, say) reaches the parser as the `error` symbol and is
  written by its name, `ERR`; `EOF` is the end of input. Layout and the
  tokens a lang `Lexer` makes are written as tokens too: the lang module
  never runs at generation time. A sentence starts at the first start
  symbol; `name!:` starts it at another.
- **`at` keys on the failure state.** The generator runs the sentence
  through the parse table as the parser runs input: each token after the
  reductions the table makes on it. On the last token it makes the
  reductions, and the state that rejects the token is the failure state.
  An `at` entry applies wherever the parser rejects that token in that
  state, which tokens alone describe best.
- **`after` keys on the construct being finished:** the anchor of the
  error's reduction chain, the state the last `@errors`-named rule the
  chain completes leads to (or the failure state, when it completes
  none; see [SEMANTICS.md, "Syntax errors"](SEMANTICS.md#syntax-errors)).
  Whatever the named rule's last token was, the chain ends at the same
  anchor, so an `after` sentence ends in an `@errors`-named rule, then
  the token.
- **Which entry.** `writeFailure` (and so `writeError`, every one of a
  tolerant parse's `failures`, and the language server's diagnostics)
  takes an `at` entry for the failure state and the token first, then an
  `after` entry for the anchor and the token; of each kind, one whose
  guard is the token's text before one without a guard. With none, the
  message is the automatic one.
- **Placeholders.** `{got}` is the offending token as the automatic
  message names it, and `{expected}` the automatic list (`A, B or C`).
  Any other `{` is an error.
- **States are what the parser knows.** LALR(1) gives contexts with the
  same items one state, so two such contexts get one message; a context
  the parser reaches in several states (after a first statement, after a
  later one) needs an example for each.

Every mistake is an error at its place: a sentence the parser takes
whole (`this example is not a syntax error`); one it rejects before the
last token (`the parser fails here, before the example's last token`);
two entries for one key, with different messages (`the parser cannot
tell them apart`) or the same (`duplicate message`); a name that is no
rule, token or literal, or no start symbol; a choice or a guard before
the last element; a rule as the last element; a guard on a rule, or one
whose text the lexer never gives the token (`IDENT("if")` when `if` is a
keyword; a token only a lang `Lexer` makes is not checked); and an
unknown placeholder. The examples are run again on every generation, so
a grammar change cannot move a message silently: its example still
reaches an error, perhaps in another state, or generation fails.

`nexus check --messages grammar` writes the coverage on standard output.
A place is an anchor an `after` entry can key on: the state the parser
enters on an `@errors`-named rule, when an error right after the rule is
anchored there. For each place without an entry it writes the shortest
example that reaches it, ready to complete with a token and a message
(`after KW_PRINT expr`), and on the next line, after `#`, its automatic
message (`expected ";" after an expression`); then how many places have
one (`N of M places have a message`). `./test/run` pins the report of
every grammar with `@messages` (`test/golden/<grammar>.messages.txt`).

## Editor support

`@highlight` (in the preamble or the @parser section, at most once) says
how editors colour the language. From it, `nexus --highlight` writes a
TextMate grammar (VS Code and the editors that read TextMate grammars),
VS Code's language configuration, a highlight.js language and a Vim
syntax file. `@highlight` changes nothing in the generated parser.

```grammar tasks.grammar
@lexer

tokens
    word, number, string, comment, colon, lparen, rparen
    kw_task, kw_done, eof, err

'#' [^\n]*                      → comment
'"' ([^"\\\n] | '\\' .)* '"'    → string
[0-9]+                          → number
':'                             → colon
'('                             → lparen
')'                             → rparen
"task"                          → kw_task
"done"                          → kw_done
[a-z]+                          → word
'\n'                            → skip, skip
.                               → err

@parser

@highlight
    language            "Tasks"
    scope-name          source.tasks
    extensions          tasks
    line-comment        "#"

    keyword             "task" [ \t]+ function:([a-z]+)
    label               [a-z]+ after [ \t]* ':'
    keyword             "task" "done"
    punctuation         ":" "(" ")"
    constant.numeric    NUMBER
    string              STRING
    string.escape       '\\' [n"\\] within STRING
    comment             COMMENT
    invalid             ERR

tasks! = item*                          → (tasks ...1)

item   = KW_TASK WORD ":" STRING        → (task 2 4)
       | KW_DONE WORD                   → (done 2)
       | WORD ":" "(" NUMBER ")"        → (count 1 4)
```

Each of the three files that colour text colours this sample the same
way: under each line, `^` marks a run of characters and names its scope.

```sample
task shop: "milk\n, \"eggs\"" # today
shop : (2) $
done shop
taskforce: (3)
```

```highlight
> task shop: "milk\n, \"eggs\"" # today
  ^^^^^ keyword
       ^^^^ function
           ^ punctuation
             ^^^^^ string
                  ^^ string.escape
                    ^^ string
                      ^^ string.escape
                        ^^^^ string
                            ^^ string.escape
                              ^ string
                                ^^^^^^^ comment
> shop : (2) $
  ^^^^ label
       ^ punctuation
         ^ punctuation
          ^ constant.numeric
           ^ punctuation
             ^ invalid
> done shop
  ^^^^ keyword
> taskforce: (3)
  ^^^^^^^^^ label
           ^ punctuation
             ^ punctuation
              ^ constant.numeric
               ^ punctuation
```

### Entries

Each indented line of `@highlight` is a metadata line or an entry,
`SCOPE targets [contexts] [within TOKEN]`. A line names one scope; a
scope may head many lines. The targets are either a list of these, blank
separated:

| Target | Matches |
|---|---|
| `"if"` `'+'` | the literal (escapes as in patterns); it must be text some lexer rule matches whole |
| `NUMBER` | the text of the token: its lexer rules' patterns (with trailing context as a lookahead) |
| `cmd` | every word of the `@keywords` group, its abbreviations, in either case when `caseless` |

or one pattern, in the syntax of the @lexer section (without `/`): any
other text, such as `[a-z]+ '!'`. A literal that ends in a word
character (a letter, digit or `_`, unless `word-chars` says otherwise)
does not match where another one follows (`"if"` leaves `iffy` alone),
nor one that starts with one where one precedes; a pattern matches as
written.

A target belongs to one entry without contexts. An entry with a context,
`line-start` or `line-end` is tried before those (see the order below),
so it may name a target another entry lists: with `operator "*"` and
`storage.modifier '*' not before [A-Za-z0-9_)] after [a-z_]`, a `*`
touching a name after it is a `storage.modifier`, any other `*` an
`operator`.

A pattern may tag parts of itself with scopes: `SCOPE:( pattern )`, at
its top level, names the text the parenthesized pattern matches. The
entry's scope colours the parts between. Above, `"task" [ \t]+
function:([a-z]+)` colours `task` and the blanks as `keyword` and the
name as `function`. A pattern with captures is a sequence: each part must
match something, and an alternation goes inside `( )`.

Contexts follow the targets and restrict where they match; none of them
is part of the match. They bind to the whole entry: to each of its
literals, words and tokens, and to all of its pattern (`line-start ([a-z]+
| [0-9]+)` matches a number only at the start of a line):

| Context | The match |
|---|---|
| `after P` | is followed by text `P` matches |
| `not after P` | is not followed by text `P` matches |
| `before P` | is preceded by text `P` matches; `P` has one length, as editors require |
| `not before P` | is not preceded by text `P` matches (`P` of one length) |
| `line-start` | starts at the start of a line |
| `line-end` | ends at the end of a line |

`within TOKEN` makes the entry match only inside the token's text. That
token becomes a region: each of its rules must be a literal prefix, a
body and a suffix that ends in a literal (`'"' (...)* '"'`). The region
opens at the prefix; inside it, the entries within it, then one
repetition of the body, are tried before the suffix, which closes it.
Above, `\n` and `\"` are escapes, and the `"` after `\` does not end the
string. The token's own entry (`string STRING`) colours the rest of the
region; its entry takes no context, and an entry within a region names
no other region.

Editor patterns match characters within a line: a pattern written as
UTF-8 bytes matches the character, a class with every byte from 0x80
matches every non-ASCII character, and no class matches a line break (`.`
neither). A pattern that matches part of a UTF-8 character has no editor
form and is an error.

### The order

Editors try what they match in one order, and where two items match at
one position, the first wins:

1. the entries with a pattern, a context, `line-start` or `line-end`, as
   written;
2. the literals and `@keywords` words; a literal that can match the
   start of a longer one comes after it (`"<"` after `"<="`), and the
   literals of one scope are tried together, longest first;
3. a run of blanks, uncoloured (blanks start no token);
4. every lexer rule, in lexer order: a listed token's rule coloured (a
   region at its first rule), any other uncoloured, so that no later item
   colours part of its text.

A token no entry lists gets no colour. The order is not the lexer's
longest match: at one position, a literal comes before a longer token,
and an earlier lexer rule before a later one that would match more. So
an `invalid` entry naming an error token written after the rules it
catches (`[0-9][0-9A-Za-z_]*` after `[0-9]+`) colours nothing where an
earlier rule matches first, and `invalid` naming a token spelled `**`
loses to the literal `"*"`. Where that matters, list the longer text as
a literal or a pattern, which come first.

An editor's highlighter has no lexer state: guards are not tested, and a
guarded rule is tried wherever its pattern matches, in its place in the
lexer order. So a guarded rule earlier in the order can cut an unguarded
token short (a pattern-mode `[0-9]+` ahead of the number rule splits
`1E3`); colour such text with a pattern entry, which comes first.

### Metadata

| Line | Meaning |
|---|---|
| `language "Name"` | the language's name in editors (required) |
| `scope-name source.x` | the TextMate scope (`source.` or `text.`, then lowercase dot-separated parts; required). Its last part is the language id: the suffix of TextMate scopes, the prefix of Vim groups, the highlight.js name and the file names `--highlight all` writes |
| `extensions x y` | the file extensions, without the dot (required) |
| `line-comment "#"` | VS Code's line comment |
| `block-comment "/*" "*/"` | VS Code's block comment |
| `indent P` / `dedent P` | VS Code's indentation rules: a line that matches `indent` indents the next line, one that matches `dedent` outdents itself. `P` is a pattern with contexts; the two go together |
| `word-chars [A-Za-z0-9%]` | the characters of words, one character class: a literal that starts or ends with one does not match next to another. By default `[A-Za-z0-9_]` |

### Scopes

Every entry names one of these scopes, written in each file as:

| Scope | TextMate | highlight.js | Vim |
|---|---|---|---|
| `keyword` | `keyword.other` | `keyword` | `Keyword` |
| `keyword.control` | `keyword.control` | `keyword` | `Statement` |
| `keyword.operator` | `keyword.operator.word` | `keyword` | `Operator` |
| `constant` | `constant.language` | `literal` | `Constant` |
| `constant.numeric` | `constant.numeric` | `number` | `Number` |
| `constant.symbol` | `constant.other.symbol` | `symbol` | `Constant` |
| `string` | `string.quoted` | `string` | `String` |
| `string.escape` | `constant.character.escape` | `char.escape` | `SpecialChar` |
| `comment` | `comment` | `comment` | `Comment` |
| `operator` | `keyword.operator` | `operator` | `Operator` |
| `punctuation` | `punctuation` | `punctuation` | `Delimiter` |
| `type` | `entity.name.type` | `type` | `Type` |
| `function` | `entity.name.function` | `title.function` | `Function` |
| `function.builtin` | `support.function` | `built_in` | `Function` |
| `label` | `entity.name.label` | `symbol` | `Label` |
| `storage.modifier` | `storage.modifier` | `keyword` | `StorageClass` |
| `variable.parameter` | `variable.parameter` | `params` | `Identifier` |
| `variable.special` | `variable.language` | `variable.language` | `Identifier` |
| `invalid` | `invalid.illegal` | `deletion` | `Error` |

A TextMate scope ends with the language id (`keyword.other.tasks`). A
Vim group is the id and the scope (`tasksKeyword`, `tasksStringEscape`),
linked to the Vim group above; groups of entries within a region, and of
the parts of a pattern with captures after the first, link to those.

### The files

```text
nexus --highlight textmate tasks.grammar tasks.tmLanguage.json
nexus --highlight language-configuration tasks.grammar language-configuration.json
nexus --highlight highlightjs tasks.grammar tasks.js
nexus --highlight vim tasks.grammar tasks.vim
nexus --highlight all tasks.grammar editors
```

The output file defaults to standard output (`-`). `--highlight all`
writes every file into a directory, each replaced atomically:

```text
editors/vscode/syntaxes/tasks.tmLanguage.json
editors/vscode/language-configuration.json
editors/vim/syntax/tasks.vim
editors/highlightjs/tasks.js
```

A language keeps them in `editors/` beside its grammar, written by
`nexus --highlight all x.grammar editors`. `--highlight` on a grammar
without `@highlight` is an error. `nexus --editor` writes the same files
with a VS Code extension and a language server ([LSP.md](LSP.md)).

- The TextMate grammar lists the items in order under `patterns`; a
  pattern with captures is one regex with `captures`, a region a
  `begin`/`end` rule with `applyEndPatternLast` and its items and body as
  `patterns`.
- The language configuration has the comments, the bracket pairs among
  `( )`, `[ ]`, `{ }` and `< >` when both are literals listed as
  `punctuation`, auto-closing and surrounding pairs (the brackets, and
  the prefix and suffix of each region whose suffix is a literal, not
  closed inside strings and comments), and the indentation rules.
- The highlight.js file is an ES module: `export const extensions` (the
  metadata's extensions) and `export default function (hljs)`, which
  returns the language: `name`, `aliases` (the extensions), `keywords`
  (empty: every word is an item) and `contains`, the items in order. A
  pattern with captures is a `match` array with a `scope` per part, a
  region a mode with `begin`, `end` and `contains`. It needs highlight.js
  11 or later.
- The Vim syntax file defines the items from last to first (where two
  start together, Vim takes the one defined last); a region is a `syn
  region` whose `skip` is its body, its entries `contained`; a pattern
  with captures is a chain of `syn match` items joined by `nextgroup`.

`./test/run` checks each file by what it does: the TextMate grammar
through a reference tokenizer that follows vscode-textmate, the
highlight.js language through one that follows highlight.js, and the Vim
file in Vim itself, on samples of each grammar with `@highlight`; each
must colour every character as expected (highlight.js, with its fewer
classes, with the class of the expected scope).

### Checks

Generation (and `nexus check`) rejects, each at its place: a word that
is no scope or metadata key; a missing `language`, `scope-name` or
`extensions`; a malformed or repeated metadata line (a `word-chars`
that is not one character class with an editor form); `indent` without
`dedent`; an unknown token or `@keywords` group; a literal no lexer rule
matches whole; a token whose text no rule gives (a lang Lexer makes it,
or it only rewinds); a target listed twice, or under two scopes, by
entries without contexts; a
capture inside `( )`, with an unknown scope, or empty; a pattern with
captures and a top-level `|`, or with a part that matches nothing; a
pattern or context that matches the empty string; `not` without `after`
or `before`; a `before` pattern of varying length; trailing context `/`;
`within` something other than a token, or a token whose rules are not
regions; a context on a region's entry; a region within a region; a
pattern with no editor form; and a second `@highlight`.

## Names and scopes

`@lsp` (in the preamble or the @parser section, at most once) declares a
language's names: which nodes open scopes, which leaves define names and
which use them, which assignments bind them, which import files, and
which name members of something else, names of another file, or names of
a namespace; and the colours of names by what they name, and words to
complete beside the grammar's. From it the language server `nexus
--editor` writes ([LSP.md](LSP.md)) gives the outline, go to definition,
references, document highlights, rename, completion of the names in
scope and after `.`, hover, and semantic tokens by meaning, across the
files of the workspace, with no code in `hooks.zig`. `@lsp` names the
kinds and roles of `@schema` ([SEMANTICS.md](SEMANTICS.md#schema)), so
it needs one; it changes nothing in the generated parser.

```grammar steps.grammar
@lexer

tokens
    ident, number, comment, newline
    kw_def, kw_let, kw_end, eq, plus, lparen, rparen, comma, dot
    eof, err

'#' [^\n]*                  → comment
'\n'                        → newline
"def"                       → kw_def
"let"                       → kw_let
"end"                       → kw_end
'='                         → eq
'+'                         → plus
'('                         → lparen
')'                         → rparen
','                         → comma
'.'                         → dot
[0-9]+                      → number
[a-z_]+                     → ident
.                           → err

@parser

@schema
    file        ...items
    def         name:leaf params:params body:body
    params      ...names:leaf
    body        ...items
    let         name:leaf value
    name        id:leaf
    num         value:leaf
    add         left right
    call        callee ...args
    get         object field:leaf

@trivia COMMENT

@repair
    holes       IDENT
    terminator  NEWLINE

@highlight
    language            "Steps"
    scope-name          source.steps
    extensions          steps
    line-comment        "#"
    keyword             "def" "let" "end"
    operator            "=" "+"
    punctuation         "(" ")" "," "."
    constant.numeric    NUMBER
    comment             COMMENT
    invalid             ERR

@lsp
    scope       file unordered
    scope       def body
    define      def.name        function  outer  doc:leading  detail:..body
    define      params.names    variable
    define      let.name        variable  doc:leading
    use         IDENT
    skip        get.field
    builtin     "print"
    doc         COMMENT strip "#"
    undefined   warning

file!  = lines                                      → (file ...1)

lines  = line                                       → (1)
       | lines NEWLINE line                         → (...1 3)

line   = item
       |                                            → _

item   = KW_DEF IDENT "(" [L(IDENT)] ")" NEWLINE lines KW_END
                                                    → (def 2 (params ...4) (body ...7))
       | KW_LET IDENT "=" expr                      → (let 2 4)
       | expr

expr   = expr "+" atom                              → (add 1 3)
       | atom

atom   = IDENT                                      → (name 1)
       | NUMBER                                     → (num 1)
       | atom "." IDENT                             → (get 1 3)
       | atom "(" [L(expr)] ")"                     → (call 1 ...3)
       | "(" expr ")"                               → 2
```

A file of Steps is a scope whose names are in sight anywhere in it
(`unordered`); a `def` opens a scope for its parameters, and its body
one for its `let`s, each in sight from the end of its `let` on. The name
of a `def` belongs to the scope around the `def` (`outer`), its detail is
its text up to its body, and its doc is the comment lines just before
it. A name after `.` is a field, which is not looked up here; `print` is
a builtin. The server, with `hooks.zig` as `--editor` writes it, answers
this session ([test/README.md, "Language-server
sessions"](../test/README.md#language-server-sessions)) as shown:

```session
initialize quiet
open main.steps
| # Twice a number.
| def twice(n)
|     let sum = n + n
|     sum
| end
| let four = twice(2)
| def show(x)
|     print(x.size, four, missing)
| end
hover main.steps 2:6
definition main.steps 4:5
references main.steps 2:11
completion main.steps 8:20
completion main.steps 8:13
rename main.steps 3:9 total
rename main.steps 7:10 four
rename main.steps 6:6 eight
symbols main.steps
```

```out
> initialize quiet
> open main.steps
diagnostics main.steps
  {"message":"'missing' is not defined","range":"8:25-8:32","severity":2,"source":"steps"}
> hover main.steps 2:6
{"contents":{"kind":"markdown","value":"```steps\ndef twice(n)\n```\n\nTwice a number."}}
> definition main.steps 4:5
main.steps 3:9-3:12
> references main.steps 2:11
  main.steps 2:11-2:12
  main.steps 3:15-3:16
  main.steps 3:19-3:20
> completion main.steps 8:20
  {"kind":6,"label":"x"}
  {"detail":"def show(x)","kind":3,"label":"show"}
  {"kind":6,"label":"four"}
  {"detail":"def twice(n)","documentation":{"kind":"markdown","value":"Twice a number."},"kind":3,"label":"twice"}
> completion main.steps 8:13
[]
> rename main.steps 3:9 total
{"changes":{"main.steps":[{"newText":"total","range":"3:9-3:12"},{"newText":"total","range":"4:5-4:8"}]}}
> rename main.steps 7:10 four
error -32803 'four' would capture the use of 'four' on line 8
> rename main.steps 6:6 eight
{"changes":{"main.steps":[{"newText":"eight","range":"6:5-6:9"},{"newText":"eight","range":"8:19-8:23"}]}}
> symbols main.steps
  {"children":[{"kind":13,"name":"n","range":"2:11-2:12","selectionRange":"2:11-2:12"}],"detail":"def twice(n)","kind":12,"name":"twice","range":"2:1-5:4","selectionRange":"2:5-2:10"}
  {"kind":13,"name":"four","range":"6:1-6:20","selectionRange":"6:5-6:9"}
  {"children":[{"kind":13,"name":"x","range":"7:10-7:11","selectionRange":"7:10-7:11"}],"detail":"def show(x)","kind":12,"name":"show","range":"7:1-9:4","selectionRange":"7:5-7:9"}
```

### The lines

Each indented line starts with its key; the words after it are taken
whole (as `@keywords` takes them), and a line indented further than the
block's first continues the line above. `KIND` and `ROLE` are names of
`@schema`, `TOKEN` a token as rules write it, `SYMBOLKIND` one of LSP's
symbol kinds as the server names them (`file`, `module`, `namespace`,
`package`, `class`, `method`, `property`, `field`, `constructor`,
`enum`, `interface`, `function`, `variable`, `constant`, `string`,
`number`, `boolean`, `array`, `object`, `key`, `null`, `enum_member`,
`struct`, `event`, `operator`, `type_parameter`).

| Line | Meaning |
|---|---|
| `scope KIND ... [unordered]` | a node of each kind opens a scope; in an `unordered` one, a name is in sight anywhere in it |
| `define KIND.ROLE SYMBOLKIND [options]` | the leaf in ROLE of a KIND node defines a name |
| `use TOKEN ...` | a leaf of these tokens that no `define` or `skip` takes uses a name |
| `skip KIND.ROLE ...` | the leaf in ROLE is neither: a member, a label, a field initializer's name |
| `skip KIND.ROLE when ...` | the same, only when the conditions hold, before any `define` line |
| `builtin "name" ...` or `builtin TOKEN` | names, or every leaf of a token, that resolve to nothing, silently |
| `doc TOKEN [strip "text"]` | the token of doc comments, and the text to take off each one's start |
| `undefined error\|warning` | a use that resolves to nothing is an error or a warning in the editor |
| `import KIND.ROLE [when ...] [file "{}.ext"]` | a KIND node imports the file its ROLE leaf names (the first leaf of a rest role; a string's contents, else the name): a module's file, else that path (made with `file`, `{}` standing for the name) relative to the importing file |
| `member KIND.ROLE of:ROLE` | the leaf in ROLE is a member of what the `of` role denotes, looked up among its members |
| `qualify KIND.ROLE in:ROLE` | the leaf in ROLE names a definition of the file's own scope of the file the `in` role, an import, names (`LABEL^ROUTINE`); without the `in` role, the leaf is what it would be without the line |
| `nominal TOKEN [ns:NAME]` | every leaf of the token is a name of the namespace NAME (the token's own, without `ns:`): all of one text are one name across the workspace, which no definition declares |
| `bind KIND.ROLE SYMBOLKIND [when ...]` | the leaf in ROLE, an assignment's target, defines a name unless a definition of the name is in sight there, which it then uses |
| `color KIND.ROLE SCOPE [MODIFIER ...] [when ...]` | the semantic token of the leaf in ROLE, and of every name of the definition it makes |
| `color KIND start\|end SCOPE [MODIFIER ...] [when ...]` | the semantic token of a KIND node's first or last token |
| `words "lit" ...` | words completion offers beside the grammar's: words a lang Lexer makes keywords of |

The options of `define`:

| Option | Meaning |
|---|---|
| `when ROLE "text"` | only when the node's ROLE leaf is `text` (an absent role's text is empty) |
| `when ROLE` | only when the node has ROLE |
| `when ROLE:KIND` | only when the node's ROLE holds a KIND node |
| `when ^KIND.ROLE ["text"]` | the same of a role of the node's parent, which is a KIND (`^KIND.ROLE:KIND` too) |
| `outer` | the name belongs to the scope around the nearest one |
| `member` / `lexical` | the name is only a member of its scope (a field: never in sight by itself), or only in sight (never a member, which `member` and `qualify` look up); by default both |
| `value:ROLE` | the node's value: when it opens a scope, that scope's names are the name's children in the outline; the members of the name are those of what the value denotes |
| `type:ROLE` | its declared type: the name's detail when it has no other; the members of the name are those of what the type denotes, when its value denotes nothing |
| `doc:ROLE` or `doc:leading` | its doc: the leaves of ROLE, or the doc tokens on the lines just before the node, each without the `strip` text and one blank after it |
| `export:ROLE` or `export:^KIND` | other files see the name, as a member or a qualified name, only when ROLE is present (`pub`), or when the node's parent is a KIND; without it, they see every name they reach |
| `detail` or `detail:..ROLE` | its one-line detail: the node's tokens, or its tokens before ROLE, one blank between two that have any, without comments and without operators at the end |

`when` may be given more than once; every one must hold. Two `define`
lines for one role differ in their `when`s, and the first whose
conditions hold defines; a leaf none takes is what it would be without
them. `import`, `bind` and `color` take `when` as `define` does, and so
do two such lines for one role.

### How names resolve

One walk over the tree the parser builds (tolerantly, with `@repair`, so
a file with errors keeps its names) finds the scopes, the definitions and
the uses. The file is the outermost scope, unordered when the kind its
start symbol builds is. A definition belongs to the nearest scope at or
around its node; with `outer`, to the scope around that one. A use
resolves up its chain of scopes to the nearest definition of its name
that is in sight: in an unordered scope any, in an ordered one the last
whose node ends before the use (whose own leaf does, for an `outer`
definition and for one whose node opens the scope it belongs to, like a
capture). A use no definition answers is a builtin when `builtin` names
it, else unresolved; a builtin's name is never a definition in sight (a
`member` definition may have one, as an enum's field `true` does). A
member is never in sight. A leaf a `bind` line takes, after the walk and
in the order of the text, resolves as a use does, against the
definitions of `define` lines and of the binds before it: when it finds
one it is a use of it, and else it defines its name in the nearest scope,
in sight from the end of its node on, as a `define` line's would.

Across files, an expression denotes what names tell: a use what it
resolves to, a member what it names, an import its file, a node that
opens an unordered scope that scope, and a node whose one child is a use
what the use denotes. The members of a definition are the names of the
scope its value denotes (its node's own import, for a definition whose
node imports), else of the scope its declared type denotes; the names of
an unordered scope, a file's or a container's, are members, and those of
an ordered one (a block's, a function's) are not. A member `a.b` names
the definition of `b` among the members of what `a` denotes; a
qualified name `b^f`, the definition of `b` of the own scope of the file
`f` imports. Both see a `lexical` definition never, and one of another
file only when it is exported. What needs a value's type (a call's
result, a generic, a pointer) denotes nothing, so a member of it answers
nothing, and an alias in a cycle the same. Names of a namespace are one
when their texts are.

### Files and members

Pieces imports a file with `use NAME`: NAME.pcs beside the importing
file. A name after `.` is a member of what is before it, the file of a
`use` or what a `let`'s value denotes:

```grammar pieces.grammar
@lexer

tokens
    ident, number, newline, kw_use, kw_let, eq, dot
    eof, err

'\n'                        → newline
"use"                       → kw_use
"let"                       → kw_let
'='                         → eq
'.'                         → dot
[0-9]+                      → number
[a-z_]+                     → ident
.                           → err

@parser

@schema
    file        ...items
    use         name:leaf
    let         name:leaf value
    name        id:leaf
    num         value:leaf
    get         object field:leaf

@repair
    holes       IDENT
    terminator  NEWLINE

@highlight
    language            "Pieces"
    scope-name          source.pieces
    extensions          pcs
    keyword             "use" "let"
    operator            "=" "."
    constant.numeric    NUMBER
    invalid             ERR

@lsp
    scope       file unordered
    define      use.name        module
    define      let.name        variable  value:value
    use         IDENT
    import      use.name        file "{}.pcs"
    member      get.field       of:object

file!  = lines                                      → (file ...1)

lines  = line                                       → (1)
       | lines NEWLINE line                         → (...1 3)

line   = KW_USE IDENT                               → (use 2)
       | KW_LET IDENT "=" expr                      → (let 2 4)
       |                                            → _

expr   = IDENT                                      → (name 1)
       | NUMBER                                     → (num 1)
       | expr "." IDENT                             → (get 1 3)
```

With two files open, the server answers across them: definition and
hover of a member in the other file, its references in both, the
members after `.`, and a rename of both:

```session
initialize quiet
open sizes.pcs
| let small = 1
| let large = 9
open main.pcs
| use sizes
| let s = sizes
| let a = sizes.small
| let b = s.large
| let c = s.
definition main.pcs 3:16
definition main.pcs 4:12
references main.pcs 3:16
completion main.pcs 5:11
rename main.pcs 3:16 tiny
rename main.pcs 3:16 large
```

```out
> initialize quiet
> open sizes.pcs
> open main.pcs
diagnostics main.pcs
  {"message":"expected ident, got newline","range":"5:11-6:1","severity":1,"source":"pieces"}
> definition main.pcs 3:16
sizes.pcs 1:5-1:10
> definition main.pcs 4:12
sizes.pcs 2:5-2:10
> references main.pcs 3:16
  main.pcs 3:15-3:20
  sizes.pcs 1:5-1:10
> completion main.pcs 5:11
  {"kind":6,"label":"small"}
  {"kind":6,"label":"large"}
> rename main.pcs 3:16 tiny
{"changes":{"main.pcs":[{"newText":"tiny","range":"3:15-3:20"}],"sizes.pcs":[{"newText":"tiny","range":"1:5-1:10"}]}}
> rename main.pcs 3:16 large
error -32803 'large' would capture the use of 'large' on line 4 of main.pcs
```

The second `let` names `sizes` by `s`, so `s.large` is a member of the
file too; after `s.` completion offers the file's names, alone, though
the line does not parse yet. Renaming `small` to `large` is refused:
`s.large` would name the renamed one.

### Qualified and nominal names

In Rounds, a file is a routine of labels: `do add^math` calls the label
`add` of math.rnd, `do add` a label of the same routine, and `$count` is
a global, one name in every routine:

```grammar rounds.grammar
@lexer

tokens
    ident, global, number, newline, kw_do, kw_set, caret, colon, eq
    eof, err

'\n'                        → newline
"do"                        → kw_do
"set"                       → kw_set
'^'                         → caret
':'                         → colon
'='                         → eq
'$' [a-z]+                  → global
[0-9]+                      → number
[a-z]+                      → ident
.                           → err

@parser

@schema
    routine     ...lines
    label       name:leaf
    do          label:leaf? routine:leaf?
    set         target:leaf value:leaf

@highlight
    language            "Rounds"
    scope-name          source.rounds
    extensions          rnd
    keyword             "do" "set"
    operator            "=" "^"
    invalid             ERR

@lsp
    scope       routine unordered
    define      label.name      function
    use         IDENT
    import      do.routine      file "{}.rnd"
    qualify     do.label        in:routine
    nominal     GLOBAL          ns:globals

routine! = lines                                    → (routine ...1)

lines    = line                                     → (1)
         | lines NEWLINE line                       → (...1 3)

line     = IDENT ":"                                → (label 1)
         | KW_DO IDENT                              → (do 2 _)
         | KW_DO IDENT "^" IDENT                    → (do 2 4)
         | KW_SET GLOBAL "=" NUMBER                 → (set 2 4)
         |                                          → _
```

```session
initialize quiet
open math.rnd
| add:
| set $count = 1
open main.rnd
| start:
| do add^math
| do start
| set $count = 2
definition main.rnd 2:5
definition main.rnd 2:9
definition main.rnd 3:5
references main.rnd 2:5
references main.rnd 4:6
definition main.rnd 4:6
rename main.rnd 4:6 $total
```

```out
> initialize quiet
> open math.rnd
> open main.rnd
> definition main.rnd 2:5
math.rnd 1:1-1:4
> definition main.rnd 2:9
math.rnd 1:1-1:1
> definition main.rnd 3:5
main.rnd 1:1-1:6
> references main.rnd 2:5
  main.rnd 2:4-2:7
  math.rnd 1:1-1:4
> references main.rnd 4:6
  main.rnd 4:5-4:11
  math.rnd 2:5-2:11
> definition main.rnd 4:6
null
> rename main.rnd 4:6 $total
{"changes":{"main.rnd":[{"newText":"$total","range":"4:5-4:11"}],"math.rnd":[{"newText":"$total","range":"2:5-2:11"}]}}
```

The routine's name in `do add^math` goes to its file, and `do start`,
without one, is a label of the routine itself. A global has no
definition; its names are its references, and a rename renames them
all.

### Assignment, colours and words

In Counts an assignment binds its name: `n = 1` defines `n` unless an
`n` is in sight, which it then assigns. A `def`'s name is a function and
its parameters parameters, coloured so where they are defined
(`declaration`) and wherever they are named; the `!` that ends a `force`
node is a modifier, and the `loop` that starts a loop a keyword. `loop`
is a keyword only where it starts a line, which the lang Lexer decides,
so the grammar names it a completion word:

```grammar counts.grammar
@lang = "counts"

@lexer

tokens
    ident, number, newline, kw_def, kw_loop, assign, plus, bang
    lparen, rparen, lbrace, rbrace, comma
    eof, err

'\n'                        → newline
"def"                       → kw_def
'='                         → assign
'+'                         → plus
'!'                         → bang
'('                         → lparen
')'                         → rparen
'{'                         → lbrace
'}'                         → rbrace
','                         → comma
[0-9]+                      → number
[a-z_]+                     → ident
.                           → err

@parser

@schema
    file        ...stmts
    def         name:leaf params:params body:block
    params      ...names:leaf
    block       ...stmts
    assign      target:leaf value
    loop        body:block
    name        id:leaf
    num         value:leaf
    add         left right
    force       value
    call        callee ...args

@repair
    holes       IDENT
    terminator  NEWLINE

@highlight
    language            "Counts"
    scope-name          source.counts
    extensions          cnt
    keyword             "def"
    operator            "=" "+" "!"
    punctuation         "(" ")" "{" "}" ","
    constant.numeric    NUMBER
    invalid             ERR

@lsp
    scope       file
    scope       def block
    define      def.name        function  outer
    define      params.names    variable
    bind        assign.target   variable
    use         IDENT
    color       def.name        function  declaration
    color       params.names    variable.parameter  declaration
    color       loop start      keyword
    color       force end       storage.modifier
    words       "loop"

file!  = lines                                      → (file ...1)

lines  = line                                       → (1)
       | lines NEWLINE line                         → (...1 3)

line   = KW_DEF IDENT "(" [L(IDENT)] ")" block      → (def 2 (params ...4) 6)
       | IDENT "=" expr                             → (assign 1 3)
       | KW_LOOP block                              → (loop 2)
       | expr
       |                                            → _

block  = "{" lines "}"                              → (block ...2)

expr   = expr "+" atom                              → (add 1 3)
       | atom

atom   = IDENT                                      → (name 1)
       | NUMBER                                     → (num 1)
       | atom "!"                                   → (force 1)
       | atom "(" [L(expr)] ")"                     → (call 1 ...3)
```

```zig counts.zig
const std = @import("std");
const parser = @import("parser.zig");

/// The generated lexer, but `loop` that starts a line is the keyword.
pub const Lexer = struct {
    base: parser.BaseLexer,
    line_start: bool = true,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }

    pub fn next(self: *Lexer) parser.Token {
        var tok = self.base.next();
        if (tok.cat == .ident and self.line_start and std.mem.eql(u8, self.base.text(tok), "loop")) tok.cat = .kw_loop;
        self.line_start = tok.cat == .newline;
        return tok;
    }
};
```

The first `n` is a definition, which the second assigns; the `n` of
`grow` is its own, and so is the `n` of the loop's block, which line 6
assigns before any `n` of the file is in sight. Completion at the start
of a line offers `loop`, which the lang Lexer reads as the keyword there,
and after `= ` names alone:

```session
initialize quiet
open main.cnt
| def grow(by) {
|     n = by + 1
|     n!
| }
| loop {
|     n = 2
| }
| n = grow(1)
| n = n + 1
| total = n
definition main.cnt 9:1
definition main.cnt 6:5
references main.cnt 8:1
rename main.cnt 2:5 by
completion main.cnt 10:1
completion main.cnt 10:9
tokens main.cnt
```

```out
> initialize quiet
> open main.cnt
> definition main.cnt 9:1
main.cnt 8:1-8:2
> definition main.cnt 6:5
main.cnt 6:5-6:6
> references main.cnt 8:1
  main.cnt 8:1-8:2
  main.cnt 9:1-9:2
  main.cnt 9:5-9:6
  main.cnt 10:9-10:10
> rename main.cnt 2:5 by
error -32803 'by' is in sight on line 2, where the assignment would assign it, not define a name
> completion main.cnt 10:1
  {"kind":6,"label":"n"}
  {"kind":3,"label":"grow"}
  {"kind":14,"label":"def"}
  {"kind":14,"label":"loop"}
> completion main.cnt 10:9
  {"kind":6,"label":"n"}
  {"kind":3,"label":"grow"}
> tokens main.cnt
  1:1 3 keyword
  1:5 4 function declaration
  1:9 1 punctuation
  1:10 2 variableParameter declaration
  1:12 1 punctuation
  1:14 1 punctuation
  2:7 1 operator
  2:9 2 variableParameter
  2:12 1 operator
  2:14 1 constantNumeric
  3:6 1 storageModifier
  4:1 1 punctuation
  5:1 4 keyword
  5:6 1 punctuation
  6:7 1 operator
  6:9 1 constantNumeric
  7:1 1 punctuation
  8:3 1 operator
  8:5 4 function
  8:9 1 punctuation
  8:10 1 constantNumeric
  8:11 1 punctuation
  9:3 1 operator
  9:7 1 operator
  9:9 1 constantNumeric
  10:7 1 operator
```

A use takes its definition's colour without `declaration` and
`definition`, which mark the definition's own leaf; a member, a name of
another file, takes its definition's too. A token no `color` line
colours keeps its `@highlight` scope. A `words` word is offered where
the parser takes it as other than what a name that is no word would be:
the lexer reads the word from where the text before it leaves off,
followed by the text after the cursor, or by a name, since a lang Lexer
may make a keyword of a word only before a name.

### Checks

Every mistake is an error at its word: `@lsp` without `@schema`; an
unknown line, kind, role, token or symbol kind; a role of the side band;
`define` or `skip` on a role that holds no token (a group, a tag, nodes
of kinds); a role of a kind twice in `skip`, or a kind twice in `scope`;
a role every `define` line takes and `skip` names; two `define` lines
with the same conditions; an option twice, `member` with `lexical`, an
option's role that is a rest role or (for `value:` and `type:`) a tag;
`when` on a role that holds no text, or `^KIND` that is never the node's
parent; `outer` on a kind that is no scope and no scope kind holds;
`export:^KIND` that is never the parent; `doc:leading` without a `doc`
line; `doc:ROLE` on a role of nodes; a `use` token of `@trivia`; a
`builtin TOKEN` that no `use` line names; an empty or repeated builtin
name; an `@lsp` without a `define` line; a second `doc` or `undefined`
line; an `import`, `member` or `qualify` line on a role that holds no
token, two `import` lines with the same conditions, an `import` option
other than `when` and `file`, `file` twice, without a string, or with no
`{}` in it; a `member` or `qualify` line without its `of:` or `in:`, or
with another option, one whose role is the name's own, a rest role, a
tag (`of:`) or a role that holds no token (`in:`), a role that is a
member or qualified twice, both, or also defined or skipped by a line
without `when`, and an `in:` role no `import` line names; a `nominal`
token twice, of `@trivia`, a `use` token too, or with an option other
than `ns:NAME` of letters, digits and `_`; a `bind` line on a role that
holds no token, without a symbol kind, with an option other than `when`,
twice with the same conditions, on a role a `define` line takes
wherever the bind's conditions hold, or one a `skip` without `when` also
names; `when ROLE:KIND` with a text, or on a role that never holds a KIND
node; a `color` line without a role or `start` or `end`, on a role that
holds no token, on a `@wrapper` kind (which the grammar's tree never
has), without a scope or with one `@highlight` does not have, with a
modifier LSP does not have, one twice or one after its `when`s, or twice
with the same conditions; a `words` line without words, or with a word
that is not a string, is empty, repeated, not one token of the lexer,
not made of `@highlight`'s word-chars, or one the grammar offers
already.

```grammar steps_bad.grammar rejects
@lexer

tokens
    ident, newline, kw_let, eq, eof, err

'\n'                        → newline
"let"                       → kw_let
'='                         → eq
[a-z]+                      → ident
.                           → err

@parser

@schema
    file        ...items
    let         name:leaf value:name
    name        id:leaf

@lsp
    scope       file unordered
    define      let.value variable
    use         IDENT

file!  = item+                              → (file ...1)
item   = KW_LET IDENT "=" name NEWLINE      → (let 2 4)
name   = IDENT                              → (name 1)
```

```error
steps_bad.grammar:21:17: error: define let.value: the role holds no token, and a definition is a token
```

## Describing a grammar

`nexus --describe grammar [out]` writes the grammar as JSON for other
tools (editor extensions, language servers, documentation): its tokens,
lexer rules, keywords, `@highlight`, `@schema` and `@lsp`, with or
without `@highlight`. It
runs every check generation runs. Keys come in the order below and lists
in the grammar's order, so a grammar gives the same bytes every run;
`format` changes when a key goes or changes its meaning, not when one is
added.

| Key | Value |
|---|---|
| `format` | `1` |
| `nexus` | the version of Nexus |
| `grammar` | the grammar file as given |
| `lang` | `@lang`, or null |
| `tokens` | each token of the `tokens` block: `name`, `terminal` (the parser's symbol id for it, or null when the parser reads no such token) and `display` (its name in syntax errors, or null) |
| `rules` | each lexer rule: `line`, `token` (null for the built-in `skip`), `pattern` (as written; null for a zero-width rule), `regex` (the pattern in a portable PCRE subset over bytes: `(?:…)`, classes with `\xHH`, `{m,n}`), `literal` (the one text it matches, or null), `trail` (its trailing context as a regex, or null), `guards` (`var`, `negated`, `op` (null for a plain test), `value`), `skip`, `hold`, `rewind`, `actions` (`kind` `set`, `inc`, `dec` or `counted`, `var`, and `value` or `char`) |
| `states` | each state variable: `name`, `initial` |
| `after` | the `after` block's actions |
| `keywords` | each `@keywords` group by name: `caseless`, `base`, `entries` sorted by word: `word` (upper-cased when caseless), `min` (the shortest accepted prefix), `id`, `terminal` (null for an alias) and `alias_of` (the aliased terminal, or null) |
| `trivia` | the `@trivia` tokens |
| `highlight` | null, or `language`, `scope_name`, `extensions`, `line_comment`, `block_comment`, `indent`, `dedent` (regexes), `word_chars` (the class as a regex, the default when not given), and `entries`: `line`, `scope`, `literals`, `tokens`, `groups`, `pattern` (as written, or null), `regex`, `captures` (the parts of a pattern with captures: `scope`, `captured`, `regex`), `line_start`, `line_end`, `contexts` (`kind`, `pattern`, `regex`) and `within` |
| `schema` | null, or `kinds`: `name`, `roles` (`name`, `type` as written, `optional`, `rest`), `side`, `wrapper` |
| `lsp` | null, or `@lsp` as read ([Names and scopes](#names-and-scopes)), roles as `kind`, `role` and `rest`, conditions as `when` (`parent`, the parent's kind or null; `role`; `text`, or null for the role's presence), tokens by their names in `tokens`: `scopes` (`kind`, `unordered`), `defines` (the role, `symbol`, `when`, `outer`, `visibility` `both`, `member` or `lexical`, `value` and `type` (a role or null), `doc` (null, `"leading"` or `{"role"}`), `export` (null, `{"role"}` or `{"parent"}`), `detail` (null, `"whole"` or `{"upto"}`)), `uses`, `skips` (the role, `when`), `builtins`, `builtin_tokens`, `doc` (null or `token`, `strip`), `undefined` (null, `"error"` or `"warning"`), `imports` (the role, `when`, `file`), `members` (the role, `of`), `qualifies` (the role, `in`) and `nominals` (`token`, `ns`) |

`./test/run` pins the description of every grammar in the repository
(`test/golden/*.describe.json`).

## Limits

Exceeding a limit is an error, located where the grammar exceeds it
(except the file size).

| Limit | Value | Why |
|---|---:|---|
| grammar file | 1 MiB | read whole into memory |
| a token of the grammar file (a pattern or a literal, say) | 65535 bytes | the frontend's own 8-byte tokens |
| nesting of `( )` and `[ ]` in rules and actions, and of groups in a pattern | 64 | every stage walks the nesting |
| declared tokens | 255 | a token's category is one byte (`skip` is the 256th) |
| `r{n,m}` bounds | 255 | keeps the automaton small |
| distinct guard conditions on rules with a pattern | 10 | one start state per combination (at most 1024) |
| lexer NFA states | 200,000 | bounded repeats expand into copies |
| lexer DFA states during subset construction | 262,140 | stops an exploding DFA before it exhausts memory |
| lexer DFA states after minimization | 65535 | the scanner numbers its states with a `u16` |
| state variable values / `pre` values | -128..127 / 0..255 | `i8` / `u8` |
| `rewind(n)` | 65535, and the rule's shortest match | a token's length is a `u16` |
| elements in one alternative, counting those in its groups and choices at any depth | 65534 | action positions are `u16` |
| alternatives one alternative's `[...]` and choices expand into | 32766 | as below |
| rules of the generated grammar | 32766 | a reduction is a 16-bit table cell |
| symbols of the generated grammar | 65535 | symbol ids are `u16` |
| LR states | 32767 | a shift is a 16-bit table cell |

A generated parser takes input up to 4 GiB (positions are `u32`;
`error.InputTooLarge` beyond) and tokens up to 65535 bytes (a longer match
is an `err` token), or of any length with [`@longtokens`](#long-tokens).
An `@as` keyword's `GId` value may be any `u16`.

## Errors

Every generation error is `file:line:col: error: message`, generation stops
with exit status 1, and no output file is written. A few that grammars meet
early:

| Message (abridged) | Cause |
|---|---|
| `the tokens block must declare 'eof'` | the `tokens` block lacks `eof` or `err` |
| `token 'x' is not declared in the tokens block` | a lexer rule names an undeclared token |
| `this rule can never match: ... goes to the rule on line N` | an earlier rule shadows it |
| `this rule can never match: whenever its guards hold, the zero-width rule on line N fires first` | a zero-width rule shadows it |
| `this pattern matches the empty string` | use `+` rather than `*`, or a zero-width rule |
| `undefined rule 'x'` / `undefined token 'X'` | a name nothing defines |
| `rule 'x' is unreachable: no start symbol reaches it` | a rule no start symbol uses, directly or through other rules |
| ``@infix is unused: no rule names `@infix` `` | an `@infix` table without the `@infix` element |
| `duplicate @schema` | a directive written twice |
| `the literal "x" is no token` | no lexer rule's pattern is exactly `x` (and no `@op` maps it) |
| `"+" and PLUS are the same token` | one token written both ways |
| `` `...2` spreads a list, but element 2 (IDENT) is a token `` | write `2` |
| `rule x derives no finite input` | every alternative needs a rule that never completes |
| `the grammar is cyclic (a ⇒ b ⇒ a)` | a rule derives itself; the grammar has infinitely many parses of some input |
| `undeclared conflict: ...` / `declared conflict no longer occurs: ...` / `conflict count changed` | see [Conflicts](#conflicts-and-hints) |
| `position 5 is past the end of the pattern (2 elements)` | an action refers to a missing element |
| `X ":" on name ... has no effect` | a hint that decides nothing |
| `X "(" on expr → ... names no token` | no lexer rule's pattern is exactly that text, and no `@op` maps it |
| `X "(" on expr → ... names no terminal` | the parser grammar uses no token the lexer gives that text |
| `X "(" on expr → ... is ambiguous` | lexer rules in different states, or under different guards, make that text two terminals of the grammar |
| `X "(" on expr → ... names the terminal "["` | the grammar writes that token as another literal |
| `X "[" on expr → ... names OPEN, as X "(" does` | two hints of one alternative name one terminal |
| `X "%" on expr → ... the token @as promotes` | a hint names the promotable token |
| ``keywords `HA[LT]` and `H[ANG]` (3:9) both accept `HA` `` | two `@keywords` entries of a group accept one word |
| `this example is not a syntax error: the parser takes its last token` | an `@messages` example the parser accepts ([Messages](#messages)) |

`nexus check grammar` runs every check generation runs, and writes
nothing; `nexus check --messages grammar` also writes the coverage of
`@messages` on standard output ([Messages](#messages)).

