//! Desugaring: turns the lowered GrammarIR into the plain BNF Grammar the LR
//! stages consume. Registers symbols and aliases; expands `[opt]` groups,
//! `(A | B)` choices and labeled `( ... )` groups at the top level of a
//! pattern into explicit alternatives (stable action positions); maps every
//! alternative's action tree onto its expanded right-hand side; synthesizes
//! rules for `X?`, `X*`, `X+`, `L(X)`, the other groups and choices, the
//! `@infix` precedence chain, and one entry rule per start symbol.
//!
//! Action positions. A pattern's positions are its top-level elements in
//! order, where a multi-element `[A B]` group counts one position per
//! element and a choice counts one. The elements inside a top-level choice
//! or labeled group get further "internal" positions after those (see
//! `Layout`), which the semantic layer uses to address labeled elements;
//! a grammar cannot write them. Expansion maps each position to the
//! element's index in the expanded right-hand side, or to "absent". Below
//! that level nothing is addressable: a group or choice nested in another,
//! or repeated, becomes a synthesized rule, and labels there are errors.
//!
//! Absent positions. In schema mode an absent `N` is nil and an absent
//! `...N` contributes nothing. Without a schema an absent `N`, `~N` or
//! `...N` becomes nil, and in an expanded alternative the action is cut
//! before the first absent position that is followed by no present one
//! (trailing nils dropped).

const std = @import("std");
const diag = @import("diag.zig");
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const GrammarIR = grammar.GrammarIR;
const InfixDecl = grammar.InfixDecl;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const Symbol = grammar.Symbol;
const Rule = grammar.Rule;
const ActionTree = grammar.ActionTree;
const ActionList = grammar.ActionList;
const ActionItem = grammar.ActionItem;
const ActionElem = grammar.ActionElem;
const Allocator = std.mem.Allocator;

pub const Error = error{ ExpandError, OutOfMemory };

/// Most rules a grammar may expand into: the parse table encodes a
/// reduction by rule r as the i16 -(r + 2).
pub const maxRules = 32766;

/// What the semantic layer resolved for one source alternative (schema
/// mode): the action with every role placed in its slot (positions may be
/// internal positions of labeled choice elements), the side-band labels,
/// and the schema kind the action constructs.
pub const Resolved = struct {
    tree: ?ActionTree,
    sideLabels: []const SideLabel = &.{},
    kind: ?u16 = null,

    pub const SideLabel = struct { role: []const u8, pos: u16 };
};

pub const Options = struct {
    /// Grammar file path, for diagnostics.
    path: []const u8 = "",
    /// Schema mode: per rule, per alternative, what semantics resolved.
    resolved: ?[]const []const Resolved = null,
    /// Schema mode: the placed `(op 1 3)` node per `@infix` operator.
    infix: ?[]const Resolved = null,
};

/// Desugar the IR into plain BNF. In schema mode, `opts.resolved` comes
/// from `semantics.resolve`, which has run `checkPatterns`.
pub fn processGrammar(g: *Grammar, ir: *const GrammarIR, opts: Options) Error!void {
    if (opts.resolved == null) try checkPatterns(ir, opts.path);
    var x = Expander{ .g = g, .ir = ir, .opts = opts };
    return x.run();
}

// =============================================================================
// Positions
// =============================================================================

/// A top-level element that expansion writes inline: one variant per
/// alternative (plus an absent variant when `optional`), each with the
/// alternative's elements in the right-hand side. The elements of `[A B]`
/// and `[X]` are positions of their own (`spliced`); a choice, or a group
/// with labels inside, is one position, and its elements get internal
/// positions.
pub const Inline = struct {
    alts: []const []const ParsedElement,
    optional: bool,
    spliced: bool,
};

/// The inline form of a top-level element, or null when expansion gives it
/// one symbol (a token, a rule, or a synthesized rule).
pub fn inlineForm(a: Allocator, e: ParsedElement) !?Inline {
    const optional = e.quantifier == .optional;
    switch (e.kind) {
        .optGroup => return .{ .alts = try a.dupe([]const ParsedElement, &.{e.subElements}), .optional = true, .spliced = true },
        .ident, .optList => if (optional) {
            const one = try a.dupe(ParsedElement, &.{e});
            one[0].quantifier = .one;
            return .{ .alts = try a.dupe([]const ParsedElement, &.{one}), .optional = true, .spliced = true };
        },
        .choice => if (once(e)) return .{ .alts = e.choices, .optional = optional, .spliced = false },
        .group => if (once(e) and hasLabel(e.subElements)) return .{ .alts = try a.dupe([]const ParsedElement, &.{e.subElements}), .optional = optional, .spliced = false },
        else => {},
    }
    return null;
}

/// Not repeated: quantifier one or optional.
fn once(e: ParsedElement) bool {
    return e.quantifier == .one or e.quantifier == .optional;
}

fn hasLabel(elements: []const ParsedElement) bool {
    for (elements) |e| if (e.label) |l| if (!std.mem.eql(u8, l, "_")) return true;
    return false;
}

/// An element in source syntax, for diagnostics: `{f}`.
pub fn fmtElement(e: ParsedElement) std.fmt.Alt(ParsedElement, writeElement) {
    return .{ .data = e };
}

fn writeElement(e: ParsedElement, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (e.skip) try w.writeByte('!');
    if (e.label) |l| try w.print("{s}:", .{l});
    switch (e.kind) {
        .ident, .token, .string => try w.writeAll(e.value),
        .group, .optGroup => {
            try w.writeByte(if (e.kind == .group) '(' else '[');
            for (e.subElements, 0..) |sub, i| {
                if (i > 0) try w.writeByte(' ');
                try writeElement(sub, w);
            }
            try w.writeByte(if (e.kind == .group) ')' else ']');
        },
        .choice => {
            try w.writeByte('(');
            for (e.choices, 0..) |alt, i| {
                if (i > 0) try w.writeAll(" | ");
                for (alt, 0..) |sub, j| {
                    if (j > 0) try w.writeByte(' ');
                    try writeElement(sub, w);
                }
            }
            try w.writeByte(')');
        },
        .reqList, .optList => {
            if (e.kind == .optList) try w.writeByte('[');
            try w.print("L({s}{s}", .{ e.value, if (e.optionalItems) "?" else "" });
            if (e.listSeparator) |sep| try w.print(", {s}", .{sep});
            try w.writeByte(')');
            if (e.kind == .optList) try w.writeByte(']');
        },
    }
    try w.writeAll(switch (e.quantifier) {
        .one => "",
        .optional => "?",
        .zeroPlus => "*",
        .onePlus => "+",
    });
}

/// Where one action position points: top-level element `elem`, or (`alt`
/// set) element `sub` of one of its inline alternatives.
pub const Slot = struct { elem: u16, alt: ?u16 = null, sub: u16 = 0 };

/// The positions of a pattern: `slots[p - 1]` for position p. The first
/// `length` are the positions a grammar writes; the rest are internal
/// positions of the elements of choices and labeled groups.
pub const Layout = struct {
    slots: []const Slot,
    length: usize,
    /// Per top-level element: its inline form, or null.
    forms: []const ?Inline,
    /// Per top-level element: its position (the first, for `[A B]`).
    pos: []const u16,
    /// Per top-level element: the position of the first element of its
    /// inline alternatives.
    first: []const u16,

    pub fn of(a: Allocator, elements: []const ParsedElement) !Layout {
        const forms = try a.alloc(?Inline, elements.len);
        const pos = try a.alloc(u16, elements.len);
        const first = try a.alloc(u16, elements.len);
        var slots: std.ArrayList(Slot) = .empty;
        for (elements, 0..) |e, i| {
            const idx: u16 = @intCast(i);
            forms[i] = try inlineForm(a, e);
            pos[i] = @intCast(slots.items.len + 1);
            first[i] = pos[i];
            if (forms[i]) |f| if (f.spliced) {
                for (0..f.alts[0].len) |j| try slots.append(a, .{ .elem = idx, .alt = 0, .sub = @intCast(j) });
                continue;
            };
            try slots.append(a, .{ .elem = idx });
        }
        const length = slots.items.len;
        for (forms, 0..) |form, i| {
            const f = form orelse continue;
            if (f.spliced) continue;
            first[i] = @intCast(slots.items.len + 1);
            for (f.alts, 0..) |alt, ai| for (0..alt.len) |j| {
                try slots.append(a, .{ .elem = @intCast(i), .alt = @intCast(ai), .sub = @intCast(j) });
            };
        }
        return .{ .slots = try slots.toOwnedSlice(a), .length = length, .forms = forms, .pos = pos, .first = first };
    }

    /// The element at position p (1-based).
    pub fn element(self: Layout, elements: []const ParsedElement, p: usize) ParsedElement {
        const s = self.slots[p - 1];
        const alt = s.alt orelse return elements[s.elem];
        return self.forms[s.elem].?.alts[alt][s.sub];
    }

    /// The inline form of position p when p is a choice or a labeled group
    /// as a whole; null for any other position.
    pub fn whole(self: Layout, p: usize) ?Inline {
        const s = self.slots[p - 1];
        if (s.alt != null) return null;
        return self.forms[s.elem];
    }

    /// The position of element `sub` of inline alternative `alt` of
    /// top-level element `elem`.
    pub fn position(self: Layout, elem: usize, alt: usize, sub: usize) usize {
        var p: usize = self.first[elem];
        for (self.forms[elem].?.alts[0..alt]) |prior| p += prior.len;
        return p + sub;
    }
};

/// A position's value in one expanded variant.
const absent: u16 = 0;
/// A choice position whose chosen alternative has several elements.
const multi: u16 = std.math.maxInt(u16);

/// Deepest nesting of groups and choices in a pattern, and of nodes in an
/// action, that generation accepts (as for lexer patterns).
pub const maxDepth = 64;

/// Checks of every pattern that need no schema: each label sits where it
/// addresses a value (and has an @schema to fill), a multi-element `[A B]`
/// group appears only at the top level, and nesting stays within
/// `maxDepth`. Schema mode runs them before resolving (semantics.zig).
pub fn checkPatterns(ir: *const GrammarIR, path: []const u8) Error!void {
    const c: PatternChecker = .{ .path = path, .schema = ir.schema != null };
    for (ir.rules) |rule| for (rule.alternatives) |alt| try c.alternative(alt);
}

const PatternChecker = struct {
    path: []const u8,
    schema: bool,

    fn fail(self: PatternChecker, line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
        diag.errLine(self.path, line, col, fmt, args);
        return error.ExpandError;
    }

    fn alternative(self: PatternChecker, alt: ParsedAlternative) Error!void {
        for (alt.elements) |e| {
            try self.label(e, true);
            // The elements of an inline element are positions, so they
            // may be labeled; below them nothing is a position.
            const inlined = switch (e.kind) {
                .optGroup => true,
                .choice => once(e),
                .group => once(e) and hasLabel(e.subElements),
                else => false,
            };
            try self.children(e, inlined, 2);
        }
        if (alt.actionTree) |t| switch (t) {
            .list => |l| try self.action(alt, l, 1),
            else => {},
        };
    }

    fn children(self: PatternChecker, e: ParsedElement, addressable: bool, depth: usize) Error!void {
        switch (e.kind) {
            .group, .optGroup => for (e.subElements) |c| try self.nested(c, addressable, depth),
            .choice => for (e.choices) |alt| for (alt) |c| try self.nested(c, addressable, depth),
            else => {},
        }
    }

    fn nested(self: PatternChecker, e: ParsedElement, addressable: bool, depth: usize) Error!void {
        if (depth > maxDepth) return self.fail(e.line, e.col, "groups and choices nested too deeply (the limit is {d})", .{maxDepth});
        if (e.kind == .optGroup) return self.fail(e.line, e.col, "a multi-element [...] group inside a group or choice is not supported; move it into a named rule", .{});
        try self.label(e, addressable);
        try self.children(e, false, depth + 1);
    }

    fn label(self: PatternChecker, e: ParsedElement, addressable: bool) Error!void {
        const name = e.label orelse return;
        if (std.mem.eql(u8, name, "_")) return;
        if (!self.schema) return self.fail(e.line, e.col, "pattern label '{s}' needs an @schema (labels fill schema roles)", .{name});
        if (!addressable) return self.fail(e.line, e.col, "label '{s}' is inside a repeated or nested group or choice, where it cannot fill a role; move that part into a named rule", .{name});
    }

    fn action(self: PatternChecker, alt: ParsedAlternative, l: ActionList, depth: usize) Error!void {
        if (depth > maxDepth) return self.fail(alt.line, alt.col, "action nodes nested too deeply (the limit is {d})", .{maxDepth});
        for (l.items) |item| switch (item.elem) {
            .node => |n| try self.action(alt, n.*, depth + 1),
            else => {},
        };
    }
};

// =============================================================================
// Expander
// =============================================================================

const Expander = struct {
    g: *Grammar,
    ir: *const GrammarIR,
    opts: Options,
    /// Source position of the alternative being expanded: the location of
    /// the rules synthesized for it (`X?`, `L(X)`, groups, ...), which are
    /// shared with later alternatives that use the same construct.
    originLine: u32 = 0,
    originCol: u32 = 0,

    fn alloc(self: *Expander) Allocator {
        return self.g.allocator;
    }

    fn fail(self: *Expander, line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
        diag.errLine(self.opts.path, line, col, fmt, args);
        return error.ExpandError;
    }

    fn schemaMode(self: *const Expander) bool {
        return self.opts.resolved != null;
    }

    fn run(self: *Expander) Error!void {
        const g = self.g;
        const ir = self.ir;
        g.acceptId = try self.addSymbol("$accept", .nonterminal);
        g.endId = try self.addSymbol("$end", .terminal);
        g.errorId = try self.addSymbol("error", .terminal);

        for (ir.rules) |rule| {
            if (aliasTarget(ir, rule)) |target| try g.aliases.put(g.allocator, rule.name, target);
        }
        for (ir.rules) |rule| {
            if (g.aliases.contains(rule.name)) try self.checkAliasChain(rule);
            // `@infix` in a pattern names the operator chain's entry rule.
            if (ir.infix != null and std.mem.eql(u8, rule.name, "infix"))
                return self.fail(rule.line, rule.col, "a rule named 'infix' clashes with the @infix chain, which patterns name `@infix`; rename the rule", .{});
        }
        for (ir.rules) |rule| {
            if (g.aliases.contains(rule.name)) continue;
            self.originLine = rule.line;
            self.originCol = rule.col;
            _ = try self.addSymbol(rule.name, .nonterminal);
        }

        for (ir.rules, 0..) |rule, ri| {
            if (g.aliases.contains(rule.name)) continue;
            const lhsId = g.getSymbol(rule.name).?;
            for (rule.alternatives, 0..) |alt, ai| {
                const resolved: ?Resolved = if (self.opts.resolved) |r| r[ri][ai] else null;
                if (rule.isStart and isEntryIdiom(rule.name, alt)) {
                    try self.checkEntryIdiom(alt);
                    continue;
                }
                try self.expandAlternative(lhsId, alt, resolved);
            }
        }

        if (g.symbolMap.get("EOF")) |eofId| g.endId = eofId;
        self.originLine = 0;
        self.originCol = 0;

        try self.addStartRules();

        g.asDirectives = ir.asDirectives;
        g.opMappings = ir.opMappings;
        g.errorNames = ir.errorNames;
        g.displayNames = ir.displayNames;
        g.lang = ir.lang;
        g.schema = ir.schema;
        g.conflicts = ir.conflicts;
        g.trivia = ir.trivia;
        g.repair = ir.repair;

        if (ir.infix) |infix| {
            if (infix.ops.len > 0) try self.generateInfixChain(infix);
        }
    }

    /// `Grammar.addSymbol`, with the symbol limit reported at the
    /// alternative being expanded.
    fn addSymbol(self: *Expander, name: []const u8, kind: Symbol.Kind) Error!u16 {
        return self.addSymbolAt(name, kind, self.originLine, self.originCol);
    }

    fn addSymbolAt(self: *Expander, name: []const u8, kind: Symbol.Kind, line: u32, col: u32) Error!u16 {
        return self.g.addSymbol(name, kind) catch |err| switch (err) {
            error.TooManySymbols => self.fail(@max(1, line), @max(1, col), "the grammar has more than {d} symbols", .{Grammar.maxSymbols}),
            error.OutOfMemory => error.OutOfMemory,
        };
    }

    fn addRule(self: *Expander, rule: Rule) !u16 {
        const g = self.g;
        if (g.rules.items.len >= maxRules)
            return self.fail(@max(1, if (rule.line != 0) rule.line else self.originLine), @max(1, if (rule.line != 0) rule.col else self.originCol), "the grammar expands into more than {d} rules, the parse table's limit", .{maxRules});
        const id: u16 = @intCast(g.rules.items.len);
        var r = rule;
        r.id = id;
        if (r.line == 0) {
            r.line = self.originLine;
            r.col = self.originCol;
        }
        try g.rules.append(g.allocator, r);
        try g.symbols.items[rule.lhs].rules.append(g.allocator, id);
        return id;
    }

    /// An alias chain must end in a symbol: `x = y`, `y = x` names none.
    fn checkAliasChain(self: *Expander, rule: ParsedRule) Error!void {
        const aliases = &self.g.aliases;
        var cur = rule.name;
        for (0..aliases.count()) |_| {
            cur = aliases.get(cur) orelse return;
            if (!std.mem.eql(u8, cur, rule.name)) continue;
            var text: std.ArrayList(u8) = .empty;
            try text.appendSlice(self.alloc(), rule.name);
            cur = rule.name;
            while (true) {
                cur = aliases.get(cur).?;
                try text.print(self.alloc(), " = {s}", .{cur});
                if (std.mem.eql(u8, cur, rule.name)) break;
            }
            return self.fail(rule.line, rule.col, "alias cycle: {s}", .{text.items});
        }
    }

    // --- Start symbols ---

    /// One accept rule per start symbol x: `$accept_x → x! x $end`. The
    /// marker terminal `x!` is what `parseX` injects first to select that
    /// rule; it appears in no other rule, so it is never a lookahead. The
    /// alternatives of an `x! = ...` block are ordinary alternatives of x
    /// (usable anywhere x is), except `x! = x`, which only declares x a
    /// start symbol (as a rule it would be the cycle x → x).
    fn addStartRules(self: *Expander) Error!void {
        const g = self.g;
        const ir = self.ir;
        if (ir.startSymbols.len == 0) {
            if (g.rules.items.len == 0) return;
            const startSymbol = g.rules.items[0].lhs;
            const ruleId = try self.addRule(.{
                .id = 0,
                .lhs = g.acceptId,
                .rhs = try g.allocator.dupe(u16, &.{ startSymbol, g.endId }),
            });
            try g.startSymbols.append(g.allocator, startSymbol);
            try g.acceptRules.append(g.allocator, ruleId);
            return;
        }
        for (ir.startSymbols) |startName| {
            const startId = g.getSymbol(startName) orelse continue;
            const at = for (ir.rules) |r| {
                if (std.mem.eql(u8, r.name, startName)) break r;
            } else unreachable;
            const markerId = try self.addSymbolAt(try g.allocator.print("{s}!", .{startName}), .terminal, at.line, at.col);
            const acceptId = try self.addSymbolAt(try g.allocator.print("$accept_{s}", .{startName}), .nonterminal, at.line, at.col);
            const ruleId = try self.addRule(.{
                .id = 0,
                .lhs = acceptId,
                .rhs = try g.allocator.dupe(u16, &.{ markerId, startId, g.endId }),
            });
            try g.startSymbols.append(g.allocator, startId);
            try g.acceptRules.append(g.allocator, ruleId);
        }
    }

    /// `x! = x → action`: the action can only be the element itself.
    fn checkEntryIdiom(self: *Expander, alt: ParsedAlternative) Error!void {
        const tree = alt.actionTree orelse return;
        if (tree == .pass) return;
        return self.fail(alt.line, alt.col, "`x! = x` only declares x a start symbol; its action must be `→ 1` or none", .{});
    }

    // --- Alternatives ---

    fn expandAlternative(self: *Expander, lhsId: u16, alt: ParsedAlternative, resolved: ?Resolved) Error!void {
        const a = self.alloc();
        self.originLine = alt.line;
        self.originCol = alt.col;

        const layout = try Layout.of(a, alt.elements);
        if (!self.schemaMode()) if (alt.actionTree) |t| switch (t) {
            .list => |l| try self.checkSpreads(alt, layout, l),
            else => {},
        };
        // The inline elements, each with its number of variants.
        var vars: std.ArrayList(usize) = .empty;
        var total: usize = 1;
        for (layout.forms, 0..) |form, i| if (form) |f| {
            try vars.append(a, i);
            total = std.math.mul(usize, total, radix(f)) catch maxRules + 1;
            if (total > maxRules)
                return self.fail(alt.line, alt.col, "this alternative's [...] groups and choices expand into more than {d} rules (one per combination); move some into helper rules", .{maxRules});
        };

        // Without a schema, a leading `role:N` names the head tag only when
        // the alternative is not expanded (otherwise the key is dropped).
        const tree: ?ActionTree = if (resolved) |r|
            r.tree
        else if (alt.actionTree) |t|
            (if (vars.items.len == 0) roleHead(t) else t)
        else
            null;
        const digits = try a.alloc(usize, vars.items.len);
        const posMap = try a.alloc(u16, layout.slots.len + 1);

        for (0..total) |combo| {
            // Mixed-radix digits, the first inline element least significant.
            var rest = combo;
            for (vars.items, 0..) |i, d| {
                const r = radix(layout.forms[i].?);
                digits[d] = rest % r;
                rest /= r;
            }

            var rhs: std.ArrayList(ParsedElement) = .empty;
            @memset(posMap, absent);
            var d: usize = 0;
            for (alt.elements, layout.forms, 0..) |e, form, i| {
                const f = form orelse {
                    try rhs.append(a, e);
                    posMap[layout.pos[i]] = @intCast(rhs.items.len);
                    continue;
                };
                const digit = digits[d];
                d += 1;
                const ai = chosen(f, digit) orelse continue;
                for (f.alts[ai], 0..) |sub, j| {
                    try rhs.append(a, sub);
                    posMap[layout.position(i, ai, j)] = @intCast(rhs.items.len);
                }
                if (!f.spliced) posMap[layout.pos[i]] = if (f.alts[ai].len == 1) @intCast(rhs.items.len) else multi;
            }

            var symbols: std.ArrayList(u16) = .empty;
            for (rhs.items) |e| try symbols.append(a, try self.processElement(e));

            const mapped: ?ActionTree = if (tree) |t|
                try self.mapTree(t, posMap, vars.items.len > 0, alt)
            else if (vars.items.len > 0)
                try self.expandedDefault(layout, digits, rhs.items.len)
            else
                null;

            var sideLabels: std.ArrayList(Rule.SideLabel) = .empty;
            if (resolved) |r| for (r.sideLabels) |sl| {
                const at = posMap[sl.pos];
                if (at != absent and at != multi) try sideLabels.append(a, .{ .role = sl.role, .pos = at });
            };

            _ = try self.addRule(.{
                .id = 0,
                .lhs = lhsId,
                .rhs = try symbols.toOwnedSlice(a),
                .actionTree = mapped,
                .excludeChars = alt.excludeChars,
                .preferReduce = alt.preferReduce,
                .preferShift = alt.preferShift,
                .kind = if (resolved) |r| r.kind else null,
                .sideLabels = try sideLabels.toOwnedSlice(a),
                .line = alt.line,
                .col = alt.col,
            });
        }
    }

    fn radix(f: Inline) usize {
        return f.alts.len + @intFromBool(f.optional);
    }

    /// The alternative an inline element's digit selects, or null for its
    /// absent variant (digit 0 of an optional element).
    fn chosen(f: Inline, digit: usize) ?usize {
        if (!f.optional) return digit;
        return if (digit == 0) null else digit - 1;
    }

    /// The default action (no `→`) of one variant of an expanded
    /// alternative: every element's value in order, with nil for each
    /// absent optional element, exactly as when the optional element is
    /// not expanded (`[T]`, `T?`: a rule that yields nil). A chosen choice
    /// alternative contributes its elements. One value is passed through.
    fn expandedDefault(self: *Expander, layout: Layout, digits: []const usize, rhsLen: usize) Error!ActionTree {
        const a = self.alloc();
        var items: std.ArrayList(ActionItem) = .empty;
        var at: u16 = 0; // rhs elements placed so far
        var d: usize = 0;
        for (layout.forms) |form| {
            const f = form orelse {
                at += 1;
                try items.append(a, .{ .elem = .{ .ref = at } });
                continue;
            };
            const digit = digits[d];
            d += 1;
            if (chosen(f, digit)) |ai| {
                for (f.alts[ai]) |_| {
                    at += 1;
                    try items.append(a, .{ .elem = .{ .ref = at } });
                }
            } else {
                // Absent: nil per position (a spliced [A B] has several).
                for (0..if (f.spliced) f.alts[0].len else 1) |_| try items.append(a, .{ .elem = .nil });
            }
        }
        std.debug.assert(at == rhsLen);
        if (items.items.len == 0) return .nil;
        if (items.items.len == 1) return switch (items.items[0].elem) {
            .ref => |p| .{ .pass = p },
            else => .nil,
        };
        return .{ .list = .{ .head = .none, .items = try items.toOwnedSlice(a), .keepNils = true } };
    }

    /// Without a schema, `...N` of a token (which is never a list) would
    /// drop it silently. (Schema mode reports it with the static types.)
    fn checkSpreads(self: *Expander, alt: ParsedAlternative, layout: Layout, l: ActionList) Error!void {
        switch (l.head) {
            .ref => |e| try self.checkSpread(alt, layout, e),
            else => {},
        }
        for (l.items) |item| try self.checkSpread(alt, layout, item.elem);
    }

    fn checkSpread(self: *Expander, alt: ParsedAlternative, layout: Layout, e: ActionElem) Error!void {
        switch (e) {
            .spread => |p| {
                if (p == 0 or p > layout.length) return;
                const elem = layout.element(alt.elements, p);
                if (!isToken(elem)) return;
                const what = if (elem.kind == .choice) "a choice of tokens" else elem.value;
                return self.fail(alt.line, alt.col, "`...{d}` spreads a list, but element {d} ({s}) is a token; use `{d}`", .{ p, p, what, p });
            },
            .node => |n| try self.checkSpreads(alt, layout, n.*),
            else => {},
        }
    }

    /// A single token (or an optional one, or a choice of single tokens).
    fn isToken(e: ParsedElement) bool {
        if (e.quantifier != .one and e.quantifier != .optional) return false;
        return switch (e.kind) {
            .token, .string => true,
            .choice => for (e.choices) |c| {
                if (c.len != 1 or !isToken(c[0])) break false;
            } else true,
            else => false,
        };
    }

    // --- Action mapping ---

    const Mapper = struct {
        x: *Expander,
        posMap: []const u16,
        /// No schema: absent spreads are nil, and expanded actions are cut.
        schemaless: bool,
        alt: ParsedAlternative,

        fn at(self: Mapper, p: u16) Error!u16 {
            const v = self.posMap[p];
            if (v == multi) return self.x.fail(self.alt.line, self.alt.col, "position {d} is a choice whose chosen alternative has several elements; label those elements instead", .{p});
            return v;
        }

        fn elem(self: Mapper, e: ActionElem) Error!?ActionElem {
            return switch (e) {
                .ref => |p| if (try self.at(p) == absent) .nil else .{ .ref = try self.at(p) },
                .symId => |p| if (try self.at(p) == absent) .nil else .{ .symId = try self.at(p) },
                .spread => |p| if (try self.at(p) != absent) .{ .spread = try self.at(p) } else if (self.schemaless) .nil else null,
                .node => |l| .{ .node = try self.listPtr(l.*) },
                .litTag => |p| if (try self.at(p) == absent) .nil else .{ .litTag = try self.at(p) },
                .nil, .tagLit => e,
            };
        }

        fn listPtr(self: Mapper, l: ActionList) Error!*const ActionList {
            const p = try self.x.alloc().create(ActionList);
            p.* = try self.list(l);
            return p;
        }

        fn list(self: Mapper, l: ActionList) Error!ActionList {
            var items: std.ArrayList(ActionItem) = .empty;
            for (l.items) |item| {
                if (try self.elem(item.elem)) |e| try items.append(self.x.alloc(), .{ .role = item.role, .elem = e });
            }
            const head: ActionList.Head = switch (l.head) {
                .ref => |e| .{ .ref = (try self.elem(e)) orelse .nil },
                else => l.head,
            };
            return .{ .head = head, .items = try items.toOwnedSlice(self.x.alloc()) };
        }
    };

    fn mapTree(self: *Expander, tree: ActionTree, posMap: []const u16, expanded: bool, alt: ParsedAlternative) Error!ActionTree {
        const m = Mapper{ .x = self, .posMap = posMap, .schemaless = !self.schemaMode(), .alt = alt };
        switch (tree) {
            .nil => return .nil,
            .pass => |p| {
                const v = try m.at(p);
                return if (v == absent) .nil else .{ .pass = v };
            },
            .list => |l| {
                var mapped = try m.list(l);
                if (m.schemaless and expanded) mapped.items = trailingCut(l.items, mapped.items);
                return .{ .list = mapped };
            },
        }
    }

    // --- Elements ---

    fn processElement(self: *Expander, elem: ParsedElement) Error!u16 {
        const baseId = try self.processBaseElement(elem);
        return switch (elem.quantifier) {
            .one => baseId,
            .optional => try self.createOptionalRule(baseId),
            .zeroPlus => try self.createZeroPlusRule(baseId),
            .onePlus => try self.createOnePlusRule(baseId),
        };
    }

    /// The symbol a name refers to, through aliases; created on first use
    /// (uppercase names are terminals).
    fn nameSymbol(self: *Expander, name: []const u8, forceTerminal: bool) Error!u16 {
        const g = self.g;
        var resolved = name;
        while (g.aliases.get(resolved)) |target| resolved = target;
        if (g.symbolMap.get(resolved)) |id| return id;
        const kind: Symbol.Kind = if (forceTerminal or (resolved.len > 0 and resolved[0] >= 'A' and resolved[0] <= 'Z'))
            .terminal
        else
            .nonterminal;
        return self.addSymbol(resolved, kind);
    }

    fn processBaseElement(self: *Expander, elem: ParsedElement) Error!u16 {
        return switch (elem.kind) {
            .ident => try self.nameSymbol(elem.value, false),
            .token => try self.nameSymbol(elem.value, true),
            .string => try self.addSymbol(elem.value, .terminal),
            .group => try self.groupRule(elem.subElements),
            .choice => try self.choiceRule(elem.choices),
            // Multi-element [A B] groups are expanded into alternatives, and
            // nested ones are rejected by checkPatterns.
            .optGroup => unreachable,
            .reqList => try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator),
            .optList => try self.createOptionalRule(try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator)),
        };
    }

    /// The symbols of a group or choice alternative, and its source-syntax
    /// text: the elements' names separated by spaces, `!` marking a
    /// skipped element.
    fn sequence(self: *Expander, elements: []const ParsedElement, text: *std.ArrayList(u8)) Error![]const u16 {
        const a = self.alloc();
        var rhs: std.ArrayList(u16) = .empty;
        for (elements, 0..) |sub, i| {
            const id = try self.processElement(sub);
            try rhs.append(a, id);
            if (i > 0) try text.append(a, ' ');
            if (sub.skip) try text.append(a, '!');
            try text.appendSlice(a, self.g.symbols.items[id].name);
        }
        return rhs.toOwnedSlice(a);
    }

    /// A `( ... )` group: the rule `(A B) → A B` whose value leaves out the
    /// `!X` elements. Identical groups share one symbol.
    fn groupRule(self: *Expander, elements: []const ParsedElement) Error!u16 {
        const g = self.g;
        if (elements.len == 0) return g.errorId;
        var text: std.ArrayList(u8) = .empty;
        try text.append(g.allocator, '(');
        const rhs = try self.sequence(elements, &text);
        try text.append(g.allocator, ')');
        if (g.getSymbol(text.items)) |existing| return existing;
        const id = try self.addSymbol(try text.toOwnedSlice(g.allocator), .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = id, .rhs = rhs, .actionTree = try groupAction(g.allocator, elements) });
        return id;
    }

    /// A repeated choice, `(A | B)*` or `(A | B)+`: the symbol `(A | B)`
    /// with one rule per alternative. Identical choices share one symbol.
    fn choiceRule(self: *Expander, choices: []const []const ParsedElement) Error!u16 {
        const g = self.g;
        var text: std.ArrayList(u8) = .empty;
        try text.append(g.allocator, '(');
        const rhss = try g.allocator.alloc([]const u16, choices.len);
        for (choices, 0..) |choice, i| {
            if (i > 0) try text.appendSlice(g.allocator, " | ");
            rhss[i] = try self.sequence(choice, &text);
        }
        try text.append(g.allocator, ')');
        if (g.getSymbol(text.items)) |existing| return existing;
        const id = try self.addSymbol(try text.toOwnedSlice(g.allocator), .nonterminal);
        for (choices, rhss) |choice, rhs| {
            _ = try self.addRule(.{ .id = 0, .lhs = id, .rhs = rhs, .actionTree = try groupAction(g.allocator, choice) });
        }
        return id;
    }

    fn createRequiredList(self: *Expander, itemName: []const u8, optionalItems: bool, customSep: ?[]const u8) Error!u16 {
        const g = self.g;
        const itemId = try self.nameSymbol(itemName, false);
        const effectiveItemId = if (optionalItems) try self.createOptionalRule(itemId) else itemId;

        const sepId = if (customSep) |sep|
            (if (sep[0] == '"') try self.addSymbol(sep, .terminal) else try self.nameSymbol(sep, true))
        else
            try self.addSymbol("\",\"", .terminal);

        // One rule set per (item, item optionality, separator), named in
        // source syntax: `L(X)`, `L(X?)`, `L(X, sep)`. `","` is the default
        // separator.
        const sepName = g.symbols.items[sepId].name;
        const listName = if (std.mem.eql(u8, sepName, "\",\""))
            try g.allocator.print("L({s})", .{g.symbols.items[effectiveItemId].name})
        else
            try g.allocator.print("L({s}, {s})", .{ g.symbols.items[effectiveItemId].name, sepName });
        if (g.getSymbol(listName)) |existing| return existing;
        const listId = try self.addSymbol(listName, .nonterminal);
        // L(X) → X → (1) | L(X) sep X → (...1 3)
        _ = try self.addRule(.{ .id = 0, .lhs = listId, .rhs = try g.allocator.dupe(u16, &.{effectiveItemId}), .actionTree = singleton });
        _ = try self.addRule(.{
            .id = 0,
            .lhs = listId,
            .rhs = try g.allocator.dupe(u16, &.{ listId, sepId, effectiveItemId }),
            .actionTree = try appendTree(g.allocator, 3),
        });
        return listId;
    }

    fn createOptionalRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try g.allocator.print("{s}?", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const optId = try self.addSymbol(name, .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = try g.allocator.dupe(u16, &.{symId}) });
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = &[_]u16{} });
        return optId;
    }

    fn createZeroPlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try g.allocator.print("{s}*", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const starId = try self.addSymbol(name, .nonterminal);
        // X* → ε → () | X* X → (...1 2)
        _ = try self.addRule(.{ .id = 0, .lhs = starId, .rhs = &[_]u16{}, .actionTree = emptyList });
        _ = try self.addRule(.{
            .id = 0,
            .lhs = starId,
            .rhs = try g.allocator.dupe(u16, &.{ starId, symId }),
            .actionTree = try appendTree(g.allocator, 2),
        });
        return starId;
    }

    fn createOnePlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try g.allocator.print("{s}+", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const plusId = try self.addSymbol(name, .nonterminal);
        // X+ → X → (1) | X+ X → (...1 2)
        _ = try self.addRule(.{ .id = 0, .lhs = plusId, .rhs = try g.allocator.dupe(u16, &.{symId}), .actionTree = singleton });
        _ = try self.addRule(.{
            .id = 0,
            .lhs = plusId,
            .rhs = try g.allocator.dupe(u16, &.{ plusId, symId }),
            .actionTree = try appendTree(g.allocator, 2),
        });
        return plusId;
    }

    fn generateInfixChain(self: *Expander, infix: InfixDecl) Error!void {
        const g = self.g;
        self.originLine = infix.line;
        self.originCol = infix.col;
        const baseId = try self.nameSymbol(infix.baseRule, false);

        // Precedence levels, ascending (level 1 binds loosest).
        var levels: std.ArrayList(u32) = .empty;
        for (infix.ops) |op| {
            if (std.mem.findScalar(u32, levels.items, op.prec) == null) try levels.append(g.allocator, op.prec);
        }
        std.mem.sort(u32, levels.items, {}, std.sort.asc(u32));

        // Each level is named by its operators: `infix("+" "-")`.
        var levelIds: std.ArrayList(u16) = .empty;
        for (levels.items) |level| {
            var name: std.ArrayList(u8) = .empty;
            try name.appendSlice(g.allocator, "infix(");
            var first = true;
            for (infix.ops) |op| {
                if (op.prec != level) continue;
                if (!first) try name.append(g.allocator, ' ');
                first = false;
                try name.print(g.allocator, "\"{s}\"", .{op.op});
            }
            try name.append(g.allocator, ')');
            try levelIds.append(g.allocator, try self.addSymbolAt(try name.toOwnedSlice(g.allocator), .nonterminal, infix.line, infix.col));
        }

        for (levels.items, 0..) |level, i| {
            const thisId = levelIds.items[i];
            const nextId = if (i + 1 < levels.items.len) levelIds.items[i + 1] else baseId;
            for (infix.ops, 0..) |op, opIndex| {
                if (op.prec != level) continue;
                const opStr = try g.allocator.print("\"{s}\"", .{op.op});
                const opId = try self.addSymbolAt(opStr, .terminal, infix.line, infix.col);
                const rhs: [3]u16 = switch (op.assoc) {
                    .left => .{ thisId, opId, nextId },
                    .right => .{ nextId, opId, thisId },
                    .none => .{ nextId, opId, nextId },
                };
                const items = try g.allocator.dupe(ActionItem, &.{ .{ .elem = .{ .ref = 1 } }, .{ .elem = .{ .ref = 3 } } });
                var tree: ActionTree = .{ .list = .{ .head = .{ .tag = op.op }, .items = items } };
                var kind: ?u16 = null;
                if (self.opts.infix) |placed| {
                    const r = placed[opIndex];
                    tree = r.tree.?;
                    kind = r.kind;
                }
                _ = try self.addRule(.{
                    .id = 0,
                    .lhs = thisId,
                    .rhs = try g.allocator.dupe(u16, &rhs),
                    .actionTree = tree,
                    .kind = kind,
                    .line = infix.line,
                    .col = infix.col,
                });
            }
            // this level → the next tighter level
            _ = try self.addRule(.{ .id = 0, .lhs = thisId, .rhs = try g.allocator.dupe(u16, &.{nextId}), .actionTree = .{ .pass = 1 }, .line = infix.line, .col = infix.col });
        }

        // `infix` → the loosest level
        const infixId = try self.addSymbolAt("infix", .nonterminal, infix.line, infix.col);
        _ = try self.addRule(.{ .id = 0, .lhs = infixId, .rhs = try g.allocator.dupe(u16, &.{levelIds.items[0]}), .actionTree = .{ .pass = 1 }, .line = infix.line, .col = infix.col });
    }
};

/// `x! = x`: the start block alternative that is the start symbol itself.
fn isEntryIdiom(name: []const u8, alt: ParsedAlternative) bool {
    if (alt.elements.len != 1) return false;
    const e = alt.elements[0];
    return e.kind == .ident and e.quantifier == .one and e.label == null and !e.skip and std.mem.eql(u8, e.value, name);
}

/// The target of `name = X` when the rule is an alias, which expansion
/// substitutes for every use of the name: the only block for the name, not
/// a start symbol, one alternative of one unlabeled token or rule name,
/// no action. Semantics judges values through the same definition.
pub fn aliasTarget(ir: *const GrammarIR, rule: ParsedRule) ?[]const u8 {
    for (ir.startSymbols) |s| if (std.mem.eql(u8, s, rule.name)) return null;
    var blocks: usize = 0;
    for (ir.rules) |r| blocks += @intFromBool(std.mem.eql(u8, r.name, rule.name));
    if (blocks != 1 or rule.alternatives.len != 1) return null;
    const alt = rule.alternatives[0];
    if (alt.elements.len != 1) return null;
    const elem = alt.elements[0];
    if (elem.kind != .token and elem.kind != .ident) return null;
    if (elem.quantifier != .one or elem.label != null) return null;
    if (alt.actionTree != null) return null;
    return elem.value;
}

const emptyList: ActionTree = .{ .list = .{ .head = .none, .items = &.{} } };

/// The lists `X*`, `X+` and `L(X)` build are left-recursive, so the
/// generated parser extends each in place (amortized O(1) per item) and
/// keeps its stack flat. They hold one item per element, nils included.
const singleton: ActionTree = .{ .list = .{ .head = .none, .items = &.{.{ .elem = .{ .ref = 1 } }}, .keepNils = true } };

/// `(...1 N)`: the list at 1 with element N appended.
fn appendTree(allocator: Allocator, n: u16) !ActionTree {
    const items = try allocator.dupe(ActionItem, &.{ .{ .elem = .{ .spread = 1 } }, .{ .elem = .{ .ref = n } } });
    return .{ .list = .{ .head = .none, .items = items, .keepNils = true } };
}

/// The value of a `( ... )` group or a choice alternative: nil when every
/// element is skipped, the element when one is kept, the kept elements as
/// a list when some are skipped (nils kept, like the default), and the
/// default (null) otherwise.
fn groupAction(allocator: Allocator, elements: []const ParsedElement) !?ActionTree {
    var kept: std.ArrayList(u16) = .empty;
    for (elements, 0..) |sub, i| if (!sub.skip) try kept.append(allocator, @intCast(i + 1));
    if (kept.items.len == 0) return .nil;
    if (kept.items.len == 1) return .{ .pass = kept.items[0] };
    if (kept.items.len == elements.len) return null;
    var items: std.ArrayList(ActionItem) = .empty;
    for (kept.items) |p| try items.append(allocator, .{ .elem = .{ .ref = p } });
    // Like the default action, a kept nil stays (no trailing-nil cut).
    return .{ .list = .{ .head = .none, .items = try items.toOwnedSlice(allocator), .keepNils = true } };
}

/// Without a schema, a list whose first item is `role:N` and that has no
/// head tag is headed by the tag `role` (`(ref:1 postcond:2)` reads as
/// `(ref 1 2)`); applied to unexpanded alternatives only.
fn roleHead(tree: ActionTree) ActionTree {
    const l = switch (tree) {
        .list => |l| l,
        else => return tree,
    };
    if (l.head != .none or l.items.len == 0) return tree;
    const role = l.items[0].role orelse return tree;
    return .{ .list = .{ .head = .{ .tag = role }, .items = l.items } };
}

/// The trailing-nil cut of an expanded alternative's action without a
/// schema: the items from the first absent position after the last present
/// one on are dropped. `original` and `mapped` are parallel (schema-less
/// mapping keeps every item).
fn trailingCut(original: []const ActionItem, mapped: []const ActionItem) []const ActionItem {
    var lastPresent: ?usize = null;
    var firstRef: ?usize = null;
    for (original, 0..) |item, i| {
        const isRef = switch (item.elem) {
            .ref, .spread, .symId => true,
            else => false,
        };
        if (!isRef) continue;
        if (firstRef == null) firstRef = i;
        if (mapped[i].elem != .nil) lastPresent = i;
    }
    const start = firstRef orelse return mapped;
    const cutFrom = if (lastPresent) |lp| blk: {
        for (original[lp + 1 ..], lp + 1..) |item, i| switch (item.elem) {
            .ref, .spread, .symId => break :blk i,
            else => {},
        };
        return mapped;
    } else start;
    return mapped[0..cutFrom];
}
