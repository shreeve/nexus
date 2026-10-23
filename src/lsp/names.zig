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
//! The lines of imports, members, binding, colours and words (`import`,
//! `member`, `qualify`, `nominal`, `bind`, `color`, `words`) are not read
//! yet: each is an error that says so.

const std = @import("std");
const Allocator = std.mem.Allocator;
const grammar = @import("../grammar.zig");
const diag = @import("../diag.zig");
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

    /// The role's text, or with no text its presence.
    pub const When = struct { parent: ?[]const u8 = null, role: []const u8, text: ?[]const u8 };
    pub const Doc = union(enum) { none, role: RoleRef, leading };
    pub const Export = union(enum) { none, role: []const u8, parent: []const u8 };
    pub const Detail = union(enum) { none, whole, upto: []const u8 };
};

pub const Severity = enum { @"error", warning };

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

/// The keys of the lines a later Nexus reads.
const later = [_][]const u8{ "import", "member", "qualify", "nominal", "bind", "color", "words" };

/// Reads `@lsp` against the schema and the lexer's tokens; the first
/// mistake is reported and returned as LspError.
pub fn analyze(
    allocator: Allocator,
    lines: grammar.LspLines,
    schema: *const Schema,
    spec: *const grammar.LexerSpec,
    trivia: []const []const u8,
    source: diag.Source,
) Error!Lsp {
    var r: Reader = .{ .allocator = allocator, .schema = schema, .spec = spec, .trivia = trivia, .source = source };
    return r.run(lines);
}

const Word = grammar.LspLines.Word;

const Reader = struct {
    allocator: Allocator,
    schema: *const Schema,
    spec: *const grammar.LexerSpec,
    trivia: []const []const u8,
    source: diag.Source,

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
            } else if (isLater(key)) {
                return self.fail(line.key.pos, "`{s}` lines of @lsp are not supported yet: this Nexus reads scope, define, use, skip, builtin, doc and undefined", .{key});
            } else {
                return self.fail(line.key.pos, "unknown @lsp line `{s}` (scope, define, use, skip, builtin, doc, undefined)", .{key});
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
        for (self.builtinTokens.items, self.builtinTokenPos.items) |t, pos| if (!contains(self.uses.items, t))
            return self.fail(pos, "builtin {s}: {s} is no `use` token, so its leaves are never looked up", .{ upper(self.allocator, t), upper(self.allocator, t) });
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
        const whenRole = words[i + 1];
        // With a string, the role's text; without, its presence.
        const text: ?[]const u8 = if (i + 2 < words.len and words[i + 2].text[0] == '"') try self.stringOf(words[i + 2], "when's text") else null;
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
        if (text != null and r.type != .leaf) return self.fail(whenRole.pos, "when {s}: the role is not leaf-typed, so it has no text", .{whenRole.text});
        try whens.append(self.allocator, .{ .parent = parent, .role = roleName, .text = text });
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

/// Whether two lists of `when`s are the same conditions.
fn sameWhens(a: []const Define.When, b: []const Define.When) bool {
    if (a.len != b.len) return false;
    for (a) |x| {
        const found = for (b) |y| {
            const parents = if (x.parent) |xp| (if (y.parent) |yp| eql(xp, yp) else false) else y.parent == null;
            const texts = if (x.text) |xt| (if (y.text) |yt| eql(xt, yt) else false) else y.text == null;
            if (parents and eql(x.role, y.role) and texts) break true;
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

fn isLater(key: []const u8) bool {
    return contains(&later, key);
}

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
