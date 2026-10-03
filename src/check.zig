//! Grammar validation on the expanded grammar, before the LR stages.
//!
//!   - validateSymbols: every nonterminal needs a rule and every uppercase
//!     terminal a lexer token.
//!   - checkReachable: a start symbol reaches every rule.
//!   - bindTokens: the terminal each lexer token reaches the parser as.
//!   - resolveHints: the terminal each `X "c"` hint names.

const std = @import("std");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedElement = grammar.ParsedElement;
const Grammar = grammar.Grammar;
const LexerSpec = grammar.LexerSpec;
const conflicts = @import("lr/conflicts.zig");

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

/// Binds each lexer token to the terminal it reaches the parser as
/// (`g.tokenMap`, the generated tokenToSymbol's cases in order); returns
/// the error count. A named terminal is the token of its name (unless
/// `@as` promotes it); a string literal is its `@op` token, else the token
/// of the lexer rule whose pattern is exactly that text. A token names one
/// terminal: a literal no lexer token produces, and two terminals for one
/// token (`"+"` and PLUS), are errors (either would leave alternatives no
/// input can reach).
pub fn bindTokens(g: *Grammar, spec: *const LexerSpec, path: []const u8) Allocator.Error!u32 {
    const a = g.allocator;
    var map: std.ArrayList(Grammar.TokenBinding) = .empty;
    var owner: std.StringHashMapUnmanaged(u16) = .empty;
    const promotable = g.promotable();
    if (promotable) |tok| try owner.put(a, tok, g.errorId);
    var errors: u32 = 0;
    // Literals already reported as sharing a token.
    var shared: std.AutoHashMapUnmanaged(u16, void) = .empty;

    for (g.symbols.items) |sym| {
        if (sym.kind != .terminal or sym.name.len == 0) continue;
        if (sym.name[0] == '$' or sym.name[0] == '"') continue;
        if (std.mem.endsWith(u8, sym.name, "!")) continue;
        if (std.mem.eql(u8, sym.name, "error")) continue;

        const lowerName = try std.ascii.allocLowerString(a, sym.name);
        if (promotable) |tok| if (std.mem.eql(u8, lowerName, tok)) continue;
        if (g.isPromotedKeyword(spec, sym.name)) continue;

        // Only names that can be TokenCat fields
        var valid = lowerName[0] >= 'a' and lowerName[0] <= 'z';
        for (lowerName) |ch| {
            if (!((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_')) valid = false;
        }
        if (valid and !owner.contains(lowerName)) {
            try map.append(a, .{ .cat = lowerName, .sym = sym.id });
            try owner.put(a, lowerName, sym.id);
        }
    }

    // String literals: `@op` mappings first, then one-byte literals, then
    // longer ones (the order of the generated switch).
    for (0..3) |phase| for (g.symbols.items) |sym| {
        if (sym.kind != .terminal or sym.name.len < 3 or sym.name[0] != '"') continue;
        const raw = sym.name[1 .. sym.name.len - 1];
        const literal = try grammar.decode(a, raw);
        const cat: ?[]const u8 = switch (phase) {
            0 => for (g.opMappings) |m| {
                if (std.mem.eql(u8, literal, m.lit)) break m.tok;
            } else null,
            1 => if (literal.len == 1) grammar.findTokenForLiteral(spec, raw) else null,
            else => if (literal.len > 1) grammar.findTokenForLiteral(spec, raw) else null,
        };
        const c = cat orelse {
            const mapped = for (map.items) |m| {
                if (m.sym == sym.id) break true;
            } else false;
            if (phase == 2 and !mapped and !shared.contains(sym.id)) {
                errAtUse(g, path, sym.id, "the literal {s} is no token: no lexer rule's pattern is exactly that text (and no @op maps it)", .{sym.name});
                errors += 1;
            }
            continue;
        };
        if (owner.get(c)) |other| {
            if (other == sym.id) continue;
            const label = if (other == g.errorId) promotable orelse "error" else g.symbols.items[other].name;
            errAtUse(g, path, sym.id, "{s} and {s} are the same token ({s}); write one of them", .{ sym.name, label, c });
            try shared.put(a, sym.id, {});
            errors += 1;
            continue;
        }
        try map.append(a, .{ .cat = c, .sym = sym.id });
        try owner.put(a, c, sym.id);
    };
    g.tokenMap = try map.toOwnedSlice(a);
    return errors;
}

/// A generation error at the first alternative that uses symbol `sym`.
fn errAtUse(g: *const Grammar, path: []const u8, sym: u16, comptime fmt: []const u8, args: anytype) void {
    for (g.rules.items) |rule| {
        if (rule.line > 0 and std.mem.findScalar(u16, rule.rhs, sym) != null) return diag.errLine(path, rule.line, rule.col, fmt, args);
    }
    diag.errLine(path, 1, 1, fmt, args);
}

/// Resolves every `X "c"` hint to the terminal it names
/// (`Rule.hintTerminals`), from bindTokens' map; returns the error count.
/// The hint names the terminal a literal "c" in a rule would be:
///   1. the literal "c" itself, when the parser grammar writes it;
///   2. else the terminal of the token "c" stands for. The candidates are
///      the token `@op` maps "c" to and the token of every lexer rule
///      whose pattern is exactly "c" (in any state, under any guard); the
///      parser grammar must use exactly one of them, and write it by name.
/// Each failure, and two hints of one alternative naming one terminal, is
/// reported once, at the alternative.
pub fn resolveHints(g: *Grammar, spec: *const LexerSpec, path: []const u8) Allocator.Error!u32 {
    const a = g.allocator;
    var errors: u32 = 0;
    for (g.rules.items, 0..) |*rule, r| {
        if (rule.excludeChars.len == 0) continue;
        // The rules expanded from one alternative share its hints.
        const done = for (g.rules.items[0..r]) |*o| {
            if (o.lhs == rule.lhs and o.line == rule.line and o.col == rule.col and o.excludeChars.len > 0) break o;
        } else null;
        if (done) |o| {
            rule.hintTerminals = o.hintTerminals;
            continue;
        }
        const terminals = try a.alloc(u16, rule.excludeChars.len);
        var ok = true;
        for (rule.excludeChars, 0..) |c, i| {
            const t = try resolveHint(g, spec, path, @intCast(r), c) orelse {
                ok = false;
                errors += 1;
                continue;
            };
            terminals[i] = t;
            for (rule.excludeChars[0..i], terminals[0..i]) |pc, pt| {
                if (pt != t) continue;
                const at = conflicts.ruleLoc(g, @intCast(r));
                diag.errLine(path, at.line, at.col, "X {s} on {s} names {s}, as X {s} does; write one of them", .{
                    try hintText(a, c), try ruleText(a, g, @intCast(r)), g.symbols.items[t].name, try hintText(a, pc),
                });
                ok = false;
                errors += 1;
                break;
            }
        }
        if (ok) rule.hintTerminals = terminals;
    }
    return errors;
}

/// The terminal hint `X "c"` of rule `r` names (see resolveHints), or null
/// after reporting why it names none.
fn resolveHint(g: *const Grammar, spec: *const LexerSpec, path: []const u8, r: u16, c: u8) Allocator.Error!?u16 {
    const a = g.allocator;
    for (g.symbols.items) |sym| {
        if (sym.kind == .terminal and grammar.oneByteLiteral(sym.name) == c) return sym.id;
    }

    var tokens: std.ArrayList([]const u8) = .empty;
    for (g.opMappings) |m| {
        if (m.lit.len == 1 and m.lit[0] == c) try tokens.append(a, m.tok);
    }
    for (spec.rules.items) |*lr| {
        const text = grammar.ruleLiteral(lr) orelse continue;
        if (text.len != 1 or text[0] != c) continue;
        const seen = for (tokens.items) |t| {
            if (std.mem.eql(u8, t, lr.token)) break true;
        } else false;
        if (!seen) try tokens.append(a, lr.token);
    }

    var terminals: std.ArrayList(u16) = .empty;
    var promoted: ?[]const u8 = null;
    for (tokens.items) |t| {
        if (g.promotable()) |p| if (std.mem.eql(u8, p, t)) {
            promoted = t;
        };
        const sym = g.terminalOf(t) orelse continue;
        if (std.mem.findScalar(u16, terminals.items, sym) == null) try terminals.append(a, sym);
    }

    const at = conflicts.ruleLoc(g, r);
    const hint = try hintText(a, c);
    const rule = try ruleText(a, g, r);
    if (tokens.items.len == 0) {
        diag.errLine(path, at.line, at.col, "X {s} on {s} names no token: no lexer rule's pattern is exactly that text (and no @op maps it)", .{ hint, rule });
    } else if (promoted) |t| {
        diag.errLine(path, at.line, at.col, "X {s} on {s} names {s}, the token @as promotes, whose terminal depends on the parser state", .{ hint, rule, t });
    } else if (terminals.items.len == 0) {
        diag.errLine(path, at.line, at.col, "X {s} on {s} names no terminal: the parser grammar uses no token the lexer gives that text ({s})", .{ hint, rule, try std.mem.join(a, ", ", tokens.items) });
    } else if (terminals.items.len > 1) {
        var names: std.ArrayList([]const u8) = .empty;
        for (terminals.items) |t| try names.append(a, g.symbols.items[t].name);
        diag.errLine(path, at.line, at.col, "X {s} on {s} is ambiguous: lexer rules make that text {s} (in different states or under different guards), and a hint names one terminal", .{ hint, rule, try std.mem.join(a, " or ", names.items) });
    } else {
        const sym = terminals.items[0];
        const name = g.symbols.items[sym].name;
        if (name[0] != '"') return sym;
        diag.errLine(path, at.line, at.col, "X {s} on {s} names the terminal {s}: a hint names a literal terminal by that literal", .{ hint, rule, name });
    }
    return null;
}

/// Rule `r` as diagnostics write it (conflicts.ruleText).
fn ruleText(a: Allocator, g: *const Grammar, r: u16) Allocator.Error![]const u8 {
    return conflicts.ruleText(a, g, r) catch return error.OutOfMemory;
}

/// A hint's character as the grammar writes it (conflicts.writeHintChar).
fn hintText(a: Allocator, c: u8) Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    conflicts.writeHintChar(&out.writer, c) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
