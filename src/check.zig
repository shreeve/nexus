//! Grammar validation.
//!
//!   - validateSymbols: before generation, every nonterminal needs a rule and
//!     every uppercase terminal a lexer token (run on the desugared Grammar).
//!   - checkGrammar: `nexus check` lint of the lowered IR (undefined rule
//!     references, unreachable rules), without generating anything.

const std = @import("std");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedElement = grammar.ParsedElement;
const Grammar = grammar.Grammar;
const LexerSpec = grammar.LexerSpec;

pub fn checkGrammar(allocator: Allocator, ir: *const GrammarIR) u32 {
    var errors: u32 = 0;
    var warnings: u32 = 0;

    // Build known rule name set (allow duplicate entries — grammar DSL merges alternatives)
    var ruleNames = std.StringHashMap(void).init(allocator);
    defer ruleNames.deinit();
    for (ir.rules) |rule| {
        ruleNames.put(rule.name, {}) catch {};
    }
    if (ir.infix != null) ruleNames.put("infix", {}) catch {};

    // Check for undefined rule references
    for (ir.rules) |rule| {
        for (rule.alternatives) |alt| {
            checkUndefinedRefs(alt.elements, rule.name, &ruleNames, &errors);
        }
    }

    // Check for unreachable rules (skipped when @as directives are present
    // because keyword expansion creates reachability edges not visible in the IR)
    if (ir.startSymbols.len > 0 and ir.asDirectives.len == 0) {
        var reachable = std.StringHashMap(void).init(allocator);
        defer reachable.deinit();
        for (ir.startSymbols) |s| markReachable(s, ir, &reachable);
        if (ir.infix) |infix| markReachable(infix.baseRule, ir, &reachable);
        for (ir.asDirectives) |d| markReachable(d.rule, ir, &reachable);

        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();
        for (ir.rules) |rule| {
            if (seen.contains(rule.name)) continue;
            seen.put(rule.name, {}) catch {};
            if (!rule.isStart and !reachable.contains(rule.name)) {
                diag.warn("unreachable rule '{s}'", .{rule.name});
                warnings += 1;
            }
        }
    }

    if (errors > 0 or warnings > 0) {
        std.debug.print("\n  {d} error(s), {d} warning(s)\n", .{ errors, warnings });
    } else {
        diag.info("  No issues found", .{});
    }

    return errors;
}

fn checkUndefinedRefs(elements: []const ParsedElement, ruleName: []const u8, ruleNames: *std.StringHashMap(void), errors: *u32) void {
    for (elements) |elem| {
        const isRuleRef = elem.kind == .ident or
            ((elem.kind == .reqList or elem.kind == .optList) and elem.value.len > 0 and !(elem.value[0] >= 'A' and elem.value[0] <= 'Z'));
        if (isRuleRef and elem.value.len > 0 and !ruleNames.contains(elem.value)) {
            diag.err("undefined rule '{s}' referenced in '{s}'", .{ elem.value, ruleName });
            errors.* += 1;
        }
        if (elem.subElements.len > 0) checkUndefinedRefs(elem.subElements, ruleName, ruleNames, errors);
        for (elem.choices) |choice| checkUndefinedRefs(choice, ruleName, ruleNames, errors);
    }
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

/// Validate that all referenced symbols are defined.
/// Returns error count (0 = all valid).
pub fn validateSymbols(g: *const Grammar, lexerSpec: *const LexerSpec) u32 {
    var errors: u32 = 0;

    for (g.symbols.items) |sym| {
        // Skip special/generated symbols
        if (sym.name.len == 0) continue;
        if (sym.name[0] == '$' or sym.name[0] == '_' or sym.name[0] == '"') continue;

        // Check nonterminals have at least one rule
        if (sym.kind == .nonterminal) {
            if (sym.rules.items.len == 0) {
                diag.err("undefined rule '{s}'", .{sym.name});
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
                diag.err("undefined token '{s}'", .{sym.name});
                errors += 1;
            }
        }
    }

    return errors;
}
