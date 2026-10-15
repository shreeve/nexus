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

Building a language on Nexus? Add your notes here, in the same spirit:
what it does for you, and where the line is.
