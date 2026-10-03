//! Grammar validation on the expanded grammar, before the LR stages.
//!
//!   - validateSymbols: every nonterminal needs a rule and every uppercase
//!     terminal a lexer token.
//!   - checkReachable: a start symbol reaches every rule.

const std = @import("std");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedElement = grammar.ParsedElement;
const Grammar = grammar.Grammar;
const LexerSpec = grammar.LexerSpec;

/// Reports every rule no start symbol reaches, located at the rule, and an
/// @infix table no rule uses; returns the error count. The walk runs on
/// the expanded grammar, where @infix and the rules synthesized for
/// groups, lists and quantifiers are real edges. An alias (`name = X`,
/// which expands to no rule of its own) is reached when a reached rule
/// names it.
pub fn checkReachable(allocator: Allocator, g: *const Grammar, ir: *const GrammarIR, path: []const u8) Allocator.Error!u32 {
    const reached = try allocator.alloc(bool, g.symbols.items.len);
    @memset(reached, false);
    var work: std.ArrayList(u16) = .empty;
    for (g.startSymbols.items) |s| try reach(allocator, reached, &work, s);
    while (work.pop()) |s| {
        for (g.symbols.items[s].rules.items) |r| for (g.rules.items[r].rhs) |x| try reach(allocator, reached, &work, x);
    }

    var walk: Walk = .{ .g = g, .reached = reached };
    var grew = true;
    while (grew) {
        grew = false;
        for (ir.rules) |rule| {
            if (!walk.isReached(rule.name)) continue;
            for (rule.alternatives) |alt| grew = try walk.name(allocator, alt.elements) or grew;
        }
        // The @infix chain names its base, which may be an alias.
        if (ir.infix) |infix| if (walk.isReached("infix")) {
            grew = !(try walk.named.getOrPut(allocator, infix.baseRule)).found_existing or grew;
        };
    }

    var errors: u32 = 0;
    for (ir.rules, 0..) |rule, i| {
        if (walk.isReached(rule.name)) continue;
        // One report per name (a rule may be written in several blocks).
        if (for (ir.rules[0..i]) |r| {
            if (std.mem.eql(u8, r.name, rule.name)) break true;
        } else false) continue;
        diag.errLine(path, rule.line, rule.col, "rule '{s}' is unreachable: no start symbol reaches it", .{rule.name});
        errors += 1;
    }
    if (ir.infix) |infix| if (!walk.isReached("infix")) {
        diag.errLine(path, infix.line, infix.col, "@infix is unused: no rule names `@infix`", .{});
        errors += 1;
    };
    return errors;
}

fn reach(allocator: Allocator, reached: []bool, work: *std.ArrayList(u16), sym: u16) Allocator.Error!void {
    if (reached[sym]) return;
    reached[sym] = true;
    try work.append(allocator, sym);
}

/// The names reached rules use, for the aliases among them.
const Walk = struct {
    g: *const Grammar,
    reached: []const bool,
    named: std.StringHashMapUnmanaged(void) = .empty,

    fn isReached(self: *const Walk, rule: []const u8) bool {
        if (self.g.aliases.contains(rule)) return self.named.contains(rule);
        const id = self.g.symbolMap.get(rule) orelse return false;
        return self.reached[id];
    }

    /// Adds the names `elements` use; whether any is new.
    fn name(self: *Walk, allocator: Allocator, elements: []const ParsedElement) Allocator.Error!bool {
        var grew = false;
        for (elements) |e| {
            switch (e.kind) {
                .ident, .token, .reqList, .optList => grew = !(try self.named.getOrPut(allocator, e.value)).found_existing or grew,
                else => {},
            }
            if (e.listSeparator) |sep| grew = !(try self.named.getOrPut(allocator, sep)).found_existing or grew;
            grew = try self.name(allocator, e.subElements) or grew;
            for (e.choices) |c| grew = try self.name(allocator, c) or grew;
        }
        return grew;
    }
};

const Loc = struct { line: u32, col: u32 };

/// Where the symbol `name` is first written in a rule, else the first
/// alternative that uses symbol `sym` (a synthesized name).
fn firstUse(g: *const Grammar, ir: *const GrammarIR, sym: u16, name: []const u8) Loc {
    for (ir.rules) |rule| for (rule.alternatives) |alt| {
        if (usedIn(alt.elements, name)) |at| return at;
    };
    for (g.rules.items) |rule| {
        if (std.mem.findScalar(u16, rule.rhs, sym) != null and rule.line > 0) return .{ .line = rule.line, .col = rule.col };
    }
    return .{ .line = 1, .col = 1 };
}

fn usedIn(elements: []const ParsedElement, name: []const u8) ?Loc {
    for (elements) |e| {
        const names = switch (e.kind) {
            .ident, .token, .reqList, .optList => std.mem.eql(u8, e.value, name),
            else => false,
        } or (e.listSeparator != null and std.mem.eql(u8, e.listSeparator.?, name));
        if (names) return .{ .line = e.line, .col = e.col };
        if (usedIn(e.subElements, name)) |at| return at;
        for (e.choices) |c| if (usedIn(c, name)) |at| return at;
    }
    return null;
}

/// Validate that all referenced symbols are defined, reporting each
/// undefined one where it is first used. Returns the error count.
pub fn validateSymbols(g: *const Grammar, ir: *const GrammarIR, lexerSpec: *const LexerSpec, path: []const u8) u32 {
    var errors: u32 = 0;

    for (g.symbols.items, 0..) |sym, symId| {
        // The accept symbols and literals need no definition.
        if (sym.name.len == 0) continue;
        if (sym.name[0] == '$' or sym.name[0] == '"') continue;

        // Check nonterminals have at least one rule
        if (sym.kind == .nonterminal) {
            if (sym.rules.items.len == 0) {
                const at = firstUse(g, ir, @intCast(symId), sym.name);
                diag.errLine(path, at.line, at.col, "undefined rule '{s}'", .{sym.name});
                errors += 1;
            }
        }
        // Check uppercase identifiers exist in lexer tokens (case-insensitive)
        else if (sym.kind == .terminal and sym.name[0] >= 'A' and sym.name[0] <= 'Z') {
            // The marker of a start symbol (`X!`, added by expand).
            if (sym.name[sym.name.len - 1] == '!') continue;
            // An @as group `g` promotes its words to the terminal `G`.
            var isAsKeyword = false;
            for (g.asDirectives) |directive| {
                if (std.ascii.eqlIgnoreCase(directive.rule, sym.name)) {
                    isAsKeyword = true;
                    break;
                }
            }
            if (isAsKeyword) continue;

            // When @lang is set, keyword terminals are resolved by the
            // lang module's keyword matcher at compile time. Trust the
            // Zig compiler to catch mismatches.
            if (g.lang != null and g.asDirectives.len > 0) continue;

            var found = false;

            // Check tokens block (case-insensitive since lexer uses lowercase)
            for (lexerSpec.tokens.items) |tok| {
                if (std.ascii.eqlIgnoreCase(tok, sym.name)) {
                    found = true;
                    break;
                }
            }

            // Check lexer rules (case-insensitive)
            if (!found) {
                for (lexerSpec.rules.items) |rule| {
                    if (std.ascii.eqlIgnoreCase(rule.token, sym.name)) {
                        found = true;
                        break;
                    }
                }
            }

            if (!found) {
                const at = firstUse(g, ir, @intCast(symId), sym.name);
                diag.errLine(path, at.line, at.col, "undefined token '{s}'", .{sym.name});
                errors += 1;
            }
        }
    }

    return errors;
}
