//! names.zig: `@lsp`, the names and scopes of a language, read against the
//! grammar's `@schema` and its tokens (docs/GRAMMAR.md, "Names and
//! scopes"). Every mistake is an error at its word. `--editor` writes what
//! it reads into the server's `language.zig`, where `scopes.zig`
//! (scopes_template.zig) indexes each open file by it.
//!
//! The lines are those of lexical names:
//!
//!   scope     KIND ... [unordered]
//!   define    KIND.ROLE SYMBOLKIND [when [^KIND.]ROLE ["text"] ...] [outer] [member|lexical]
//!             [value:ROLE] [type:ROLE] [doc:ROLE|doc:leading]
//!             [export:ROLE|export:^KIND] [detail|detail:..ROLE]
//!   use       TOKEN ...
//!   skip      KIND.ROLE ... | KIND.ROLE when ...
//!   builtin   "name" ... | TOKEN
//!   doc       TOKEN [strip "text"]
//!   undefined error|warning
//!
//! and those of files and members:
//!
//!   import    KIND.ROLE [when [^KIND.]ROLE ["text"] ...] [file "{}.ext"]
//!   member    KIND.ROLE of:ROLE
//!   qualify   KIND.ROLE in:ROLE
//!   nominal   TOKEN [ns:NAME]
//!
//! and those of assignment, colours and completion words:
//!
//!   bind      KIND.ROLE SYMBOLKIND [when ...]
//!   color     KIND.ROLE SCOPE [MODIFIER ...] [when ...]
//!   color     KIND start|end SCOPE [MODIFIER ...] [when ...]
//!   words     "lit" ...
//!
//! A `when` names a role and the text its leaf must have; with no text,
//! that the role is present; written `ROLE:KIND`, that it holds a KIND
//! node.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const diag = @import("../diag.zig");
const highlight = @import("../highlight/highlight.zig");
const regex = @import("../lexgen/regex.zig");
const Schema = grammar.Schema;

pub const Error = error{ LspError, OutOfMemory };

/// A role of a kind: its name and whether it is a rest role.
pub const RoleRef = struct { kind: []const u8, role: []const u8, rest: bool };

pub const Visibility = enum { both, member, lexical };

pub const Define = struct {
    role: RoleRef,
    /// LSP's symbol kind, as the server's `SymbolKind` names it.
    symbol: []const u8,
    /// `when ROLE "text"`: the definition is made only when that leaf's
    /// text is `text` (empty when the role is absent); `when ROLE`, only
    /// when the role is present; `when ^KIND.ROLE ...`, the same of a role
    /// of the node's parent, which is a KIND. Every `when` of a line holds.
    when: []const When = &.{},
    outer: bool = false,
    visibility: Visibility = .both,
    value: ?[]const u8 = null,
    type: ?[]const u8 = null,
    doc: Doc = .none,
    @"export": Export = .none,
    detail: Detail = .none,

    /// The role's text, or with no text its presence; with `kind`, that
    /// the role holds a node of the kind.
    pub const When = struct { parent: ?[]const u8 = null, role: []const u8, text: ?[]const u8, kind: ?[]const u8 = null };
    pub const Doc = union(enum) { none, role: RoleRef, leading };
    pub const Export = union(enum) { none, role: []const u8, parent: []const u8 };
    pub const Detail = union(enum) { none, whole, upto: []const u8 };
};

pub const Severity = enum { @"error", warning };

/// `import KIND.ROLE`: the leaf of ROLE (its first, for a rest role) names
/// a file, which is the node's value.
pub const Import = struct {
    role: RoleRef,
    when: []const Define.When = &.{},
    /// `file "{}.ext"`: the file's path, `{}` standing for the leaf's
    /// name; null for the name itself.
    file: ?[]const u8 = null,
};

/// `member KIND.ROLE of:ROLE`: the leaf is looked up among the members of
/// what the node's `of` role denotes.
pub const Member = struct { role: RoleRef, of: []const u8 };

/// `qualify KIND.ROLE in:ROLE`: the leaf is looked up in the file the
/// node's `in` role, an import, names.
pub const Qualify = struct { role: RoleRef, in: []const u8 };

/// `nominal TOKEN [ns:NAME]`: every leaf of the token is a name of its
/// namespace, one across the workspace; without `ns:` the namespace is
/// the token's.
pub const Nominal = struct { token: []const u8, ns: []const u8 };

/// `bind KIND.ROLE SYMBOLKIND`: the leaf, an assignment's target, defines
/// a name unless a definition of the name is in sight there, which it then
/// uses.
pub const Bind = struct { role: RoleRef, symbol: []const u8, when: []const Define.When = &.{} };

/// `color`: the semantic token of a role's leaf (`edge` none), or of a
/// node's first or last token.
pub const Color = struct {
    kind: []const u8,
    /// The role, for `color KIND.ROLE`.
    role: ?RoleRef = null,
    edge: Edge = .none,
    scope: highlight.Scope,
    /// LSP's token modifiers, as the server names them.
    modifiers: []const []const u8 = &.{},
    when: []const Define.When = &.{},

    pub const Edge = enum { none, start, end };
};

/// `@lsp`, read and checked.
pub const Lsp = struct {
    scopes: []const Scope,
    defines: []const Define,
    /// Token names, as the lexer spec names them.
    uses: []const []const u8,
    /// Each with its conditions: one with `when` takes a leaf before any
    /// `define` line; one without, a leaf no `define` line takes.
    skips: []const Skip,
    builtins: []const []const u8,
    builtinTokens: []const []const u8,
    docToken: ?[]const u8 = null,
    docStrip: []const u8 = "",
    undefined: ?Severity = null,
    imports: []const Import = &.{},
    members: []const Member = &.{},
    qualifies: []const Qualify = &.{},
    nominals: []const Nominal = &.{},
    binds: []const Bind = &.{},
    colors: []const Color = &.{},
    /// `words`: the completion words beside the grammar's, each with where
    /// it is written.
    words: []const Word = &.{},

    pub const Scope = struct { kind: []const u8, unordered: bool };
    pub const Skip = struct { role: RoleRef, when: []const Define.When = &.{} };
};

/// LSP's symbol kinds, as the server's `SymbolKind` names them.
pub const symbol_kinds = [_][]const u8{
    "file",     "module",         "namespace",   "package",     "class",     "method",
    "property", "field",          "constructor", "enum",        "interface", "function",
    "variable", "constant",       "string",      "number",      "boolean",   "array",
    "object",   "key",            "null",        "enum_member", "struct",    "event",
    "operator", "type_parameter",
};

/// LSP's semantic token modifiers, as the server names them, in the order
/// of its legend.
pub const modifier_names = [_][]const u8{
    "declaration", "definition", "readonly",     "static",        "deprecated",
    "abstract",    "async",      "modification", "documentation", "default_library",
};

/// The token the grammar's lexer reads a whole text as, if it reads it as
/// one.
pub const OneToken = struct {
    ctx: *const anyopaque,
    call: *const fn (ctx: *const anyopaque, text: []const u8) ?[]const u8,
};

/// Reads `@lsp` against the schema and the lexer's tokens; the first
/// mistake is reported and returned as LspError.
pub fn analyze(
    allocator: Allocator,
    lines: grammar.LspLines,
    schema: *const Schema,
    spec: *const grammar.LexerSpec,
    trivia: []const []const u8,
    source: diag.Source,
    oneToken: OneToken,
) Error!Lsp {
    var r: Reader = .{ .allocator = allocator, .schema = schema, .spec = spec, .trivia = trivia, .source = source, .oneToken = oneToken };
    return r.run(lines);
}

/// The completion words of `@lsp` against `@highlight`'s characters of
/// words and the words the grammar offers itself (`offered`): each is made
/// of those characters, and none is one of the grammar's.
pub fn checkWords(l: *const Lsp, offered: []const []const u8, wordChars: regex.ByteSet, source: diag.Source) error{LspError}!void {
    for (l.words) |w| {
        for (w.text) |c| if (!wordChars.has(c)) {
            diag.errAt(source, w.pos, "words: \"{f}\" is not a word: '{f}' is not one of @highlight's word-chars, and completion offers words", .{ std.zig.fmtString(w.text), std.zig.fmtString(&.{c}) });
            return error.LspError;
        };
        if (contains(offered, w.text)) {
            diag.errAt(source, w.pos, "words: \"{f}\" is a word of the grammar, which completion offers already", .{std.zig.fmtString(w.text)});
            return error.LspError;
        }
    }
}

const Word = grammar.LspLines.Word;

const Reader = struct {
    allocator: Allocator,
    schema: *const Schema,
    spec: *const grammar.LexerSpec,
    trivia: []const []const u8,
    source: diag.Source,
    oneToken: OneToken,

    scopes: std.ArrayList(Lsp.Scope) = .empty,
    defines: std.ArrayList(Define) = .empty,
    /// Where each define line starts, its `outer` and its `export:^KIND`.
    definePos: std.ArrayList(DefinePos) = .empty,
    uses: std.ArrayList([]const u8) = .empty,
    usePos: std.ArrayList(u32) = .empty,
    skips: std.ArrayList(Lsp.Skip) = .empty,
    skipPos: std.ArrayList(u32) = .empty,
    builtins: std.ArrayList([]const u8) = .empty,
    builtinTokens: std.ArrayList([]const u8) = .empty,
    builtinTokenPos: std.ArrayList(u32) = .empty,
    docToken: ?[]const u8 = null,
    docStrip: []const u8 = "",
    docPos: ?u32 = null,
    undefinedSeverity: ?Severity = null,
    undefinedPos: ?u32 = null,
    /// The first `doc:leading`, which needs a `doc` line.
    leadingPos: ?u32 = null,
    imports: std.ArrayList(Import) = .empty,
    members: std.ArrayList(Member) = .empty,
    memberPos: std.ArrayList(u32) = .empty,
    qualifies: std.ArrayList(Qualify) = .empty,
    /// Where each qualify line's role and its `in:` role start.
    qualifyPos: std.ArrayList([2]u32) = .empty,
    nominals: std.ArrayList(Nominal) = .empty,
    nominalPos: std.ArrayList(u32) = .empty,
    binds: std.ArrayList(Bind) = .empty,
    bindPos: std.ArrayList(u32) = .empty,
    colors: std.ArrayList(Color) = .empty,
    words: std.ArrayList(Word) = .empty,

    const DefinePos = struct { line: u32, outer: ?u32, parent: ?u32 };

    fn fail(self: *const Reader, pos: usize, comptime fmt: []const u8, args: anytype) Error {
        diag.errAt(self.source, pos, fmt, args);
        return error.LspError;
    }

    fn run(self: *Reader, lines: grammar.LspLines) Error!Lsp {
        for (lines.lines) |line| {
            const key = line.key.text;
            if (eql(key, "scope")) {
                try self.scopeLine(line);
            } else if (eql(key, "define")) {
                try self.defineLine(line);
            } else if (eql(key, "use")) {
                try self.useLine(line);
            } else if (eql(key, "skip")) {
                try self.skipLine(line);
            } else if (eql(key, "builtin")) {
                try self.builtinLine(line);
            } else if (eql(key, "doc")) {
                try self.docLine(line);
            } else if (eql(key, "undefined")) {
                try self.undefinedLine(line);
            } else if (eql(key, "import")) {
                try self.importLine(line);
            } else if (eql(key, "member") or eql(key, "qualify")) {
                try self.memberLine(line, eql(key, "qualify"));
            } else if (eql(key, "nominal")) {
                try self.nominalLine(line);
            } else if (eql(key, "bind")) {
                try self.bindLine(line);
            } else if (eql(key, "color")) {
                try self.colorLine(line);
            } else if (eql(key, "words")) {
                try self.wordsLine(line);
            } else {
                return self.fail(line.key.pos, "unknown @lsp line `{s}` (scope, define, use, skip, builtin, doc, undefined, import, member, qualify, nominal, bind, color, words)", .{key});
            }
        }
        if (self.defines.items.len == 0) return self.fail(lines.pos, "@lsp defines no names: give it a `define KIND.ROLE SYMBOLKIND` line", .{});
        try self.checkAfter();
        return .{
            .scopes = try self.scopes.toOwnedSlice(self.allocator),
            .defines = try self.defines.toOwnedSlice(self.allocator),
            .uses = try self.uses.toOwnedSlice(self.allocator),
            .skips = try self.skips.toOwnedSlice(self.allocator),
            .builtins = try self.builtins.toOwnedSlice(self.allocator),
            .builtinTokens = try self.builtinTokens.toOwnedSlice(self.allocator),
            .docToken = self.docToken,
            .docStrip = self.docStrip,
            .undefined = self.undefinedSeverity,
            .imports = try self.imports.toOwnedSlice(self.allocator),
            .members = try self.members.toOwnedSlice(self.allocator),
            .qualifies = try self.qualifies.toOwnedSlice(self.allocator),
            .nominals = try self.nominals.toOwnedSlice(self.allocator),
            .binds = try self.binds.toOwnedSlice(self.allocator),
            .colors = try self.colors.toOwnedSlice(self.allocator),
            .words = try self.words.toOwnedSlice(self.allocator),
        };
    }

    /// The checks that need every line: `outer`, `export:^KIND`,
    /// `doc:leading`, a definition also skipped, `builtin TOKEN`.
    fn checkAfter(self: *Reader) Error!void {
        for (self.defines.items, self.definePos.items) |d, at| {
            if (at.outer) |pos| if (!self.isScope(d.role.kind) and !self.heldByScope(d.role.kind))
                return self.fail(pos, "outer: '{s}' is no scope kind and no role of a scope kind holds it, so it has no scope to step out of", .{d.role.kind});
            if (at.parent) |pos| if (!self.holds(d.@"export".parent, d.role.kind))
                return self.fail(pos, "export:^{s}: no role of '{s}' holds a '{s}' node, so it is never its parent", .{ d.@"export".parent, d.@"export".parent, d.role.kind });
        }
        if (self.leadingPos) |pos| if (self.docToken == null)
            return self.fail(pos, "doc:leading reads the doc tokens before a definition: name them with a `doc TOKEN` line", .{});
        // A skip takes the leaves of a role no `define` line takes: none,
        // when a line without `when` defines the role.
        for (self.skips.items, self.skipPos.items) |s, pos| for (self.defines.items) |d| {
            if (eql(d.role.kind, s.role.kind) and eql(d.role.role, s.role.role) and d.when.len == 0 and s.when.len == 0)
                return self.fail(pos, "{s}.{s} is both defined and skipped", .{ s.role.kind, s.role.role });
        };
        // A bind takes a leaf no define line takes, before a skip without
        // `when`: a line that never gets a leaf is a mistake.
        for (self.binds.items, self.bindPos.items) |b, pos| {
            for (self.defines.items) |d| if (sameRole(d.role, b.role) and (d.when.len == 0 or sameWhens(d.when, b.when)))
                return self.fail(pos, "{s}.{s}: a `define` line defines it wherever this bind's conditions hold, so the bind never binds", .{ b.role.kind, b.role.role });
            if (b.when.len == 0) for (self.skips.items, self.skipPos.items) |s, spos| if (sameRole(s.role, b.role) and s.when.len == 0)
                return self.fail(spos, "{s}.{s} is both bound and skipped", .{ s.role.kind, s.role.role });
        }
        for (self.builtinTokens.items, self.builtinTokenPos.items) |t, pos| if (!contains(self.uses.items, t))
            return self.fail(pos, "builtin {s}: {s} is no `use` token, so its leaves are never looked up", .{ upper(self.allocator, t), upper(self.allocator, t) });
        // A member's or a qualified name's leaf is looked up by its line
        // alone: no `define` or `skip` line without `when` takes it.
        for (self.members.items, self.memberPos.items) |m, pos| try self.takenOnce(m.role, pos, "a member");
        for (self.qualifies.items, self.qualifyPos.items) |q, pos| {
            try self.takenOnce(q.role, pos[0], "qualified");
            for (self.members.items) |m| if (sameRole(m.role, q.role))
                return self.fail(pos[0], "{s}.{s} is both {s} and {s}", .{ q.role.kind, q.role.role, "a member", "qualified" });
            const imported = for (self.imports.items) |im| {
                if (eql(im.role.kind, q.role.kind) and eql(im.role.role, q.in)) break true;
            } else false;
            if (!imported) return self.fail(pos[1], "in:{s} names the file the name is in: give {s}.{s} an `import` line", .{ q.in, q.role.kind, q.in });
        }
        for (self.nominals.items, self.nominalPos.items) |n, pos| if (contains(self.uses.items, n.token))
            return self.fail(pos, "{s} is a `use` token too: a leaf is looked up in its scopes, or is a name of a namespace, not both", .{upper(self.allocator, n.token)});
    }

    /// No `define` or `skip` line without `when` takes the role of a
    /// `member` or `qualify` line at `pos`.
    fn takenOnce(self: *Reader, role: RoleRef, pos: u32, comptime what: []const u8) Error!void {
        for (self.defines.items) |d| if (sameRole(d.role, role) and d.when.len == 0)
            return self.fail(pos, "{s}.{s} is both {s} and {s}", .{ role.kind, role.role, "defined", what });
        for (self.binds.items) |b| if (sameRole(b.role, role) and b.when.len == 0)
            return self.fail(pos, "{s}.{s} is both {s} and {s}", .{ role.kind, role.role, "bound", what });
        for (self.skips.items) |s| if (sameRole(s.role, role) and s.when.len == 0)
            return self.fail(pos, "{s}.{s} is both {s} and {s}", .{ role.kind, role.role, "skipped", what });
    }

    // --- Lines ------------------------------------------------------------

    fn scopeLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        var words = line.words;
        var unordered = false;
        if (words.len > 0 and eql(words[words.len - 1].text, "unordered")) {
            unordered = true;
            words = words[0 .. words.len - 1];
        }
        if (words.len == 0) return self.fail(line.key.pos, "a scope line names at least one kind", .{});
        for (words) |w| {
            const kind = try self.kindOf(w);
            for (self.scopes.items) |s| if (eql(s.kind, kind))
                return self.fail(w.pos, "'{s}' is a scope kind already", .{kind});
            try self.scopes.append(self.allocator, .{ .kind = kind, .unordered = unordered });
        }
    }

    fn defineLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a define line names a role and a symbol kind: define KIND.ROLE SYMBOLKIND", .{});
        const role = try self.roleOf(words[0], "define");
        if (!holdsLeaf(self.roleIn(role.kind, role.role).?)) return self.fail(words[0].pos, "define {s}.{s}: the role holds no token, and a definition is a token", .{ role.kind, role.role });
        if (words.len < 2) return self.fail(line.key.pos, "define {s}.{s} needs a symbol kind ({s})", .{ role.kind, role.role, symbolList });
        const symbol = words[1].text;
        if (!contains(&symbol_kinds, symbol)) return self.fail(words[1].pos, "unknown symbol kind '{s}' (LSP's: {s})", .{ symbol, symbolList });
        var d: Define = .{ .role = role, .symbol = symbol };
        var at: DefinePos = .{ .line = line.key.pos, .outer = null, .parent = null };
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var whens: std.ArrayList(Define.When) = .empty;
        var i: usize = 2;
        while (i < words.len) : (i += 1) {
            const w = words[i];
            const colon = std.mem.findScalar(u8, w.text, ':');
            const name = if (colon) |c| w.text[0..c] else w.text;
            const arg = if (colon) |c| w.text[c + 1 ..] else null;
            const option = std.meta.stringToEnum(Option, name) orelse
                return self.fail(w.pos, "unknown option '{s}' of define (when, outer, member, lexical, value:, type:, doc:, export:, detail:)", .{w.text});
            const group = option.group();
            if (option != .when and (try seen.fetchPut(self.allocator, group, {})) != null) {
                if (eql(group, "member or lexical") and !eql(name, if (d.visibility == .member) "member" else "lexical"))
                    return self.fail(w.pos, "a definition is `member` or `lexical`, not both", .{});
                return self.fail(w.pos, "define {s}.{s} has {s} twice", .{ role.kind, role.role, name });
            }
            const argPos: u32 = w.pos + @as(u32, @intCast(name.len + 1));
            switch (option) {
                .when => {
                    if (arg != null) return self.fail(w.pos, "write `when ROLE \"text\"`, not `{s}`", .{w.text});
                    i = try self.whenAt(words, i, role.kind, &whens);
                },
                .outer, .member, .lexical => {
                    if (arg != null) return self.fail(w.pos, "`{s}` takes no argument", .{name});
                    switch (option) {
                        .outer => {
                            d.outer = true;
                            at.outer = w.pos;
                        },
                        .member => d.visibility = .member,
                        .lexical => d.visibility = .lexical,
                        else => unreachable,
                    }
                },
                .value, .type => {
                    const a = arg orelse return self.fail(w.pos, "write `{s}:ROLE`", .{name});
                    const r = try self.slotRole(role.kind, a, argPos, if (option == .value) "value:" else "type:");
                    if (r.type == .tag) return self.fail(argPos, "{s}:{s} is a tag role; a {s} is a node or a leaf", .{ name, a, name });
                    if (option == .value) d.value = a else d.type = a;
                },
                .doc => {
                    const a = arg orelse return self.fail(w.pos, "write `doc:ROLE` or `doc:leading`", .{});
                    if (eql(a, "leading")) {
                        d.doc = .leading;
                        if (self.leadingPos == null) self.leadingPos = w.pos;
                    } else {
                        const r = self.roleIn(role.kind, a) orelse return self.noRole(role.kind, a, argPos);
                        if (r.type != .leaf and r.type != .group) return self.fail(argPos, "doc:{s}: the role holds neither tokens nor a group of them", .{a});
                        d.doc = .{ .role = .{ .kind = role.kind, .role = a, .rest = r.rest } };
                    }
                },
                .@"export" => {
                    const a = arg orelse return self.fail(w.pos, "write `export:ROLE` or `export:^KIND`", .{});
                    if (a.len > 0 and a[0] == '^') {
                        d.@"export" = .{ .parent = try self.kindOf(.{ .text = a[1..], .pos = argPos + 1 }) };
                        at.parent = w.pos;
                    } else {
                        _ = try self.slotRole(role.kind, a, argPos, "export:");
                        d.@"export" = .{ .role = a };
                    }
                },
                .detail => {
                    if (arg) |a| {
                        if (!std.mem.startsWith(u8, a, "..")) return self.fail(w.pos, "write `detail` or `detail:..ROLE`, not `{s}`", .{w.text});
                        _ = try self.slotRole(role.kind, a[2..], argPos + 2, "detail:..");
                        d.detail = .{ .upto = a[2..] };
                    } else d.detail = .whole;
                },
            }
        }
        d.when = try whens.toOwnedSlice(self.allocator);
        // Two lines for one role are told apart by their `when`s.
        for (self.defines.items) |o| {
            if (!eql(o.role.kind, role.kind) or !eql(o.role.role, role.role)) continue;
            if (sameWhens(o.when, d.when)) return self.fail(words[0].pos, "{s}.{s} is defined twice: give each line a different `when`", .{ role.kind, role.role });
        }
        try self.defines.append(self.allocator, d);
        try self.definePos.append(self.allocator, at);
    }

    /// The condition `when` at `words[i]` starts, of a node of `kind`;
    /// the index of its last word.
    fn whenAt(self: *Reader, words: []const Word, i: usize, kind: []const u8, whens: *std.ArrayList(Define.When)) Error!usize {
        if (i + 1 >= words.len) return self.fail(words[i].pos, "`when` takes a role, and the text it must have: when [^KIND.]ROLE [\"text\"]", .{});
        const word = words[i + 1];
        // With a string, the role's text; without, its presence; `:KIND`,
        // the kind of the node it holds.
        const text: ?[]const u8 = if (i + 2 < words.len and words[i + 2].text[0] == '"') try self.stringOf(words[i + 2], "when's text") else null;
        const colon = std.mem.findScalar(u8, word.text, ':');
        const whenRole: Word = .{ .text = word.text[0 .. colon orelse word.text.len], .pos = word.pos };
        var of = kind;
        var roleName = whenRole.text;
        var pos = whenRole.pos;
        var parent: ?[]const u8 = null;
        if (whenRole.text.len > 0 and whenRole.text[0] == '^') {
            // A role of the parent: ^KIND.ROLE.
            const p = try self.roleOf(.{ .text = whenRole.text[1..], .pos = whenRole.pos + 1 }, "when ^");
            if (!self.holds(p.kind, kind)) return self.fail(whenRole.pos + 1, "when ^{s}: no role of '{s}' holds a '{s}' node, so it is never its parent", .{ whenRole.text[1..], p.kind, kind });
            of = p.kind;
            roleName = p.role;
            pos = whenRole.pos + 1;
            parent = p.kind;
        }
        const r = try self.slotRole(of, roleName, pos, if (parent != null) "when ^" else "when ");
        var held: ?[]const u8 = null;
        if (colon) |c| {
            const kindPos = word.pos + @as(u32, @intCast(c + 1));
            if (text != null) return self.fail(words[i + 2].pos, "when {s} asks the kind of the node the role holds, which has no text", .{word.text});
            const k = try self.kindOf(.{ .text = word.text[c + 1 ..], .pos = kindPos });
            const can = switch (r.type) {
                .any, .node => true,
                .kinds => |ks| contains(ks, k),
                .leaf, .tag, .group => false,
            };
            if (!can) return self.fail(kindPos, "when {s}: the role never holds a '{s}' node", .{ word.text, k });
            held = k;
        }
        if (text != null and r.type != .leaf) return self.fail(whenRole.pos, "when {s}: the role is not leaf-typed, so it has no text", .{whenRole.text});
        try whens.append(self.allocator, .{ .parent = parent, .role = roleName, .text = text, .kind = held });
        return i + @as(usize, if (text != null) 2 else 1);
    }

    const Option = enum {
        when,
        outer,
        member,
        lexical,
        value,
        type,
        doc,
        @"export",
        detail,

        /// Options of one group exclude each other.
        fn group(o: Option) []const u8 {
            return switch (o) {
                .member, .lexical => "member or lexical",
                else => @tagName(o),
            };
        }
    };

    fn useLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (line.words.len == 0) return self.fail(line.key.pos, "a use line names at least one token", .{});
        for (line.words) |w| {
            const token = try self.tokenOf(w);
            if (contains(self.uses.items, token)) return self.fail(w.pos, "{s} is a use token already", .{w.text});
            for (self.trivia) |t| if (std.ascii.eqlIgnoreCase(t, token))
                return self.fail(w.pos, "{s} is @trivia, so it is never in the tree", .{w.text});
            try self.uses.append(self.allocator, token);
            try self.usePos.append(self.allocator, w.pos);
        }
    }

    fn skipLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (line.words.len == 0) return self.fail(line.key.pos, "a skip line names at least one role: skip KIND.ROLE ...", .{});
        // Roles, then the conditions of a line that names one role.
        var roles = line.words;
        var whens: std.ArrayList(Define.When) = .empty;
        for (line.words, 0..) |w, i| if (eql(w.text, "when")) {
            roles = line.words[0..i];
            if (roles.len != 1) return self.fail(w.pos, "a skip line with `when` names one role", .{});
            var j = i;
            while (j < line.words.len) : (j += 1) {
                if (!eql(line.words[j].text, "when")) return self.fail(line.words[j].pos, "after a skip line's role come its `when`s, not '{s}'", .{line.words[j].text});
                j = try self.whenAt(line.words, j, (try self.roleOf(roles[0], "skip")).kind, &whens);
            }
            break;
        };
        for (roles) |w| {
            const role = try self.roleOf(w, "skip");
            if (!holdsLeaf(self.roleIn(role.kind, role.role).?))
                return self.fail(w.pos, "skip {s}.{s}: the role holds no token, and skip names tokens", .{ role.kind, role.role });
            for (self.skips.items) |s| if (eql(s.role.kind, role.kind) and eql(s.role.role, role.role) and sameWhens(s.when, whens.items))
                return self.fail(w.pos, "{s}.{s} is skipped already", .{ role.kind, role.role });
            try self.skips.append(self.allocator, .{ .role = role, .when = whens.items });
            try self.skipPos.append(self.allocator, w.pos);
        }
    }

    fn builtinLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (line.words.len == 0) return self.fail(line.key.pos, "a builtin line names strings or one token: builtin \"name\" ... | builtin TOKEN", .{});
        if (line.words[0].text[0] != '"') {
            if (line.words.len > 1) return self.fail(line.words[1].pos, "builtin TOKEN names one token, alone on its line", .{});
            const token = try self.tokenOf(line.words[0]);
            if (contains(self.builtinTokens.items, token)) return self.fail(line.words[0].pos, "{s} is a builtin token already", .{line.words[0].text});
            try self.builtinTokens.append(self.allocator, token);
            try self.builtinTokenPos.append(self.allocator, line.words[0].pos);
            return;
        }
        for (line.words) |w| {
            const name = try self.stringOf(w, "a builtin name");
            if (name.len == 0) return self.fail(w.pos, "a builtin name is not empty", .{});
            if (contains(self.builtins.items, name)) return self.fail(w.pos, "\"{s}\" is a builtin name already", .{name});
            try self.builtins.append(self.allocator, name);
        }
    }

    fn docLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (self.docPos != null) return self.fail(line.key.pos, "duplicate `doc` line in @lsp", .{});
        self.docPos = line.key.pos;
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a doc line names the doc token: doc TOKEN [strip \"text\"]", .{});
        self.docToken = try self.tokenOf(words[0]);
        if (words.len == 1) return;
        if (!eql(words[1].text, "strip") or words.len != 3) return self.fail(words[1].pos, "after the doc token comes `strip \"text\"`, the text to take off each doc token's start", .{});
        self.docStrip = try self.stringOf(words[2], "strip's text");
    }

    fn undefinedLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (self.undefinedPos != null) return self.fail(line.key.pos, "duplicate `undefined` line in @lsp", .{});
        self.undefinedPos = line.key.pos;
        if (line.words.len != 1) return self.fail(line.key.pos, "write `undefined error` or `undefined warning`", .{});
        self.undefinedSeverity = std.meta.stringToEnum(Severity, line.words[0].text) orelse
            return self.fail(line.words[0].pos, "write `undefined error` or `undefined warning`", .{});
    }

    fn importLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "an import line names a role: import KIND.ROLE [when ROLE \"text\"] [file \"{{}}.ext\"]", .{});
        const role = try self.roleOf(words[0], "import");
        if (!holdsLeaf(self.roleIn(role.kind, role.role).?)) return self.fail(words[0].pos, "import {s}.{s}: the role holds no token, and a token names the file", .{ role.kind, role.role });
        var im: Import = .{ .role = role };
        var whens: std.ArrayList(Define.When) = .empty;
        var i: usize = 1;
        while (i < words.len) : (i += 1) {
            const w = words[i];
            if (eql(w.text, "when")) {
                i = try self.whenAt(words, i, role.kind, &whens);
            } else if (eql(w.text, "file")) {
                if (im.file != null) return self.fail(w.pos, "import {s}.{s} has file twice", .{ role.kind, role.role });
                if (i + 1 >= words.len or words[i + 1].text[0] != '"') return self.fail(w.pos, "`file` takes the file's path, with `{{}}` for the name: file \"{{}}.ext\"", .{});
                i += 1;
                const path = try self.stringOf(words[i], "file's path");
                if (std.mem.find(u8, path, "{}") == null) return self.fail(words[i].pos, "file {s}: the path has no `{{}}` for the name", .{words[i].text});
                im.file = path;
            } else return self.fail(w.pos, "unknown option '{s}' of import (when, file)", .{w.text});
        }
        im.when = try whens.toOwnedSlice(self.allocator);
        for (self.imports.items) |o| if (sameRole(o.role, role) and sameWhens(o.when, im.when))
            return self.fail(words[0].pos, "{s}.{s} is imported twice: give each line a different `when`", .{ role.kind, role.role });
        try self.imports.append(self.allocator, im);
    }

    /// `member KIND.ROLE of:ROLE`, or with `qualify`, `qualify KIND.ROLE
    /// in:ROLE`.
    fn memberLine(self: *Reader, line: grammar.LspLines.Line, qualify: bool) Error!void {
        const key = if (qualify) "qualify" else "member";
        const option = if (qualify) "in" else "of";
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a {s} line names a role, then the role of {s}: {s} KIND.ROLE {s}:ROLE", .{ key, if (qualify) "the file the name is in" else "what the name is a member of", key, option });
        const role = if (qualify) try self.roleOf(words[0], "qualify") else try self.roleOf(words[0], "member");
        if (!holdsLeaf(self.roleIn(role.kind, role.role).?)) return self.fail(words[0].pos, "{s} {s}.{s}: the role holds no token, and a name is a token", .{ key, role.kind, role.role });
        if (words.len < 2) return self.fail(line.key.pos, "{s} {s}.{s} needs {s}:ROLE", .{ key, role.kind, role.role, option });
        const w = words[1];
        if (words.len > 2 or !std.mem.startsWith(u8, w.text, option) or w.text.len == option.len or w.text[option.len] != ':') {
            const bad = if (words.len > 2 and std.mem.startsWith(u8, w.text, option)) words[2] else w;
            return self.fail(bad.pos, "unknown option '{s}' of {s} ({s}:ROLE)", .{ bad.text, key, option });
        }
        const name = w.text[option.len + 1 ..];
        const argPos = w.pos + @as(u32, @intCast(option.len + 1));
        if (eql(name, role.role)) return self.fail(argPos, "{s}:{s} is the name's own role", .{ option, name });
        const r = try self.slotRole(role.kind, name, argPos, if (qualify) "in:" else "of:");
        if (qualify) {
            if (!holdsLeaf(r)) return self.fail(argPos, "in:{s}: the role holds no token, and a token names the file", .{name});
            for (self.qualifies.items) |q| if (sameRole(q.role, role))
                return self.fail(words[0].pos, "{s}.{s} is qualified already", .{ role.kind, role.role });
            try self.qualifies.append(self.allocator, .{ .role = role, .in = name });
            try self.qualifyPos.append(self.allocator, .{ words[0].pos, argPos });
        } else {
            if (r.type == .tag) return self.fail(argPos, "of:{s} is a tag role; what a name is a member of is a node or a leaf", .{name});
            for (self.members.items) |m| if (sameRole(m.role, role))
                return self.fail(words[0].pos, "{s}.{s} is a member already", .{ role.kind, role.role });
            try self.members.append(self.allocator, .{ .role = role, .of = name });
            try self.memberPos.append(self.allocator, words[0].pos);
        }
    }

    fn nominalLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a nominal line names a token: nominal TOKEN [ns:NAME]", .{});
        const token = try self.tokenOf(words[0]);
        for (self.nominals.items) |n| if (eql(n.token, token))
            return self.fail(words[0].pos, "{s} is a nominal token already", .{words[0].text});
        for (self.trivia) |t| if (std.ascii.eqlIgnoreCase(t, token))
            return self.fail(words[0].pos, "{s} is @trivia, so it is never in the tree", .{words[0].text});
        var n: Nominal = .{ .token = token, .ns = token };
        for (words[1..], 1..) |w, i| {
            if (i > 1 or !std.mem.startsWith(u8, w.text, "ns:")) return self.fail(w.pos, "unknown option '{s}' of nominal (ns:NAME)", .{w.text});
            const ns = w.text[3..];
            if (ns.len == 0 or wordLen(ns) != ns.len) return self.fail(w.pos + 3, "ns:NAME names the namespace with letters, digits and '_', not '{s}'", .{ns});
            n.ns = ns;
        }
        try self.nominals.append(self.allocator, n);
        try self.nominalPos.append(self.allocator, words[0].pos);
    }

    fn bindLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a bind line names a role and a symbol kind: bind KIND.ROLE SYMBOLKIND", .{});
        const role = try self.roleOf(words[0], "bind");
        if (!holdsLeaf(self.roleIn(role.kind, role.role).?)) return self.fail(words[0].pos, "bind {s}.{s}: the role holds no token, and a name is a token", .{ role.kind, role.role });
        if (words.len < 2) return self.fail(line.key.pos, "bind {s}.{s} needs a symbol kind ({s})", .{ role.kind, role.role, symbolList });
        const symbol = words[1].text;
        if (!contains(&symbol_kinds, symbol)) return self.fail(words[1].pos, "unknown symbol kind '{s}' (LSP's: {s})", .{ symbol, symbolList });
        var whens: std.ArrayList(Define.When) = .empty;
        var i: usize = 2;
        while (i < words.len) : (i += 1) {
            if (!eql(words[i].text, "when")) return self.fail(words[i].pos, "unknown option '{s}' of bind (when)", .{words[i].text});
            i = try self.whenAt(words, i, role.kind, &whens);
        }
        for (self.binds.items) |b| if (sameRole(b.role, role) and sameWhens(b.when, whens.items))
            return self.fail(words[0].pos, "{s}.{s} is bound twice: give each line a different `when`", .{ role.kind, role.role });
        try self.binds.append(self.allocator, .{ .role = role, .symbol = symbol, .when = whens.items });
        try self.bindPos.append(self.allocator, words[0].pos);
    }

    /// `color KIND.ROLE SCOPE [MODIFIER ...] [when ...]`, or `color KIND
    /// start|end SCOPE ...`.
    fn colorLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        const words = line.words;
        if (words.len == 0) return self.fail(line.key.pos, "a color line names a role, or a kind and `start` or `end`, then a scope: color KIND.ROLE SCOPE, color KIND start|end SCOPE", .{});
        var c: Color = .{ .kind = undefined, .scope = undefined };
        var i: usize = 1;
        if (std.mem.findScalar(u8, words[0].text, '.') != null) {
            const role = try self.roleOf(words[0], "color");
            if (!holdsLeaf(self.roleIn(role.kind, role.role).?)) return self.fail(words[0].pos, "color {s}.{s}: the role holds no token, and a colour is a token's", .{ role.kind, role.role });
            c.kind = role.kind;
            c.role = role;
        } else {
            c.kind = try self.kindOf(words[0]);
            if (words.len < 2 or !(eql(words[1].text, "start") or eql(words[1].text, "end")))
                return self.fail(if (words.len < 2) words[0].pos else words[1].pos, "color {s}: after a kind comes `start` or `end`, its node's first or last token; a role is written KIND.ROLE", .{words[0].text});
            c.edge = if (eql(words[1].text, "start")) .start else .end;
            i = 2;
        }
        const what = if (c.role) |r| try self.allocator.print("{s}.{s}", .{ r.kind, r.role }) else try self.allocator.print("{s} {s}", .{ c.kind, @tagName(c.edge) });
        // The tree the server reads is the grammar's: a lang Parser
        // wrapper's kinds are never in it.
        for (self.schema.kinds) |k| if (eql(k.tag, c.kind) and k.wrapper)
            return self.fail(words[0].pos, "color {s}: '{s}' is @wrapper, built by the lang Parser wrapper, and the server colours the grammar's tree, which has no such node", .{ what, c.kind });
        if (i >= words.len) return self.fail(line.key.pos, "color {s} needs a scope ({s})", .{ what, scopeList });
        c.scope = highlight.Scope.parse(words[i].text) orelse
            return self.fail(words[i].pos, "unknown scope '{s}' (@highlight's: {s})", .{ words[i].text, scopeList });
        i += 1;
        var mods: std.ArrayList([]const u8) = .empty;
        var whens: std.ArrayList(Define.When) = .empty;
        while (i < words.len) : (i += 1) {
            const w = words[i];
            if (eql(w.text, "when")) {
                i = try self.whenAt(words, i, c.kind, &whens);
                continue;
            }
            if (whens.items.len > 0) return self.fail(w.pos, "after a color line's `when`s come more `when`s, not '{s}'", .{w.text});
            if (!contains(&modifier_names, w.text)) return self.fail(w.pos, "unknown modifier '{s}' (LSP's: {s})", .{ w.text, modifierList });
            if (contains(mods.items, w.text)) return self.fail(w.pos, "color {s} has {s} twice", .{ what, w.text });
            try mods.append(self.allocator, w.text);
        }
        c.modifiers = mods.items;
        c.when = whens.items;
        for (self.colors.items) |o| {
            if (!eql(o.kind, c.kind) or o.edge != c.edge or !sameWhens(o.when, c.when)) continue;
            if (c.role) |r| if (!eql(o.role.?.role, r.role)) continue;
            return self.fail(words[0].pos, "{s} is coloured twice: give each line a different `when`", .{what});
        }
        try self.colors.append(self.allocator, c);
    }

    fn wordsLine(self: *Reader, line: grammar.LspLines.Line) Error!void {
        if (line.words.len == 0) return self.fail(line.key.pos, "a words line names at least one word: words \"lit\" ...", .{});
        for (line.words) |w| {
            const text = try self.stringOf(w, "a completion word");
            if (text.len == 0) return self.fail(w.pos, "a completion word is not empty", .{});
            for (self.words.items) |o| if (eql(o.text, text))
                return self.fail(w.pos, "\"{f}\" is a completion word already", .{std.zig.fmtString(text)});
            if (self.oneToken.call(self.oneToken.ctx, text) == null)
                return self.fail(w.pos, "words: the lexer does not read \"{f}\" as one token, so the parser never takes it", .{std.zig.fmtString(text)});
            try self.words.append(self.allocator, .{ .text = text, .pos = w.pos });
        }
    }

    // --- Names --------------------------------------------------------------

    /// A kind of the schema, as written (a quoted kind's escapes decoded).
    fn kindOf(self: *Reader, w: Word) Error![]const u8 {
        const name = if (w.text.len > 0 and w.text[0] == '"') try self.stringOf(w, "a kind") else w.text;
        for (self.schema.kinds) |k| if (eql(k.tag, name)) return k.tag;
        return self.fail(w.pos, "unknown kind '{s}' (the @schema has no such kind)", .{name});
    }

    /// `KIND.ROLE`: a kind of the schema and one of its roles.
    fn roleOf(self: *Reader, w: Word, comptime what: []const u8) Error!RoleRef {
        const dot = std.mem.findScalarLast(u8, w.text, '.') orelse
            return self.fail(w.pos, what ++ " names a role of a kind: KIND.ROLE, not '{s}'", .{w.text});
        const kind = try self.kindOf(.{ .text = w.text[0..dot], .pos = w.pos });
        const name = w.text[dot + 1 ..];
        const pos = w.pos + @as(u32, @intCast(dot + 1));
        const r = self.roleIn(kind, name) orelse return self.noRole(kind, name, pos);
        return .{ .kind = kind, .role = name, .rest = r.rest };
    }

    /// A slot role (not a rest role) of `kind`, for an option.
    fn slotRole(self: *Reader, kind: []const u8, name: []const u8, pos: u32, what: []const u8) Error!Schema.Role {
        const r = self.roleIn(kind, name) orelse return self.noRole(kind, name, pos);
        if (r.rest) return self.fail(pos, "{s}{s} is a rest role; name a role of one child", .{ what, name });
        return r;
    }

    fn noRole(self: *Reader, kind: []const u8, name: []const u8, pos: u32) Error {
        for (self.schema.kinds) |k| if (eql(k.tag, kind)) for (k.side) |s| if (eql(s, name))
            return self.fail(pos, "'{s}' is a side-band role of '{s}', which is not in the tree", .{ name, kind });
        return self.fail(pos, "kind '{s}' has no role '{s}'", .{ kind, name });
    }

    fn roleIn(self: *const Reader, kind: []const u8, name: []const u8) ?Schema.Role {
        for (self.schema.kinds) |k| if (eql(k.tag, kind)) {
            for (k.roles) |r| if (eql(r.name, name)) return r;
            return null;
        };
        return null;
    }

    /// A token of the lexer, written in capitals as rules write it.
    fn tokenOf(self: *Reader, w: Word) Error![]const u8 {
        for (w.text) |c| if (!(std.ascii.isUpper(c) or std.ascii.isDigit(c) or c == '_'))
            return self.fail(w.pos, "unknown token '{s}' (tokens are written in capitals, as rules write them)", .{w.text});
        for (self.spec.tokens.items) |t| if (std.ascii.eqlIgnoreCase(t, w.text)) return t;
        return self.fail(w.pos, "unknown token '{s}' (tokens are written in capitals, as rules write them)", .{w.text});
    }

    /// A string word's bytes, its escapes decoded.
    fn stringOf(self: *Reader, w: Word, comptime what: []const u8) Error![]const u8 {
        const t = w.text;
        if (t.len < 2 or t[0] != '"' or t[t.len - 1] != '"') return self.fail(w.pos, what ++ " is a string: \"...\", not {s}", .{t});
        const body = t[1 .. t.len - 1];
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            if (body[i] != '\\') continue;
            const e = grammar.escapeAt(body, i) orelse
                return self.fail(w.pos + 1 + i, "unknown escape sequence (the escapes are \\n \\r \\t \\0 \\\\ \\' \\\" and \\xHH)", .{});
            i += e.len - 1;
        }
        return grammar.decode(self.allocator, body);
    }

    fn isScope(self: *const Reader, kind: []const u8) bool {
        for (self.scopes.items) |s| if (eql(s.kind, kind)) return true;
        return false;
    }

    /// Whether some role of a scope kind can hold a `kind` node.
    fn heldByScope(self: *const Reader, kind: []const u8) bool {
        for (self.scopes.items) |s| if (self.holds(s.kind, kind)) return true;
        return false;
    }

    /// Whether some role of `parent` can hold a `kind` node: one typed
    /// with `kind`, an untyped one, or a group.
    fn holds(self: *const Reader, parent: []const u8, kind: []const u8) bool {
        for (self.schema.kinds) |k| if (eql(k.tag, parent)) {
            for (k.roles) |r| switch (r.type) {
                .any, .node, .group => return true,
                .kinds => |ks| if (contains(ks, kind)) return true,
                .leaf, .tag => {},
            };
            return false;
        };
        return false;
    }
};

/// Whether a role can hold a token: a leaf role, or an untyped one.
fn holdsLeaf(r: Schema.Role) bool {
    return switch (r.type) {
        .leaf, .any, .node => true,
        .tag, .group, .kinds => false,
    };
}

fn sameRole(a: RoleRef, b: RoleRef) bool {
    return eql(a.kind, b.kind) and eql(a.role, b.role);
}

/// The length of the run of letters, digits and '_' that starts `s`.
fn wordLen(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) i += 1;
    return i;
}

/// Whether two lists of `when`s are the same conditions.
fn sameWhens(a: []const Define.When, b: []const Define.When) bool {
    if (a.len != b.len) return false;
    for (a) |x| {
        const found = for (b) |y| {
            const parents = if (x.parent) |xp| (if (y.parent) |yp| eql(xp, yp) else false) else y.parent == null;
            const texts = if (x.text) |xt| (if (y.text) |yt| eql(xt, yt) else false) else y.text == null;
            const kinds = if (x.kind) |xk| (if (y.kind) |yk| eql(xk, yk) else false) else y.kind == null;
            if (parents and eql(x.role, y.role) and texts and kinds) break true;
        } else false;
        if (!found) return false;
    }
    return true;
}

const symbolList = blk: {
    var s: []const u8 = "";
    for (symbol_kinds, 0..) |k, i| s = s ++ (if (i == 0) "" else ", ") ++ k;
    break :blk s;
};

const modifierList = blk: {
    var s: []const u8 = "";
    for (modifier_names, 0..) |k, i| s = s ++ (if (i == 0) "" else ", ") ++ k;
    break :blk s;
};

const scopeList = blk: {
    var s: []const u8 = "";
    for (std.enums.values(highlight.Scope), 0..) |k, i| s = s ++ (if (i == 0) "" else ", ") ++ k.names().name;
    break :blk s;
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (eql(x, s)) return true;
    return false;
}

/// A token name as rules write it.
fn upper(allocator: Allocator, name: []const u8) []const u8 {
    return std.ascii.allocUpperString(allocator, name) catch name;
}
