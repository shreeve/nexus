//! `nexus check`: lint the lowered grammar IR (undefined rule references,
//! unreachable rules) without generating anything.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedElement = grammar.ParsedElement;

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
                std.debug.print("  warning: unreachable rule '{s}'\n", .{rule.name});
                warnings += 1;
            }
        }
    }

    if (errors > 0 or warnings > 0) {
        std.debug.print("\n  {d} error(s), {d} warning(s)\n", .{ errors, warnings });
    } else {
        std.debug.print("  ✅ No issues found\n", .{});
    }

    return errors;
}

fn checkUndefinedRefs(elements: []const ParsedElement, ruleName: []const u8, ruleNames: *std.StringHashMap(void), errors: *u32) void {
    for (elements) |elem| {
        if (elem.kind == .ident and elem.value.len > 0 and !ruleNames.contains(elem.value)) {
            std.debug.print("  error: undefined rule '{s}' referenced in '{s}'\n", .{ elem.value, ruleName });
            errors.* += 1;
        }
        if (elem.subElements.len > 0) checkUndefinedRefs(elem.subElements, ruleName, ruleNames, errors);
    }
}

fn markReachable(name: []const u8, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    if (reachable.contains(name)) return;
    reachable.put(name, {}) catch return;
    for (ir.rules) |rule| {
        if (!std.mem.eql(u8, rule.name, name)) continue;
        for (rule.alternatives) |alt| {
            for (alt.elements) |elem| {
                if (elem.kind == .ident or elem.kind == .reqList or elem.kind == .optList) {
                    markReachable(elem.value, ir, reachable);
                }
                markReachableElements(elem.subElements, ir, reachable);
            }
        }
    }
}

fn markReachableElements(elements: []const ParsedElement, ir: *const GrammarIR, reachable: *std.StringHashMap(void)) void {
    for (elements) |elem| {
        if (elem.kind == .ident or elem.kind == .reqList or elem.kind == .optList) {
            markReachable(elem.value, ir, reachable);
        }
        markReachableElements(elem.subElements, ir, reachable);
    }
}
