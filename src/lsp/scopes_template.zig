//! scopes.zig: the names and scopes of a language's files, from the
//! `@lsp` lines of its grammar (docs/GRAMMAR.md, "Names and scopes"),
//! written by `nexus --editor` beside the server (`lsp.zig`) for a grammar
//! with `@lsp`.
//!
//! `index` parses a text (tolerantly, with `@repair`) and walks its tree
//! once. A node of a scope kind opens a scope, and a node an `import` line
//! takes is an import of the file its leaf names. A leaf is skipped when a
//! `skip` line with conditions takes it; else it is a definition when a
//! `define` line takes it (the first whose conditions hold), of the
//! nearest scope at or around its node (the one around that, with
//! `outer`); else it is skipped when a plain `skip` line names its role;
//! else it is a member when a `member` line names its role, a qualified
//! name when a `qualify` line does and its node imports a file, the name
//! of an import's file, a name of a namespace when its token is
//! `nominal`; else, a leaf of a `use` token is a use, which resolves up
//! its chain of scopes to the nearest definition of its name: any in an
//! unordered scope; in an ordered one, the last whose node ends before it
//! (whose own leaf does, for an `outer` definition or one of the node that
//! opens its scope). A name that resolves to none is a builtin when
//! `builtin` lists it, else unresolved.
//!
//! The rest resolves across files, through a `World` that gives each
//! file's index (`Resolver`): what an expression denotes (a scope, a file,
//! a definition's value or declared type), the definition a member or a
//! qualified name names, references and rename over many files.
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
    /// A `bind` line: the leaf defines its name unless a definition of the
    /// name is in sight there, whose use it then is.
    bind: bool = false,

    /// The leaf in slot `slot` of the node (of its parent, when the parent
    /// is a `parent`) is `text`, an absent one's text being empty; with
    /// `kind`, the slot holds a node of the kind; with neither, the slot
    /// is not empty.
    pub const When = struct { parent: ?Tag = null, slot: u16, text: ?[]const u8 = null, kind: ?Tag = null };
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

/// `import`: the leaf in `at` (the first of a rest role) names a file;
/// `file` is its path, `{}` standing for the name.
pub const Import = struct { at: Slot, when: []const Define.When = &.{}, file: ?[]const u8 = null };

/// `member`: the leaf in `at` is a member of what slot `of` denotes.
pub const Member = struct { at: Slot, of: u16 };

/// `qualify`: the leaf in `at` is a name of the file slot `in` imports.
pub const Qualify = struct { at: Slot, in: u16 };

/// `nominal`: a leaf of `cat` is a name of namespace `ns`.
pub const Nominal = struct { cat: TokenCat, ns: u16 };

/// `color`: the semantic token of the leaf in `at`, or with an `edge`, of
/// the first or last token of a node of `at.kind`.
pub const Color = struct {
    at: Slot,
    edge: Edge = .none,
    when: []const Define.When = &.{},
    scope: lsp.Scope,
    modifiers: lsp.Modifiers = .{},

    pub const Edge = enum { none, start, end };
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
    imports: []const Import = &.{},
    members: []const Member = &.{},
    qualifies: []const Qualify = &.{},
    nominals: []const Nominal = &.{},
    /// The namespaces of `nominal`, by number.
    namespaces: []const []const u8 = &.{},
    colors: []const Color = &.{},
    /// The extensions of the language's files, which make up a workspace.
    extensions: []const []const u8 = &.{},
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
    /// Its `define` (or `bind`) line.
    line: u16,
    /// The `color` line of its leaf, which its uses take too.
    color: ?u16 = null,
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
    /// Whether another file sees it, as a member or a qualified name.
    exported: bool,
    /// What its value denotes: an import when its node is one, else its
    /// `value:` role's; and what its `type:` role denotes. Members of the
    /// name are looked up in the value's scope, else in the type's.
    value: Expr = .none,
    typed: Expr = .none,
};

pub const Resolution = union(enum) { def: u32, builtin, unresolved };

pub const Use = struct { start: u32, end: u32, scope: u32, res: Resolution };

/// What an expression denotes, as far as names tell: what a use resolves
/// to, a member, an import's file, or a scope its node opens. A node
/// whose one child is a use denotes what the use does.
pub const Expr = union(enum) { none, use: u32, member: u32, import: u32, scope: u32 };

/// An import: its leaf, and the name it gives (a string's contents).
pub const ImportRef = struct { start: u32, end: u32, name: []const u8, line: u16 };

/// A member: its leaf (empty for a hole), and what it is a member of.
pub const MemberRef = struct { start: u32, end: u32, of: Expr = .none };

/// A qualified name: its leaf (empty for a hole), and the import of its
/// node that names its file.
pub const Qualified = struct { start: u32, end: u32, file: u32 };

/// A name of a namespace (`nominal`).
pub const NominalRef = struct { start: u32, end: u32, ns: u16 };

/// A name in the text: a definition's leaf, a use, a member, a qualified
/// name, an import's leaf, or a name of a namespace.
pub const Occurrence = struct {
    start: u32,
    end: u32,
    what: union(enum) { def: u32, use: u32, member: u32, qualified: u32, import: u32, nominal: u32 },
};

/// A leaf no lookup reads: a skipped one, a definition's, or a hole the
/// tolerant parse inserted.
const Other = struct { start: u32, end: u32, use: bool };

/// A token a `color` line colours: a leaf of its role, or a node's first
/// or last token.
pub const Colored = struct { start: u32, end: u32, color: u16 };

pub const Index = struct {
    text: []const u8,
    tokens: []const parser.Token,
    scopes: []const Scope,
    defs: []const Def,
    uses: []const Use,
    imports: []const ImportRef,
    members: []const MemberRef,
    qualified: []const Qualified,
    nominals: []const NominalRef,
    /// Every name, by position.
    occurrences: []const Occurrence,
    /// Every other leaf, and every hole, by position: what completion
    /// asks of the word at the cursor.
    others: []const Other,
    /// The tokens `color` lines colour, by position.
    colored: []const Colored,
    /// The definitions of each name.
    byName: std.StringHashMapUnmanaged(std.ArrayList(u32)),

    /// The name at `at`: the one it is in, else the one it ends.
    pub fn at(self: *const Index, offset: u32) ?Occurrence {
        const occ = self.occurrences;
        var lo: usize = 0;
        var hi: usize = occ.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (occ[mid].start <= offset) lo = mid + 1 else hi = mid;
        }
        if (lo > 0 and offset <= occ[lo - 1].end) return occ[lo - 1];
        return null;
    }

    /// The text of an occurrence.
    pub fn textOf(self: *const Index, o: Occurrence) []const u8 {
        return self.text[o.start..o.end];
    }

    /// Whether a hole at `pos` is where `offset` is: only blanks between.
    fn holeAt(self: *const Index, pos: u32, offset: u32) bool {
        const lo = @min(pos, offset);
        const hi = @max(pos, offset);
        return hi <= self.text.len and std.mem.trim(u8, self.text[lo..hi], " \t").len == 0;
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
        // The definition being written at `offset` is not offered.
        const here: ?u32 = if (self.at(offset)) |o| switch (o.what) {
            .def => |d| d,
            else => null,
        } else null;
        var scope: ?u32 = self.scopeAt(offset);
        var picks: std.StringArrayHashMapUnmanaged(u32) = .empty;
        while (scope) |s| : (scope = self.scopes[s].parent) {
            const unordered = self.scopes[s].unordered;
            // Of each name, the last definition of the scope: in an ordered
            // scope, the last before `offset`, the one in sight.
            picks.clearRetainingCapacity();
            for (self.defs, 0..) |d, i| {
                if (d.scope != s or table.defines[d.line].visibility == .member) continue;
                if (!unordered and d.visible >= offset) continue;
                if (here != null and here.? == i) continue;
                const gop = try picks.getOrPut(arena, d.name);
                if (!gop.found_existing or self.defs[gop.value_ptr.*].start < d.start) gop.value_ptr.* = @intCast(i);
            }
            // The scope's names, the last defined first.
            const ids = try arena.dupe(u32, picks.values());
            std.mem.sort(u32, ids, self, struct {
                fn later(ix: *const Index, x: u32, y: u32) bool {
                    return ix.defs[x].start > ix.defs[y].start;
                }
            }.later);
            for (ids) |i| {
                const gop = try seen.getOrPut(arena, self.defs[i].name);
                if (gop.found_existing) continue;
                try out.append(arena, i);
            }
        }
        return out.items;
    }

    /// Whether completion at `offset` offers names: unless the word there
    /// (or the hole the tolerant parse put there) is a definition's, a
    /// skipped role's, a member's or another name a scope does not hold,
    /// where a name in scope cannot go. An assignment's target that
    /// defines its name (`bind`) may assign one in sight instead.
    pub fn wantsNames(self: *const Index, offset: u32) bool {
        if (self.at(offset)) |o| return switch (o.what) {
            .use => true,
            .def => |d| table.defines[self.defs[d].line].bind,
            else => false,
        };
        for (self.others) |o| {
            if (o.start == o.end) {
                if (self.holeAt(o.start, offset)) return o.use;
            } else if (o.start <= offset and offset <= o.end) return o.use;
        }
        return true;
    }

    /// The member or qualified name at `offset`, a hole's included.
    fn memberAt(self: *const Index, offset: u32) ?union(enum) { member: u32, qualified: u32 } {
        for (self.members, 0..) |m, i| if (if (m.start == m.end) self.holeAt(m.start, offset) else m.start <= offset and offset <= m.end)
            return .{ .member = @intCast(i) };
        for (self.qualified, 0..) |q, i| if (if (q.start == q.end) self.holeAt(q.start, offset) else q.start <= offset and offset <= q.end)
            return .{ .qualified = @intCast(i) };
        return null;
    }

    /// The symbol of definition `d` of the file at `path`, for the server.
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
        // A bind's definition is made after the walk: in the order of the
        // text.
        std.mem.sort(lsp.OutlineItem, out.items, {}, struct {
            fn lt(_: void, x: lsp.OutlineItem, y: lsp.OutlineItem) bool {
                return x.name_start < y.name_start;
            }
        }.lt);
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
    try b.bindAll();
    try b.resolve();
    try b.denote();
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
    std.mem.sort(Colored, b.colored.items, {}, struct {
        fn lt(_: void, x: Colored, y: Colored) bool {
            return x.start < y.start;
        }
    }.lt);
    var byName: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty;
    for (b.defs.items, 0..) |d, i| {
        const gop = try byName.getOrPut(arena, d.name);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(arena, @intCast(i));
    }
    return .{
        .text = text,
        .tokens = b.tokens.items,
        .scopes = b.scopes.items,
        .defs = b.defs.items,
        .uses = b.uses.items,
        .imports = b.imports.items,
        .members = b.members.items,
        .qualified = b.qualified.items,
        .nominals = b.nominals.items,
        .occurrences = b.occurrences.items,
        .others = b.others.items,
        .colored = b.colored.items,
        .byName = byName,
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
    imports: std.ArrayList(ImportRef) = .empty,
    members: std.ArrayList(MemberRef) = .empty,
    qualified: std.ArrayList(Qualified) = .empty,
    nominals: std.ArrayList(NominalRef) = .empty,
    /// The import each import node makes, and the member each node of a
    /// member's role is, by the node's items.
    importOf: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    memberOf: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    /// The use at each position.
    useAt: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// The values whose denotations are found after the walk: of each
    /// member, what it is a member of; of each definition, its value and
    /// type roles'.
    operands: std.ArrayList(struct { member: u32, value: Sexp }) = .empty,
    defValues: std.ArrayList(struct { def: u32, value: Sexp, typed: Sexp }) = .empty,
    /// The leaves `bind` lines take, in the order of the text, each made a
    /// definition or a use after the walk.
    binds: std.ArrayList(struct { item: Item, line: u16, start: u32, end: u32 }) = .empty,
    colored: std.ArrayList(Colored) = .empty,

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
                try b.importAt(item, kind);
                if (comptime table.colors.len > 0) try b.edgeColors(item, kind);
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

    /// The import a node of `kind` makes: the first `import` line on the
    /// kind whose conditions hold and whose role holds a leaf.
    fn importAt(b: *Builder, item: Item, kind: Tag) error{OutOfMemory}!void {
        const node: Item = .{ .value = item.value, .owner = item.value, .parent = item.owner, .slot = 0, .scope = item.scope };
        const items = item.value.items();
        for (table.imports, 0..) |im, line| {
            if (im.at.kind != kind or im.at.slot >= items.len or items[im.at.slot] != .src) continue;
            if (!b.holds(node, im.when)) continue;
            const leaf = items[im.at.slot].src;
            const start = leaf.pos;
            const end = b.p.leafEnd(leaf);
            if (start == end) continue;
            try b.imports.append(b.arena, .{ .start = start, .end = end, .name = unquote(b.text[start..end]), .line = @intCast(line) });
            try b.importOf.put(b.arena, @intFromPtr(item.value.list.ptr), @intCast(b.imports.items.len - 1));
            return;
        }
    }

    /// The `color` line of a node's first and last tokens.
    fn edgeColors(b: *Builder, item: Item, kind: Tag) error{OutOfMemory}!void {
        const node: Item = .{ .value = item.value, .owner = item.value, .parent = item.owner, .slot = 0, .scope = item.scope };
        var done: [2]bool = .{ false, false };
        for (table.colors, 0..) |c, line| {
            if (c.edge == .none or c.at.kind != kind or done[@intFromBool(c.edge == .end)]) continue;
            if (!b.holds(node, c.when)) continue;
            done[@intFromBool(c.edge == .end)] = true;
            const span = b.p.span(item.value);
            const t = (if (c.edge == .start) b.solidFrom(span.start, span.end) else b.solidBefore(span.start, span.end)) orelse continue;
            try b.colored.append(b.arena, .{ .start = t.pos, .end = t.pos + t.len, .color = @intCast(line) });
        }
    }

    /// The first token of `start..end` with text other than blanks and
    /// line ends, not a comment.
    fn solidFrom(b: *Builder, start: u32, end: u32) ?parser.Token {
        var i = b.firstAt(start);
        while (i < b.tokens.items.len and b.tokens.items[i].pos < end) : (i += 1) {
            const t = b.tokens.items[i];
            if (isSolid(b.text, t)) return t;
        }
        return null;
    }

    /// The last such token that ends by `end`.
    fn solidBefore(b: *Builder, start: u32, end: u32) ?parser.Token {
        var i = b.firstAt(end);
        while (i > 0) {
            i -= 1;
            const t = b.tokens.items[i];
            if (t.pos < start) return null;
            if (t.pos + t.len <= end and isSolid(b.text, t)) return t;
        }
        return null;
    }

    /// The first token that starts at or after `pos`.
    fn firstAt(b: *Builder, pos: u32) usize {
        const toks = b.tokens.items;
        var lo: usize = 0;
        var hi: usize = toks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (toks[mid].pos < pos) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    /// The `color` line of a leaf of slot `item.slot` of a `kind` node: the
    /// first whose conditions hold.
    fn colorOf(b: *Builder, item: Item, kind: Tag) ?u16 {
        for (table.colors, 0..) |c, line| {
            if (c.edge != .none or c.at.kind != kind or !slotMatches(c.at, item.slot)) continue;
            if (b.holds(item, c.when)) return @intCast(line);
        }
        return null;
    }

    /// Classify a leaf of slot `item.slot` of `item.owner`.
    fn classify(b: *Builder, item: Item, leafv: parser.Src) error{OutOfMemory}!void {
        const start = leafv.pos;
        const end = b.p.leafEnd(leafv);
        const ownerKind = item.owner.kind();
        if (ownerKind) |k| {
            if (comptime table.colors.len > 0) if (start < end) if (b.colorOf(item, k)) |c| {
                try b.colored.append(b.arena, .{ .start = start, .end = end, .color = c });
            };
            for (table.skips) |s| if (s.when.len > 0 and s.at.kind == k and slotMatches(s.at, item.slot) and b.holds(item, s.when))
                return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
            for (table.defines, 0..) |d, line| {
                if (d.at.kind != k or !slotMatches(d.at, item.slot)) continue;
                if (!b.holds(item, d.when)) continue;
                // A hole, and a builtin's name, which is never defined in
                // sight; a member, which is never in sight, may have one.
                if (start == end or (d.visibility != .member and b.builtinAt(start, end))) return b.others.append(b.arena, .{ .start = start, .end = end, .use = d.bind });
                if (d.bind) return b.binds.append(b.arena, .{ .item = item, .line = @intCast(line), .start = start, .end = end });
                return b.define(item, @intCast(line), start, end);
            }
            for (table.skips) |s| if (s.when.len == 0 and s.at.kind == k and slotMatches(s.at, item.slot))
                return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
            const key = @intFromPtr(item.owner.list.ptr);
            for (table.members) |m| if (m.at.kind == k and slotMatches(m.at, item.slot)) {
                const items = item.owner.items();
                try b.members.append(b.arena, .{ .start = start, .end = end });
                const id: u32 = @intCast(b.members.items.len - 1);
                try b.memberOf.put(b.arena, key, id);
                try b.operands.append(b.arena, .{ .member = id, .value = if (m.of < items.len) items[m.of] else .nil });
                if (start == end) return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
                return b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .member = id } });
            };
            const imp = b.importOf.get(key);
            // Qualified by the file its node imports; without the import,
            // the leaf is what it would be without the `qualify` line.
            for (table.qualifies) |q| if (q.at.kind == k and slotMatches(q.at, item.slot)) {
                const file = imp orelse break;
                if (importLine(b.imports.items[file].line).at.slot != q.in) break;
                try b.qualified.append(b.arena, .{ .start = start, .end = end, .file = file });
                if (start == end) return b.others.append(b.arena, .{ .start = start, .end = end, .use = false });
                return b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .qualified = @intCast(b.qualified.items.len - 1) } });
            };
            if (imp) |i| if (b.imports.items[i].start == start)
                return b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .import = i } });
        }
        // A hole the tolerant parse inserted has no token of its own.
        if (start == end) return b.others.append(b.arena, .{ .start = start, .end = end, .use = true });
        const tok = b.tokenOf(start) orelse return;
        for (table.nominals) |n| if (n.cat == tok.cat) {
            try b.nominals.append(b.arena, .{ .start = start, .end = end, .ns = n.ns });
            return b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .nominal = @intCast(b.nominals.items.len - 1) } });
        };
        if (!isUse(tok.cat)) return;
        try b.uses.append(b.arena, .{ .start = start, .end = end, .scope = item.scope, .res = .unresolved });
        const id: u32 = @intCast(b.uses.items.len - 1);
        try b.useAt.put(b.arena, start, id);
        try b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .use = id } });
    }

    /// What each member is a member of, and what each definition's value
    /// and type denote.
    fn denote(b: *Builder) error{OutOfMemory}!void {
        for (b.operands.items) |o| b.members.items[o.member].of = b.exprOf(o.value);
        for (b.defValues.items) |v| {
            const d = &b.defs.items[v.def];
            if (d.value == .none) d.value = b.exprOf(v.value);
            d.typed = b.exprOf(v.typed);
        }
    }

    /// What a value denotes: a use's leaf, a node whose one child is one,
    /// a member's node, an import, or a node that opens a scope.
    fn exprOf(b: *Builder, v: Sexp) Expr {
        switch (v) {
            .src => |leaf| if (b.useAt.get(leaf.pos)) |u| return .{ .use = u },
            .list => |list| {
                const key = @intFromPtr(list.ptr);
                if (b.memberOf.get(key)) |m| return .{ .member = m };
                if (b.importOf.get(key)) |i| return .{ .import = i };
                if (b.opened.get(key)) |s| return .{ .scope = s };
                const items = list.items();
                if (v.kind() != null and items.len == 2 and items[1] == .src) return b.exprOf(items[1]);
            },
            else => {},
        }
        return .none;
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
                .none => true,
                .slot => |s| s < items.len and items[s] != .nil,
                .parent => |parent| item.parent.kind() == parent,
            },
        };
        // A definition whose node is an import has the import's file as
        // its value.
        if (b.importOf.get(@intFromPtr(item.owner.list.ptr))) |i| def.value = .{ .import = i };
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
        if (comptime table.colors.len > 0) if (item.owner.kind()) |k| {
            def.color = b.colorOf(item, k);
        };
        try b.defs.append(b.arena, def);
        const id: u32 = @intCast(b.defs.items.len - 1);
        try b.occurrences.append(b.arena, .{ .start = start, .end = end, .what = .{ .def = id } });
        if (d.value) |s| if (s < items.len and items[s] == .list) {
            try b.values.append(b.arena, .{ .def = id, .node = @intFromPtr(items[s].list.ptr) });
        };
        const value: Sexp = if (d.value) |s| (if (s < items.len) items[s] else .nil) else .nil;
        const typed: Sexp = if (d.type) |s| (if (s < items.len) items[s] else .nil) else .nil;
        if (value != .nil or typed != .nil) try b.defValues.append(b.arena, .{ .def = id, .value = value, .typed = typed });
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
            if (w.kind) |k| {
                const items = node.items();
                if (w.slot >= items.len or items[w.slot].kind() != k) return false;
            } else if (w.text) |t| {
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

    /// The definitions in sight by name, of every definition made so far.
    const ByName = std.StringHashMapUnmanaged(std.ArrayList(u32));

    fn addName(b: *Builder, byName: *ByName, d: u32) error{OutOfMemory}!void {
        const def = b.defs.items[d];
        if (table.defines[def.line].visibility == .member) return;
        const gop = try byName.getOrPut(b.arena, def.name);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(b.arena, d);
    }

    /// The definition a name at `at`, in `scope`, resolves to: up the
    /// chain of scopes, the nearest definition of the name in sight.
    fn lookupAt(b: *Builder, byName: *const ByName, chain: *std.ArrayList(u32), name: []const u8, scope: u32, at: u32) error{OutOfMemory}!?u32 {
        const candidates = byName.get(name) orelse return null;
        chain.clearRetainingCapacity();
        var s: ?u32 = scope;
        while (s) |x| : (s = b.scopes.items[x].parent) try chain.append(b.arena, x);
        var best: ?u32 = null;
        var bestDepth: usize = std.math.maxInt(usize);
        for (candidates.items) |c| {
            const d = b.defs.items[c];
            const depth = std.mem.findScalar(u32, chain.items, d.scope) orelse continue;
            if (depth > bestDepth) continue;
            const unordered = b.scopes.items[d.scope].unordered;
            if (!unordered and d.visible > at) continue;
            if (depth == bestDepth) {
                // Ordered: the last before the use; unordered: the first.
                const prev = b.defs.items[best.?];
                if (if (unordered) d.start > prev.start else d.start < prev.start) continue;
            }
            best = c;
            bestDepth = depth;
        }
        return best;
    }

    /// Each leaf a `bind` line takes, in the order of the text: a use of
    /// the definition of its name in sight there (a define line's, or an
    /// earlier bind's), else a definition.
    fn bindAll(b: *Builder) error{OutOfMemory}!void {
        if (b.binds.items.len == 0) return;
        var byName: ByName = .empty;
        for (0..b.defs.items.len) |i| try b.addName(&byName, @intCast(i));
        var chain: std.ArrayList(u32) = .empty;
        for (b.binds.items) |x| {
            if (try b.lookupAt(&byName, &chain, b.text[x.start..x.end], x.item.scope, x.start)) |d| {
                try b.uses.append(b.arena, .{ .start = x.start, .end = x.end, .scope = x.item.scope, .res = .{ .def = d } });
                const id: u32 = @intCast(b.uses.items.len - 1);
                try b.useAt.put(b.arena, x.start, id);
                try b.occurrences.append(b.arena, .{ .start = x.start, .end = x.end, .what = .{ .use = id } });
                continue;
            }
            try b.define(x.item, x.line, x.start, x.end);
            try b.addName(&byName, @intCast(b.defs.items.len - 1));
        }
    }

    /// Resolve every use: up its chain of scopes, the nearest definition
    /// of its name in sight; else a builtin; else unresolved. A bind's use
    /// is resolved already.
    fn resolve(b: *Builder) error{OutOfMemory}!void {
        var byName: ByName = .empty;
        for (0..b.defs.items.len) |i| try b.addName(&byName, @intCast(i));
        var chain: std.ArrayList(u32) = .empty;
        for (b.uses.items) |*u| {
            if (u.res != .unresolved) continue;
            const name = b.text[u.start..u.end];
            if (try b.lookupAt(&byName, &chain, name, u.scope, u.start)) |d| {
                u.res = .{ .def = d };
                continue;
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

/// The name an import's leaf gives: a string's contents (between its
/// quotes, as written), else its text.
fn unquote(text: []const u8) []const u8 {
    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'') and text[text.len - 1] == text[0]) return text[1 .. text.len - 1];
    return text;
}

// =============================================================================
// Files: imports, members and qualified names
// =============================================================================

/// The files a resolution reads: each one's index, and the files modules
/// name.
pub const World = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// The index of the file at `path`; null when it cannot be read.
        load: *const fn (ptr: *anyopaque, path: []const u8) error{OutOfMemory}!?*const Index,
        /// The file the import `name` of the file at `from` names when
        /// `name` is a module's; null to take it as a path.
        module: *const fn (ptr: *anyopaque, from: []const u8, name: []const u8) error{OutOfMemory}!?[]const u8,
    };
};

/// A file and its index.
pub const File = struct { path: []const u8, ix: *const Index };

/// A definition of a file.
pub const Global = struct { file: File, def: u32 };

/// A scope of a file.
pub const Place = struct { file: File, scope: u32 };

/// What a name names: a definition, a file (an import's leaf), or a name
/// of a namespace.
pub const Target = union(enum) {
    def: Global,
    file: File,
    nominal: struct { ns: u16, name: []const u8 },

    /// The text of every name of the target: a definition's or a
    /// namespace's name; empty for a file, whose imports spell it many
    /// ways.
    pub fn name(t: Target) []const u8 {
        return switch (t) {
            .def => |g| g.file.ix.defs[g.def].name,
            .file => "",
            .nominal => |n| n.name,
        };
    }
};

/// The most steps a denotation takes (`std.mem.Allocator` takes three, an
/// alias one more); a cycle of aliases ends there and denotes nothing.
const max_depth = 64;

/// Resolution across files: what an expression denotes, and what a member
/// or a qualified name names, each looked up once (in `arena`).
pub const Resolver = struct {
    arena: Allocator,
    world: World,
    memo: std.AutoHashMapUnmanaged(Key, ?Global) = .empty,

    const Key = struct { ix: usize, qualified: bool, n: u32 };

    pub fn init(arena: Allocator, world: World) Resolver {
        return .{ .arena = arena, .world = world };
    }

    /// The file at `path`, indexed; null when it cannot be read.
    pub fn load(r: *Resolver, path: []const u8) error{OutOfMemory}!?File {
        const ix = (try r.world.vtable.load(r.world.ptr, path)) orelse return null;
        return .{ .path = path, .ix = ix };
    }

    /// The path of the file import `i` of `f` names: a module's file, else
    /// the name (with `file`, the path it makes of it) relative to `f`'s
    /// directory.
    pub fn importPath(r: *Resolver, f: File, i: u32) error{OutOfMemory}!?[]const u8 {
        const im = f.ix.imports[i];
        if (im.name.len == 0) return null;
        if (try r.world.vtable.module(r.world.ptr, f.path, im.name)) |p| return p;
        const rel = if (importLine(im.line).file) |pattern| try std.mem.replaceOwned(u8, r.arena, pattern, "{}", im.name) else im.name;
        if (std.fs.path.isAbsolute(rel)) return rel;
        if (!std.fs.path.isAbsolute(f.path)) return null;
        return try std.fs.path.resolveAlloc(r.arena, &.{ std.fs.path.dirname(f.path) orelse "/", rel });
    }

    /// The file import `i` of `f` names, indexed.
    pub fn importFile(r: *Resolver, f: File, i: u32) error{OutOfMemory}!?File {
        const path = (try r.importPath(f, i)) orelse return null;
        return r.load(path);
    }

    /// The scope the members of definition `g` are in: its value's, else
    /// its declared type's.
    pub fn defScope(r: *Resolver, g: Global, depth: u32) error{OutOfMemory}!?Place {
        const d = g.file.ix.defs[g.def];
        if (try r.exprScope(g.file, d.value, depth + 1)) |p| return p;
        return r.exprScope(g.file, d.typed, depth + 1);
    }

    /// The scope expression `e` of `f` denotes, whose names are members:
    /// an unordered one its node opens (a container; an ordered scope, a
    /// block's or a function's, has no members), an import's file, or the
    /// scope of what a use or a member names.
    pub fn exprScope(r: *Resolver, f: File, e: Expr, depth: u32) error{OutOfMemory}!?Place {
        if (depth > max_depth) return null;
        switch (e) {
            .none => return null,
            .scope => |s| return if (f.ix.scopes[s].unordered) .{ .file = f, .scope = s } else null,
            .import => |i| {
                const file = (try r.importFile(f, i)) orelse return null;
                return .{ .file = file, .scope = 0 };
            },
            .use => |u| switch (f.ix.uses[u].res) {
                .def => |d| return r.defScope(.{ .file = f, .def = d }, depth + 1),
                else => return null,
            },
            .member => |m| {
                const g = (try r.memberDef(f, m, depth + 1)) orelse return null;
                return r.defScope(g, depth + 1);
            },
        }
    }

    /// The definition member `m` of `f` names.
    pub fn memberDef(r: *Resolver, f: File, m: u32, depth: u32) error{OutOfMemory}!?Global {
        const key: Key = .{ .ix = @intFromPtr(f.ix), .qualified = false, .n = m };
        if (r.memo.get(key)) |g| return g;
        // A member met again while it is looked up is in a cycle: nothing.
        try r.memo.put(r.arena, key, null);
        const ref = f.ix.members[m];
        var got: ?Global = null;
        if (ref.start < ref.end) if (try r.exprScope(f, ref.of, depth + 1)) |place| {
            got = lookup(place, f.ix.text[ref.start..ref.end], f.path);
        };
        try r.memo.put(r.arena, key, got);
        return got;
    }

    /// The definition qualified name `q` of `f` names: one of the own
    /// scope of the file its node imports.
    pub fn qualifiedDef(r: *Resolver, f: File, q: u32) error{OutOfMemory}!?Global {
        const key: Key = .{ .ix = @intFromPtr(f.ix), .qualified = true, .n = q };
        if (r.memo.get(key)) |g| return g;
        const ref = f.ix.qualified[q];
        var got: ?Global = null;
        if (ref.start < ref.end) if (try r.importFile(f, ref.file)) |file| {
            got = lookup(.{ .file = file, .scope = 0 }, f.ix.text[ref.start..ref.end], f.path);
        };
        try r.memo.put(r.arena, key, got);
        return got;
    }

    /// What occurrence `o` of `f` names.
    pub fn resolve(r: *Resolver, f: File, o: Occurrence) error{OutOfMemory}!?Target {
        switch (o.what) {
            .def => |d| return .{ .def = .{ .file = f, .def = d } },
            .use => |u| return switch (f.ix.uses[u].res) {
                .def => |d| .{ .def = .{ .file = f, .def = d } },
                else => null,
            },
            .member => |m| return if (try r.memberDef(f, m, 0)) |g| .{ .def = g } else null,
            .qualified => |q| return if (try r.qualifiedDef(f, q)) |g| .{ .def = g } else null,
            .import => |i| return if (try r.importFile(f, i)) |file| .{ .file = file } else null,
            .nominal => |n| return .{ .nominal = .{ .ns = f.ix.nominals[n].ns, .name = f.ix.textOf(o) } },
        }
    }

    /// What the name at `offset` of `f` names.
    pub fn targetAt(r: *Resolver, f: File, offset: u32) error{OutOfMemory}!?Target {
        const o = f.ix.at(offset) orelse return null;
        return r.resolve(f, o);
    }

    /// The definitions a member or a qualified name at `offset` of `f`
    /// (a hole's included) can name, one per name; null when no member
    /// or qualified name is there.
    pub fn membersAt(r: *Resolver, f: File, offset: u32) error{OutOfMemory}!?[]const Global {
        const which = f.ix.memberAt(offset) orelse return null;
        var out: std.ArrayList(Global) = .empty;
        const place: Place = switch (which) {
            .member => |m| (try r.exprScope(f, f.ix.members[m].of, 0)) orelse return out.items,
            .qualified => |q| .{ .file = (try r.importFile(f, f.ix.qualified[q].file)) orelse return out.items, .scope = 0 },
        };
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        for (place.file.ix.defs, 0..) |d, i| {
            if (!sees(place, @intCast(i), f.path)) continue;
            if ((try seen.getOrPut(r.arena, d.name)).found_existing) continue;
            try out.append(r.arena, .{ .file = place.file, .def = @intCast(i) });
        }
        return out.items;
    }

    /// Every name of the files at `paths` that names `t`, by file and
    /// position.
    pub fn references(r: *Resolver, t: Target, paths: []const []const u8) error{OutOfMemory}![]const lsp.Span {
        var out: std.ArrayList(lsp.Span) = .empty;
        const name = t.name();
        for (paths) |path| {
            const f = (try r.load(path)) orelse continue;
            if (name.len > 0 and std.mem.find(u8, f.ix.text, name) == null) continue;
            for (f.ix.occurrences) |o| {
                if (if (t == .file) o.what != .import else !std.mem.eql(u8, f.ix.textOf(o), name)) continue;
                const got = (try r.resolve(f, o)) orelse continue;
                if (same(got, t)) try out.append(r.arena, .{ .path = path, .start = o.start, .end = o.end });
            }
        }
        return out.items;
    }
};

/// The semantic tokens `@lsp` gives file `f`, by position: each token a
/// `color` line colours, and each other name that names a definition whose
/// leaf one colours, with that line's scope and modifiers but
/// `declaration` and `definition`, which mark the definition's own leaf.
pub fn tokens(r: *Resolver, f: File) error{OutOfMemory}![]const lsp.Token {
    if (comptime table.colors.len == 0) return &.{};
    const ix = f.ix;
    var out: std.ArrayList(lsp.Token) = .empty;
    var c: usize = 0;
    for (ix.occurrences) |o| {
        // The tokens colour lines colour themselves come first.
        while (c < ix.colored.len and ix.colored[c].start <= o.start) : (c += 1) try addColored(r.arena, &out, ix.colored[c]);
        if (out.items.len > 0 and out.getLast().start == o.start) continue;
        if (o.what == .def) continue;
        const t = (try r.resolve(f, o)) orelse continue;
        if (t != .def) continue;
        const line = t.def.file.ix.defs[t.def.def].color orelse continue;
        var m = colorLine(line).modifiers;
        m.declaration = false;
        m.definition = false;
        try out.append(r.arena, .{ .start = o.start, .len = o.end - o.start, .scope = colorLine(line).scope, .modifiers = m });
    }
    while (c < ix.colored.len) : (c += 1) try addColored(r.arena, &out, ix.colored[c]);
    return out.items;
}

/// The token of a `color` line; of two at one token, the leaf's role's
/// (made after its node's) in place of the node's edge.
fn addColored(arena: Allocator, out: *std.ArrayList(lsp.Token), c: Colored) error{OutOfMemory}!void {
    const line = colorLine(c.color);
    const t: lsp.Token = .{ .start = c.start, .len = c.end - c.start, .scope = line.scope, .modifiers = line.modifiers };
    if (out.items.len > 0 and out.getLast().start == c.start) {
        out.items[out.items.len - 1] = t;
    } else try out.append(arena, t);
}

/// Whether a token has text other than blanks and line ends, and is not a
/// comment.
fn isSolid(text: []const u8, t: parser.Token) bool {
    if (t.len == 0 or t.pos >= text.len or Index.isComment(t)) return false;
    return std.mem.trim(u8, text[t.pos..][0..@min(t.len, text.len - t.pos)], " \t\r\n").len > 0;
}

/// The definition of `name` among the members of `place` that a name of
/// the file at `from` sees.
fn lookup(place: Place, name: []const u8, from: []const u8) ?Global {
    const list = place.file.ix.byName.get(name) orelse return null;
    for (list.items) |d| if (sees(place, d, from)) return .{ .file = place.file, .def = d };
    return null;
}

/// Whether definition `d` is a member of `place` that a name of the file
/// at `from` sees: one of its scope, not `lexical`, and exported unless
/// `from` is its file.
fn sees(place: Place, d: u32, from: []const u8) bool {
    const def = place.file.ix.defs[d];
    if (def.scope != place.scope or table.defines[def.line].visibility == .lexical) return false;
    return def.exported or std.mem.eql(u8, place.file.path, from);
}

/// Whether two targets are one.
pub fn same(a: Target, b: Target) bool {
    return switch (a) {
        .def => |x| b == .def and std.mem.eql(u8, x.file.path, b.def.file.path) and
            x.file.ix.defs[x.def].start == b.def.file.ix.defs[b.def.def].start,
        .file => |x| b == .file and std.mem.eql(u8, x.path, b.file.path),
        .nominal => |x| b == .nominal and x.ns == b.nominal.ns and std.mem.eql(u8, x.name, b.nominal.name),
    };
}

// =============================================================================
// Rename
// =============================================================================

/// A file's text in place of its own.
pub const Text = struct { path: []const u8, text: []const u8 };

/// The spans a rename of `t` edits over the files at `paths`: every name
/// of it; or why it is refused.
pub fn renameSpans(r: *Resolver, t: Target, paths: []const []const u8) error{OutOfMemory}!union(enum) { spans: []const lsp.Span, refused: []const u8 } {
    if (t == .file) return .{ .refused = "an import's name names a file: rename the file" };
    return .{ .spans = try r.references(t, paths) };
}

/// The texts of the files `spans` edit, each span replaced by `name`.
pub fn renamed(r: *Resolver, spans: []const lsp.Span, name: []const u8) error{OutOfMemory}![]const Text {
    var out: std.ArrayList(Text) = .empty;
    for (spans) |s| {
        const seen = for (out.items) |t| {
            if (std.mem.eql(u8, t.path, s.path)) break true;
        } else false;
        if (seen) continue;
        const f = (try r.load(s.path)) orelse continue;
        var text: std.ArrayList(u8) = .empty;
        var from: u32 = 0;
        for (spans) |x| if (std.mem.eql(u8, x.path, s.path)) {
            try text.appendSlice(r.arena, f.ix.text[from..x.start]);
            try text.appendSlice(r.arena, name);
            from = x.end;
        };
        try text.appendSlice(r.arena, f.ix.text[from..]);
        try out.append(r.arena, .{ .path = s.path, .text = text.items });
    }
    return out.items;
}

/// Why the rename of `t` to `name`, which edits `spans`, is refused; null
/// when it is not. `before` reads the files as they are and `after` with
/// the edits made (`renamed`). The rename is refused unless, in each file
/// at `paths` (every file that holds either name), every name of `t`
/// names it under the new name and every other name names what it did;
/// and no other definition of its scope, or name of its namespace, has
/// the new name.
pub fn renameRefusal(before: *Resolver, after: *Resolver, t: Target, name: []const u8, spans: []const lsp.Span, paths: []const []const u8) error{OutOfMemory}!?[]const u8 {
    const arena = before.arena;
    const old = t.name();
    const m: Shift = .{ .spans = spans, .delta = @as(i64, @intCast(name.len)) - @as(i64, @intCast(old.len)) };
    const changed = "the new name changes what the file's names are";
    const home = switch (t) {
        .def => |g| g.file.path,
        else => "",
    };
    if (t == .nominal) for (paths) |path| {
        const f = (try before.load(path)) orelse continue;
        for (f.ix.nominals) |n| if (n.ns == t.nominal.ns and std.mem.eql(u8, f.ix.text[n.start..n.end], name))
            return try arena.print("'{s}' is a name of {s} already", .{ name, namespace(n.ns) });
    };
    for (paths) |path| {
        const a = (try before.load(path)) orelse continue;
        const b = (try after.load(path)) orelse return changed;
        if (a.ix.occurrences.len != b.ix.occurrences.len) return changed;
        for (a.ix.occurrences, b.ix.occurrences) |oa, ob| {
            if (m.of(path, oa.start) != ob.start) return changed;
            const line = lineOf(a.ix.text, oa.start);
            const of = if (std.mem.eql(u8, path, home)) "" else try arena.print(" of {s}", .{std.fs.path.basename(path)});
            if (std.meta.activeTag(oa.what) != std.meta.activeTag(ob.what)) {
                // A bind that defines, and would assign the name in sight.
                if (oa.what == .def and ob.what == .use)
                    return try arena.print("'{s}' is in sight on line {d}{s}, where the assignment would assign it, not define a name", .{ b.ix.textOf(ob), line, of });
                return changed;
            }
            const was = try before.resolve(a, oa);
            const now = try after.resolve(b, ob);
            if (was != null and same(was.?, t)) {
                if (now == null or !m.same(was.?, now.?, name))
                    return try arena.print("the use of '{s}' on line {d}{s} would name another '{s}'", .{ old, line, of, name });
                continue;
            }
            const kept = if (was) |x| now != null and m.same(x, now.?, null) else now == null;
            if (!kept) return try arena.print("'{s}' would capture the use of '{s}' on line {d}{s}", .{ name, a.ix.textOf(oa), line, of });
        }
        if (a.ix.defs.len != b.ix.defs.len) return changed;
    }
    if (t == .def) {
        const g = t.def;
        const b = (try after.load(g.file.path)) orelse return changed;
        const at = m.of(g.file.path, g.file.ix.defs[g.def].start);
        const scope = b.ix.defs[findDef(b.ix, at) orelse return changed].scope;
        for (b.ix.defs) |o| {
            if (o.start == at or o.scope != scope) continue;
            if (std.mem.eql(u8, o.name, name)) return try arena.print("'{s}' is defined in this scope already", .{name});
        }
    }
    return null;
}

/// Positions of the texts before a rename in the texts after it: each
/// moves by `delta` for every edited span before it in its file.
const Shift = struct {
    spans: []const lsp.Span,
    delta: i64,

    fn of(m: Shift, path: []const u8, pos: u32) u32 {
        var n: i64 = 0;
        for (m.spans) |s| if (s.start < pos and std.mem.eql(u8, s.path, path)) {
            n += 1;
        };
        return @intCast(@as(i64, pos) + n * m.delta);
    }

    /// Whether `now`, a target after the rename, is `was` moved by it;
    /// with `name`, `was` renamed to it.
    fn same(m: Shift, was: Target, now: Target, name: ?[]const u8) bool {
        return switch (was) {
            .def => |x| now == .def and std.mem.eql(u8, x.file.path, now.def.file.path) and
                m.of(x.file.path, x.file.ix.defs[x.def].start) == now.def.file.ix.defs[now.def.def].start,
            .file => |x| now == .file and std.mem.eql(u8, x.path, now.file.path),
            .nominal => |x| now == .nominal and x.ns == now.nominal.ns and std.mem.eql(u8, name orelse x.name, now.nominal.name),
        };
    }
};

/// The `import` line `line`.
fn importLine(line: u16) Import {
    if (comptime table.imports.len == 0) unreachable;
    return table.imports[line];
}

/// The `color` line `line`.
fn colorLine(line: u16) Color {
    if (comptime table.colors.len == 0) unreachable;
    return table.colors[line];
}

/// The name of namespace `ns`.
fn namespace(ns: u16) []const u8 {
    if (comptime table.namespaces.len == 0) unreachable;
    return table.namespaces[ns];
}

/// The line of `pos`, from 1.
fn lineOf(text: []const u8, pos: u32) usize {
    return std.mem.count(u8, text[0..pos], "\n") + 1;
}

fn findDef(ix: *const Index, start: u32) ?u32 {
    for (ix.defs, 0..) |x, i| if (x.start == start) return @intCast(i);
    return null;
}
