//! Desugaring: turns the lowered GrammarIR into the plain BNF Grammar the LR
//! stages consume. Registers symbols and aliases, expands `[opt]` groups into
//! explicit alternatives (with stable action positions), and synthesizes
//! rules for `X?`, `X*`, `X+`, `L(X)`, `( ... )` groups, the `@infix`
//! precedence chain, and one augmented accept rule per start symbol.

const std = @import("std");
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const GrammarIR = grammar.GrammarIR;
const InfixDecl = grammar.InfixDecl;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const Symbol = grammar.Symbol;

/// Process parsed grammar into internal representation
pub fn processGrammar(g: *Grammar, ir: *const GrammarIR) !void {
    // Add special symbols
    g.acceptId = try g.addSymbol("$accept", .nonterminal);
    g.endId = try g.addSymbol("$end", .terminal);
    g.errorId = try g.addSymbol("error", .terminal);

    // Pre-pass: detect aliases
    for (ir.rules) |rule| {
        if (isAliasRule(rule)) |target| {
            try g.aliases.put(g.allocator, rule.name, target);
        }
    }

    // First pass: add all nonterminal names (skip aliases)
    for (ir.rules) |rule| {
        if (g.aliases.contains(rule.name)) continue;
        _ = try g.addSymbol(rule.name, .nonterminal);
    }

    // Second pass: process rules and add terminals
    // Expands consecutive optional groups to avoid LALR conflicts
    for (ir.rules) |rule| {
        if (g.aliases.contains(rule.name)) continue;

        const lhsId = g.getSymbol(rule.name).?;

        for (rule.alternatives) |alt| {
            // Expand consecutive opt_groups into explicit alternatives
            const expandedAlts = try expandOptionalGroups(g, alt);

            for (expandedAlts) |expandedAlt| {
                var rhs: std.ArrayListUnmanaged(u16) = .empty;

                for (expandedAlt.elements) |elem| {
                    const symId = try processElement(g, elem);
                    try rhs.append(g.allocator, symId);
                }

                const ruleId: u16 = @intCast(g.rules.items.len);
                try g.rules.append(g.allocator, .{
                    .id = ruleId,
                    .lhs = lhsId,
                    .rhs = try rhs.toOwnedSlice(g.allocator),
                    .action = expandedAlt.action,
                    .excludeChar = expandedAlt.excludeChar,
                    .preferReduce = expandedAlt.preferReduce,
                    .preferShift = expandedAlt.preferShift,
                });
                try g.symbols.items[lhsId].rules.append(g.allocator, ruleId);
            }
        }
    }

    // Use EOF as $end if defined
    if (g.symbolMap.get("EOF")) |eofId| {
        g.endId = eofId;
    }

    // Create augmented rules for EACH start symbol
    if (ir.startSymbols.len > 0) {
        for (ir.startSymbols) |startName| {
            if (g.getSymbol(startName)) |startId| {
                // Create marker terminal "X!"
                const markerName = try std.fmt.allocPrint(g.allocator, "{s}!", .{startName});
                const markerId = try g.addSymbol(markerName, .terminal);

                // Prepend marker to start rule
                for (g.rules.items) |*rule| {
                    if (rule.lhs == startId) {
                        var newRhs: std.ArrayListUnmanaged(u16) = .empty;
                        try newRhs.append(g.allocator, markerId);
                        for (rule.rhs) |sym| {
                            try newRhs.append(g.allocator, sym);
                        }
                        rule.rhs = try newRhs.toOwnedSlice(g.allocator);
                        rule.actionOffset = 1;
                        break;
                    }
                }

                // Create unique accept symbol
                const acceptName = try std.fmt.allocPrint(g.allocator, "$accept_{s}", .{startName});
                const uniqueAcceptId = try g.addSymbol(acceptName, .nonterminal);

                // Create augmented rule: $accept_X → startSymbol EOF
                var acceptRhs: std.ArrayListUnmanaged(u16) = .empty;
                try acceptRhs.append(g.allocator, startId);
                try acceptRhs.append(g.allocator, g.endId);

                const acceptRuleId: u16 = @intCast(g.rules.items.len);
                try g.rules.append(g.allocator, .{
                    .id = acceptRuleId,
                    .lhs = uniqueAcceptId,
                    .rhs = try acceptRhs.toOwnedSlice(g.allocator),
                    .action = null,
                });
                try g.symbols.items[uniqueAcceptId].rules.append(g.allocator, acceptRuleId);

                try g.startSymbols.append(g.allocator, startId);
                try g.acceptRules.append(g.allocator, acceptRuleId);
            }
        }
    } else if (g.rules.items.len > 0) {
        // Fallback: use first rule as start symbol
        const startSymbol = g.rules.items[0].lhs;

        var acceptRhs: std.ArrayListUnmanaged(u16) = .empty;
        try acceptRhs.append(g.allocator, startSymbol);
        try acceptRhs.append(g.allocator, g.endId);

        const acceptRuleId: u16 = @intCast(g.rules.items.len);
        try g.rules.append(g.allocator, .{
            .id = acceptRuleId,
            .lhs = g.acceptId,
            .rhs = try acceptRhs.toOwnedSlice(g.allocator),
            .action = null,
        });
        try g.symbols.items[g.acceptId].rules.append(g.allocator, acceptRuleId);

        try g.startSymbols.append(g.allocator, startSymbol);
        try g.acceptRules.append(g.allocator, acceptRuleId);
    }

    // Carry directives over from the IR
    g.asDirectives = ir.asDirectives;
    g.opMappings = ir.opMappings;
    g.lang = ir.lang;
    g.expectConflicts = ir.expectConflicts;

    // Generate infix expression chain if @infix was declared
    if (ir.infix) |infix| {
        if (infix.ops.len > 0) try generateInfixChain(g, infix);
    }
}

fn isAliasRule(rule: ParsedRule) ?[]const u8 {
    if (rule.alternatives.len != 1) return null;
    const alt = rule.alternatives[0];
    if (alt.elements.len != 1) return null;
    const elem = alt.elements[0];
    if (elem.kind != .token and elem.kind != .ident) return null;
    if (elem.quantifier != .one) return null;
    if (alt.action != null) return null;
    return elem.value;
}

/// Info about an optional group for expansion
const OptGroupInfo = struct {
    index: usize, // Index in elements array
    startPos: usize, // Starting position number (1-based)
    elemCount: usize, // Number of elements in this optional
};

/// Expand an alternative with consecutive opt_groups into multiple explicit alternatives.
/// This avoids LALR shift-reduce conflicts caused by epsilon productions.
/// Example: A [B C] [D E] → action  becomes:
///   A B C D E → adjusted_action
///   A B C     → adjusted_action
///   A D E     → adjusted_action
///   A         → adjusted_action
fn expandOptionalGroups(g: *Grammar, alt: ParsedAlternative) ![]ParsedAlternative {
    // Find all bracket-optionals ([X] or [A B C]) - these need expansion for stable positions.
    // Note: X? quantifiers (like SPACES?) don't need expansion - they're typically not in actions.
    var optGroups: std.ArrayListUnmanaged(OptGroupInfo) = .empty;
    defer optGroups.deinit(g.allocator);

    var pos: usize = 1;
    for (alt.elements, 0..) |elem, idx| {
        if (elem.kind == .optGroup) {
            // Multi-element optional: [A B C]
            try optGroups.append(g.allocator, .{
                .index = idx,
                .startPos = pos,
                .elemCount = elem.subElements.len,
            });
            pos += elem.subElements.len;
        } else if (elem.quantifier == .optional and (elem.kind == .ident or elem.kind == .optList)) {
            // Single-element bracket-optional: [X] parsed as X with .optional quantifier
            // Only include nonterminals (ident) and optional lists, not token quantifiers (SPACES?)
            try optGroups.append(g.allocator, .{
                .index = idx,
                .startPos = pos,
                .elemCount = 1,
            });
            pos += 1;
        } else {
            pos += 1;
        }
    }

    // If no opt_groups, no expansion needed
    // Note: Even single opt_groups need expansion for positionally stable output
    if (optGroups.items.len == 0) {
        var result: std.ArrayListUnmanaged(ParsedAlternative) = .empty;
        try result.append(g.allocator, alt);
        return result.toOwnedSlice(g.allocator);
    }

    // Generate 2^n combinations
    const n = optGroups.items.len;
    const combinations: usize = @as(usize, 1) << @intCast(n);

    var expanded: std.ArrayListUnmanaged(ParsedAlternative) = .empty;

    var combo: usize = 0;
    while (combo < combinations) : (combo += 1) {
        // Build elements for this combination
        var newParsedElements: std.ArrayListUnmanaged(ParsedElement) = .empty;

        for (alt.elements, 0..) |elem, idx| {
            // Check if this element is an optional (opt_group or single-element)
            const optIdx: ?usize = for (optGroups.items, 0..) |og, oi| {
                if (og.index == idx) break oi;
            } else null;

            if (optIdx) |oi| {
                // Check if this optional is present in this combination
                const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;
                if (present) {
                    if (elem.kind == .optGroup) {
                        // Multi-element optional: add sub-elements directly
                        for (elem.subElements) |sub| {
                            try newParsedElements.append(g.allocator, sub);
                        }
                    } else {
                        // Single-element optional: add element without optional quantifier
                        var nonOpt = elem;
                        nonOpt.quantifier = .one;
                        try newParsedElements.append(g.allocator, nonOpt);
                    }
                }
                // If not present, skip this optional entirely
            } else {
                try newParsedElements.append(g.allocator, elem);
            }
        }

        // Transform action with stable positions (use original elements for position mapping)
        const finalParsedElements = try newParsedElements.toOwnedSlice(g.allocator);
        var newAction: ?[]const u8 = alt.action;
        if (alt.action) |action| {
            newAction = try transformActionStable(g, action, alt.elements, optGroups.items, combo);
        }

        try expanded.append(g.allocator, .{
            .elements = finalParsedElements,
            .action = newAction,
            .excludeChar = alt.excludeChar,
            .preferReduce = alt.preferReduce,
        });
    }

    return expanded.toOwnedSlice(g.allocator);
}

// Position map: 255 means nil/absent, otherwise it's the actual RHS position
const nilPos: u8 = 255;

const maxPositions: usize = 64;

/// Parsed position reference from action template
const PosRef = struct {
    kind: enum { bare, keyed, spread },
    posNum: usize,
    endIdx: usize, // Index after this reference in the action string
};

/// Tracks position references for trailing-nil stripping
const PosRefInfo = struct { start: usize, isNil: bool };

/// Build logical-to-actual position map for stable positions.
/// Maps logical positions (1-based) to actual RHS positions, or NIL_POS for absent optionals.
fn buildPositionMap(
    altParsedElements: []const ParsedElement,
    optGroups: []const OptGroupInfo,
    combo: usize,
) [maxPositions]u8 {
    var posMap: [maxPositions]u8 = [_]u8{nilPos} ** maxPositions;
    var logicalPos: usize = 1;
    var actualPos: usize = 0;

    for (altParsedElements, 0..) |_, elemIdx| {
        // Find if this element is an opt_group
        const optIdx = for (optGroups, 0..) |og, oi| {
            if (og.index == elemIdx) break oi;
        } else null;

        if (optIdx) |oi| {
            const og = optGroups[oi];
            const present = (combo & (@as(usize, 1) << @intCast(oi))) != 0;

            for (0..og.elemCount) |_| {
                if (logicalPos < maxPositions) {
                    posMap[logicalPos] = if (present) @intCast(actualPos) else nilPos;
                }
                logicalPos += 1;
                if (present) actualPos += 1;
            }
        } else {
            if (logicalPos < maxPositions) {
                posMap[logicalPos] = @intCast(actualPos);
            }
            logicalPos += 1;
            actualPos += 1;
        }
    }

    return posMap;
}

/// Parse a position reference at the given index in the action string.
/// Returns null if no position reference found at this location.
fn parsePositionRef(action: []const u8, start: usize) ?PosRef {
    if (start >= action.len) return null;

    // key:N (key prefix is for documentation, stripped from output)
    if (action[start] >= 'a' and action[start] <= 'z') {
        var keyEnd = start;
        while (keyEnd < action.len and action[keyEnd] != ':' and action[keyEnd] != ' ' and action[keyEnd] != ')') {
            keyEnd += 1;
        }
        if (keyEnd < action.len and action[keyEnd] == ':') {
            const numStart = keyEnd + 1;
            var numEnd = numStart;
            while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
                numEnd += 1;
            }
            if (numEnd > numStart) {
                const posNum = std.fmt.parseInt(usize, action[numStart..numEnd], 10) catch return null;
                return .{ .kind = .keyed, .posNum = posNum, .endIdx = numEnd };
            }
        }
        return null;
    }

    // Bare number N
    if (action[start] >= '1' and action[start] <= '9') {
        var numEnd = start;
        while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
            numEnd += 1;
        }
        const posNum = std.fmt.parseInt(usize, action[start..numEnd], 10) catch return null;
        return .{ .kind = .bare, .posNum = posNum, .endIdx = numEnd };
    }

    // ...N (spread)
    if (start + 3 < action.len and action[start] == '.' and action[start + 1] == '.' and action[start + 2] == '.') {
        var numEnd = start + 3;
        while (numEnd < action.len and action[numEnd] >= '0' and action[numEnd] <= '9') {
            numEnd += 1;
        }
        if (numEnd > start + 3) {
            const posNum = std.fmt.parseInt(usize, action[start + 3 .. numEnd], 10) catch return null;
            return .{ .kind = .spread, .posNum = posNum, .endIdx = numEnd };
        }
    }

    return null;
}

/// Strip trailing nil references from the result buffer.
fn stripTrailingNils(result: *std.ArrayListUnmanaged(u8), posRefs: []const PosRefInfo) void {
    // Find last non-nil position reference
    var lastNonNil: ?usize = null;
    for (posRefs, 0..) |pr, idx| {
        if (!pr.isNil) lastNonNil = idx;
    }

    const truncateStart = if (lastNonNil) |lnn|
        if (lnn + 1 < posRefs.len) posRefs[lnn + 1].start else return
    else if (posRefs.len > 0)
        posRefs[0].start
    else
        return;

    // Also remove preceding spaces
    var actualStart = truncateStart;
    while (actualStart > 0 and result.items[actualStart - 1] == ' ') {
        actualStart -= 1;
    }
    result.items.len = actualStart;
}

/// Transform action template for stable positions.
/// Keeps logical positions stable, maps to actual RHS positions, inserts nil for absent optionals.
/// Strips trailing nils from the output.
fn transformActionStable(
    g: *Grammar,
    action: []const u8,
    altParsedElements: []const ParsedElement,
    optGroups: []const OptGroupInfo,
    combo: usize,
) ![]const u8 {
    const posMap = buildPositionMap(altParsedElements, optGroups, combo);

    var result: std.ArrayListUnmanaged(u8) = .empty;
    var posRefs: std.ArrayListUnmanaged(PosRefInfo) = .empty;
    defer posRefs.deinit(g.allocator);

    var i: usize = 0;
    while (i < action.len) {
        if (parsePositionRef(action, i)) |ref| {
            const mapped = if (ref.posNum < maxPositions) posMap[ref.posNum] else nilPos;
            const isNil = (mapped == nilPos);

            try posRefs.append(g.allocator, .{ .start = result.items.len, .isNil = isNil });

            if (isNil) {
                try result.appendSlice(g.allocator, "nil");
            } else {
                // Output prefix (...) then mapped position
                if (ref.kind == .spread) {
                    try result.appendSlice(g.allocator, "...");
                }
                var buf: [16]u8 = undefined;
                const posStr = std.fmt.bufPrint(&buf, "{d}", .{mapped + 1}) catch unreachable;
                try result.appendSlice(g.allocator, posStr);
            }
            i = ref.endIdx;
        } else {
            try result.append(g.allocator, action[i]);
            i += 1;
        }
    }

    stripTrailingNils(&result, posRefs.items);
    return result.toOwnedSlice(g.allocator);
}

fn processElement(g: *Grammar, elem: ParsedElement) error{OutOfMemory}!u16 {
    const baseId = try processBaseElement(g, elem);

    return switch (elem.quantifier) {
        .one => baseId,
        .optional => try createOptionalRule(g, baseId),
        .zeroPlus => try createZeroPlusRule(g, baseId),
        .onePlus => try createOnePlusRule(g, baseId),
    };
}

fn processBaseElement(g: *Grammar, elem: ParsedElement) error{OutOfMemory}!u16 {
    return switch (elem.kind) {
        .ident => blk: {
            if (g.getSymbol(elem.value)) |symId| break :blk symId;
            var resolved = elem.value;
            while (g.aliases.get(resolved)) |target| resolved = target;
            const kind: Symbol.Kind = if (resolved.len > 0 and resolved[0] >= 'A' and resolved[0] <= 'Z')
                .terminal
            else
                .nonterminal;
            break :blk try g.addSymbol(resolved, kind);
        },
        .token => blk: {
            if (g.getSymbol(elem.value)) |symId| break :blk symId;
            var resolved = elem.value;
            while (g.aliases.get(resolved)) |target| resolved = target;
            break :blk try g.addSymbol(resolved, .terminal);
        },
        .string => try g.addSymbol(elem.value, .terminal),
        .group => blk: {
            if (elem.subElements.len == 0) break :blk g.errorId;

            const grpName = try std.fmt.allocPrint(g.allocator, "_grp_{d}", .{g.rules.items.len});
            const grpId = try g.addSymbol(grpName, .nonterminal);

            var rhs: std.ArrayListUnmanaged(u16) = .empty;
            for (elem.subElements) |sub| {
                try rhs.append(g.allocator, try processElement(g, sub));
            }

            // Build action that excludes skipped elements
            // If element has skip=true, don't include its position in the action
            var actionTemplate: ?[]const u8 = null;
            var nonSkipped: std.ArrayListUnmanaged(u8) = .empty;
            defer nonSkipped.deinit(g.allocator);

            for (elem.subElements, 0..) |sub, i| {
                if (!sub.skip) {
                    try nonSkipped.append(g.allocator, @intCast(i + 1)); // 1-based positions
                }
            }

            // Generate action based on non-skipped count
            if (nonSkipped.items.len == 0) {
                actionTemplate = "nil";
            } else if (nonSkipped.items.len == 1) {
                // Single non-skipped: just return that position
                actionTemplate = try std.fmt.allocPrint(g.allocator, "{d}", .{nonSkipped.items[0]});
            } else if (nonSkipped.items.len < elem.subElements.len) {
                // Multiple non-skipped but some skipped: build explicit list
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                defer buf.deinit(g.allocator);
                try buf.append(g.allocator, '(');
                for (nonSkipped.items, 0..) |pos, j| {
                    if (j > 0) try buf.append(g.allocator, ' ');
                    try buf.append(g.allocator, '0' + pos);
                }
                try buf.append(g.allocator, ')');
                actionTemplate = try g.allocator.dupe(u8, buf.items);
            }
            // else: all elements included, action stays null (default list behavior)

            const ruleId: u16 = @intCast(g.rules.items.len);
            try g.rules.append(g.allocator, .{
                .id = ruleId,
                .lhs = grpId,
                .rhs = try rhs.toOwnedSlice(g.allocator),
                .action = actionTemplate,
            });
            try g.symbols.items[grpId].rules.append(g.allocator, ruleId);

            break :blk grpId;
        },
        .optGroup => g.errorId, // Should be expanded
        .reqList => blk: {
            const itemName = elem.value;
            break :blk try createRequiredList(g, itemName, elem.optionalItems, elem.listSeparator);
        },
        .optList => blk: {
            const itemName = elem.value;
            const reqList = try createRequiredList(g, itemName, elem.optionalItems, elem.listSeparator);
            break :blk try createOptionalRule(g, reqList);
        },
    };
}

fn createRequiredList(g: *Grammar, itemName: []const u8, optionalItems: bool, customSep: ?[]const u8) !u16 {
    const itemId = g.getSymbol(itemName) orelse blk: {
        const kind: Symbol.Kind = if (itemName.len > 0 and itemName[0] >= 'A' and itemName[0] <= 'Z')
            .terminal
        else
            .nonterminal;
        break :blk try g.addSymbol(itemName, kind);
    };

    const effectiveItemId = if (optionalItems)
        try createOptionalRule(g, itemId)
    else
        itemId;

    const sepStr = customSep orelse "\",\"";
    const sepId = try g.addSymbol(sepStr, .terminal);

    const suffix: []const u8 = if (optionalItems) "opt" else "";
    const sepSuffix: []const u8 = if (customSep != null) "s" else "";
    const listName = try std.fmt.allocPrint(g.allocator, "_list_{d}{s}{s}", .{ itemId, suffix, sepSuffix });
    const tailName = try std.fmt.allocPrint(g.allocator, "_tail_{d}{s}{s}", .{ itemId, suffix, sepSuffix });

    if (g.getSymbol(listName)) |existing| return existing;

    const listId = try g.addSymbol(listName, .nonterminal);
    const tailId = try g.addSymbol(tailName, .nonterminal);

    // Rule: _list → item _tail → (!1 ...2)
    const listRuleId: u16 = @intCast(g.rules.items.len);
    var listRhs: std.ArrayListUnmanaged(u16) = .empty;
    try listRhs.append(g.allocator, effectiveItemId);
    try listRhs.append(g.allocator, tailId);
    try g.rules.append(g.allocator, .{
        .id = listRuleId,
        .lhs = listId,
        .rhs = try listRhs.toOwnedSlice(g.allocator),
        .action = "(!1 ...2)",
    });
    try g.symbols.items[listId].rules.append(g.allocator, listRuleId);

    // Rule: _tail → sep item _tail → (!2 ...3)
    const tailRule1Id: u16 = @intCast(g.rules.items.len);
    var tailRhs1: std.ArrayListUnmanaged(u16) = .empty;
    try tailRhs1.append(g.allocator, sepId);
    try tailRhs1.append(g.allocator, effectiveItemId);
    try tailRhs1.append(g.allocator, tailId);
    try g.rules.append(g.allocator, .{
        .id = tailRule1Id,
        .lhs = tailId,
        .rhs = try tailRhs1.toOwnedSlice(g.allocator),
        .action = "(!2 ...3)",
    });
    try g.symbols.items[tailId].rules.append(g.allocator, tailRule1Id);

    // Rule: _tail → ε → ()
    const tailRule2Id: u16 = @intCast(g.rules.items.len);
    try g.rules.append(g.allocator, .{
        .id = tailRule2Id,
        .lhs = tailId,
        .rhs = &[_]u16{},
        .action = "()",
        .nullable = true,
        .preferShift = true,
    });
    try g.symbols.items[tailId].rules.append(g.allocator, tailRule2Id);
    g.symbols.items[tailId].nullable = true;

    return listId;
}

fn generateInfixChain(g: *Grammar, infix: InfixDecl) !void {
    const baseName = infix.baseRule;
    const baseId = g.getSymbol(baseName) orelse blk: {
        break :blk try g.addSymbol(baseName, .nonterminal);
    };

    // Collect unique precedence levels and sort them
    var levelsSeen: [64]u32 = undefined;
    var levelCount: usize = 0;

    for (infix.ops) |op| {
        var found = false;
        for (levelsSeen[0..levelCount]) |l| {
            if (l == op.prec) {
                found = true;
                break;
            }
        }
        if (!found and levelCount < 64) {
            levelsSeen[levelCount] = op.prec;
            levelCount += 1;
        }
    }

    // Sort levels ascending (level 1 = loosest binding)
    for (0..levelCount) |i| {
        for (i + 1..levelCount) |j| {
            if (levelsSeen[j] < levelsSeen[i]) {
                const tmp = levelsSeen[i];
                levelsSeen[i] = levelsSeen[j];
                levelsSeen[j] = tmp;
            }
        }
    }

    // Create a nonterminal for each level
    var levelIds: [64]u16 = undefined;
    for (0..levelCount) |i| {
        const name = try std.fmt.allocPrint(g.allocator, "_infix_{d}", .{levelsSeen[i]});
        levelIds[i] = try g.addSymbol(name, .nonterminal);
    }

    // For each level, generate rules
    for (0..levelCount) |i| {
        const level = levelsSeen[i];
        const thisId = levelIds[i];
        const nextId = if (i + 1 < levelCount) levelIds[i + 1] else baseId;

        // Find all operators at this level
        for (infix.ops) |op| {
            if (op.prec != level) continue;

            const opStr = try std.fmt.allocPrint(g.allocator, "\"{s}\"", .{op.op});
            const opId = try g.addSymbol(opStr, .terminal);

            const actionStr = try std.fmt.allocPrint(g.allocator, "({s} 1 3)", .{op.op});

            var rhs: std.ArrayListUnmanaged(u16) = .empty;
            switch (op.assoc) {
                .left => {
                    try rhs.append(g.allocator, thisId);
                    try rhs.append(g.allocator, opId);
                    try rhs.append(g.allocator, nextId);
                },
                .right => {
                    try rhs.append(g.allocator, nextId);
                    try rhs.append(g.allocator, opId);
                    try rhs.append(g.allocator, thisId);
                },
                .none => {
                    try rhs.append(g.allocator, nextId);
                    try rhs.append(g.allocator, opId);
                    try rhs.append(g.allocator, nextId);
                },
            }

            const ruleId: u16 = @intCast(g.rules.items.len);
            try g.rules.append(g.allocator, .{
                .id = ruleId,
                .lhs = thisId,
                .rhs = try rhs.toOwnedSlice(g.allocator),
                .action = actionStr,
            });
            try g.symbols.items[thisId].rules.append(g.allocator, ruleId);
        }

        // Passthrough rule: this_level → next_level
        const passthroughId: u16 = @intCast(g.rules.items.len);
        var passRhs: std.ArrayListUnmanaged(u16) = .empty;
        try passRhs.append(g.allocator, nextId);
        try g.rules.append(g.allocator, .{
            .id = passthroughId,
            .lhs = thisId,
            .rhs = try passRhs.toOwnedSlice(g.allocator),
            .action = "1",
        });
        try g.symbols.items[thisId].rules.append(g.allocator, passthroughId);
    }

    // Create the `infix` entry point that aliases to the lowest-precedence level
    const infixId = try g.addSymbol("infix", .nonterminal);
    const infixRuleId: u16 = @intCast(g.rules.items.len);
    var infixRhs: std.ArrayListUnmanaged(u16) = .empty;
    try infixRhs.append(g.allocator, levelIds[0]);
    try g.rules.append(g.allocator, .{
        .id = infixRuleId,
        .lhs = infixId,
        .rhs = try infixRhs.toOwnedSlice(g.allocator),
        .action = "1",
    });
    try g.symbols.items[infixId].rules.append(g.allocator, infixRuleId);
}

fn createOptionalRule(g: *Grammar, symId: u16) !u16 {
    const name = try std.fmt.allocPrint(g.allocator, "_opt_{d}", .{symId});
    if (g.getSymbol(name)) |existing| return existing;

    const optId = try g.addSymbol(name, .nonterminal);

    // Rule 1: opt → sym
    const rule1Id: u16 = @intCast(g.rules.items.len);
    var rhs1: std.ArrayListUnmanaged(u16) = .empty;
    try rhs1.append(g.allocator, symId);
    try g.rules.append(g.allocator, .{
        .id = rule1Id,
        .lhs = optId,
        .rhs = try rhs1.toOwnedSlice(g.allocator),
        .action = null,
    });
    try g.symbols.items[optId].rules.append(g.allocator, rule1Id);

    // Rule 2: opt → ε
    const rule2Id: u16 = @intCast(g.rules.items.len);
    try g.rules.append(g.allocator, .{
        .id = rule2Id,
        .lhs = optId,
        .rhs = &[_]u16{},
        .action = null,
        .nullable = true,
    });
    try g.symbols.items[optId].rules.append(g.allocator, rule2Id);
    g.symbols.items[optId].nullable = true;

    return optId;
}

fn createZeroPlusRule(g: *Grammar, symId: u16) !u16 {
    const name = try std.fmt.allocPrint(g.allocator, "_star_{d}", .{symId});
    if (g.getSymbol(name)) |existing| return existing;

    const starId = try g.addSymbol(name, .nonterminal);

    // Rule 1: star → sym star → (!1 ...2)
    const rule1Id: u16 = @intCast(g.rules.items.len);
    var rhs1: std.ArrayListUnmanaged(u16) = .empty;
    try rhs1.append(g.allocator, symId);
    try rhs1.append(g.allocator, starId);
    try g.rules.append(g.allocator, .{
        .id = rule1Id,
        .lhs = starId,
        .rhs = try rhs1.toOwnedSlice(g.allocator),
        .action = "(!1 ...2)",
    });
    try g.symbols.items[starId].rules.append(g.allocator, rule1Id);

    // Rule 2: star → ε → ()
    const rule2Id: u16 = @intCast(g.rules.items.len);
    try g.rules.append(g.allocator, .{
        .id = rule2Id,
        .lhs = starId,
        .rhs = &[_]u16{},
        .action = "()",
        .nullable = true,
    });
    try g.symbols.items[starId].rules.append(g.allocator, rule2Id);
    g.symbols.items[starId].nullable = true;

    return starId;
}

fn createOnePlusRule(g: *Grammar, symId: u16) !u16 {
    const name = try std.fmt.allocPrint(g.allocator, "_plus_{d}", .{symId});
    if (g.getSymbol(name)) |existing| return existing;

    const starId = try createZeroPlusRule(g, symId);
    const plusId = try g.addSymbol(name, .nonterminal);

    // Rule: plus → sym star → (!1 ...2)
    const ruleId: u16 = @intCast(g.rules.items.len);
    var rhs: std.ArrayListUnmanaged(u16) = .empty;
    try rhs.append(g.allocator, symId);
    try rhs.append(g.allocator, starId);
    try g.rules.append(g.allocator, .{
        .id = ruleId,
        .lhs = plusId,
        .rhs = try rhs.toOwnedSlice(g.allocator),
        .action = "(!1 ...2)",
    });
    try g.symbols.items[plusId].rules.append(g.allocator, ruleId);

    return plusId;
}
