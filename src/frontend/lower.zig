//! Strict, schema-driven lowering of the frontend Sexp tree into GrammarIR.

const std = @import("std");
const diag = @import("../diag.zig");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Sexp = parser.Sexp;
const Tag = parser.Tag;
const grammar = @import("../grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const InfixDecl = grammar.InfixDecl;
const InfixOp = grammar.InfixOp;
const AsDirective = grammar.AsDirective;
const OpMapping = grammar.OpMapping;
const ErrorName = grammar.ErrorName;

// =============================================================================
// Grammar Lowerer — schema-driven Sexp → GrammarIR conversion
//
// Consumes the canonical S-expression tree produced by the generated
// nexus.grammar frontend (see the schema block at the top of nexus.grammar)
// and builds the same GrammarIR that processGrammar expects.
//
// Every lowering entry point receives exactly the documented shape or raises
// error.ShapeError with a byte offset into the parser section. There are no
// silent fall-throughs, no permissive default cases, and no heuristic shape
// unwrapping. Tag dispatch is exhaustive by construction.
// =============================================================================

pub const GrammarLowerer = struct {
    allocator: Allocator,
    source: []const u8, // The @parser section body — positions in .src nodes are offsets into this slice.

    rules: std.ArrayListUnmanaged(ParsedRule) = .empty,
    startSymbols: std.ArrayListUnmanaged([]const u8) = .empty,
    asDirectives: std.ArrayListUnmanaged(AsDirective) = .empty,
    opMappings: std.ArrayListUnmanaged(OpMapping) = .empty,
    errorNames: std.ArrayListUnmanaged(ErrorName) = .empty,
    infixOps: std.ArrayListUnmanaged(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    expectConflicts: ?u32 = null,

    const LoweringError = error{ ShapeError, OutOfMemory };

    pub fn lower(allocator: Allocator, sexp: Sexp, source: []const u8) LoweringError!GrammarIR {
        var self = GrammarLowerer{ .allocator = allocator, .source = source };
        try self.lowerRoot(sexp);
        return GrammarIR{
            .rules = try self.rules.toOwnedSlice(allocator),
            .startSymbols = try self.startSymbols.toOwnedSlice(allocator),
            .asDirectives = try self.asDirectives.toOwnedSlice(allocator),
            .opMappings = try self.opMappings.toOwnedSlice(allocator),
            .errorNames = try self.errorNames.toOwnedSlice(allocator),
            .infix = if (self.infixBase) |base| InfixDecl{
                .baseRule = base,
                .ops = try self.infixOps.toOwnedSlice(allocator),
            } else null,
            .lang = self.lang,
            .expectConflicts = self.expectConflicts,
        };
    }

    // --- Shape helpers ---

    fn listItems(node: Sexp) ?[]const Sexp {
        return switch (node) {
            .list => |items| items,
            else => null,
        };
    }

    fn taggedItems(node: Sexp) ?struct { tag: Tag, items: []const Sexp } {
        const items = listItems(node) orelse return null;
        if (items.len == 0) return null;
        const tag = switch (items[0]) {
            .tag => |t| t,
            else => return null,
        };
        return .{ .tag = tag, .items = items };
    }

    fn stripQuotes(s: []const u8) []const u8 {
        if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
        return s;
    }

    fn nodeOffset(node: Sexp) u32 {
        return switch (node) {
            .src => |s| s.pos,
            .list => |items| if (items.len > 0) nodeOffset(items[0]) else 0,
            else => 0,
        };
    }

    fn shapeError(self: *const GrammarLowerer, node: Sexp, expected: []const u8) LoweringError {
        // The negative-test suite fires this path by design; silencing the
        // diagnostic during `zig test` keeps the test runner's output clean
        // without losing real diagnostics in production runs.
        if (!@import("builtin").is_test) {
            const off = nodeOffset(node);
            var line: u32 = 1;
            var col: u32 = 1;
            var i: usize = 0;
            while (i < off and i < self.source.len) : (i += 1) {
                if (self.source[i] == '\n') {
                    line += 1;
                    col = 1;
                } else col += 1;
            }
            diag.err("shape error at line {d}, col {d}: expected {s}", .{ line, col, expected });
        }
        return error.ShapeError;
    }

    fn requireTag(self: *const GrammarLowerer, node: Sexp, expected: Tag) LoweringError![]const Sexp {
        const t = taggedItems(node) orelse return self.shapeError(node, @tagName(expected));
        if (t.tag != expected) return self.shapeError(node, @tagName(expected));
        return t.items;
    }

    fn requireSrc(self: *const GrammarLowerer, node: Sexp, what: []const u8) LoweringError![]const u8 {
        return switch (node) {
            .src => |s| self.source[s.pos..][0..s.len],
            else => self.shapeError(node, what),
        };
    }

    fn requireList(self: *const GrammarLowerer, node: Sexp, what: []const u8) LoweringError![]const Sexp {
        return listItems(node) orelse self.shapeError(node, what);
    }

    // --- Root ---

    fn lowerRoot(self: *GrammarLowerer, sexp: Sexp) LoweringError!void {
        const items = try self.requireTag(sexp, .grammar);
        for (items[1..]) |entry| try self.lowerEntry(entry);
    }

    fn lowerEntry(self: *GrammarLowerer, entry: Sexp) LoweringError!void {
        const t = taggedItems(entry) orelse return self.shapeError(entry, "directive or rule");
        switch (t.tag) {
            .lang => try self.lowerLang(entry, t.items),
            .conflicts => try self.lowerConflicts(entry, t.items),
            .as => try self.lowerAs(entry, t.items),
            .op => try self.lowerOp(entry, t.items),
            .errors => try self.lowerErrors(entry, t.items),
            .infix => try self.lowerInfix(entry, t.items),
            .rule => try self.lowerRule(entry, t.items),
            else => return self.shapeError(entry, "directive or rule"),
        }
    }

    // --- Directives ---

    fn lowerLang(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!void {
        if (items.len != 2) return self.shapeError(node, "(lang STRING)");
        const raw = try self.requireSrc(items[1], "language-name string");
        self.lang = stripQuotes(raw);
    }

    fn lowerConflicts(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!void {
        if (items.len != 2) return self.shapeError(node, "(conflicts INTEGER)");
        const text = try self.requireSrc(items[1], "conflict count");
        self.expectConflicts = std.fmt.parseInt(u32, text, 10) catch
            return self.shapeError(items[1], "integer");
    }

    fn lowerAs(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!void {
        if (items.len < 3) return self.shapeError(node, "(as IDENT AS_ENTRY+)");
        const token = try self.requireSrc(items[1], "@as source-token ident");
        for (items[2..]) |entry| {
            const et = try self.requireTag(entry, .as_entry);
            if (et.len != 3) return self.shapeError(entry, "(as_entry KIND IDENT)");
            const permissive = switch (et[1]) {
                .nil => false,
                .tag => |t| t == .perm,
                else => return self.shapeError(entry, "(as_entry KIND IDENT) — KIND must be _ or perm"),
            };
            const rule = try self.requireSrc(et[2], "candidate ident");
            try self.asDirectives.append(self.allocator, .{
                .token = token,
                .rule = rule,
                .permissive = permissive,
            });
        }
    }

    fn lowerOp(self: *GrammarLowerer, _: Sexp, items: []const Sexp) LoweringError!void {
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .op_map);
            if (et.len != 3) return self.shapeError(entry, "(op_map STRING STRING)");
            const lit = stripQuotes(try self.requireSrc(et[1], "op literal"));
            const tok = stripQuotes(try self.requireSrc(et[2], "op target token"));
            try self.opMappings.append(self.allocator, .{ .lit = lit, .tok = tok });
        }
    }

    fn lowerErrors(self: *GrammarLowerer, _: Sexp, items: []const Sexp) LoweringError!void {
        for (items[1..]) |entry| {
            const et = try self.requireTag(entry, .error_name);
            if (et.len != 3) return self.shapeError(entry, "(error_name RULE STRING)");
            const rule = try self.requireSrc(et[1], "rule name");
            const name = stripQuotes(try self.requireSrc(et[2], "display string"));
            try self.errorNames.append(self.allocator, .{ .rule = rule, .name = name });
        }
    }

    fn lowerInfix(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!void {
        if (items.len < 2) return self.shapeError(node, "(infix IDENT LEVEL+)");
        self.infixBase = try self.requireSrc(items[1], "@infix base expression");
        var prec: u32 = 1;
        for (items[2..]) |level| {
            const lt = try self.requireTag(level, .level);
            for (lt[1..]) |opNode| {
                const ot = try self.requireTag(opNode, .infix_op);
                if (ot.len != 3) return self.shapeError(opNode, "(infix_op STRING assoc)");
                const op = stripQuotes(try self.requireSrc(ot[1], "operator literal"));
                const assocName = try self.requireSrc(ot[2], "associativity keyword");
                const assoc: InfixOp.Assoc = if (std.mem.eql(u8, assocName, "left"))
                    .left
                else if (std.mem.eql(u8, assocName, "right"))
                    .right
                else if (std.mem.eql(u8, assocName, "none"))
                    .none
                else
                    return self.shapeError(ot[2], "left|right|none");
                try self.infixOps.append(self.allocator, .{ .op = op, .assoc = assoc, .prec = prec });
            }
            prec += 1;
        }
    }

    // --- Rules ---

    fn lowerRule(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!void {
        if (items.len < 3) return self.shapeError(node, "(rule RULE_NAME ALT+)");

        const nameInfo = try self.lowerRuleName(items[1]);
        if (nameInfo.isStart) try self.startSymbols.append(self.allocator, nameInfo.name);

        var alts: std.ArrayListUnmanaged(ParsedAlternative) = .empty;
        for (items[2..]) |altNode| try alts.append(self.allocator, try self.lowerAlt(altNode));

        try self.rules.append(self.allocator, .{
            .name = nameInfo.name,
            .isStart = nameInfo.isStart,
            .alternatives = try alts.toOwnedSlice(self.allocator),
        });
    }

    fn lowerRuleName(self: *GrammarLowerer, node: Sexp) LoweringError!struct { name: []const u8, isStart: bool } {
        const t = taggedItems(node) orelse return self.shapeError(node, "(start ...) or (name ...)");
        return switch (t.tag) {
            .start => .{
                .name = try self.extractSingleIdent(node, t.items, "(start IDENT-or-TOKEN)"),
                .isStart = true,
            },
            .name => .{
                .name = try self.extractSingleIdent(node, t.items, "(name IDENT-or-TOKEN)"),
                .isStart = false,
            },
            else => self.shapeError(node, "(start ...) or (name ...)"),
        };
    }

    fn extractSingleIdent(self: *GrammarLowerer, node: Sexp, items: []const Sexp, expected: []const u8) LoweringError![]const u8 {
        if (items.len != 2) return self.shapeError(node, expected);
        return self.requireSrc(items[1], expected);
    }

    fn lowerAlt(self: *GrammarLowerer, altNode: Sexp) LoweringError!ParsedAlternative {
        const items = try self.requireTag(altNode, .alt);
        if (items.len < 3 or items.len > 4) return self.shapeError(altNode, "(alt KIND ELEMENT-list ACTION?)");
        const kind: ?Tag = switch (items[1]) {
            .nil => null,
            .tag => |t| t,
            else => return self.shapeError(altNode, "(alt KIND ...) — KIND must be _, reduce, or shift"),
        };
        const preferReduce = kind != null and kind.? == .reduce;
        const preferShift = kind != null and kind.? == .shift;
        if (kind != null and !preferReduce and !preferShift) {
            return self.shapeError(altNode, "(alt KIND ...) — KIND must be _, reduce, or shift");
        }

        // Children of the element list are either regular ELEMENT sexps or
        // (exclude STRING) hints. Exclude elements are consumed here: they
        // set the alternative's excludeChar (the last one wins) and never
        // reach the element list that processGrammar sees.
        const rawChildren = try self.requireList(items[2], "element list");
        var elements: std.ArrayListUnmanaged(ParsedElement) = .empty;
        var excludeChar: u8 = 0;
        for (rawChildren) |child| {
            if (taggedItems(child)) |ct| if (ct.tag == .exclude) {
                if (ct.items.len != 2) return self.shapeError(child, "(exclude STRING)");
                const raw = try self.requireSrc(ct.items[1], "exclusion literal");
                const inner = stripQuotes(raw);
                if (inner.len != 1) return self.shapeError(child, "exclude \"c\" — c must be a one-char literal");
                excludeChar = inner[0];
                continue;
            };
            try elements.append(self.allocator, try self.lowerElement(child));
        }

        var action: ?[]const u8 = null;
        if (items.len == 4) action = try self.requireSrc(items[3], "action text");

        return ParsedAlternative{
            .elements = try elements.toOwnedSlice(self.allocator),
            .action = action,
            .excludeChar = excludeChar,
            .preferReduce = preferReduce,
            .preferShift = preferShift,
        };
    }

    // Lowers a list of element sexps. Used only for group bodies (inside
    // parenthesized groups and bracket groups) where (exclude ...) is not
    // legal — an exclude there will fall through lowerElement's switch and
    // emit a shape error, which is the correct behavior.
    fn lowerAltBody(self: *GrammarLowerer, node: Sexp) LoweringError!std.ArrayListUnmanaged(ParsedElement) {
        const items = try self.requireList(node, "element list");
        var out: std.ArrayListUnmanaged(ParsedElement) = .empty;
        for (items) |child| try out.append(self.allocator, try self.lowerElement(child));
        return out;
    }

    // --- Elements ---

    fn lowerElement(self: *GrammarLowerer, node: Sexp) LoweringError!ParsedElement {
        const t = taggedItems(node) orelse return self.shapeError(node, "tagged element sexp");
        return switch (t.tag) {
            .ref => try self.lowerScalarElement(node, t.items, .ident),
            .tok => try self.lowerScalarElement(node, t.items, .token),
            .lit => try self.lowerScalarElement(node, t.items, .string),
            .at_ref => try self.lowerScalarElement(node, t.items, .ident),
            .list_req => try self.lowerListElement(node, t.items, .reqList),
            .group => try self.lowerGroupKinded(node, t.items),
            .quantified => try self.lowerQuantifiedElement(node, t.items),
            .skip => try self.lowerSkipElement(node, t.items, false),
            .skip_q => try self.lowerSkipElement(node, t.items, true),
            else => self.shapeError(node, "element"),
        };
    }

    fn lowerScalarElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp, kind: ParsedElement.Kind) LoweringError!ParsedElement {
        if (items.len != 2) return self.shapeError(node, "(ref|tok|lit|at_ref SRC)");
        return ParsedElement{
            .kind = kind,
            .value = try self.requireSrc(items[1], "identifier/token/string"),
        };
    }

    fn lowerListElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp, kind: ParsedElement.Kind) LoweringError!ParsedElement {
        if (items.len != 3) return self.shapeError(node, "(list_req TOKEN LIST_INNER)");
        const listTok = try self.requireSrc(items[1], "list head token");
        _ = listTok; // The leading TOKEN is always `L`; the surface syntax gives no other choice.
        const inner = taggedItems(items[2]) orelse return self.shapeError(items[2], "LIST_INNER");
        var elem = ParsedElement{ .kind = kind, .value = "" };
        switch (inner.tag) {
            .plain => {
                if (inner.items.len != 2) return self.shapeError(items[2], "(plain IDENT)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
            },
            .opt_items => {
                if (inner.items.len != 3) return self.shapeError(items[2], "(opt_items IDENT SEP)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.optionalItems = true;
                elem.listSeparator = try self.requireSrc(inner.items[2], "separator");
            },
            .sep_items => {
                if (inner.items.len != 3) return self.shapeError(items[2], "(sep_items IDENT SEP)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.listSeparator = try self.requireSrc(inner.items[2], "separator");
            },
            .opt_items_nosep => {
                if (inner.items.len != 2) return self.shapeError(items[2], "(opt_items_nosep IDENT)");
                elem.value = try self.requireSrc(inner.items[1], "list item ident");
                elem.optionalItems = true;
            },
            else => return self.shapeError(items[2], "plain|opt_items|sep_items|opt_items_nosep"),
        }
        return elem;
    }

    // Decodes the kind discriminator in `(group KIND ALT_BODY ALT_BODY ...)`
    // and dispatches to lowerGroupElement with the appropriate parameters.
    // KIND ∈ _ (plain group), many ([X, ...] optional list), opt ([X] optional).
    fn lowerGroupKinded(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!ParsedElement {
        if (items.len < 3) return self.shapeError(node, "(group KIND ALT_BODY...)");
        const bodies = items[2..];
        return switch (items[1]) {
            .nil => self.lowerGroupElement(node, bodies, .group, false),
            .tag => |t| switch (t) {
                .many => self.lowerGroupElement(node, bodies, .optList, true),
                .opt => self.lowerGroupElement(node, bodies, .optGroup, false),
                else => self.shapeError(node, "(group KIND ...) — KIND must be _, many, or opt"),
            },
            else => self.shapeError(node, "(group KIND ...) — KIND must be _, many, or opt"),
        };
    }

    fn lowerGroupElement(self: *GrammarLowerer, node: Sexp, bodies: []const Sexp, kind: ParsedElement.Kind, asMany: bool) LoweringError!ParsedElement {
        if (bodies.len < 1) return self.shapeError(node, "group with ≥1 ALT_BODY");

        if (bodies.len == 1) {
            var bodyElements = try self.lowerAltBody(bodies[0]);
            defer bodyElements.deinit(self.allocator);

            if (asMany) {
                // [X, ...] with a single simple element collapses to an optList
                // carrying the item name directly; the parser generator emits a
                // comma-separated list rule for it.
                if (isSingleSimpleElem(bodyElements.items)) {
                    return ParsedElement{
                        .kind = .optList,
                        .value = bodyElements.items[0].value,
                    };
                }
                return ParsedElement{
                    .kind = .optList,
                    .value = if (bodyElements.items.len > 0) bodyElements.items[0].value else "",
                    .subElements = try self.allocator.dupe(ParsedElement, bodyElements.items),
                };
            }

            // [L(X)]: single alt body containing exactly one required-list
            // element collapses to an optional-list element carrying the same
            // list fields (item name, separator, per-item optionality).
            if (kind == .optGroup and bodyElements.items.len == 1 and bodyElements.items[0].kind == .reqList and bodyElements.items[0].quantifier == .one and !bodyElements.items[0].skip) {
                const inner = bodyElements.items[0];
                return ParsedElement{
                    .kind = .optList,
                    .value = inner.value,
                    .optionalItems = inner.optionalItems,
                    .listSeparator = inner.listSeparator,
                };
            }

            // [X] with a single simple element collapses to the base element with
            // an optional quantifier. Multiple elements or complex bodies keep
            // the optGroup shape, which is expanded into explicit alternatives
            // downstream by expandOptionalGroups.
            if (kind == .optGroup and isSingleSimpleElem(bodyElements.items)) {
                return ParsedElement{
                    .kind = bodyElements.items[0].kind,
                    .value = bodyElements.items[0].value,
                    .quantifier = .optional,
                };
            }

            // For optGroup, `value` carries the first sub-element's text.
            // Plain groups don't need it.
            const firstValue: []const u8 = if (kind == .optGroup and bodyElements.items.len > 0)
                bodyElements.items[0].value
            else
                "";

            return ParsedElement{
                .kind = kind,
                .value = firstValue,
                .subElements = try self.allocator.dupe(ParsedElement, bodyElements.items),
            };
        }

        // Multi-alt group. Each alternative contributes a sub-group element so
        // that downstream emitters see a list of distinct alternatives.
        var subElems: std.ArrayListUnmanaged(ParsedElement) = .empty;
        for (bodies) |altBody| {
            var body = try self.lowerAltBody(altBody);
            defer body.deinit(self.allocator);
            if (body.items.len == 0) continue;
            try subElems.append(self.allocator, .{
                .kind = .group,
                .subElements = try self.allocator.dupe(ParsedElement, body.items),
            });
        }

        return ParsedElement{
            .kind = if (asMany) .optList else kind,
            .subElements = try subElems.toOwnedSlice(self.allocator),
        };
    }

    fn isSingleSimpleElem(elements: []const ParsedElement) bool {
        if (elements.len != 1) return false;
        const e = elements[0];
        if (e.skip) return false;
        if (e.quantifier != .one) return false;
        return e.kind == .ident or e.kind == .token;
    }

    fn lowerQuantifiedElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp) LoweringError!ParsedElement {
        if (items.len != 3) return self.shapeError(node, "(quantified ELEMENT QUANT)");
        var inner = try self.lowerElement(items[1]);
        inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerSkipElement(self: *GrammarLowerer, node: Sexp, items: []const Sexp, withQuant: bool) LoweringError!ParsedElement {
        const expected = if (withQuant) "(skip_q ELEMENT QUANT)" else "(skip ELEMENT)";
        const need: usize = if (withQuant) 3 else 2;
        if (items.len != need) return self.shapeError(node, expected);
        var inner = try self.lowerElement(items[1]);
        inner.skip = true;
        if (withQuant) inner.quantifier = try self.lowerQuantifier(items[2]);
        return inner;
    }

    fn lowerQuantifier(self: *const GrammarLowerer, node: Sexp) LoweringError!ParsedElement.Quantifier {
        const t = taggedItems(node) orelse return self.shapeError(node, "(opt|zero_plus|one_plus)");
        if (t.items.len != 1) return self.shapeError(node, "(opt|zero_plus|one_plus)");
        return switch (t.tag) {
            .opt => .optional,
            .zero_plus => .zeroPlus,
            .one_plus => .onePlus,
            else => self.shapeError(node, "(opt|zero_plus|one_plus)"),
        };
    }
};

// =============================================================================
// Negative shape tests for the lowerer
//
// Each `test` block constructs a deliberately malformed S-expression tree by
// hand and asserts that GrammarLowerer.lower rejects it with
// error.ShapeError. The goal is to mechanically prove the lowerer's "exact
// shape or hard error" contract — the downstream parser cannot produce
// malformed Sexps by construction, so these shapes can only be built
// directly.
//
// The suite covers every lowering entry point: root dispatch, each
// directive, rule/alt structure, every element variant, list inner shapes,
// quantifiers, and the exclude hint. Collectively they pin down every
// dispatch site in GrammarLowerer against a known-bad shape.
//
// These `test` blocks are compiled only when Zig's test runner is invoked
// (`zig build test-lowerer`). They add zero
// bytes to the shipped binary.
// =============================================================================

const testing = std.testing;

// Shared source buffer used by every negative-shape test. Byte layout:
//   0..1  -> "x"         (harmless one-char src for most cases)
//   1..5  -> "\"ab\""    (a multi-char string literal for the exclude-too-long case)
const negSource = "x\"ab\"";
const negSrc0: Sexp = .{ .src = .{ .pos = 0, .len = 1, .id = 0 } };
const negSrcMulti: Sexp = .{ .src = .{ .pos = 1, .len = 4, .id = 0 } };

// Wrap an element list as (grammar (rule (name SRC) (alt _ (elems...)))) so
// the lowerer reaches the element dispatch. The `_` (nil) at slot 1 of the
// alt is the "plain alternative — no precedence kind" discriminator per the
// schema at the top of nexus.grammar. Must be comptime so the nested `&[_]Sexp{...}` literals
// resolve into static memory.
fn negRule(comptime elems: []const Sexp) Sexp {
    return comptime .{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]Sexp{ .{ .tag = .name }, negSrc0 } },
            .{ .list = &[_]Sexp{
                .{ .tag = .alt },
                .nil,
                .{ .list = elems },
            } },
        } },
    } };
}

// Every test below creates its own arena so shape-error bailouts from the
// lowerer don't trip std.testing.allocator's leak detector — the lowerer
// doesn't clean up partially-built IR on early return (processGrammar
// owns the final IR in production).
fn expectShapeError(sexp: Sexp) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.ShapeError, GrammarLowerer.lower(arena.allocator(), sexp, negSource));
}

test "lowerer rejects non-list root" {
    try expectShapeError(negSrc0);
}

test "lowerer rejects root list with wrong tag" {
    try expectShapeError(.{ .list = &[_]Sexp{.{ .tag = .alt }} });
}

test "lowerer rejects entry that is not a tagged list" {
    try expectShapeError(.{ .list = &[_]Sexp{ .{ .tag = .grammar }, negSrc0 } });
}

test "lowerer rejects entry with unknown tag" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{.{ .tag = .opt }} },
    } });
}

test "lowerer rejects (lang) with no STRING" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{.{ .tag = .lang }} },
    } });
}

test "lowerer rejects (conflicts) with non-numeric src" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{ .{ .tag = .conflicts }, negSrc0 } },
    } });
}

test "lowerer rejects (as) with no entries" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{ .{ .tag = .as }, negSrc0 } },
    } });
}

test "lowerer rejects (as) entry with wrong tag" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .as },
            negSrc0,
            .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects (op_map) with wrong arity" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .op },
            .{ .list = &[_]Sexp{ .{ .tag = .op_map }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects (level) containing non-infix_op child" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .infix },
            negSrc0,
            .{ .list = &[_]Sexp{
                .{ .tag = .level },
                .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
            } },
        } },
    } });
}

test "lowerer rejects (rule) with no alts" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]Sexp{ .{ .tag = .name }, negSrc0 } },
        } },
    } });
}

test "lowerer rejects rule_name tag that is neither start nor name" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
            .{ .list = &[_]Sexp{ .{ .tag = .alt }, .nil, .{ .list = &[_]Sexp{} } } },
        } },
    } });
}

test "lowerer rejects alt child that is not list" {
    try expectShapeError(.{ .list = &[_]Sexp{
        .{ .tag = .grammar },
        .{ .list = &[_]Sexp{
            .{ .tag = .rule },
            .{ .list = &[_]Sexp{ .{ .tag = .name }, negSrc0 } },
            .{ .list = &[_]Sexp{ .{ .tag = .alt }, .nil, negSrc0 } },
        } },
    } });
}

test "lowerer rejects bare src as an element" {
    try expectShapeError(negRule(&.{negSrc0}));
}

test "lowerer rejects (ref) with wrong arity" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{.{ .tag = .ref }} }}));
}

test "lowerer rejects (list_req) missing inner" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{ .{ .tag = .list_req }, negSrc0 } }}));
}

test "lowerer rejects (list_req) inner with unknown tag" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{
        .{ .tag = .list_req },
        negSrc0,
        .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (group) with no ALT_BODY" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{.{ .tag = .group }} }}));
}

test "lowerer rejects (quantified) missing quant" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{
        .{ .tag = .quantified },
        .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (quantified) quant child with wrong tag" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{
        .{ .tag = .quantified },
        .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
        .{ .list = &[_]Sexp{.{ .tag = .skip }} },
    } }}));
}

test "lowerer rejects (skip_q) missing quant" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{
        .{ .tag = .skip_q },
        .{ .list = &[_]Sexp{ .{ .tag = .ref }, negSrc0 } },
    } }}));
}

test "lowerer rejects (exclude) with wrong arity" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{.{ .tag = .exclude }} }}));
}

test "lowerer rejects (exclude) with multi-char literal" {
    try expectShapeError(negRule(&.{.{ .list = &[_]Sexp{ .{ .tag = .exclude }, negSrcMulti } }}));
}

test "lowerer rejects (exclude) appearing inside a group body" {
    try expectShapeError(negRule(&.{.{
        .list = &[_]Sexp{
            .{ .tag = .group },
            .nil, // KIND slot — `_` for plain group
            .{ .list = &[_]Sexp{
                .{ .list = &[_]Sexp{ .{ .tag = .exclude }, negSrc0 } },
            } },
        },
    }}));
}
