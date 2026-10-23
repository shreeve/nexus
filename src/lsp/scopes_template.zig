//! scopes.zig: the names and scopes of one file, from the `@lsp` lines of
//! its grammar (docs/GRAMMAR.md, "Names and scopes"), written by `nexus
//! --editor` beside the server (`lsp.zig`) for a grammar with `@lsp`.
//!
//! `index` parses a text (tolerantly, with `@repair`) and walks its tree
//! once. A node of a scope kind opens a scope; a leaf in a role a `define`
//! line names is a definition, of the nearest scope at or around its node
//! (the one around that, with `outer`); a leaf of a `use` token in any
//! other role but a skipped one is a use, which resolves up its chain of
//! scopes to the nearest definition of its name: any in an unordered
//! scope; in an ordered one, the last whose node ends before it (whose
//! own leaf does, for an `outer` definition or one of the node that opens
//! its scope). A name that resolves to none is a builtin when `builtin`
//! lists it, else unresolved.
//! The tables come from `language.zig` (`language.names`), so nothing here
//! knows the language.

const std = @import("std");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const lsp = @import("lsp.zig");
const language = @import("language.zig");

const Sexp = parser.Sexp;
const Tag = parser.Tag;
const TokenCat = parser.TokenCat;

// =============================================================================
// The tables of `@lsp`
// =============================================================================

/// A role of a kind: its slot (the head is slot 0), and whether it is a
/// rest role, whose children run from that slot on.
pub const Slot = struct { kind: Tag, slot: u16, rest: bool = false };

pub const ScopeKind = struct { kind: Tag, unordered: bool = false };

pub const Skip = struct { at: Slot, when: []const Define.When = &.{} };

pub const Visibility = enum { both, member, lexical };

pub const Define = struct {
    at: Slot,
    symbol: lsp.SymbolKind,
    /// The definition is made only when each of these holds.
    when: []const When = &.{},
    outer: bool = false,
    visibility: Visibility = .both,
    /// The slot of the definition's value, whose scope is its members in
    /// the outline.
    value: ?u16 = null,
    /// The slot of its declared type, its detail when it has no other.
    type: ?u16 = null,
    doc: Doc = .none,
    @"export": Export = .none,
    detail: Detail = .none,

    /// The leaf in slot `slot` of the node (of its parent, when the parent
    /// is a `parent`) is `text`, an absent one's text being empty; without
    /// `text`, the slot is not empty.
    pub const When = struct { parent: ?Tag = null, slot: u16, text: ?[]const u8 = null };
    /// `doc:ROLE`: the tokens of a role; `doc:leading`: the doc tokens on
    /// the lines just before the definition's node.
    pub const Doc = union(enum) { none, role: Slot, leading };
    /// Whether another file can see the definition: always in the file's
    /// outermost scope (`none`), when a role is present, or when the
    /// node's parent is of a kind.
    pub const Export = union(enum) { none, slot: u16, parent: Tag };
    /// The definition's one-line detail: the node's text, or its text up
    /// to a role.
    pub const Detail = union(enum) { none, whole, upto: u16 };
};

pub const Table = struct {
    scopes: []const ScopeKind = &.{},
    /// Whether the file's own scope is unordered when its tree is not
    /// whole: the order of the kind the start symbol builds.
    file_unordered: bool = false,
    defines: []const Define = &.{},
    /// Leaves that are neither definitions nor uses: a skip with `when`
    /// takes a leaf before any define does; one without, a leaf no define
    /// takes.
    skips: []const Skip = &.{},
    uses: []const TokenCat = &.{},
    builtins: []const []const u8 = &.{},
    builtin_tokens: []const TokenCat = &.{},
    doc_token: ?TokenCat = null,
    doc_strip: []const u8 = "",
    undefined: ?lsp.Severity = null,
};

const table: Table = language.names;

// =============================================================================
// The index
// =============================================================================

pub const Scope = struct {
    start: u32,
    end: u32,
    parent: ?u32,
    unordered: bool,
};

pub const Def = struct {
    name: []const u8,
    start: u32,
    end: u32,
    /// The scope it belongs to.
    scope: u32,
    /// The scope whose definitions are its children in the outline.
    inner: ?u32 = null,
    /// Its `define` line.
    line: u16,
    /// Its node's span (for a rest role, its own leaf's).
    node_start: u32,
    node_end: u32,
    /// Where it comes into sight in an ordered scope: the end of its node,
    /// or of its own leaf when it is `outer` or its node is its scope's.
    visible: u32,
    /// Where its detail text ends: its node's end, or the start of the
    /// role `detail:..ROLE` names.
    detail_end: u32 = 0,
    /// Its type role's span, when it has one.
    type_span: ?[2]u32 = null,
    /// Its doc role's leaves (`doc:ROLE`).
    doc: []const [2]u32 = &.{},
    exported: bool,
};

pub const Resolution = union(enum) { def: u32, builtin, unresolved };

pub const Use = struct { start: u32, end: u32, scope: u32, res: Resolution };

/// A name in the text: a definition's leaf, or a use.
pub const Occurrence = struct { start: u32, end: u32, what: union(enum) { def: u32, use: u32 } };

/// A leaf no lookup reads: a skipped one, a definition's, or a hole the
/// tolerant parse inserted.
const Other = struct { start: u32, end: u32, use: bool };

pub const Index = struct {
    text: []const u8,
    tokens: []const parser.Token,
    scopes: []const Scope,
    defs: []const Def,
    uses: []const Use,
    /// Every definition's leaf and use, by position.
    occurrences: []const Occurrence,
    /// Every other leaf, and every hole, by position: what completion
    /// asks of the word at the cursor.
    others: []const Other,

    /// The name at `at`: the one it is in, else the one it ends.
    pub fn at(self: *const Index, offset: u32) ?Occurrence {
        const occ = self.occurrences;
        var lo: usize = 0;
        var hi: usize = occ.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (occ[mid].start <= offset) lo = mid + 1 else hi = mid;
        }
        if (lo > 0 and offset < occ[lo - 1].end) return occ[lo - 1];
        if (lo > 0 and offset == occ[lo - 1].end) return occ[lo - 1];
        return null;
    }

    /// The definition the name at `offset` is, or resolves to.
    pub fn defAt(self: *const Index, offset: u32) ?u32 {
        const o = self.at(offset) orelse return null;
        return switch (o.what) {
            .def => |d| d,
            .use => |u| switch (self.uses[u].res) {
                .def => |d| d,
                else => null,
            },
        };
    }

    /// The leaf of definition `d` and every use that resolves to it, by
    /// position.
    pub fn references(self: *const Index, arena: Allocator, d: u32) error{OutOfMemory}![]const [2]u32 {
        var out: std.ArrayList([2]u32) = .empty;
        for (self.occurrences) |o| switch (o.what) {
            .def => |x| if (x == d) try out.append(arena, .{ o.start, o.end }),
            .use => |u| if (self.uses[u].res == .def and self.uses[u].res.def == d) try out.append(arena, .{ o.start, o.end }),
        };
        return out.items;
    }

    /// The innermost scope around `offset`.
    pub fn scopeAt(self: *const Index, offset: u32) u32 {
        var best: u32 = 0;
        for (self.scopes, 0..) |s, i| if (s.start <= offset and offset <= s.end) {
            best = @intCast(i);
        };
        return best;
    }

    /// The definitions a use at `offset` could name, nearest scope first,
    /// one per name.
    pub fn visibleAt(self: *const Index, arena: Allocator, offset: u32) error{OutOfMemory}![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var scope: ?u32 = self.scopeAt(offset);
        while (scope) |s| : (scope = self.scopes[s].parent) {
            const unordered = self.scopes[s].unordered;
            // In an ordered scope the last definition before `offset` of a
            // name is the one in sight.
            var i = self.defs.len;
            while (i > 0) {
                i -= 1;
                const d = self.defs[i];
                if (d.scope != s or table.defines[d.line].visibility == .member) continue;
                if (!unordered and d.visible >= offset) continue;
                if (self.at(offset)) |o| if (o.what == .def and o.what.def == i) continue;
                const gop = try seen.getOrPut(arena, d.name);
                if (gop.found_existing) continue;
                try out.append(arena, @intCast(i));
            }
        }
        return out.items;
    }

    /// Whether completion at `offset` offers names: unless the word there
    /// (or the hole the tolerant parse put there) is a definition's or a
    /// skipped role's, where a name in scope cannot go.
    pub fn wantsNames(self: *const Index, offset: u32) bool {
        if (self.at(offset)) |o| return o.what == .use;
        for (self.others) |o| {
            if (o.start == o.end) {
                const lo = @min(o.start, offset);
                const hi = @max(o.start, offset);
                if (hi <= self.text.len and std.mem.trim(u8, self.text[lo..hi], " \t").len == 0) return o.use;
            } else if (o.start <= offset and offset <= o.end) return o.use;
        }
        return true;
    }

    /// The symbol of definition `d`, for the server.
    pub fn symbol(self: *const Index, arena: Allocator, path: []const u8, d: u32) error{OutOfMemory}!lsp.Symbol {
        const def = self.defs[d];
        return .{
            .id = try arena.print("{s}:{d}", .{ path, def.start }),
            .name = def.name,
            .kind = table.defines[def.line].symbol,
            .decl = .{ .path = path, .start = def.start, .end = def.end },
            .detail = try self.detail(arena, d),
            .doc = try self.doc(arena, d),
        };
    }

    /// The one-line text `detail` gives definition `d`: its node's tokens
    /// up to where the detail ends, one blank where the text has any, and
    /// no operator at its end. Empty without `detail`.
    pub fn detail(self: *const Index, arena: Allocator, d: u32) error{OutOfMemory}![]const u8 {
        const def = self.defs[d];
        if (table.defines[def.line].detail == .none) return "";
        return self.tokenText(arena, def.node_start, def.detail_end, true);
    }

    /// The text of definition `d`'s type role.
    pub fn typeText(self: *const Index, arena: Allocator, d: u32) error{OutOfMemory}![]const u8 {
        const span = self.defs[d].type_span orelse return "";
        return self.tokenText(arena, span[0], span[1], false);
    }

    /// The doc text of definition `d`: its doc tokens, each without the
    /// `strip` text and one blank after it, one a line.
    pub fn doc(self: *const Index, arena: Allocator, d: u32) error{OutOfMemory}![]const u8 {
        const def = self.defs[d];
        var spans: std.ArrayList([2]u32) = .empty;
        switch (table.defines[def.line].doc) {
            .none => return "",
            .role => try spans.appendSlice(arena, def.doc),
            .leading => {
                const cat = table.doc_token orelse return "";
                var i = self.firstTokenAt(def.node_start);
                var next = def.node_start;
                while (self.solidBefore(i)) |j| {
                    const t = self.tokens[j];
                    if (t.cat != cat) break;
                    // With no blank line after it, and on a line of its own.
                    const after = self.text[t.pos + t.len .. next];
                    if (std.mem.count(u8, after, "\n") != 1 or std.mem.trim(u8, after, " \t\r\n").len > 0) break;
                    if (self.solidBefore(j)) |k| {
                        const prev = self.tokens[k];
                        if (std.mem.findScalar(u8, self.text[prev.pos + prev.len .. t.pos], '\n') == null) break;
                    }
                    try spans.insert(arena, 0, .{ t.pos, t.pos + t.len });
                    next = t.pos;
                    i = j;
                }
            },
        }
        var out: std.ArrayList(u8) = .empty;
        for (spans.items, 0..) |s, n| {
            var line = std.mem.trimEnd(u8, self.text[s[0]..s[1]], " \t\r");
            if (std.mem.startsWith(u8, line, table.doc_strip)) line = line[table.doc_strip.len..];
            if (line.len > 0 and line[0] == ' ') line = line[1..];
            if (n > 0) try out.append(arena, '\n');
            try out.appendSlice(arena, line);
        }
        return out.items;
    }

    /// The tokens of `start..end`, one blank where the text between two
    /// has blanks, a line end or a comment, without comments, doc tokens
    /// and layout (tokens of blanks and line ends, or of no text); with
    /// `trim`, without operators at the end.
    fn tokenText(self: *const Index, arena: Allocator, start: u32, end: u32, trim: bool) error{OutOfMemory}![]const u8 {
        var last = self.firstTokenAt(start);
        var stop = last;
        while (stop < self.tokens.len and self.tokens[stop].pos < end) stop += 1;
        var kept: std.ArrayList(parser.Token) = .empty;
        while (last < stop) : (last += 1) {
            const t = self.tokens[last];
            if (isComment(t) or std.mem.trim(u8, self.text[t.pos..][0..t.len], " \t\r\n").len == 0) continue;
            try kept.append(arena, t);
        }
        if (trim) while (kept.items.len > 1) {
            const t = kept.items[kept.items.len - 1];
            const scope = language.wordScope(self.text[t.pos..][0..t.len]) orelse language.tokenScope(t.cat);
            if (scope != .operator) break;
            kept.items.len -= 1;
        };
        var out: std.ArrayList(u8) = .empty;
        for (kept.items, 0..) |t, n| {
            if (n > 0) {
                const prev = kept.items[n - 1];
                if (prev.pos + prev.len < t.pos) try out.append(arena, ' ');
            }
            try out.appendSlice(arena, self.text[t.pos..@min(self.text.len, t.pos + @as(u32, t.len))]);
        }
        return out.items;
    }

    fn isComment(t: parser.Token) bool {
        if (table.doc_token) |c| if (t.cat == c) return true;
        return language.tokenScope(t.cat) == .comment;
    }

    /// The last token before token `i` with text other than blanks and
    /// line ends.
    fn solidBefore(self: *const Index, i: usize) ?usize {
        var j = i;
        while (j > 0) {
            j -= 1;
            const t = self.tokens[j];
            if (std.mem.trim(u8, self.text[t.pos..][0..t.len], " \t\r\n").len > 0) return j;
        }
        return null;
    }

    /// The first token that starts at or after `pos`.
    fn firstTokenAt(self: *const Index, pos: u32) usize {
        var lo: usize = 0;
        var hi: usize = self.tokens.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (self.tokens[mid].pos < pos) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    /// The token that starts at `pos`, if one does.
    fn tokenAt(self: *const Index, pos: u32) ?parser.Token {
        const i = self.firstTokenAt(pos);
        if (i < self.tokens.len and self.tokens[i].pos == pos) return self.tokens[i];
        return null;
    }

    /// The outline: the definitions of the file's own scope, each with
    /// the definitions of its inner scope as children.
    pub fn outline(self: *const Index, arena: Allocator) error{OutOfMemory}![]const lsp.OutlineItem {
        return self.outlineOf(arena, 0, null, 0);
    }

    fn outlineOf(self: *const Index, arena: Allocator, scope: u32, skip: ?u32, depth: u32) error{OutOfMemory}![]const lsp.OutlineItem {
        var out: std.ArrayList(lsp.OutlineItem) = .empty;
        if (depth > 64) return out.items;
        for (self.defs, 0..) |d, i| {
            if (d.scope != scope or (skip != null and skip.? == i)) continue;
            const children: []const lsp.OutlineItem = if (d.inner) |inner| try self.outlineOf(arena, inner, @intCast(i), depth + 1) else &.{};
            var text = try self.detail(arena, @intCast(i));
            if (text.len == 0) text = try self.typeText(arena, @intCast(i));
            try out.append(arena, .{
                .name = d.name,
                .kind = table.defines[d.line].symbol,
                .start = @min(d.node_start, d.start),
                .end = @max(d.node_end, d.end),
                .name_start = d.start,
                .name_end = d.end,
                .detail = text,
                .children = children,
            });
        }
        return out.items;
    }

    /// An error or warning at each use no definition or builtin answers,
    /// with `undefined`.
    pub fn undefinedNames(self: *const Index, arena: Allocator, path: []const u8) error{OutOfMemory}![]const lsp.Diagnostic {
        const severity = table.undefined orelse return &.{};
        var out: std.ArrayList(lsp.Diagnostic) = .empty;
        for (self.uses) |u| if (u.res == .unresolved) try out.append(arena, .{
            .span = .{ .path = path, .start = u.start, .end = u.end },
            .severity = severity,
            .message = try arena.print("'{s}' is not defined", .{self.text[u.start..u.end]}),
        });
        return out.items;
    }
};

// =============================================================================
// Building the index
// =============================================================================

/// The index of `text`, in `arena`.
pub fn index(arena: Allocator, text: []const u8) error{OutOfMemory}!Index {
    var b: Builder = .{ .arena = arena, .text = text };
    try b.lex();
    try b.walk();
    try b.resolve();
    std.mem.sort(Occurrence, b.occurrences.items, {}, struct {
        fn lt(_: void, x: Occurrence, y: Occurrence) bool {
            return x.start < y.start;
        }
    }.lt);
    std.mem.sort(Other, b.others.items, {}, struct {
        fn lt(_: void, x: Other, y: Other) bool {
            return x.start < y.start;
        }
    }.lt);
    return .{
        .text = text,
        .tokens = b.tokens.items,
        .scopes = b.scopes.items,
        .defs = b.defs.items,
        .uses = b.uses.items,
        .occurrences = b.occurrences.items,
        .others = b.others.items,
    };
}

const Builder = struct {
    arena: Allocator,
    text: []const u8,
    p: *parser.BaseParser = undefined,
    tokens: std.ArrayList(parser.Token) = .empty,
    scopes: std.ArrayList(Scope) = .empty,
    defs: std.ArrayList(Def) = .empty,
    uses: std.ArrayList(Use) = .empty,
    occurrences: std.ArrayList(Occurrence) = .empty,
    others: std.ArrayList(Other) = .empty,
    /// The scope each scope node opened, by the node's items, for the
    /// definitions whose value is a scope node.
    opened: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    /// Definitions whose value node's scope is looked up after the walk.
    values: std.ArrayList(struct { def: u32, node: usize }) = .empty,

    fn lex(b: *Builder) error{OutOfMemory}!void {
        var lexer = parser.Lexer.init(b.text);
        while (true) {
            const t = lexer.next();
            if (t.cat == .eof) break;
            try b.tokens.append(b.arena, t);
        }
    }

    /// A value to visit: the node or leaf, the node of a kind whose child
    /// it is (in slot `slot`), that node's parent's kind, and the scope
    /// around the owner's children.
    const Item = struct { value: Sexp, owner: Sexp, parent: Sexp, slot: u16, scope: u32 };

    fn walk(b: *Builder) error{OutOfMemory}!void {
        const p = try b.arena.create(parser.BaseParser);
        p.* = parser.BaseParser.init(b.arena, b.text);
        b.p = p;
        var roots: []const Sexp = &.{};
        var whole = false;
        if (parser.hasRepair) {
            const r = p.parseTolerant(std.enums.values(parser.Start)[0], 64) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null,
            };
            if (r) |got| {
                if (got.sexp != .nil) {
                    roots = try b.arena.dupe(Sexp, &.{got.sexp});
                    whole = true;
                } else roots = got.pieces;
            }
        } else {
            const root = p.parse(std.enums.values(parser.Start)[0]) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => Sexp.nil,
            };
            if (root != .nil) {
                roots = try b.arena.dupe(Sexp, &.{root});
                whole = true;
            }
        }
        // The file's own scope; a whole tree's root of a scope kind is it.
        var unordered = table.file_unordered;
        if (whole) if (roots[0].kind()) |k| if (scopeKind(k)) |sk| {
            unordered = sk.unordered;
        };
        try b.scopes.append(b.arena, .{ .start = 0, .end = @intCast(b.text.len), .parent = null, .unordered = unordered });
        var stack: std.ArrayList(Item) = .empty;
        var i = roots.len;
        while (i > 0) {
            i -= 1;
            try stack.append(b.arena, .{ .value = roots[i], .owner = .nil, .parent = .nil, .slot = 0, .scope = 0 });
        }
        while (stack.pop()) |item| switch (item.value) {
            .src => |leaf| try b.classify(item, leaf),
            .list => |list| {
                const kind = item.value.kind() orelse {
                    // A group: its items belong to the owner's slot.
                    var n = list.len;
                    while (n > 0) {
                        n -= 1;
                        try stack.append(b.arena, .{ .value = list.items()[n], .owner = item.owner, .parent = item.parent, .slot = item.slot, .scope = item.scope });
                    }
                    continue;
                };
                var scope = item.scope;
                if (scopeKind(kind)) |sk| {
                    const span = p.span(item.value);
                    if (whole and list.ptr == roots[0].list.ptr) {
                        // The root: the file's own scope.
                        try b.opened.put(b.arena, @intFromPtr(list.ptr), 0);
                    } else {
                        try b.scopes.append(b.arena, .{ .start = span.start, .end = span.end, .parent = item.scope, .unordered = sk.unordered });
                        scope = @intCast(b.scopes.items.len - 1);
                        try b.opened.put(b.arena, @intFromPtr(list.ptr), scope);
                    }
                }
                const items = list.items();
                var n = items.len;
                while (n > 1) {
                    n -= 1;
                    try stack.append(b.arena, .{
                        .value = items[n],
                        .owner = item.value,
                        .parent = item.owner,
                        .slot = @intCast(n),
                        .scope = scope,
                    });
                }
            },
            else => {},
        };
        for (b.values.items) |v| if (b.opened.get(v.node)) |s| {
            if (s != b.defs.items[v.def].scope) b.defs.items[v.def].inner = s;
        };
    }

    /// Classify a leaf of slot `item.slot` of `item.owner`.
    fn classify(b: *Builder, item: Item, leafv: parser.Src) error{OutOfMemory}!void {
        const start = leafv.pos;
        const end = b.p.leafEnd(leafv);
        const ownerKind = item.owner.kind();
        if (ownerKind) |k| {
            for (table.skips) |s| if (s.when.len > 0 and s.at.kind == k and slotMatches(s.at, item.slot) and b.holds(item, s.when))
                return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
            for (table.defines, 0..) |d, line| {
                if (d.at.kind != k or !slotMatches(d.at, item.slot)) continue;
                if (!b.holds(item, d.when)) continue;
                // A hole, and a builtin's name, which is never defined.
                if (start == end or b.builtinAt(start, end)) return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
                return b.define(item, @intCast(line), start, end);
            }
            for (table.skips) |s| if (s.when.len == 0 and s.at.kind == k and slotMatches(s.at, item.slot))
                return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
        }
        // A hole the tolerant parse inserted has no token of its own.
        if (start == end) return b.others.append(b.arena, .{ .start = start, .end = end, .use = true });
        const tok = b.tokenOf(start) orelse return;
        if (!isUse(tok.cat)) return;
        try b.uses.append(b.arena, .{ .start = start, .end = end, .scope = item.scope, .res = .unresolved });
        try b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .use = @intCast(b.uses.items.len - 1) } });
    }

    fn define(b: *Builder, item: Item, line: u16, start: u32, end: u32) error{OutOfMemory}!void {
        const d = table.defines[line];
        const node = b.p.span(item.owner);
        // The nearest scope at or around the node: the owner's children's.
        var scope = item.scope;
        var inner: ?u32 = null;
        if (d.outer) if (b.scopes.items[scope].parent) |up| {
            inner = scope;
            scope = up;
        };
        const items = item.owner.items();
        var def: Def = .{
            .name = b.text[start..end],
            .start = start,
            .end = end,
            .scope = scope,
            .inner = inner,
            .line = line,
            .node_start = if (d.at.rest) start else node.start,
            .node_end = if (d.at.rest) end else node.end,
            .visible = node.end,
            .detail_end = node.end,
            .exported = switch (d.@"export") {
                .none => scope == 0,
                .slot => |s| s < items.len and items[s] != .nil,
                .parent => |parent| item.parent.kind() == parent,
            },
        };
        switch (d.detail) {
            .upto => |s| if (s < items.len and items[s] != .nil) {
                def.detail_end = b.p.span(items[s]).start;
            },
            else => {},
        }
        if (d.type) |s| if (s < items.len and items[s] != .nil) {
            const span = b.p.span(items[s]);
            def.type_span = .{ span.start, span.end };
        };
        switch (d.doc) {
            .role => |r| {
                var leaves: std.ArrayList([2]u32) = .empty;
                const kids: []const Sexp = if (r.rest) (if (r.slot < items.len) items[r.slot..] else &.{}) else if (r.slot < items.len) items[r.slot .. r.slot + 1] else &.{};
                for (kids) |kid| try b.leavesOf(kid, &leaves);
                def.doc = leaves.items;
            },
            else => {},
        }
        if (d.outer or b.opened.get(@intFromPtr(item.owner.list.ptr)) == scope) def.visible = end;
        try b.defs.append(b.arena, def);
        const id: u32 = @intCast(b.defs.items.len - 1);
        try b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .def = id } });
        if (d.value) |s| if (s < items.len and items[s] == .list) {
            try b.values.append(b.arena, .{ .def = id, .node = @intFromPtr(items[s].list.ptr) });
        };
        // A definition of a node that opens a scope has that scope inside.
        if (!d.outer and inner == null) if (b.opened.get(@intFromPtr(item.owner.list.ptr))) |s| {
            if (s != scope) b.defs.items[id].inner = s;
        };
    }

    /// The leaves of a value: itself, or a group's.
    fn leavesOf(b: *Builder, v: Sexp, out: *std.ArrayList([2]u32)) error{OutOfMemory}!void {
        switch (v) {
            .src => |x| try out.append(b.arena, .{ x.pos, b.p.leafEnd(x) }),
            .list => for (v.items()) |x| if (x == .src) try out.append(b.arena, .{ x.src.pos, b.p.leafEnd(x.src) }),
            else => {},
        }
    }

    /// Whether every condition holds of the node `item` is a child of.
    fn holds(b: *Builder, item: Item, when: []const Define.When) bool {
        for (when) |w| {
            const node = if (w.parent) |p| (if (item.parent.kind() == p) item.parent else return false) else item.owner;
            if (w.text) |t| {
                if (!std.mem.eql(u8, b.childText(node, w.slot), t)) return false;
            } else {
                const items = node.items();
                if (w.slot >= items.len or items[w.slot] == .nil) return false;
            }
        }
        return true;
    }

    fn builtinAt(b: *Builder, start: u32, end: u32) bool {
        if (isBuiltin(b.text[start..end])) return true;
        const t = b.tokenOf(start) orelse return false;
        for (table.builtin_tokens) |bt| if (bt == t.cat) return true;
        return false;
    }

    fn childText(b: *Builder, node: Sexp, slot: u16) []const u8 {
        const items = node.items();
        if (slot >= items.len) return "";
        return b.p.leafText(items[slot]);
    }

    fn tokenOf(b: *Builder, pos: u32) ?parser.Token {
        const toks = b.tokens.items;
        var lo: usize = 0;
        var hi: usize = toks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (toks[mid].pos < pos) lo = mid + 1 else hi = mid;
        }
        if (lo < toks.len and toks[lo].pos == pos) return toks[lo];
        return null;
    }

    /// Resolve every use: up its chain of scopes, the nearest definition
    /// of its name in sight; else a builtin; else unresolved.
    fn resolve(b: *Builder) error{OutOfMemory}!void {
        var byName: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty;
        for (b.defs.items, 0..) |d, i| {
            if (table.defines[d.line].visibility == .member) continue;
            const gop = try byName.getOrPut(b.arena, d.name);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(b.arena, @intCast(i));
        }
        var chain: std.ArrayList(u32) = .empty;
        for (b.uses.items) |*u| {
            const name = b.text[u.start..u.end];
            if (byName.get(name)) |candidates| {
                chain.clearRetainingCapacity();
                var s: ?u32 = u.scope;
                while (s) |x| : (s = b.scopes.items[x].parent) try chain.append(b.arena, x);
                var best: ?u32 = null;
                var bestDepth: usize = std.math.maxInt(usize);
                for (candidates.items) |c| {
                    const d = b.defs.items[c];
                    const depth = std.mem.findScalar(u32, chain.items, d.scope) orelse continue;
                    if (depth > bestDepth) continue;
                    const unordered = b.scopes.items[d.scope].unordered;
                    if (!unordered and d.visible > u.start) continue;
                    if (depth == bestDepth) {
                        // Ordered: the last before the use; unordered: the first.
                        const prev = b.defs.items[best.?];
                        if (unordered or d.start < prev.start) continue;
                    }
                    best = c;
                    bestDepth = depth;
                }
                if (best) |d| {
                    u.res = .{ .def = d };
                    continue;
                }
            }
            if (isBuiltin(name)) {
                u.res = .builtin;
                continue;
            }
            if (b.tokenOf(u.start)) |t| for (table.builtin_tokens) |bt| if (bt == t.cat) {
                u.res = .builtin;
            };
        }
    }
};

fn slotMatches(s: Slot, slot: u16) bool {
    return if (s.rest) slot >= s.slot else slot == s.slot;
}

fn scopeKind(k: Tag) ?ScopeKind {
    for (table.scopes) |s| if (s.kind == k) return s;
    return null;
}

fn isUse(cat: TokenCat) bool {
    for (table.uses) |u| if (u == cat) return true;
    return false;
}

fn isBuiltin(name: []const u8) bool {
    for (table.builtins) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

// =============================================================================
// Rename
// =============================================================================

/// A rename of definition `d` to `name`: the spans to replace, or why it
/// is refused. It is refused for a name another file can see, and unless,
/// the edits made and the text indexed again, every name the definition
/// had resolves to it under the new name, every other use resolves as it
/// did, and no other definition of its scope has the new name.
pub fn rename(arena: Allocator, ix: *const Index, d: u32, name: []const u8) error{OutOfMemory}!union(enum) { spans: []const [2]u32, refused: []const u8 } {
    const def = ix.defs[d];
    if (def.exported) return .{ .refused = try arena.print("'{s}' is visible to other files, and the server resolves names within one file: it renames only what other files cannot see", .{def.name}) };
    const spans = try ix.references(arena, d);
    // The text with the edits made.
    var out: std.ArrayList(u8) = .empty;
    var from: u32 = 0;
    for (spans) |s| {
        try out.appendSlice(arena, ix.text[from..s[0]]);
        try out.appendSlice(arena, name);
        from = s[1];
    }
    try out.appendSlice(arena, ix.text[from..]);
    const again = try index(arena, out.items);
    const delta: i64 = @as(i64, @intCast(name.len)) - @as(i64, @intCast(def.end - def.start));
    const Map = struct {
        spans: []const [2]u32,
        delta: i64,
        fn of(m: @This(), pos: u32) u32 {
            var n: i64 = 0;
            for (m.spans) |s| {
                if (s[0] < pos) n += 1 else break;
            }
            return @intCast(@as(i64, pos) + n * m.delta);
        }
    };
    const map: Map = .{ .spans = spans, .delta = delta };
    const changed = "the new name changes what the file's names are";
    if (again.defs.len != ix.defs.len or again.uses.len != ix.uses.len) return .{ .refused = changed };
    const renamed = map.of(def.start);
    for (ix.uses, again.uses) |u, v| {
        if (map.of(u.start) != v.start) return .{ .refused = changed };
        const was: ?u32 = switch (u.res) {
            .def => |x| x,
            else => null,
        };
        if (was != null and was.? == d) {
            if (v.res != .def or again.defs[v.res.def].start != renamed)
                return .{ .refused = try arena.print("the use of '{s}' on line {d} would name another '{s}'", .{ def.name, lineOf(ix.text, u.start), name }) };
            continue;
        }
        const ok = switch (u.res) {
            .def => |x| v.res == .def and again.defs[v.res.def].start == map.of(ix.defs[x].start),
            .builtin => v.res == .builtin,
            .unresolved => v.res == .unresolved,
        };
        if (!ok) return .{ .refused = try arena.print("'{s}' would capture the use of '{s}' on line {d}", .{ name, ix.text[u.start..u.end], lineOf(ix.text, u.start) }) };
    }
    const scope = again.defs[findDef(&again, renamed) orelse return .{ .refused = changed }].scope;
    for (again.defs) |o| {
        if (o.start == renamed or o.scope != scope) continue;
        if (std.mem.eql(u8, o.name, name)) return .{ .refused = try arena.print("'{s}' is defined in this scope already", .{name}) };
    }
    return .{ .spans = spans };
}

/// The line of `pos`, from 1.
fn lineOf(text: []const u8, pos: u32) usize {
    return std.mem.count(u8, text[0..pos], "\n") + 1;
}

fn findDef(ix: *const Index, start: u32) ?u32 {
    for (ix.defs, 0..) |x, i| if (x.start == start) return @intCast(i);
    return null;
}
