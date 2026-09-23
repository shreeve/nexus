//! Pattern-text recognizers for lexer rules: literal and character-class
//! parsing, and the rule collectors that classify rules by shape
//! (identifier-like, punctuation-led identifiers, numeric suffixes).

const std = @import("std");
const grammar = @import("../grammar.zig");
const LexerSpec = grammar.LexerSpec;
const Guard = grammar.Guard;

pub const PatternInfo = struct {
    chars: [8]u8,
    len: u8,
};

pub fn parseLiteralPattern(pattern: []const u8) ?PatternInfo {
    if (pattern.len < 3) return null;
    var info = PatternInfo{ .chars = undefined, .len = 0 };

    if (pattern[0] == '\'' or pattern[0] == '"') {
        const delim = pattern[0];
        var i: usize = 1;
        while (i < pattern.len) {
            if (pattern[i] == delim) {
                i += 1;
                const after = std.mem.trim(u8, pattern[i..], " \t");
                if (after.len != 0) return null;
                return if (info.len > 0) info else null;
            }
            if (info.len >= 8) return null;
            if (pattern[i] == '\\' and i + 1 < pattern.len) {
                info.chars[info.len] = switch (pattern[i + 1]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '\'' => '\'',
                    '"' => '"',
                    else => pattern[i + 1],
                };
                i += 2;
            } else {
                info.chars[info.len] = pattern[i];
                i += 1;
            }
            info.len += 1;
        }
        return null;
    }
    return null;
}

pub fn charToZigLiteral(c: u8) struct { buf: [4]u8, len: u8 } {
    return switch (c) {
        '\n' => .{ .buf = "\\n".* ++ .{ 0, 0 }, .len = 2 },
        '\r' => .{ .buf = "\\r".* ++ .{ 0, 0 }, .len = 2 },
        '\t' => .{ .buf = "\\t".* ++ .{ 0, 0 }, .len = 2 },
        '\\' => .{ .buf = "\\\\".* ++ .{ 0, 0 }, .len = 2 },
        '\'' => .{ .buf = "\\'".* ++ .{ 0, 0 }, .len = 2 },
        else => .{ .buf = .{ c, 0, 0, 0 }, .len = 1 },
    };
}

fn resolveEscape(pattern: []const u8, pos: usize) struct { ch: u8, next: usize } {
    if (pos < pattern.len and pattern[pos] == '\\' and pos + 1 < pattern.len) {
        return .{ .ch = switch (pattern[pos + 1]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            else => pattern[pos + 1],
        }, .next = pos + 2 };
    }
    return .{ .ch = pattern[pos], .next = pos + 1 };
}

pub fn parseCharClass(pattern: []const u8) ?struct { chars: [256]bool, endPos: usize } {
    if (pattern.len == 0 or pattern[0] != '[') return null;
    var chars: [256]bool = @splat(false);
    var i: usize = 1;
    const negated = i < pattern.len and pattern[i] == '^';
    if (negated) i += 1;
    while (i < pattern.len and pattern[i] != ']') {
        if (pattern[i] == '\\' and i + 1 < pattern.len) {
            switch (pattern[i + 1]) {
                'w' => {
                    for ('a'..('z' + 1)) |c| chars[c] = true;
                    for ('A'..('Z' + 1)) |c| chars[c] = true;
                    for ('0'..('9' + 1)) |c| chars[c] = true;
                    chars['_'] = true;
                    i += 2;
                    continue;
                },
                'd' => {
                    for ('0'..('9' + 1)) |c| chars[c] = true;
                    i += 2;
                    continue;
                },
                's' => {
                    chars[' '] = true;
                    chars['\t'] = true;
                    chars['\n'] = true;
                    chars['\r'] = true;
                    i += 2;
                    continue;
                },
                else => {},
            }
        }
        const first = resolveEscape(pattern, i);
        if (first.next < pattern.len and pattern[first.next] == '-' and
            first.next + 1 < pattern.len and pattern[first.next + 1] != ']')
        {
            const second = resolveEscape(pattern, first.next + 1);
            var c: u16 = first.ch;
            while (c <= second.ch) : (c += 1) chars[@intCast(c)] = true;
            i = second.next;
        } else {
            chars[first.ch] = true;
            i = first.next;
        }
    }
    if (i >= pattern.len or pattern[i] != ']') return null;
    if (negated) for (0..256) |c| {
        chars[c] = !chars[c];
    };
    return .{ .chars = chars, .endPos = i + 1 };
}

pub const IdentInfo = struct {
    token: []const u8,
    startChars: [256]bool,
    contChars: [256]bool,     // Main-loop continuation class (from [class]* or [class]+ after start)
    hasCont: bool,             // True if the rule had an explicit continuation class
    suffixChars: [256]bool,
    hasSuffix: bool,
};

pub const PunctIdentInfo = struct {
    token: []const u8,
    startChars: [256]bool,
    contChars: [256]bool,
    requireOne: bool, // true for `+` quantifier, false for `*`
    guards: []const Guard,
};

/// Collect rules of shape `[punct_class][cont_class]* → token` where the
/// start class contains no letters/underscore (pure punctuation start).
/// Examples: Slash's `[./~][\w./-]* → ident` (path-ident) and globs.
/// These rules cannot use the alpha-led ident fast-path and need their
/// own pre-switch dispatch so the start char doesn't get consumed as a
/// standalone operator. Guards are preserved verbatim.
pub fn collectPunctIdentRules(spec: *const LexerSpec) !struct {
    rules: [16]PunctIdentInfo,
    count: usize,
} {
    var result: [16]PunctIdentInfo = undefined;
    var count: usize = 0;

    for (spec.rules.items) |rule| {
        if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
        if (std.mem.eql(u8, rule.token, "integer") or
            std.mem.eql(u8, rule.token, "real") or
            std.mem.eql(u8, rule.token, "err")) continue;

        const cc = parseCharClass(rule.pattern) orelse continue;

        // Must contain at least one non-alnum-non-underscore char in the
        // start class (e.g. `.`, `/`, `~`, `*`, `?`) AND have no alpha.
        // This is the marker of a genuine punct-start rule: rules that
        // begin with `[0-9]` are number-suffixed idents, not paths.
        var hasAlpha = false;
        var hasPunct = false;
        for (0..256) |c| {
            if (!cc.chars[c]) continue;
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
                hasAlpha = true;
            } else if (c >= 0x20 and c < 0x7f and !(c >= '0' and c <= '9')) {
                hasPunct = true;
            }
        }
        if (hasAlpha) continue;
        if (!hasPunct) continue;

        // Must have [class]* or [class]+ continuation. `*` allows zero
        // continuation chars (bare leader tokenizes as len-1 ident);
        // `+` requires at least one, which becomes a pre-commit peek
        // gate in the emitted dispatch.
        var pos = cc.endPos;
        while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
        if (pos >= rule.pattern.len or rule.pattern[pos] != '[') continue;
        const cont = parseCharClass(rule.pattern[pos..]) orelse continue;
        pos += cont.endPos;
        if (pos >= rule.pattern.len or
            (rule.pattern[pos] != '*' and rule.pattern[pos] != '+')) continue;
        const requireOne = rule.pattern[pos] == '+';

        if (count >= result.len) {
            std.debug.print("error: too many punct-ident rules (max {d})\n", .{result.len});
            return error.Overflow;
        }
        result[count] = .{
            .token = rule.token,
            .startChars = cc.chars,
            .contChars = cont.chars,
            .requireOne = requireOne,
            .guards = rule.guards,
        };
        count += 1;
    }
    return .{ .rules = result, .count = count };
}

pub fn collectIdentRules(spec: *const LexerSpec) !struct { rules: [8]IdentInfo, count: usize } {
    var result: [8]IdentInfo = undefined;
    var count: usize = 0;

    for (spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue;
        if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;
        if (std.mem.eql(u8, rule.token, "integer") or
            std.mem.eql(u8, rule.token, "real") or
            std.mem.eql(u8, rule.token, "err")) continue;

        var dup = false;
        for (result[0..count]) |existing| {
            if (std.mem.eql(u8, existing.token, rule.token)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;

        const cc = parseCharClass(rule.pattern) orelse continue;

        var hasAlpha = false;
        for (0..256) |c| {
            if (cc.chars[c] and ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_')) {
                hasAlpha = true;
                break;
            }
        }
        if (!hasAlpha) continue;

        // Detect continuation + trailing suffix: parse past body classes.
        //   [class]* / [class]+          → main-loop continuation class
        //   [chars]? / 'c'?              → optional suffix after main loop
        var contChars: [256]bool = @splat(false);
        var hasCont = false;
        var suffixChars: [256]bool = @splat(false);
        var hasSuffix = false;
        var pos = cc.endPos;

        while (pos < rule.pattern.len) {
            if (rule.pattern[pos] == '[') {
                if (parseCharClass(rule.pattern[pos..])) |cls| {
                    pos += cls.endPos;
                    if (pos < rule.pattern.len and rule.pattern[pos] == '?') {
                        suffixChars = cls.chars;
                        hasSuffix = true;
                        pos += 1;
                    } else if (pos < rule.pattern.len and
                        (rule.pattern[pos] == '*' or rule.pattern[pos] == '+'))
                    {
                        contChars = cls.chars;
                        hasCont = true;
                        hasSuffix = false;
                        pos += 1;
                    } else {
                        hasSuffix = false;
                    }
                } else break;
            } else if (pos + 2 < rule.pattern.len and rule.pattern[pos] == '\'' and
                rule.pattern[pos + 2] == '\'')
            {
                const ch = rule.pattern[pos + 1];
                pos += 3;
                if (pos < rule.pattern.len and rule.pattern[pos] == '?') {
                    suffixChars = @splat(false);
                    suffixChars[ch] = true;
                    hasSuffix = true;
                    pos += 1;
                } else {
                    hasSuffix = false;
                }
            } else if (rule.pattern[pos] == ' ') {
                pos += 1;
            } else break;
        }

        if (count >= result.len) {
            std.debug.print("error: too many identifier-like token types (max {d})\n", .{result.len});
            return error.Overflow;
        }
        result[count] = .{
            .token = rule.token,
            .startChars = cc.chars,
            .contChars = contChars,
            .hasCont = hasCont,
            .suffixChars = suffixChars,
            .hasSuffix = hasSuffix,
        };
        count += 1;
    }
    return .{ .rules = result, .count = count };
}

pub const NumericSuffixRule = struct {
    firstClass: [256]bool,      // Consumed by scanNumber
    middle: [8]u8,
    middleLen: u8,
    hasSuffix: bool,            // Optional [class]+ after the middle
    suffixClass: [256]bool,
    token: []const u8,
};

/// Detect rules of shape `[class1]+ 'X'... ( [class2]+ )? → token` where
/// class1 is consumed by scanNumber (e.g. `[0-9]+`). Examples from slash:
///   `[0-9]+ '>' → redir_fd_out`
///   `[0-9]+ '<' → redir_fd_in`
///   `[0-9]+ '>' '&' [0-9]+ → redir_fd_dup`
/// After scanNumber consumes the digit run, the emitter peeks for the
/// literal middle (and optional class-suffix), extending the token and
/// reclassifying its category when the suffix matches.
pub fn collectNumericSuffixRules(spec: *const LexerSpec) !struct {
    rules: [8]NumericSuffixRule,
    count: usize,
} {
    var result: [8]NumericSuffixRule = undefined;
    var count: usize = 0;

    for (spec.rules.items) |rule| {
        if (rule.guards.len > 0) continue;
        if (rule.actions.len > 0) continue;
        if (rule.pattern.len == 0 or rule.pattern[0] != '[') continue;

        const firstCC = parseCharClass(rule.pattern) orelse continue;
        var pos = firstCC.endPos;
        if (pos >= rule.pattern.len or rule.pattern[pos] != '+') continue;
        pos += 1;
        while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;

        // Must be digit-like: first class contains a digit, no alpha.
        var hasAlpha = false;
        var hasDigit = false;
        for (0..256) |c| {
            if (!firstCC.chars[c]) continue;
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') hasAlpha = true;
            if (c >= '0' and c <= '9') hasDigit = true;
        }
        if (hasAlpha or !hasDigit) continue;

        // Literal middle: one or more `'X'` chars.
        var middle: [8]u8 = undefined;
        var middleLen: u8 = 0;
        while (pos < rule.pattern.len and rule.pattern[pos] == '\'') {
            if (pos + 2 >= rule.pattern.len or rule.pattern[pos + 2] != '\'') break;
            if (middleLen >= middle.len) break;
            middle[middleLen] = rule.pattern[pos + 1];
            middleLen += 1;
            pos += 3;
            while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
        }
        if (middleLen == 0) continue;

        // Optional suffix: [class]+
        var hasSuffix = false;
        var suffixClass: [256]bool = @splat(false);
        if (pos < rule.pattern.len and rule.pattern[pos] == '[') {
            const sc = parseCharClass(rule.pattern[pos..]) orelse continue;
            pos += sc.endPos;
            if (pos >= rule.pattern.len or rule.pattern[pos] != '+') continue;
            pos += 1;
            suffixClass = sc.chars;
            hasSuffix = true;
            while (pos < rule.pattern.len and rule.pattern[pos] == ' ') pos += 1;
        }
        if (pos != rule.pattern.len) continue;

        if (count >= result.len) {
            std.debug.print("error: too many numeric-suffix rules (max {d})\n", .{result.len});
            return error.Overflow;
        }
        result[count] = .{
            .firstClass = firstCC.chars,
            .middle = middle,
            .middleLen = middleLen,
            .hasSuffix = hasSuffix,
            .suffixClass = suffixClass,
            .token = rule.token,
        };
        count += 1;
    }
    return .{ .rules = result, .count = count };
}
