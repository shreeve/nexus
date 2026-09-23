//! Desugaring: turns the lowered GrammarIR into the plain BNF Grammar the LR
//! stages consume. Registers symbols and aliases; expands `[opt]` groups and
//! `(A | B)` choices into explicit alternatives (stable action positions);
//! maps every alternative's action tree onto its expanded right-hand side;
//! synthesizes rules for `X?`, `X*`, `X+`, `L(X)`, `( ... )` groups, the
//! `@infix` precedence chain, and one entry rule per start symbol.
//!
//! Action positions. A pattern's positions are its top-level elements in
//! order, where a multi-element `[A B]` group counts one position per
//! element and a choice counts one. The elements inside choice
//! alternatives get further "internal" positions after those (see
//! `Layout`), which the semantic layer uses to address labeled elements;
//! a grammar cannot write them. Expansion maps each position to the
//! element's index in the expanded right-hand side, or to "absent".
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

/// Process parsed grammar into internal representation
pub fn processGrammar(g: *Grammar, ir: *const GrammarIR, opts: Options) Error!void {
    var x = Expander{ .g = g, .ir = ir, .opts = opts };
    return x.run();
}

// =============================================================================
// Positions
// =============================================================================

/// Where one action position points in a pattern.
pub const Slot = struct {
    /// Index of the top-level element.
    elem: u16,
    kind: Kind,
    /// optGroup: sub-element index. choiceElem: alternative index.
    sub: u16 = 0,
    /// choiceElem: element index within the alternative.
    subElem: u16 = 0,

    pub const Kind = enum { plain, optSub, choice, choiceElem };
};

/// The positions of a pattern: `slots[p - 1]` for position p. The first
/// `length` are the positions a grammar writes; the rest are internal
/// positions of the elements inside choice alternatives.
pub const Layout = struct {
    slots: []const Slot,
    length: usize,

    pub fn of(allocator: Allocator, elements: []const ParsedElement) !Layout {
        var slots: std.ArrayListUnmanaged(Slot) = .empty;
        for (elements, 0..) |e, i| {
            const idx: u16 = @intCast(i);
            if (e.kind == .optGroup) {
                for (0..e.subElements.len) |j| try slots.append(allocator, .{ .elem = idx, .kind = .optSub, .sub = @intCast(j) });
            } else if (e.kind == .choice) {
                try slots.append(allocator, .{ .elem = idx, .kind = .choice });
            } else {
                try slots.append(allocator, .{ .elem = idx, .kind = .plain });
            }
        }
        const length = slots.items.len;
        for (elements, 0..) |e, i| {
            if (e.kind != .choice) continue;
            for (e.choices, 0..) |alt, a| for (0..alt.len) |j| {
                try slots.append(allocator, .{ .elem = @intCast(i), .kind = .choiceElem, .sub = @intCast(a), .subElem = @intCast(j) });
            };
        }
        return .{ .slots = try slots.toOwnedSlice(allocator), .length = length };
    }

    /// The element at position p (1-based).
    pub fn element(self: Layout, elements: []const ParsedElement, p: usize) ParsedElement {
        const s = self.slots[p - 1];
        const e = elements[s.elem];
        return switch (s.kind) {
            .plain, .choice => e,
            .optSub => e.subElements[s.sub],
            .choiceElem => e.choices[s.sub][s.subElem],
        };
    }
};

/// A position's value in one expanded variant.
const absent: u16 = 0;
/// A choice position whose chosen alternative has several elements.
const multi: u16 = std.math.maxInt(u16);

/// Whether expansion turns this top-level element into variants: `[A B]`
/// groups, `[X]` on a rule name or list, and non-repeated choices.
fn isVariable(e: ParsedElement) bool {
    return switch (e.kind) {
        .optGroup => true,
        .choice => e.quantifier == .one or e.quantifier == .optional,
        .ident, .optList => e.quantifier == .optional,
        else => false,
    };
}

fn radix(e: ParsedElement) usize {
    return switch (e.kind) {
        .choice => e.choices.len + @intFromBool(e.quantifier == .optional),
        else => 2,
    };
}

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
        g.acceptId = try g.addSymbol("$accept", .nonterminal);
        g.endId = try g.addSymbol("$end", .terminal);
        g.errorId = try g.addSymbol("error", .terminal);

        for (ir.rules) |rule| {
            if (self.isStart(rule.name) or self.blocks(rule.name) != 1) continue;
            if (isAliasRule(rule)) |target| try g.aliases.put(g.allocator, rule.name, target);
        }
        for (ir.rules) |rule| {
            if (g.aliases.contains(rule.name)) continue;
            _ = try g.addSymbol(rule.name, .nonterminal);
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

    fn addRule(self: *Expander, rule: Rule) !u16 {
        const g = self.g;
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

    // --- Start symbols ---

    fn isStart(self: *const Expander, name: []const u8) bool {
        for (self.ir.startSymbols) |s| if (std.mem.eql(u8, s, name)) return true;
        return false;
    }

    /// Number of `name = ...` blocks for `name`.
    fn blocks(self: *const Expander, name: []const u8) usize {
        var n: usize = 0;
        for (self.ir.rules) |r| n += @intFromBool(std.mem.eql(u8, r.name, name));
        return n;
    }

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
            const markerId = try g.addSymbol(try std.fmt.allocPrint(g.allocator, "{s}!", .{startName}), .terminal);
            const acceptId = try g.addSymbol(try std.fmt.allocPrint(g.allocator, "$accept_{s}", .{startName}), .nonterminal);
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
        try self.checkElements(alt);
        self.originLine = alt.line;
        self.originCol = alt.col;

        const layout = try Layout.of(a, alt.elements);
        if (!self.schemaMode()) if (alt.actionTree) |t| switch (t) {
            .list => |l| try self.checkSpreads(alt, layout, l),
            else => {},
        };
        var vars: std.ArrayListUnmanaged(usize) = .empty;
        for (alt.elements, 0..) |e, i| if (isVariable(e)) try vars.append(a, i);

        var total: usize = 1;
        for (vars.items) |i| total *= radix(alt.elements[i]);

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
            // Mixed-radix digits, the first variable element least significant.
            var rest = combo;
            for (vars.items, 0..) |i, d| {
                const r = radix(alt.elements[i]);
                digits[d] = rest % r;
                rest /= r;
            }

            var rhs: std.ArrayListUnmanaged(ParsedElement) = .empty;
            @memset(posMap, absent);
            var p: usize = 1;
            var d: usize = 0;
            for (alt.elements, 0..) |e, i| {
                if (!isVariable(e)) {
                    try rhs.append(a, e);
                    posMap[p] = @intCast(rhs.items.len);
                    p += 1;
                    continue;
                }
                const digit = digits[d];
                d += 1;
                switch (e.kind) {
                    .optGroup => {
                        for (e.subElements) |sub| {
                            if (digit == 1) {
                                try rhs.append(a, sub);
                                posMap[p] = @intCast(rhs.items.len);
                            }
                            p += 1;
                        }
                    },
                    .choice => {
                        const optional = e.quantifier == .optional;
                        if (!optional or digit > 0) {
                            const ai = if (optional) digit - 1 else digit;
                            const choice = e.choices[ai];
                            for (choice, 0..) |sub, j| {
                                try rhs.append(a, sub);
                                posMap[internalPos(layout, i, ai, j)] = @intCast(rhs.items.len);
                            }
                            posMap[p] = if (choice.len == 1) @intCast(rhs.items.len) else multi;
                        }
                        p += 1;
                    },
                    else => {
                        if (digit == 1) {
                            var one = e;
                            one.quantifier = .one;
                            try rhs.append(a, one);
                            posMap[p] = @intCast(rhs.items.len);
                        }
                        p += 1;
                    },
                }
            }

            var symbols: std.ArrayListUnmanaged(u16) = .empty;
            for (rhs.items) |e| try symbols.append(a, try self.processElement(e));

            const mapped: ?ActionTree = if (tree) |t|
                try self.mapTree(t, posMap, vars.items.len > 0, alt)
            else if (vars.items.len > 0)
                try self.expandedDefault(alt, digits, rhs.items.len)
            else
                null;

            var sideLabels: std.ArrayListUnmanaged(Rule.SideLabel) = .empty;
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

    /// The default action (no `→`) of one variant of an expanded
    /// alternative: every element's value in order, with nil for each
    /// absent optional element, exactly as when the optional element is
    /// not expanded (`[T]`, `T?`: a rule that yields nil). A chosen choice
    /// alternative contributes its elements. One value is passed through.
    fn expandedDefault(self: *Expander, alt: ParsedAlternative, digits: []const usize, rhsLen: usize) Error!ActionTree {
        const a = self.alloc();
        var items: std.ArrayListUnmanaged(ActionItem) = .empty;
        var at: u16 = 0; // rhs elements placed so far
        var d: usize = 0;
        for (alt.elements) |e| {
            if (!isVariable(e)) {
                at += 1;
                try items.append(a, .{ .elem = .{ .ref = at } });
                continue;
            }
            const digit = digits[d];
            d += 1;
            switch (e.kind) {
                .optGroup => for (e.subElements) |_| {
                    if (digit == 1) {
                        at += 1;
                        try items.append(a, .{ .elem = .{ .ref = at } });
                    } else try items.append(a, .{ .elem = .nil });
                },
                .choice => {
                    const optional = e.quantifier == .optional;
                    if (optional and digit == 0) {
                        try items.append(a, .{ .elem = .nil });
                    } else for (e.choices[if (optional) digit - 1 else digit]) |_| {
                        at += 1;
                        try items.append(a, .{ .elem = .{ .ref = at } });
                    }
                },
                else => if (digit == 1) {
                    at += 1;
                    try items.append(a, .{ .elem = .{ .ref = at } });
                } else try items.append(a, .{ .elem = .nil }),
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

    fn internalPos(layout: Layout, elem: usize, alt: usize, j: usize) usize {
        for (layout.slots[layout.length..], layout.length..) |s, k| {
            if (s.elem == elem and s.sub == alt and s.subElem == j) return k + 1;
        }
        unreachable;
    }

    /// Constructs expansion does not support, and labels without a schema.
    fn checkElements(self: *Expander, alt: ParsedAlternative) Error!void {
        for (alt.elements) |e| {
            try self.checkLabel(e);
            switch (e.kind) {
                .optGroup => for (e.subElements) |sub| {
                    try self.checkLabel(sub);
                    try self.checkNested(sub, "a [...] group");
                },
                .choice => for (e.choices) |choice| for (choice) |sub| {
                    try self.checkLabel(sub);
                    try self.checkNested(sub, "a choice");
                },
                .group => for (e.subElements) |sub| {
                    if (sub.label != null and !std.mem.eql(u8, sub.label.?, "_"))
                        return self.fail(sub.line, sub.col, "labels inside a ( ... ) group are not supported; label the group's rule instead", .{});
                },
                else => {},
            }
        }
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

    fn checkLabel(self: *Expander, e: ParsedElement) Error!void {
        const label = e.label orelse return;
        if (self.schemaMode() or std.mem.eql(u8, label, "_")) return;
        return self.fail(e.line, e.col, "pattern label '{s}' needs an @schema (labels fill schema roles)", .{label});
    }

    fn checkNested(self: *Expander, e: ParsedElement, where: []const u8) Error!void {
        if (e.kind == .optGroup or e.kind == .choice)
            return self.fail(e.line, e.col, "a multi-element [...] group or a choice inside {s} is not supported; use a helper rule", .{where});
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
            var items: std.ArrayListUnmanaged(ActionItem) = .empty;
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
        if (g.getSymbol(name)) |id| return id;
        var resolved = name;
        var hops: usize = 0;
        while (g.aliases.get(resolved)) |target| : (hops += 1) {
            if (hops > 100) break;
            resolved = target;
        }
        const kind: Symbol.Kind = if (forceTerminal or (resolved.len > 0 and resolved[0] >= 'A' and resolved[0] <= 'Z'))
            .terminal
        else
            .nonterminal;
        return g.addSymbol(resolved, kind);
    }

    fn processBaseElement(self: *Expander, elem: ParsedElement) Error!u16 {
        const g = self.g;
        return switch (elem.kind) {
            .ident => try self.nameSymbol(elem.value, false),
            .token => try self.nameSymbol(elem.value, true),
            .string => try g.addSymbol(elem.value, .terminal),
            .group => try self.groupRule(elem.subElements),
            .choice => try self.choiceRule(elem.choices),
            // Multi-element [A B] groups are expanded into alternatives, and
            // nested ones are rejected by checkElements.
            .optGroup => unreachable,
            .reqList => try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator),
            .optList => try self.createOptionalRule(try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator)),
        };
    }

    /// The symbols of a group or choice alternative, and its source-syntax
    /// text: the elements' names separated by spaces, `!` marking a
    /// skipped element.
    fn sequence(self: *Expander, elements: []const ParsedElement, text: *std.ArrayListUnmanaged(u8)) Error![]const u16 {
        const a = self.alloc();
        var rhs: std.ArrayListUnmanaged(u16) = .empty;
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
        var text: std.ArrayListUnmanaged(u8) = .empty;
        try text.append(g.allocator, '(');
        const rhs = try self.sequence(elements, &text);
        try text.append(g.allocator, ')');
        if (g.getSymbol(text.items)) |existing| return existing;
        const id = try g.addSymbol(try text.toOwnedSlice(g.allocator), .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = id, .rhs = rhs, .actionTree = try groupAction(g.allocator, elements) });
        return id;
    }

    /// A repeated choice, `(A | B)*` or `(A | B)+`: the symbol `(A | B)`
    /// with one rule per alternative. Identical choices share one symbol.
    fn choiceRule(self: *Expander, choices: []const []const ParsedElement) Error!u16 {
        const g = self.g;
        var text: std.ArrayListUnmanaged(u8) = .empty;
        try text.append(g.allocator, '(');
        const rhss = try g.allocator.alloc([]const u16, choices.len);
        for (choices, 0..) |choice, i| {
            if (i > 0) try text.appendSlice(g.allocator, " | ");
            rhss[i] = try self.sequence(choice, &text);
        }
        try text.append(g.allocator, ')');
        if (g.getSymbol(text.items)) |existing| return existing;
        const id = try g.addSymbol(try text.toOwnedSlice(g.allocator), .nonterminal);
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
            (if (sep[0] == '"') try g.addSymbol(sep, .terminal) else try self.nameSymbol(sep, true))
        else
            try g.addSymbol("\",\"", .terminal);

        // One rule set per (item, item optionality, separator), named in
        // source syntax: `L(X)`, `L(X?)`, `L(X, sep)`, and `L(X).tail` for
        // the repetition after the first item. `","` is the default
        // separator.
        const sepName = g.symbols.items[sepId].name;
        const listName = if (std.mem.eql(u8, sepName, "\",\""))
            try std.fmt.allocPrint(g.allocator, "L({s})", .{g.symbols.items[effectiveItemId].name})
        else
            try std.fmt.allocPrint(g.allocator, "L({s}, {s})", .{ g.symbols.items[effectiveItemId].name, sepName });
        if (g.getSymbol(listName)) |existing| return existing;
        const tailName = try std.fmt.allocPrint(g.allocator, "{s}.tail", .{listName});

        const listId = try g.addSymbol(listName, .nonterminal);
        const tailId = try g.addSymbol(tailName, .nonterminal);

        // L(X) → X L(X).tail → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = listId,
            .rhs = try g.allocator.dupe(u16, &.{ effectiveItemId, tailId }),
            .actionTree = try consTree(g.allocator, 1),
        });
        // L(X).tail → sep X L(X).tail → (!2 ...3)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = tailId,
            .rhs = try g.allocator.dupe(u16, &.{ sepId, effectiveItemId, tailId }),
            .actionTree = try consTree(g.allocator, 2),
        });
        // L(X).tail → ε → ()
        _ = try self.addRule(.{
            .id = 0,
            .lhs = tailId,
            .rhs = &[_]u16{},
            .actionTree = emptyList,
        });
        return listId;
    }

    fn createOptionalRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "{s}?", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const optId = try g.addSymbol(name, .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = try g.allocator.dupe(u16, &.{symId}) });
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = &[_]u16{} });
        return optId;
    }

    fn createZeroPlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "{s}*", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const starId = try g.addSymbol(name, .nonterminal);
        // X* → X X* → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = starId,
            .rhs = try g.allocator.dupe(u16, &.{ symId, starId }),
            .actionTree = try consTree(g.allocator, 1),
        });
        // X* → ε → ()
        _ = try self.addRule(.{ .id = 0, .lhs = starId, .rhs = &[_]u16{}, .actionTree = emptyList });
        return starId;
    }

    fn createOnePlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "{s}+", .{g.symbols.items[symId].name});
        if (g.getSymbol(name)) |existing| return existing;
        const starId = try self.createZeroPlusRule(symId);
        const plusId = try g.addSymbol(name, .nonterminal);
        // X+ → X X* → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = plusId,
            .rhs = try g.allocator.dupe(u16, &.{ symId, starId }),
            .actionTree = try consTree(g.allocator, 1),
        });
        return plusId;
    }

    fn generateInfixChain(self: *Expander, infix: InfixDecl) Error!void {
        const g = self.g;
        const baseId = g.getSymbol(infix.baseRule) orelse try g.addSymbol(infix.baseRule, .nonterminal);

        // Precedence levels, ascending (level 1 binds loosest).
        var levels: std.ArrayListUnmanaged(u32) = .empty;
        for (infix.ops) |op| {
            if (std.mem.indexOfScalar(u32, levels.items, op.prec) == null) try levels.append(g.allocator, op.prec);
        }
        std.mem.sort(u32, levels.items, {}, std.sort.asc(u32));

        // Each level is named by its operators: `infix("+" "-")`.
        var levelIds: std.ArrayListUnmanaged(u16) = .empty;
        for (levels.items) |level| {
            var name: std.ArrayListUnmanaged(u8) = .empty;
            try name.appendSlice(g.allocator, "infix(");
            var first = true;
            for (infix.ops) |op| {
                if (op.prec != level) continue;
                if (!first) try name.append(g.allocator, ' ');
                first = false;
                try name.print(g.allocator, "\"{s}\"", .{op.op});
            }
            try name.append(g.allocator, ')');
            try levelIds.append(g.allocator, try g.addSymbol(try name.toOwnedSlice(g.allocator), .nonterminal));
        }

        for (levels.items, 0..) |level, i| {
            const thisId = levelIds.items[i];
            const nextId = if (i + 1 < levels.items.len) levelIds.items[i + 1] else baseId;
            for (infix.ops, 0..) |op, opIndex| {
                if (op.prec != level) continue;
                const opStr = try std.fmt.allocPrint(g.allocator, "\"{s}\"", .{op.op});
                const opId = try g.addSymbol(opStr, .terminal);
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
        const infixId = try g.addSymbol("infix", .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = infixId, .rhs = try g.allocator.dupe(u16, &.{levelIds.items[0]}), .actionTree = .{ .pass = 1 }, .line = infix.line, .col = infix.col });
    }
};

/// `x! = x`: the start block alternative that is the start symbol itself.
fn isEntryIdiom(name: []const u8, alt: ParsedAlternative) bool {
    if (alt.elements.len != 1) return false;
    const e = alt.elements[0];
    return e.kind == .ident and e.quantifier == .one and e.label == null and !e.skip and std.mem.eql(u8, e.value, name);
}

fn isAliasRule(rule: ParsedRule) ?[]const u8 {
    if (rule.alternatives.len != 1) return null;
    const alt = rule.alternatives[0];
    if (alt.elements.len != 1) return null;
    const elem = alt.elements[0];
    if (elem.kind != .token and elem.kind != .ident) return null;
    if (elem.quantifier != .one or elem.label != null) return null;
    if (alt.actionTree != null) return null;
    return elem.value;
}

const emptyList: ActionTree = .{ .list = .{ .head = .none, .items = &.{} } };

/// `(!N ...N+1)`: element N consed onto the list at N+1.
fn consTree(allocator: Allocator, n: u16) !ActionTree {
    const items = try allocator.dupe(ActionItem, &.{.{ .elem = .{ .spread = n + 1 } }});
    return .{ .list = .{ .head = .{ .ref = .{ .ref = n } }, .items = items } };
}

/// The value of a `( ... )` group or a choice alternative: nil when every
/// element is skipped, the element when one is kept, the kept elements as
/// a list when some are skipped (nils kept, like the default), and the
/// default (null) otherwise.
fn groupAction(allocator: Allocator, elements: []const ParsedElement) !?ActionTree {
    var kept: std.ArrayListUnmanaged(u16) = .empty;
    for (elements, 0..) |sub, i| if (!sub.skip) try kept.append(allocator, @intCast(i + 1));
    if (kept.items.len == 0) return .nil;
    if (kept.items.len == 1) return .{ .pass = kept.items[0] };
    if (kept.items.len == elements.len) return null;
    var items: std.ArrayListUnmanaged(ActionItem) = .empty;
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
