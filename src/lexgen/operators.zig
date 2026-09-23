//! Operator emission: the final `switch (c)` over literal rules (with
//! multi-char peek-ahead and guarded arms), and the top-of-matchRules
//! preemption of multi-char literals that other scanners would shadow.

const std = @import("std");
const grammar = @import("../grammar.zig");
const LexerSpec = grammar.LexerSpec;
const Guard = grammar.Guard;
const Action = grammar.Action;
const Allocator = std.mem.Allocator;
const LexerGenerator = @import("lexgen.zig").LexerGenerator;
const patterns = @import("patterns.zig");

pub const OpRule = struct {
    chars: [8]u8,
    charCount: u8,
    token: []const u8,
    guards: []const Guard,
    actions: []const Action,
};

pub fn generateOperatorSwitch(gen: *LexerGenerator) !void {
    var groups: [256]std.ArrayListUnmanaged(OpRule) = @splat(.empty);
    defer for (&groups) |*g| g.deinit(gen.allocator);

    // Build set of characters that start string literal patterns
    // (these are handled by the string scanner, not the operator switch)
    var stringStartChars: [256]bool = @splat(false);
    for (gen.spec.rules.items) |rule| {
        const isStringTok = std.mem.startsWith(u8, rule.token, "string");
        if (!isStringTok) continue;
        if (rule.guards.len > 0) continue;
        if (rule.pattern.len >= 3) {
            const delim = rule.pattern[0];
            if (delim == '\'' or delim == '"') {
                stringStartChars[rule.pattern[1]] = true;
            }
        }
    }

    // Find the comment start character from the grammar
    var commentStartChar: u8 = 0;
    for (gen.spec.rules.items) |rule| {
        if (std.mem.eql(u8, rule.token, "comment")) {
            const info = patterns.parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len > 0) commentStartChar = info.chars[0];
            break;
        }
    }

    for (gen.spec.rules.items, 0..) |rule, ri| {
        const info = patterns.parseLiteralPattern(rule.pattern) orelse continue;
        if (info.len == 0) continue;
        const fc = info.chars[0];
        if (fc == '\n' or fc == '\r') continue;
        if (fc == commentStartChar) continue;
        if (stringStartChars[fc]) continue;
        // Skip rules already emitted by generateMultiCharLiteralPreemption.
        // Keeps the operator switch from redundantly re-handling multi-char
        // literals like MUMPS's `'=`, `'<` or slash's `???`, `??`.
        if (gen.isRulePreempted(ri)) continue;

        try groups[fc].append(gen.allocator, .{
            .chars = info.chars,
            .charCount = info.len,
            .token = rule.token,
            .guards = rule.guards,
            .actions = rule.actions,
        });
    }

    try gen.write(
        \\        // Single/multi-char operators
        \\        self.pos += 1;
        \\        return switch (c) {
        \\
    );

    for (0..256) |i| {
        const c: u8 = @intCast(i);
        if (groups[c].items.len == 0) continue;
        try emitSwitchArm(gen, c, groups[c].items, null);
    }

    try gen.write(
        \\            else => Token{ .cat = .@"err", .pre = wsCount, .pos = start, .len = 1 },
        \\        };
        \\    }
        \\
    );
}

pub fn emitSwitchArm(gen: *LexerGenerator, firstChar: u8, rules: []const OpRule, codeFn: ?[]const u8) !void {
    var singleRules: std.ArrayListUnmanaged(OpRule) = .empty;
    defer singleRules.deinit(gen.allocator);
    var multiRules: std.ArrayListUnmanaged(OpRule) = .empty;
    defer multiRules.deinit(gen.allocator);

    for (rules) |rule| {
        if (rule.charCount > 1)
            try multiRules.append(gen.allocator, rule)
        else
            try singleRules.append(gen.allocator, rule);
    }

    const lit = patterns.charToZigLiteral(firstChar);
    const litStr = lit.buf[0..lit.len];

    const hasGuards = blk: {
        for (singleRules.items) |r| if (r.guards.len > 0) break :blk true;
        break :blk false;
    };
    const hasActions = blk: {
        for (singleRules.items) |r| if (r.actions.len > 0) break :blk true;
        break :blk false;
    };
    const needsBlk = multiRules.items.len > 0 or hasGuards or hasActions;

    if (!needsBlk) {
        const r = singleRules.items[0];
        try gen.print("            '{s}' => Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ litStr, r.token });
        return;
    }

    // Pre-guard shortcut: two rules for same char differing only by pre guard,
    // both producing single-char tokens with no actions.
    // Skip shortcut if pattern-exit logic is needed (requires a block).
    if (multiRules.items.len == 0 and singleRules.items.len == 2 and !hasActions) {
        var guarded: ?[]const u8 = null;
        var default: ?[]const u8 = null;
        for (singleRules.items) |r| {
            if (r.guards.len > 0) {
                var isPre = false;
                for (r.guards) |g| {
                    if (std.mem.eql(u8, g.variable, "pre") and !g.negated and
                        (g.op == .truthy or (g.op == .gt and g.value == 0)))
                        isPre = true;
                }
                if (isPre) guarded = r.token;
            } else {
                default = r.token;
            }
        }
        if (guarded != null and default != null) {
            try gen.print("            '{s}' => Token{{ .cat = if (wsCount > 0) .@\"{s}\" else .@\"{s}\", .pre = wsCount, .pos = start, .len = 1 }},\n", .{ litStr, guarded.?, default.? });
            return;
        }
    }

    try gen.print("            '{s}' => blk: {{\n", .{litStr});

    // Multi-char rules: group by second char, longest first
    if (multiRules.items.len > 0) {
        try emitMultiCharPeekAhead(gen, multiRules.items, 1, codeFn);
    }

    // Single-char rules with guards
    try emitGuardedSingleCharRules(gen, singleRules.items);

    // If multi-char rules exist but no unguarded single-char fallback,
    // the blk: may not return. Add a fallback: rewind pos and route to
    // the appropriate scanner, or emit an error token.
    // Skip if guarded rules form an exhaustive chain (2+ guards, no unguarded).
    if (multiRules.items.len > 0) {
        const hasUnguarded = blk: {
            for (singleRules.items) |r| {
                if (r.guards.len == 0) break :blk true;
            }
            break :blk false;
        };
        var guardedCount: usize = 0;
        for (singleRules.items) |r| {
            if (r.guards.len > 0) guardedCount += 1;
        }
        const exhaustive = !hasUnguarded and guardedCount >= 2;
        if (!hasUnguarded and !exhaustive) {
            // Determine fallback based on what this character starts
            const isStringStart = (firstChar == '\'' or firstChar == '"');
            const isDigit = (firstChar >= '0' and firstChar <= '9');

            if (isStringStart) {
                // scanString re-reads from start, so rewind pos.
                try gen.write("                self.pos -= 1;\n");
                try gen.write("                break :blk self.scanString(start, wsCount);\n");
            } else if (isDigit) {
                // scanNumber re-reads from start, so rewind pos.
                try gen.write("                self.pos -= 1;\n");
                try gen.write("                break :blk self.scanNumber(start, wsCount);\n");
            } else {
                // Err fallback: pos was already advanced by the outer
                // consumer; emit `len=1` covering the offending byte and
                // keep `pos` advanced so the next call moves on. (The
                // previous `self.pos -= 1` here caused an infinite loop in
                // BaseLexer-only callers such as the syntax highlighter
                // when the buffer ended mid-token, e.g. `echo $!`.)
                try gen.write("                break :blk Token{ .cat = .@\"err\", .pre = wsCount, .pos = start, .len = 1 };\n");
            }
        }
    }

    try gen.write("            },\n");
}

pub fn emitMultiCharPeekAhead(gen: *LexerGenerator, rules: []const OpRule, depth: u8, codeFn: ?[]const u8) !void {
    const baseIndent = "                ";
    var indentBuf: [64]u8 = undefined;
    const extra: usize = (@as(usize, depth) - 1) * 4;
    const indent = blk: {
        @memset(&indentBuf, ' ');
        break :blk indentBuf[0 .. baseIndent.len + extra];
    };

    var seenSecond: [256]bool = @splat(false);
    var secondChars: [256]u8 = undefined;
    var secondCount: usize = 0;

    for (rules) |r| {
        if (r.charCount <= depth) continue;
        const sc = r.chars[depth];
        if (!seenSecond[sc]) {
            seenSecond[sc] = true;
            secondChars[secondCount] = sc;
            secondCount += 1;
        }
    }

    for (secondChars[0..secondCount]) |sc| {
        var matching: std.ArrayListUnmanaged(OpRule) = .empty;
        defer matching.deinit(gen.allocator);
        for (rules) |r| {
            if (r.charCount > depth and r.chars[depth] == sc)
                try matching.append(gen.allocator, r);
        }

        const scLit = patterns.charToZigLiteral(sc);
        const scStr = scLit.buf[0..scLit.len];

        // Check if ALL matching rules share the same guard
        const allSameGuard = blk: {
            if (matching.items.len == 0) break :blk false;
            const firstGuards = matching.items[0].guards;
            for (matching.items[1..]) |r| {
                if (r.guards.len != firstGuards.len) break :blk false;
            }
            break :blk firstGuards.len > 0;
        };

        if (allSameGuard) {
            try gen.write(indent);
            try gen.write("if (");
            try gen.emitAllGuards(matching.items[0].guards);
            try gen.print(" and self.peek() == '{s}') {{\n", .{scStr});
        } else {
            try gen.write(indent);
            try gen.print("if (self.peek() == '{s}') {{\n", .{scStr});
        }
        try gen.write(indent);
        try gen.write("    self.pos += 1;\n");

        // Check for deeper (3-char) rules
        var hasDeeper = false;
        for (matching.items) |r| {
            if (r.charCount > depth + 1) {
                hasDeeper = true;
                break;
            }
        }
        if (hasDeeper) {
            try emitMultiCharPeekAhead(gen, matching.items, depth + 1, codeFn);
        }

        // Emit terminating rules at this depth
        var terminated = false;
        for (matching.items) |r| {
            if (r.charCount == depth + 1) {
                if (!allSameGuard and r.guards.len > 0) {
                    try gen.write(indent);
                    try gen.write("    if (");
                    try gen.emitAllGuards(r.guards);
                    try gen.write(") {\n");
                    try gen.emitActions(r.actions, indent);
                    try gen.emitTokenReturn("break :blk", r.token, r.charCount);
                    try gen.write(indent);
                    try gen.write("    }\n");
                } else if (!terminated) {
                    try gen.emitActions(r.actions, indent);
                    try gen.emitTokenReturn("break :blk", r.token, r.charCount);
                    terminated = true;
                }
            }
        }

        // If deeper rules didn't all terminate, rewind pos on failure
        if (!terminated) {
            try gen.write(indent);
            try gen.write("    self.pos -= 1;\n");
        }
        try gen.write(indent);
        try gen.write("}\n");
    }
}

pub fn emitGuardedSingleCharRules(gen: *LexerGenerator, rules: []const OpRule) !void {
    if (rules.len == 0) return;

    // Separate guarded from unguarded
    var guarded: std.ArrayListUnmanaged(OpRule) = .empty;
    defer guarded.deinit(gen.allocator);
    var unguarded: ?OpRule = null;

    for (rules) |r| {
        if (r.guards.len > 0)
            try guarded.append(gen.allocator, r)
        else
            unguarded = r;
    }

    // Emit guarded rules as if-chain
    for (guarded.items, 0..) |r, i| {
        const isLast = (i == guarded.items.len - 1);
        if (i == 0) {
            try gen.write("                if (");
            try gen.emitAllGuards(r.guards);
            try gen.write(") {\n");
        } else if (isLast and unguarded == null) {
            try gen.write(" else {\n");
        } else {
            try gen.write(" else if (");
            try gen.emitAllGuards(r.guards);
            try gen.write(") {\n");
        }
        try gen.emitActions(r.actions, "                    ");
        try gen.emitTokenReturn("break :blk", r.token, r.charCount);
        try gen.write("                }");
    }

    // Emit unguarded fallback
    if (unguarded) |r| {
        if (guarded.items.len > 0) {
            try gen.write("\n");
        }
        try gen.emitActions(r.actions, "                ");
        try gen.emitTokenReturn("break :blk", r.token, r.charCount);
    } else if (guarded.items.len > 0) {
        // If the last guarded rule was emitted as a bare `else`, the chain
        // is already exhaustive — no fallback needed.
        const exhaustive = guarded.items.len >= 2 and unguarded == null;
        if (!exhaustive) {
            try gen.write("\n                break :blk Token{ .cat = .@\"err\", .pre = wsCount, .pos = start, .len = 1 };\n");
        } else {
            try gen.write("\n");
        }
    }
}

/// Top-of-matchRules preemption for rules whose pattern begins with a
/// multi-char literal (optionally followed by a class-suffix continuation).
/// Runs BEFORE string scanners, punct-ident, compound-literal, number/ident
/// fast-paths, and the operator switch.
///
/// Resolves two shadowing bugs surfaced by slash:
///   - `"'''" → heredoc_sq` was silently dropped because the sq-string
///     scanner (triggered by leader `'`) fired first and consumed the
///     triple quotes as an escape-and-unterminated error.
///   - `"???" → missing` was preempted by the `[*?]...` punct-ident
///     dispatch consuming `?` as a len-1 ident.
///
/// Also fills the shape gap left by `generatePrefixScanners` (single-char
/// literal prefix + class) for multi-char literal prefix + class:
/// e.g. `"```" [a-zA-Z][a-zA-Z0-9]* → heredoc_bt`.
///
/// Emission rules:
///   - Pattern must start with a literal of length >= 2.
///   - Optional suffix: `[class]` (single char) or `[class1][class2]*` or
///     `[class1][class2]+`. Single literal chars after the prefix are NOT
///     supported here (those are operator-switch territory).
///   - Per first-byte bucket: rules emitted longest-first (longer prefix
///     wins; with-suffix wins over without at same prefix length; then
///     source order). Matches the standard maximal-munch + source-order
///     tiebreak rule for lexer alternatives.
///   - Guards (if any) are emitted as an inner `if`; on guard-false,
///     control falls through to the next candidate / next leader.
///   - No match: pos is untouched; control falls through to the rest of
///     matchRules.
pub fn generateMultiCharLiteralPreemption(gen: *LexerGenerator) !void {
    const Suffix = struct {
        startChars: [256]bool,
        contChars: [256]bool,
        hasCont: bool,
        contQuantPlus: bool, // true for +, false for *
    };
    const Rule = struct {
        prefix: [8]u8,
        prefixLen: u8,
        hasSuffix: bool,
        suffix: Suffix,
        token: []const u8,
        guards: []const Guard,
    };

    // Compute the set of leaders whose multi-char literal rules would be
    // shadowed by a non-operator-switch dispatch that runs earlier in
    // matchRules. For these leaders, ALL multi-char literal rules must
    // be hoisted into the preemption block — otherwise the shadowing
    // dispatch consumes the leader before the switch sees it.
    //
    // Sources of shadowing:
    //   - String scanner (delimiter-led open-ended loop)
    //   - Punct-ident dispatch (paths, globs)
    //   - Compound-literal dispatch (`'X' 'X'? [class]...`)
    //
    // Note: class-suffix rules (e.g. `"```" [a-zA-Z]...`) are handled
    // separately — those are emitted in preemption regardless of
    // shadowing because the operator switch can't emit class-suffix
    // consumption. Marking their LEADER as globally shadowed would
    // over-preempt sibling pure-literal rules on that leader (the MUMPS
    // bug em flagged).
    var trulyShadowed: [256]bool = @splat(false);
    for (gen.spec.rules.items) |gr| {
        if (!std.mem.startsWith(u8, gr.token, "string")) continue;
        if (gr.guards.len > 0) continue;
        if (gr.pattern.len >= 3 and (gr.pattern[0] == '\'' or gr.pattern[0] == '"')) {
            trulyShadowed[gr.pattern[1]] = true;
        }
    }
    {
        var pir = try patterns.collectPunctIdentRules(gen.spec);
        const pirSlice = pir.rules[0..pir.count];
        for (pirSlice) |*r| {
            for (0..256) |c| {
                if (r.startChars[c]) trulyShadowed[c] = true;
            }
        }
    }
    for (gen.spec.rules.items) |gr| {
        // Compound-literal leader: pattern starts with `'X' 'X'?`
        if (gr.pattern.len < 7) continue;
        if (gr.pattern[0] != '\'' or gr.pattern[2] != '\'') continue;
        var p: usize = 3;
        while (p < gr.pattern.len and gr.pattern[p] == ' ') p += 1;
        if (p + 3 < gr.pattern.len and gr.pattern[p] == '\'' and
            gr.pattern[p + 2] == '\'' and gr.pattern[p + 3] == '?')
        {
            trulyShadowed[gr.pattern[1]] = true;
        }
    }

    const Collected = struct { rule: Rule, ruleIndex: usize };
    var rules: std.ArrayListUnmanaged(Collected) = .empty;
    defer rules.deinit(gen.allocator);

    for (gen.spec.rules.items, 0..) |gr, gi| {
        // Parse literal prefix using the same rules as parseLiteralPattern,
        // but accept trailing non-empty pattern content (a class suffix).
        if (gr.pattern.len < 4) continue; // need at least delim + 2 prefix chars + delim
        if (gr.pattern[0] != '\'' and gr.pattern[0] != '"') continue;
        const delim = gr.pattern[0];

        var prefixChars: [8]u8 = undefined;
        var prefixLen: u8 = 0;
        var i: usize = 1;
        var closed = false;
        while (i < gr.pattern.len) : (i += 1) {
            if (gr.pattern[i] == delim) {
                closed = true;
                i += 1;
                break;
            }
            if (prefixLen >= 8) break;
            if (gr.pattern[i] == '\\' and i + 1 < gr.pattern.len) {
                prefixChars[prefixLen] = switch (gr.pattern[i + 1]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '\'' => '\'',
                    '"' => '"',
                    else => gr.pattern[i + 1],
                };
                i += 1; // consume second char; loop's +=1 handles the escape char
            } else {
                prefixChars[prefixLen] = gr.pattern[i];
            }
            prefixLen += 1;
        }
        if (!closed or prefixLen < 2) continue;

        // Skip rules with dedicated earlier dispatches or with actions
        // that the preemption block wouldn't reproduce:
        //   - "string"-token rules: delimiter-scan loops, not literals.
        //   - "newline" / "skip" tokens: handled by generateNewlineHandling
        //     and the operator-switch `\\` arm respectively, both of
        //     which also execute state mutations.
        //   - Rules with actions (state mutations) beyond token return:
        //     preemption only emits the return, so action-bearing rules
        //     must stay in their original dispatch.
        if (std.mem.startsWith(u8, gr.token, "string")) continue;
        if (std.mem.eql(u8, gr.token, "newline")) continue;
        if (std.mem.eql(u8, gr.token, "skip")) continue;
        if (gr.actions.len > 0) continue;

        // Optional suffix: [class] (single required) or [class1][class2]* etc.
        var rest = gr.pattern[i..];
        rest = std.mem.trimStart(u8, rest, " ");
        var suffix: Suffix = .{
            .startChars = @splat(false),
            .contChars = @splat(false),
            .hasCont = false,
            .contQuantPlus = false,
        };
        var hasSuffix = false;
        if (rest.len > 0) {
            if (rest[0] != '[') continue; // unsupported suffix shape
            const sc = patterns.parseCharClass(rest) orelse continue;
            suffix.startChars = sc.chars;
            hasSuffix = true;
            var p: usize = sc.endPos;
            while (p < rest.len and rest[p] == ' ') p += 1;
            // Optional continuation class with * or +
            if (p < rest.len and rest[p] == '[') {
                const cc = patterns.parseCharClass(rest[p..]) orelse continue;
                p += cc.endPos;
                if (p >= rest.len or (rest[p] != '*' and rest[p] != '+')) continue;
                suffix.contChars = cc.chars;
                suffix.hasCont = true;
                suffix.contQuantPlus = rest[p] == '+';
                p += 1;
            }
            const trailing = std.mem.trimStart(u8, rest[p..], " ");
            if (trailing.len != 0) continue; // disallow more elements
        }

        // Per-rule preemption decision: a rule goes into preemption iff
        //   - Its leader is truly shadowed by an earlier dispatch, OR
        //   - It has a class suffix (operator switch can't emit that shape)
        // Pure multi-char literals on non-shadowed leaders continue to
        // flow through the operator switch where they're already handled
        // correctly — avoids the MUMPS-style duplication em flagged.
        const needsPreemption = trulyShadowed[prefixChars[0]] or hasSuffix;
        if (!needsPreemption) continue;

        try rules.append(gen.allocator, .{
            .rule = .{
                .prefix = prefixChars,
                .prefixLen = prefixLen,
                .hasSuffix = hasSuffix,
                .suffix = suffix,
                .token = gr.token,
                .guards = gr.guards,
            },
            .ruleIndex = gi,
        });
        try gen.preemptedRules.append(gen.allocator, gi);
    }

    if (rules.items.len == 0) return;

    // Group by first byte
    var groups: [256]std.ArrayListUnmanaged(Rule) = @splat(.empty);
    defer for (&groups) |*g| g.deinit(gen.allocator);
    for (rules.items) |c| try groups[c.rule.prefix[0]].append(gen.allocator, c.rule);

    // Sort each group: longer prefix first, with-suffix before without at
    // same prefix length, then stable (source) order.
    const sortFn = struct {
        fn lt(_: void, a: Rule, b: Rule) bool {
            if (a.prefixLen != b.prefixLen) return a.prefixLen > b.prefixLen;
            if (a.hasSuffix != b.hasSuffix) return a.hasSuffix and !b.hasSuffix;
            return false; // preserve source order
        }
    }.lt;

    try gen.write(
        \\        // Multi-char literal preemption (heredoc delimiters,
        \\        // triple-bang operators, etc.) — longest-first; falls
        \\        // through on no match.
        \\
    );

    for (0..256) |bi| {
        const b: u8 = @intCast(bi);
        const grp = &groups[b];
        if (grp.items.len == 0) continue;

        // Zig's std.sort.block is stable-ish; use insertion for tiny groups.
        std.mem.sort(Rule, grp.items, {}, sortFn);

        const lit = patterns.charToZigLiteral(b);
        try gen.print("        if (c == '{s}') {{\n", .{lit.buf[0..lit.len]});

        for (grp.items) |r| {
            // Build the full match condition. The leader (pos 0) is
            // already c == first char; we need the remaining prefix chars
            // to match at pos+1..pos+prefixLen-1, and (if suffix) the
            // suffix start class to match at pos+prefixLen.
            const minLen: u32 = @as(u32, r.prefixLen) + (if (r.hasSuffix) @as(u32, 1) else @as(u32, 0));

            try gen.print("            if (self.pos + {d} <= self.source.len", .{minLen});
            for (1..r.prefixLen) |pi| {
                const pl = patterns.charToZigLiteral(r.prefix[pi]);
                try gen.print(" and self.source[self.pos + {d}] == '{s}'", .{ pi, pl.buf[0..pl.len] });
            }
            if (r.hasSuffix) {
                // Single-required-char suffix start class.
                var ix: [64]u8 = undefined;
                const ixStr = try std.fmt.bufPrint(&ix, "self.source[self.pos + {d}]", .{r.prefixLen});
                try gen.write(" and (");
                try gen.emitCharSetCondition(r.suffix.startChars, ixStr);
                try gen.write(")");
            }
            try gen.write(") {\n");

            const bodyIndent = if (r.guards.len > 0) "                " else "                ";
            if (r.guards.len > 0) {
                try gen.write("                if (");
                try gen.emitAllGuards(r.guards);
                try gen.write(") {\n");
            }

            try gen.print("{s}self.pos += {d};\n", .{ bodyIndent, minLen });
            if (r.hasSuffix and r.suffix.hasCont) {
                try gen.print("{s}while (self.pos < self.source.len and (", .{bodyIndent});
                try gen.emitCharSetCondition(r.suffix.contChars, "self.source[self.pos]");
                try gen.write(")) self.pos += 1;\n");
            }
            try gen.print("{s}return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n", .{ bodyIndent, r.token });

            if (r.guards.len > 0) try gen.write("                }\n");
            try gen.write("            }\n");
        }

        try gen.write("        }\n");
    }
}
