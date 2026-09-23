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
//! `...N` contributes nothing. Without a schema the 0.10 rules apply
//! unchanged: an absent `N`, `~N` or `...N` becomes nil, and in an
//! expanded alternative the action is cut before the first absent
//! position that is followed by no present one (trailing nils dropped).

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

        try self.addStartRules();

        g.asDirectives = ir.asDirectives;
        g.opMappings = ir.opMappings;
        g.errorNames = ir.errorNames;
        g.displayNames = ir.displayNames;
        g.lang = ir.lang;
        g.expectConflicts = ir.expectConflicts;
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
                .action = null,
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
                .action = null,
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

        const layout = try Layout.of(a, alt.elements);
        var vars: std.ArrayListUnmanaged(usize) = .empty;
        for (alt.elements, 0..) |e, i| if (isVariable(e)) try vars.append(a, i);

        var total: usize = 1;
        for (vars.items) |i| total *= radix(alt.elements[i]);

        // Without a schema, a leading `role:N` names the head tag only when
        // the alternative is not expanded (0.10 dropped the key otherwise).
        const tree: ?ActionTree = if (resolved) |r|
            r.tree
        else if (alt.actionTree) |t|
            (if (vars.items.len == 0) legacyHeadRole(t) else t)
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
                .action = if (mapped) |t| try grammar.renderAction(a, t) else null,
                .actionTree = mapped,
                .excludeChar = alt.excludeChar,
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
        legacy: bool,
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
                .spread => |p| if (try self.at(p) != absent) .{ .spread = try self.at(p) } else if (self.legacy) .nil else null,
                .node => |l| .{ .node = try self.listPtr(l.*) },
                .nil, .tagLit, .label => e,
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
        const m = Mapper{ .x = self, .posMap = posMap, .legacy = !self.schemaMode(), .alt = alt };
        switch (tree) {
            .nil => return .nil,
            .pass => |p| {
                const v = try m.at(p);
                return if (v == absent) .nil else .{ .pass = v };
            },
            .list => |l| {
                var mapped = try m.list(l);
                if (m.legacy and expanded) mapped.items = legacyCut(l.items, mapped.items);
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
            .group => try self.groupRule(elem.subElements, "_grp_"),
            .choice => blk: {
                // A repeated choice, (A | B)* or (A | B)+: one rule per alternative.
                const name = try std.fmt.allocPrint(g.allocator, "_choice_{d}", .{g.rules.items.len});
                const id = try g.addSymbol(name, .nonterminal);
                for (elem.choices) |choice| {
                    var rhs: std.ArrayListUnmanaged(u16) = .empty;
                    for (choice) |sub| try rhs.append(g.allocator, try self.processElement(sub));
                    _ = try self.addRule(.{
                        .id = 0,
                        .lhs = id,
                        .rhs = try rhs.toOwnedSlice(g.allocator),
                        .action = null,
                        .actionTree = try groupAction(g.allocator, choice),
                    });
                }
                break :blk id;
            },
            // Multi-element [A B] groups are expanded into alternatives, and
            // nested ones are rejected by checkElements.
            .optGroup => unreachable,
            .reqList => try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator),
            .optList => try self.createOptionalRule(try self.createRequiredList(elem.value, elem.optionalItems, elem.listSeparator)),
        };
    }

    /// A `( ... )` group: a rule over its elements whose value leaves out
    /// the `!X` elements.
    fn groupRule(self: *Expander, elements: []const ParsedElement, prefix: []const u8) Error!u16 {
        const g = self.g;
        if (elements.len == 0) return g.errorId;
        const name = try std.fmt.allocPrint(g.allocator, "{s}{d}", .{ prefix, g.rules.items.len });
        const id = try g.addSymbol(name, .nonterminal);
        var rhs: std.ArrayListUnmanaged(u16) = .empty;
        for (elements) |sub| try rhs.append(g.allocator, try self.processElement(sub));
        const tree = try groupAction(g.allocator, elements);
        _ = try self.addRule(.{
            .id = 0,
            .lhs = id,
            .rhs = try rhs.toOwnedSlice(g.allocator),
            .action = if (tree) |t| try grammar.renderAction(g.allocator, t) else null,
            .actionTree = tree,
        });
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

        // One rule set per (item, item optionality, separator).
        const suffix: []const u8 = if (optionalItems) "opt" else "";
        const listName = try std.fmt.allocPrint(g.allocator, "_list_{d}{s}_{d}", .{ itemId, suffix, sepId });
        const tailName = try std.fmt.allocPrint(g.allocator, "_tail_{d}{s}_{d}", .{ itemId, suffix, sepId });
        if (g.getSymbol(listName)) |existing| return existing;

        const listId = try g.addSymbol(listName, .nonterminal);
        const tailId = try g.addSymbol(tailName, .nonterminal);

        // _list → item _tail → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = listId,
            .rhs = try g.allocator.dupe(u16, &.{ effectiveItemId, tailId }),
            .action = "(!1 ...2)",
            .actionTree = try consTree(g.allocator, 1),
        });
        // _tail → sep item _tail → (!2 ...3)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = tailId,
            .rhs = try g.allocator.dupe(u16, &.{ sepId, effectiveItemId, tailId }),
            .action = "(!2 ...3)",
            .actionTree = try consTree(g.allocator, 2),
        });
        // _tail → ε → ()
        _ = try self.addRule(.{
            .id = 0,
            .lhs = tailId,
            .rhs = &[_]u16{},
            .action = "()",
            .actionTree = emptyList,
            .nullable = true,
            .preferShift = true,
        });
        g.symbols.items[tailId].nullable = true;
        return listId;
    }

    fn createOptionalRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "_opt_{d}", .{symId});
        if (g.getSymbol(name)) |existing| return existing;
        const optId = try g.addSymbol(name, .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = try g.allocator.dupe(u16, &.{symId}), .action = null });
        _ = try self.addRule(.{ .id = 0, .lhs = optId, .rhs = &[_]u16{}, .action = null, .nullable = true });
        g.symbols.items[optId].nullable = true;
        return optId;
    }

    fn createZeroPlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "_star_{d}", .{symId});
        if (g.getSymbol(name)) |existing| return existing;
        const starId = try g.addSymbol(name, .nonterminal);
        // star → sym star → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = starId,
            .rhs = try g.allocator.dupe(u16, &.{ symId, starId }),
            .action = "(!1 ...2)",
            .actionTree = try consTree(g.allocator, 1),
        });
        // star → ε → ()
        _ = try self.addRule(.{ .id = 0, .lhs = starId, .rhs = &[_]u16{}, .action = "()", .actionTree = emptyList, .nullable = true });
        g.symbols.items[starId].nullable = true;
        return starId;
    }

    fn createOnePlusRule(self: *Expander, symId: u16) Error!u16 {
        const g = self.g;
        const name = try std.fmt.allocPrint(g.allocator, "_plus_{d}", .{symId});
        if (g.getSymbol(name)) |existing| return existing;
        const starId = try self.createZeroPlusRule(symId);
        const plusId = try g.addSymbol(name, .nonterminal);
        // plus → sym star → (!1 ...2)
        _ = try self.addRule(.{
            .id = 0,
            .lhs = plusId,
            .rhs = try g.allocator.dupe(u16, &.{ symId, starId }),
            .action = "(!1 ...2)",
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

        var levelIds: std.ArrayListUnmanaged(u16) = .empty;
        for (levels.items) |level| {
            const name = try std.fmt.allocPrint(g.allocator, "_infix_{d}", .{level});
            try levelIds.append(g.allocator, try g.addSymbol(name, .nonterminal));
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
                    .action = try grammar.renderAction(g.allocator, tree),
                    .actionTree = tree,
                    .kind = kind,
                });
            }
            // this_level → next_level
            _ = try self.addRule(.{ .id = 0, .lhs = thisId, .rhs = try g.allocator.dupe(u16, &.{nextId}), .action = "1", .actionTree = .{ .pass = 1 } });
        }

        // `infix` → the loosest level
        const infixId = try g.addSymbol("infix", .nonterminal);
        _ = try self.addRule(.{ .id = 0, .lhs = infixId, .rhs = try g.allocator.dupe(u16, &.{levelIds.items[0]}), .action = "1", .actionTree = .{ .pass = 1 } });
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
/// a list when some are skipped, and the default (null) otherwise.
fn groupAction(allocator: Allocator, elements: []const ParsedElement) !?ActionTree {
    var kept: std.ArrayListUnmanaged(u16) = .empty;
    for (elements, 0..) |sub, i| if (!sub.skip) try kept.append(allocator, @intCast(i + 1));
    if (kept.items.len == 0) return .nil;
    if (kept.items.len == 1) return .{ .pass = kept.items[0] };
    if (kept.items.len == elements.len) return null;
    var items: std.ArrayListUnmanaged(ActionItem) = .empty;
    for (kept.items) |p| try items.append(allocator, .{ .elem = .{ .ref = p } });
    return .{ .list = .{ .head = .none, .items = try items.toOwnedSlice(allocator) } };
}

/// Without a schema, a list whose first item is `role:N` and that has no
/// head tag is headed by the tag `role` (the 0.10 reading of
/// `(ref:1 postcond:2)` as `(ref 1 2)`); applied to unexpanded
/// alternatives only, as in 0.10.
fn legacyHeadRole(tree: ActionTree) ActionTree {
    const l = switch (tree) {
        .list => |l| l,
        else => return tree,
    };
    if (l.head != .none or l.items.len == 0) return tree;
    const role = l.items[0].role orelse return tree;
    return .{ .list = .{ .head = .{ .tag = role }, .items = l.items } };
}

/// The 0.10 trailing-nil cut of an expanded alternative's action: the
/// items from the first absent position after the last present one on
/// are dropped. `original` and `mapped` are parallel (legacy mapping keeps
/// every item).
fn legacyCut(original: []const ActionItem, mapped: []const ActionItem) []const ActionItem {
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
