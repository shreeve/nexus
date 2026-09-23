//! Scanner emission: newline and zero-width guard rules, the character
//! classification table, the pre-switch scanner dispatch (strings, compound
//! literals, punct-led identifiers, prefixes, numbers, identifiers) and the
//! scan functions themselves, plus comment handling.

const std = @import("std");
const diag = @import("../diag.zig");
const grammar = @import("../grammar.zig");
const Guard = grammar.Guard;
const Action = grammar.Action;
const LexerGenerator = @import("lexgen.zig").LexerGenerator;
const patterns = @import("patterns.zig");

pub fn generateEmptyPatternGuards(gen: *LexerGenerator) !void {
    // Collect rules with empty patterns (guard-only, zero-width tokens)
    var hasAny = false;
    for (gen.spec.rules.items) |rule| {
        if (rule.pattern.len > 0) continue;
        if (rule.guards.len == 0) continue;
        hasAny = true;
        break;
    }
    if (!hasAny) return;

    try gen.write("        // Empty-pattern guard rules (zero-width tokens based on state)\n");
    for (gen.spec.rules.items) |rule| {
        if (rule.pattern.len > 0) continue;
        if (rule.guards.len == 0) continue;

        try gen.write("        if (");
        for (rule.guards, 0..) |guard, gi| {
            if (gi > 0) try gen.write(" and ");
            try gen.emitGuardCondition(guard);
        }
        try gen.write(") {\n");

        // Emit actions (e.g., {beg = 0}, {pre = counted('.')})
        for (rule.actions) |action| {
            switch (action.kind) {
                .set => {
                    if (std.mem.eql(u8, action.variable.?, "pre")) {
                        try gen.print("            wsCount = {d};\n", .{@as(u32, @intCast(action.value.?))});
                    } else {
                        try gen.print("            self.{s} = {d};\n", .{ action.variable.?, action.value.? });
                    }
                },
                .counted => {
                    const ch = patterns.charToZigLiteral(action.char.?);
                    try gen.print(
                        \\            {{
                        \\                var count: u8 = 0;
                        \\                while (self.pos < self.source.len and self.source[self.pos] == '{s}') {{
                        \\                    self.pos += 1;
                        \\                    count +|= 1;
                        \\                    while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) self.pos += 1;
                        \\                }}
                        \\                wsCount = count;
                        \\            }}
                        \\
                    , .{ch.buf[0..ch.len]});
                },
                .inc => try gen.print("            self.{s} += 1;\n", .{action.variable.?}),
                .dec => try gen.print("            self.{s} -= 1;\n", .{action.variable.?}),
            }
        }

        try gen.print("            return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = wsStart, .len = @intCast(self.pos - wsStart) }};\n", .{rule.token});
        try gen.write("        }\n");
    }
    try gen.write("\n");
}

pub fn generateNewlineHandling(gen: *LexerGenerator) !void {
    // Collect newline rules from grammar (literal patterns for \n, \r, \r\n)
    const NlRule = struct {
        chars: [2]u8,
        charCount: u8,
        token: []const u8,
        guards: []const Guard,
        actions: []const Action,
    };

    var crlfRules: std.ArrayListUnmanaged(NlRule) = .empty;
    defer crlfRules.deinit(gen.allocator);
    var lfRules: std.ArrayListUnmanaged(NlRule) = .empty;
    defer lfRules.deinit(gen.allocator);
    var crRules: std.ArrayListUnmanaged(NlRule) = .empty;
    defer crRules.deinit(gen.allocator);

    for (gen.spec.rules.items) |rule| {
        const info = patterns.parseLiteralPattern(rule.pattern) orelse continue;
        if (info.len == 2 and info.chars[0] == '\r' and info.chars[1] == '\n') {
            try crlfRules.append(gen.allocator, .{
                .chars = .{ '\r', '\n' },
                .charCount = 2,
                .token = rule.token,
                .guards = rule.guards,
                .actions = rule.actions,
            });
        } else if (info.len == 1 and info.chars[0] == '\n') {
            try lfRules.append(gen.allocator, .{
                .chars = .{ '\n', 0 },
                .charCount = 1,
                .token = rule.token,
                .guards = rule.guards,
                .actions = rule.actions,
            });
        } else if (info.len == 1 and info.chars[0] == '\r') {
            try crRules.append(gen.allocator, .{
                .chars = .{ '\r', 0 },
                .charCount = 1,
                .token = rule.token,
                .guards = rule.guards,
                .actions = rule.actions,
            });
        }
    }

    if (lfRules.items.len == 0 and crRules.items.len == 0) return;

    try gen.write(
        \\        // Newline handling (generated from grammar rules)
        \\        if (c == '\n' or c == '\r') {
        \\
    );

    // CRLF check first (longest match)
    if (crlfRules.items.len > 0) {
        try gen.write("            if (c == '\\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\\n') {\n");
        try emitNewlineRules(gen, crlfRules.items, 2);
        try gen.write("            }\n");
    }

    // Single-char newline rules (\n and standalone \r)
    // After CRLF is excluded, \n and \r have identical handling — use \n rules
    const singleRules = if (lfRules.items.len > 0) lfRules.items else crRules.items;
    if (singleRules.len > 0) {
        try emitNewlineRules(gen, singleRules, 1);
    }

    try gen.write(
        \\        }
        \\
    );
}

fn emitNewlineRules(gen: *LexerGenerator, rules: anytype, charCount: u8) !void {
    var guarded: std.ArrayListUnmanaged(@TypeOf(rules[0])) = .empty;
    defer guarded.deinit(gen.allocator);
    var unguarded: ?@TypeOf(rules[0]) = null;

    for (rules) |r| {
        if (r.guards.len > 0) {
            try guarded.append(gen.allocator, r);
        } else {
            unguarded = r;
        }
    }

    // Consume the newline character(s)
    if (charCount == 2) {
        try gen.write("                self.pos += 2;\n");
    } else {
        try gen.write("                self.pos += 1;\n");
    }

    for (guarded.items) |r| {
        try gen.write("                if (");
        try gen.emitAllGuards(r.guards);
        try gen.write(") {\n");
        try gen.emitActions(r.actions, "                    ");
        try gen.print("                    return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, charCount });
        try gen.write("                }\n");
    }

    if (unguarded) |r| {
        try gen.emitActions(r.actions, "                ");
        try gen.print("                return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = {d} }};\n", .{ r.token, charCount });
    }
}

pub fn generateCharClassification(gen: *LexerGenerator) !void {
    var letterChars: [256]bool = @splat(false);
    var digitChars: [256]bool = @splat(false);
    var identExtraChars: [256]bool = @splat(false);

    for (gen.spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue;
        if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
        if (std.mem.eql(u8, rule.token, "integer") or std.mem.eql(u8, rule.token, "real")) {
            if (patterns.parseCharClass(rule.pattern)) |cc| {
                for (0..256) |c| {
                    if (cc.chars[c]) digitChars[c] = true;
                }
            }
        }
    }

    const ident = try patterns.collectIdentRules(gen.spec);
    for (ident.rules[0..ident.count]) |r| {
        for (0..256) |c| {
            if (r.startChars[c]) letterChars[c] = true;
        }
    }

    // IDENT_EXTRA = continuation chars that aren't letters or digits.
    // E.g. Slash's `[\w./-]` yields extras `{'.', '/', '-'}`. Grammars
    // whose continuation is `[\w]` yield an empty extra set.
    for (ident.rules[0..ident.count]) |r| {
        if (!r.hasCont) continue;
        for (0..256) |c| {
            if (!r.contChars[c]) continue;
            if (letterChars[c]) continue;
            if (digitChars[c]) continue;
            identExtraChars[c] = true;
        }
    }
    // Also absorb punct-ident rule continuation chars — but only for
    // UNGUARDED rules. Guarded rules (e.g. Slash's globs with
    // `@ math == 0`) introduce chars like `*` and `?` that must not
    // leak into the globally-shared isIdentChar helper. Those rules
    // emit their own per-rule continuation checks in the pre-switch
    // dispatch.
    const punctIdent = try patterns.collectPunctIdentRules(gen.spec);
    for (punctIdent.rules[0..punctIdent.count]) |r| {
        if (r.guards.len > 0) continue;
        for (0..256) |c| {
            if (!r.contChars[c]) continue;
            if (letterChars[c]) continue;
            if (digitChars[c]) continue;
            identExtraChars[c] = true;
        }
    }
    var hasIdentExtra = false;
    for (0..256) |c| {
        if (identExtraChars[c]) {
            hasIdentExtra = true;
            break;
        }
    }

    // Emit the char_flags table
    try gen.write(
        \\    // Character classification flags (generated from grammar patterns)
        \\    const DIGIT: u8 = 1 << 0;
        \\    const LETTER: u8 = 1 << 1;
        \\    const WHITESPACE: u8 = 1 << 2;
    );
    if (hasIdentExtra) try gen.write(
        \\
        \\    const IDENT_EXTRA: u8 = 1 << 3;
    );
    try gen.write(
        \\
        \\
        \\    const charFlags: [256]u8 = blk: {
        \\        var table: [256]u8 = [_]u8{0} ** 256;
        \\
    );

    // Emit DIGIT entries
    var hasDigitRange = true;
    for ('0'..('9' + 1)) |c| {
        if (!digitChars[c]) {
            hasDigitRange = false;
            break;
        }
    }
    if (hasDigitRange) {
        try gen.write("        for ('0'..'9' + 1) |c| table[c] = DIGIT;\n");
    } else {
        for (0..256) |c| {
            if (digitChars[c]) {
                const lit = patterns.charToZigLiteral(@intCast(c));
                try gen.print("        table['{s}'] = DIGIT;\n", .{lit.buf[0..lit.len]});
            }
        }
    }

    // Emit LETTER entries — check for standard ranges first
    var hasUpper = true;
    var hasLower = true;
    for ('A'..('Z' + 1)) |c| {
        if (!letterChars[c]) {
            hasUpper = false;
            break;
        }
    }
    for ('a'..('z' + 1)) |c| {
        if (!letterChars[c]) {
            hasLower = false;
            break;
        }
    }

    if (hasUpper) try gen.write("        for ('A'..'Z' + 1) |c| table[c] = LETTER;\n");
    if (hasLower) try gen.write("        for ('a'..'z' + 1) |c| table[c] = LETTER;\n");

    // Emit individual LETTER chars outside standard ranges
    for (0..256) |c| {
        if (!letterChars[c]) continue;
        if (hasUpper and c >= 'A' and c <= 'Z') continue;
        if (hasLower and c >= 'a' and c <= 'z') continue;
        const lit = patterns.charToZigLiteral(@intCast(c));
        try gen.print("        table['{s}'] = LETTER;\n", .{lit.buf[0..lit.len]});
    }

    // Emit IDENT_EXTRA entries for continuation chars outside letter/digit.
    // These are the `./–` in `[\w./-]` that mainline isIdentChar doesn't cover.
    for (0..256) |c| {
        if (identExtraChars[c]) {
            const lit = patterns.charToZigLiteral(@intCast(c));
            try gen.print("        table['{s}'] = IDENT_EXTRA;\n", .{lit.buf[0..lit.len]});
        }
    }

    // Whitespace is always space + tab
    try gen.write(
        \\        table[' '] = WHITESPACE;
        \\        table['\t'] = WHITESPACE;
        \\        break :blk table;
        \\    };
        \\
        \\    inline fn isDigit(c: u8) bool {
        \\        return (charFlags[c] & DIGIT) != 0;
        \\    }
        \\
        \\    inline fn isLetter(c: u8) bool {
        \\        return (charFlags[c] & LETTER) != 0;
        \\    }
        \\
        \\    inline fn isWhitespace(c: u8) bool {
        \\        return (charFlags[c] & WHITESPACE) != 0;
        \\    }
        \\
        \\
    );
    if (hasIdentExtra) {
        try gen.write(
            \\    inline fn isIdentChar(c: u8) bool {
            \\        return (charFlags[c] & (LETTER | DIGIT | IDENT_EXTRA)) != 0;
            \\    }
            \\
        );
    } else {
        try gen.write(
            \\    inline fn isIdentChar(c: u8) bool {
            \\        return isLetter(c) or isDigit(c);
            \\    }
            \\
        );
    }
}

pub fn generateScannerDispatch(gen: *LexerGenerator) !void {
    // Derive dispatch conditions from grammar patterns
    var hasNumber = false;
    var numberHasLeadingDot = false;
    var hasIdent = false;

    // Collect string patterns (heredocs are handled by the language wrapper, not the engine)
    const StringInfo = struct { openChar: u8, token: []const u8, useDoubledEscape: bool };
    var stringInfos: [4]StringInfo = undefined;
    var stringInfoCount: usize = 0;

    for (gen.spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue;

        const isStringTok = std.mem.eql(u8, rule.token, "string") or
            std.mem.startsWith(u8, rule.token, "string_");
        if (isStringTok) {
            if (rule.pattern.len >= 3 and (rule.pattern[0] == '\'' or rule.pattern[0] == '"')) {
                if (rule.pattern[1] != rule.pattern[0]) {
                    if (stringInfoCount < stringInfos.len) {
                        const delim = rule.pattern[0]; // grammar quote delimiter
                        const openChar = rule.pattern[1]; // actual string delimiter in target language
                        const quotedDoubled = [4]u8{ delim, openChar, openChar, delim };
                        stringInfos[stringInfoCount] = .{
                            .openChar = openChar,
                            .token = rule.token,
                            .useDoubledEscape = std.mem.indexOf(u8, rule.pattern, &quotedDoubled) != null,
                        };
                        stringInfoCount += 1;
                    } else {
                        @panic("too many string token patterns (max 4)");
                    }
                }
            }
        }
        if (std.mem.eql(u8, rule.token, "integer") or
            std.mem.eql(u8, rule.token, "real"))
        {
            hasNumber = true;
            if (std.mem.indexOf(u8, rule.pattern, "'.'") != null and
                rule.pattern.len > 0 and rule.pattern[0] == '[')
            {
                const cc = patterns.parseCharClass(rule.pattern);
                if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.endPos..], "* '.'"))
                    numberHasLeadingDot = true;
            }
        }
        if (std.mem.eql(u8, rule.token, "ident") and rule.pattern.len > 0 and rule.pattern[0] == '[') {
            hasIdent = true;
        }
    }

    // String token types
    for (stringInfos[0..stringInfoCount]) |si| {
        const lit = patterns.charToZigLiteral(si.openChar);
        const litStr = lit.buf[0..lit.len];

        try gen.print(
            \\        if (c == '{s}') {{
        , .{litStr});

        // One escape strategy per string rule: doubled-delimiter or backslash.
        // Grammars needing both should use a lang module Lexer wrapper.
        if (si.useDoubledEscape) {
            // Doubled-quote escape (e.g. '' or ""), stop on \n
            try gen.print(
                \\            self.pos += 1;
                \\            while (self.pos < self.source.len) {{
                \\                const ch = self.source[self.pos];
                \\                if (ch == '{s}') {{
                \\                    self.pos += 1;
                \\                    if (self.pos < self.source.len and self.source[self.pos] == '{s}') {{ self.pos += 1; continue; }}
                \\                    return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\                }}
                \\                if (ch == '\n') break;
                \\                self.pos += 1;
                \\            }}
                \\            return Token{{ .cat = .@"err", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\        }}
                \\
            , .{ litStr, litStr, si.token });
        } else {
            // Backslash escape, stop on \n
            try gen.print(
                \\            self.pos += 1;
                \\            while (self.pos < self.source.len) {{
                \\                const ch = self.source[self.pos];
                \\                if (ch == '{s}') {{
                \\                    self.pos += 1;
                \\                    return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\                }}
                \\                if (ch == '\\') {{ self.pos += 2; continue; }}
                \\                if (ch == '\n') break;
                \\                self.pos += 1;
                \\            }}
                \\            return Token{{ .cat = .@"err", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\        }}
                \\
            , .{ litStr, si.token });
        }
    }

    // Compound-literal rules like Slash's `flag` (`'-' '-'? [a-zA-Z]...`).
    // The leading literal overlaps with a single-char operator (`-` =>
    // minus), so these must dispatch first and restore pos on no-match.
    try generateCompoundLiteralDispatch(gen);

    // Punctuation-start ident rules (paths, globs) — must dispatch BEFORE
    // the number/ident/operator layers so the start char doesn't get
    // consumed by a single-char operator arm. Each rule has its own start
    // class, continuation class, and guards. Falls through cleanly when
    // guards fail or the continuation doesn't match.
    try generatePunctIdentDispatch(gen);

    if (hasNumber) {
        // Detect digits that also start multi-char operator rules (e.g. '2>' in slash).
        // Without this, the digit fast-path consumes '2' into scanNumber before the
        // operator switch gets a chance to dispatch the '2>' family.
        var digitHasOpArm: [10]bool = @splat(false);
        var anyDigitOpArm = false;
        for (gen.spec.rules.items) |rule| {
            const info = patterns.parseLiteralPattern(rule.pattern) orelse continue;
            if (info.len <= 1) continue; // single-char digit token is fine; fast-path handles it
            const fc = info.chars[0];
            if (fc >= '0' and fc <= '9') {
                digitHasOpArm[fc - '0'] = true;
                anyDigitOpArm = true;
            }
        }

        // Header comment
        if (numberHasLeadingDot) {
            try gen.write("        // Number (digit or leading dot followed by digit)\n");
        } else {
            try gen.write("        // Number\n");
        }

        // Fast-path guard. If any digit is also the start of a multi-char
        // operator rule (e.g. '2>' in slash), exclude those digits from
        // the fast-path so the operator switch's arm gets to dispatch.
        // The switch's digit arm has a `self.pos -= 1; scanNumber()`
        // fallback, so a bare digit still reaches number scanning.
        try gen.write("        if (");
        if (anyDigitOpArm) try gen.write("(");
        try gen.write("isDigit(c)");
        if (anyDigitOpArm) {
            for (0..10) |i| {
                if (digitHasOpArm[i]) {
                    try gen.print(" and c != '{d}'", .{i});
                }
            }
            try gen.write(")");
        }
        if (numberHasLeadingDot) {
            try gen.write(" or (c == '.' and self.pos + 1 < self.source.len and isDigit(self.source[self.pos + 1]))");
        }
        const nsr = try patterns.collectNumericSuffixRules(gen.spec);
        if (nsr.count > 0) {
            try gen.write(
                \\) {
                \\            const tok = self.scanNumber(start, wsCount);
                \\
            );
            try emitNumericSuffixReclassify(gen, "            ");
            try gen.write(
                \\            return tok;
                \\        }
                \\
            );
        } else {
            try gen.write(
                \\) {
                \\            return self.scanNumber(start, wsCount);
                \\        }
                \\
            );
        }
    }

    if (hasIdent) {
        try gen.write(
            \\        // Identifier
            \\        if (isLetter(c)) {
            \\            return self.scanIdent(start, wsCount);
            \\        }
            \\
        );
    }

    // Generate inline prefix scanners for complex patterns that start with a
    // literal character followed by a character class (e.g., '$' [a-zA-Z_]... → variable).
    // These must dispatch before the operator switch to avoid the prefix char being
    // consumed as a standalone operator token.
    try generatePrefixScanners(gen);
}

/// Emit post-scanNumber peek-and-reclassify for numeric-suffix rules.
/// Placed at the number fast-path call site: if scanNumber returns an
/// integer token and the following chars match the literal middle
/// (and optional class suffix) of a rule, extend pos and reclassify.
/// Longest-first so `[0-9]+ '>' '&' [0-9]+` beats `[0-9]+ '>'`.
fn emitNumericSuffixReclassify(gen: *LexerGenerator, indent: []const u8) !void {
    const nsr = try patterns.collectNumericSuffixRules(gen.spec);
    if (nsr.count == 0) return;

    // Sort: longer middle first, with-suffix before without at same length
    const sortFn = struct {
        fn lt(_: void, a: patterns.NumericSuffixRule, b: patterns.NumericSuffixRule) bool {
            if (a.middleLen != b.middleLen) return a.middleLen > b.middleLen;
            if (a.hasSuffix != b.hasSuffix) return a.hasSuffix and !b.hasSuffix;
            return false;
        }
    }.lt;

    var sorted = nsr.rules;
    std.mem.sort(patterns.NumericSuffixRule, sorted[0..nsr.count], {}, sortFn);

    try gen.print("{s}if (tok.cat == .@\"integer\") {{\n", .{indent});
    for (sorted[0..nsr.count]) |r| {
        const middleLen: u32 = r.middleLen;
        const minLen: u32 = middleLen + (if (r.hasSuffix) @as(u32, 1) else @as(u32, 0));

        try gen.print("{s}    if (self.pos + {d} <= self.source.len", .{ indent, minLen });
        for (0..r.middleLen) |mi| {
            const ml = patterns.charToZigLiteral(r.middle[mi]);
            try gen.print(" and self.source[self.pos + {d}] == '{s}'", .{ mi, ml.buf[0..ml.len] });
        }
        if (r.hasSuffix) {
            var ix: [64]u8 = undefined;
            const ixStr = try std.fmt.bufPrint(&ix, "self.source[self.pos + {d}]", .{r.middleLen});
            try gen.write(" and (");
            try gen.emitCharSetCondition(r.suffixClass, ixStr);
            try gen.write(")");
        }
        try gen.print(") {{\n{s}        self.pos += {d};\n", .{ indent, minLen });
        if (r.hasSuffix) {
            try gen.print("{s}        while (self.pos < self.source.len and (", .{indent});
            try gen.emitCharSetCondition(r.suffixClass, "self.source[self.pos]");
            try gen.write(")) self.pos += 1;\n");
        }
        try gen.print(
            "{s}        return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n{s}    }}\n",
            .{ indent, r.token, indent },
        );
    }
    try gen.print("{s}}}\n", .{indent});
}

/// Emit pre-switch dispatch for rules of shape:
///     'X' 'X'? [class] [class]* ('=' [class]*)?  → token
/// Example: Slash's flag rule `'-' '-'? [a-zA-Z][a-zA-Z0-9_-]* ('=' [\w./:@,+-]*)?`.
/// The leading literal is required; the second literal is optional;
/// what follows must be an alpha-class char then a continuation class;
/// the tail `('=' [class]*)?` is optional. On no-match, pos is restored
/// and control falls through cleanly.
fn generateCompoundLiteralDispatch(gen: *LexerGenerator) !void {
    for (gen.spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue; // only unguarded for now
        const p = rule.pattern;
        if (p.len < 11) continue; // minimum: 'X' 'X'? [A][B]*
        if (p[0] != '\'' or p[2] != '\'') continue;
        const firstChar = p[1];

        // Skip chars handled elsewhere (string delimiters, comment, etc).
        if (firstChar == '\'' or firstChar == '"') continue;
        if ((firstChar >= '0' and firstChar <= '9')) continue;
        if ((firstChar >= 'a' and firstChar <= 'z') or
            (firstChar >= 'A' and firstChar <= 'Z') or firstChar == '_') continue;

        var pos: usize = 3;
        while (pos < p.len and p[pos] == ' ') pos += 1;

        // Optional second literal: 'X'?
        var hasSecondLit = false;
        var secondChar: u8 = 0;
        if (pos + 3 < p.len and p[pos] == '\'' and p[pos + 2] == '\'' and p[pos + 3] == '?') {
            secondChar = p[pos + 1];
            hasSecondLit = true;
            pos += 4;
            while (pos < p.len and p[pos] == ' ') pos += 1;
        }
        if (!hasSecondLit) continue; // this function handles compound-literal only

        // First char class [alpha_class]
        if (pos >= p.len or p[pos] != '[') continue;
        const startCC = patterns.parseCharClass(p[pos..]) orelse continue;
        pos += startCC.endPos;
        while (pos < p.len and p[pos] == ' ') pos += 1;

        // Continuation class [cont_class]* or [cont_class]+
        if (pos >= p.len or p[pos] != '[') continue;
        const contCC = patterns.parseCharClass(p[pos..]) orelse continue;
        pos += contCC.endPos;
        if (pos >= p.len or (p[pos] != '*' and p[pos] != '+')) continue;
        pos += 1;
        while (pos < p.len and p[pos] == ' ') pos += 1;

        // Optional tail group: ('=' [val_class]*)?
        var hasTail = false;
        var tailSep: u8 = 0;
        var tailCC: ?struct { chars: [256]bool, endPos: usize } = null;
        if (pos < p.len and p[pos] == '(') {
            pos += 1;
            while (pos < p.len and p[pos] == ' ') pos += 1;
            if (pos + 2 < p.len and p[pos] == '\'' and p[pos + 2] == '\'') {
                tailSep = p[pos + 1];
                pos += 3;
                while (pos < p.len and p[pos] == ' ') pos += 1;
                if (pos < p.len and p[pos] == '[') {
                    if (patterns.parseCharClass(p[pos..])) |tcc| {
                        pos += tcc.endPos;
                        if (pos < p.len and (p[pos] == '*' or p[pos] == '+')) {
                            pos += 1;
                            while (pos < p.len and p[pos] == ' ') pos += 1;
                            if (pos < p.len and p[pos] == ')') {
                                pos += 1;
                                if (pos < p.len and p[pos] == '?') {
                                    hasTail = true;
                                    tailCC = .{ .chars = tcc.chars, .endPos = 0 };
                                }
                            }
                        }
                    }
                }
            }
        }

        // Emit the dispatch
        const lit = patterns.charToZigLiteral(firstChar);
        const litStr = lit.buf[0..lit.len];
        try gen.print(
            \\        // Compound-literal rule for .@"{s}"
            \\        if (c == '{s}') {{
            \\            const save = self.pos;
            \\            self.pos += 1;
            \\
        , .{ rule.token, litStr });

        if (hasSecondLit) {
            const sl = patterns.charToZigLiteral(secondChar);
            try gen.print(
                \\            if (self.pos < self.source.len and self.source[self.pos] == '{s}') self.pos += 1;
                \\
            , .{sl.buf[0..sl.len]});
        }

        // Require at least one char from the start class
        try gen.write("            if (self.pos < self.source.len and (");
        try gen.emitCharSetCondition(startCC.chars, "self.source[self.pos]");
        try gen.write(")) {\n");
        try gen.write("                self.pos += 1;\n");
        try gen.write("                while (self.pos < self.source.len and (");
        try gen.emitCharSetCondition(contCC.chars, "self.source[self.pos]");
        try gen.write(")) self.pos += 1;\n");

        if (hasTail) {
            const ts = patterns.charToZigLiteral(tailSep);
            try gen.print(
                \\                if (self.pos < self.source.len and self.source[self.pos] == '{s}') {{
                \\                    self.pos += 1;
                \\                    while (self.pos < self.source.len and (
            , .{ts.buf[0..ts.len]});
            try gen.emitCharSetCondition(tailCC.?.chars, "self.source[self.pos]");
            try gen.write(
                \\)) self.pos += 1;
                \\                }
                \\
            );
        }

        try gen.print(
            \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
            \\            }}
            \\            self.pos = save;
            \\        }}
            \\
        , .{rule.token});
    }
}

/// Emit pre-switch dispatch for punct-start ident rules. Each rule peeks
/// the next char for continuation-class membership before committing. If
/// guards or continuation check fails, control falls through to the
/// remaining scanner stages without consuming any input.
fn generatePunctIdentDispatch(gen: *LexerGenerator) !void {
    const punct = try patterns.collectPunctIdentRules(gen.spec);
    if (punct.count == 0) return;

    try gen.write(
        \\        // Punct-start ident rules (paths, globs)
        \\
    );

    for (punct.rules[0..punct.count]) |r| {
        // Emit start-char test: `if (c == x or c == y or ...)`
        try gen.write("        if (");
        var first = true;
        for (0..256) |c| {
            if (!r.startChars[c]) continue;
            if (!first) try gen.write(" or ");
            const lit = patterns.charToZigLiteral(@intCast(c));
            try gen.print("c == '{s}'", .{lit.buf[0..lit.len]});
            first = false;
        }
        try gen.write(") {\n");

        // Optional guards. Emitted as a nested `if` that falls through
        // (does nothing, no consumption) when the guard evaluates false.
        if (r.guards.len > 0) {
            try gen.write("            if (");
            try gen.emitAllGuards(r.guards);
            try gen.write(") {\n");
        }

        const inner = if (r.guards.len > 0) "                " else "            ";

        // For `+` quantifier: require at least one continuation char
        // before committing. Emit a pre-commit peek gate; if it fails,
        // control falls through without consuming the leader.
        // For `*` quantifier: commit unconditionally — the start-char
        // match plus any guard is sufficient; the while-loop naturally
        // handles zero-or-more continuation.
        //
        // We emit literal membership checks rather than using the shared
        // isIdentChar helper, so guarded rules with rare continuation
        // chars (e.g. globs with '*', '?') don't pollute the shared
        // continuation set.
        if (r.requireOne) {
            try gen.print("{s}const nc = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;\n", .{inner});
            try gen.print("{s}if (", .{inner});
            try gen.emitCharSetCondition(r.contChars, "nc");
            try gen.print(") {{\n", .{});
        }

        const body = if (r.requireOne)
            (if (r.guards.len > 0) "                    " else "                ")
        else
            inner;
        try gen.print("{s}self.pos += 1;\n{s}while (self.pos < self.source.len and (", .{ body, body });
        try gen.emitCharSetCondition(r.contChars, "self.source[self.pos]");
        try gen.print(")) self.pos += 1;\n{s}return Token{{ .cat = .@\"{s}\", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};\n", .{ body, r.token });

        if (r.requireOne) try gen.print("{s}}}\n", .{inner});

        // Close guard block if present
        if (r.guards.len > 0) try gen.write("            }\n");
        // Close outer start-char block
        try gen.write("        }\n");
    }
}

fn generatePrefixScanners(gen: *LexerGenerator) !void {
    // Find rules like: '$' [a-zA-Z_]... → variable, '$' '{' ... → var_braced
    // Group by prefix character
    var emittedPrefixes: [256]bool = @splat(false);

    for (gen.spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue;
        if (rule.pattern.len < 5) continue;

        // Match pattern: 'X' followed by character class or literal
        if (rule.pattern[0] != '\'') continue;
        if (rule.pattern[2] != '\'') continue;
        const prefixChar = rule.pattern[1];

        // Skip if this prefix is handled by string/number/ident/comment scanners
        if (prefixChar == '"' or prefixChar == '\'') continue;
        if (prefixChar >= '0' and prefixChar <= '9') continue;
        if ((prefixChar >= 'a' and prefixChar <= 'z') or
            (prefixChar >= 'A' and prefixChar <= 'Z') or prefixChar == '_' or prefixChar == '%') continue;
        // Skip comment start chars and flag chars (handled elsewhere)
        if (std.mem.eql(u8, rule.token, "comment")) continue;
        if (std.mem.eql(u8, rule.token, "skip")) continue;

        // Must have a 2nd part that's a character class or literal (not just [^\n]*)
        const rest = rule.pattern[3..];
        const trimmed = std.mem.trimStart(u8, rest, " ");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '[' and trimmed.len > 1 and trimmed[1] == '^') continue; // negated class like [^\n]

        if (emittedPrefixes[prefixChar]) continue;

        // Collect all rules with this prefix
        const PrefixRule = struct { pattern: []const u8, token: []const u8, actions: []const Action };
        var prefixRules: [32]PrefixRule = undefined;
        var prefixCount: usize = 0;

        for (gen.spec.rules.items) |r| {
            if (r.guards.len > 0) continue;
            if (r.pattern.len < 5) continue;
            if (r.pattern[0] != '\'' or r.pattern[2] != '\'') continue;
            if (r.pattern[1] != prefixChar) continue;
            if (prefixCount < prefixRules.len) {
                prefixRules[prefixCount] = .{ .pattern = r.pattern, .token = r.token, .actions = r.actions };
                prefixCount += 1;
            }
        }

        if (prefixCount == 0) continue;
        emittedPrefixes[prefixChar] = true;

        const lit = patterns.charToZigLiteral(prefixChar);
        const litStr = lit.buf[0..lit.len];

        // Pre-scan: determine if any prefix rule will emit code that references nc
        var needsNc = false;
        for (prefixRules[0..prefixCount]) |pr| {
            const prSuffix = std.mem.trimStart(u8, pr.pattern[3..], " ");
            if (prSuffix.len > 3 and prSuffix[0] == '\'') {
                // Literal second char: only emits nc if followed by [^ (scan-to-close pattern)
                if (std.mem.indexOf(u8, prSuffix[3..], "'")) |closeIdx| {
                    const endPat = prSuffix[3..][0..closeIdx];
                    if (endPat.len >= 3 and endPat[0] == ' ' and endPat[1] == '[' and endPat[2] == '^') {
                        needsNc = true;
                        break;
                    }
                }
            } else if (prSuffix.len >= 1 and prSuffix[0] == '[') {
                needsNc = true;
                break;
            }
        }

        if (!needsNc) continue; // no checks would be emitted for this prefix

        try gen.print("        if (c == '{s}') {{\n", .{litStr});
        try gen.write("            const nc = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;\n");

        // Emit checks for each rule's second character condition
        for (prefixRules[0..prefixCount]) |pr| {
            // Parse what follows the prefix literal in the pattern
            const prRest = pr.pattern[3..]; // after 'X'
            const prTrimmed = std.mem.trimStart(u8, prRest, " ");

            if (prTrimmed.len >= 3 and prTrimmed[0] == '\'') {
                // Second literal: '$' '{' → scan until matching close
                const secondChar = prTrimmed[1];
                const scLit = patterns.charToZigLiteral(secondChar);
                const scStr = scLit.buf[0..scLit.len];

                // Find the closing delimiter
                if (std.mem.indexOf(u8, prTrimmed[3..], "'")) |closeIdx| {
                    const endPattern = prTrimmed[3..][0..closeIdx];
                    if (endPattern.len >= 3 and endPattern[0] == ' ' and endPattern[1] == '[' and endPattern[2] == '^') {
                        // Pattern: '$' '{' [^}\n]+ '}' → scan to closing char
                        if (std.mem.indexOf(u8, endPattern[3..], "]") == null) continue;
                        // Find the close delimiter from the end of the pattern
                        if (std.mem.lastIndexOf(u8, pr.pattern, "'")) |li| {
                            if (li > 3) {
                                const closeCh = pr.pattern[li - 1];
                                const clLit = patterns.charToZigLiteral(closeCh);
                                const clStr = clLit.buf[0..clLit.len];
                                try gen.print(
                                    \\            if (nc == '{s}') {{
                                    \\                self.pos += 2;
                                    \\                while (self.pos < self.source.len and self.source[self.pos] != '{s}' and self.source[self.pos] != '\n') self.pos += 1;
                                    \\                if (self.pos < self.source.len and self.source[self.pos] == '{s}') self.pos += 1;
                                    \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                                    \\            }}
                                    \\
                                , .{ scStr, clStr, clStr, pr.token });
                            }
                        }
                    }
                }
            } else if (prTrimmed.len >= 1 and prTrimmed[0] == '[') {
                // Character class: '$' [a-zA-Z_] → scan identifier-like
                // Check what chars are in the class
                const hasAlpha = std.mem.indexOf(u8, prTrimmed, "a-z") != null or
                    std.mem.indexOf(u8, prTrimmed, "A-Z") != null;
                const hasDigit = std.mem.indexOf(u8, prTrimmed, "0-9") != null;
                const hasSpecial = std.mem.indexOf(u8, prTrimmed, "?$!#*") != null;

                if (hasAlpha) {
                    // $name pattern: letter/underscore followed by alphanum
                    try gen.print(
                        \\            if ((nc >= 'a' and nc <= 'z') or (nc >= 'A' and nc <= 'Z') or nc == '_') {{
                        \\                self.pos += 1;
                        \\                while (self.pos < self.source.len) {{
                        \\                    const vc = self.source[self.pos];
                        \\                    if (!((vc >= 'a' and vc <= 'z') or (vc >= 'A' and vc <= 'Z') or (vc >= '0' and vc <= '9') or vc == '_')) break;
                        \\                    self.pos += 1;
                        \\                }}
                        \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                        \\            }}
                        \\
                    , .{pr.token});
                } else if (hasDigit) {
                    // $0-$9 pattern
                    try gen.print(
                        \\            if (nc >= '0' and nc <= '9') {{
                        \\                self.pos += 2;
                        \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = 2 }};
                        \\            }}
                        \\
                    , .{pr.token});
                } else if (hasSpecial) {
                    // $?, $$, $!, $#, $*
                    try gen.print(
                        \\            if (nc == '?' or nc == '$' or nc == '!' or nc == '#' or nc == '*') {{
                        \\                self.pos += 2;
                        \\                return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = 2 }};
                        \\            }}
                        \\
                    , .{pr.token});
                }
            }
        }

        try gen.write("        }\n");
    }
}

pub fn generateScanners(gen: *LexerGenerator) !void {
    try generateNumberScanner(gen);
    try generateIdentScanner(gen);
}

fn generateNumberScanner(gen: *LexerGenerator) !void {
    // Analyze number patterns to detect features
    var hasDecimal = false;
    var hasExponent = false;
    var hasLeadingDot = false;
    for (gen.spec.rules.items) |rule| {
        if (std.mem.eql(u8, rule.token, "real")) {
            if (std.mem.indexOf(u8, rule.pattern, "'.'") != null) hasDecimal = true;
            if (std.mem.indexOf(u8, rule.pattern, "[Ee]") != null or
                std.mem.indexOf(u8, rule.pattern, "[eE]") != null) hasExponent = true;
            if (rule.pattern.len > 0 and rule.pattern[0] == '[') {
                const cc = patterns.parseCharClass(rule.pattern);
                if (cc != null and std.mem.startsWith(u8, rule.pattern[cc.?.endPos..], "* '.'"))
                    hasLeadingDot = true;
            }
        }
    }

    // Check if any number patterns exist
    var hasAny = false;
    for (gen.spec.rules.items) |rule| {
        if (std.mem.eql(u8, rule.token, "integer") or
            std.mem.eql(u8, rule.token, "real"))
        {
            hasAny = true;
            break;
        }
    }
    if (!hasAny) return;

    try gen.write(
        \\
        \\    /// Scan number (generated from grammar)
        \\    fn scanNumber(self: *Self, start: u32, ws: u8) Token {
    );

    if (hasDecimal) {
        try gen.write(
            \\        var hasDecimal = false;
        );
    }
    if (hasExponent) {
        try gen.write(
            \\        var hasExponent = false;
        );
    }
    if (hasLeadingDot) {
        try gen.write(
            \\        const startsWithDot = self.source[self.pos] == '.';
        );
    }

    // Check for grammar-defined number prefix patterns (e.g., 0x hex, 0b binary, 0o octal)
    const hasPrefixed = hasNumberPrefixPatterns(gen);
    if (hasPrefixed) {
        try gen.write(
            \\
            \\        // Number prefix patterns (from grammar)
            \\        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            \\            const prefix = self.source[self.pos + 1];
            \\
        );
        try emitNumberPrefixBranches(gen);
        try gen.write(
            \\        }
            \\
        );
    }

    // Integer part
    try gen.write(
        \\        // Decimal integer
        \\        if (isDigit(self.source[self.pos])) {
        \\            while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
        \\                self.pos += 1;
        \\            }
        \\        }
        \\
    );

    // Decimal part
    if (hasDecimal) {
        try gen.write(
            \\        // Decimal part
            \\        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            \\            const nextC = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;
            \\            if (isDigit(nextC)) {
            \\                hasDecimal = true;
            \\                self.pos += 1;
            \\                while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
            \\                    self.pos += 1;
            \\                }
            \\            }
            \\        }
            \\
        );
    }

    // Exponent part
    if (hasExponent) {
        try gen.write(
            \\        // Exponent part
            \\        if (self.pos < self.source.len) {
            \\            const e = self.source[self.pos];
            \\            if (e == 'E' or e == 'e') {
            \\                var expPos = self.pos + 1;
            \\                if (expPos < self.source.len and (self.source[expPos] == '+' or self.source[expPos] == '-')) {
            \\                    expPos += 1;
            \\                }
            \\                if (expPos < self.source.len and isDigit(self.source[expPos])) {
            \\                    hasExponent = true;
            \\                    self.pos = expPos;
            \\                    while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
            \\                        self.pos += 1;
            \\                    }
            \\                }
            \\            }
            \\        }
            \\
        );
    }

    // Classification
    if (hasDecimal or hasExponent or hasLeadingDot) {
        try gen.write("        // Classify\n");
        try gen.write("        const tokenCat: TokenCat = ");

        if (hasDecimal or hasExponent or hasLeadingDot) {
            try gen.write("if (");
            var firstCond = true;
            if (hasDecimal) {
                try gen.write("hasDecimal");
                firstCond = false;
            }
            if (hasExponent) {
                if (!firstCond) try gen.write(" or ");
                try gen.write("hasExponent");
                firstCond = false;
            }
            if (hasLeadingDot) {
                if (!firstCond) try gen.write(" or ");
                try gen.write("startsWithDot");
            }
            try gen.write(")\n            .@\"real\"\n");
            try gen.write("        else\n            .@\"integer\";\n");
        }

        try gen.write(
            \\
            \\        return Token{ .cat = tokenCat, .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
            \\    }
            \\
        );
    } else {
        try gen.write(
            \\        return Token{ .cat = .@"integer", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
            \\    }
            \\
        );
    }
}

/// Check if grammar defines number prefix patterns like '0' [xX] ...
fn hasNumberPrefixPatterns(gen: *LexerGenerator) bool {
    for (gen.spec.rules.items) |rule| {
        if (!std.mem.eql(u8, rule.token, "integer")) continue;
        if (rule.pattern.len >= 5 and rule.pattern[0] == '\'' and
            rule.pattern[1] == '0' and rule.pattern[2] == '\'')
            return true;
    }
    return false;
}

/// Emit prefix branches for grammar-defined patterns like '0' [xX] [0-9a-fA-F]+
fn emitNumberPrefixBranches(gen: *LexerGenerator) !void {
    var first = true;
    for (gen.spec.rules.items) |rule| {
        if (!std.mem.eql(u8, rule.token, "integer")) continue;
        if (rule.pattern.len < 5 or rule.pattern[0] != '\'' or
            rule.pattern[1] != '0' or rule.pattern[2] != '\'') continue;

        // Parse: '0' [xXbBoO] [digit-class]+
        const rest = std.mem.trimStart(u8, rule.pattern[3..], " ");
        if (rest.len < 3 or rest[0] != '[') continue;
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse continue;
        const charClass = rest[1..close];
        const digitPart = std.mem.trimStart(u8, rest[close + 1 ..], " ");

        // Build condition for prefix char
        if (!first) {
            try gen.write("            else ");
        } else {
            try gen.write("            ");
            first = false;
        }
        try gen.write("if (");
        var firstCond = true;
        var i: usize = 0;
        while (i < charClass.len) {
            if (!firstCond) try gen.write(" or ");
            firstCond = false;
            try gen.print("prefix == '{c}'", .{charClass[i]});
            i += 1;
        }
        try gen.write(") {\n");
        try gen.write("                self.pos += 2;\n");

        // Build digit scanning loop from the digit class pattern
        if (digitPart.len > 0 and digitPart[0] == '[') {
            const dclose = std.mem.indexOfScalar(u8, digitPart, ']') orelse continue;
            const dclass = digitPart[1..dclose];
            try gen.write("                while (self.pos < self.source.len) {\n");
            try gen.write("                    const dc = self.source[self.pos];\n");
            try gen.write("                    if (");
            // Parse ranges in digit class
            var di: usize = 0;
            var firstDc = true;
            while (di < dclass.len) {
                if (di + 2 < dclass.len and dclass[di + 1] == '-') {
                    if (!firstDc) try gen.write(" or ");
                    firstDc = false;
                    try gen.print("(dc >= '{c}' and dc <= '{c}')", .{ dclass[di], dclass[di + 2] });
                    di += 3;
                } else {
                    if (!firstDc) try gen.write(" or ");
                    firstDc = false;
                    try gen.print("dc == '{c}'", .{dclass[di]});
                    di += 1;
                }
            }
            try gen.write(" or dc == '_'");
            try gen.write(") {\n");
            try gen.write("                        self.pos += 1;\n");
            try gen.write("                    } else break;\n");
            try gen.write("                }\n");
        }

        try gen.write("                return Token{ .cat = .@\"integer\", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };\n");
        try gen.write("            }\n");
    }
}

fn generateIdentScanner(gen: *LexerGenerator) !void {
    const ident = try patterns.collectIdentRules(gen.spec);
    const identRules = ident.rules;
    const identCount = ident.count;

    // Emit body loop
    try gen.write(
        \\
        \\    /// Scan identifier (generated from grammar)
        \\    fn scanIdent(self: *Self, start: u32, ws: u8) Token {
        \\        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
        \\            self.pos += 1;
        \\        }
        \\
    );

    // Check for non-ident tokens that need first-char discrimination
    var hasAltTokens = false;
    for (identRules[0..identCount]) |r| {
        if (!std.mem.eql(u8, r.token, "ident")) {
            hasAltTokens = true;
            break;
        }
    }

    if (hasAltTokens) {
        try gen.write("        const first = self.source[start];\n");
        for (identRules[0..identCount]) |r| {
            if (std.mem.eql(u8, r.token, "ident")) continue;

            try gen.write("        if (");
            try gen.emitCharSetCondition(r.startChars, "first");

            try gen.write(") {\n");
            if (r.hasSuffix) try emitIdentSuffix(gen, r.suffixChars, "            ");

            try gen.print("            return Token{{ .cat = .@\"{s}\", .pre = ws, .pos = start, .len = @intCast(self.pos - start) }};\n", .{r.token});
            try gen.write("        }\n");
        }
    }

    // Suffix handling for the ident rule
    for (identRules[0..identCount]) |r| {
        if (std.mem.eql(u8, r.token, "ident") and r.hasSuffix) {
            try emitIdentSuffix(gen, r.suffixChars, "        ");
            break;
        }
    }

    try gen.write(
        \\        return Token{ .cat = .@"ident", .pre = ws, .pos = start, .len = @intCast(self.pos - start) };
        \\    }
        \\
    );
}

fn emitIdentSuffix(gen: *LexerGenerator, suffixChars: [256]bool, indent: []const u8) !void {
    var chars: [8]u8 = undefined;
    var n: usize = 0;
    for (0..256) |c| {
        if (suffixChars[c]) {
            if (n >= chars.len) {
                diag.err("too many suffix characters (max {d})", .{chars.len});
                return error.Overflow;
            }
            chars[n] = @intCast(c);
            n += 1;
        }
    }
    if (n == 0) return;

    try gen.print("{s}if (self.pos < self.source.len and ", .{indent});
    if (n == 1) {
        const lit = patterns.charToZigLiteral(chars[0]);
        try gen.print("self.source[self.pos] == '{s}')\n", .{lit.buf[0..lit.len]});
    } else {
        try gen.write("(");
        for (0..n) |i| {
            if (i > 0) try gen.write(" or ");
            const lit = patterns.charToZigLiteral(chars[i]);
            try gen.print("self.source[self.pos] == '{s}'", .{lit.buf[0..lit.len]});
        }
        try gen.write("))\n");
    }
    try gen.print("{s}    self.pos += 1;\n", .{indent});
}

pub fn generateCommentHandling(gen: *LexerGenerator) !void {
    for (gen.spec.rules.items) |rule| {
        if (!std.mem.eql(u8, rule.token, "comment")) continue;

        // Extract the leading literal char from the pattern (e.g., ';' or '#')
        const startChar = blk: {
            if (rule.pattern.len >= 3 and rule.pattern[0] == '\'') {
                if (rule.pattern[1] == '\\' and rule.pattern.len >= 4)
                    break :blk switch (rule.pattern[2]) {
                        'n' => @as(u8, '\n'),
                        'r' => '\r',
                        't' => '\t',
                        '\\' => '\\',
                        '\'' => '\'',
                        else => rule.pattern[2],
                    }
                else
                    break :blk rule.pattern[1];
            }
            continue;
        };

        const startLit = patterns.charToZigLiteral(startChar);
        const startStr = startLit.buf[0..startLit.len];

        if (rule.isSimd and rule.simdChar != null) {
            const stopLit = patterns.charToZigLiteral(rule.simdChar.?);
            const stopStr = stopLit.buf[0..stopLit.len];

            try gen.print(
                \\        // Comment (SIMD accelerated, generated from grammar)
                \\        if (c == '{s}') {{
                \\            self.pos += 1;
                \\            const remaining = self.source[self.pos..];
                \\            const offset = simd.findByte(remaining, '{s}');
                \\            self.pos += @intCast(offset);
                \\            return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\        }}
                \\
            , .{ startStr, stopStr, rule.token });
        } else {
            try gen.print(
                \\        // Comment (scan to end of line)
                \\        if (c == '{s}') {{
                \\            while (self.pos < self.source.len and self.source[self.pos] != '\n') {{
                \\                self.pos += 1;
                \\            }}
                \\            return Token{{ .cat = .@"{s}", .pre = wsCount, .pos = start, .len = @intCast(self.pos - start) }};
                \\        }}
                \\
            , .{ startStr, rule.token });
        }
    }
}
