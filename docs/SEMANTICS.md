# The semantic layer

A grammar with an `@schema` declares the tree it builds: every node kind and,
for each kind, its children by name and type. Nexus checks every action
against that declaration when it generates the parser, builds every node
with a fixed number of slots, records a source span for every node, and
generates the accessors a compiler reads the tree with. The shape of the
tree stops being a convention between the grammar and its consumers and
becomes a checked contract.

Everything here is opt-in per grammar; a grammar without `@schema` works as
described in [GRAMMAR.md](GRAMMAR.md). As there, every example with a file
name is generated, compiled and run by `./test/run`, and every `zig test`
block runs against that example's generated parser.

Contents: [An example](#an-example) · [The generated API](#the-generated-api) ·
[@schema](#schema) · [Role-named actions](#role-named-actions) ·
[Labels](#labels) · [What generation checks](#what-generation-checks) ·
[Spans and node ids](#spans-and-node-ids) ·
[Facts](#facts) · [Trivia](#trivia) · [Syntax errors](#syntax-errors) ·
[Tolerant parsing](#tolerant-parsing) · [Lang wrappers](#lang-wrappers) ·
[Without a schema](#without-a-schema) · [Lineage: Solar](#lineage-solar)

## An example

```grammar stmt.grammar
@lexer

tokens
    ident, number, newline, comment
    kw_let, kw_if, kw_unless, kw_then, kw_else
    eq, plus_eq, minus_eq, colon, comma, plus, minus, star, lparen, rparen
    eof, err

'#' [^\n]*                  → comment
'\n'                        → newline
"let"                       → kw_let
"if"                        → kw_if
"unless"                    → kw_unless
"then"                      → kw_then
"else"                      → kw_else
"+="                        → plus_eq
"-="                        → minus_eq
'='                         → eq
':'                         → colon
','                         → comma
'+'                         → plus
'-'                         → minus
'*'                         → star
'('                         → lparen
')'                         → rparen
[0-9]+                      → number
[a-z_]+                     → ident
.                           → err

@parser

@schema
    module     ...stmts
    let        name:leaf type:name? value | eq
    set        op:tag("+="|"-=")? target:name value
    if         kw:leaf cond then else?
    call       callee:leaf ...args
    "+", "-"   left right
    "*"        left right
    neg        value:num
    num        value:leaf
    name       id:leaf
    note       text:leaf @wrapper

@display
    IDENT: "a name", NEWLINE: "end of line"

@errors
    expr: "an expression"

@trivia COMMENT

@repair
    holes       IDENT
    terminator  NEWLINE

program! = body                                 → (module ...1)

body     = stmt                                 → (1)
         | body NEWLINE stmt                    → (...1 3)
         | body NEWLINE                         → 1

stmt     = KW_LET name:IDENT [":" type:name] eq:"=" value:expr
                                                → (let)
         | target:name "=" value:expr           → (set)
         | target:name op:("+=" | "-=") value:expr
                                                → (set)
         | (KW_IF | KW_UNLESS):kw cond:expr KW_THEN then:stmt [KW_ELSE else:stmt]
                                             >  → (if)
         | callee:IDENT "(" [args:L(expr)] ")"  → (call)

name     = IDENT                                → (name 1)

expr     = @infix

atom     = name
         | NUMBER                               → (num 1)
         | "-" NUMBER                           → (neg value:(num 2))
         | "(" expr ")"                         → 2

@infix atom
    "+" left, "-" left
    "*" left
```

```input
let x : t = 1 + 2 * 3   # seven
x += -4
if x then f(x, 1) else unless y then g()
```

```tree
(module
  (let
    `x`
    (name `t`)@8..9
    (+ (num `1`)@12..13 (* (num `2`)@16..17 (num `3`)@20..21)@16..21)@12..21)@0..21
  (set += (name `x`)@32..33 (neg (num `4`)@38..39)@37..39)@32..39
  (if
    `if`
    (name `x`)@43..44
    (call `f` (name `x`)@52..53 (num `1`)@55..56)@50..57
    (if `unless` (name `y`)@70..71 (call `g`)@77..80 _)@63..80)@40..80)@0..81
```

Every list prints its span (`@start..end`, byte offsets). Leaves carry their
own position. Every `if` has four slots and every `set` three, whether or
not the optional parts were written: `_` fills an empty slot.

## The generated API

A consumer of the example above reads the tree by role; nothing depends on
positions:

```zig test
const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");
const ir = parser.ir;
const Sexp = parser.Sexp;

const source = "let x : t = 1 + 2 * 3   # seven\nx += -4\n";

test "read the tree by role" {
    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();

    const stmts = ir.Module.stmts(tree); // or ir.rest(tree, .stmts)
    try testing.expectEqual(2, stmts.len);

    const let = stmts[0];
    try testing.expect(let.isKind(.let));
    try testing.expectEqualStrings("x", ir.Let.name(let).getText(source));
    const sum = ir.get(let, .value); // the slot, looked up by the node's kind
    try testing.expect(sum.isKind(.@"+"));
    try testing.expect(ir.@"+".right(sum).isKind(.@"*"));

    const set = stmts[1];
    try testing.expectEqual(parser.Tag.@"+=", ir.Set.op(set).tag);
    try testing.expect(ir.Neg.value(ir.Set.value(set)).isKind(.num));

    // Slots are fixed: a `let` has its name, type and value, always.
    try testing.expectEqual(4, let.items().len);
    try testing.expect(ir.has(.let, .type) and !ir.has(.let, .op));
}

test "spans, rules, side-band roles" {
    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const let = ir.Module.stmts(tree)[0];

    const span = p.span(ir.Let.value(let));
    try testing.expectEqualStrings("1 + 2 * 3", source[span.start..span.end]);
    try testing.expect(p.ruleOf(let) != null);
    try testing.expect(let.list.id >= 1 and let.list.id <= p.nodeCount());

    const eq = p.sideRole(let, .eq).?; // recorded, not in the tree
    try testing.expectEqualStrings("=", source[eq.start..eq.end]);
}

test "facts" {
    var p = parser.Parser.init(testing.allocator, "x += 1");
    defer p.deinit();
    const tree = try p.parseProgram();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try p.writeFacts(&out.writer, tree);
    try testing.expectEqualStrings(
        \\(node 4 module 0 6)
        \\(role 4 stmts 3)
        \\(node 3 set 0 6)
        \\(role 3 op tag +=)
        \\(role 3 target 1)
        \\(role 3 value 2)
        \\(node 1 name 0 1)
        \\(role 1 id leaf 0 1)
        \\(node 2 num 5 6)
        \\(role 2 value leaf 5 1)
        \\
    , out.written());
}

test "trivia" {
    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    _ = try p.parseProgram();
    const comment = p.trivia()[0];
    try testing.expectEqualStrings("# seven", source[comment.pos..][0..comment.len]);
}

test "syntax errors name what was expected" {
    var p = parser.Parser.init(testing.allocator, "let x = \n");
    defer p.deinit();
    try testing.expectError(error.ParseError, p.parseProgram());
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try p.writeError(&w);
    try testing.expectEqualStrings("1:9: expected an expression, got end of line", w.buffered());
}

test "tolerant parsing" {
    const text = "let x = \ny = 2 z = 3\n";
    var p = parser.Parser.init(testing.allocator, text);
    defer p.deinit();
    const r = try p.parseTolerant(.program, 8);
    try testing.expect(r.complete);
    try testing.expectEqual(2, r.insertions); // a hole after `=`, a newline before `z`
    try testing.expectEqual(parser.TokenCat.newline, r.failure.?.cat);
    const stmts = ir.Module.stmts(r.sexp);
    try testing.expectEqual(3, stmts.len);
    const hole = ir.Name.id(ir.Let.value(stmts[0]));
    try testing.expectEqual(0, hole.src.len);
}

test "a wrapper builds an @wrapper node" {
    var p = parser.Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const name = ir.Let.name(ir.Module.stmts(tree)[0]);

    var children: [ir.width(.note) - 1]Sexp = @splat(.nil);
    children[ir.slot(.note, .text) - 1] = name;
    const note = try p.newNode(.note, &children, .{ .start = 0, .end = 5 });
    try testing.expectEqualStrings("x", ir.Note.text(note).getText(source));
    try testing.expectEqual(null, p.ruleOf(note));
}
```

The module exports:

| Name | What |
|---|---|
| `Tag`, `Role`, `Start` | the kinds and tags, the role names, the start symbols |
| `Sexp` | `nil`, `tag`, `src` (`pos`, `len`, `id`), `str`, `list` (`items()`, `id`); 24 bytes. `kind()`, `isKind(t)`, `items()`, `getText(source)`, `write(source, w)`, `listOf(items)` |
| `ir.get(node, role)` | a slot by role name (nil when empty) |
| `ir.rest(node, role)` | a rest role's children |
| `ir.has(kind, role)` | whether a kind has a role |
| `ir.slot(kind, role)`, `ir.restSlot(kind, role)`, `ir.width(kind)` | compile-time slot numbers (the head is slot 0) and the fixed width |
| `ir.Let.name(node)` ... | per-kind views, one function per role (`ir.@"+".left` for quoted kinds) |
| `Parser` | the lang module's `Parser` wrapper, or `BaseParser` |
| `parseProgram(allocator, source)` | per start symbol: a new parser and its tree; `deinit()` the parser when done |

`BaseParser` methods: `init`, `deinit`, `parse<Start>()`, `parse(start)`,
`parseTolerant(start, budget)`, `span(sexp)`, `ruleOf(sexp)`, `nodeCount()`,
`sideRole(sexp, role)`, `newNode(tag, children, span)`, `newList(items, span)`,
`writeFacts(w, root)`, `trivia()`, `lastError()`, `writeError(w)`,
`printError()`, `lineCol(pos)`, `expected(state)`, `symbolText(symbol)`.

`ir.get` and `ir.rest` look the slot up by the node's kind at run time;
asking for a role the kind lacks panics in safety-checked builds (and names
the kind and the role). The per-kind views and `ir.slot` resolve at compile
time, so a misspelled role is a compile error.

## @schema

```text
@schema
    kind[, kind ...]   role role ...  [| side side ...]  [@wrapper]
```

One line per kind (or per group of kinds with the same roles). Kinds that
are not identifiers are quoted (`"+"`). Roles are listed in slot order:

| Role | Meaning |
|---|---|
| `name` | a child of any value except nil and untagged lists |
| `name:type` | a child of that type |
| `name?` `name:type?` | may be nil |
| `...name` `...name:type` | the remaining children (zero or more); last |
| `\| a b` | side-band roles: recorded with a span, not placed in the tree |
| `@wrapper` | built by a lang `Parser` wrapper, not by any rule |

| Type | Values |
|---|---|
| `leaf` | a token |
| `node` | a leaf or a node of any kind |
| `tag` | a marker tag; its values join the `Tag` enum as actions use them |
| `tag(a\|b)` | one of these tags (quote non-identifiers: `tag("+="\|"-=")`) |
| `group` | an untagged list (a parameter list, say) |
| `k1\|k2` | a node of one of these kinds |

The generated `Tag` enum lists the kinds in declaration order, then the
`tag(...)` values, then the `@tags` names, then marker values used in
untyped `tag` roles. It has no catch-all, so a misspelled tag is a
generation error, not a new tag. `@tags a b` adds tags only a lang wrapper
uses. The `Role` enum lists every role name.

## Role-named actions

In schema mode an action's list is a node of the kind at its head, and its
items fill roles. Positional items fill slots in order; `role:v` items fill
roles by name (positional items come first); what is not filled is nil,
which a required role rejects.

| Item | Fills the role with |
|---|---|
| `N` / `role:N` | element N |
| `role:...N` | the items of element N (a rest role only) |
| `role:_` | nil |
| `role:word` | the tag `word` (`op:+=`, `mode:ptr`) |
| `role:(kind ...)` | a nested node, with its own id and span |

```grammar fragment
stmt = name "+=" expr                → (set += 1 value:3)
     | LET IDENT "+=" expr           → (set op:+= target:(name 2) value:4)
     | RETURN [expr]                 → (return value:2)
```

Lists without a kind (`(1)`, `(...1 3)`) remain the way to accumulate
children for a rest role (plumbing); a spread must splice a list.

## Labels

`role:element` in a pattern labels an element. When the action builds a
kind with that role, the labeled value fills it, so most actions need no
positions at all (`→ (let)` above).

- A label on an optional element (`[":" type:name]`) gives nil when the
  element is absent; on a list (`args:[L(expr)]`) the items fill a rest role.
- A label on a choice, `(A | B):role` or `role:(A | B)`, labels whichever
  alternative matched. When the role is a `tag` role and every alternative
  is a literal, the tag is the matched literal's text: `op:("+=" | "-=")`
  gives the tag `+=` or `-=`.
- A label naming a side-band role (`eq:"="` for `let ... | eq`) records the
  element's span in the role store: `parser.sideRole(node, .eq)`.
- `_:X` drops a value on purpose (as does `!X`).

A label that is neither a role nor a side-band role of the kind the action
builds is an error, and so is a label on an alternative that builds no
schema node. Labels inside a `( ... )` group are not supported.

## What generation checks

In schema mode generation fails, with every problem of a phase reported at
its rule, when:

- **Inventory.** An action builds a kind `@schema` does not declare, uses a
  tag no kind, `tag(...)` or `@tags` declares, or a declared kind (not
  `@wrapper`) is built by no rule. The report ends with the actions' actual
  inventory as an `@schema` block, ready to paste and edit.
- **Roles.** A role is unknown, filled twice, given a spread when it takes
  one value, or required and left empty; a positional item follows a named
  one; an action gives more items than the kind has slots; a tag is not
  one of its role's `tag(...)` values.
- **Coverage.** Every value-bearing element of a pattern is used by the
  action, labeled, or dropped with `!X` or `_:X`; an alternative opts out
  with `→ (...)  ~ "reason"`. Value-bearing are rules, lists, groups, the
  `@as` token and its keywords, and tokens whose text varies (a lexer rule
  produces them from a pattern that is not a single literal). Literals,
  fixed-text tokens, and tokens only a lang wrapper produces carry no value.
- **Types.** The generator computes, by fixpoint over the expanded grammar,
  the set of values every rule can produce (nil, leaf, tag, untagged list,
  and each kind) and checks every role against its declared type. The
  error names the rule that produces the offending value.

```grammar typed.grammar rejects
@lexer

tokens
    ident, number, eq, lparen, rparen, eof, err

'\n'                        → skip, skip
'='                         → eq
'('                         → lparen
')'                         → rparen
[0-9]+                      → number
[a-z]+                      → ident
.                           → err

@parser

@schema
    module     ...stmts
    set        target:name value
    call       callee args?
    name       id:leaf
    num        value:leaf

program! = stmt+                                → (module ...1)

stmt     = target:expr "=" value:expr           → (set)

expr     = IDENT                                → (name 1)
         | NUMBER                               → (num 1)
         | expr "(" expr ")"                    → (call 1 3)
```

```error
typed.grammar:25:12: error: rule 'stmt': role 'target' of 'set' takes name, but element 1 (expr) can be a 'call' node, a 'num' node (from expr → expr "(" expr ")", line 29)
```

A coverage failure, and a required role left empty:

```grammar covered.grammar rejects
@lexer

tokens
    ident, number, eq, eof, err

'\n'                        → skip, skip
'='                         → eq
[0-9]+                      → number
[a-z]+                      → ident
.                           → err

@parser

@schema
    module     ...stmts
    set        target:name value
    name       id:leaf
    num        value:leaf

program! = stmt+                                → (module ...1)

stmt     = name "=" value                       → (set 1)

name     = IDENT                                → (name 1)
value    = NUMBER                               → (num 1)
```

```error
covered.grammar:22:12: error: rule 'stmt': required role 'value' of 'set' is not filled
covered.grammar:22:12: error: rule 'stmt': element 3 (value) carries a value the action does not use; use it, label it, or drop it with !X or _:X (or opt out with ~ "reason")
```

An undeclared kind prints the inventory:

```grammar inventory.grammar rejects
@lexer

tokens
    ident, number, eq, eof, err

'\n'                        → skip, skip
'='                         → eq
[0-9]+                      → number
[a-z]+                      → ident
.                           → err

@parser

@schema
    module     ...stmts
    name       id:leaf

program! = stmt+                                → (module ...1)

stmt     = name "=" NUMBER                      → (assign 1 value:3)

name     = IDENT                                → (name 1)
```

```error
inventory.grammar:20:12: error: rule 'stmt': undeclared kind 'assign' (the action builds it; @schema does not declare it)
the actions' inventory, ready to paste:
@schema
    module ...stmts
    name id:leaf
    assign r1 value
```

## Spans and node ids

Every list the parser builds for the tree gets a node id (dense, from 1 per
parse) and an entry in the node store: its span and the rule that built it.

- A node spans its reduction: from its first token to its last, including
  tokens that are not in the tree (keywords, punctuation). `(1 + 2)` passed
  through by `→ 2` keeps the span of the `+` node inside it.
- A nested node (`value:(num 2)`) spans the elements it references.
- A leaf spans its token. A list without an id (built by a wrapper with
  `List.of`) spans the hull of its children.
- Untagged lists that are only ever spliced into another list (the insides
  of `L(X)`, left-recursive accumulators) get no id: nothing can reach them.

The store costs one 12-byte entry per node: about 3% of parse time on Rig
and 5% on MUMPS (see `test/bench/BASELINE.md`). Grammars without `@schema`
get it with `nexus --spans`.

## Facts

`writeFacts(w, root)` writes the tree as flat s-expression facts in
pre-order, for tools that want relations rather than a tree:

```text
(node ID KIND START END)      every list with a node id
(role ID ROLE CHILD ...)      each non-nil child; a rest role lists all of its children
(side ID ROLE START LEN)      each side-band role
```

A child is a node id, `leaf POS LEN`, `tag NAME`, `str "TEXT"`, or `(...)`
for a list without an id. An untagged list's KIND is `group`, and its roles
are child indexes.

## Trivia

Tokens listed in `@trivia` never reach the parser; `parser.trivia()` returns
them in source order, with positions, for formatters and documentation
tools. A rule may not use a trivia token.

## Syntax errors

A failed parse returns `error.ParseError`; `lastError()` gives the
offending token's span, category and state, and `writeError(w)` writes
`line:col: expected X, Y or Z, got W`. The expected set is computed per
state at generation time: the `@errors`-named rules the state is waiting
for, then the tokens none of them can begin with. Tokens print with their
`@display` names, else as their literal or their name in lower case.

## Tolerant parsing

A grammar with `@repair` gets `parseTolerant(start, budget)`, a second
driver for editors: it parses past errors and returns `Tolerant` (`sexp`,
`failure`, `repairs`, `insertions`, `deletions`, `complete`). Strict parsing
is unaffected. The rules:

1. The first error is recorded exactly as a strict parse reports it; a
   repaired parse still returns it.
2. Only tokens the grammar declares in `@repair` are inserted, zero-width,
   from a per-state candidate list computed at generation time: holes
   first, then fewer further insertions needed to finish the construct,
   then symbol order.
3. In front of real input only a `terminator` may be inserted (a
   statement boundary never invents meaning); at end of input or before a
   `structure` token any candidate may.
4. An insertion must let the offending token be consumed. At end of input
   or before structure, a shiftable candidate may be inserted anyway, never
   twice in the same configuration, so several insertions can complete an
   unfinished construct.
5. With no admissible insertion the offending token is deleted; end of
   input is never deleted.
6. At most `budget` repairs; then the parse stops, incomplete.

## Lang wrappers

A lang `Parser` wrapper may rewrite the tree (the generated `Parser` alias
picks it up when the lang module declares one). With a schema it builds
nodes through the same contract: `newNode(.kind, children, span)` gives a
node an id and a span, `ir.slot`/`ir.width` place its children at compile
time, `List.withId(items, id)` keeps an id (and so the span) on a rewritten
node, and `@wrapper` declares kinds that only the wrapper builds. The
wrapper is returned by value from `parseX(allocator, source)`, so it must
be movable.

## Without a schema

A grammar without `@schema` builds the same `Sexp` trees from the same
actions, with these differences: lists drop trailing nils (positions of
what is present stay stable); `role:v` items are positional; labels other
than `_:X` are errors; the `Tag` enum comes from the lang module (or from the actions,
plus a `_` catch-all, without `@lang`); there is no `ir`; spans and facts
need `--spans`. This is how the 0.10 grammars run on 1.0 unchanged in shape
([PORTING.md](PORTING.md)).

## Lineage: Solar

The semantic layer follows ideas from Solar, the LALR(1) generator of
Rip (`src/grammar/solar.rip` in the Rip repository), which
annotates each rule with a kind and one part per action element, keeps node
and role stores beside the tree, labels pattern symbols the action drops,
gates annotation coverage with `~ reason` opt-outs, and repairs editor
buffers from a generated table with the same rules as
[Tolerant parsing](#tolerant-parsing) above.

What Nexus adopted: node kinds and named roles, side-band roles and pattern
labels, spans in a node store, the coverage gate and its opt-out, the
repair table and the tolerant driver's rules (first error kept, only
terminators before real input, deletion as the fallback, a budget), and a
trivia channel.

What is different in Nexus:

- **The schema shapes the tree.** Solar's annotations describe positions
  and never change the parser's output; Nexus declares each kind once, and
  the generator places every role in a fixed slot, so the tree and the
  schema cannot disagree.
- **Types.** Roles have types, and a fixpoint over the grammar proves every
  role's value has its type at generation time.
- **Coverage per value.** Solar requires every constructor rule to be
  annotated; Nexus requires every value-bearing element to be used,
  labeled or dropped, so no value is discarded by accident.
- **Declared repair alphabet.** Solar's fabricable tokens are
  conventional names (`IDENTIFIER`, `TERMINATOR`, `INDENT`, ...); Nexus
  grammars declare theirs in `@repair`.
- **Zig, without side maps.** Node ids live in the list itself (the
  24-byte `Sexp` has room), the node store is chunked arrays, spans are byte
  offsets, and the accessors are generated Zig resolved at compile time
  where possible. Trivia is filtered by the parser from declared tokens.
- **Facts.** `writeFacts` exports the tree as relations.
