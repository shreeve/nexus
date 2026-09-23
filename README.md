<p align="center">
  <img src="docs/nexus-logo-720w.png" alt="Nexus Logo" width="400">
</p>

<div align="center">
  <strong>One grammar file in. One standalone Zig module out: a DFA lexer, an LALR(1) parser, and a verified semantic layer.</strong>
</div>

# Nexus

Nexus is a parser generator for language tools written in Zig. You write one
`.grammar` file: the tokens as regular expressions, the syntax as LALR(1)
rules, and next to each rule the tree it builds. Nexus writes one Zig file
you can vendor: no runtime library, no allocation while lexing, the same
bytes on every run.

With an `@schema`, the grammar also declares that tree: every node kind and
its children by name and type. Nexus then proves, when it generates the
parser, that every rule builds nodes of the declared shape, and generates
the accessors, source spans, and error messages a compiler or an editor
needs. The grammar becomes the one place that says what the syntax is and
what it means.

If you know yacc, Bison, or tree-sitter: Nexus is a yacc with a real lexer
generator in the same file, S-expression actions instead of C code, a
declared conflict manifest instead of `%expect`, and a typed tree with
spans and tolerant parsing, in one Zig module.

## A short tour

`calc.grammar`:

```grammar calc.grammar
@lexer

tokens
    ident, number, let
    eq, plus, minus, star, slash, lparen, rparen
    newline, comment, eof, err

'#' [^\n]*                 → comment
'\n'                       → newline
'='                        → eq
'+'                        → plus
'-'                        → minus
'*'                        → star
'/'                        → slash
'('                        → lparen
')'                        → rparen
[0-9]+                     → number
"let"                      → let
[a-zA-Z_][a-zA-Z0-9_]*     → ident
.                          → err

@parser

@schema
    program    ...stmts
    let        name:leaf value
    "+", "-"   left right
    "*", "/"   left right
    neg        value
    num        value:leaf
    var        name:leaf

@trivia COMMENT

program! = stmts                            → (program ...1)

stmts    = stmt                             → (1)
         | stmts NEWLINE stmt               → (...1 3)
         | stmts NEWLINE                    → 1

stmt     = LET name:IDENT "=" value:expr    → (let)
         | expr

expr     = @infix

atom     = NUMBER                           → (num 1)
         | IDENT                            → (var 1)
         | "-" value:atom                   → (neg)
         | "(" expr ")"                     → 2

@infix atom
    "+" left, "-" left
    "*" left, "/" left
```

Generate the parser:

```bash
nexus calc.grammar src/parser.zig
```

This input:

```input
let x = 1 + 2 * 3   # seven
x - -1
```

parses to this tree (spans omitted):

```tree no-spans
(program (let `x` (+ (num `1`) (* (num `2`) (num `3`)))) (- (var `x`) (neg (num `1`))))
```

and a compiler reads it by role, never by position:

```zig test
const std = @import("std");
const parser = @import("parser.zig"); // the generated module
const ir = parser.ir;

test "tour" {
    const source = "let x = 1 + 2 * 3   # seven\nx - -1\n";
    var p = parser.Parser.init(std.testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();

    const let = ir.Program.stmts(tree)[0];
    try std.testing.expectEqualStrings("x", ir.Let.name(let).getText(source));

    const sum = ir.Let.value(let);
    try std.testing.expect(ir.@"+".right(sum).isKind(.@"*"));

    const span = p.span(sum); // every node has a source span
    try std.testing.expectEqualStrings("1 + 2 * 3", source[span.start..span.end]);

    const comment = p.trivia()[0]; // comments are kept aside, with positions
    try std.testing.expectEqualStrings("# seven", source[comment.pos..][0..comment.len]);
}
```

Had an action built a node the schema does not allow (a `num` where a role
takes a `var`, a kind nobody declared, a value dropped by accident),
generation would have failed with `file:line:col: error:` naming the rule.

## Features

- **One file, one module.** Lexer, parser, tables, tree types, accessors,
  in a single generated Zig file. Deterministic, byte for byte.
- **A real lexer generator.** Patterns compile through an NFA to one
  minimized DFA, emitted as direct-coded Zig (a `switch` per state), with
  longest match, lexer states and guards, trailing context (`r1 / r2`),
  zero-width tokens, and SIMD scanning of long runs. Tokens are 8 bytes and
  zero-copy.
- **LALR(1)** with DeRemer–Pennello lookaheads (SLR(1) with `--slr`), and
  every remaining conflict declared in an `@conflicts` manifest, with a
  reason; any change fails generation and prints the conflict, its state,
  an example input, and the new manifest.
- **Actions next to rules.** `→ (set 1 3)` is the tree. Optional groups
  keep positions stable; lists (`L(X)`, `X*`, `[X ...]`), choices,
  operator-precedence chains (`@infix`), contextual keywords (`@as`).
- **A verified semantic layer** (`@schema`): fixed-length nodes, named
  roles, labels in patterns, a coverage gate that no value is dropped by
  accident, static result types checked by fixpoint, generated `Tag`/`Role`
  enums and `ir` accessors, spans and node ids, side-band roles, and a facts
  export. See [SEMANTICS.md](docs/SEMANTICS.md).
- **For editors.** Syntax errors name what was expected (`expected an
  expression or ")", got end of line`), trivia is kept with positions, and
  `parseTolerant` repairs a broken buffer from a table the generator
  computes.
- **Extensible in Zig.** A language module can wrap the generated lexer
  (layout, keyword classification) and parser (tree rewrites).
- **Self-hosted.** Nexus parses grammar files with a parser Nexus generates
  from [`nexus.grammar`](nexus.grammar), itself written in schema mode.
- **Located errors.** A mistake in a grammar is reported as
  `file:line:col: error:` and generation fails; the few gaps left are
  failing tests in `test/known/`, listed in
  [GRAMMAR.md](docs/GRAMMAR.md#known-limitations).

## Validated languages

The grammars in `test/` generate with this checkout, compile, and parse
their cases in `./test/run`, trees compared with goldens. Rig's schema-mode
grammar lives in the Rig repository (its `nexus-1.0` branch). Sizes are
from Nexus 1.0.0.

| Language | Grammar | Lines | LR states | Declared conflicts | Suite cases | Mode |
|---|---|---:|---:|---:|---:|---|
| Rig | `rig.grammar` (Rig repository) | 711 | 524 | 0 | Rig's suite | schema |
| Rig (0.10 shape) | `test/rig/rig.grammar` | 624 | 530 | 0 | 144 | plain |
| MUMPS | `test/mumps/mumps.grammar` | 909 | 831 | 46 | 62 (+ 6 with `--spans`) | plain |
| Ruby subset | `test/ruby/ruby.grammar` | 773 | 536 | 66 | 7 | plain |
| Zag | `test/zag/zag.grammar` | 511 | 477 | 23 | 5 | plain |
| Slash | `test/slash/slash.grammar` | 385 | 166 | 0 | 7 | plain |
| Nexis (a Clojure reader) | `test/nexis/nexis.grammar` | 196 | 60 | 108 | 27 | plain |
| Nexus grammar files | `nexus.grammar` | 557 | 364 | 0 | 11 + every grammar in the suite | schema |

Beyond the suite, `test/diff` parses all 24,704 VistA routines (86.5 MB)
with the MUMPS parser generated by Nexus 0.10.3 from em's grammar and by
Nexus 1.0 from `test/mumps/mumps.grammar`: every file gives the same tree
or the same parse error. Generating the MUMPS parser takes about 17 ms,
process start included, and it parses VistA at about 50 MB/s, 37% faster
than 0.10.3 ([test/bench/BASELINE.md](test/bench/BASELINE.md)).

## Install

Nexus needs [Zig 0.16](https://ziglang.org/download/).

```bash
git clone https://github.com/shreeve/nexus && cd nexus
zig build -Doptimize=ReleaseSafe      # bin/nexus
./test/run                            # the whole suite
```

```bash
nexus calc.grammar src/parser.zig     # generate (default output: src/parser.zig)
nexus check calc.grammar              # every check, nothing written
nexus --dump-sexp calc.grammar        # the frontend's tree of the grammar file
nexus --help
```

Options: `--spans` (node spans without a schema), `--slr`, `-c` (rules as
comments in the output). Exit status: 0 success, 1 error, 2 usage.

## Documentation

- [docs/GRAMMAR.md](docs/GRAMMAR.md): the grammar file, completely
- [docs/SEMANTICS.md](docs/SEMANTICS.md): schemas, roles, spans, the generated API, tolerant parsing
- [docs/INTERNALS.md](docs/INTERNALS.md): how Nexus works, for contributors
- [docs/PORTING.md](docs/PORTING.md): moving a 0.10 grammar to 1.0
- [CHANGELOG.md](CHANGELOG.md), [AGENTS.md](AGENTS.md), [test/README.md](test/README.md)

Every grammar and Zig example in these documents is generated, compiled and
run by `./test/run`.

## License

MIT
