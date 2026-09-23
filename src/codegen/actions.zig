//! Action codegen: compiles a rule's action template (`(tag 1 ...2)`, `N`,
//! `_`, `~N`, `key:N`, child tag literals) into the Zig expression that
//! builds its Sexp, and collects the tags actions use for the Tag enum.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const Rule = grammar.Rule;

/// Tags referenced by action templates, in first-seen order.
pub const TagSet = struct {
    map: std.StringHashMapUnmanaged(u16) = .empty,
    list: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn collect(self: *TagSet, allocator: Allocator, rules: []const Rule) !void {
        for (rules) |rule| {
            if (rule.action) |action| {
                try self.collectFromAction(allocator, action);
            }
        }
    }

    fn collectFromAction(self: *TagSet, allocator: Allocator, template: []const u8) !void {
        // For paren-style: (tag elem1 elem2 ...) — register the head as
        // a Tag, AND walk every child element to register any tag literal
        // found at a child position (e.g., `(set move 1 _ 3)` registers
        // both `set` and `move`). The head and child semantics differ
        // in how `key:value` sugar is interpreted:
        //   * head `tag:N` registers `tag` (key part)
        //   * child `key:val` registers `val` (value part, via stripKeyAndSuffix)
        if (template.len <= 1 or template[0] != '(') return;

        var i: usize = 1;
        var first_element = true;
        while (i < template.len and template[i] != ')') {
            while (i < template.len and (template[i] == ' ' or template[i] == '\t')) i += 1;
            if (i >= template.len or template[i] == ')') break;
            const start = i;
            while (i < template.len and template[i] != ' ' and template[i] != '\t' and template[i] != ')') i += 1;
            if (i <= start) break;
            const raw = template[start..i];

            var tag: []const u8 = "";
            if (first_element) {
                // Head: strip `:value` suffix, keep the `key` part as the tag.
                tag = raw;
                if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
                    const after = tag[colonPos + 1 ..];
                    if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
                        after[0] == '.' or after[0] == '~'))
                    {
                        tag = tag[0..colonPos];
                    }
                }
            } else {
                // Child: strip `key:` prefix, keep the value part.
                tag = stripKeyAndSuffix(raw);
            }

            if (isLikelyTagName(tag)) {
                try self.register(allocator, tag);
            }
            first_element = false;
        }
    }

    fn register(self: *TagSet, allocator: Allocator, tag: []const u8) !void {
        if (!self.map.contains(tag)) {
            const owned = try allocator.dupe(u8, tag);
            try self.map.put(allocator, owned, @intCast(self.list.items.len));
            try self.list.append(allocator, owned);
        }
    }
};

pub fn generateRuleAction(allocator: Allocator, writer: anytype, rule: Rule) !void {
    if (rule.action == null) {
        try writer.writeAll("self.list(pass)");
        return;
    }

    const template = rule.action.?;
    const offset = rule.actionOffset;

    // Handle simple cases
    if (std.mem.eql(u8, template, "nil") or std.mem.eql(u8, template, "_")) {
        try writer.writeAll(".nil");
        return;
    }

    if (std.mem.eql(u8, template, "()")) {
        try writer.writeAll(".{ .list = &[_]Sexp{} }");
        return;
    }

    // Handle spread patterns: (!1 ...2)
    if (std.mem.eql(u8, template, "(!1 ...2)")) {
        try writer.writeAll("self.spreadList(pass[0], pass[1])");
        return;
    }
    if (std.mem.eql(u8, template, "(!2 ...3)")) {
        try writer.writeAll("self.spreadList(pass[1], pass[2])");
        return;
    }

    // Handle simple passthrough: 1, 2, etc.
    if (template.len == 1 and template[0] >= '1' and template[0] <= '9') {
        const pos = template[0] - '1' + offset;
        try writer.print("pass[{d}]", .{pos});
        return;
    }

    // Handle paren-style S-expressions: (tag 1 2 3)
    if (template.len > 0 and template[0] == '(') {
        try generateParenAction(allocator, writer, template, offset);
        return;
    }

    // Fallback
    try writer.writeAll("self.list(pass)");
}

fn generateParenAction(allocator: Allocator, writer: anytype, template: []const u8, offset: u8) !void {
    // Parse (tag elem1 elem2 ...) and generate build code
    var i: usize = 1; // Skip opening paren
    var elements: std.ArrayListUnmanaged([]const u8) = .empty;
    defer elements.deinit(allocator);

    // Skip whitespace and parse elements
    while (i < template.len and template[i] != ')') {
        while (i < template.len and (template[i] == ' ' or template[i] == '\t')) i += 1;
        if (i >= template.len or template[i] == ')') break;
        const start = i;
        while (i < template.len and template[i] != ' ' and template[i] != '\t' and template[i] != ')') i += 1;
        if (i > start) try elements.append(allocator, template[start..i]);
    }

    if (elements.items.len == 0) {
        try writer.writeAll(".{ .list = &[_]Sexp{} }");
        return;
    }

    // Analyze elements
    const tag = elements.items[0];
    var tagName = tag;

    // Strip key:value from tag if present (e.g., "dots:2?" -> "dots")
    if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
        const after = tag[colonPos + 1 ..];
        if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
            after[0] == '.' or after[0] == '~' or after[0] == '_'))
        {
            tagName = tag[0..colonPos];
        }
    }

    const firstIsTag = isTagLiteral(tagName);

    // Count element types
    var spreadCount: usize = 0;
    var spreadPos: u8 = 0;
    var posCount: usize = 0;
    var firstPos: u8 = 0;
    var hasTilde = false;
    var hasOther = false;
    var hasNil = false;
    // Track child-position Tag literals separately. The dispatcher's
    // sexpSpread / sexpPosSpread fast paths emit (tag ...spread) and
    // (tag pos ...spread) shapes, neither of which has a slot for a
    // kind-discriminator child Tag — so routing a mixed (Tag + spread)
    // template through either would silently drop the Tag. Force such
    // templates to the complex case, which can place tag literals at
    // arbitrary positions.
    var hasChildTagLiteral = false;

    for (elements.items[1..]) |elem| {
        const work = stripKeyAndSuffix(elem);
        if (work.len == 0) continue;
        if (work[0] == '.' and work.len >= 4 and work[1] == '.' and work[2] == '.') {
            spreadCount += 1;
            spreadPos = work[3] - '1' + offset;
        } else if (work[0] == '~') {
            hasTilde = true;
        } else if (work[0] >= '1' and work[0] <= '9') {
            if (posCount == 0) firstPos = work[0] - '1' + offset;
            posCount += 1;
        } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
            hasNil = true; // track nil separately for pattern matching
        } else if (isTagLiteral(work)) {
            hasChildTagLiteral = true;
        } else {
            hasOther = true;
        }
    }

    // Pattern: (tag ...N) - use sexpSpread (only if no nil elements and no child tag literals)
    if (firstIsTag and spreadCount == 1 and posCount == 0 and !hasTilde and !hasOther and !hasNil and !hasChildTagLiteral) {
        try writer.print("self.sexpSpread(.@\"{s}\", pass[{d}])", .{ tagName, spreadPos });
        return;
    }

    // Pattern: (tag N ...M) - use sexpPosSpread (only if no nil elements and no child tag literals)
    if (firstIsTag and spreadCount == 1 and posCount == 1 and !hasTilde and !hasOther and !hasNil and !hasChildTagLiteral) {
        try writer.print("self.sexpPosSpread(.@\"{s}\", pass[{d}], pass[{d}])", .{ tagName, firstPos, spreadPos });
        return;
    }

    // Simple case: self.sexp(.@"tag", &.{pass[0], pass[1], ...})
    // Only if first element is a tag and no spreads/tilde
    var tagHasValue = false;
    var tagValue: []const u8 = "";

    // Check if tag has key:value format (like "dots:2?", "type:_")
    if (std.mem.indexOfScalar(u8, tag, ':')) |colonPos| {
        const after = tag[colonPos + 1 ..];
        if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
            after[0] == '.' or after[0] == '~' or after[0] == '_'))
        {
            tagHasValue = true;
            tagValue = stripKeyAndSuffix(tag);
        }
    }

    if (firstIsTag and spreadCount == 0 and !hasTilde and !hasOther) {
        try writer.print("self.sexp(.@\"{s}\", &.{{", .{tagName});
        var first = true;

        // Add tag's value if it had key:value format
        if (tagHasValue and tagValue.len > 0) {
            if (tagValue[0] >= '1' and tagValue[0] <= '9') {
                try writer.print("pass[{d}]", .{tagValue[0] - '1' + offset});
                first = false;
            }
        }

        for (elements.items[1..]) |elem| {
            const work = stripKeyAndSuffix(elem);
            if (work.len == 0) continue;
            if (!first) try writer.writeAll(", ");
            first = false;
            if (work[0] >= '1' and work[0] <= '9') {
                try writer.print("pass[{d}]", .{work[0] - '1' + offset});
            } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
                try writer.writeAll(".nil");
            } else if (isTagLiteral(work)) {
                // Tag literal at child position — kind-discriminator
                // pattern used by Rig and any grammar that wants the
                // grammar action to emit normalized shapes directly
                // (e.g., `(set move 1 _ 3)` puts the Tag `.move` in
                // slot 2). Previously silent-dropped; now emitted as
                // a literal-Tag Sexp.
                try writer.print(".{{ .tag = .@\"{s}\" }}", .{work});
            } else {
                std.debug.print(
                    "❌ Unknown action element '{s}' in template: {s}\n" ++
                    "   (expected position ref like `1`, `_`, `...N`, `~N`, `key:N`, or a tag literal)\n",
                    .{ work, template },
                );
                return error.UnknownActionElement;
            }
        }
        try writer.writeAll("})");
        return;
    }

    // Complex case: inline list building (spreads, tilde transforms).
    //
    // A template that starts with a spread, `(...N more...)`, extends
    // the list at N: that is how a left-recursive list rule adds one
    // element. Copying the whole list on every reduction would make
    // parsing an n-element list O(n^2) in time and arena memory, so
    // the list grows in place instead (`extendList` / `keepList`,
    // amortized O(1) per element). This is safe because each reduced
    // value is consumed exactly once, unless the template names N
    // again, in which case the list is copied as before.
    var extendElem: ?usize = null;
    for (elements.items, 0..) |elem, idx| {
        const work = stripKeyAndSuffix(elem);
        if (work.len == 0) continue;
        if (isSpread(work)) extendElem = idx;
        break;
    }
    if (extendElem) |first| {
        const digit = stripKeyAndSuffix(elements.items[first])[3];
        for (elements.items[first + 1 ..]) |elem| {
            if (positionDigit(stripKeyAndSuffix(elem)) == digit) extendElem = null;
        }
    }
    if (extendElem) |first| {
        const pos = stripKeyAndSuffix(elements.items[first])[3] - '1' + offset;
        try writer.print("blk: {{ var out = self.extendList(pass[{d}]) catch break :blk .nil; ", .{pos});
    } else {
        try writer.writeAll("blk: { var out: std.ArrayListUnmanaged(Sexp) = .empty; ");
    }
    for (elements.items, 0..) |elem, idx| {
        if (elem.len == 0) continue;
        if (extendElem == idx) continue;
        const work = stripKeyAndSuffix(elem);
        if (work.len == 0) continue;

        if (work[0] >= '1' and work[0] <= '9') {
            const pos = work[0] - '1' + offset;
            try writer.print("out.append(self.allocator(), pass[{d}]) catch break :blk .nil; ", .{pos});
        } else if (work[0] == '~' and work.len > 1 and work[1] >= '1' and work[1] <= '9') {
            const pos = work[1] - '1' + offset;
            try writer.print("out.append(self.allocator(), if (pass[{d}] == .src) pass[{d}] else .{{ .src = .{{ .pos = 0, .len = 0, .id = 0 }} }}) catch break :blk .nil; ", .{ pos, pos });
        } else if (work[0] == '.' and work.len >= 4 and work[1] == '.' and work[2] == '.') {
            const pos = work[3] - '1' + offset;
            try writer.print("if (pass[{d}] == .list) for (pass[{d}].list) |item| out.append(self.allocator(), item) catch break :blk .nil; ", .{ pos, pos });
        } else if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) {
            try writer.writeAll("out.append(self.allocator(), .nil) catch break :blk .nil; ");
        } else if (isLikelyTagName(work)) {
            // Tag literal at child position. The complex-case path
            // already emitted this for unrecognized elements, but
            // (a) using `elem` instead of `work` let `key:` prefixes
            // leak into the emitted Tag name, and (b) any garbage
            // element silently became a (broken) Tag literal. Both
            // are tightened here: strip via `work`, validate via
            // `isLikelyTagName`, error on anything else.
            try writer.print("out.append(self.allocator(), .{{ .tag = .@\"{s}\" }}) catch break :blk .nil; ", .{work});
        } else {
            std.debug.print(
                "❌ Unknown action element '{s}' in template: {s}\n" ++
                "   (expected position ref like `1`, `_`, `...N`, `~N`, `key:N`, or a tag literal)\n",
                .{ work, template },
            );
            return error.UnknownActionElement;
        }
    }
    try writer.writeAll("while (out.items.len > 0 and out.items[out.items.len - 1] == .nil) _ = out.pop(); ");
    if (extendElem != null) {
        try writer.writeAll("break :blk self.keepList(&out); }");
    } else {
        try writer.writeAll("break :blk .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} }; }");
    }
}

/// `...N` in an action template.
fn isSpread(work: []const u8) bool {
    return work.len >= 4 and work[0] == '.' and work[1] == '.' and work[2] == '.';
}

/// The position digit an action element refers to (`N`, `~N`, `...N`).
fn positionDigit(work: []const u8) ?u8 {
    if (work.len == 0) return null;
    const digit = if (isSpread(work)) work[3] else if (work[0] == '~' and work.len > 1) work[1] else work[0];
    return if (digit >= '1' and digit <= '9') digit else null;
}

fn stripKeyAndSuffix(elem: []const u8) []const u8 {
    var work = elem;
    // Strip key: prefix (e.g., "offset:3" -> "3", "type:_" -> "_")
    if (std.mem.indexOfScalar(u8, work, ':')) |colonPos| {
        const after = work[colonPos + 1 ..];
        if (after.len > 0 and (after[0] >= '1' and after[0] <= '9' or
            after[0] == '.' or after[0] == '~' or after[0] == '_'))
        {
            work = after;
        }
    }
    return work;
}

fn isTagLiteral(work: []const u8) bool {
    if (work.len == 0) return false;
    if (std.mem.eql(u8, work, "nil") or std.mem.eql(u8, work, "_")) return false;
    const c = work[0];
    // Tag literals start with letter or special char like !, #, ?, @, $
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        c == '!' or c == '#' or c == '?' or c == '@' or c == '$' or c == '*' or c == '/';
}

// Permissive recognizer for action elements that look like a Tag-enum
// member name. Used at child positions (where the dispatcher routes
// letter-start tags through the simple case and operator-name tags
// through the complex case). Rejects only the forms the action
// language has dedicated syntax for: position refs (digit-start),
// symbol-id refs (`~`-start), spreads (`...`), nil/`_`, and the
// `key:value` annotation sugar (`:` strictly between two non-empty
// halves — a bare `:` or leading-colon operator like `:=` is a
// valid Tag name and passes through).
fn isLikelyTagName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.mem.eql(u8, name, "nil") or std.mem.eql(u8, name, "_")) return false;
    const c = name[0];
    // Single-digit position ref `1`-`9`. (Multi-digit names and `0`
    // are valid Tag names and pass through.)
    if (c >= '1' and c <= '9' and name.len == 1) return false;
    // Symbol-id ref `~N` (tilde + digit). A bare `~` is a valid Tag.
    if (c == '~' and name.len >= 2 and name[1] >= '1' and name[1] <= '9') return false;
    // Spread `...N` (3 dots + digit). Shorter dot-starts like `.`, `..`,
    // `.member` are valid Tag names.
    if (c == '.' and name.len >= 4 and name[1] == '.' and name[2] == '.'
        and name[3] >= '1' and name[3] <= '9') return false;
    // `key:value` annotation sugar requires content on BOTH sides of the
    // colon. A bare `:` or leading-colon operator (`:=`) passes through.
    if (std.mem.indexOfScalar(u8, name, ':')) |colonPos| {
        if (colonPos > 0 and colonPos + 1 < name.len) return false;
    }
    return true;
}
