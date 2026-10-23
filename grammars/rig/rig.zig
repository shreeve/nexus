//! Rig language module for the Nexus-generated parser (src/parser.zig).
//!
//! The generated parser has two stages, each wrapped here and auto-wired
//! in by Nexus through `@hasDecl`:
//!
//!   stage   generated (parser.zig)   wrapper (this file)
//!   lex     BaseLexer                Lexer   — layout, keywords, position
//!   parse   BaseParser               Parser  — post-parse IR rewrites,
//!                                              diagnostics
//!
//! so `parser.Parser.init(allocator, source).parseProgram()` returns the
//! semantic IR described in docs/internals/INTERNALS.md.
//!
//! Also here: `Tag` (re-exported from the generated parser), IR helpers
//! over the generated accessors, `BindingKind`, and the identifier
//! escaping that emit needs (`writeZigIdent`).

const std = @import("std");
const parser = @import("parser.zig");
const diag = @import("diag.zig");
const ir = parser.ir;
const BaseLexer = parser.BaseLexer;
const BaseParser = parser.BaseParser;
const Token = parser.Token;
const TokenCat = parser.TokenCat;
const Sexp = parser.Sexp;

// =============================================================================
// Tag and IR helpers
// =============================================================================

/// Every node kind and marker tag of the IR, generated from the `@schema`
/// in rig.grammar (which also gives each kind's roles).
pub const Tag = parser.Tag;

/// The declared return type of a `fun`; `_` for a `sub`, which has none.
pub fn returnType(fun_or_sub: Sexp) Sexp {
    return if (fun_or_sub.isKind(.fun)) ir.Fun.returns(fun_or_sub) else .nil;
}

/// A compile-time function: a `fun` with compile-time parameters and no
/// run-time parameter list, `fun cap[n: Int] -> Int`, which the checker
/// runs and the program never does. The Parser wrapper lets this form
/// stand only at module level (`ctFunShape`), so the IR decides it: the
/// one classifier every pass reads.
pub fn isCtFun(decl: Sexp) bool {
    const def = unpub(decl);
    return def.isKind(.fun) and ir.Fun.params(def) == .nil and ir.Fun.tparams(def) != .nil;
}

/// Whether `decl` declares an API (`api Shape`) or adds one to a type
/// (`add Int: Shape`): methods no pass but the checker of conformances
/// reads, and nothing emits (docs/design/apis.md, Stage 3).
pub fn isApiDecl(decl: Sexp) bool {
    const d = unpub(decl);
    return d.isKind(.api) or d.isKind(.api_add);
}

/// A declaration without its `pub`.
pub fn unpub(decl: Sexp) Sexp {
    return if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl;
}

/// Whether the function body `body` ends in a panic on every path: its
/// last statement panics, or is an `if` with an `else` or a `match`
/// each of whose branches does, and nothing in it returns or passes a
/// failure or a `none` on first.
pub fn alwaysPanics(body: Sexp) bool {
    if (holdsExit(body)) return false;
    return endsInPanic(body);
}

fn endsInPanic(s: Sexp) bool {
    const h = s.kind() orelse return false;
    return switch (h) {
        .panic => true,
        .block => blk: {
            const items = ir.Block.stmts(s);
            break :blk items.len > 0 and endsInPanic(items[items.len - 1]);
        },
        .@"if" => ir.If.@"else"(s) != .nil and endsInPanic(ir.If.then(s)) and endsInPanic(ir.If.@"else"(s)),
        .match => for (ir.Match.arms(s)) |arm| {
            if (!endsInPanic(ir.Arm.body(arm))) break false;
        } else ir.Match.arms(s).len > 0,
        else => false,
    };
}

/// Whether `e` holds a `return`, or a `!` or `?` that passes a failure
/// or a `none` on, outside the closures in it.
fn holdsExit(e: Sexp) bool {
    if (e != .list) return false;
    if (e.kind()) |h| switch (h) {
        .lambda => return false,
        .@"return", .propagate, .propagate_none => return true,
        else => {},
    };
    for (e.items()) |c| if (holdsExit(c)) return true;
    return false;
}

/// A fallible `sub`: `sub save(p: Page)!`.
/// The error set a `sub`'s or a `sub` type's `!` names (`sub f()!E`),
/// or nil for a bare `!`, which fails with any error.
pub fn failSet(fails: Sexp) Sexp {
    return if (fails == .tag) .nil else fails;
}

pub fn subFails(fun_or_sub: Sexp) bool {
    return fun_or_sub.isKind(.sub) and ir.Sub.fails(fun_or_sub) != .nil;
}

/// A function's marker, which asks for a speed and never changes what
/// the program means: `inline fun` (inline it at every call), `called
/// fun` (every call stays a call), a body whose first line is `rarely`
/// (it is rarely called), or none (`inlining.decide` decides). The header
/// says how calls compile and wins over the body's `rarely`.
pub const Marker = enum { none, @"inline", called, rarely };

pub fn markerOf(fun_or_sub: Sexp) Marker {
    const m = ir.get(fun_or_sub, .mark);
    if (m == .nil) return if (startsRarely(ir.get(fun_or_sub, .body))) .rarely else .none;
    return switch (m.kind().?) {
        .@"inline" => .@"inline",
        .called => .called,
        else => unreachable,
    };
}

/// Where the marker of a `fun` or `sub` is written: its header's word,
/// or the `rarely` that starts its body.
pub fn markNode(fun_or_sub: Sexp) Sexp {
    const m = ir.get(fun_or_sub, .mark);
    if (m != .nil) return m;
    const body = ir.get(fun_or_sub, .body);
    return if (startsRarely(body)) ir.Block.stmts(body)[0] else fun_or_sub;
}

/// Whether `body`, a block, starts with `rarely`: it rarely runs.
pub fn startsRarely(body: Sexp) bool {
    if (!body.isKind(.block)) return false;
    const stmts = ir.Block.stmts(body);
    return stmts.len > 0 and stmts[0].isKind(.rarely);
}

/// A module-level constant (`name = value`, or a `pub` one). Passes take
/// them before the other declarations, so functions anywhere in the
/// module see them.
pub fn isModuleConst(decl: Sexp) bool {
    return (if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl).isKind(.set);
}

/// An `if` or `while` condition that binds: `a as x`, or parts joined by
/// `and`, one of them `a as x`. `as` binds tighter than `and`, so
/// `a as x and x > 0 and b as y` is
/// `(and (and (as a x) (> x 0)) (as b y))`: its parts are the leaves of
/// the left spine, checked in order, each binding visible to the parts
/// after it and to the body.
pub fn bindsInCondition(cond: Sexp) bool {
    if (isAsPart(cond)) return true;
    if (!cond.isKind(.@"and")) return false;
    return isAsPart(ir.get(cond, .right)) or bindsInCondition(ir.get(cond, .left));
}

/// A part of a condition that binds: `a as x`, `f() as a, b`, which
/// binds a call's several results (`as_results`), or `s as .circle(r)`,
/// which binds a variant's fields (`as_match`).
pub fn isAsPart(e: Sexp) bool {
    return e.isKind(.as) or e.isKind(.as_results) or e.isKind(.as_match);
}

/// The one-arm `match` an `as_match` part is (`Parser.asMatch`).
pub fn asMatchOf(part: Sexp) Sexp {
    return part.items()[1];
}

/// The one arm of the `match` an `as_match` part is: its pattern binds,
/// and the rest of the condition and the body go on in it.
pub fn asMatchArm(part: Sexp) Sexp {
    return ir.Match.arms(asMatchOf(part))[0];
}

/// Whether `cond` joins two parts of a binding condition: an `and` on
/// its left spine.
pub fn isConditionJoin(cond: Sexp) bool {
    return cond.isKind(.@"and") and bindsInCondition(cond);
}

/// Call `visitor.part(p)` for each guard part of an `if` or `while`
/// condition, in the order they run: each part a binding condition joins
/// (`isConditionJoin`), which is a header of its own, or else the whole
/// condition, which is one. The one list of a condition's parts: emit
/// writes one `if` per part, and the storage plan, the type checker, the
/// symbol resolver, and the ownership checker walk the same parts. A
/// visitor with a `join` method is also given each `and` that joins
/// parts, after the parts it joins.
pub fn eachGuardPart(cond: Sexp, visitor: anytype) !void {
    if (isConditionJoin(cond)) {
        try eachGuardPart(ir.get(cond, .left), visitor);
        try eachGuardPart(ir.get(cond, .right), visitor);
        const V = @TypeOf(visitor);
        const T = if (@typeInfo(V) == .pointer) @typeInfo(V).pointer.child else V;
        if (@hasDecl(T, "join")) try visitor.join(cond);
        return;
    }
    try visitor.part(cond);
}

/// The nodes that leave the function or closure body holding them, on
/// the edge where they fail or always: `return`, `e!`, `e?`. A jump
/// (`jump_kinds`) goes to its `JumpDest` in the body instead.
pub const body_exit_kinds = [_]Tag{ .@"return", .propagate, .propagate_none };

/// The jumps, `break` and `continue`, each to the construct its
/// `JumpDest` names.
pub const jump_kinds = [_]Tag{ .@"break", .@"continue" };

/// Whether `e` leaves the body that holds it (`body_exit_kinds`): the
/// positive list of a body's exits.
pub fn leavesBody(e: Sexp) bool {
    const k = e.kind() orelse return false;
    return std.mem.findScalar(Tag, &body_exit_kinds, k) != null;
}

/// Whether `e` ends the code that follows it in its block: a `return`,
/// a jump (`isJump`), or a `panic`, which ends the program.
pub fn leaves(e: Sexp) bool {
    const k = e.kind() orelse return false;
    return k == .@"return" or k == .panic or std.mem.findScalar(Tag, &jump_kinds, k) != null;
}

/// Whether `e` is a jump (`jump_kinds`).
pub fn isJump(e: Sexp) bool {
    const k = e.kind() orelse return false;
    return std.mem.findScalar(Tag, &jump_kinds, k) != null;
}

/// Call `f(ctx, owner, body)` for the body of each function, `sub`,
/// `test`, and `drop` declared in module `root`, members of types
/// included: the bodies `eachUnit` lists the units of.
pub fn eachBody(root: Sexp, ctx: anytype, comptime f: anytype) !void {
    if (root.kind() != .module) return;
    for (ir.Module.decls(root)) |d| try bodiesOfDecl(d, ctx, f);
}

fn bodiesOfDecl(decl: Sexp, ctx: anytype, comptime f: anytype) !void {
    switch (decl.kind() orelse return) {
        .@"pub" => try bodiesOfDecl(ir.Pub.decl(decl), ctx, f),
        .fun, .sub, .drop_decl, .@"test" => if (ir.get(decl, .body) != .nil) try f(ctx, decl, ir.get(decl, .body)),
        .@"struct", .@"enum", .generic_struct, .generic_enum => for (ir.rest(decl, .members)) |m| try bodiesOfDecl(m, ctx, f),
        else => {},
    }
}

/// What a unit is (`eachUnit`).
pub const UnitKind = enum {
    /// A statement of a block that orders no others (`stmtClass`).
    stmt,
    /// The step of a `while`.
    step,
    /// A guard part of an `if` or `while` condition: an `as` part, or an
    /// operand of the top `and` chain of any other part.
    guard,
    /// The source of a `for`.
    source,
    /// A statement `match`'s selection: its subject, every pattern, and
    /// every guard, which run before an arm's body and never after it.
    selection,
    /// A `raw` block, opaque: no unit is listed inside it.
    raw,
};

/// What a statement of a block is to the units of a body
/// (`skeletonOf`). Every IR tag is listed, so a new one fails to compile
/// until it is placed.
pub const StmtClass = enum {
    /// It orders the units it holds, and is no unit itself.
    structured,
    /// One unit: it orders nothing inside it.
    unit,
    /// A `raw` block: one opaque unit.
    raw,
    /// Never a statement (a declaration, a pattern, a type, a part of
    /// another node): met as one, it is an opaque unit.
    none,
};

pub fn stmtClass(tag: Tag) StmtClass {
    return switch (tag) {
        .block, .@"if", .@"while", .@"for", .match, .labeled, .@"defer", .@"errdefer" => .structured,
        .raw_block => .raw,
        // Assignments, drops, `pass`, the exits and jumps, and expressions.
        .set, .destructure, .tuple, .drop, .pass, .rarely, .@"return", .@"break", .@"continue", .panic, .propagate, .propagate_none, .@"catch", .call, .builtin, .member, .index, .inst, .ct_call, .array, .array_fill, .lambda, .@"+", .@"-", .@"*", .@"/", .@"%", .@"+%", .@"-%", .@"*%", .@"+|", .@"-|", .@"==", .@"!=", .@"<", .@">", .@"<=", .@">=", .@"&", .@"|", .@"^", .@"<<", .@"<<%", .@">>", .@"??", .@"and", .@"or", .@"..", .neg, .not, .move, .read, .write, .clone, .share, .weak, .box => .unit,
        .module, .use, .fun, .sub, .@"struct", .@"enum", .errors, .error_join, .generic_struct, .generic_enum, .api, .api_type, .api_add, .type, .@"test", .@"pub", .@"extern", .extern_fun, .extern_sub, .zig_extern, .zig_const, .drop_decl, .@"inline", .called, .@":", .bound, .assoc_bound, .default, .valued, .none_value, .variant, .as, .as_results, .as_pattern, .as_match, .results, .result_part, .results_type, .arm, .alt_pattern, .range_pattern, .set_pattern, .variant_pattern, .enum_lit, .symbol, .captures, .cap_clone, .cap_move, .cap_weak, .cap_read, .cap_write, .kwarg, .optional, .error_union, .read_view, .write_view, .shared, .boxed, .slice, .generic_inst, .array_type, .fun_type, .fails, .unique, .fixed, .task, .shadow, .shadow_fixed, .@"+=", .@"-=", .@"*=", .@"/=", .@"%=", .@"+%=", .@"-%=", .@"*%=", .@"+|=", .@"-|=", .@"&=", .@"|=", .@"^=", .@"<<=", .@"<<%=", .@">>=", .iter, .inclusive => .none,
        // `>t`, rewritten to a call; `f: once T`, rewritten to a
        // parameter; and `a..=b`, rewritten to an inclusive `..`: each
        // before any pass reads a statement.
        .wait, .once, .@"..=" => .none,
    };
}

/// How a statement orders the units it holds: the one skeleton `eachUnit`
/// lists the units by and the proof pass walks (docs/internals/INTERNALS.md,
/// "Proven checks").
pub const Skeleton = union(enum) {
    /// One unit, of kind `stmt` or `raw`.
    unit: UnitKind,
    /// A block: its statements in order.
    block: Sexp,
    @"if": struct { cond: Sexp, then: Sexp, @"else": Sexp },
    @"while": struct { cond: Sexp, body: Sexp, step: Sexp, @"else": Sexp },
    @"for": struct { source: Sexp, body: Sexp, @"else": Sexp },
    /// A statement `match`: its selection unit, then each arm's body.
    match: Sexp,
    /// A labeled statement: the statement.
    labeled: Sexp,
    /// A `defer` or `errdefer`: its body, run at its block's exits.
    @"defer": Sexp,
};

/// The skeleton of statement `stmt` (`StmtClass`). A leaf is a unit that
/// holds nothing to check or write.
pub fn skeletonOf(stmt: Sexp) Skeleton {
    const tag = stmt.kind() orelse return .{ .unit = .stmt };
    return switch (stmtClass(tag)) {
        .unit => .{ .unit = .stmt },
        .raw, .none => .{ .unit = .raw },
        .structured => switch (tag) {
            .block => .{ .block = stmt },
            .@"if" => .{ .@"if" = .{ .cond = ir.If.cond(stmt), .then = ir.If.then(stmt), .@"else" = ir.If.@"else"(stmt) } },
            .@"while" => .{ .@"while" = .{ .cond = ir.While.cond(stmt), .body = ir.While.body(stmt), .step = ir.While.step(stmt), .@"else" = ir.While.@"else"(stmt) } },
            .@"for" => .{ .@"for" = .{ .source = ir.For.source(stmt), .body = ir.For.body(stmt), .@"else" = ir.For.@"else"(stmt) } },
            .match => .{ .match = stmt },
            .labeled => .{ .labeled = ir.Labeled.stmt(stmt) },
            .@"defer", .@"errdefer" => .{ .@"defer" = ir.get(stmt, .body) },
            else => unreachable,
        },
    };
}

/// Call `visitor.enter(root, kind)` and `visitor.exit(root)` around each
/// unit of a function or closure body, in the order the body runs them
/// (docs/internals/INTERNALS.md, "Proven checks"). A unit is a part of a body
/// inside which nothing is ordered: a statement, a guard part, a `while`
/// step, a `for` source, a statement `match`'s selection, or a `raw`
/// block. A block inside a unit's expression (an arm of a value `match`,
/// a branch of a value `if`, a `catch` handler, a loop's body) and a
/// closure's body hold units of their own, listed between the enter and
/// the exit of the unit around them. The selection's root is the `match`
/// node; its nodes are the subject, the patterns, and the guards
/// (`selectionParts`). The one list of a body's units: the storage plan
/// records each node's unit from it (`SemContext.unitOf`), and the proof
/// pass and emit enter the same units.
pub fn eachUnit(body: Sexp, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    try unitsOfBranch(body, visitor);
}

/// The errors a unit visitor's `enter` may return, which every step of
/// `eachUnit` passes on.
fn VisitError(comptime V: type) type {
    const T = if (@typeInfo(V) == .pointer) @typeInfo(V).pointer.child else V;
    return @typeInfo(@typeInfo(@TypeOf(T.enter)).@"fn".return_type.?).error_union.error_set;
}

/// A branch: a block, or one statement.
fn unitsOfBranch(b: Sexp, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    if (b.isKind(.block)) {
        for (ir.Block.stmts(b)) |s| try unitsOfStmt(s, visitor);
        return;
    }
    if (b != .nil) try unitsOfStmt(b, visitor);
}

fn unitsOfStmt(stmt: Sexp, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    switch (skeletonOf(stmt)) {
        .unit => |kind| try unitOf(stmt, kind, visitor),
        .block => |b| try unitsOfBranch(b, visitor),
        .@"if" => |x| {
            try unitsOfCond(x.cond, visitor);
            try unitsOfBranch(x.then, visitor);
            try unitsOfBranch(x.@"else", visitor);
        },
        .@"while" => |x| {
            try unitsOfCond(x.cond, visitor);
            try unitsOfBranch(x.body, visitor);
            if (x.step != .nil) try unitOf(x.step, .step, visitor);
            try unitsOfBranch(x.@"else", visitor);
        },
        .@"for" => |x| {
            try unitOf(x.source, .source, visitor);
            try unitsOfBranch(x.body, visitor);
            try unitsOfBranch(x.@"else", visitor);
        },
        .match => |m| {
            try unitOf(m, .selection, visitor);
            for (ir.Match.arms(m)) |arm| try unitsOfBranch(ir.Arm.body(arm), visitor);
        },
        .labeled => |inner| try unitsOfStmt(inner, visitor),
        .@"defer" => |body| try unitsOfBranch(body, visitor),
    }
}

/// The guard parts of a condition (`eachGuardPart`), each `and` operand
/// of a part that binds nothing its own unit. A part `s as .circle(r)`
/// is the selection of the `match` it is (`asMatchOf`).
fn unitsOfCond(cond: Sexp, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    const Parts = struct {
        v: @TypeOf(visitor),
        pub fn part(self: @This(), p: Sexp) VisitError(@TypeOf(visitor))!void {
            if (p.isKind(.as_match)) return unitOf(asMatchOf(p), .selection, self.v);
            try eachGuardOperand(p, self, @This().unit);
        }
        fn unit(self: @This(), p: Sexp) VisitError(@TypeOf(visitor))!void {
            try unitOf(p, .guard, self.v);
        }
    };
    try eachGuardPart(cond, Parts{ .v = visitor });
}

/// Call `f(ctx, e)` for each operand of guard part `part`'s top `and`
/// chain, left to right, or for the part itself: an `as` part, or one
/// that is no `and`. Zig's `and` runs each only when those before it
/// held, as Rig's does.
pub fn eachGuardOperand(part: Sexp, ctx: anytype, comptime f: anytype) !void {
    if (part.isKind(.@"and")) {
        try eachGuardOperand(ir.get(part, .left), ctx, f);
        return eachGuardOperand(ir.get(part, .right), ctx, f);
    }
    try f(ctx, part);
}

/// The nodes of a statement `match`'s selection unit: its subject, then
/// each arm's pattern and guard.
pub fn selectionParts(a: std.mem.Allocator, match: Sexp) ![]const Sexp {
    var out: std.ArrayList(Sexp) = .empty;
    try out.append(a, ir.Match.subject(match));
    for (ir.Match.arms(match)) |arm| {
        try out.append(a, ir.Arm.pattern(arm));
        if (ir.Arm.guard(arm) != .nil) try out.append(a, ir.Arm.guard(arm));
    }
    return out.items;
}

fn unitOf(root: Sexp, kind: UnitKind, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    // A leaf (a name, a literal) holds nothing to check or write.
    if (root != .list) return;
    try visitor.enter(root, kind);
    switch (kind) {
        // Nothing inside `raw` is a unit of its own.
        .raw => {},
        .selection => {
            try nestedUnits(ir.Match.subject(root), visitor);
            for (ir.Match.arms(root)) |arm| {
                try nestedUnits(ir.Arm.pattern(arm), visitor);
                try nestedUnits(ir.Arm.guard(arm), visitor);
            }
        },
        else => try nestedUnits(root, visitor),
    }
    try visitor.exit(root);
}

/// The units of the blocks and closure bodies inside a unit's expression.
/// A visitor with a `nest` method is given each such block before and
/// after its units.
fn nestedUnits(e: Sexp, visitor: anytype) VisitError(@TypeOf(visitor))!void {
    if (e != .list) return;
    if (e.isKind(.block)) {
        const V = @TypeOf(visitor);
        const T = if (@typeInfo(V) == .pointer) @typeInfo(V).pointer.child else V;
        if (@hasDecl(T, "nest")) try visitor.nest(e, true);
        try unitsOfBranch(e, visitor);
        if (@hasDecl(T, "nest")) try visitor.nest(e, false);
        return;
    }
    for (e.items()) |c| try nestedUnits(c, visitor);
}

/// `x[...]`: an index, or compile-time arguments (sema tells which).
pub fn isBracketList(e: Sexp) bool {
    return e.isKind(.index) or e.isKind(.inst);
}

/// Whether a call of `callee` is a method call: a member, or a member
/// followed by a bracket list (`v.put[2](x)`).
pub fn isMethodCallee(callee: Sexp) bool {
    if (callee.isKind(.member)) return true;
    return isBracketList(callee) and ir.get(callee, .object).isKind(.member);
}

/// The member a variant pattern names, `.name(...)` or `E.name(...)`:
/// its name's leaf.
pub fn variantPatternName(p: Sexp) Sexp {
    const n = ir.VariantPattern.name(p);
    return if (n.isKind(.member)) ir.Member.name(n) else n;
}

/// Whether range `r`, a `..` or a range pattern, includes its end:
/// `a..=b`.
pub fn isInclusive(r: Sexp) bool {
    return ir.get(r, .inclusive) != .nil;
}

/// A slice, `xs[a..b]`: an index node whose index is a range.
pub fn isRangeIndex(e: Sexp) bool {
    return e.isKind(.index) and ir.Index.index(e).isKind(.@"..");
}

/// Every child of a node, in slot order (absent optional slots are `_`),
/// for passes that visit all of them; empty for a leaf. Passes that need
/// a particular child read it by role (`parser.ir`).
pub fn children(node: Sexp) []const Sexp {
    if (node.kind() == null) return &.{};
    return node.items()[1..];
}

// =============================================================================
// BindingKind — the op slot of (set <op> ...)
// =============================================================================

/// Exhaustive view of the op slot, so dispatch sites must handle every
/// kind: `_` → default, `fixed` (`x =!`, and `new x =!`), `shadow`
/// (`new x =`), and the compound assignments (`x op= e`, one per binary
/// arithmetic, wrapping, bitwise, and shift operator). Every kind but
/// `default` is named after its tag in the schema's `op:tag(...)` for
/// `set`. `new x =! e` is the tag `shadow_fixed`, decoded as `fixed`: it
/// binds as `x =! e` does, and only declaring the name tells the two
/// apart (`shadows`).
pub const BindingKind = enum {
    default,
    fixed,
    shadow,
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"+%=",
    @"-%=",
    @"*%=",
    @"+|=",
    @"-|=",
    @"&=",
    @"|=",
    @"^=",
    @"<<=",
    @"<<%=",
    @">>=",

    comptime {
        for (@typeInfo(BindingKind).@"enum".field_names[1..]) |f| {
            if (!@hasField(Tag, f)) @compileError("BindingKind." ++ f ++ " is not a tag of the IR");
        }
    }

    /// The binary operator a compound assignment applies (`+=` applies
    /// `+`), or null for a plain binding or assignment.
    pub fn operator(k: BindingKind) ?Tag {
        return switch (k) {
            .default, .fixed, .shadow => null,
            inline else => |c| @field(Tag, @tagName(c)[0 .. @tagName(c).len - 1]),
        };
    }
};

/// Decode the op slot of `(set <op> ...)`. Nexus builds it from the
/// schema's `op:tag(...)`, so any other value is unreachable.
pub fn bindingKindOf(op: Sexp) BindingKind {
    return switch (op) {
        .nil => .default,
        .tag => |t| switch (t) {
            .shadow_fixed => .fixed,
            inline else => |c| if (@hasField(BindingKind, @tagName(c))) @field(BindingKind, @tagName(c)) else unreachable,
        },
        else => unreachable,
    };
}

/// Whether the op slot of `(set <op> ...)` binds a new name even where
/// one is already visible: `new x = e` and `new x =! e`.
pub fn shadows(op: Sexp) bool {
    return op == .tag and (op.tag == .shadow or op.tag == .shadow_fixed);
}

// =============================================================================
// Keywords
// =============================================================================

/// The categories from `true` to `yield` in rig.grammar's `tokens`
/// block are Rig's keywords. Every keyword is reserved and is a lexer
/// rule, so the base lexer gives it its own category, except `new`, `obj`,
/// `inline`, `called`, and `rarely`, which lex as names and are keywords only where
/// the rewriter classifies them (`classifyWord`): `new` at the start of a
/// statement followed by a name (`new x = ...`, `new x =! ...`), so
/// `fun new(...)` and `Point.new(...)` stay ordinary names.
pub fn isKeyword(cat: TokenCat) bool {
    return @intFromEnum(cat) >= @intFromEnum(TokenCat.true) and @intFromEnum(cat) <= @intFromEnum(TokenCat.yield);
}

/// A word the base lexer reads: a name or a reserved word.
fn isWord(cat: TokenCat) bool {
    return cat == .ident or isKeyword(cat);
}

/// The token category of a keyword, or null for a plain name.
pub fn keyword(word: []const u8) ?TokenCat {
    if (std.mem.eql(u8, word, "new")) return .new;
    var base = BaseLexer.init(word);
    const tok = base.next();
    return if (endOf(&base, tok) == word.len and isKeyword(tok.cat)) tok.cat else null;
}

/// Where a token the lexer `base` scanned or built ends: `pos + len`, and
/// for a token over 65534 bytes (its `len` is 65535, `@longtokens`) the
/// end `base` recorded. Every end of a token on the lexer's side is read
/// here; the parser's side reads `BaseParser.tokenEnd`.
pub fn endOf(base: *const BaseLexer, tok: Token) u32 {
    if (tok.len < std.math.maxInt(u16)) return tok.pos + tok.len;
    return base.longEnds.find(tok.pos).?;
}

// =============================================================================
// Zig identifiers for emitted code
// =============================================================================

const zig_keywords = std.StaticStringMap(void).initComptime(.{
    .{"addrspace"},   .{"align"},   .{"allowzero"},   .{"and"},
    .{"anyframe"},    .{"anytype"}, .{"asm"},         .{"break"},
    .{"callconv"},    .{"catch"},   .{"comptime"},    .{"const"},
    .{"continue"},    .{"defer"},   .{"else"},        .{"enum"},
    .{"errdefer"},    .{"error"},   .{"export"},      .{"extern"},
    .{"fn"},          .{"for"},     .{"if"},          .{"inline"},
    .{"linksection"}, .{"noalias"}, .{"noinline"},    .{"nosuspend"},
    .{"opaque"},      .{"or"},      .{"orelse"},      .{"packed"},
    .{"pub"},         .{"resume"},  .{"return"},      .{"struct"},
    .{"suspend"},     .{"switch"},  .{"test"},        .{"threadlocal"},
    .{"try"},         .{"union"},   .{"unreachable"}, .{"var"},
    .{"volatile"},    .{"while"},
});

const zig_primitives = std.StaticStringMap(void).initComptime(.{
    .{"anyerror"}, .{"anyopaque"},      .{"bool"},         .{"c_char"},
    .{"c_int"},    .{"c_long"},         .{"c_longdouble"}, .{"c_longlong"},
    .{"c_short"},  .{"c_uint"},         .{"c_ulong"},      .{"c_ulonglong"},
    .{"c_ushort"}, .{"comptime_float"}, .{"comptime_int"}, .{"f128"},
    .{"f16"},      .{"f32"},            .{"f64"},          .{"f80"},
    .{"false"},    .{"isize"},          .{"noreturn"},     .{"null"},
    .{"true"},     .{"type"},           .{"undefined"},    .{"usize"},
    .{"void"},
});

/// Names a Rig name may not keep in the emitted Zig: the ones the emitted
/// prelude declares (`std`, `rig`, and `panic`, the root module's panic
/// handler), and the ones Zig's standard library looks up in the root
/// module with `@hasDecl(root, ...)` and uses as hooks (`debug`, `os`,
/// `std_options`, the entry points of each target), and `self`, which
/// `@` is written as. Every one is renamed wherever it
/// stands, so no hook depends on which module or scope declares it.
const emitter_names = std.StaticStringMap(void).initComptime(.{
    .{"std"},       .{"rig"},                .{"panic"},
    .{"debug"},     .{"os"},                 .{"tracy"},
    .{"_start"},    .{"__start"},            .{"main"},
    .{"WinMain"},   .{"wWinMain"},           .{"WinMainCRTStartup"},
    .{"DllMain"},   .{"wWinMainCRTStartup"}, .{"DllMainCRTStartup"},
    .{"EfiMain"},   .{"_DllMainCRTStartup"}, .{"self"},
});
/// The prefixes of the names emitter temporaries take (`__rig_tmp_3`),
/// and of the `std_options_*` hooks.
const emitter_prefixes = [_][]const u8{ "__rig", "std_options" };

pub fn isPlainName(name: []const u8) bool {
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    return true;
}

fn isZigIntType(name: []const u8) bool {
    if (name.len < 2 or (name[0] != 'i' and name[0] != 'u')) return false;
    for (name[1..]) |c| if (c < '0' or c > '9') return false;
    return true;
}

/// Whether the Zig spelling of the Rig name `name` is another name: the
/// name `writeZigIdent` gives it a `'` suffix.
pub fn zigRenames(name: []const u8) bool {
    if (!isPlainName(name)) return false;
    if (emitter_names.has(name)) return true;
    for (emitter_prefixes) |p| if (std.mem.startsWith(u8, name, p)) return true;
    return false;
}

/// How a name is written: a Rig name of the program (`.rig`), or a name
/// that must be spelled exactly, as the Zig or C it denotes declares it
/// (`.exact`: a function of a standard library Zig file).
pub const ZigSpelling = enum { rig, exact };

/// Write `name` as a Zig identifier that denotes the Rig name and nothing
/// else. This is the one place a Rig name becomes a Zig name: every
/// declaration and every use of a local, parameter, capture, field,
/// method, variant, type, generic parameter, constant, function,
/// label, or module the program names is written here, so a use is
/// always spelled as its declaration.
///   * self, `@`, is `self`;
///   * a name the emitter or Zig's standard library uses
///     (`zigRenames`: `std`, `rig`, `debug`, `self`, `__rig*`) gets a `'`
///     suffix, which no Rig identifier can contain: `@"rig'"`; an
///     `.exact` name never does;
///   * a Zig keyword or primitive (`var`, `fn`, `u8`, `type`), and `_`,
///     which alone is Zig's discard, are quoted: `@"var"`, `@"_"`;
///   * anything else is written as is.
/// The mapping is one to one, so two Rig names never meet in one Zig
/// name, and the runtime strips the suffix where a name is printed
/// (`rig.rigName`).
pub fn writeZigIdent(w: *std.Io.Writer, name: []const u8, spelling: ZigSpelling) std.Io.Writer.Error!void {
    if (std.mem.eql(u8, name, "@")) {
        try w.writeAll("self");
    } else if (!isPlainName(name)) {
        // A name no program writes (`hiddenLeaf`).
        try w.print("@\"{s}\"", .{name});
    } else if (spelling == .rig and zigRenames(name)) {
        try w.print("@\"{s}'\"", .{name});
    } else if (zig_keywords.has(name) or zig_primitives.has(name) or isZigIntType(name) or std.mem.eql(u8, name, "_")) {
        try w.print("@\"{s}\"", .{name});
    } else {
        try w.writeAll(name);
    }
}

// =============================================================================
// Lexer — layout and token classification over the generated BaseLexer
// =============================================================================
//
// Layout
//   Leading spaces set a line's indentation; deeper lines open a block
//   (INDENT), shallower ones close blocks (OUTDENT) and must land on an
//   enclosing level. Blank and comment-only lines are ignored. Inside
//   ( ) and [ ] newlines are whitespace, so an expression may span lines.
//   A trailing `\` also joins the next line. Tabs are rejected in
//   indentation.
//
//   Closure bodies inside brackets: a closure's bar list that ends its
//   line inside ( ) or [ ] opens a layout island, so the body below is
//   laid out in blocks like anywhere else:
//
//       sig.subscribe(*|~sig|
//         if sig.upgrade() as s
//           print(s.get())
//       )
//
//   The island closes when a line comes back to the indentation of the
//   line the closure started on, or when the bracket around it closes;
//   its open blocks end there. The line that closes it starts with that
//   bracket, at the indentation of the line that opened the bracket; a
//   bracket that closes it anywhere else is recorded (`layouts`), and
//   reported once the source parses.
//
// Position
//   Whitespace inside an expression never picks a form. A character that
//   both starts and continues an operand (`<x` and `a < b`, `f(x)` and
//   `(x)`, `?T` and `T?`, `.red` and `a.b`) is one token, and the parser
//   tells the forms apart by where it stands. The lexer still reads
//   position where the parser cannot: after a value (a name, the type
//   `error`, a literal, `)`, `]`, or a `?` / `!` suffix) a character
//   continues it; anywhere else it starts an operand, as a prefix:
//
//     `|x| ...` starts a closure's bar list; after a value `|` is
//     bitwise or.
//
//     A prefix sigil touches its operand: `- b` and `< x` are errors,
//     so `a <- b` is not quietly `a < -b`. After a type's `]` the
//     parser decides (`[2]?T`), and the Parser wrapper checks the touch.
//
//     Spacing never picks a form, but spacing that reads as another
//     form is wrong: an infix operator has the same spacing on both
//     sides (`a < b`, `a<b`, never `a <b`), a postfix `?` or `!` touches
//     what it follows, a member `.` touches both sides (a chain may go
//     on at the start of the next line inside brackets), an enum
//     literal's `.` touches its name, and a range's `..` with one bound
//     touches it. The lexer records each such operator (`spacings`);
//     the Parser wrapper reports them once the source parses, so that a
//     parse error is the one reported.
//
//   Token boundaries still matter, as in `!=` and `==`: `=!` is one
//   token, so `x =!y` could be a fixed binding of `y` or `x = !y`; a
//   `=!` without a space or tab after it is an error.
//
// `if`
//   After `return`/`break`/`continue` or a value, `if` is a postfix guard
//   (`return x if done`), or the inline ternary when an `else` follows on
//   the same logical line (`a if c else b`). Elsewhere it opens a block.
//
// `of`
//   After a value directly inside [ ], `of` separates a fill literal's
//   count from its element (`[n of x]`). Elsewhere it is a name.
//
// `obj`
//   At the start of a statement (after any `pub`), when a name follows
//   it, `obj` starts a type declaration (`obj Point`). Elsewhere it is a
//   name (`obj = 5`, `obj.x`, `f(obj: 1)`), and so is `struct`.
//
// A leading `.`
//   A line that starts with `.` and a name, indented deeper than its
//   statement, continues that statement (`continuesChain`). The
//   statement must be complete and open no block, so `match` arms and
//   the members of a type are unchanged.
//
// `unique`, `from`, `static`
//   Names to the lexer: the parser reads each as a keyword where its
//   state takes it (rig.grammar, `@keywords`).
//
// `..`
//   Before `]` (past any line break, which is whitespace inside
//   brackets), `..` ends an open range (`xs[a..]`, `xs[..]`):
//   DOTDOT_OPEN, so the expression before it ends there.

pub const Lexer = struct {
    base: BaseLexer,

    // Indentation: `levels[0..depth]` are the enclosing block columns.
    levels: [max_indent_depth]u32 = undefined,
    depth: u32 = 0,
    /// Per depth: the current line there opened a block that `else` may
    /// continue (it has a block `if`, `while`, or `for`). An `else` after
    /// any other block (a match arm) is a new line.
    takes_else: [max_indent_depth + 1]bool = @splat(false),
    /// Per depth: the block is the member list of a struct, enum, or
    /// error set, where a keyword may name a field or method.
    in_members: [max_indent_depth + 1]bool = @splat(false),
    /// Per depth: the block is the arm list of a `match`, where each line
    /// is an arm and a deeper line is its body.
    in_arms: [max_indent_depth + 1]bool = @splat(false),
    /// The first token of the current statement, after any `pub`, and
    /// where it starts.
    line_head: TokenCat = .eof,
    /// The logical line has a token that opens a block (`fun`, `if`,
    /// `match`, `obj`, ...), wherever it stands: `x = match c` opens one
    /// as `match c` does.
    line_opens: bool = false,
    /// The line has a `match`, so the block it opens holds arms.
    line_match: bool = false,
    head_pos: u32 = 0,
    column: u32 = 0,
    pending_outdents: u32 = 0,
    pending_newline: bool = false,
    pending_pos: u32 = 0,

    // Positions of the open ( and [; newlines inside them are whitespace.
    brackets: [max_nesting]u32 = undefined,
    nesting: u32 = 0,

    /// Category of the last token returned.
    last_cat: TokenCat = .eof,
    /// The last token ends an operand (`isValue`, or a `?` / `!` suffix
    /// after one), so a character after it continues the operand.
    after_value: bool = false,
    /// The last token is a `$` that declares a statement's label; the
    /// name after it is the label.
    label_sigil: bool = false,
    /// The last token is the name of a label being declared: its `:`
    /// is next, and it ends no operand.
    label_name: bool = false,
    /// The last token is a label's `:` (`$outer:`): a statement starts
    /// after it.
    after_label: bool = false,
    /// The last token is the label of a jump (`break $outer`): what
    /// follows it starts the jump's value, and ends no operand.
    after_jump_label: bool = false,
    /// The category of the token before the last one.
    last2_cat: TokenCat = .eof,
    /// The last token is a symbol's `:`: the word after it is the
    /// symbol's name, a keyword too (`:if`).
    symbol_name: bool = false,
    /// The operators whose spacing breaks the rule (an infix operator
    /// has the same spacing on both sides; a postfix, a member `.`, and a
    /// range's open end touch what they join), and the closure bodies
    /// laid out below their bar lists that end anywhere but on a line of
    /// their own: the first `max_layouts` of them, reported once the
    /// source parses (`Parser.layoutMessage`).
    layouts: [max_layouts]Layout = undefined,
    layout_count: u32 = 0,
    /// The bracket nesting of the `while` header being lexed, whose first
    /// `:` there starts the step; null outside one.
    while_header: ?u32 = null,
    /// Start and end of the last real (non-layout) token; an unexpected
    /// end of block or file is reported at its end.
    prev_pos: u32 = 0,
    prev_end: u32 = 0,
    prev_cat: TokenCat = .eof,
    /// The real token before that one, which a parse error's hint reads.
    before_cat: TokenCat = .eof,
    before_pos: u32 = 0,
    /// Position of the `|` that closes the bar list being lexed.
    capture_close: ?u32 = null,
    /// The last token closed a closure's bar list.
    closed_bars: bool = false,
    /// Layout islands: closure bodies laid out inside brackets, innermost
    /// last.
    islands: [max_islands]Island = undefined,
    island_count: u32 = 0,
    /// A token held back until pending OUTDENTs are returned.
    pending_token: ?Token = null,
    /// Where the name after an `@` touching it starts (`@hits`): the
    /// next token is a `.` there, which makes `@hits` the member access
    /// `@ . hits`.
    member_dot: ?u32 = null,
    /// A module of several files, joined: where each file but the last
    /// ends in the source, ascending. Each file closes its own blocks and
    /// brackets: no token is read across an end while a bracket is open,
    /// and a file's first line is not indented.
    ends: []const u32 = &.{},
    /// The index in `ends` of the end of the file being read.
    file: u32 = 0,

    /// Why the last `.err` token was produced.
    err: LexError = .none,

    pub const max_indent_depth = 64;
    pub const max_nesting = 512;
    pub const max_islands = 32;
    pub const max_layouts = 32;

    /// A closure body laid out inside brackets. Its blocks sit on the
    /// layout stack above `depth`; `column` is the indentation of the
    /// line the closure starts on, and the layout state to restore is
    /// `depth` / `outer_column`.
    const Island = struct { nesting: u32, depth: u32, column: u32, outer_column: u32 };

    /// An operator whose spacing, or a closure body whose layout, breaks
    /// the rule, at `pos`.
    pub const Layout = struct {
        pos: u32,
        len: u32,
        kind: Kind,
        /// For a closure body: the indentation of the line that opened
        /// the bracket around it, where its closing bracket goes.
        column: u32 = 0,

        pub const Kind = enum {
            /// An infix operator with whitespace before it only (`a <b`).
            infix_before,
            /// An infix operator with whitespace after it only (`a< b`).
            infix_after,
            /// A postfix `?` or `!` apart from what it follows (`f() !`).
            postfix,
            /// A member `.` with whitespace beside it (`w . get()`).
            member,
            /// An enum literal's `.` apart from its name (`. red`).
            enum_dot,
            /// A range's `..` apart from its only bound (`.. b`, `a ..]`).
            range_end,
            /// A call's or index's bracket apart from what it follows
            /// (`f (x)`, `xs [0]`).
            call_bracket,
            /// The bracket around a closure body laid out below its bar
            /// list closes on the body's last line (`print(x))`).
            closure_hanging,
            /// The line that ends such a body starts with something other
            /// than that bracket (`, 1)`).
            closure_close,
            /// It starts with the bracket, at another indentation than
            /// the line that opened the bracket.
            closure_indent,
        };
    };

    pub const LexError = enum {
        none,
        bad_char,
        unterminated_string,
        tab_indent,
        bad_dedent,
        first_line_indented,
        indent_too_deep,
        nesting_too_deep,
        islands_too_deep,
        and_operator,
        or_operator,
        or_fallback,
        power_operator,
        increment,
        decrement,
        slash_comment,
        receiver_dot,
        dollar_detached,
        dollar_stray,
        label_keyword,
        label_decl,
        label_touch,
        symbol_detached,
        symbol_name,
        symbol_long,
        control_in_string,
        lone_cr,
        leading_zero,
        radix_case,
        bad_number,
        fixed_touch,
        detached_prefix,
        semicolon,
        brace,
        two_markers,
        repeated_marker,
        marker_before_pub,

        pub fn message(e: LexError) []const u8 {
            return switch (e) {
                .none => "invalid token",
                .bad_char => "invalid character",
                .unterminated_string => "unterminated string",
                .control_in_string => "control character in a string; write it as an escape (`\\t`, `\\n`) in a double-quoted string",
                .lone_cr => "carriage return without a line feed; end lines with `\\n` or `\\r\\n`",
                .leading_zero => "a decimal number has no leading zero",
                .radix_case => "radix prefixes are lowercase: `0x`, `0b`, `0o`",
                .bad_number => "malformed number; `_` may separate digits, and a space or an operator ends a number",
                .fixed_touch => "`=!` needs a space after it: write `x =! y` for a fixed binding, or `x = !y` to lend `y` to write",
                .detached_prefix => "a prefix sigil touches its operand",
                .semicolon => "unexpected `;`",
                .brace => "Rig has no braces: a block is the lines indented under its header",
                .tab_indent => "tab in indentation; indent with spaces",
                .bad_dedent => "indentation does not match any enclosing block",
                .first_line_indented => "unexpected indentation",
                .indent_too_deep => "indentation is nested too deeply",
                .nesting_too_deep => "brackets are nested too deeply",
                .islands_too_deep => "closures laid out inside brackets are nested too deeply",
                .and_operator => "`&&` is not a Rig operator; use `and`",
                .or_operator => "`||` is not a Rig operator; use `or`, or `??` for an optional's fallback",
                .or_fallback => "`||` is not a Rig operator; a fallback value for an optional is written with `??`: `x ?? 0`",
                .power_operator => "`**` is not a Rig operator",
                .increment => "Rig has no `++`; write `x += 1`",
                .decrement => "Rig has no `--`; write `x -= 1`",
                .slash_comment => "comments start with `#`; Rig has no `//` or `/* */` comments",
                .receiver_dot => "a member of self is written `@name`, the name touching the `@`",
                .dollar_detached => "`$` touches the name after it: a builtin call is written `$size(T)`, a label `$outer:` (`break $outer`)",
                .dollar_stray => "`$name` is a builtin call, `$size(T)`, with the name touching its `(`, or a label: `$outer:` where a statement starts, and `break $outer` or `continue $outer`",
                .label_keyword => "a keyword is not a label name",
                .label_decl => "a label is declared with a `:` touching its name: `$outer: for ...`, or `$outer:` on a line of its own over the block it names",
                .label_touch => "a jump's label ends at its name: put a space before the value, `break $outer -1`",
                .symbol_detached => "a prefix `:` touches its operand: a symbol is written `:width`",
                .symbol_name => "a symbol is `:` and a name: `:width`, `:content-type`",
                .symbol_long => "a symbol's name is too long",
                .marker_before_pub => "`pub` comes before a function's marker: write `pub inline fun` or `pub called fun`",
                .repeated_marker => "a function's marker is written once",
                .two_markers => "a function takes one marker: `inline` (inline it at every call) or `called` (keep every call a call), which contradict each other",
            };
        }
    };

    pub fn init(source: []const u8) Lexer {
        var lexer: Lexer = .{ .base = BaseLexer.init(source) };
        if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) lexer.base.pos = 3; // a UTF-8 byte order mark
        return lexer;
    }

    pub fn next(self: *Lexer) Token {
        const tok = self.produce();
        self.after_label = tok.cat == .label_colon;
        self.label_name = self.label_sigil and tok.cat == .ident;
        self.label_sigil = tok.cat == .label and !isLabelJump(self.last_cat);
        self.after_jump_label = tok.cat == .ident and self.last_cat == .label and isLabelJump(self.last2_cat);
        self.after_value = !self.label_name and !self.after_jump_label and (isValue(tok.cat) or (self.after_value and (tok.cat == .question or tok.cat == .not_sym)));
        self.last2_cat = self.last_cat;
        self.last_cat = tok.cat;
        switch (tok.cat) {
            .newline, .indent, .outdent => {
                self.line_opens = false;
                self.line_match = false;
            },
            else => {},
        }
        switch (tok.cat) {
            .@"while" => self.while_header = self.nesting,
            .newline, .indent, .outdent, .eof, .step_colon => self.while_header = null,
            else => {},
        }
        if (tok.len > 0 and tok.cat != .err) { // a real token, not layout
            self.before_cat = self.prev_cat;
            self.before_pos = self.prev_pos;
            self.prev_cat = tok.cat;
            self.prev_pos = tok.pos;
            self.prev_end = endOf(&self.base, tok);
        }
        if (self.closed_bars) {
            self.closed_bars = false;
            if (self.nesting > 0 and !self.inIsland() and self.lineEndsAfter()) {
                if (self.island_count == max_islands) return self.fail(.islands_too_deep, tok.pos);
                const column = self.lineIndent(tok.pos);
                self.islands[self.island_count] = .{ .nesting = self.nesting, .depth = self.depth, .column = column, .outer_column = self.column };
                self.island_count += 1;
                self.column = column;
            }
        }
        return tok;
    }

    /// Newlines at the current bracket depth are layout: the innermost
    /// island is open at this depth.
    fn inIsland(self: *const Lexer) bool {
        return self.island_count > 0 and self.islands[self.island_count - 1].nesting == self.nesting;
    }

    /// Nothing but a comment follows on the current line.
    fn lineEndsAfter(self: *const Lexer) bool {
        var probe = self.base;
        var t = probe.next();
        if (t.cat == .comment) t = probe.next();
        return t.cat == .newline or t.cat == .eof;
    }

    /// Indentation of the line containing `pos`.
    fn lineIndent(self: *const Lexer, pos: u32) u32 {
        var start = pos;
        while (start > 0 and self.base.source[start - 1] != '\n') start -= 1;
        var p = start;
        while (p < self.base.source.len and self.base.source[p] == ' ') p += 1;
        return p - start;
    }

    /// Close the innermost island: its open blocks end here. Returns the
    /// first OUTDENT, with the rest pending and `after` held back, or
    /// null when no block was open.
    fn closeIsland(self: *Lexer, pos: u32, after: ?Token) ?Token {
        self.island_count -= 1;
        const island = self.islands[self.island_count];
        const open = self.depth - island.depth;
        self.depth = island.depth;
        self.column = island.outer_column;
        if (open == 0) return null;
        self.pending_outdents = open - 1;
        self.pending_pos = pos;
        self.pending_newline = false;
        self.pending_token = after;
        return synthetic(.outdent, pos);
    }

    fn produce(self: *Lexer) Token {
        if (self.pending_outdents > 0) {
            self.pending_outdents -= 1;
            return synthetic(.outdent, self.pending_pos);
        }
        if (self.pending_newline) {
            self.pending_newline = false;
            return synthetic(.newline, self.pending_pos);
        }
        if (self.pending_token) |t| {
            self.pending_token = null;
            return self.classify(t);
        }
        if (self.member_dot) |pos| {
            self.member_dot = null;
            return synthetic(.dot, pos);
        }

        while (true) {
            const tok = self.base.next();
            switch (tok.cat) {
                .comment => continue,
                .skip => continue, // `\` line continuation
                .newline => {
                    if (!self.inIsland() and (self.nesting > 0 or self.last_cat == .eof)) continue;
                    return self.lineBreak(tok);
                },
                .eof => return self.endOfInput(tok),
                else => {},
            }
            if (self.last_cat == .eof and tok.pre > 0) return self.firstLineIndented(tok);
            if (self.crossesFile(tok.pos)) {
                if (self.nesting > 0) return self.endOfFile();
                if (self.last_cat != .eof) {
                    // The file ended with no line break (a `\` before its
                    // end): its last line ends there.
                    return self.lineBreak(synthetic(.newline, self.ends[self.file]));
                }
                // The files before this token hold none.
                while (self.crossesFile(tok.pos)) self.file += 1;
            }
            return self.classify(tok);
        }
    }

    fn synthetic(cat: TokenCat, pos: u32) Token {
        return .{ .cat = cat, .pre = 0, .pos = pos, .len = 0 };
    }

    fn fail(self: *Lexer, e: LexError, pos: u32) Token {
        self.err = e;
        return .{ .cat = .err, .pre = 0, .pos = pos, .len = 0 };
    }

    /// The first token of the file is indented: with a tab, or spaces.
    fn firstLineIndented(self: *Lexer, tok: Token) Token {
        const src = self.base.source;
        var start = tok.pos;
        while (start > 0 and (src[start - 1] == ' ' or src[start - 1] == '\t')) start -= 1;
        if (std.mem.findScalar(u8, src[start..tok.pos], '\t')) |tab| return self.fail(.tab_indent, start + @as(u32, @intCast(tab)));
        return self.fail(.first_line_indented, tok.pos);
    }

    // -------------------------------------------------------------------------
    // Layout
    // -------------------------------------------------------------------------

    /// A newline outside brackets: find the next line with content and
    /// turn its indentation into NEWLINE, INDENT, or OUTDENTs.
    fn lineBreak(self: *Lexer, nl: Token) Token {
        const src = self.base.source;
        var line: u32 = endOf(&self.base, nl);
        while (true) {
            var p = line;
            var tab: ?u32 = null;
            while (p < src.len and (src[p] == ' ' or src[p] == '\t')) : (p += 1) {
                if (src[p] == '\t' and tab == null) tab = p;
            }
            if (p >= src.len) {
                self.base.pos = @intCast(src.len);
                return self.endOfInput(synthetic(.eof, @intCast(src.len)));
            }
            switch (src[p]) {
                '\n' => {
                    line = p + 1;
                    continue;
                },
                '\r' => if (p + 1 < src.len and src[p + 1] == '\n') {
                    line = p + 2;
                    continue;
                },
                '#' => {
                    while (p < src.len and src[p] != '\n') p += 1;
                    line = p;
                    continue;
                },
                else => {},
            }
            if (tab) |t| return self.fail(.tab_indent, t);
            if (self.crossesFile(p)) {
                if (self.nesting > 0) return self.endOfFile();
                self.file += 1;
                while (self.crossesFile(p)) self.file += 1;
                if (p > line) return self.fail(.first_line_indented, @intCast(p));
                // A block of the file before closes; no `else` continues it.
                self.takes_else = @splat(false);
            }
            self.base.pos = line;
            // Back at the closure's own line: the island ends and the
            // bracketed expression continues.
            if (self.inIsland() and p - line <= self.islands[self.island_count - 1].column) {
                self.checkIslandClose(p, p - line);
                return self.closeIsland(p, null) orelse self.produce();
            }
            if (p - line > self.column and self.continuesChain(src, p)) {
                self.base.pos = @intCast(p);
                return self.produce();
            }
            return self.indentTo(p - line, p, nl);
        }
    }

    /// The line at `p`, indented deeper than its statement, starts with
    /// a member access (`.name`) and continues the expression statement
    /// above it. That statement is complete (its last token ends an
    /// operand) and its line opens no block (it has none of the tokens
    /// that open one), and it is not an arm or a member, whose deeper
    /// `.variant` line is the body. Blank and comment lines between two chain lines are skipped
    /// before this is asked, so they do not end the chain.
    fn continuesChain(self: *const Lexer, src: []const u8, p: usize) bool {
        if (src[p] != '.' or p + 1 >= src.len or !isIdentStart(src[p + 1])) return false;
        if (!self.after_value or self.nesting > 0 or self.line_opens) return false;
        return !self.in_members[self.depth] and !self.in_arms[self.depth];
    }

    fn indentTo(self: *Lexer, width: u32, pos: u32, nl: Token) Token {
        if (width > self.column) {
            if (self.depth == max_indent_depth) return self.fail(.indent_too_deep, pos);
            self.levels[self.depth] = self.column;
            self.depth += 1;
            self.column = width;
            self.takes_else[self.depth] = false;
            self.in_arms[self.depth] = self.line_match;
            self.in_members[self.depth] = switch (self.line_head) {
                .obj, .api, .add => true,
                else => false,
            } or switch (self.line_head) {
                .@"enum", .@"error" => true,
                else => false,
            };
            return synthetic(.indent, pos);
        }
        if (width == self.column) {
            self.takes_else[self.depth] = false;
            return nl;
        }

        var closed: u32 = 0;
        while (self.column > width) {
            if (self.depth == 0) return self.fail(.bad_dedent, pos);
            self.depth -= 1;
            self.column = self.levels[self.depth];
            closed += 1;
        }
        if (self.column != width) return self.fail(.bad_dedent, pos);

        self.pending_outdents = closed - 1;
        self.pending_pos = pos;
        if (self.takes_else[self.depth] and self.startsWithElse(pos)) {
            self.pending_newline = false;
        } else {
            self.pending_newline = true;
            self.takes_else[self.depth] = false;
        }
        return synthetic(.outdent, pos);
    }

    /// The line at `pos` starts with `else`, which continues the block
    /// that just closed, so no NEWLINE separates them.
    fn startsWithElse(self: *const Lexer, pos: u32) bool {
        var probe = self.base;
        probe.pos = pos;
        const tok = probe.next();
        return tok.cat == .@"else";
    }

    /// Whether `pos` is past the end of the file being read.
    fn crossesFile(self: *const Lexer, pos: usize) bool {
        return self.file < self.ends.len and pos >= self.ends[self.file];
    }

    /// The file being read ends inside a bracket: the input ends there,
    /// and no token of the next file is read.
    fn endOfFile(self: *Lexer) Token {
        const end = self.ends[self.file];
        self.base.pos = @intCast(self.base.source.len);
        return self.endOfInput(synthetic(.eof, end));
    }

    fn endOfInput(self: *Lexer, eof: Token) Token {
        if (self.depth > 0) {
            self.pending_outdents = self.depth - 1;
            self.pending_pos = eof.pos;
            self.depth = 0;
            self.column = 0;
            return synthetic(.outdent, eof.pos);
        }
        return eof;
    }

    // -------------------------------------------------------------------------
    // Classification
    // -------------------------------------------------------------------------

    fn classify(self: *Lexer, tok: Token) Token {
        if (self.symbol_name) {
            self.symbol_name = false;
            return self.symbolName(tok);
        }
        // The bracket around an island closes on the body's last line:
        // so do the island's blocks. The bracket belongs on a line of its
        // own.
        if ((tok.cat == .rparen or tok.cat == .rbracket) and self.inIsland()) {
            const kind: Layout.Kind = if (self.startsLine(tok)) .closure_indent else .closure_hanging;
            self.recordLayout(.{ .pos = tok.pos, .len = 1, .kind = kind, .column = self.lineIndent(self.brackets[self.nesting - 1]) });
            if (self.closeIsland(tok.pos, tok)) |outdent| return outdent;
        }
        const after_value = self.after_value;
        var out = tok;
        out.cat = switch (tok.cat) {
            .ident => if (self.misplacedMarker(tok)) |bad| return self.fail(bad.err, bad.pos) else self.classifyWord(tok),
            .lparen, .lbracket => blk: {
                if (self.nesting == max_nesting) return self.fail(.nesting_too_deep, tok.pos);
                self.brackets[self.nesting] = tok.pos;
                self.nesting += 1;
                break :blk tok.cat;
            },
            .rparen, .rbracket => blk: {
                if (self.nesting > 0) self.nesting -= 1;
                break :blk tok.cat;
            },
            .at => if (self.receiverMember(tok)) |err| return self.fail(err, tok.pos) else .ident,
            .dollar => switch (self.classifyDollar(tok)) {
                .cat => |cat| cat,
                .err => |err| return self.fail(err, tok.pos),
            },
            .bar => if (self.isCaptureBar(tok, after_value)) .bar_capture else .bar,
            .and_sym => return self.fail(.and_operator, tok.pos),
            // `||` where an operand starts is an empty closure bar list.
            .or_sym => if (!after_value) blk: {
                self.closed_bars = true;
                break :blk .bar_empty;
            } else return self.fail(if (self.literalFollows()) .or_fallback else .or_operator, tok.pos),
            .slash => if (self.charAfter(tok) == '/' or self.charAfter(tok) == '*') return self.fail(.slash_comment, tok.pos) else .slash,
            .power => return self.fail(.power_operator, tok.pos),
            // `x =!y`: a fixed binding of `y`, or `x = !y`, a write lend?
            .fixed_assign => if (!isBlank(self.charAfter(tok))) return self.fail(.fixed_touch, tok.pos) else tok.cat,
            // `xs[a..]`: an open range ends at the `]`.
            .dotdot => if (self.nextJoined().cat == .rbracket) .dotdot_open else .dotdot,
            .colon => if (self.label_name) .label_colon else switch (self.classifyColon(tok, after_value)) {
                .cat => |cat| cat,
                .err => |err| return self.fail(err.err, err.pos),
            },
            // `get(k) ?? return none`: a jump as the fallback.
            .nullish => if (self.nextIsJump()) .nullish_jump else .nullish,
            .ampersand => if (self.isTaskAmp(tok)) .task_amp else .ampersand,
            // `if f() as a, b`: a `,` after `as name` outside brackets
            // joins the names `as` binds. Inside brackets a `,` after
            // `x as a` separates arguments or elements.
            .comma => if (self.nesting == 0 and self.last_cat == .ident and (self.last2_cat == .as or self.last2_cat == .as_comma)) .as_comma else .comma,
            .err => return self.lexError(tok),
            else => if (isKeyword(tok.cat)) self.classifyKeyword(tok) else tok.cat,
        };
        // A jump's label ends at its name: a value after it stands apart
        // (`break $outer -1`, not `break $outer-1`).
        if (self.after_jump_label and tok.pos == self.prev_end and startsOperand(tok.cat)) return self.fail(.label_touch, tok.pos);
        // A prefix sigil touches its operand (`-b`, `<x`, `*T`); `i++`
        // is no increment.
        if (!after_value and isSigil(tok.cat) and isSpace(self.charAfter(tok))) {
            const twice = tok.pos > 0 and self.base.source[tok.pos - 1] == self.base.source[tok.pos];
            if (twice and tok.cat == .plus) return self.fail(.increment, tok.pos - 1);
            if (twice and tok.cat == .minus) return self.fail(.decrement, tok.pos - 1);
            return self.fail(.detached_prefix, tok.pos);
        }
        if (self.layout_count < max_layouts) self.checkSpacing(tok, out.cat, after_value);
        switch (out.cat) {
            .@"if", .@"while", .@"for" => self.takes_else[self.depth] = true,
            else => {},
        }
        switch (out.cat) {
            .fun, .sub, .@"enum", .@"error", .@"if", .@"else", .@"while", .@"for", .match, .@"test", .raw, .@"extern", .drop, .obj, .api, .add => self.line_opens = true,
            else => {},
        }
        if (out.cat == .match) self.line_match = true;
        if (self.stmtStart() or self.last_cat == .@"pub") {
            self.line_head = out.cat;
            self.head_pos = tok.pos;
        }
        return out;
    }

    /// Record the first operator whose spacing breaks the rule:
    /// `after_value` says the token follows an operand, so it continues
    /// it (an infix operator, a postfix, a member `.`).
    fn checkSpacing(self: *Lexer, tok: Token, cat: TokenCat, after_value: bool) void {
        const src = self.base.source;
        const before = tok.pos > 0 and isSpaceBefore(src[tok.pos - 1]);
        const after = isSpace(self.charAfter(tok));
        const kind: ?Layout.Kind = switch (cat) {
            .question, .not_sym => if (after_value and before) .postfix else null,
            // A member may start a line inside brackets, continuing a
            // chain from the line before.
            .dot => if (after_value) (if ((before and !self.startsLine(tok)) or after) .member else null) else if (after) .enum_dot else null,
            .dotdot, .dotdot_eq => if (!after_value) (if (after) .range_end else null) else if (before != after) (if (before) .infix_before else .infix_after) else null,
            .dotdot_open => if (after_value and before) .range_end else null,
            .lparen, .lbracket => if (after_value and before and !self.startsLine(tok)) .call_bracket else null,
            else => if (after_value and isInfix(cat) and before != after) (if (before) .infix_before else .infix_after) else null,
        };
        if (kind) |k| self.recordLayout(.{ .pos = tok.pos, .len = endOf(&self.base, tok) - tok.pos, .kind = k });
    }

    fn recordLayout(self: *Lexer, layout: Layout) void {
        if (self.layout_count == max_layouts) return;
        self.layouts[self.layout_count] = layout;
        self.layout_count += 1;
    }

    /// The line at `pos`, `width` deep, ends a closure body laid out in
    /// the innermost island: it starts with the bracket around the body,
    /// at the indentation of the line that opened that bracket.
    fn checkIslandClose(self: *Lexer, pos: u32, width: u32) void {
        const open = self.brackets[self.nesting - 1];
        const closer: u8 = if (self.base.source[open] == '(') ')' else ']';
        const want = self.lineIndent(open);
        if (self.base.source[pos] != closer) {
            self.recordLayout(.{ .pos = pos, .len = 1, .kind = .closure_close, .column = want });
        } else if (width != want) {
            self.recordLayout(.{ .pos = pos, .len = 1, .kind = .closure_indent, .column = want });
        }
    }

    /// Only whitespace stands before `tok` on its line.
    fn startsLine(self: *const Lexer, tok: Token) bool {
        var p = tok.pos;
        while (p > 0) : (p -= 1) switch (self.base.source[p - 1]) {
            ' ', '\t', '\r' => {},
            '\n' => return true,
            else => return false,
        };
        return true;
    }

    /// `catch` before a jump, after any `|e|` (`f() catch return -1`),
    /// is CATCH_JUMP, whose handler takes the rest of the expression;
    /// before `|e|` and the end of the line, CATCH_BLOCK, whose handler
    /// is the block below; any other is CATCH, an operator on `??`'s
    /// level.
    fn catchCat(self: *const Lexer) TokenCat {
        var probe = self.base;
        var t = probe.next();
        var bars = false;
        if (t.cat == .bar) {
            _ = probe.next();
            if (probe.next().cat != .bar) return .@"catch";
            t = probe.next();
            bars = true;
        }
        return switch (t.cat) {
            .@"return", .@"break", .@"continue" => .catch_jump,
            .newline, .comment, .eof => if (bars) .catch_block else .@"catch",
            else => .@"catch",
        };
    }

    fn classifyKeyword(self: *const Lexer, tok: Token) TokenCat {
        const kw = tok.cat;
        if (kw != .@"if") return self.memberName(tok) orelse if (kw == .@"catch") self.catchCat() else kw;
        switch (self.last_cat) {
            .@"return", .@"break", .@"continue", .pass => return .post_if,
            else => {},
        }
        if (self.after_jump_label) return .post_if;
        if (!self.after_value) return .@"if";
        return if (self.elseFollows()) .ternary_if else .post_if;
    }

    fn classifyWord(self: *const Lexer, tok: Token) TokenCat {
        const word = self.base.text(tok);
        // A name before `:` inside ( ) names a keyword argument or a
        // payload field, `new` too (`O(new: 1)`, `.pp(new: x)`).
        if (self.argNameNext(tok)) return .kwarg_name;
        if (std.mem.eql(u8, word, "new")) return if (self.stmtStart() and self.nextIsName()) .new else .ident;
        if (std.mem.eql(u8, word, "of") and self.isFillOf()) return .of;
        if (std.mem.eql(u8, word, "obj")) return if ((self.stmtStart() or self.last_cat == .@"pub") and self.nextIsName()) .obj else .ident;
        // `api` and `add` start a module-level declaration, and are
        // names everywhere else: `user.api`, `!set.add(x)`, `add = 2`.
        if (std.mem.eql(u8, word, "api")) return if (self.moduleDeclStart(true) and self.nextIsName()) .api else .ident;
        if (std.mem.eql(u8, word, "add")) return if (self.moduleDeclStart(true) and self.nextStartsType()) .add else .ident;
        if (isMarker(word)) {
            if (!(self.stmtStart() or self.last_cat == .@"pub") or !self.nextIsFunOrSub()) return .ident;
            return if (word[0] == 'i') .@"inline" else .called;
        }
        // `rarely` alone on its line starts the block it marks.
        if (std.mem.eql(u8, word, "rarely")) return if (self.stmtStart() and self.nextEndsLine()) .rarely else .ident;
        return .ident;
    }

    /// The next token ends the line: a newline, a comment, or the end.
    fn nextEndsLine(self: *const Lexer) bool {
        var probe = self.base;
        return switch (probe.next().cat) {
            .newline, .comment, .eof => true,
            else => false,
        };
    }

    /// The next token is `fun` or `sub`: a function's marker (`inline`,
    /// `called`) stands right before it.
    fn nextIsFunOrSub(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.next();
        return t.cat == .fun or t.cat == .sub;
    }

    /// A marker `tok` puts where a declaration cannot take it: a second
    /// one (`inline called fun f()`), since a function takes one, the same
    /// one again (`inline inline fun f()`), or one before `pub`
    /// (`inline pub fun f()`), which comes first.
    fn misplacedMarker(self: *const Lexer, tok: Token) ?struct { err: LexError, pos: u32 } {
        if (!isMarker(self.base.text(tok)) or !(self.stmtStart() or self.last_cat == .@"pub")) return null;
        var probe = self.base;
        const second = probe.next();
        const second_marks = second.cat == .ident and isMarker(probe.text(second));
        const t = if (second.cat == .@"pub" or second_marks) probe.next() else second;
        if (t.cat != .fun and t.cat != .sub) return null;
        if (second.cat == .@"pub") return .{ .err = .marker_before_pub, .pos = tok.pos };
        if (!second_marks) return null;
        const same = std.mem.eql(u8, probe.text(second), self.base.text(tok));
        return .{ .err = if (same) .repeated_marker else .two_markers, .pos = second.pos };
    }

    fn isMarker(word: []const u8) bool {
        return std.mem.eql(u8, word, "inline") or std.mem.eql(u8, word, "called");
    }

    /// `of` after a value directly inside [ ] separates a fill literal's
    /// count from its element (`[n of x]`); anywhere else it is a name.
    fn isFillOf(self: *const Lexer) bool {
        return self.after_value and self.nesting > 0 and !self.inIsland() and
            self.base.source[self.brackets[self.nesting - 1]] == '[';
    }

    /// A keyword names a member where nothing else can stand: after
    /// `.`, before `:` inside ( ) (a keyword argument or payload field),
    /// and in a member list before `:` (a field) or after `fun` / `sub`
    /// (a method). After `$` it names a builtin (`$type(x)`).
    fn memberName(self: *const Lexer, tok: Token) ?TokenCat {
        switch (self.last_cat) {
            .dot, .dollar => return .ident,
            .fun, .sub => return if (self.in_members[self.depth]) .ident else null,
            else => {},
        }
        if (self.nextCat() != .colon) return null;
        if (self.inParens()) return if (self.argNameNext(tok)) .kwarg_name else null;
        return if (self.in_members[self.depth] and (self.stmtStart() or self.last_cat == .@"pub")) .ident else null;
    }

    /// `word` names a keyword argument, a payload field, or a parameter:
    /// it stands directly inside ( ) where an argument starts, right
    /// after `(`, `,`, or a closure's opening bar, and a `:` follows it
    /// (`f(a: 1)`, `O(new: 1)`, `K(break : 3)`). A `:` with a space before
    /// it and a name touching it starts a symbol instead (`f(not :a)`).
    fn argNameNext(self: *const Lexer, word: Token) bool {
        if (!self.inParens()) return false;
        switch (self.last_cat) {
            .lparen, .comma, .bar_capture => {},
            else => return false,
        }
        var probe = self.base;
        const colon = probe.next();
        if (colon.cat != .colon) return false;
        if (colon.pos == endOf(&self.base, word)) return true;
        const after = endOf(&probe, colon);
        return after >= self.base.source.len or !isIdentStart(self.base.source[after]);
    }

    /// What a `:` is, decided once, by where it stands:
    ///
    ///   * the step of a `while` header, at the header's bracket depth,
    ///     after a value or a jump (`while i < n : i += 1`,
    ///     `while a ?? break : i += 1`);
    ///   * the `:` of a type, a field, or a keyword argument after a
    ///     value anywhere else (`x: Int`, `f(a: 1)`);
    ///   * a symbol's `:` where an operand starts, touching its name
    ///     (`x = :width`, `:a =>`).
    fn classifyColon(self: *Lexer, tok: Token, after_value: bool) union(enum) { cat: TokenCat, err: struct { err: LexError, pos: u32 } } {
        const jump_end = self.after_jump_label or switch (self.last_cat) {
            .@"return", .@"break", .@"continue" => true,
            else => false,
        };
        if (self.while_header == self.nesting and (after_value or jump_end)) return .{ .cat = .step_colon };
        if (after_value or self.last_cat == .kwarg_name) return .{ .cat = .colon };
        const end = endOf(&self.base, tok);
        const src = self.base.source;
        const touches = end < src.len and isIdentStart(src[end]);
        if (!touches) return .{ .err = .{ .err = if (end >= src.len or isBlank(src[end])) .symbol_detached else .symbol_name, .pos = tok.pos } };
        self.symbol_name = true;
        return .{ .cat = .symbol_colon };
    }

    /// The name after a symbol's `:`, a keyword too (`:if`): a word,
    /// then runs of `-` or `.` each followed by a letter, digit, or `_`
    /// (`:content-type`, `:utf-8`, `:a.b`). It stops at `..`, at a `-`
    /// or `.` with no name character after it, and at a space.
    fn symbolName(self: *Lexer, tok: Token) Token {
        const src = self.base.source;
        var end: usize = endOf(&self.base, tok);
        while (end + 1 < src.len and (src[end] == '-' or src[end] == '.') and isIdentCont(src[end + 1])) {
            end += 2;
            while (end < src.len and isIdentCont(src[end])) end += 1;
        }
        if (end - tok.pos >= std.math.maxInt(u16)) return self.fail(.symbol_long, tok.pos);
        self.base.pos = @intCast(end);
        var out = tok;
        out.cat = .ident;
        out.len = @intCast(end - tok.pos);
        return out;
    }

    /// `@` is self, a name, and `@name` its member `name`: an
    /// `@` touching a name is followed by a `.` before it, which the
    /// next call returns (`member_dot`). Self's member is never written
    /// `@.name`.
    fn receiverMember(self: *Lexer, at: Token) ?LexError {
        var probe = self.base;
        const after = probe.next();
        if (after.pos != endOf(&self.base, at)) return null;
        if (after.cat == .dot) return .receiver_dot;
        if (isWord(after.cat)) self.member_dot = after.pos;
        return null;
    }

    /// `$name(...)` is a builtin call, anywhere: the `$` touches the
    /// name, and the name the `(`. Any other `$name` is a label: declared
    /// where a statement that takes one starts, its `:` touching the name
    /// (`$outer: for`, or `$outer:` on a line of its own over the block
    /// it names), and named after `break` or `continue` (`break $outer`,
    /// `break $outer (x)`, which leaves `outer` with the value `(x)`).
    fn classifyDollar(self: *const Lexer, dollar: Token) union(enum) { cat: TokenCat, err: LexError } {
        var probe = self.base;
        const name = probe.next();
        const after = probe.next();
        if (!isWord(name.cat) or name.pos != endOf(&self.base, dollar)) return .{ .err = .dollar_detached };
        const touches = after.pos == endOf(&probe, name);
        if (after.cat == .lparen and touches) return .{ .cat = .dollar };
        const jump = isLabelJump(self.last_cat);
        if (!jump and !self.labelStart()) return .{ .err = .dollar_stray };
        if (name.cat != .ident) return .{ .err = .label_keyword };
        if (!jump and (after.cat != .colon or !touches)) return .{ .err = .label_decl };
        return .{ .cat = .label };
    }

    /// The character right after `tok`, or 0 at the end of the source.
    fn charAfter(self: *const Lexer, tok: Token) u8 {
        const end = endOf(&self.base, tok);
        return if (end < self.base.source.len) self.base.source[end] else 0;
    }

    /// A `|` that starts an operand opens a closure's bar list:
    /// `entry (, entry)* [,]` and a closing bar. An entry is a sigiled
    /// capture (`+x`, `<x`, `~x`, `?x`, `!x`) or a parameter name with
    /// an optional type (`a`, `a: Int`, `f: *fun(Int) -> Int`). The
    /// closing bar is the one this probe finds.
    fn isCaptureBar(self: *Lexer, tok: Token, after_value: bool) bool {
        if (self.capture_close) |close| if (close == tok.pos) {
            self.capture_close = null;
            self.closed_bars = true;
            return true;
        };
        if (after_value) return false;
        var probe = self.base;
        while (true) {
            var t = probe.next();
            if (t.cat == .plus or t.cat == .lt or t.cat == .tilde or t.cat == .question or t.cat == .not_sym) t = probe.next();
            // A keyword entry still makes a bar list, so that the parser
            // reports the keyword (`|when: Int|`). Self, `@`, is a
            // name (`|?@|`).
            if (!isWord(t.cat) and t.cat != .at) return true;
            var sep = probe.next();
            // A capture's place: `@name`, then `.name` steps, and an
            // index or call the Parser wrapper rejects (`|?xs[0]|`).
            if (t.cat == .at and isWord(sep.cat) and sep.pos == t.pos + t.len) sep = probe.next();
            while (true) switch (sep.cat) {
                .dot => {
                    if (!isWord(probe.next().cat)) return true;
                    sep = probe.next();
                },
                .lbracket, .lparen => {
                    var depth: u32 = 1;
                    while (depth > 0) {
                        const b = probe.next();
                        switch (b.cat) {
                            .lbracket, .lparen => depth += 1,
                            .rbracket, .rparen => depth -= 1,
                            .eof, .newline => return true,
                            else => {},
                        }
                    }
                    sep = probe.next();
                },
                else => break,
            };
            if (sep.cat == .colon) sep = skipType(&probe) orelse return true;
            switch (sep.cat) {
                .bar => {
                    self.capture_close = sep.pos;
                    return true;
                },
                .comma => {
                    var after = probe;
                    const close = after.next();
                    if (close.cat == .bar) {
                        self.capture_close = close.pos;
                        return true;
                    }
                },
                else => return true,
            }
        }
    }

    /// Skip a parameter type in a bar list; returns the token after it
    /// (a `,` or `|` outside brackets), or null if the tokens cannot be a
    /// type.
    fn skipType(probe: *BaseLexer) ?Token {
        var depth: u32 = 0;
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    if (depth == 0) return null;
                    depth -= 1;
                },
                .comma, .bar => if (depth == 0) return t,
                .ident, .integer, .dot, .question, .not_sym, .star, .tilde, .caret, .arrow => {},
                // Arithmetic in an array size: `[N + 1]Int`.
                .plus, .minus, .slash, .percent => if (depth == 0) return null,
                else => if (!isKeyword(t.cat)) return null,
            }
        }
    }

    /// Scan ahead on the current logical line for an `else` at this
    /// nesting level (the ternary form `a if c else b`).
    fn elseFollows(self: *const Lexer) bool {
        var probe = self.base;
        var depth: u32 = 0;
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .eof => return false,
                .newline => if (depth == 0 and (self.nesting == 0 or self.inIsland())) return false,
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    if (depth == 0) return false;
                    depth -= 1;
                },
                .comma => if (depth == 0) return false,
                .@"else" => if (depth == 0) return true,
                else => {},
            }
        }
    }

    /// A statement starts here: at the start of a line, after `=>`,
    /// `defer`, or `errdefer`, or after a statement's label (`$outer:`).
    fn stmtStart(self: *const Lexer) bool {
        return self.after_label or switch (self.last_cat) {
            .newline, .indent, .outdent, .eof, .fat_arrow, .@"defer", .@"errdefer" => true,
            else => false,
        };
    }

    /// A statement that may take a label starts here: at the start of a
    /// line, or after another label. The statement after `=>`, `defer`,
    /// or `errdefer` takes none.
    fn labelStart(self: *const Lexer) bool {
        return self.after_label or switch (self.last_cat) {
            .newline, .indent, .outdent, .eof => true,
            else => false,
        };
    }

    /// Directly inside ( ), not in a closure body laid out there.
    fn inParens(self: *const Lexer) bool {
        return self.nesting > 0 and !self.inIsland() and self.base.source[self.brackets[self.nesting - 1]] == '(';
    }

    fn nextCat(self: *const Lexer) TokenCat {
        var probe = self.base;
        return probe.next().cat;
    }

    /// The next token, past comments, `\` line joins, and line breaks
    /// where they are whitespace (inside brackets).
    fn nextJoined(self: *const Lexer) Token {
        var probe = self.base;
        const joins = self.nesting > 0 and !self.inIsland();
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .comment, .skip => continue,
                .newline => if (!joins) return t,
                else => return t,
            }
        }
    }

    /// `f(x)&`: a `&` that touches the `)` before it, with no operand
    /// touching it on the right, makes the call a task. Any other `&` is
    /// bitwise and, whose spacing is the same on both sides (`a & b`,
    /// `f()&b`).
    fn isTaskAmp(self: *const Lexer, tok: Token) bool {
        if (self.last_cat != .rparen or tok.pos != self.prev_end) return false;
        const c = self.charAfter(tok);
        return c == 0 or isSpaceBefore(c) or c == ')' or c == ']' or c == ',' or c == '#';
    }

    /// The next token is `return`, `break`, or `continue`.
    fn nextIsJump(self: *const Lexer) bool {
        return switch (self.nextJoined().cat) {
            .@"return", .@"break", .@"continue" => true,
            else => false,
        };
    }

    /// A literal comes next: a number, a string, or an array.
    fn literalFollows(self: *const Lexer) bool {
        return switch (self.nextJoined().cat) {
            .integer, .real, .string_sq, .string_dq, .lbracket => true,
            else => false,
        };
    }

    /// A declaration at the module's margin starts here: at the start of a
    /// line outside any block or bracket, or after its `pub` when
    /// `after_pub`.
    fn moduleDeclStart(self: *const Lexer, after_pub: bool) bool {
        if (self.depth != 0 or self.nesting != 0) return false;
        return (self.stmtStart() and !self.after_label) or (after_pub and self.last_cat == .@"pub");
    }

    /// A type starts next: a name, or a sigil or bracket a type may start
    /// with (`add ?Square: Shape` parses, to be rejected).
    fn nextStartsType(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.next();
        return switch (t.cat) {
            .ident => !std.mem.eql(u8, probe.text(t), "new"),
            .question, .not_sym, .star, .caret, .tilde, .lbracket, .lparen => true,
            else => false,
        };
    }

    fn nextIsName(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.next();
        return t.cat == .ident and !std.mem.eql(u8, probe.text(t), "new");
    }

    /// Why the grammar produced an `err` token.
    fn lexError(self: *Lexer, tok: Token) Token {
        const t = self.base.text(tok);
        return switch (t[0]) {
            '"', '\'' => self.stringError(tok.pos),
            '0'...'9' => self.fail(if (t.len > 1 and t[0] == '0' and std.mem.findScalar(u8, "XBO", t[1]) != null)
                .radix_case
            else if (t.len > 1 and t[0] == '0' and (std.ascii.isDigit(t[1]) or t[1] == '_'))
                .leading_zero
            else
                .bad_number, tok.pos),
            '\r' => self.fail(.lone_cr, tok.pos),
            ';' => self.fail(.semicolon, tok.pos),
            '{', '}' => self.fail(.brace, tok.pos),
            else => self.fail(.bad_char, tok.pos),
        };
    }

    /// A string starting at `open` that does not lex: a control character
    /// inside it, or no closing quote on its line.
    /// Whether the quote at `pos` follows a bare `b`, which makes a byte
    /// literal of it.
    fn afterBareB(self: *const Lexer, pos: u32) bool {
        const src = self.base.source;
        return pos > 0 and src[pos - 1] == 'b' and (pos < 2 or !isIdentCont(src[pos - 2]));
    }

    fn stringError(self: *Lexer, open: u32) Token {
        const src = self.base.source;
        const quote = src[open];
        var p = open + 1;
        while (p < src.len and src[p] != '\n') : (p += 1) {
            if (quote == '"' and src[p] == '\\' and p + 1 < src.len and src[p + 1] != '\n') {
                p += 1; // the escaped character
            } else if (src[p] == quote) {
                if (quote == '"' or p + 1 == src.len or src[p + 1] != quote) break;
                p += 1; // `''` in a single-quoted string
                continue;
            }
            const at_line_end = src[p] == '\r' and p + 1 < src.len and src[p + 1] == '\n';
            if ((src[p] < 0x20 or src[p] == 0x7f) and !at_line_end) return self.fail(.control_in_string, p);
        }
        return self.fail(.unterminated_string, open);
    }
};

/// Token categories that end an operand: a `(` / `[` / `?` / `!` or
/// another shared character after one of these continues it, as a
/// call, an index, a suffix, or an infix operator. The keyword `error`
/// ends one as the type of any error, so `error?` is its optional.
fn isValue(cat: TokenCat) bool {
    return switch (cat) {
        .ident,
        .@"error",
        .integer,
        .real,
        .string_sq,
        .string_dq,
        .true,
        .false,
        .rparen,
        .rbracket,
        .task_amp,
        => true,
        else => false,
    };
}

/// The characters that start an operand as a prefix sigil.
/// A token that starts an operand and does not continue a name: what may
/// not touch a jump's label (`break $outer-1`, `break $outer.red`).
fn startsOperand(cat: TokenCat) bool {
    return isSigil(cat) or switch (cat) {
        .lparen, .lbracket, .dot, .dotdot, .dotdot_eq, .bar, .or_sym, .at, .dollar, .string_sq, .string_dq => true,
        else => false,
    };
}

/// `break` or `continue`: the jumps that name a label.
fn isLabelJump(cat: TokenCat) bool {
    return cat == .@"break" or cat == .@"continue";
}

fn isSigil(cat: TokenCat) bool {
    return switch (cat) {
        .minus, .lt, .gt, .plus, .star, .question, .not_sym, .tilde, .caret => true,
        else => false,
    };
}

/// The infix operators, whose spacing is the same on both sides.
fn isInfix(cat: TokenCat) bool {
    return switch (cat) {
        .plus, .minus, .star, .slash, .percent, .plus_wrap, .minus_wrap, .star_wrap, .plus_sat, .minus_sat => true,
        .eq, .ne, .lt, .gt, .le, .ge, .nullish, .nullish_jump => true,
        .bar, .ampersand, .caret, .lshift, .lshift_wrap, .rshift => true,
        .assign, .fixed_assign, .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign => true,
        .amp_assign, .bar_assign, .caret_assign, .lshift_assign, .lshift_wrap_assign, .rshift_assign => true,
        .plus_wrap_assign, .minus_wrap_assign, .star_wrap_assign, .plus_sat_assign, .minus_sat_assign => true,
        else => false,
    };
}

/// Whitespace before a token.
fn isSpaceBefore(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\r', '\n' => true,
        else => false,
    };
}

/// A space or a tab: what must follow `=!`.
fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Whitespace, or the end of the line or source, after a token.
fn isSpace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\r', '\n', '\\', '#', 0 => true,
        else => false,
    };
}

pub fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

/// The name that starts at `at`.
fn identAt(src: []const u8, at: usize) []const u8 {
    var e = at;
    while (e < src.len and isIdentCont(src[e])) e += 1;
    return src[at..e];
}

fn isIdentCont(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

// =============================================================================
// Parser — post-parse rewrites and diagnostics over the generated BaseParser
// =============================================================================

/// The names of the leaves a rewrite builds that no source text holds.
const HiddenName = enum(u16) {
    /// The method every iterator declares.
    next = 0,
    /// The binding that holds a loop's source. It has a space, so no
    /// program can write it, and a message that names it says what it is.
    iterator = 1,
    /// The variable of a bare `for`, which binds nothing: `for xs` is
    /// `for _ in xs`.
    discard = 2,
    /// The type of each byte of a byte string, `[U8(65), U8(66)]`.
    u8 = 3,
    /// The method a wait calls: `>t` is `<t.wait()`, on a task or a set
    /// of tasks (`isWaitCall`).
    wait = 4,
    /// The module of the built-in types written in Rig (`Map`, `Set`),
    /// which a module that names one uses
    /// (`Parser.builtinRefs`).
    builtin_module = 5,

    fn text(self: HiddenName) []const u8 {
        return switch (self) {
            .next => "next",
            .iterator => "for iterator",
            .discard => "_",
            .u8 => "U8",
            .wait => "wait",
            .builtin_module => builtin_module_name,
        };
    }
};

/// Whether `node` is a wait, `>t`: the call the wrapper builds for it,
/// whose method is the hidden `wait` (`Parser.waitCall`).
pub fn isWaitCall(node: Sexp) bool {
    return node.isKind(.call) and isWaitMember(ir.Call.callee(node));
}

/// Whether `member` is the callee of a wait, `>t`: its name is the
/// hidden `wait`.
pub fn isWaitMember(member: Sexp) bool {
    if (!member.isKind(.member)) return false;
    const name = ir.Member.name(member);
    return name == .src and name.src.id == hidden_id_base + @intFromEnum(HiddenName.wait);
}

/// The name the module of the built-in types written in Rig has, which
/// no program can import: names starting `__rig` are the compiler's.
pub const builtin_module_name = "__rig_builtin";

/// The built-in types written in Rig, in `std/__rig_builtin.rig`: a
/// program names them with no import, and its own declaration of one
/// hides it.
pub const builtin_type_names = [_][]const u8{ "Map", "Set", "Item", "Items", "Keys", "Values", "Members" };

/// Whether `leaf` is the hidden name of the module of the built-in types
/// written in Rig (`Parser.builtinRefs`).
pub fn isBuiltinModuleLeaf(leaf: Sexp) bool {
    return leaf == .src and leaf.src.id == hidden_id_base + @intFromEnum(HiddenName.builtin_module);
}

/// The name of the binding that holds a `for` loop's source.
pub fn hiddenIteratorName() []const u8 {
    return HiddenName.iterator.text();
}

/// A leaf for a name no source text holds, at `pos` inside the `for`
/// keyword (which holds no leaf); its `id` tells `leafText` which name.
fn hiddenLeaf(pos: u32, name: HiddenName) Sexp {
    return .{ .src = .{ .pos = pos, .len = 1, .id = hidden_id_base + @intFromEnum(name) } };
}

/// The integer leaf of byte `value`, which spans `len` bytes at `pos`
/// (a string literal where a `U8` goes, or one byte of one where a
/// `[N]U8` goes) and reads as its decimal value.
fn byteLeaf(pos: u32, len: u16, value: u8) Sexp {
    return .{ .src = .{ .pos = pos, .len = len, .id = byte_id_base + value } };
}

/// Leaf ids from here to `hidden_id_base` are bytes (`byteLeaf`).
const byte_id_base: u16 = 0xFE00;

/// The id of the name of a capture of a field path (`|?p.a|`), whose leaf
/// spans the path from its sigil, so that it holds a position no other
/// leaf does (the path's root holds its own), and reads as the path.
const path_capture_id: u16 = byte_id_base - 1;

/// Whether `leaf` names a capture of a field path, `|?@template|`: the
/// capture's value is then the lend it makes (`Parser.capturePlace`).
pub fn isPathCapture(leaf: Sexp) bool {
    return leaf == .src and leaf.src.id == path_capture_id;
}

/// Each byte's value in decimal, the text of its leaf.
const byte_texts = blk: {
    @setEvalBranchQuota(100_000);
    var texts: [256][]const u8 = undefined;
    for (&texts, 0..) |*t, i| t.* = std.fmt.comptimePrint("{d}", .{i});
    break :blk texts;
};

/// Whether `leaf` is a name a rewrite built (`hiddenLeaf`), such as the
/// `next` a `for` over an iterator calls.
pub fn isHiddenLeaf(leaf: Sexp) bool {
    return leaf == .src and leaf.src.id >= hidden_id_base;
}

/// Leaf ids from here are hidden names; the lexer's are keyword ordinals.
const hidden_id_base: u16 = 0xFF00;

/// The built-in APIs a bound or a type's header names (docs/design/apis.md,
/// Stage 2). The first five are facts the compiler derives from a type's
/// parts; `Eq`, `Hash`, `Ord`, and `Print` a type may give a meaning of
/// its own by naming them on its header; the number APIs only the
/// built-in numbers provide.
pub const Api = enum {
    Copy,
    Clone,
    Owned,
    Sends,
    Syncs,
    Eq,
    Hash,
    Ord,
    Print,
    Num,
    Integer,
    Signed,
    /// What a `for` loop walks: a type that declares `next(!@) -> T?`,
    /// whose `Item` is `T` (`sema.iterItem`); derived, never named on a
    /// header.
    Iter,

    /// The API a name spells, or null.
    pub fn named(text: []const u8) ?Api {
        return std.meta.stringToEnum(Api, text);
    }

    /// Whether a type may name this API on its header to give it a meaning
    /// of its own.
    pub fn ownable(api: Api) bool {
        return switch (api) {
            .Eq, .Hash, .Ord, .Print => true,
            else => false,
        };
    }
};

/// The text of a leaf: the source it spans, or its name when the rewrite
/// built it (`hiddenLeaf`). Every pass reads a name through this.
pub fn leafText(source: []const u8, leaf: parser.Src) []const u8 {
    if (leaf.id >= hidden_id_base) return @as(HiddenName, @enumFromInt(leaf.id - hidden_id_base)).text();
    if (leaf.id >= byte_id_base) return byte_texts[leaf.id - byte_id_base];
    if (leaf.id == path_capture_id) return diag.textBetween(source, leaf.pos + 1, leafEnd(source, leaf));
    return diag.textBetween(source, leaf.pos, leafEnd(source, leaf));
}

/// Where a leaf's text ends: `pos + len`, and for a leaf of a token over
/// 65534 bytes (its `len` is 65535, `@longtokens`) the end of the token
/// the generated lexer scans from its start. That lexer keeps no state
/// between tokens, and the wrapper builds no long token, so this is the
/// end the parser kept for the token (`Parser.parseTree` checks it).
/// Every end of a leaf is read here.
pub fn leafEnd(source: []const u8, leaf: parser.Src) u32 {
    if (leaf.len < std.math.maxInt(u16) or leaf.pos >= source.len) return leaf.pos + leaf.len;
    var lx = BaseLexer.init(source);
    lx.pos = leaf.pos;
    return endOf(&lx, lx.next());
}

/// `sexp`'s span as far as its leaves tell. Keywords and punctuation are
/// not leaves, so this is a fallback for trees without the parser's
/// spans; it is empty at 0 for a node without leaves.
pub fn leafSpan(source: []const u8, sexp: Sexp) diag.Span {
    switch (sexp) {
        .src => |s| return .{ .start = s.pos, .end = leafEnd(source, s) },
        .list => {
            var out: ?diag.Span = null;
            for (sexp.items()) |c| {
                const cs = leafSpan(source, c);
                if (cs.end == 0) continue;
                out = if (out) |o| .{ .start = @min(o.start, cs.start), .end = @max(o.end, cs.end) } else cs;
            }
            return out orelse .empty;
        },
        else => return .empty,
    }
}

/// Print `tree` on one line as `Sexp.write` does, with the whole text of
/// a leaf of a token over 65534 bytes (`leafText`), which `Sexp.write`
/// does not hold.
pub fn writeTree(tree: Sexp, source: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    var stack: std.ArrayList([]const Sexp) = .empty;
    defer stack.deinit(std.heap.page_allocator);
    var s = tree;
    while (true) {
        // Whether the next item of the innermost list follows another.
        var sep = true;
        switch (s) {
            .nil => try w.writeAll("_"),
            .tag => |t| try w.writeAll(std.enums.tagName(parser.Tag, t) orelse "?"),
            .src => |x| if (x.id == path_capture_id) try w.writeAll(leafText(source, x)) else {
                try w.writeAll(diag.textBetween(source, x.pos, leafEnd(source, x)));
                if (x.id != 0) try w.print("#{d}", .{x.id});
            },
            .str => |x| try w.print("\"{s}\"", .{x}),
            .list => |l| {
                try w.writeByte('(');
                stack.append(std.heap.page_allocator, l.items()) catch return error.WriteFailed;
                sep = false;
            },
        }
        while (true) {
            if (stack.items.len == 0) return;
            const rest = &stack.items[stack.items.len - 1];
            if (rest.len > 0) {
                if (sep) try w.writeByte(' ');
                s = rest.*[0];
                rest.* = rest.*[1..];
                break;
            }
            _ = stack.pop();
            try w.writeByte(')');
            sep = true;
        }
    }
}

/// How a `for` over an iterator walks its source, which decides the
/// `while` it is rewritten into (docs/internals/INTERNALS.md, "Loops over an
/// iterator").
pub const IterSource = enum {
    /// A place the loop advances where it stands: `for x in it` and
    /// `for x in !it` are `while (!it).next() as x`.
    place,
    /// A value made here, held in a hidden binding for the whole loop.
    made,
    /// A place the loop takes (`for x in <it`), moved into the hidden
    /// binding it holds for the whole loop.
    moved,
    /// A value a method call makes, with the loop's `?` on the call's
    /// receiver by the receiver-sigil rule (`for x in ?b.each()` is
    /// `for x in (?b).each()`), held in a hidden binding as `made` is
    /// (`Parser.loopReceiverSource`).
    lent,
};

/// A `for` node to rewrite (`Parser.desugarIterLoops`), with how it
/// walks its source.
pub const IterLoop = struct { node: parser.NodeId, source: IterSource };

/// A string literal typecheck found where a `U8` or a `[N]U8` goes
/// (`Parser.byteLiterals`): the position of its leaf and its bytes.
pub const ByteLiteral = struct { pos: u32, bytes: []const u8, array: bool };

pub const Parser = struct {
    base: BaseParser,
    /// Set when parsing succeeded but the tree was rejected.
    failure: ?diag.Diagnostic = null,
    /// The definitions after the first rejected one that also leave
    /// out their parameter list, each reported, so that one run shows
    /// every header to fix.
    more_failures: std.ArrayList(diag.Diagnostic) = .empty,
    /// How many hidden parameters `padLambda` has made; each takes the
    /// next position past the end of the source, which no leaf of the
    /// source holds, so facts keyed by position stay apart.
    padded: u32 = 0,
    /// Where each hidden parameter `padLambda` made belongs: the start of
    /// its closure, so a diagnostic about it points into the closure.
    pad_homes: std.ArrayList(u32) = .empty,
    /// The node ids of the `(read place)`, `(write place)`, and
    /// `(move place)` receivers written in front of the call
    /// (`!v.push(x)`), not in parentheses.
    receiver_sigils: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// The node ids of the parameters written `f: once ?fun() -> T`,
    /// each made a `(: f type)` (`isOnceParam`).
    once_params: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// Each `rarely` that starts a body it may mark (`placeRarely`).
    placed_rarely: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// For each `for` whose `?` before its source reaches the receiver
    /// of a method call by the receiver-sigil rule
    /// (`for x in ?b.each()`), the source with the sigil there,
    /// `(?b).each()`: what the loop holds when the call makes an
    /// iterator (`IterSource.lent`).
    loop_receivers: std.AutoHashMapUnmanaged(parser.NodeId, Sexp) = .empty,
    /// The node ids of the `(share x)` and `(weak x)` whose operand has a
    /// `?` suffix inside parentheses that open right after the sigil
    /// (`*(T?)`), which the tree does not keep.
    paren_suffixes: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// The node ids of the fields and methods declared `pub`, which the
    /// member list holds without their `(pub ...)` wrapper.
    pub_members: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// The node ids of the fields declared `pub ?name: T`, which other
    /// modules read and only their own module writes (`isReadOnlyMember`).
    read_only_members: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// Where the names of the methods declared outside their type's body
    /// are (`attachMethods`).
    outside_members: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// The bounds of the type parameters written with them (`[T: Ord]`,
    /// `[K: Hash + Print]`), by where each parameter's name is: the
    /// parameter itself is left a bare name, as `[T]` (`tparamBounds`).
    bounds: std.AutoHashMapUnmanaged(u32, []const Sexp) = .empty,
    /// The methods declared outside a body that name no type of this
    /// module as it declares it (`fun Nope.m()`, `fun geo.Point.m()`),
    /// each as written, `pub` included; the checker says why.
    detached: std.ArrayList(Sexp) = .empty,
    /// The type's parameters as a method declared outside its type's
    /// body names them, by where the method's name is, for a method that
    /// bounds one of them (`fun Wrap[T: Print].show(?@)`): each a bare
    /// name, its bounds recorded by where it is (`bounds`).
    owner_bounds: std.AutoHashMapUnmanaged(u32, []const Sexp) = .empty,
    /// The bounds on associated types (`[S: Source, S.Item: Ord]`), by
    /// where the name of the parameter whose types they bound is.
    assoc_bounds: std.AutoHashMapUnmanaged(u32, []const Sexp) = .empty,

    /// How many `obj` or `enum` bodies the node being rewritten is in: a
    /// function there is a method.
    type_depth: u32 = 0,

    /// Every pass walks the tree recursively; deeper trees are rejected
    /// here instead of exhausting the stack later.
    pub const max_tree_depth = 1000;

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Parser {
        return .{ .base = BaseParser.init(alloc, source) };
    }

    /// A parser over a directory module's files joined, each but the
    /// last ending at the matching `ends` position (`Lexer.ends`).
    pub fn initFiles(alloc: std.mem.Allocator, source: []const u8, ends: []const u32) Parser {
        var p = init(alloc, source);
        const lexer = &p.base.lexer;
        lexer.ends = ends;
        // The parser read its first token as it started: the files before
        // it hold none.
        while (lexer.crossesFile(lexer.prev_pos)) lexer.file += 1;
        return p;
    }

    pub fn deinit(self: *Parser) void {
        self.base.deinit();
    }

    /// Parse and rewrite into the semantic IR. On `error.ParseError`,
    /// `diagnostic()` describes the failure.
    pub fn parseProgram(self: *Parser) !Sexp {
        const tree = try self.rewrite(try self.parseTree());
        // Spacing is checked once the source parses, so that an error in
        // the parse is the one reported.
        if (self.failure == null) {
            const lexer = &self.base.lexer;
            for (lexer.layouts[0..lexer.layout_count]) |sp| {
                if (self.afterOnce(sp)) continue;
                const d: diag.Diagnostic = .{ .severity = .@"error", .pos = sp.pos, .end = sp.pos + sp.len, .message = self.layoutMessage(sp) };
                if (self.failure == null) self.failure = d else try self.more_failures.append(self.allocator(), d);
            }
        }
        if (self.failure != null) return error.ParseError;
        return tree;
    }

    /// Whether spacing record `sp` is the sigil that starts the type after
    /// `once` in a parameter (`f: once ?fun() -> T`), where `once` is a
    /// keyword, not a value the sigil would follow.
    fn afterOnce(self: *Parser, sp: Lexer.Layout) bool {
        const src = self.base.source;
        var i = sp.pos;
        while (i > 0 and isSpace(src[i - 1])) i -= 1;
        if (i < 4 or !std.mem.eql(u8, src[i - 4 .. i], "once")) return false;
        var j = i - 4;
        if (j > 0 and (std.ascii.isAlphanumeric(src[j - 1]) or src[j - 1] == '_')) return false;
        while (j > 0 and isSpace(src[j - 1])) j -= 1;
        return j > 0 and src[j - 1] == ':';
    }

    /// Why an operator's spacing is wrong, with the text to write.
    fn layoutMessage(self: *Parser, sp: Lexer.Layout) []const u8 {
        const src = self.base.source;
        const op = src[sp.pos .. sp.pos + sp.len];
        const left = operandBefore(src, sp.pos) orelse "a";
        const right = operandAfter(src, sp.pos + sp.len) orelse "b";
        // `print -1`: a call without its parentheses.
        if (sp.kind == .infix_before and isOutputCall(left)) return self.format("`{s}` is called with parentheses: `{s}({s}{s})`", .{ left, left, op, right });
        return switch (sp.kind) {
            .infix_before => if (prefixMeaning(op)) |m|
                self.format("`{s} {s}{s}`: an operator has the same spacing on both sides; write `{s} {s} {s}` to {s}, or `{s}, {s}{s}` to {s} `{s}` as a value of its own", .{ left, op, right, left, op, right, m.infix, left, op, right, m.prefix, right })
            else if (std.mem.eql(u8, op, "..") or std.mem.eql(u8, op, "..="))
                self.format("`{s} {s}{s}`: an operator has the same spacing on both sides; write `{s}{s}{s}` or `{s} {s} {s}`", .{ left, op, right, left, op, right, left, op, right })
            else
                self.format("`{s} {s}{s}`: an operator has the same spacing on both sides; write `{s} {s} {s}`", .{ left, op, right, left, op, right }),
            .infix_after => if (std.mem.eql(u8, op, "..") or std.mem.eql(u8, op, "..="))
                self.format("`{s}{s} {s}`: an operator has the same spacing on both sides; write `{s}{s}{s}` or `{s} {s} {s}`", .{ left, op, right, left, op, right, left, op, right })
            else
                self.format("`{s}{s} {s}`: an operator has the same spacing on both sides; write `{s} {s} {s}`", .{ left, op, right, left, op, right }),
            .postfix => if (sp.pos + sp.len < src.len and !isSpace(src[sp.pos + sp.len]))
                self.format("`{s} {s}{s}`: a `{s}` after a value touches it; write `{s}{s}{s}`", .{ left, op, right, op, left, op, right })
            else
                self.format("`{s} {s}`: a postfix `{s}` touches what it follows; write `{s}{s}`", .{ left, op, op, left, op }),
            .member => self.format("a member `.` touches both sides; write `{s}.{s}`", .{ left, right }),
            .enum_dot => self.format("`.` touches the name after it; write `.{s}`", .{right}),
            .call_bracket => if (bracketAfter(src, sp.pos)) |args|
                self.format("`{s} {s}`: a call's or index's bracket touches what it follows; write `{s}{s}`", .{ left, args, left, args })
            else
                self.format("`{s} {s}`: a call's or index's bracket touches what it follows; write `{s}{s}`", .{ left, op, left, op }),
            .range_end => if (sp.pos + sp.len < src.len and src[sp.pos + sp.len] == ']')
                self.format("a range's `..` touches its only bound; write `{s}..`", .{left})
            else
                self.format("a range's `{s}` touches its only bound; write `{s}{s}`", .{ op, op, right }),
            .closure_hanging => self.format("a closure body below its bar list ends with `{s}` on a line of its own: end this line before the `{s}`, and write `{s}` on the next line at the indentation of the line that opened it (column {d}); a one-line body may instead follow the bar list on its line", .{ op, op, op, sp.column + 1 }),
            .closure_close => self.format("a closure body below its bar list ends where the `{c}` around it stands alone at the start of a line, at the indentation of the line that opened it (column {d})", .{ closerOf(src, sp), sp.column + 1 }),
            .closure_indent => self.format("write this `{s}`, which ends a closure body below its bar list, at the indentation of the line that opened it (column {d})", .{ op, sp.column + 1 }),
        };
    }

    /// The bracket that closes the island a `closure_close` ends.
    fn closerOf(src: []const u8, sp: Lexer.Layout) u8 {
        // The opening bracket is on the line at `column`'s indentation
        // above; the island's bracket is the innermost one open there.
        var depth: i32 = 0;
        var p = sp.pos;
        while (p > 0) {
            p -= 1;
            switch (src[p]) {
                ')', ']' => depth += 1,
                '(', '[' => {
                    if (depth == 0) return if (src[p] == '(') ')' else ']';
                    depth -= 1;
                },
                else => {},
            }
        }
        return ')';
    }

    const Meaning = struct { infix: []const u8, prefix: []const u8 };

    /// What an operator that is also a prefix sigil does in each place.
    fn prefixMeaning(op: []const u8) ?Meaning {
        if (op.len != 1) return null;
        return switch (op[0]) {
            '<' => .{ .infix = "compare", .prefix = "move" },
            '>' => .{ .infix = "compare", .prefix = "wait for" },
            '-' => .{ .infix = "subtract", .prefix = "negate" },
            '+' => .{ .infix = "add", .prefix = "clone" },
            '*' => .{ .infix = "multiply", .prefix = "share" },
            else => null,
        };
    }

    /// The operand that ends at `end` (past whitespace, line breaks
    /// included, and a comment that ends a line), as written, when it is
    /// short: a name, a literal, or a call or index on one (`f(x)`,
    /// `a.b[i]`).
    fn operandBefore(src: []const u8, end: u32) ?[]const u8 {
        var e: usize = end;
        while (true) {
            while (e > 0 and (src[e - 1] == ' ' or src[e - 1] == '\t' or src[e - 1] == '\r')) e -= 1;
            if (e == 0 or src[e - 1] != '\n') break;
            // The line before may end in a comment, which is no operand.
            e -= 1;
            const line = if (std.mem.lastIndexOfScalar(u8, src[0..e], '\n')) |nl| nl + 1 else 0;
            if (commentStart(src[line..e])) |c| e = line + c;
        }
        var s = e;
        while (s > 0) {
            const c = src[s - 1];
            if (c == ')' or c == ']') {
                const open: u8 = if (c == ')') '(' else '[';
                var depth: u32 = 0;
                while (s > 0) {
                    s -= 1;
                    if (src[s] == '\n') return null;
                    if (src[s] == c) depth += 1;
                    if (src[s] == open) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
            } else if (c == '"' or c == '\'') {
                s -= 1;
                while (s > 0 and src[s - 1] != c) : (s -= 1) if (src[s - 1] == '\n') return null;
                if (s == 0) return null;
                s -= 1;
            } else if (isIdentCont(c) or c == '.' or c == '?' or c == '!') {
                s -= 1;
            } else break;
        }
        while (s < e and (src[s] == '.' or src[s] == '?' or src[s] == '!')) s += 1;
        if (s == e or e - s > 24) return null;
        return src[s..e];
    }

    /// The bracketed text that starts at `open`, `(x)` or `[0]`, when it
    /// closes on its line and is short.
    fn bracketAfter(src: []const u8, open: u32) ?[]const u8 {
        const want: u8 = if (src[open] == '(') ')' else ']';
        var depth: u32 = 0;
        var e: usize = open;
        while (e < src.len and e - open <= 24) : (e += 1) {
            switch (src[e]) {
                '(', '[' => depth += 1,
                ')', ']' => {
                    depth -= 1;
                    if (depth == 0) return if (src[e] == want) src[open .. e + 1] else null;
                },
                '\n' => return null,
                else => {},
            }
        }
        return null;
    }

    /// Where a comment starts on `line`: its first `#` outside a string.
    fn commentStart(line: []const u8) ?usize {
        var i: usize = 0;
        while (i < line.len) : (i += 1) switch (line[i]) {
            '#' => return i,
            '"', '\'' => {
                const q = line[i];
                i += 1;
                while (i < line.len and line[i] != q) : (i += 1) {
                    if (q == '"' and line[i] == '\\') i += 1;
                }
            },
            else => {},
        };
        return null;
    }

    /// The operand that starts at `start` (past whitespace on its line),
    /// as written, when it is short.
    fn operandAfter(src: []const u8, start: u32) ?[]const u8 {
        var s: usize = start;
        while (s < src.len and (src[s] == ' ' or src[s] == '\t')) s += 1;
        var e = s;
        while (e < src.len and std.mem.findScalar(u8, "<?!+-*~.", src[e]) != null) e += 1;
        if (e < src.len and (src[e] == '"' or src[e] == '\'')) {
            const q = src[e];
            e += 1;
            while (e < src.len and src[e] != q and src[e] != '\n') e += 1;
            if (e == src.len or src[e] != q) return null;
            e += 1;
        }
        while (e < src.len) {
            const c = src[e];
            if (isIdentCont(c) or c == '.') {
                e += 1;
            } else if (c == '(' or c == '[') {
                const close: u8 = if (c == '(') ')' else ']';
                var depth: u32 = 0;
                while (e < src.len) : (e += 1) {
                    if (src[e] == '\n') return null;
                    if (src[e] == c) depth += 1;
                    if (src[e] == close) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                if (e == src.len) return null;
                e += 1;
            } else break;
        }
        while (e > s and src[e - 1] == '.') e -= 1;
        if (e == s or e - s > 24) return null;
        return src[s..e];
    }

    /// Parse without the IR rewrites: the grammar's own output.
    pub fn parseTree(self: *Parser) !Sexp {
        const tree = try self.base.parseProgram();
        // `leafEnd` finds a long token's end by scanning it again.
        for (self.base.longTokenEnds.items) |kept| {
            const leaf: parser.Src = .{ .pos = kept.pos, .len = std.math.maxInt(u16), .id = 0 };
            if (leafEnd(self.base.source, leaf) != kept.end) @panic("a token over 65534 bytes scans to another end than the parser kept");
        }
        if (tooDeep(tree, 0)) |deep| {
            self.reject(deep, "expression is nested too deeply or too long; split it with named intermediate values");
            return error.ParseError;
        }
        return tree;
    }

    /// Reject the tree at `node`, unless it is already rejected.
    fn reject(self: *Parser, node: Sexp, message: []const u8) void {
        if (self.failure != null) return;
        const at = self.span(node);
        self.failure = .{ .severity = .@"error", .pos = at.start, .end = at.end, .message = message };
    }

    /// The source span of a node (see `BaseParser.span`).
    /// A hidden parameter of a padded closure spans the start of its
    /// closure, not the positions past the source's end its leaf holds.
    pub fn span(self: *const Parser, sexp: Sexp) parser.Span {
        if (sexp == .src and sexp.src.pos >= self.base.source.len) {
            const k = sexp.src.pos - self.base.source.len;
            if (k >= 1 and k <= self.pad_homes.items.len) {
                const home = self.pad_homes.items[k - 1];
                return .{ .start = home, .end = home };
            }
        }
        return self.base.span(sexp);
    }

    /// The first subtree nested `max_tree_depth` deep, or null.
    fn tooDeep(sexp: Sexp, depth: u32) ?Sexp {
        if (sexp != .list) return null;
        if (depth == max_tree_depth) return sexp;
        for (sexp.items()) |item| if (tooDeep(item, depth + 1)) |deep| return deep;
        return null;
    }

    /// Why parsing failed: at the token where the parser stopped, or the
    /// rejected tree. A token the parser did not expect is followed by
    /// what it expected there, when that is a short list.
    pub fn diagnostic(self: *Parser) diag.Diagnostic {
        if (self.failure) |f| return f;
        const failure = self.base.lastError().?;
        const lexer = &self.base.lexer;
        const tok = lexer.base.token(failure.cat, 0, failure.span.start, failure.span.end);
        const src = self.base.source;
        var pos = tok.pos;
        var end = failure.span.end;
        if (self.openRange(tok)) |d| return d;
        if (self.foreignWord(tok)) |d| return d;
        if (self.headerColon(tok)) |d| return d;
        if (self.bareResults(tok)) |d| return d;
        const message: []const u8 = switch (tok.cat) {
            .err => return .{ .severity = .@"error", .pos = pos, .end = end, .message = switch (lexer.err) {
                .semicolon => self.semicolonMessage(tok),
                .detached_prefix => self.detachedPrefix(tok),
                .brace => self.format("unexpected `{c}`; {s}", .{ src[pos], lexer.err.message() }),
                else => lexer.err.message(),
            } },
            .eof, .outdent => blk: {
                pos = lexer.prev_end;
                end = pos;
                break :blk if (tok.cat == .eof) "unexpected end of file" else "unexpected end of block";
            },
            .newline => "unexpected end of line",
            .indent => "unexpected indentation",
            // After `s as .circle(r)`: no guard in the pattern, and one
            // pattern (docs/design/as-patterns.md, rules 2 and 1).
            .post_if => if (afterAsPattern(src, pos)) "a pattern after `as` takes no `if` guard: join the condition with `and`, `if s as .circle(r) and r > 10`" else "a postfix `if` guard must end a statement; write `a if c else b` for a value",
            .comma => if (afterAsPattern(src, pos)) "after `as`, a pattern tests one variant; to test several, write a `match`" else self.format("unexpected `{s}`", .{src[pos..end]}),
            .ident => self.format("unexpected name `{s}`", .{src[pos..end]}),
            else => if (keyword(src[pos..end]) != null)
                self.format("unexpected keyword `{s}`", .{src[pos..end]})
            else
                self.format("unexpected `{s}`", .{src[pos..end]}),
        };
        const expected = self.expectedHint(failure.state);
        const with_expected = if (expected) |hint| self.format("{s}; expected {s}", .{ message, hint }) else message;
        const hint = self.printHint(tok) orelse self.bracketHint(tok) orelse self.typeSuffixHint(tok) orelse tokenHint(tok) orelse self.waitHint(src, tok) orelse chainedComparison(src, tok) orelse reservedHint(src, tok, expected orelse "");
        const full = if (hint) |h| self.format("{s}; {s}", .{ with_expected, h }) else with_expected;
        return .{ .severity = .@"error", .pos = pos, .end = end, .message = full };
    }

    /// A range with a side left out where only a slice may leave one
    /// out: `for i in 0..`, `1.. =>`, `[..3]`. Reported at the `..`.
    fn openRange(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const at: Token, const side: []const u8 = switch (tok.cat) {
            .dotdot, .dotdot_eq => .{ tok, "a start" },
            .dotdot_open => .{ tok, if (lexer.before_cat == .lbracket) "both ends" else "an end" },
            else => blk: {
                // The real token before this one; a layout token is not
                // one, so the last real token is.
                const cat, const pos = if (tok.len > 0) .{ lexer.before_cat, lexer.before_pos } else .{ lexer.prev_cat, lexer.prev_pos };
                if ((cat != .dotdot and cat != .dotdot_eq) or tok.cat == .err) return null;
                if (cat == .dotdot_eq) {
                    // The `..=` ends where the space before this token
                    // starts.
                    var end = if (tok.len > 0) tok.pos else pos + 3;
                    while (end > 3 and isSpaceBefore(self.base.source[end - 1])) end -= 1;
                    return .{ .severity = .@"error", .pos = end - 3, .end = end, .message = "`a..=` needs the end it includes; only `..` leaves a slice's end open: `xs[a..]`" };
                }
                break :blk .{ .{ .cat = .dotdot, .pre = 0, .pos = pos, .len = 2 }, "an end" };
            },
        };
        return .{ .severity = .@"error", .pos = at.pos, .end = self.base.tokenEnd(at), .message = self.format("a range needs {s}; only a slice leaves a side open: `xs[a..]`, `xs[..b]`, `xs[..]`", .{side}) };
    }

    /// A word other languages use where Rig has its own form, at the
    /// start of a statement (`def f()`, `let x = 5`, `loop` before its
    /// block) or where it fails itself (`if x then`): reported at the
    /// word, with Rig's spelling.
    fn foreignWord(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const src = self.base.source;
        const start: u32, const end: u32 = blk: {
            // The word the parser failed on, written where no Rig form
            // takes a name (`if x then`, `const x = 5`).
            if (tok.len > 0 and (tok.cat == .ident or keyword(self.base.tokenText(tok)) != null)) {
                if (foreign_words.get(self.base.tokenText(tok))) |f| if (f.alone) break :blk .{ tok.pos, self.base.tokenEnd(tok) };
            }
            // The statement's first word, right before the failure.
            const cat, const pos = if (tok.len > 0) .{ lexer.before_cat, lexer.before_pos } else .{ lexer.prev_cat, lexer.prev_pos };
            if (cat != .ident or pos != lexer.head_pos) return null;
            var end = pos;
            while (end < src.len and isIdentCont(src[end])) end += 1;
            break :blk .{ pos, end };
        };
        const word = src[start..end];
        const f = foreign_words.get(word) orelse return null;
        return .{ .severity = .@"error", .pos = start, .end = end, .message = self.format("Rig has no `{s}`; {s}", .{ word, f.fix }) };
    }

    const Foreign = struct {
        fix: []const u8,
        /// Named even where the parse fails on the word itself, not only
        /// when it starts a statement: a keyword of Rig's, or a word that
        /// ends a header.
        alone: bool = false,
    };

    /// Other languages' words for forms Rig spells differently.
    const foreign_words = std.StaticStringMap(Foreign).initComptime(.{
        .{ "def", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "fn", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "func", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "function", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "let", Foreign{ .fix = "bind a name with `x = 5`, or `x =! 5` for one that never changes" } },
        .{ "var", Foreign{ .fix = "bind a name with `x = 5`, or `x =! 5` for one that never changes" } },
        .{ "const", Foreign{ .fix = "write `x =! e` for a binding that never changes", .alone = true } },
        .{ "class", Foreign{ .fix = "declare a type with `obj`" } },
        .{ "struct", Foreign{ .fix = "write `obj Name`: `struct` is spelled `obj`" } },
        .{ "impl", Foreign{ .fix = "write `add`: `add Int: Shape` adds an API to a type, and `obj Square: Shape` names one on its header", .alone = true } },
        .{ "trait", Foreign{ .fix = "write `api`: `api Shape` declares the methods a type provides", .alone = true } },
        .{ "switch", Foreign{ .fix = "write `match`" } },
        .{ "case", Foreign{ .fix = "a match arm is `pattern => ...`" } },
        .{ "elif", Foreign{ .fix = "write `else if`" } },
        .{ "elsif", Foreign{ .fix = "write `else if`" } },
        .{ "elseif", Foreign{ .fix = "write `else if`" } },
        .{ "unless", Foreign{ .fix = "write `if not`" } },
        .{ "until", Foreign{ .fix = "write `while not`" } },
        .{ "import", Foreign{ .fix = "use a module with `use name`" } },
        .{ "require", Foreign{ .fix = "use a module with `use name`" } },
        .{ "include", Foreign{ .fix = "use a module with `use name`" } },
        .{ "loop", Foreign{ .fix = "write `while true`" } },
        .{ "forever", Foreign{ .fix = "write `while true`" } },
        .{ "do", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
        .{ "begin", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
        .{ "then", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
    });

    /// `if x:`, `while x:`, `obj S:`: a `:` ending a block's header,
    /// as in Python. Reported at the `:`.
    fn headerColon(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const src = self.base.source;
        const pos = switch (tok.cat) {
            // `while x:` reads the `:` as the start of a step.
            .indent, .newline => if (lexer.prev_cat == .step_colon) lexer.prev_pos else return null,
            .colon, .step_colon => blk: {
                var p = tok.pos + 1;
                while (p < src.len and (src[p] == ' ' or src[p] == '\r')) p += 1;
                if (p < src.len and src[p] != '\n' and src[p] != '#') return null;
                break :blk tok.pos;
            },
            else => return null,
        };
        return .{ .severity = .@"error", .pos = pos, .end = pos + 1, .message = "unexpected `:`; a block's header ends without one: remove the `:`, and indent the block below" };
    }

    /// `a / b, a % b` as a statement: a function's several results are
    /// given by `return`, never by a bare list, which no statement is.
    /// Reported at the line, where the parse fails on its `,` or its end.
    fn bareResults(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const src = self.base.source;
        if (lexer.nesting > 0) return null;
        const at: u32 = switch (tok.cat) {
            .comma => tok.pos,
            .newline, .outdent, .eof => lexer.prev_pos,
            else => return null,
        };
        const start: u32 = if (std.mem.findScalarLast(u8, src[0..at], '\n')) |nl| @intCast(nl + 1) else 0;
        var end: u32 = at;
        while (end < src.len and src[end] != '\n' and src[end] != '#') end += 1;
        const line = std.mem.trim(u8, src[start..end], " \t\r");
        if (line.len == 0) return null;
        // A statement that starts with a keyword is no bare list.
        var w: usize = 0;
        while (w < line.len and isIdentCont(line[w])) w += 1;
        if (w > 0 and keyword(line[0..w]) != null) return null;
        // A comma outside brackets, and no `=` of a binding.
        var depth: i32 = 0;
        var comma = false;
        for (line, 0..) |c, i| switch (c) {
            '(', '[' => depth += 1,
            ')', ']' => depth -= 1,
            '"', '\'' => return null,
            ',' => if (depth == 0) {
                comma = true;
            },
            '=' => if (depth == 0) {
                const before = if (i > 0) line[i - 1] else ' ';
                const after = if (i + 1 < line.len) line[i + 1] else ' ';
                if (after != '=' and after != '>' and std.mem.findScalar(u8, "=!<>+-*/%&|^", before) == null) return null;
            },
            else => {},
        };
        if (!comma) return null;
        const first = start + @as(u32, @intCast(std.mem.find(u8, src[start..end], line).?));
        return .{ .severity = .@"error", .pos = first, .end = first + @as(u32, @intCast(line.len)), .message = self.format("results are written `return {s}`", .{line}) };
    }

    /// A note for a parse error inside a bracket opened on an earlier
    /// line that nothing after the error closes: the innermost such
    /// bracket, which is likely the one left open.
    pub fn unclosedBracket(self: *Parser) ?diag.Diagnostic {
        if (self.failure != null) return null;
        const lexer = &self.base.lexer;
        const src = self.base.source;
        // How many of the open brackets the rest of the source closes.
        const at = self.base.lastError().?.span.start;
        var probe = BaseLexer.init(src);
        probe.pos = at;
        // The rest of the file `at` is in.
        const end = for (lexer.ends) |e| {
            if (at <= e) break e;
        } else src.len;
        var depth: u32 = 0;
        var closed: u32 = 0;
        while (closed < lexer.nesting) {
            const tok = probe.next();
            if (tok.pos >= end) break;
            switch (tok.cat) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => if (depth > 0) {
                    depth -= 1;
                } else {
                    closed += 1;
                },
                .eof => break,
                else => {},
            }
        } else return null;
        const open = lexer.brackets[lexer.nesting - 1 - closed];
        if (std.mem.findScalar(u8, src[open..at], '\n') == null) return null;
        return .{ .severity = .note, .pos = open, .end = open + 1, .message = self.format("the `{c}` opened here is not closed", .{src[open]}) };
    }

    /// Why an unexpected token is not Rig: it starts a reserved form, or
    /// Rig spells what it starts differently.
    fn reservedHint(src: []const u8, tok: Token, expected: []const u8) ?[]const u8 {
        const in_pattern = std.mem.find(u8, expected, "a match arm") != null or std.mem.find(u8, expected, "a pattern") != null;
        // Only a function type's result must follow here.
        if (std.mem.eql(u8, expected, "`->`")) return "a function type writes its result after `->`: `fun(Int) -> Int`";
        return switch (tok.cat) {
            .real, .string_sq, .string_dq => if (in_pattern) "a pattern is a name, an integer, a string, `true`, `false`, or an enum variant" else null,
            .@"else" => if (in_pattern) "the catch-all arm is `_`, or a name that binds the value" else null,
            .@"try" => "`try` blocks are reserved: propagate with `e!` or handle with `e catch ...`",
            .zig => "inline Zig is reserved: use `raw` blocks and `extern` declarations",
            .star => if (precededBy(src, tok.pos, "for")) reserved_for_star else null,
            .in => if (forStar(src, tok.pos)) reserved_for_star else null,
            .ident, .not_sym, .question => if (precededBy(src, tok.pos, "drop")) "a drop body takes self in parentheses: `drop(!@)`" else null,
            else => null,
        };
    }

    /// Whether the source just before `pos`, on its line, is a pattern
    /// after `as`: `as .name` or `as .name(...)`.
    fn afterAsPattern(src: []const u8, pos: u32) bool {
        var at: usize = pos;
        while (at > 0 and src[at - 1] == ' ') at -= 1;
        if (at > 0 and src[at - 1] == ')') {
            var depth: usize = 0;
            while (at > 0) : (at -= 1) {
                const c = src[at - 1];
                if (c == '\n') return false;
                if (c == ')') depth += 1;
                if (c == '(') {
                    depth -= 1;
                    if (depth == 0) {
                        at -= 1;
                        break;
                    }
                }
            }
        }
        const name_end = at;
        while (at > 0 and isIdentCont(src[at - 1])) at -= 1;
        if (at == name_end or at == 0 or src[at - 1] != '.') return false;
        at -= 1;
        return precededBy(src, @intCast(at), "as");
    }

    /// Compile-time parameters and arguments written where Rig does not
    /// take them: in parentheses (`obj Wrap(T)`, `List(Int)` in a type,
    /// `pre n: Int`), on a type alias, or as a type an expression cannot
    /// spell (`List[[]Int]()`). Also a struct declared with `type`.
    fn bracketHint(self: *Parser, tok: Token) ?[]const u8 {
        const src = self.base.source;
        const before = std.mem.trimEnd(u8, src[0..tok.pos], if (tok.cat == .indent) " \r\n" else " ");
        var start = before.len;
        while (start > 0 and isIdentCont(before[start - 1])) start -= 1;
        const word = before[start..];
        const declared = std.mem.trimEnd(u8, before[0..start], " ");
        // `type` declares only an alias: `type Name = T`.
        if (word.len > 0 and endsWithWord(declared, "type")) switch (tok.cat) {
            .indent => return self.format("an object is declared with `obj`: `obj {s}`", .{word}),
            .lbracket, .lparen => {
                const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
                if (std.mem.findScalar(u8, src[tok.pos..eol], '=') != null) return "a type alias takes no type parameters; generic aliases are not supported";
                return self.format("an object is declared with `obj`: `obj {s}[T]`", .{word});
            },
            else => {},
        };
        const decl_kw: ?[]const u8 = for ([_][]const u8{ "obj", "enum", "fun", "sub" }) |kw| {
            if (endsWithWord(declared, kw)) break kw;
        } else null;
        switch (tok.cat) {
            .lparen => {
                if (word.len == 0) return null;
                if (decl_kw) |kw| if (!std.mem.eql(u8, kw, "fun") and !std.mem.eql(u8, kw, "sub")) return self.format("type parameters go in brackets: `{s} {s}[T]`", .{ kw, word });
                if (std.ascii.isUpper(word[0])) return self.format("type arguments go in brackets: `{s}[...]`", .{word});
                return null;
            },
            .lbracket => if (word.len > 0 and endsWithWord(declared, "error")) {
                return "an error set takes no type parameters";
            },
            .rbracket => if (before.len > 0 and before[before.len - 1] == '[') {
                return "empty brackets: give the compile-time arguments, as in `List[Int]()`";
            },
            .fun, .sub => if (self.base.lexer.nesting > 0 and src[self.base.lexer.brackets[self.base.lexer.nesting - 1]] == '[') {
                return "a function type has no expression spelling: as a type argument in an expression, name it with a `type` alias, or annotate the binding instead";
            },
            else => {},
        }
        if (std.mem.eql(u8, word, "pre") and self.base.lexer.inParens()) {
            return "compile-time parameters go in brackets after the name, before the run-time ones: `fun f[n: Int](x: Int)`";
        }
        if (tok.cat == .ident and tok.pos > 0 and src[tok.pos - 1] == ']') {
            return "a slice or array type has no expression spelling: as a type argument in an expression, name it with a `type` alias, or annotate the binding instead";
        }
        return null;
    }

    /// Whether `name` is `print` or `warn`, which are called with parentheses.
    fn isOutputCall(name: []const u8) bool {
        return std.mem.eql(u8, name, "print") or std.mem.eql(u8, name, "warn");
    }

    /// `print "hi"`: `print` or `warn` named without its call's parentheses.
    fn printHint(self: *Parser, tok: Token) ?[]const u8 {
        const lex = &self.base.lexer;
        if (tok.len == 0 or lex.before_cat != .ident) return null;
        const src = self.base.source;
        var end = lex.before_pos;
        while (end < src.len and isIdentCont(src[end])) end += 1;
        const name = src[lex.before_pos..end];
        if (!isOutputCall(name)) return null;
        return self.format("`{s}` is called with parentheses: `{s}(...)`", .{ name, name });
    }

    /// A prefix sigil with whitespace after it (`- b`): named with the
    /// operand it should touch.
    fn detachedPrefix(self: *Parser, tok: Token) []const u8 {
        const src = self.base.source;
        var probe = BaseLexer.init(src);
        probe.pos = tok.pos + 1;
        const next = while (true) {
            const t = probe.next();
            if (t.cat != .skip and t.cat != .comment) break t;
        };
        const operand = switch (next.cat) {
            .ident, .integer, .real, .string_sq, .string_dq => probe.text(next),
            else => if (isKeyword(next.cat)) probe.text(next) else "x",
        };
        return self.format("a prefix `{c}` touches its operand: write `{c}{s}`", .{ src[tok.pos], src[tok.pos], operand });
    }

    /// A `;`, which Rig does not take: one ending a statement, Rust's
    /// fill literal `[x; n]`, or Rust's array type `[T; n]`.
    fn semicolonMessage(self: *Parser, tok: Token) []const u8 {
        const src = self.base.source;
        const lex = &self.base.lexer;
        if (lex.nesting == 0) {
            // `a = 1; b = 2`: another statement follows on the line.
            const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
            const rest = std.mem.trim(u8, src[tok.pos + 1 .. eol], " \r");
            if (rest.len > 0 and rest[0] != '#') return "unexpected `;`; Rig ends a statement at the end of its line; put each statement on its own line";
            return "unexpected `;`; Rig ends a statement at the end of its line; remove the `;`";
        }
        const open = lex.brackets[lex.nesting - 1];
        if (src[open] != '[') return "unexpected `;`";
        const either = "unexpected `;`; `[x; n]` is written `[n of x]`, and `[Int; 3]` is written `[3]Int`";
        const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
        const close = std.mem.findScalarPos(u8, src[0..eol], tok.pos, ']') orelse return either;
        const elem = std.mem.trim(u8, src[open + 1 .. tok.pos], " ");
        const len = std.mem.trim(u8, src[tok.pos + 1 .. close], " ");
        if (elem.len == 0 or len.len == 0 or std.mem.findAny(u8, elem, ",;") != null or std.mem.findAny(u8, len, ",;([") != null) return either;
        // `[Int; 3]`: the brackets stand where a type goes (after `:` or
        // `->`), or the element reads as a type: `Int`, `U8`, `T`, not a
        // constant such as `LIMIT`, nor a constructor call.
        const before = std.mem.trimEnd(u8, src[0..open], " ");
        const in_type = std.mem.endsWith(u8, before, ":") or std.mem.endsWith(u8, before, "->");
        const rest = elem[1..];
        const typelike = in_type or (std.ascii.isUpper(elem[0]) and std.mem.findScalar(u8, elem, '(') == null and
            (rest.len == 0 or std.mem.findAny(u8, rest, "abcdefghijklmnopqrstuvwxyz") != null or
                std.mem.findNone(u8, rest, "0123456789") == null));
        if (typelike) return self.format("unexpected `;`; an array type puts its length first: `[{s}]{s}`", .{ len, elem });
        return self.format("unexpected `;`; a fill literal puts its count first: `[{s} of {s}]`", .{ len, elem });
    }

    /// `sub()?`, `*fun(Int) -> Int` then `!`: a function type takes no
    /// suffix, so an optional one is written in parentheses.
    fn typeSuffixHint(self: *Parser, tok: Token) ?[]const u8 {
        if (tok.cat != .question and tok.cat != .not_sym) return null;
        const src = self.base.source;
        if (tok.pos == 0 or src[tok.pos - 1] != ')') return null;
        // The `(` that the `)` before the suffix closes.
        var depth: u32 = 0;
        var p = tok.pos;
        const open = while (p > 0) {
            p -= 1;
            switch (src[p]) {
                ')' => depth += 1,
                '(' => {
                    depth -= 1;
                    if (depth == 0) break p;
                },
                '\n' => return null,
                else => {},
            }
        } else return null;
        if (!endsWithWord(src[0..open], "sub") and !endsWithWord(src[0..open], "fun")) return null;
        var start = open - 3;
        while (start > 0 and (src[start - 1] == '*' or src[start - 1] == '~' or src[start - 1] == '^')) start -= 1;
        return self.format("a function type takes no suffix; write `({s}){c}`", .{ src[start..tok.pos], src[tok.pos] });
    }

    /// `[a, 2 of 3]`: a fill literal is the whole bracket. `Int??`: `??`
    /// is an operator, and where the parser does not take one, it was
    /// meant as two suffixes.
    fn tokenHint(tok: Token) ?[]const u8 {
        return switch (tok.cat) {
            .of => "a fill literal `[n of x]` holds one count and one element; it cannot share brackets with a list",
            .nullish => "`??` is the fallback operator; an optional of an optional is written `(T?)?`",
            // Where no operator could come: C and Rust's address-of.
            .ampersand => "Rig lends with `?x` (to read) or `!x` (to write)",
            else => null,
        };
    }

    /// A wait whose `>` the token before it took: `x=>t` is the match
    /// arm's `=>`, and `->t` a function's `->`.
    fn waitHint(self: *Parser, src: []const u8, tok: Token) ?[]const u8 {
        const end = tok.pos + tok.len;
        if (end >= src.len or !isIdentStart(src[end])) return null;
        const name = identAt(src, end);
        return switch (tok.cat) {
            .fat_arrow => self.format("`=>` ends a match arm's pattern; to wait for the task `{s}`, write `= >{s}`", .{ name, name }),
            .arrow => self.format("`->` gives a function's result type; to negate what the task `{s}` gives, write `-(>{s})`", .{ name, name }),
            else => null,
        };
    }

    /// A comparison operator after a value, where the parser takes none:
    /// a second comparison in a chain (`a == b | c == d` reads as
    /// `a == (b | c) == d`, since `|`, `&`, and `^` bind tighter).
    fn chainedComparison(src: []const u8, tok: Token) ?[]const u8 {
        switch (tok.cat) {
            .eq, .ne, .le, .ge, .lt, .gt => {},
            else => return null,
        }
        const before = std.mem.trimEnd(u8, src[0..tok.pos], " ");
        if (before.len == 0) return null;
        const c = before[before.len - 1];
        if (!isIdentCont(c) and c != ')' and c != ']' and c != '"' and c != '\'') return null;
        return "comparisons do not chain, and `|`, `&`, and `^` bind tighter than a comparison: put each comparison in parentheses, `(a == b) | (c == d)`";
    }

    fn endsWithWord(text: []const u8, word: []const u8) bool {
        return std.mem.endsWith(u8, text, word) and (text.len == word.len or !isIdentCont(text[text.len - word.len - 1]));
    }

    const reserved_for_star = "`for *x in` is reserved: iterate with `for x in xs`, `?xs`, or `!xs`";

    /// Whether the `in` at `pos` closes a `for *x` header, which reads as
    /// a bare `for` over `*x` until the `in`.
    fn forStar(src: []const u8, pos: u32) bool {
        const start = if (std.mem.findScalarLast(u8, src[0..pos], '\n')) |nl| nl + 1 else 0;
        const line = std.mem.trimStart(u8, src[start..pos], " \t");
        return std.mem.startsWith(u8, line, "for *");
    }

    /// The word before `pos` is `word`.
    fn precededBy(src: []const u8, pos: u32, word: []const u8) bool {
        return endsWithWord(std.mem.trimEnd(u8, src[0..pos], " "), word);
    }

    /// The generated parser's expected set where it stopped (its
    /// `@display` and `@errors` names, distinct), or null when it names
    /// more than a few things.
    fn expectedHint(self: *Parser, state: u16) ?[]const u8 {
        var buf: [parser.maxExpected][]const u8 = undefined;
        const names = BaseParser.expectedNames(state, &buf);
        if (names.len == 0 or names.len > max_expected) return null;
        var out: std.Io.Writer.Allocating = .init(self.allocator());
        for (names, 0..) |n, i| {
            out.writer.writeAll(if (i == 0) "" else if (i + 1 == names.len) " or " else ", ") catch return null;
            out.writer.writeAll(n) catch return null;
        }
        return out.written();
    }

    /// The longest expected set a parse error lists.
    const max_expected = 3;

    fn format(self: *Parser, comptime fmt: []const u8, args: anytype) []const u8 {
        return self.allocator().print(fmt, args) catch "unexpected token";
    }

    fn allocator(self: *Parser) std.mem.Allocator {
        return self.base.allocator();
    }

    // -------------------------------------------------------------------------
    // Rewrites that need to inspect the tree:
    //
    //   * a closure's bar list (the grammar's `params`) splits into its
    //     captures and parameters:
    //       (lambda _ ((cap_clone v) a) _ body)  →  (lambda (captures (cap_clone v)) (a) _ body)
    //   * `for` source sigils move into the mode slot:
    //       (for iter x _ (read xs) body _)  →  (for read x _ xs body _)
    //   * a statement `<e` whose value is not used drops now: a block's
    //     statement, a `defer` or `errdefer` body, an arm's body, or a
    //     labeled statement becomes (drop x) for a name, and
    //     (drop (move e)) for anything else; the last statement of a
    //     `fun` body, a closure body, a `break` or `return` value, a
    //     binding's value, or a branch, arm, `catch` handler, or loop
    //     `else` block whose value is used keeps its (move e):
    //       (block (move x))  →  (block (drop x))
    //   * a jump fallback belongs to the nearest `??` (the grammar reads
    //     it at the level of `catch`, after the chain before it):
    //       (?? (?? a b) (return v))  →  (?? a (?? b (return v)))
    //   * `?`, `!`, or `<` before a place followed by a method call is the
    //     receiver's mode:
    //       (write (call (member (member x v) push) 1))  →  (call (member (write (member x v)) push) 1)
    //
    // Every rewritten node keeps its node id, and so its span; the new
    // `captures` node and receiver sigil get their own (`newNode`).
    // -------------------------------------------------------------------------

    pub fn rewrite(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        if (sexp != .list) return sexp;
        var items = sexp.items();
        // A `for` source sigil is the loop's mode, taken before the
        // receiver rewrite can see it.
        var loop_sigil: Sexp = .nil;
        if (sexp.kind() == .@"for") {
            const copy = try self.allocator().dupe(Sexp, items);
            self.bareFor(sexp, copy);
            const source = ir.For.source(sexp);
            if (ir.For.mode(sexp).tag == .iter and source.isKind(.read)) loop_sigil = source;
            normFor(copy);
            items = copy;
        }
        const walked = try self.allocator().alloc(Sexp, items.len);
        const in_type = switch (sexp.kind() orelse .module) {
            .@"struct", .@"enum", .errors, .generic_struct, .generic_enum, .api, .api_add => true,
            else => false,
        };
        if (in_type) self.type_depth += 1;
        for (items, 0..) |child, i| walked[i] = try self.rewrite(child);
        if (in_type) self.type_depth -= 1;
        const out: Sexp = .{ .list = parser.List.withId(walked, sexp.list.id) };
        if (loop_sigil != .nil) try self.loopReceiver(out, loop_sigil);
        try self.placeRarely(out);
        switch (out.kind() orelse return out) {
            .module => {
                self.strayRarely(out, false);
                self.moduleConsts(out);
                return self.builtinRefs(try self.attachMethods(out));
            },
            .@"struct", .@"enum", .errors, .api, .api_add => try self.pubMembers(out),
            .generic_struct => {
                try self.tparamBounds(walked, ir.slot(.generic_struct, .tparams));
                try self.pubMembers(out);
            },
            .generic_enum => {
                try self.tparamBounds(walked, ir.slot(.generic_enum, .tparams));
                try self.pubMembers(out);
            },
            .lambda => {
                try self.splitBars(out, walked);
                // A closure's value is its body's last line.
                try self.valueTail(&walked[ir.slot(.lambda, .body)]);
            },
            .block => for (walked[1..]) |*stmt| try self.dropStatement(stmt),
            .@"defer", .@"errdefer" => try self.dropStatement(&walked[ir.slot(.@"defer", .body)]),
            .arm => try self.dropStatement(&walked[ir.slot(.arm, .body)]),
            .labeled => try self.dropStatement(&walked[ir.slot(.labeled, .stmt)]),
            .@"??" => return self.nearestFallback(try self.rightNested(out)),
            .destructure => try self.destructureTargets(walked),
            .as_results => try self.resultNames(walked),
            .as_pattern => return self.asMatch(out),
            .read, .write, .move => return self.receiverSigil(out),
            .wait => {
                self.touchesOperand(out);
                return self.waitCall(out);
            },
            .once => {
                const param = try self.base.newNode(.@":", &.{ ir.get(out, .name), ir.get(out, .type) }, self.span(out));
                try self.once_params.put(self.allocator(), param.list.id, {});
                return param;
            },
            .@"..=" => return self.base.newNode(.@"..", &.{ ir.get(out, .left), ir.get(out, .right), .{ .tag = .inclusive } }, self.span(out)),
            .member, .index, .inst => self.waitTakesName(out, ir.get(out, .object)),
            .call => self.waitTakesName(out, ir.Call.callee(out)),
            .share, .box => try self.noteParenSuffix(out),
            .weak => {
                self.touchesOperand(out);
                try self.noteParenSuffix(out);
            },
            .read_view, .write_view, .shared, .boxed => self.touchesOperand(out),
            // The body's value is returned.
            .fun => {
                try self.tparamBounds(walked, ir.slot(.fun, .tparams));
                try self.tparamBounds(walked, ir.slot(.fun, .owner_params));
                try self.paramList(out);
                if (ir.Fun.returns(out) != .nil) try self.valueTail(&walked[ir.slot(.fun, .body)]);
            },
            .sub => {
                try self.tparamBounds(walked, ir.slot(.sub, .tparams));
                try self.tparamBounds(walked, ir.slot(.sub, .owner_params));
                try self.paramList(out);
            },
            .extern_fun, .extern_sub => try self.paramList(out),
            // The expression's value is bound or returned.
            .set => try self.valueTail(&walked[ir.slot(.set, .value)]),
            .@"return" => try self.valueTail(&walked[ir.slot(.@"return", .value)]),
            // A loop's value is always used.
            .@"break" => try self.valueTail(&walked[ir.slot(.@"break", .value)]),
            else => {},
        }
        return out;
    }

    /// A name of a built-in type written in Rig (`builtin_type_names`),
    /// where it refers to the type, is that type of the hidden module
    /// that declares them, `__rig_builtin.Map`, and each file that names
    /// one uses that module, so the passes after the wrapper read it as
    /// any imported type. A module that declares a name of its own, or
    /// imports a module under it, keeps its own.
    fn builtinRefs(self: *Parser, module: Sexp) std.mem.Allocator.Error!Sexp {
        var hidden: [builtin_type_names.len]bool = @splat(false);
        for (module.items()[1..]) |d0| {
            const d = if (d0.isKind(.@"pub")) ir.Pub.decl(d0) else d0;
            const name: Sexp = switch (d.kind() orelse continue) {
                .@"struct", .@"enum", .errors, .generic_struct, .generic_enum, .type, .fun, .sub, .@"extern", .extern_fun, .extern_sub => ir.get(d, .name),
                .use => if (ir.Use.alias(d) != .nil) ir.Use.alias(d) else blk: {
                    const p = ir.Use.name(d);
                    break :blk if (p.isKind(.member)) ir.Member.name(p) else p;
                },
                .set => ir.Set.target(d),
                else => continue,
            };
            if (name != .src) continue;
            const text = leafText(self.base.source, name.src);
            for (builtin_type_names, 0..) |n, i| if (std.mem.eql(u8, n, text)) {
                hidden[i] = true;
            };
        }
        var firsts: std.ArrayList(u32) = .empty;
        const out = try self.rewriteBuiltin(module, &hidden, &firsts);
        if (firsts.items.len == 0) return out;
        // One `use` of the module in each file that names a built-in
        // type, at the first name there.
        const items = out.items();
        const uses = try self.allocator().alloc(Sexp, firsts.items.len);
        for (firsts.items, uses) |pos, *u| u.* = try self.base.newNode(.use, &.{ hiddenLeaf(pos, .builtin_module), .nil }, .{ .start = pos, .end = pos + 1 });
        const all = try std.mem.concat(self.allocator(), Sexp, &.{ items[0..1], uses, items[1..] });
        return .{ .list = parser.List.withId(all, out.list.id) };
    }

    /// `node` with each name of a built-in type that refers to it made
    /// `__rig_builtin.Name` (`builtinRefs`). A declaration's own name, a
    /// member's name, a field's, a binding's, and a parameter's are names
    /// of their own, and stay. `firsts` gets the position of the first
    /// such name of each file.
    fn rewriteBuiltin(self: *Parser, node: Sexp, outer: []const bool, firsts: *std.ArrayList(u32)) std.mem.Allocator.Error!Sexp {
        if (node != .list) return node;
        const kind = node.kind();
        const items = node.items();
        // An API's associated type (`type Item`) hides a built-in type of
        // its name in the API.
        var own: [builtin_type_names.len]bool = undefined;
        const hidden = if (kind == .api) blk: {
            @memcpy(&own, outer[0..builtin_type_names.len]);
            for (ir.rest(node, .members)) |m| {
                if (!m.isKind(.api_type) or ir.ApiType.name(m) != .src) continue;
                const text = leafText(self.base.source, ir.ApiType.name(m).src);
                for (builtin_type_names, 0..) |n, i| if (std.mem.eql(u8, n, text)) {
                    own[i] = true;
                };
            }
            break :blk own[0..];
        } else outer;
        var copy: ?[]Sexp = null;
        for (items, 0..) |c, i| {
            if (kind != null and i == 0) continue;
            const new = if (c == .src) blk: {
                // Leaves in an untagged list (parameters, captures, names)
                // are names of their own.
                const k = kind orelse break :blk c;
                if (!self.refersAt(node, k, c)) break :blk c;
                break :blk try self.builtinRef(c, hidden, firsts);
            } else try self.rewriteBuiltin(c, hidden, firsts);
            if (std.meta.eql(new, c)) continue;
            if (copy == null) copy = try self.allocator().dupe(Sexp, items);
            copy.?[i] = new;
        }
        const out = copy orelse return node;
        return .{ .list = parser.List.withId(out, node.list.id) };
    }

    /// The file of a module of several files that `pos` is in: how many
    /// files end before it (`Lexer.ends`).
    fn fileAt(self: *const Parser, pos: u32) usize {
        var n: usize = 0;
        for (self.base.lexer.ends) |e| {
            if (pos >= e) n += 1;
        }
        return n;
    }

    /// Whether leaf `c`, a child of `node` (of kind `k`), stands where a
    /// name refers to a type or a value, rather than naming a new one.
    fn refersAt(self: *Parser, node: Sexp, k: Tag, c: Sexp) bool {
        _ = self;
        // A generic instance's type is named in its `name` slot.
        if (k == .generic_inst) return true;
        inline for ([_]parser.Role{ .name, .alias, .label, .@"var", .index, .target, .operand, .owner }) |r| {
            if (ir.has(k, r) and std.meta.eql(ir.get(node, r), c)) return false;
        }
        return true;
    }

    /// `leaf` as `__rig_builtin.Name` when it names a built-in type its
    /// module does not hide.
    fn builtinRef(self: *Parser, leaf: Sexp, hidden: []const bool, firsts: *std.ArrayList(u32)) std.mem.Allocator.Error!Sexp {
        const text = leafText(self.base.source, leaf.src);
        const i = for (builtin_type_names, 0..) |n, i| {
            if (std.mem.eql(u8, n, text)) break i;
        } else return leaf;
        if (hidden[i] or isHiddenLeaf(leaf)) return leaf;
        const file = self.fileAt(leaf.src.pos);
        const seen = for (firsts.items) |p| {
            if (self.fileAt(p) == file) break true;
        } else false;
        if (!seen) try firsts.append(self.allocator(), leaf.src.pos);
        const at: parser.Span = .{ .start = leaf.src.pos, .end = leafEnd(self.base.source, leaf.src) };
        return self.base.newNode(.member, &.{ hiddenLeaf(leaf.src.pos, .builtin_module), leaf }, at);
    }

    /// The type parameters among `walked[slot]`, a declaration's
    /// compile-time parameters, written with bounds: `[T: Ord]`, whose
    /// name after the colon is a built-in API (`Api`), `[T: Shape]`, a
    /// type parameter (a capital letter) named after the colon, and `[K:
    /// Hash + Print]`. Each becomes a bare name, as `[T]`, and its bounds
    /// are recorded by where its name is (`bounds`); resolve tells an API
    /// from a type. `[n: Int]` names a type and stays a compile-time
    /// value.
    fn tparamBounds(self: *Parser, walked: []Sexp, slot: usize) std.mem.Allocator.Error!void {
        const group = walked[slot];
        if (group != .list) return;
        const items = try self.allocator().dupe(Sexp, group.items());
        var changed = false;
        for (items) |*p| {
            const name: Sexp, const apis: []const Sexp = switch (p.kind() orelse continue) {
                .@":" => blk: {
                    const ty = ir.get(p.*, .type);
                    const pname = ir.get(p.*, .name);
                    const builtin = ty == .src and Api.named(leafText(self.base.source, ty.src)) != null;
                    const capital = pname == .src and std.ascii.isUpper(leafText(self.base.source, pname.src)[0]);
                    const named = (ty == .src and std.ascii.isUpper(leafText(self.base.source, ty.src)[0])) or ty.isKind(.member);
                    if (!builtin and !(capital and named)) continue;
                    break :blk .{ pname, try self.allocator().dupe(Sexp, &.{ty}) };
                },
                .bound => .{ ir.get(p.*, .name), ir.get(p.*, .apis).items() },
                else => continue,
            };
            if (name != .src) continue;
            try self.bounds.put(self.allocator(), name.src.pos, apis);
            p.* = name;
            changed = true;
        }
        // `S.Item: Ord`: bounds on an associated type of a parameter the
        // same brackets name, recorded by where that parameter's name is
        // (`assoc_bounds`), and no parameter of its own.
        var kept: std.ArrayList(Sexp) = .empty;
        for (items) |p| {
            if (!p.isKind(.assoc_bound)) {
                try kept.append(self.allocator(), p);
                continue;
            }
            changed = true;
            const owner = ir.get(p, .owner);
            const base = for (items) |q| {
                const qn = if (q == .src) q else if (q.isKind(.@":") or q.isKind(.bound)) ir.get(q, .name) else Sexp.nil;
                if (qn == .src and owner == .src and std.mem.eql(u8, leafText(self.base.source, qn.src), leafText(self.base.source, owner.src))) break qn;
            } else {
                self.reject(p, "an associated type's bound names a parameter of the same brackets: `[S: Source, S.Item: Ord]`");
                continue;
            };
            const entry = try self.assoc_bounds.getOrPut(self.allocator(), base.src.pos);
            if (!entry.found_existing) entry.value_ptr.* = &.{};
            entry.value_ptr.* = try std.mem.concat(self.allocator(), Sexp, &.{ entry.value_ptr.*, &.{p} });
        }
        if (changed) walked[slot] = .{ .list = parser.List.withId(kept.items, group.list.id) };
    }

    /// The bounds on associated types of the type parameter whose name is
    /// at `pos`, each an `assoc_bound` (`[S: Source, S.Item: Ord]`).
    pub fn assocBoundsAt(self: *const Parser, pos: u32) []const Sexp {
        return self.assoc_bounds.get(pos) orelse &.{};
    }

    /// The bounds written on the type parameter whose name is at `pos`
    /// (`tparamBounds`); empty for one written bare.
    pub fn boundsAt(self: *const Parser, pos: u32) []const Sexp {
        return self.bounds.get(pos) orelse &.{};
    }

    /// The type's parameters as the method whose name is at `pos` names
    /// them, when it bounds one (`fun Wrap[T: Print].show(?@)`); each
    /// one's bounds are `boundsAt` its name. Empty for any other method.
    pub fn ownerBoundsAt(self: *const Parser, pos: u32) []const Sexp {
        return self.owner_bounds.get(pos) orelse &.{};
    }

    /// A `rarely` that starts the body of a function, a branch of `if` or
    /// `match`, a `catch` handler, or a loop marks it: the block rarely
    /// runs, and emit starts its branch with Zig's cold hint.
    fn placeRarely(self: *Parser, node: Sexp) std.mem.Allocator.Error!void {
        const bodies: [2]Sexp = switch (node.kind() orelse return) {
            .fun, .sub => .{ ir.get(node, .body), .nil },
            .@"if" => .{ ir.If.then(node), ir.If.@"else"(node) },
            .arm => .{ ir.Arm.body(node), .nil },
            .@"while" => .{ ir.While.body(node), .nil },
            .@"for" => .{ ir.For.body(node), .nil },
            .@"catch" => .{ ir.Catch.handler(node), .nil },
            else => return,
        };
        for (bodies) |b| if (startsRarely(b)) try self.placed_rarely.put(self.allocator(), ir.Block.stmts(b)[0].list.id, {});
    }

    /// A `rarely` anywhere else is rejected: after a block's first line,
    /// or starting a block it may not mark.
    fn strayRarely(self: *Parser, node: Sexp, first: bool) void {
        if (node != .list) return;
        if (node.isKind(.rarely) and !self.placed_rarely.contains(node.list.id)) return self.reject(node, if (first)
            "`rarely` marks the body of a function, a branch of `if` or `match`, a `catch` handler, or a loop"
        else
            "`rarely` is the first line of the block it marks");
        const block = node.isKind(.block);
        // A group (a parameter list) has no kind in front.
        const kids = if (node.kind() != null) node.items()[1..] else node.items();
        for (kids, 0..) |child, i| self.strayRarely(child, block and i == 0);
    }

    /// `q, r = f()`: each target but `_` takes the result in its position,
    /// as the binding `(set op q _ (result_part))`, which every pass
    /// reads as the `x = e` it is (docs/internals/INTERNALS.md, "Several
    /// results"). A `_` stays a leaf: its result is left in the
    /// statement's temporary, which drops it at the statement's end.
    fn destructureTargets(self: *Parser, walked: []Sexp) std.mem.Allocator.Error!void {
        const slot = ir.slot(.destructure, .targets);
        const group = walked[slot];
        const op = walked[ir.slot(.destructure, .op)];
        const targets = group.items();
        const out = try self.allocator().alloc(Sexp, targets.len);
        for (targets, out) |t, *o| {
            if (t == .src and std.mem.eql(u8, leafText(self.base.source, t.src), "_")) {
                o.* = t;
                continue;
            }
            const at = self.span(t);
            const part = try self.base.newNode(.result_part, &.{}, at);
            o.* = try self.base.newNode(.set, &.{ op, t, .nil, part }, at);
        }
        walked[slot] = .{ .list = parser.List.withId(out, group.list.id) };
    }

    /// `s as .circle(r)`: the `match` it is, `(as_match (match s (arm
    /// .circle(r) _ pass) (arm _ _ pass)))`. Its first arm goes on with
    /// the rest of the condition and the body; any other value takes the
    /// second, which falls to the `else` (docs/design/as-patterns.md). Every pass
    /// reads its subject and its pattern as a `match`'s, and emit writes
    /// the `match`, which drops a value `<s` took when no arm keeps it.
    fn asMatch(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const at = self.span(node);
        const pattern = ir.AsPattern.pattern(node);
        const pat_at = self.span(pattern);
        const pass = try self.base.newNode(.pass, &.{}, pat_at);
        const arm = try self.base.newNode(.arm, &.{ pattern, .nil, pass }, pat_at);
        const other = try self.base.newNode(.arm, &.{ hiddenLeaf(pat_at.start, .discard), .nil, try self.base.newNode(.pass, &.{}, pat_at) }, pat_at);
        const match = try self.base.newNode(.match, &.{ ir.AsPattern.value(node), arm, other }, at);
        return self.base.newNode(.as_match, &.{match}, at);
    }

    /// `if f() as a, b`: each name but `_` is a new binding of the result
    /// in its position, `(set shadow a _ (result_part))`, as a
    /// destructure's target is (`destructureTargets`).
    fn resultNames(self: *Parser, walked: []Sexp) std.mem.Allocator.Error!void {
        const slot = ir.slot(.as_results, .names);
        const group = walked[slot];
        const names = group.items();
        const out = try self.allocator().alloc(Sexp, names.len);
        for (names, out) |n, *o| {
            if (n == .src and std.mem.eql(u8, leafText(self.base.source, n.src), "_")) {
                o.* = n;
                continue;
            }
            const at = self.span(n);
            const part = try self.base.newNode(.result_part, &.{}, at);
            o.* = try self.base.newNode(.set, &.{ .{ .tag = .shadow }, n, .nil, part }, at);
        }
        walked[slot] = .{ .list = parser.List.withId(out, group.list.id) };
    }

    /// A module-level binding is a constant, written with `=`: its
    /// `(set _ ...)` becomes `(set fixed ...)`, the fixed binding every
    /// pass reads. A `=!` there is rejected, as it would say nothing
    /// more.
    fn moduleConsts(self: *Parser, module: Sexp) void {
        for (ir.Module.decls(module)) |decl| {
            const set = if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl;
            if (!set.isKind(.set)) continue;
            switch (bindingKindOf(ir.Set.op(set))) {
                .default => @constCast(set.items())[ir.slot(.set, .op)] = .{ .tag = .fixed },
                .fixed => {
                    const src = self.base.source;
                    const target = self.span(ir.Set.target(set));
                    const value = self.span(ir.Set.value(set));
                    const ty = ir.Set.type(set);
                    const annot = if (ty == .nil) "" else src[target.end..self.span(ty).end];
                    const shown = src[value.start..value.end];
                    const short = shown.len <= 40 and std.mem.findScalar(u8, shown, '\n') == null;
                    self.reject(set, self.format("a module-level binding is already a constant; write `{s}{s} = {s}`", .{ src[target.start..target.end], annot, if (short) shown else "..." }));
                },
                else => {},
            }
        }
    }

    /// A function's parameter list is always written, even when empty,
    /// as its calls and its type write theirs: `sub main()`, not `sub
    /// main`. The grammar parses a definition without one so that the
    /// fix-it can show the header with it.
    fn paramList(self: *Parser, def: Sexp) std.mem.Allocator.Error!void {
        if (ir.get(def, .params) != .nil) return;
        const src = self.base.source;
        const name = ir.get(def, .name);
        const start = self.span(def).start;
        if (try self.ctFunShape(def)) return;
        // The list goes after the name and its compile-time parameters.
        const at = self.afterTparams(name);
        var end = at;
        while (end < src.len and src[end] != '\n' and src[end] != '#') end += 1;
        const rest = std.mem.trimEnd(u8, src[at..end], " \t\r");
        const message = self.format("write `{s}(){s}`: a function's parameter list is always written, even when empty", .{ src[start..at], rest });
        if (self.failure == null) return self.reject(name, message);
        const at_name = self.span(name);
        try self.more_failures.append(self.allocator(), .{ .severity = .@"error", .pos = at_name.start, .end = at_name.end, .message = message });
    }

    /// Where a definition's header goes on after its name and its
    /// compile-time parameters, `[...]`.
    fn afterTparams(self: *Parser, name: Sexp) usize {
        const src = self.base.source;
        var at: usize = self.span(name).end;
        var probe = at;
        while (probe < src.len and src[probe] == ' ') probe += 1;
        if (probe < src.len and src[probe] == '[') {
            var depth: u32 = 0;
            while (probe < src.len) : (probe += 1) {
                if (src[probe] == '[') depth += 1;
                if (src[probe] == ']') {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            at = @min(probe + 1, src.len);
        }
        return at;
    }

    /// A `fun` with compile-time parameters and no run-time list is a
    /// compile-time function (`isCtFun`), declared at module level, whose
    /// every parameter is a value (`n: Int`) and which gives a value
    /// (`-> T`). True when `def` takes that form: accepted, or rejected
    /// here with why. False when it is a run-time function missing its
    /// list, which the caller's fix-it shows.
    fn ctFunShape(self: *Parser, def: Sexp) std.mem.Allocator.Error!bool {
        if (!def.isKind(.fun) and !def.isKind(.sub)) return false;
        const tparams = ir.get(def, .tparams);
        if (tparams == .nil or tparams.items().len == 0) return false;
        for (tparams.items()) |p| if (!p.isKind(.@":")) return false;
        const src = self.base.source;
        const name = ir.get(def, .name);
        const header = src[self.span(name).start..self.afterTparams(name)];
        if (def.isKind(.sub)) {
            self.reject(name, self.format("a compile-time function gives a value: write `fun {s} -> T`; a `sub` writes its parameter list: `sub {s}()`", .{ header, header }));
            return true;
        }
        if (!def.isKind(.fun)) return false;
        if (self.type_depth > 0 or ir.get(def, .owner) != .nil) {
            self.reject(name, self.format("a compile-time function is declared at module level; a method writes its parameter list: `fun {s}(?@)`", .{header}));
            return true;
        }
        const mark = ir.get(def, .mark);
        if (mark != .nil) {
            self.reject(mark, self.format("`{s}` is a compile-time function, which the checker runs, so no call of it is left to mark `{s}`: drop the `{s}`", .{ header, @tagName(mark.kind().?), @tagName(mark.kind().?) }));
            return true;
        }
        if (ir.Fun.returns(def) == .nil) {
            self.reject(name, self.format("a compile-time function gives a value: write its type, `fun {s} -> T`", .{header}));
            return true;
        }
        if (ir.get(def, .body) == .nil) {
            self.reject(name, self.format("`{s}` runs in the compiler, which runs only Rig: give it a body", .{header}));
            return true;
        }
        if (ir.get(def, .origins) != .nil or ir.get(def, .keeps) != .nil) {
            self.reject(name, self.format("`{s}` gives a value made at compile time, which views nothing: drop its `from` and `keeps`", .{header}));
            return true;
        }
        return true;
    }

    /// The rejections after the first (`diagnostic()`), in source order.
    pub fn moreDiagnostics(self: *const Parser) []const diag.Diagnostic {
        return if (self.failure != null) self.more_failures.items else &.{};
    }

    /// `pub` on a field or method: the member stands in the member list
    /// as itself, as every pass reads it, and its id is recorded
    /// (`isPubMember`).
    fn pubMembers(self: *Parser, node: Sexp) std.mem.Allocator.Error!void {
        const is_enum = node.isKind(.@"enum") or node.isKind(.generic_enum) or node.isKind(.errors);
        for (@constCast(ir.rest(node, .members))) |*m| {
            // `?len: Int` alone: `?` says who may read a field, and only a
            // `pub` field is read by anyone but its own module.
            if (readOnlyField(m.*)) |field| {
                self.reject(m.*, "`?` before a field means other modules may read it but not write it, which only a `pub` field allows: write `pub ?name: T`, or drop the `?`");
                m.* = field;
                continue;
            }
            if (!m.isKind(.@"pub")) continue;
            var inner = ir.Pub.decl(m.*);
            // `pub ?len: Int`: public to read, written only by this module.
            if (readOnlyField(inner)) |field| {
                if (is_enum) self.reject(m.*, "an enum has no fields to make read-only");
                try self.read_only_members.put(self.allocator(), field.list.id, {});
                inner = field;
            }
            // A bare name is a variant; in a struct, the checker rejects
            // it, and any other member that is not a field or method.
            switch (inner.kind() orelse .variant) {
                .@":", .default, .fun, .sub => {},
                .drop_decl => self.reject(m.*, "a `drop` body is never called by name, so it takes no `pub`"),
                .@"pub" => self.reject(inner, "`pub` is written once"),
                else => if (is_enum) self.reject(m.*, "an enum's variants are always public; remove the `pub`"),
            }
            if (inner == .list) try self.pub_members.put(self.allocator(), inner.list.id, {});
            m.* = inner;
        }
    }

    /// A method declared outside its type's body is the member it names
    /// (docs/internals/INTERNALS.md, "Methods outside the body"): in a module that
    /// declares `obj T[P]` or `enum T[P]`, `[pub] fun T[P].m(...)` is
    /// `[pub] fun m(...)` appended to `T`'s members, with `T`'s
    /// parameters named exactly as the declaration names them. One that
    /// names no such type is set aside (`detached`).
    fn attachMethods(self: *Parser, module: Sexp) std.mem.Allocator.Error!Sexp {
        const a = self.allocator();
        const decls = ir.Module.decls(module);
        var methods: usize = 0;
        for (decls) |d| methods += @intFromBool(ownerOf(d) != .nil);
        if (methods == 0) return module;
        const src = self.base.source;
        // Each type's members, with the methods it gains appended.
        var added = std.AutoArrayHashMapUnmanaged(usize, std.ArrayList(Sexp)).empty;
        var kept: std.ArrayList(Sexp) = .empty;
        const head = module.items().len - decls.len;
        try kept.appendSlice(a, module.items()[0..head]);
        for (decls) |d| {
            const owner = ownerOf(d);
            if (owner == .nil) {
                try kept.append(a, d);
                continue;
            }
            const method = if (d.isKind(.@"pub")) ir.Pub.decl(d) else d;
            const at = (if (owner == .src) typeDeclNamed(src, decls, leafText(src, owner.src)) else null) orelse {
                try self.detached.append(a, d);
                continue;
            };
            if (!sameParams(src, ir.get(method, .owner_params), tparamsOf(unpub(decls[at])))) {
                try self.detached.append(a, d);
                continue;
            }
            const owner_params = ir.get(method, .owner_params);
            const named = ir.get(method, .name);
            if (named == .src and owner_params != .nil) for (owner_params.items()) |p| {
                if (p == .src and self.bounds.contains(p.src.pos)) {
                    try self.owner_bounds.put(a, named.src.pos, owner_params.items());
                    break;
                }
            };
            const items = @constCast(method.items());
            const fun = method.isKind(.fun);
            items[if (fun) ir.slot(.fun, .owner) else ir.slot(.sub, .owner)] = .nil;
            items[if (fun) ir.slot(.fun, .owner_params) else ir.slot(.sub, .owner_params)] = .nil;
            if (d.isKind(.@"pub")) try self.pub_members.put(a, method.list.id, {});
            const name = ir.get(method, .name);
            if (name == .src) try self.outside_members.put(a, name.src.pos, {});
            const entry = try added.getOrPut(a, at);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(a, method);
        }
        const out = kept.items;
        for (out[head..]) |*d| {
            const at = std.mem.indexOfScalar(usize, added.keys(), indexIn(decls, d.*) orelse continue) orelse continue;
            const extra = added.values()[at].items;
            const ty = unpub(d.*);
            const members = try std.mem.concat(a, Sexp, &.{ ty.items(), extra });
            const node: Sexp = .{ .list = parser.List.withId(members, ty.list.id) };
            if (d.isKind(.@"pub")) {
                @constCast(d.items())[ir.slot(.@"pub", .decl)] = node;
            } else d.* = node;
        }
        return .{ .list = parser.List.withId(out, module.list.id) };
    }

    /// A type declaration's compile-time parameters, or `_`.
    pub fn tparamsOf(ty: Sexp) Sexp {
        return if (ir.has(ty.kind() orelse return .nil, .tparams)) ir.get(ty, .tparams) else .nil;
    }

    /// The owner of a method declared outside a body, or `_`.
    fn ownerOf(decl: Sexp) Sexp {
        const d = unpub(decl);
        return if (d.isKind(.fun) or d.isKind(.sub)) ir.get(d, .owner) else .nil;
    }

    /// The index in `decls` of the `obj` or `enum` named `name`.
    fn typeDeclNamed(src: []const u8, decls: []const Sexp, name: []const u8) ?usize {
        for (decls, 0..) |d, i| {
            const t = unpub(d);
            switch (t.kind() orelse continue) {
                .@"struct", .@"enum", .generic_struct, .generic_enum => {},
                else => continue,
            }
            const n = ir.get(t, .name);
            if (n == .src and std.mem.eql(u8, leafText(src, n.src), name)) return i;
        }
        return null;
    }

    fn indexIn(decls: []const Sexp, d: Sexp) ?usize {
        for (decls, 0..) |e, i| if (e == .list and d == .list and e.list.id == d.list.id) return i;
        return null;
    }

    /// Whether a method's owner names its type's parameters (`[T, n]`)
    /// exactly as the type's declaration does (`[T, n: Int]`): the same
    /// names, bare, in the same order.
    pub fn sameParams(src: []const u8, written: Sexp, declared: Sexp) bool {
        const w = if (written == .nil) &[_]Sexp{} else written.items();
        const d = if (declared == .nil) &[_]Sexp{} else declared.items();
        if (w.len != d.len) return false;
        for (w, d) |x, y| {
            if (x != .src) return false;
            const name = if (y.isKind(.@":")) ir.get(y, .name) else y;
            if (name != .src or !std.mem.eql(u8, leafText(src, x.src), leafText(src, name.src))) return false;
        }
        return true;
    }

    /// Whether `member`, a field or method, is declared `pub`.
    pub fn isPubMember(self: *const Parser, member: Sexp) bool {
        return member == .list and self.pub_members.contains(member.list.id);
    }

    /// Whether `member`, a field, is declared `pub ?name: T`: other
    /// modules may read it, and only its own module may write it.
    pub fn isReadOnlyMember(self: *const Parser, member: Sexp) bool {
        return member == .list and self.read_only_members.contains(member.list.id);
    }

    /// The field `?name: T` (or `?name: T = v`) declares, or null: the
    /// grammar reads the `?` as a read sigil around the field.
    fn readOnlyField(m: Sexp) ?Sexp {
        if (!m.isKind(.read)) return null;
        const field = ir.Read.operand(m);
        return if (field.isKind(.@":") or field.isKind(.default)) field else null;
    }

    /// `a ?? b ?? c`: the grammar reads a chain left to right, `(a ?? b)
    /// ?? c`, and every pass reads it nested to the right, `a ?? (b ??
    /// c)`, which gives the same value and lets each fallback have the
    /// payload's type. A parenthesized left side keeps its grouping: it
    /// starts after the node that holds it. A jump fallback is
    /// `nearestFallback`'s.
    fn rightNested(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const right = ir.@"??".right(node);
        if (right.kind()) |k| switch (k) {
            .@"return", .@"break", .@"continue" => return node,
            else => {},
        };
        const left = ir.@"??".left(node);
        if (!left.isKind(.@"??") or self.span(left).start != self.span(node).start) return node;
        const middle = ir.@"??".right(left);
        // The new right side starts where `middle` is written, with any
        // parentheses around it, so a grouped `middle` stays grouped.
        const src = self.base.source;
        var start = self.span(middle).start;
        while (start > 0 and (src[start - 1] == '(' or isSpaceBefore(src[start - 1]))) start -= 1;
        while (start < self.span(middle).start and isSpaceBefore(src[start])) start += 1;
        const inner = try self.rightNested(try self.base.newNode(.@"??", &.{ middle, right }, .{ .start = start, .end = self.span(node).end }));
        return self.base.newNode(.@"??", &.{ ir.@"??".left(left), inner }, self.span(node));
    }

    /// `a ?? b ?? return v`: the grammar reads a jump fallback after the
    /// whole chain before it, `(a ?? b) ?? return v`; `??` is
    /// right-associative, so the jump goes to the innermost right side,
    /// `a ?? (b ?? return v)`. A parenthesized left side keeps its
    /// grouping: it starts after the node that holds it.
    fn nearestFallback(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const right = ir.@"??".right(node);
        switch (right.kind() orelse return node) {
            .@"return", .@"break", .@"continue" => {},
            else => return node,
        }
        const left = ir.@"??".left(node);
        if (!left.isKind(.@"??") or self.span(left).start != self.span(node).start) return node;
        return self.attachFallback(left, right);
    }

    /// `chain ?? jump`, the jump attached to the last right side of the
    /// `??` chain that is not parenthesized.
    fn attachFallback(self: *Parser, chain: Sexp, jump: Sexp) std.mem.Allocator.Error!Sexp {
        const inner = ir.@"??".right(chain);
        const grouped = !inner.isKind(.@"??") or self.span(inner).end != self.span(chain).end;
        const new_right = if (grouped)
            try self.base.newNode(.@"??", &.{ inner, jump }, .{ .start = self.span(inner).start, .end = self.span(jump).end })
        else
            try self.attachFallback(inner, jump);
        return self.base.newNode(.@"??", &.{ ir.@"??".left(chain), new_right }, .{ .start = self.span(chain).start, .end = self.span(jump).end });
    }

    /// `*(T?)`, `~(T?)`, `*(~T?)`: a `?` suffix sits inside parentheses
    /// within a chain of handles, so it belongs to what a handle holds.
    /// In `*T?`, `*~T?`, and `*(T)?` every suffix follows the whole chain:
    /// each handle and each suffix layer starts at the token after the
    /// sigil before it.
    fn noteParenSuffix(self: *Parser, node: Sexp) std.mem.Allocator.Error!void {
        var e = node;
        while (true) {
            const at = self.afterSigil(e);
            var op = ir.get(e, .operand);
            if (op.isKind(.share) or op.isKind(.weak) or op.isKind(.box)) {
                if (self.span(op).start == at) {
                    e = op;
                    continue;
                }
                // `*(~T?)`: a parenthesized handle with a suffix of its own.
                while (op.isKind(.share) or op.isKind(.weak) or op.isKind(.box)) op = ir.get(op, .operand);
                if (op.isKind(.propagate_none)) try self.paren_suffixes.put(self.allocator(), node.list.id, {});
                return;
            }
            while (op.isKind(.propagate_none)) : (op = ir.PropagateNone.value(op)) {
                if (self.span(op).start != at) return self.paren_suffixes.put(self.allocator(), node.list.id, {});
            }
            return;
        }
    }

    /// A type's prefix sigil touches its operand. The lexer checks every
    /// other prefix; a sigil after a type's `]` (`[]*T`) reads to it as a
    /// suffix, which may stand apart.
    fn touchesOperand(self: *Parser, node: Sexp) void {
        const at = self.span(node).start;
        const src = self.base.source;
        // The view inside `^?T` has no sigil of its own: the box's `^?` is
        // checked as one token pair.
        if (at >= src.len or std.mem.findScalar(u8, "<>+-?!*~^", src[at]) == null) return;
        if (!isSpace(if (at + 1 < src.len) src[at + 1] else 0) or self.failure != null) return;
        self.failure = .{ .severity = .@"error", .pos = at, .end = at + 1, .message = self.detachedPrefix(.{ .cat = .err, .pre = 0, .pos = at, .len = 1 }) };
    }

    /// Whether `node`, a `share` or `weak`, has a parenthesized suffix in
    /// its operand: `*(T?)`, not `*T?` or `*(T)?`.
    pub fn hasParenSuffix(self: *const Parser, node: Sexp) bool {
        return node == .list and self.paren_suffixes.contains(node.list.id);
    }

    /// Record, for the `for` loop `loop` whose source was written after
    /// `sigil`, a `?`, the source with that sigil on the receiver of its
    /// first method call, when the receiver-sigil rule puts it there
    /// (`loop_receivers`).
    fn loopReceiver(self: *Parser, loop: Sexp, sigil: Sexp) std.mem.Allocator.Error!void {
        const lent = try self.base.newNode(sigil.kind().?, &.{ir.For.source(loop)}, self.span(sigil));
        const moved = try self.receiverSigil(lent);
        if (moved.list.id == lent.list.id) return;
        try self.loop_receivers.put(self.allocator(), loop.list.id, moved);
    }

    /// `>t`: the call `<t.wait()` makes, `(call _ (member (move t) wait))`,
    /// with a hidden `wait` (`isWaitCall`). Every node spans the `>t`, so
    /// a message quotes it as written, and the move is a receiver sigil,
    /// as the one `<t.wait()` writes is.
    fn waitCall(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const at = self.span(node);
        const moved = try self.base.newNode(.move, &.{ir.get(node, .operand)}, at);
        try self.receiver_sigils.put(self.allocator(), moved.list.id, {});
        const member = try self.base.newNode(.member, &.{ moved, hiddenLeaf(at.start, .wait) }, at);
        return self.base.newNode(.call, &.{ .nil, member }, at);
    }

    /// A wait takes a name alone, and a `!` or `?` after it applies to
    /// what it gives: `>t!` is `(>t)!`. Anything else after it is written
    /// on the parenthesized wait, so it never reads as the task's own:
    /// `(>t).len`, not `>t.len`.
    fn waitTakesName(self: *Parser, node: Sexp, head: Sexp) void {
        var w = head;
        while (w.isKind(.propagate) or w.isKind(.propagate_none)) w = ir.get(w, .value);
        if (!isWaitCall(w) or self.failure != null) return;
        const src = self.base.source;
        var after = self.span(head).end;
        while (after < src.len and (src[after] == ' ' or src[after] == '\t')) after += 1;
        if (after < src.len and src[after] == ')') return;
        const whole = self.span(node);
        const written = diag.textBetween(src, self.span(head).start, self.span(head).end);
        const rest = diag.textBetween(src, self.span(head).end, whole.end);
        // `>f(x)` and `>f(x)&`: a wait takes a task that is held, which a
        // call is not.
        if (node.isKind(.call) and w.list.id == head.list.id) {
            const call = diag.textBetween(src, self.span(head).start + 1, whole.end);
            self.failure = .{
                .severity = .@"error",
                .pos = self.span(head).start,
                .end = whole.end,
                .message = (if (ir.Call.task(node) != .nil)
                    std.fmt.allocPrint(self.allocator(), "`>{s}` starts a task and waits for it at once, which is the call itself: write `{s}`", .{ call, call[0 .. call.len - 1] })
                else
                    std.fmt.allocPrint(self.allocator(), "`>` waits for a task that is held: make the call a task and bind it, `t = {s}&`, then wait for it, `>t`", .{call})) catch "a wait takes a task that is held: `t = f(x)&`, then `>t`",
            };
            return;
        }
        self.failure = .{
            .severity = .@"error",
            .pos = self.span(head).end,
            .end = whole.end,
            .message = std.fmt.allocPrint(self.allocator(), "`{s}` waits for a task, and `{s}` applies to what it gives: write `({s}){s}`; to wait for a task that `{s}{s}` holds, take it out to a name first, then wait for that, `>t`", .{ written, rest, written, rest, written[1..], rest }) catch "a wait takes a name alone: write `(>t).x`",
        };
    }

    /// The source of the `for` loop `loop` with its sigil on the
    /// receiver of its first method call (`loop_receivers`), or null.
    pub fn loopReceiverSource(self: *const Parser, loop: Sexp) ?Sexp {
        return if (loop == .list) self.loop_receivers.get(loop.list.id) else null;
    }

    /// Whether `node` is a receiver sigil the wrapper moved onto the
    /// receiver: `!v` in `!v.push(x)`, not in `(!v).push(x)`.
    pub fn isReceiverSigil(self: *const Parser, node: Sexp) bool {
        return node == .list and self.receiver_sigils.contains(node.list.id);
    }

    /// Whether `node`, a `(: name type)`, was written `name: once type`:
    /// a parameter the function calls at most once.
    pub fn isOnceParam(self: *const Parser, node: Sexp) bool {
        return node == .list and self.once_params.contains(node.list.id);
    }

    /// Where the token after the sigil that starts `node` starts, past
    /// any whitespace, line joins, and comments.
    fn afterSigil(self: *const Parser, node: Sexp) u32 {
        var probe = BaseLexer.init(self.base.source);
        probe.pos = self.span(node).start + 1;
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .comment, .newline, .skip => continue,
                else => return t.pos,
            }
        }
    }

    /// `?`, `!`, and `<` before a place (a name and the fields and elements
    /// after it) followed by a method call apply to the place; the call
    /// and every postfix after it apply to the lent or moved place:
    ///   (write (propagate_none (call (member v pop))))
    ///   → (propagate_none (call (member (write v) pop)))
    /// The sigil reaches the receiver of the chain's first method call.
    /// A `!` reaches one that is a value no name holds too: one a call
    /// that is no method call makes (`!mk().bump()` is
    /// `(!mk()).bump()`), a literal, or a parenthesized expression
    /// (`!(+s).bump()`); a call of a call's value is walked through to
    /// the first call (`!a.b(x)(y).g()` is `(!a).b(x)(y).g()`). Anything
    /// else keeps its
    /// sigil outside: a chain that is all place (`!x.v`), a `?` or `<`
    /// chain whose head is called (`<f(x).g()`), and one whose spine is
    /// parenthesized (`!(v.pop())`), which starts after the token after
    /// the sigil, a `(`.
    fn receiverSigil(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const tag: parser.Tag = node.kind().?;
        const at = self.afterSigil(node);
        // `!` lends any value to write, so its chain may start from a
        // value no name holds: a call that is no method call
        // (`!mk().bump()`), a literal (`![a, b][0].bump()`), or a
        // parenthesized expression (`!(+s).bump()`).
        const any_head = tag == .write;
        // The chain from the operand down to its head, outermost first.
        var chain: std.ArrayList(Sexp) = .empty;
        var e = ir.get(node, .operand);
        while (true) {
            if (self.span(e).start != at) {
                if (!any_head or chain.items.len == 0) return node;
                try chain.append(self.allocator(), e);
                break;
            }
            try chain.append(self.allocator(), e);
            e = switch (e.kind() orelse break) {
                .propagate, .propagate_none => ir.get(e, .value),
                .member, .index, .inst => ir.get(e, .object),
                // A call of a call's value (`a.b(x)(y)`) is walked to
                // the first call, as before.
                .call => if (any_head and !isMethodCallee(ir.Call.callee(e)) and !ir.Call.callee(e).isKind(.call)) break else ir.Call.callee(e),
                else => if (any_head) break else return node,
            };
        }
        const spine = chain.items;
        const n = spine.len;
        // Grow the place up from the head through fields and elements,
        // stopping at the member a call follows, directly or after a
        // bracket list (`!v.put[2](x)`, compile-time arguments): the
        // method.
        var top = n - 1;
        while (top > 0) {
            const up = spine[top - 1];
            if (up.isKind(.member) and top >= 2 and spine[top - 2].isKind(.call)) break;
            if (up.isKind(.member) and top >= 3 and isBracketList(spine[top - 2]) and spine[top - 3].isKind(.call)) break;
            if (!up.isKind(.member) and !up.isKind(.index)) return node;
            top -= 1;
        }
        if (top == 0) return node;
        const place = spine[top];
        var out = try self.base.newNode(tag, &.{place}, .{ .start = self.span(node).start, .end = self.span(place).end });
        try self.receiver_sigils.put(self.allocator(), out.list.id, {});
        var i = top;
        while (i > 0) {
            i -= 1;
            const link = spine[i];
            const slot = switch (link.kind().?) {
                .propagate => ir.slot(.propagate, .value),
                .propagate_none => ir.slot(.propagate_none, .value),
                .member => ir.slot(.member, .object),
                .index => ir.slot(.index, .object),
                .inst => ir.slot(.inst, .object),
                .call => ir.slot(.call, .callee),
                else => unreachable,
            };
            const copy = try self.allocator().dupe(Sexp, link.items());
            copy[slot] = out;
            out = .{ .list = parser.List.withId(copy, link.list.id) };
        }
        return out;
    }

    /// `(lambda _ entries _ body)`: sigiled entries are captures, the
    /// rest parameters. Captures come first.
    fn splitBars(self: *Parser, node: Sexp, items: []Sexp) std.mem.Allocator.Error!void {
        const bars = ir.Lambda.params(node);
        var caps: std.ArrayList(Sexp) = .empty;
        var params: std.ArrayList(Sexp) = .empty;
        var paths: std.ArrayList(Sexp) = .empty;
        for (bars.items()) |e| {
            const is_capture = if (e.kind()) |k| switch (k) {
                .cap_clone, .cap_move, .cap_weak, .cap_read, .cap_write => true,
                else => false,
            } else false;
            if (!is_capture) {
                try params.append(self.allocator(), e);
                continue;
            }
            if (params.items.len > 0) self.reject(e, "captures come before parameters in a closure's bar list: `|+v, a| ...`");
            const cap = try self.capturePlace(e);
            if (isPathCapture(ir.get(cap, .name))) try paths.append(self.allocator(), cap);
            try caps.append(self.allocator(), cap);
        }
        // In the body, each captured path names its capture.
        if (paths.items.len > 0) {
            const at = ir.slot(.lambda, .body);
            items[at] = try self.namePaths(items[at], paths.items);
        }
        items[ir.slot(.lambda, .captures)] = if (caps.items.len > 0) try self.base.newNode(.captures, caps.items, .{
            .start = self.span(caps.items[0]).start,
            .end = self.span(caps.items[caps.items.len - 1]).end,
        }) else .nil;
        items[ir.slot(.lambda, .params)] = if (params.items.len > 0) .{ .list = parser.List.withId(params.items, bars.list.id) } else .nil;
    }

    /// A capture as the grammar gives it, `(cap_read _ place)`, as the
    /// passes read it: a name is the capture's name, `(cap_read x)`; a
    /// field path keeps the lend its sigil makes there as its value, and
    /// a name spanning the path from the sigil, `(cap_read ?p.a (read
    /// (member p a)))`, which the body's paths name (`namePaths`).
    fn capturePlace(self: *Parser, cap: Sexp) std.mem.Allocator.Error!Sexp {
        const kind = cap.kind().?;
        const place = ir.get(cap, .value);
        const out = try self.allocator().alloc(Sexp, 3);
        out[0] = .{ .tag = kind };
        out[ir.slot(.cap_read, .name)] = .nil;
        out[ir.slot(.cap_read, .value)] = .nil;
        const node: Sexp = .{ .list = parser.List.withId(out, cap.list.id) };
        if (place == .src) {
            out[ir.slot(.cap_read, .name)] = place;
            return node;
        }
        const at = self.span(cap);
        const text = self.pathText(place) orelse {
            const shown = diag.textBetween(self.base.source, self.span(place).start, self.span(place).end);
            self.reject(place, if (place.isKind(.index))
                std.fmt.allocPrint(self.allocator(), "a capture names a local or a field of one, not an element: lend it first, `x = ?{s}`, and capture `?x`", .{shown}) catch "a capture names a local or a field of one, not an element"
            else
                std.fmt.allocPrint(self.allocator(), "a capture names a local or a field of one: bind `{s}` to a name first, and capture the name", .{shown}) catch "a capture names a local or a field of one");
            return node;
        };
        const lend: parser.Tag = switch (kind) {
            .cap_clone => .clone,
            .cap_move => .move,
            .cap_weak => .weak,
            .cap_read => .read,
            .cap_write => .write,
            else => unreachable,
        };
        out[ir.slot(.cap_read, .name)] = .{ .src = .{ .pos = at.start, .len = @intCast(text.len + 1), .id = path_capture_id } };
        out[ir.slot(.cap_read, .value)] = try self.base.newNode(lend, &.{place}, at);
        return node;
    }

    /// The source text of `place` when it is a field path written as one
    /// (`p.a.b`, `@template`): a name, or `@`, then `.field` steps, with
    /// nothing between them. Null for anything else.
    fn pathText(self: *const Parser, place: Sexp) ?[]const u8 {
        if (!place.isKind(.member)) return null;
        var root = place;
        while (root.isKind(.member)) root = ir.Member.object(root);
        if (root != .src) return null;
        const extent = self.span(place);
        const text = diag.textBetween(self.base.source, extent.start, extent.end);
        // The path's own text, spelled from its parts, is the source's.
        var p = place;
        var end = text.len;
        while (p.isKind(.member)) : (p = ir.Member.object(p)) {
            const field = leafText(self.base.source, ir.Member.name(p).src);
            if (end < field.len or !std.mem.eql(u8, text[end - field.len .. end], field)) return null;
            end -= field.len;
            const self_member = ir.Member.object(p) == .src and std.mem.eql(u8, leafText(self.base.source, ir.Member.object(p).src), "@");
            if (!self_member) {
                if (end == 0 or text[end - 1] != '.') return null;
                end -= 1;
            }
        }
        if (!std.mem.eql(u8, text[0..end], leafText(self.base.source, root.src))) return null;
        return text;
    }

    /// Whether member chain `node` names the path `text` (`p.a`,
    /// `@template`) by its parts, however it is spaced.
    fn spellsPath(self: *const Parser, node: Sexp, text: []const u8) bool {
        var rest = text;
        var p = node;
        while (p.isKind(.member)) : (p = ir.Member.object(p)) {
            const field = leafText(self.base.source, ir.Member.name(p).src);
            if (!std.mem.endsWith(u8, rest, field)) return false;
            rest = rest[0 .. rest.len - field.len];
            const at_self = ir.Member.object(p) == .src and std.mem.eql(u8, leafText(self.base.source, ir.Member.object(p).src), "@");
            if (!at_self) {
                if (!std.mem.endsWith(u8, rest, ".")) return false;
                rest = rest[0 .. rest.len - 1];
            }
        }
        return p == .src and std.mem.eql(u8, rest, leafText(self.base.source, p.src));
    }

    /// `body` with each member chain that spells a captured path in
    /// `paths` replaced by a name spanning it, which names the capture.
    fn namePaths(self: *Parser, body: Sexp, paths: []const Sexp) std.mem.Allocator.Error!Sexp {
        return try self.namePathsIn(body, paths) orelse body;
    }

    /// `namePaths`, or null when `node` holds no captured path.
    fn namePathsIn(self: *Parser, node: Sexp, paths: []const Sexp) std.mem.Allocator.Error!?Sexp {
        if (node != .list) return null;
        if (node.isKind(.member)) for (paths) |cap| {
            const path = leafText(self.base.source, ir.get(cap, .name).src);
            if (!self.spellsPath(node, path)) continue;
            const text = self.pathText(node) orelse {
                self.reject(node, std.fmt.allocPrint(self.allocator(), "write `{s}`, the path this closure captures, on one line", .{path}) catch "write the path this closure captures on one line");
                return null;
            };
            return .{ .src = .{ .pos = self.span(node).start, .len = @intCast(text.len), .id = 0 } };
        };
        const items = node.items();
        var copy: ?[]Sexp = null;
        for (items, 0..) |child, i| {
            const named = try self.namePathsIn(child, paths) orelse continue;
            if (copy == null) copy = try self.allocator().dupe(Sexp, items);
            copy.?[i] = named;
        }
        return if (copy) |c| .{ .list = parser.List.withId(c, node.list.id) } else null;
    }

    /// A statement `<e` drops what it moves: `(move x)` of a name becomes
    /// `(drop x)`, keeping its node id; `(move e)` of anything else is
    /// held by a new `(drop (move e))`, so that every pass reads the move
    /// as `_ = <e` reads it. `valueTail` undoes it where the value is used.
    fn dropStatement(self: *Parser, slot: *Sexp) std.mem.Allocator.Error!void {
        if (!slot.isKind(.move)) return;
        const operand = ir.Move.operand(slot.*);
        if (operand == .src and isBindingName(self.base.source, operand)) {
            @constCast(slot.items())[0] = .{ .tag = .drop };
            return;
        }
        slot.* = try self.base.newNode(.drop, &.{slot.*}, self.span(slot.*));
    }

    /// A name a binding may have, self, `@`, too: not a literal,
    /// `true`, or `false`.
    fn isBindingName(source: []const u8, leaf: Sexp) bool {
        const text = leafText(source, leaf.src);
        if (std.mem.eql(u8, text, "@")) return true;
        if (text.len == 0 or !isIdentStart(text[0])) return false;
        return keyword(text) == null;
    }

    /// `slot` (already walked, so its lists are freshly allocated) is in
    /// value position: a drop `dropStatement` made of its last statement
    /// is the move again.
    fn valueTail(self: *Parser, slot: *Sexp) std.mem.Allocator.Error!void {
        const kind = slot.kind() orelse return;
        const items = @constCast(slot.items());
        switch (kind) {
            .drop => {
                const target = ir.Drop.target(slot.*);
                if (target == .list) {
                    slot.* = target;
                } else {
                    items[0] = .{ .tag = .move };
                }
            },
            .block => if (items.len > 1) try self.valueTail(&items[items.len - 1]),
            .@"if" => {
                try self.valueTail(&items[ir.slot(.@"if", .then)]);
                try self.valueTail(&items[ir.slot(.@"if", .@"else")]);
            },
            .match => for (ir.Match.arms(slot.*)) |arm| try self.valueTail(&@constCast(arm.items())[ir.slot(.arm, .body)]),
            .@"catch" => try self.valueTail(&items[ir.slot(.@"catch", .handler)]),
            .@"while" => try self.valueTail(&items[ir.slot(.@"while", .@"else")]),
            .@"for" => try self.valueTail(&items[ir.slot(.@"for", .@"else")]),
            .labeled => try self.valueTail(&items[ir.slot(.labeled, .stmt)]),
            .raw_block => try self.valueTail(&items[ir.slot(.raw_block, .body)]),
            else => {},
        }
    }

    /// A closure whose type returns nothing has no value: the last line
    /// `valueTail` kept as a move, and that of each branch ending it, is a
    /// statement `<e` again, which drops (`dropStatement`). The type
    /// checker calls it on the body of such a closure before any pass reads
    /// it, and it changes nothing a second time.
    pub fn dropTail(self: *const Parser, slot: *Sexp) std.mem.Allocator.Error!void {
        const mutable: *Parser = @constCast(self);
        try mutable.dropTailOf(slot);
    }

    /// A closure that declares fewer parameters than the function type it
    /// is checked against is the same closure with `_` for each trailing
    /// parameter it leaves out. The type checker calls it on a closure
    /// literal before any pass reads the parameters; it changes nothing
    /// when the closure already has `count` parameters.
    pub fn padLambda(self: *const Parser, lambda: Sexp, count: usize) std.mem.Allocator.Error!void {
        const mutable: *Parser = @constCast(self);
        const slot = &@constCast(lambda.items())[ir.slot(.lambda, .params)];
        const have = slot.items();
        if (have.len >= count) return;
        const out = try mutable.allocator().alloc(Sexp, count);
        @memcpy(out[0..have.len], have);
        const at = mutable.span(lambda).start;
        for (out[have.len..]) |*p| {
            mutable.padded += 1;
            var leaf = hiddenLeaf(at, .discard);
            leaf.src.pos = @intCast(mutable.base.source.len + mutable.padded);
            try mutable.pad_homes.append(mutable.allocator(), at);
            p.* = leaf;
        }
        slot.* = try mutable.base.newList(out, .{ .start = at, .end = at });
    }

    fn dropTailOf(self: *Parser, slot: *Sexp) std.mem.Allocator.Error!void {
        const kind = slot.kind() orelse return;
        const items = @constCast(slot.items());
        switch (kind) {
            .move => try self.dropStatement(slot),
            .block => if (items.len > 1) try self.dropTailOf(&items[items.len - 1]),
            .@"if" => {
                try self.dropTailOf(&items[ir.slot(.@"if", .then)]);
                try self.dropTailOf(&items[ir.slot(.@"if", .@"else")]);
            },
            .match => for (ir.Match.arms(slot.*)) |arm| try self.dropTailOf(&@constCast(arm.items())[ir.slot(.arm, .body)]),
            .@"while" => try self.dropTailOf(&items[ir.slot(.@"while", .@"else")]),
            .@"for" => try self.dropTailOf(&items[ir.slot(.@"for", .@"else")]),
            .labeled => try self.dropTailOf(&items[ir.slot(.labeled, .stmt)]),
            .raw_block => try self.dropTailOf(&items[ir.slot(.raw_block, .body)]),
            else => {},
        }
    }

    // -------------------------------------------------------------------------
    // Loops over an iterator
    //
    // Typecheck finds the `for` loops whose source is an iterator, since
    // the type of a source is known only there, and the module is checked
    // again on this rewrite (docs/internals/INTERNALS.md, "Loops over an iterator").
    // The nodes it builds are IR nodes like the parser's: each spans the
    // loop's source, and a name no source text holds (a method's `next`,
    // the hidden binding) is a leaf at a position inside the loop's `for`
    // keyword, which no other leaf has, with the name's text from
    // `leafText`. So every position the checkers order by lies in the loop,
    // as in the loop written by hand.
    // -------------------------------------------------------------------------

    const IterRewrite = struct {
        loops: []const IterLoop,

        fn find(self: IterRewrite, node: Sexp) ?usize {
            if (node != .list or !node.isKind(.@"for")) return null;
            for (self.loops, 0..) |l, i| if (l.node == node.list.id) return i;
            return null;
        }
    };

    /// Each string literal of `lits` in `tree` as the literal it is
    /// where it stands: where a `U8` goes, the integer leaf of its byte,
    /// spanning the string; where a `[N]U8` goes, the array literal of
    /// its bytes, each a leaf inside the string, so that no two share a
    /// position. Every other node keeps its position and id.
    pub fn byteLiterals(self: *Parser, tree: Sexp, lits: []const ByteLiteral) std.mem.Allocator.Error!void {
        if (lits.len == 0) return;
        var at: std.AutoHashMapUnmanaged(u32, usize) = .empty;
        defer at.deinit(self.allocator());
        for (lits, 0..) |l, i| try at.put(self.allocator(), l.pos, i);
        try self.bytesIn(tree, lits, &at);
    }

    fn bytesIn(self: *Parser, node: Sexp, lits: []const ByteLiteral, at: *const std.AutoHashMapUnmanaged(u32, usize)) std.mem.Allocator.Error!void {
        if (node != .list) return;
        for (@constCast(node.items())) |*slot| switch (slot.*) {
            .src => |leaf| if (at.get(leaf.pos)) |i| {
                const lit = lits[i];
                if (!lit.array) {
                    slot.* = byteLeaf(leaf.pos, leaf.len, lit.bytes[0]);
                    continue;
                }
                const elems = try self.allocator().alloc(Sexp, lit.bytes.len);
                for (lit.bytes, elems, 0..) |b, *e, k| e.* = byteLeaf(leaf.pos + 1 + @as(u32, @intCast(k)), 1, b);
                slot.* = try self.base.newNode(.array, elems, .{ .start = leaf.pos, .end = leafEnd(self.base.source, leaf) });
            },
            .list => try self.bytesIn(slot.*, lits, at),
            else => {},
        };
    }

    /// Rewrite each `for` of `loops` in `tree` into the `while` it means.
    /// Every other node keeps its position and id.
    pub fn desugarIterLoops(self: *Parser, tree: Sexp, loops: []const IterLoop) std.mem.Allocator.Error!void {
        try self.desugarIn(tree, .{ .loops = loops });
    }

    fn desugarIn(self: *Parser, node: Sexp, state: IterRewrite) std.mem.Allocator.Error!void {
        if (node != .list) return;
        const items = @constCast(node.items());
        for (items) |*slot| slot.* = try self.desugarChild(slot.*, state);
    }

    /// `child` with the loops inside it rewritten, or what replaces it
    /// when it is one: a loop that holds its source is a block of the
    /// binding and the `while`, around the label when it has one.
    fn desugarChild(self: *Parser, child: Sexp, state: IterRewrite) std.mem.Allocator.Error!Sexp {
        const labeled = child.isKind(.labeled);
        const loop = if (labeled) ir.Labeled.stmt(child) else child;
        const at = state.find(loop) orelse {
            try self.desugarIn(child, state);
            return child;
        };
        try self.desugarIn(loop, state);
        const built = try self.iterWhile(loop, state.loops[at]);
        if (labeled) {
            const copy = try self.allocator().dupe(Sexp, child.items());
            copy[ir.slot(.labeled, .stmt)] = built.loop;
            const out: Sexp = .{ .list = parser.List.withId(copy, child.list.id) };
            return if (built.hold) |h| self.base.newNode(.block, &.{ h, out }, self.span(child)) else out;
        }
        return if (built.hold) |h| self.base.newNode(.block, &.{ h, built.loop }, self.span(child)) else built.loop;
    }

    const IterWhile = struct { loop: Sexp, hold: ?Sexp };

    /// `for x in it` as `while (!it).next() as x`; a held source `e` is
    /// bound first, `h = e` (`h = <e` for a place the loop takes), and
    /// walked as `(!h)`.
    fn iterWhile(self: *Parser, loop: Sexp, l: IterLoop) std.mem.Allocator.Error!IterWhile {
        const source = ir.For.source(loop);
        const binding = ir.For.@"var"(loop);
        const at = self.span(source);
        const key = self.span(loop).start;
        var hold: ?Sexp = null;
        var receiver = source;
        if (l.source != .place) {
            const value = switch (l.source) {
                .moved => try self.base.newNode(.move, &.{source}, at),
                .lent => self.loopReceiverSource(loop).?,
                else => source,
            };
            // `h` is declared before the loop, at the position before
            // its `for`, so the loop does not enclose its declaration:
            // what it holds stays in force through every iteration
            // (`ownership.Checker.liveFrom`).
            hold = try self.base.newNode(.set, &.{ .{ .tag = .shadow }, hiddenLeaf(key - 1, .iterator), .nil, value }, at);
            receiver = hiddenLeaf(key + 2, .iterator);
        }
        const lend = try self.base.newNode(.write, &.{receiver}, at);
        const member = try self.base.newNode(.member, &.{ lend, hiddenLeaf(key, .next) }, at);
        const call = try self.base.newNode(.call, &.{ .nil, member }, at);
        const bound = try self.base.newNode(.as, &.{ call, binding }, .{ .start = self.span(binding).start, .end = at.end });
        const out = try self.allocator().alloc(Sexp, 5);
        out[0] = .{ .tag = .@"while" };
        out[ir.slot(.@"while", .cond)] = bound;
        out[ir.slot(.@"while", .step)] = .nil;
        out[ir.slot(.@"while", .body)] = ir.For.body(loop);
        out[ir.slot(.@"while", .@"else")] = ir.For.@"else"(loop);
        return .{ .loop = .{ .list = parser.List.withId(out, loop.list.id) }, .hold = hold };
    }

    /// A bare `for xs` is `for _ in xs`: the variable the grammar left
    /// out is the discard name, at the `for` keyword.
    fn bareFor(self: *Parser, loop: Sexp, items: []Sexp) void {
        const slot = ir.slot(.@"for", .@"var");
        if (items[slot] != .nil) return;
        const at = self.span(loop).start;
        items[slot] = hiddenLeaf(at, .discard);
    }

    /// Promote the source's `?xs` / `!xs` / `<xs` wrapper into the mode.
    fn normFor(items: []Sexp) void {
        const node = Sexp.listOf(items);
        if (ir.For.mode(node).tag != .iter) return;
        const source = ir.For.source(node);
        const kind = source.kind() orelse return;
        switch (kind) {
            .read, .write, .move => {
                items[ir.slot(.@"for", .mode)] = .{ .tag = kind };
                items[ir.slot(.@"for", .source)] = ir.get(source, .operand);
            },
            else => {},
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn expectCats(source: []const u8, expected: []const TokenCat) !void {
    var lx = Lexer.init(source);
    for (expected) |want| {
        const got = lx.next();
        testing.expectEqual(want, got.cat) catch |e| {
            std.debug.print("source: {s}\n  at `{s}`\n", .{ source, lx.base.text(got) });
            return e;
        };
    }
}

/// The token at `index` reads `want`, and the next one starts after it.
fn expectText(source: []const u8, index: usize, want: []const u8) !void {
    var lx = Lexer.init(source);
    for (0..index) |_| _ = lx.next();
    const got = lx.next();
    try testing.expectEqual(TokenCat.ident, got.cat);
    try testing.expectEqualStrings(want, lx.base.text(got));
    try testing.expectEqual(TokenCat.eof, lx.next().cat);
}

test "keywords are reserved; `new` only at statement start" {
    try testing.expectEqual(TokenCat.@"else", keyword("else").?);
    try testing.expect(keyword("fn") == null);
    for ([_][]const u8{ "trait", "impl", "where", "async", "await", "yield", "when", "const" }) |w| {
        try testing.expect(keyword(w) != null);
    }
    try testing.expect(keyword("var") == null);
    // Every keyword category but `new`, `obj`, `inline`, `called`, and
    // `rarely` is a lexer rule.
    for (@intFromEnum(TokenCat.true)..@intFromEnum(TokenCat.yield) + 1) |c| {
        const cat: TokenCat = @enumFromInt(c);
        if (cat == .obj or cat == .api or cat == .add or cat == .@"inline" or cat == .called or cat == .rarely) continue;
        try testing.expectEqual(cat, keyword(@tagName(cat)).?);
        if (cat != .new) try expectCats(@tagName(cat), &.{cat});
    }
    try expectCats("new x = 1", &.{ .new, .ident, .assign, .integer });
    try expectCats("p = Point.new(1)", &.{ .ident, .assign, .ident, .dot, .ident, .lparen, .integer, .rparen });
    try expectCats("O(new: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
}

test "`obj` is a keyword only where a declaration starts; `struct` is a name" {
    try testing.expect(keyword("obj") == null and keyword("struct") == null);
    try expectCats("obj P", &.{ .obj, .ident });
    try expectCats("pub obj P[T] unique", &.{ .@"pub", .obj, .ident, .lbracket, .ident, .rbracket, .ident });
    try expectCats("obj = 5", &.{ .ident, .assign, .integer });
    try expectCats("obj.x = obj", &.{ .ident, .dot, .ident, .assign, .ident });
    try expectCats("f(obj: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
    try expectCats("x = obj P", &.{ .ident, .assign, .ident, .ident });
    try expectCats("struct P", &.{ .ident, .ident });
    try parses("obj = 5\n");
    try parses("struct = 5\nobj = struct\n");
    try parses("fun f(obj: Int, struct: Int) -> Int\n  obj + struct\n");
    try parses("obj P\n  obj: Int\n  struct: Int\n");
}

test "`inline` and `called` are keywords only before a declaration's `fun` or `sub`, and `rarely` only alone on its line" {
    try testing.expect(keyword("inline") == null and keyword("called") == null and keyword("rarely") == null);
    try expectCats("inline fun f()", &.{ .@"inline", .fun, .ident, .lparen, .rparen });
    try expectCats("called fun f()", &.{ .called, .fun, .ident, .lparen, .rparen });
    try expectCats("called = 1", &.{ .ident, .assign, .integer });
    try expectCats("pub called sub s()", &.{ .@"pub", .called, .sub, .ident, .lparen, .rparen });
    try expectCats("rarely", &.{.rarely});
    try expectCats("rarely  # cold", &.{.rarely});
    try expectCats("rarely fun f()", &.{ .ident, .fun, .ident, .lparen, .rparen });
    try expectCats("rarely = 2", &.{ .ident, .assign, .integer });
    try expectCats("inline = 5", &.{ .ident, .assign, .integer });
    try expectCats("x = rarely", &.{ .ident, .assign, .ident });
    try expectCats("f(inline: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
    try expectCats("p.inline(rarely)", &.{ .ident, .dot, .ident, .lparen, .ident, .rparen });
    try parses("inline fun f() -> Int\n  1\n");
    try parses("obj P\n  inline: Int\n  rarely: Int\n  called sub m(?@)\n    pass\n  fun inline(?@) -> Int\n    @inline\n");
    try parses("fun f(inline: Int, rarely: Int) -> Int\n  inline + rarely\n");
    try parses("fun f(n: Int) -> Int\n  rarely\n  n\n");
}

test "a deeper line starting with `.` continues a complete statement" {
    // The chain joins the lines: no NEWLINE or INDENT between them.
    try expectCats("b = B()\n  .add(1)\n  .add(2)\nc = 3", &.{
        .ident, .assign, .ident, .lparen, .rparen, .dot, .ident, .lparen, .integer, .rparen,
        .dot,   .ident,  .lparen, .integer, .rparen, .newline, .ident, .assign, .integer,
    });
    // Blank and comment lines do not end it.
    try expectCats("b\n  .x\n\n  # c\n  .y", &.{ .ident, .dot, .ident, .dot, .ident });
    // A line at the statement's own indentation does not continue it.
    try expectCats("b\n.x", &.{ .ident, .newline, .dot, .ident });
    // `.5` is a number, not a member.
    try expectCats("b\n  .5", &.{ .ident, .indent, .real });
    // A line that opens a block is not continued: its block starts.
    try expectCats("match c\n  .red", &.{ .match, .ident, .indent, .dot, .ident });
    try expectCats("fun f() -> Int\n  .x", &.{ .fun, .ident, .lparen, .rparen, .arrow, .ident, .indent, .dot, .ident });
    try expectCats("obj P\n  x: Int\n    .y", &.{ .obj, .ident, .indent, .ident, .colon, .ident, .indent, .dot, .ident });
    // An arm written above its body: the body's first line is not a chain.
    try expectCats("match c\n  .red\n    .blue => 1", &.{ .match, .ident, .indent, .dot, .ident, .indent, .dot, .ident, .fat_arrow, .integer });
}

/// The tree of `source`'s first declaration, past any `pub`.
fn firstDecl(p: *Parser) !Sexp {
    const decl = ir.Module.decls(try p.parseTree())[0];
    return if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl;
}

/// Whether `source` declares a unique struct first.
fn structUnique(source: []const u8) !bool {
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    return ir.get(try firstDecl(&p), .unique) != .nil;
}

/// The origins of `source`'s first declaration, a function: how many
/// names follow `from`, 0 for `from static`, null for none.
fn originCount(source: []const u8) !?usize {
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const origins = ir.get(try firstDecl(&p), .origins);
    return if (origins == .nil) null else origins.items().len;
}

test "`unique` is a keyword only after an obj header's name or type parameters" {
    try testing.expect(keyword("unique") == null);
    try expectCats("obj R unique", &.{ .obj, .ident, .ident });
    try testing.expect(try structUnique("obj R unique\n  x: Int\n"));
    try testing.expect(try structUnique("pub obj R unique # note\n  x: Int\n"));
    try testing.expect(try structUnique("obj R[T] unique\n  x: T\n"));
    try testing.expect(!try structUnique("obj R[unique]\n  x: Int\n"));
    try testing.expect(!try structUnique("obj unique\n  x: Int\n"));
    try testing.expect(!try structUnique("obj R\n  unique: Bool\n"));
    try testing.expectError(error.ParseError, parses("enum E unique\n  a\n"));
    try parses("unique = x.unique\n");
    try expectCats("f(unique: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
}

test "`from` and `static` are keywords only after a function's result type" {
    try testing.expect(keyword("from") == null and keyword("static") == null);
    try testing.expectEqual(@as(?usize, 1), try originCount("fun f(a: ?T) -> ?T from a\n  a\n"));
    try testing.expectEqual(@as(?usize, 0), try originCount("pub fun f() -> ?String from static\n  s\n"));
    try testing.expectEqual(@as(?usize, 2), try originCount("fun f() -> T? from a, b\n  a\n"));
    try testing.expectEqual(@as(?usize, 1), try originCount("extern fun f(s: ?String) -> ?String from s\n"));
    try testing.expectEqual(@as(?usize, null), try originCount("fun span(from: Int) -> Int\n  from\n"));
    try testing.expectEqual(@as(?usize, null), try originCount("fun f() -> Int\n  from\n"));
    try testing.expectEqual(@as(?usize, null), try originCount("fun f(g: fun(Int) -> Int, from: Int) -> Int\n  from\n"));
    try parses("from = static\n");
    try parses("f = |x: Int| x\nfrom = 1\n");
}

/// The `keeps` list of `source`'s first declaration, a function: how
/// many names it lists, null for none.
fn keepsCount(source: []const u8) !?usize {
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const keeps = ir.get(try firstDecl(&p), .keeps);
    return if (keeps == .nil) null else keeps.items().len;
}

test "`keeps` is a keyword only at the end of a function's header" {
    try testing.expectEqual(@as(?usize, 1), try keepsCount("sub f(!@, s: ?String) keeps s\n  pass\n"));
    try testing.expectEqual(@as(?usize, 2), try keepsCount("fun f(o: !T, s: ?T) -> ?T from s keeps s, o\n  s\n"));
    try testing.expectEqual(@as(?usize, 1), try keepsCount("fun f(o: !T, s: ?T) -> Int keeps s\n  1\n"));
    try testing.expectEqual(@as(?usize, 1), try keepsCount("sub f(o: !T, s: ?T)! keeps s\n  pass\n"));
    try testing.expectEqual(@as(?usize, 1), try keepsCount("extern sub f(o: !T, s: ?T) keeps s\n"));
    try testing.expectEqual(@as(?usize, null), try keepsCount("fun keeps(keeps: Int) -> Int\n  keeps\n"));
    try testing.expectEqual(@as(?usize, null), try keepsCount("sub f(g: sub(Int), keeps: Int)\n  g(keeps)\n"));
    try parses("keeps = 1\nf(keeps: keeps)\n");
}

test "a prefix sigil touches its operand; after a value it is infix or a suffix" {
    for ([_][]const u8{ "a < b", "a<b", "a <b", "a< b" }) |src| try expectCats(src, &.{ .ident, .lt, .ident });
    for ([_][]const u8{ "a - 1", "a-1", "a -1" }) |src| try expectCats(src, &.{ .ident, .minus, .integer });
    try expectCats("x = <y", &.{ .ident, .assign, .lt, .ident });
    try expectCats("x = < y", &.{ .ident, .assign, .err });
    try expectCats("x = * y", &.{ .ident, .assign, .err });
    try expectCats("f(! x)", &.{ .ident, .lparen, .err });
    try expectCats("T? x! T ? x !", &.{ .ident, .question, .ident, .not_sym, .ident, .question, .ident, .not_sym });
    try expectCats("a | b | c", &.{ .ident, .bar, .ident, .bar, .ident });
    try expectCats("f = |a, +b| a", &.{ .ident, .assign, .bar_capture, .ident, .comma, .plus, .ident, .bar_capture, .ident });
    try expectCats("f = | +b , a | a", &.{ .ident, .assign, .bar_capture, .plus, .ident, .comma, .ident, .bar_capture, .ident });
}

test "`=!` binds fixed only with a space after it" {
    try expectCats("x =! y", &.{ .ident, .fixed_assign, .ident });
    try expectCats("x =! !y", &.{ .ident, .fixed_assign, .not_sym, .ident });
    try expectCats("x =!\ty", &.{ .ident, .fixed_assign, .ident });
    try expectCats("new x =! y", &.{ .new, .ident, .fixed_assign, .ident });
    try expectCats("x: Int =! 1", &.{ .ident, .colon, .ident, .fixed_assign, .integer });
    try expectCats("x = !y", &.{ .ident, .assign, .not_sym, .ident });
    try expectCats("x != y", &.{ .ident, .ne, .ident });
    for ([_][]const u8{ "x =!y", "x=!y", "x =!(y)", "x =!=y", "x =!= y", "x =!1", "x =!", "x =!\n", "x =!# c", "x =!\\\n  1" }) |src| {
        try expectCats(src, &.{ .ident, .err });
    }
    try expectLayout("x =! y", &.{});
    try expectLayout("x=! y", &.{.infix_after});
}

/// The spacing kinds the lexer records for `source`, in order.
fn expectLayout(source: []const u8, expected: []const Lexer.Layout.Kind) !void {
    var lx = Lexer.init(source);
    while (true) {
        const t = lx.next();
        if (t.cat == .eof or t.cat == .err) break;
    }
    const got = lx.layouts[0..lx.layout_count];
    testing.expectEqual(expected.len, got.len) catch |e| {
        std.debug.print("source: {s}\n", .{source});
        return e;
    };
    for (expected, got) |want, sp| try testing.expectEqual(want, sp.kind);
}

test "spacing: an infix operator is balanced; a postfix, a member, and an open range touch" {
    for ([_][]const u8{ "a < b", "a<b", "a - 1", "a-1", "x = -1", "x=1", "a ?? b", "0..n", "0 .. n", "f()!", "x?", "w.get()", "c = .red", "xs[..2]", "xs[a..]", "a < -b", "a<-b", "f(\n  a\n  .b())", "[]?T", "[2]*T", "break $a !n", "break $a (n)", "f = |a| a + 1", "while i < n : i += 1" }) |src| {
        try expectLayout(src, &.{});
    }
    try expectLayout("a <b", &.{.infix_before});
    try expectLayout("a< b", &.{.infix_after});
    try expectLayout("x =1", &.{.infix_before});
    try expectLayout("f() !", &.{.postfix});
    try expectLayout("[] ?T", &.{.postfix});
    try expectLayout("w . get()", &.{.member});
    try expectLayout("w .get()", &.{.member});
    try expectLayout("c = . red", &.{.enum_dot});
    try expectLayout("xs[.. 2]", &.{.range_end});
    try expectLayout("xs[a ..]", &.{.range_end});
    try expectLayout("0 ..n", &.{.infix_before});
    // Inside brackets a line break is whitespace, so a line starting
    // `-1` after a value is a subtraction with one side spaced.
    try expectLayout("f(a\n  -1)", &.{.infix_before});
    try expectLayout("a -1 + b *c", &.{ .infix_before, .infix_before });
}

test "`name:` is a keyword argument inside ( ), a name inside [ ]" {
    try expectCats("fun f[n: Int](x: Int)", &.{ .fun, .ident, .lbracket, .ident, .colon, .ident, .rbracket, .lparen, .kwarg_name, .colon, .ident, .rparen });
    try expectCats("pre = 1", &.{ .ident, .assign, .integer });
}

test "a statement label ends no operand" {
    try expectCats("$a: if x", &.{ .label, .ident, .label_colon, .@"if", .ident });
    try expectCats("$a: -x", &.{ .label, .ident, .label_colon, .minus, .ident });
    try expectCats("$a: (x)", &.{ .label, .ident, .label_colon, .lparen, .ident, .rparen });
    try expectCats("$a: $b: for x in y", &.{ .label, .ident, .label_colon, .label, .ident, .label_colon, .@"for", .ident, .in, .ident });
    try expectCats("$a:\n  x", &.{ .label, .ident, .label_colon, .indent, .ident, .outdent });
}

test "a `,` after `as name` outside brackets joins the names `as` binds" {
    try expectCats("if f() as a, b", &.{ .@"if", .ident, .lparen, .rparen, .as, .ident, .as_comma, .ident });
    try expectCats("while g() as a, b, c", &.{ .@"while", .ident, .lparen, .rparen, .as, .ident, .as_comma, .ident, .as_comma, .ident });
    try expectCats("f(x as a, b)", &.{ .ident, .lparen, .ident, .as, .ident, .comma, .ident, .rparen });
    try expectCats("q, r = f()", &.{ .ident, .comma, .ident, .assign, .ident, .lparen, .rparen });
}

test "`$name(` with the `(` touching is a builtin; `$name` alone is a label" {
    try expectCats("$size(T)", &.{ .dollar, .ident, .lparen, .ident, .rparen });
    try expectCats("$type(x)", &.{ .dollar, .ident, .lparen, .ident, .rparen });
    try expectCats("x = $size(T)", &.{ .ident, .assign, .dollar, .ident, .lparen, .ident, .rparen });
    try expectCats("break $size(T)", &.{ .@"break", .dollar, .ident, .lparen, .ident, .rparen });
    try expectCats("$size", &.{.err});
    try expectCats("$ size(T)", &.{.err});
    try expectCats("$size (T)", &.{.err});
    try expectCats("break $a", &.{ .@"break", .label, .ident });
    try expectCats("break $a (x)", &.{ .@"break", .label, .ident, .lparen, .ident, .rparen });
    try expectCats("break $a x if c", &.{ .@"break", .label, .ident, .ident, .post_if, .ident });
    try expectCats("continue $a if c", &.{ .@"continue", .label, .ident, .post_if, .ident });
    try expectCats("break $a -1", &.{ .@"break", .label, .ident, .minus, .integer });
    try expectCats("break $a-1", &.{ .@"break", .label, .ident, .err });
    try expectCats("break $a.red", &.{ .@"break", .label, .ident, .err });
    try expectCats("break $a - 1", &.{ .@"break", .label, .ident, .err });
    try expectCats("break $a |x| x", &.{ .@"break", .label, .ident, .bar_capture, .ident, .bar_capture, .ident });
    try expectCats("break $a, 1", &.{ .@"break", .label, .ident, .comma, .integer });
    try expectCats("break $for", &.{ .@"break", .err });
    try expectCats("$a for x in y", &.{.err});
    try expectCats("$a : for x in y", &.{.err});
    try expectCats("$ a: for x in y", &.{.err});
    try expectCats("$for: for x in y", &.{.err});
    try expectCats("x => $a: for y in z", &.{ .ident, .fat_arrow, .err });
    try expectCats("defer $a: for y in z", &.{ .@"defer", .err });
    try expectCats("x = $a", &.{ .ident, .assign, .err });
    try expectCats("f($a)", &.{ .ident, .lparen, .err });
}

test "`@` is self, and `@name` its member" {
    try expectCats("@", &.{.ident});
    try expectCats("x = @a", &.{ .ident, .assign, .ident, .dot, .ident });
    try expectCats("f(!@)", &.{ .ident, .lparen, .not_sym, .ident, .rparen });
    try expectCats("@type.x", &.{ .ident, .dot, .ident, .dot, .ident });
    try expectCats("@a[0] += 1", &.{ .ident, .dot, .ident, .lbracket, .integer, .rbracket, .plus_assign, .integer });
    try expectCats("!@a.push(1)", &.{ .not_sym, .ident, .dot, .ident, .dot, .ident, .lparen, .integer, .rparen });
    try expectCats("@[0]", &.{ .ident, .lbracket, .integer, .rbracket });
    try expectCats("@.a", &.{.err});
    try expectCats("g = |?@| 1", &.{ .ident, .assign, .bar_capture, .question, .ident, .bar_capture, .integer });
}

test "a `:` touching a name where an operand starts is a symbol" {
    try expectCats("x = :a", &.{ .ident, .assign, .symbol_colon, .ident });
    try expectCats("x = :if", &.{ .ident, .assign, .symbol_colon, .ident });
    try expectCats(":a => 1", &.{ .symbol_colon, .ident, .fat_arrow, .integer });
    try expectCats("break :a", &.{ .@"break", .symbol_colon, .ident });
    try expectCats("x = a ?? break :b", &.{ .ident, .assign, .ident, .nullish_jump, .@"break", .symbol_colon, .ident });
    try expectCats("f(a: :b)", &.{ .ident, .lparen, .kwarg_name, .colon, .symbol_colon, .ident, .rparen });
    try expectCats("f(c or :a)", &.{ .ident, .lparen, .ident, .@"or", .symbol_colon, .ident, .rparen });
    try expectCats("f(not :a)", &.{ .ident, .lparen, .not, .symbol_colon, .ident, .rparen });
    try expectCats("f(not: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
    try expectCats("K(break : 3)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
    try expectCats("f(x if c else :b)", &.{ .ident, .lparen, .ident, .ternary_if, .ident, .@"else", .symbol_colon, .ident, .rparen });
    try expectCats("[:a, :b]", &.{ .lbracket, .symbol_colon, .ident, .comma, .symbol_colon, .ident, .rbracket });
    try expectCats("while s != :done : s = t", &.{ .@"while", .ident, .ne, .symbol_colon, .ident, .step_colon, .ident, .assign, .ident });
    try expectCats("y = : a", &.{ .ident, .assign, .err });
    try expectCats("y = :1", &.{ .ident, .assign, .err });
}

test "a symbol's name runs on over `-` and `.` before a name character" {
    try expectText("x = :content-type", 3, "content-type");
    try expectText("x = :utf-8", 3, "utf-8");
    try expectText("x = :a.b-c", 3, "a.b-c");
    try expectText("x = :width.text", 3, "width.text");
    try expectCats("x = :a..b", &.{ .ident, .assign, .symbol_colon, .ident, .dotdot, .ident });
    try expectCats("x = :a - b", &.{ .ident, .assign, .symbol_colon, .ident, .minus, .ident });
}

test "a `while` header's first `:` starts its step, and a jump there may name a label" {
    try expectCats("while x : y", &.{ .@"while", .ident, .step_colon, .ident });
    try expectCats("while f(a: 1) : y", &.{ .@"while", .ident, .lparen, .kwarg_name, .colon, .integer, .rparen, .step_colon, .ident });
    try expectCats("while a ?? break : y", &.{ .@"while", .ident, .nullish_jump, .@"break", .step_colon, .ident });
    try expectCats("while a ?? break $b : y", &.{ .@"while", .ident, .nullish_jump, .@"break", .label, .ident, .step_colon, .ident });
    try expectCats("while x : y = a ?? break $b", &.{ .@"while", .ident, .step_colon, .ident, .assign, .ident, .nullish_jump, .@"break", .label, .ident });
    try expectCats("x = a ?? break $b", &.{ .ident, .assign, .ident, .nullish_jump, .@"break", .label, .ident });
}

test "minus: infix or negation, never a drop" {
    try expectCats("a - b", &.{ .ident, .minus, .ident });
    try expectCats("-x", &.{ .minus, .ident });
    try expectCats("- x", &.{.err});
    try expectCats("-x + 1", &.{ .minus, .ident, .plus, .integer });
    try expectCats("y = -x", &.{ .ident, .assign, .minus, .ident });
    try expectCats("defer -x", &.{ .@"defer", .minus, .ident });
}

test "if: block, guard, ternary" {
    try expectCats("if c", &.{ .@"if", .ident });
    try expectCats("return if c", &.{ .@"return", .post_if, .ident });
    try expectCats("return x if c", &.{ .@"return", .ident, .post_if, .ident });
    try expectCats("x = a if c else b", &.{ .ident, .assign, .ident, .ternary_if, .ident, .@"else", .ident });
    try expectCats("f(a if c else b)", &.{ .ident, .lparen, .ident, .ternary_if, .ident, .@"else", .ident, .rparen });
}

test "layout: indentation, joined lines, tabs" {
    try expectCats("a\n  b\nc", &.{ .ident, .indent, .ident, .outdent, .newline, .ident, .eof });
    try expectCats("f(1,\n  2)\nx", &.{ .ident, .lparen, .integer, .comma, .integer, .rparen, .newline, .ident });
    try expectCats("a\n\tb", &.{ .ident, .err });
    try expectCats("a\n    b\n  c", &.{ .ident, .indent, .ident, .err });
}

test "closure bar lists: typed parameters, empty bars, owned star" {
    try expectCats("f = |+v, a: Int| a", &.{ .ident, .assign, .bar_capture, .plus, .ident, .comma, .ident, .colon, .ident, .bar_capture, .ident });
    try expectCats("f = |?v, !w, a| a", &.{ .ident, .assign, .bar_capture, .question, .ident, .comma, .not_sym, .ident, .comma, .ident, .bar_capture, .ident });
    try expectCats("g = || 1", &.{ .ident, .assign, .bar_empty, .integer });
    try expectCats("h = *|a| a", &.{ .ident, .assign, .star, .bar_capture, .ident, .bar_capture, .ident });
    try expectCats("x = a | b", &.{ .ident, .assign, .ident, .bar, .ident });
    try expectCats("x = a * b", &.{ .ident, .assign, .ident, .star, .ident });
    try expectCats("x = a || b", &.{ .ident, .assign, .ident, .err });
}

/// `n` copies of `c`, for building long test strings.
fn chars(comptime c: u8, comptime n: usize) *const [n]u8 {
    const s: [n]u8 = @splat(c);
    return &s;
}

test "tokens over 65534 bytes keep their category and their end" {
    try expectCats("#" ++ chars('c', 70000) ++ "\nx", &.{ .ident, .eof });
    try expectCats("x = 1 # " ++ chars('c', 70000) ++ "\ny", &.{ .ident, .assign, .integer, .newline, .ident, .eof });
    const source = "x = \"" ++ chars('y', 70000) ++ "\" + " ++ chars('z', 65535) ++ "\n";
    var lx = Lexer.init(source);
    _ = lx.next();
    _ = lx.next();
    const str = lx.next();
    try testing.expectEqual(TokenCat.string_dq, str.cat);
    try testing.expectEqual(@as(u32, 4 + 70002), endOf(&lx.base, str));
    try testing.expectEqual(@as(u32, 4 + 70002), lx.prev_end);
    try testing.expectEqual(TokenCat.plus, lx.next().cat);
    const name = lx.next();
    try testing.expectEqual(TokenCat.ident, name.cat);
    try testing.expectEqual(@as(u32, source.len - 1), endOf(&lx.base, name));
    try testing.expectEqual(@as(?TokenCat, null), keyword(chars('a', 70000)));
}

test "leafEnd and leafText: a long leaf's whole text, as the parser kept it" {
    const source = "sub main()\n  s = '" ++ chars('q', 65533) ++ "'\n  print(s)\n";
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    _ = tree;
    try testing.expectEqual(@as(usize, 1), p.base.longTokenEnds.items.len);
    const kept = p.base.longTokenEnds.items[0];
    const leaf: parser.Src = .{ .pos = kept.pos, .len = std.math.maxInt(u16), .id = 0 };
    try testing.expectEqual(kept.end, leafEnd(source, leaf));
    try testing.expectEqual(@as(usize, 65535), leafText(source, leaf).len);
    try testing.expectEqualStrings(p.base.leafText(.{ .src = leaf }), leafText(source, leaf));
}

test "leafSpan: from the first leaf to the end of the last" {
    var inner = [_]Sexp{ .{ .tag = .@"+" }, .{ .src = .{ .pos = 4, .len = 1, .id = 0 } }, .{ .src = .{ .pos = 8, .len = 2, .id = 0 } } };
    const s = leafSpan("0123456789", Sexp.listOf(&inner));
    try testing.expectEqual(@as(u32, 4), s.start);
    try testing.expectEqual(@as(u32, 10), s.end);
}

test "layout: a closure body inside brackets is laid out in blocks" {
    try expectCats("f(*|x|\n  g(x)\n  h)\ny", &.{
        .ident,  .lparen,  .star,   .bar_capture, .ident,  .bar_capture,
        .indent, .ident,   .lparen, .ident,       .rparen, .newline,
        .ident,  .outdent, .rparen, .newline,     .ident,
    });
    // Coming back to the closure's line ends the body.
    try expectCats("f(||\n  g\n, 1)", &.{ .ident, .lparen, .bar_empty, .indent, .ident, .outdent, .comma, .integer, .rparen });
    // The bracket around the body goes on a line of its own, at the
    // indentation of the line that opened it.
    try expectLayout("f(*|x|\n  g(x)\n  h\n)\ny", &.{});
    try expectLayout("  r = (|+n|\n    n\n  )()", &.{});
    try expectLayout("f(*|x|\n  g(x)\n  h)\ny", &.{.closure_hanging});
    try expectLayout("f(||\n  g\n, 1)", &.{.closure_close});
    try expectLayout("f(||\n  g\n  )", &.{.closure_indent});
}

test "writeZigIdent escapes Zig keywords and emitter names" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    for ([_][]const u8{ "var", "u8", "rig", "count", "_", "debug", "std_options_cwd", "__rig_x" }) |n| {
        try writeZigIdent(&w, n, .rig);
        try w.writeAll(" ");
    }
    try writeZigIdent(&w, "panic", .exact);
    try testing.expectEqualStrings("@\"var\" @\"u8\" @\"rig'\" count @\"_\" @\"debug'\" @\"std_options_cwd'\" @\"__rig_x'\" panic", w.buffered());
}

test "a condition's guard parts: each part a binding condition joins, or the whole condition" {
    const source =
        \\while a as x and x > 0 and b as y: i += 1
        \\  pass
        \\while i < n and s[i] > 0
        \\  pass
        \\if a as x and (p and q)
        \\  pass
        \\
    ;
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const Parts = struct {
        texts: [4][]const u8 = undefined,
        n: usize = 0,
        parser: *const Parser,
        fn part(self: *@This(), e: Sexp) !void {
            const sp = self.parser.span(e);
            self.texts[self.n] = self.parser.base.source[sp.start..sp.end];
            self.n += 1;
        }
    };
    const decls = ir.Module.decls(tree);
    const want = [_][]const []const u8{
        &.{ "a as x", "x > 0", "b as y" },
        &.{"i < n and s[i] > 0"},
        &.{ "a as x", "p and q" },
    };
    for (decls, want) |d, w| {
        const cond = if (d.isKind(.@"while")) ir.While.cond(d) else ir.If.cond(d);
        var parts: Parts = .{ .parser = &p };
        try eachGuardPart(cond, &parts);
        try testing.expectEqual(w.len, parts.n);
        for (w, parts.texts[0..parts.n]) |a, b| try testing.expectEqualStrings(a, std.mem.trim(u8, b, " "));
    }
}

test "a body's units: statements, guard parts, steps, sources, selections, and raw blocks, nested in the unit holding their block" {
    const source =
        \\fun f(s: ?String, o: Int?, k: Int) -> Int
        \\  i = 0
        \\  while o as x and i < s.len and s[i] > 0: i += 1
        \\    if i > 2 and x > 1
        \\      break
        \\  for c in s[i..]
        \\    print(c)
        \\  match k
        \\    1 if i > 0 => print(1)
        \\    _ => pass
        \\  y = match k
        \\    1
        \\      print(2)
        \\      3
        \\    _ => 4
        \\  raw
        \\    print(5)
        \\  defer print(6)
        \\  g = |n: Int| n + 1
        \\  i + y + g(1)
        \\
    ;
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const Units = struct {
        lines: std.ArrayList(u8) = .empty,
        depth: usize = 0,
        parser: *const Parser,
        pub fn enter(self: *@This(), root: Sexp, kind: UnitKind) std.mem.Allocator.Error!void {
            const sp = self.parser.span(root);
            const text = std.mem.trim(u8, self.parser.base.source[sp.start..sp.end], " \n");
            const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
            for (0..self.depth) |_| try self.lines.appendSlice(testing.allocator, "  ");
            try self.lines.print(testing.allocator, "{s} {s}\n", .{ @tagName(kind), text[0..line_end] });
            self.depth += 1;
        }
        pub fn exit(self: *@This(), _: Sexp) std.mem.Allocator.Error!void {
            self.depth -= 1;
        }
    };
    var units: Units = .{ .parser = &p };
    defer units.lines.deinit(testing.allocator);
    const Body = struct {
        fn each(u: *Units, _: Sexp, body: Sexp) std.mem.Allocator.Error!void {
            try eachUnit(body, u);
        }
    };
    try eachBody(tree, &units, Body.each);
    try testing.expectEqualStrings(
        \\stmt i = 0
        \\guard o as x
        \\guard i < s.len
        \\guard s[i] > 0
        \\guard i > 2
        \\guard x > 1
        \\stmt break
        \\step i += 1
        \\source s[i..]
        \\stmt print(c)
        \\selection match k
        \\stmt print(1)
        \\stmt pass
        \\stmt y = match k
        \\  stmt print(2)
        \\raw raw
        \\stmt print(6)
        \\stmt g = |n: Int| n + 1
        \\  stmt n + 1
        \\stmt i + y + g(1)
        \\
    , units.lines.items);
}

test "a body's exits are `return`, `!`, and `?`; the jumps are `break` and `continue`" {
    const source =
        \\fun f(o: Int?, r: Int!) -> Int?
        \\  for i in 0..3
        \\    break if i == 1
        \\    continue
        \\  x = o?
        \\  y = r!
        \\  return x + y
        \\
    ;
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const Count = struct {
        exits: usize = 0,
        jumps: usize = 0,
        fn walk(self: *@This(), e: Sexp) void {
            if (leavesBody(e)) self.exits += 1;
            if (isJump(e)) self.jumps += 1;
            std.debug.assert(!(leavesBody(e) and isJump(e)));
            if (e == .list) for (e.items()) |c| self.walk(c);
        }
    };
    var c: Count = .{};
    c.walk(tree);
    try testing.expectEqual(3, c.exits);
    try testing.expectEqual(2, c.jumps);
}

test "parser: for-source sigil moves into the mode slot" {
    var p = Parser.init(testing.allocator, "for x in ?xs\n  print(x)\n");
    defer p.deinit();
    const tree = try p.parseProgram();
    const loop = ir.Module.decls(tree)[0];
    try testing.expectEqual(Tag.read, ir.For.mode(loop).tag);
    try testing.expectEqualStrings("xs", ir.For.source(loop).getText(p.base.source));
}

test "parser: a receiver sigil moves onto the place before the method" {
    const source = "!x.v[0].push(1)\n(!v).push(2)\n!(v.pop())\n!f(x).g()\n?p.m()\n?(p.m())\n?f(x).g()\n!(+s).g()\n!a.b(x)(y).g()\n";
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const stmts = ir.Module.decls(tree);
    // (call (member (write (index (member x v) 0)) push) 1)
    const recv = ir.Member.object(ir.Call.callee(stmts[0]));
    try testing.expect(recv.isKind(.write) and p.isReceiverSigil(recv));
    const s = p.span(recv);
    try testing.expectEqualStrings("!x.v[0]", source[s.start..s.end]);
    try testing.expect(ir.Write.operand(recv).isKind(.index));
    // Parentheses keep their meaning, and are not a receiver sigil.
    const long = ir.Member.object(ir.Call.callee(stmts[1]));
    try testing.expect(long.isKind(.write) and !p.isReceiverSigil(long));
    try testing.expect(stmts[2].isKind(.write));
    // `!` lends any value to write: a called head is the receiver.
    const made = ir.Member.object(ir.Call.callee(stmts[3]));
    try testing.expect(made.isKind(.write) and p.isReceiverSigil(made));
    try testing.expect(ir.Write.operand(made).isKind(.call));
    // `?` reaches the receiver too, and lends a parenthesized call.
    const read = ir.Member.object(ir.Call.callee(stmts[4]));
    try testing.expect(read.isKind(.read) and p.isReceiverSigil(read));
    try testing.expect(stmts[5].isKind(.read));
    // A `?` before a called head lends the result.
    try testing.expect(stmts[6].isKind(.read));
    // A parenthesized receiver is lent to write by `!`.
    const paren = ir.Member.object(ir.Call.callee(stmts[7]));
    try testing.expect(paren.isKind(.write) and p.isReceiverSigil(paren));
    try testing.expect(ir.Write.operand(paren).isKind(.clone));
    // A call of a call's value: the first method call's receiver, `a`.
    var head = stmts[8];
    while (!head.isKind(.write)) head = if (head.isKind(.call)) ir.Call.callee(head) else ir.get(head, .object);
    try testing.expect(p.isReceiverSigil(head) and ir.Write.operand(head) == .src);
}

test "parser: bar lists split into captures and parameters, all with node ids" {
    const source = "f = |+c, a| a + c\n";
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const raw = try p.parseTree();
    const tree = try p.rewrite(raw);
    const set = ir.Module.decls(tree)[0];
    try testing.expectEqual(ir.Module.decls(raw)[0].list.id, set.list.id);
    const lambda = ir.Set.value(set);
    const captures = ir.Lambda.captures(lambda);
    try testing.expect(captures.isKind(.captures));
    try testing.expectEqual(@as(usize, 1), ir.Lambda.params(lambda).items().len);
    const s = p.span(lambda);
    try testing.expectEqualStrings("|+c, a| a + c", source[s.start..s.end]);
    // The wrapper's `captures` node gets its own id, spanning its entries.
    try testing.expect(captures.list.id != 0);
    const cs = p.span(captures);
    try testing.expectEqualStrings("+c", source[cs.start..cs.end]);
}

fn parses(source: []const u8) !void {
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    _ = try p.parseProgram();
}

test "parser: every form parses" {
    try parses(
        \\use m
        \\
        \\type Id = U64
        \\
        \\obj Wrap[T]
        \\  value: T
        \\
        \\  fun get(?@) -> T
        \\    @value
        \\
        \\enum Shape
        \\  circle(radius: Int)
        \\  empty()
        \\  dot
        \\
        \\enum Code
        \\  ok = 200
        \\
        \\error Net
        \\  timeout
        \\
        \\obj P
        \\  n: Int
        \\
        \\  drop(!@)
        \\    print(@n)
        \\
        \\obj Random unique
        \\  seed: Int
        \\
        \\pub obj Ring[T] unique
        \\  item: T
        \\
        \\extern fun abs(n: Int) -> Int
        \\extern fun tick(n: Int)
        \\extern sub halt()
        \\extern count: Int
        \\
        \\pub fun f[c: Int](a: Int, b: Int = 2) -> Int!
        \\  a
        \\
        \\test "t"
        \\  print(1)
        \\
        \\sub main()
        \\  x = 1
        \\  y: [2]Int =! [1, 2]
        \\  y2 =! y
        \\  new x = x + 1
        \\  new x: Int = x + 1
        \\  new x =! x + 1
        \\  new y2: [2]Int =! y
        \\  x += 1
        \\  x <<= 2
        \\  z = <w
        \\  <z
        \\  if x > 1
        \\    print(x, y)
        \\  else if not (x < 0 and true)
        \\    return
        \\  if m as v
        \\    print(v)
        \\  $outer: while x < 3 : x += 1
        \\    break $outer
        \\  $done:
        \\    break $done if x > 2
        \\    x += 1
        \\  while m as v
        \\    continue
        \\  else
        \\    break
        \\  for a, i in ?xs
        \\    print(a[i])
        \\  else
        \\    print(0)
        \\  match s
        \\    .circle(r) => print(r)
        \\    1..3 => print(-1)
        \\    _
        \\      print(2)
        \\  g = |+c, <d, ~e, k: Int, j| c + k
        \\  h = *|+c| c.set($size(Int))
        \\  i = || print(1)
        \\  v = f(1, b: 3) catch 0
        \\  u = f(1)!
        \\  t = f(1) catch |err| 0
        \\  q = a ?? b
        \\  o = 1 if c else 2
        \\  defer print(1)
        \\  raw
        \\    print($intCast(x))
        \\  print(+a, <b, ?c, !d, *e, ~f, v.w[0])
        \\  n: fun() -> Int = f
        \\  n2: *sub(Int, ?Wrap[Int]) = h
        \\  n3: sub() = i
        \\  o2: *Wrap[Int]? = none
        \\  p2 = Pair[Int, ?String].make(f[3](1), v[0])
        \\  o3: []~Int = o
        \\  return x
        \\
    );
}

test "parser: a definition writes its parameter list, even when empty" {
    const cases = [_][2][]const u8{
        .{ "sub main\n  pass\n", "write `sub main()`: a function's parameter list is always written, even when empty" },
        .{ "fun answer -> Int  # the answer\n  42\n", "write `fun answer() -> Int`" },
        .{ "fun first[T, n: Int] -> T?\n  none\n", "write `fun first[T, n: Int]() -> T?`" },
        .{ "sub save!\n  pass\n", "write `sub save()!`" },
        .{ "obj S\n  n: Int\n\n  pub fun get -> Int\n    1\n", "write `fun get() -> Int`" },
        .{ "extern fun now -> Int\n", "write `extern fun now() -> Int`" },
        .{ "extern sub halt\n", "write `extern sub halt()`" },
        .{ "extern zig \"z.zig\"\n  pub fun one -> Int\n", "write `fun one() -> Int`" },
    };
    for (cases) |c| {
        var p = Parser.init(testing.allocator, c[0]);
        defer p.deinit();
        try testing.expectError(error.ParseError, p.parseProgram());
        const d = p.diagnostic();
        testing.expect(std.mem.startsWith(u8, d.message, c[1])) catch |e| {
            std.debug.print("source: {s}\n  got: {s}\n", .{ c[0], d.message });
            return e;
        };
    }
}

test "a keyword after `$` names a builtin" {
    try expectCats("$type(x)", &.{ .dollar, .ident, .lparen, .ident, .rparen });
    try expectCats("$size($type(x))", &.{ .dollar, .ident, .lparen, .dollar, .ident, .lparen, .ident, .rparen, .rparen });
}
