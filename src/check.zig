//! Grammar validation.
//!
//!   - validateSymbols: before generation, every nonterminal needs a rule and
//!     every uppercase terminal a lexer token (run on the desugared Grammar).
//!   - checkGrammar: `nexus check` lint of the lowered IR (unreachable
//!     rules); `check` then runs the whole pipeline without writing output.

const std = @import("std");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedElement = grammar.ParsedElement;
const Grammar = grammar.Grammar;
const LexerSpec = grammar.LexerSpec;

/// `nexus check` lint of the lowered IR: warns about rules no start symbol
/// reaches (located at the rule). Everything that is an error is reported
/// by the generation pipeline, which `check` also runs. Returns the number
/// of warnings.
pub fn checkGrammar(allocator: Allocator, ir: *const GrammarIR, path: []const u8) u32 {
    var warnings: u32 = 0;

    // Unreachable rules (skipped when @as directives are present because
    // keyword expansion creates reachability edges not visible in the IR)
    if (ir.startSymbols.len > 0 and ir.asDirectives.len == 0) {
        var reachable = std.StringHashMap(void).init(allocator);
        defer reachable.deinit();
        for (ir.startSymbols) |s| markReachable(s, ir, &reachable);
        if (ir.infix) |infix| markReachable(infix.baseRule, ir, &reachable);

        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();
        for (ir.rules) |rule| {
            if (seen.contains(rule.name)) continue;
            seen.put(rule.name, {}) catch {};
            if (!rule.isStart and !reachable.contains(rule.name)) {
                std.debug.print("{s}:{d}:{d}: warning: unreachable rule '{s}'\n", .{ path, @max(rule.line, 1), @max(rule.col, 1), rule.name });
                warnings += 1;
            }
        }
    }
    return warnings;
}

fn markReachable(name: []const u8, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    if (reachable.contains(name)) return;
    reachable.put(name, {}) catch return;
    for (ir.rules) |rule| {
        if (!std.mem.eql(u8, rule.name, name)) continue;
        for (rule.alternatives) |alt| markReachableElements(alt.elements, ir, reachable);
    }
}

fn markReachableElements(elements: []const ParsedElement, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    for (elements) |elem| {
        if (elem.kind == .ident or elem.kind == .reqList or elem.kind == .optList) {
            markReachable(elem.value, ir, reachable);
        }
        markReachableElements(elem.subElements, ir, reachable);
        for (elem.choices) |choice| markReachableElements(choice, ir, reachable);
    }
}

/// Where `sym` is first used: the location of the first rule whose
/// right-hand side has it.
fn firstUse(g: *const Grammar, sym: u16) struct { line: u32, col: u32 } {
    for (g.rules.items) |rule| {
        if (std.mem.indexOfScalar(u16, rule.rhs, sym) != null and rule.line > 0) return .{ .line = rule.line, .col = rule.col };
    }
    return .{ .line = 1, .col = 1 };
}

/// Validate that all referenced symbols are defined, reporting each
/// undefined one where it is first used. Returns the error count.
pub fn validateSymbols(g: *const Grammar, lexerSpec: *const LexerSpec, path: []const u8) u32 {
    var errors: u32 = 0;

    for (g.symbols.items, 0..) |sym, symId| {
        // The accept symbols and literals need no definition.
        if (sym.name.len == 0) continue;
        if (sym.name[0] == '$' or sym.name[0] == '"') continue;

        // Check nonterminals have at least one rule
        if (sym.kind == .nonterminal) {
            if (sym.rules.items.len == 0) {
                const at = firstUse(g, @intCast(symId));
                diag.errLine(path, at.line, at.col, "undefined rule '{s}'", .{sym.name});
                errors += 1;
            }
        }
        // Check uppercase identifiers exist in lexer tokens (case-insensitive)
        else if (sym.kind == .terminal and sym.name[0] >= 'A' and sym.name[0] <= 'Z') {
            // Skip if it's a start symbol marker (ends with !)
            if (sym.name[sym.name.len - 1] == '!') continue;

            // Skip if there's a matching lowercase nonterminal (@as keyword)
            // e.g., SET terminal has a matching 'set' nonterminal rule
            var isAsKeyword = false;
            for (g.symbols.items) |other| {
                if (other.kind == .nonterminal and std.ascii.eqlIgnoreCase(sym.name, other.name)) {
                    isAsKeyword = true;
                    break;
                }
            }
            if (isAsKeyword) continue;

            // Skip if it matches an @as directive rule name (e.g., SYSVAR from @as=[ident,sysvar])
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
                if (std.ascii.eqlIgnoreCase(tok.name, sym.name)) {
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
                const at = firstUse(g, @intCast(symId));
                diag.errLine(path, at.line, at.col, "undefined token '{s}'", .{sym.name});
                errors += 1;
            }
        }
    }

    return errors;
}
