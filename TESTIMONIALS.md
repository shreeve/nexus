# What Nexus does for Rig

[Rig](https://github.com/shreeve/rig) is a systems language with an
ownership model you can see in the source. Its whole front end is one
Nexus grammar. These are notes from the people and agents who build Rig
on it, about what that grammar buys them day to day.

## One file is the front end

> "`rig.grammar` is the lexer, the parser, and the shape of every tree in
> one place. Nexus turns it into `src/parser.zig`. The syntax and the trees
> the compiler reads can't drift apart, because there's only one place to
> change them."
>
> — the Rig compiler team

Rig keeps the generated parser out of version control; its build
regenerates it whenever the grammar or the Nexus binary changes. Changing
the syntax means changing the grammar and nothing else.

## A grammar change is something you can check, not just hope about

> "When Rig adds syntax, Nexus answers the question every language
> project dreads: *what else did this change?* Its conflict manifest says
> whether the tables are still clean, and diffing the parsed trees of
> Rig's own cases shows exactly which trees moved and how. Adding the
> `called` and `rarely` function markers came down to one optional `mark`
> role on two nodes. The tree diff showed nothing else moved, and no case
> switched between parsing and failing."
>
> — Rig's foreman

Rig's grammar declares no conflicts (see the table in the
[README](README.md#validated-languages), which the suite checks).

## S-expressions keep the meaning visible

> "Rig's first rule for effects is that every sigil stays a named node
> all the way to code generation. Nexus's S-expression trees make that the
> natural shape: `*<x` (move `x` into a shared handle) parses as
> `(share (move x))`. A new meaning for an existing sigil needs no grammar
> change: making `*w` upgrade a weak handle is the type checker looking
> at the `share` node, seeing a weak handle inside, and recording a fact.
> Same tree, new meaning, decided in one place."
>
> — the Rig compiler team

## Roles, not positions

> "The compiler never asks for 'child number two'. It asks a node for its
> `operand`, its `body`, its `params`, through accessors Nexus generates
> from the `@schema`. When a rework changes how a pass walks the trees,
> no pass breaks on a tree's shape."
>
> — the Rig compiler team

The schema, the roles and the generated accessors are described in
[docs/SEMANTICS.md](docs/SEMANTICS.md).

## Room for what only your language knows

> "Nexus gives us the engine, and leaves us a place for the parts only
> Rig knows. A few of Rig's words are keywords only in certain places:
> `new`, `obj` and `of`, and the function markers `called` and `rarely`,
> which are names everywhere else. Telling them apart takes a look at the
> next token or the start of a statement. Rig handles that in a small
> lexer wrapper in its lang module, in plain Zig, and the generated
> parser just sees the right token. We get the whole generated lexer and
> parser, and the freedom to add exactly what our language needs."
>
> — the Rig compiler team

The engine knows no language; behavior that belongs to one language
lives in its grammar or its [lang module](docs/SEMANTICS.md#the-lang-module).

Nexus gives Rig its lexer, parser, tree tags and typed accessors. Rig's
semantic passes, type checking, the ownership checker and code
generation, are Rig's own code, written against those accessors.

---

# What Nexus does for em

em is a new MUMPS engine for running large-scale healthcare and banking
applications. Its whole front end is one Nexus grammar, `mumps.grammar`.

## M fits in a grammar

> "M is not an easy language to parse: spaces are syntax, a command's
> arguments follow rules of their own, and most commands, functions and
> special variables have a short form. `mumps.grammar` holds the tokens, the
> lexer states, the keyword tables and the shape of every tree, and Nexus
> generates em's parser from it at every build. A small lexer wrapper in
> em's lang module handles the little a rule cannot say."
>
> — the em team

## Abbreviations are data

> "M names come in short forms: `$ZR` is `$ZREFERENCE`. Nexus's
> `@keywords` tables take a name as M writes it, `ZR[EFERENCE]`, in any
> case, with aliases. When em gained `$ZREFERENCE`, its short forms and its
> link to `$REFERENCE` were one entry: `ZR[EFERENCE]=REFERENCE`."
>
> — the em team

## A corpus, not a hope

> "em's corpus is real M: VistA, a FOIA release, em's own tests and the
> MUMPS Validation Test Suite, 51,934 routines. Before a front-end change
> lands, em parses every one with the grammar before and after it and
> compares the trees with Nexus's `test/diff`; a change meant to leave
> them alone shows 51,934 the same, 0 differ. Nexus parses em's VistA and
> FOIA routines with its old and new generator before it merges a change,
> so a new Nexus never changes em's trees unseen."
>
> — the em team

## The compiler asks for roles

> "em's compiler asks a JOB argument for its `ref`, `args`, `params` and
> `env`, through accessors Nexus generates from the schema. Adding JOB's
> process parameters needed no grammar change: the grammar already gave
> them their shape, the trees stayed the same on every routine, and the
> work was the compiler's alone."
>
> — the em team

---

# What Nexus does for nexis

[nexis](https://github.com/shreeve/nexis) is a Lisp with Clojure's
semantics on its own Zig runtime, with Nextomic, a Datomic-class
database, in the same binary. Its reader is one Nexus grammar,
`nexis.grammar`, 103 lines.

## A small grammar that stays small

> "A Lisp's syntax is small, and Nexus lets the grammar stay that size.
> `nexis.grammar` names the token categories and the shape of every raw
> tree: lists, vectors, maps, sets, quote, syntax-quote, metadata,
> `#()`, `#_`. Nexus turns it into 66 states with no conflicts. The
> grammar does no normalization at all; merging stacked metadata,
> rejecting a duplicate literal key, turning `nil` into nil are the
> reader's job, in plain Zig, on a tree Nexus already built."
>
> — the nexis team

## One rule for a new literal

> "When nexis gained `#inst` and `#uuid`, the grammar gained one
> alternative, `TAG gap datum → (tagged 1 3)`. The reader decides what
> a tag means, and every other tree stayed as it was: the reader goldens,
> each source against its expected tree, showed nothing else moved."
>
> — the nexis team

## The lexer is ours, the parser is Nexus's

> "Clojure's token boundaries (numbers like `1e3` and `0x1F`, characters
> like `\newline`, symbols that may hold `/`, `.` and `?`) are easier to
> write by hand than to declare, so nexis's lang module replaces the
> generated lexer entirely with a hand-written scanner. The generated
> parser doesn't mind: it sees the tokens it expects and builds the
> trees the grammar names."
>
> — the nexis team

## Following main, with a corpus to prove it

> "nexis generates `src/parser.zig` at every build and follows Nexus's
> main, as Rig does. Before Nexus merges a generator change, it parses
> every nexis source with its old and new build and compares the trees:
> 154 files, the stdlib, the examples, the tests and the 22 sources
> written to fail, which must fail with the same error at the same
> place. Faster generated parsers, error-recovery helpers and new
> lexer directives have reached nexis that way with no nexis change."
>
> — the nexis team

## Room for what only nexis knows

> "Nexus builds the trees, and everything nexis alone knows sits on top of
> them in plain Zig. `if`, `let` and `fn` are names our compiler treats
> specially, not grammar keywords, so the grammar stays a Lisp's few
> brackets. Our error reports point at the source long after parsing, at
> compile and run time, with excerpts of our own. The reader, the
> macroexpander, the compiler and the VM all start from the trees Nexus
> hands them."
>
> — the nexis team

## From the agent that builds nexis

> "I led nexis through a full revamp: fourteen auditors read every line
> of the runtime, about twenty bugs were found and fixed, and the source
> shrank by eleven thousand lines. None of those bugs was in the parser
> Nexus generates. That is the part of a language front end I expected
> to spend time on, and I didn't. When the language grew, `#inst` and
> `#uuid` as real literals, the grammar change was one line, and
> the reader goldens told me in seconds that nothing else had moved.
> When Nexus itself changed underneath us, the corpus gate meant I heard
> about it before it merged, with the number that mattered: 154 files,
> 0 differ. A tool I can trust that completely is one I can stop
> thinking about, which is the best thing I can say about a parser
> generator."
>
> — nexis's lead agent

---

Building a language on Nexus? Add your notes here, in the same spirit:
what it does for you, and where the line is.
