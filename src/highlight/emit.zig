//! emit.zig: the editor files of a grammar's `@highlight`.
//!
//!   textmate                 a TextMate grammar (.tmLanguage.json): VS Code,
//!                            and the editors that read TextMate grammars
//!   language-configuration   VS Code's language-configuration.json
//!   highlightjs              a highlight.js (11 or later) language module
//!   vim                      a Vim syntax file
//!
//! Every format matches `Highlight.items` in their order: where two items
//! match at one position, the first wins (Vim lets the item defined last
//! win, so the syntax file defines them from last to first). A region's
//! begin opens it; inside, its items and its body are tried before its
//! end, everywhere.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const json = @import("../json.zig");
const regex = @import("../lexgen/regex.zig");
const render = @import("render.zig");
const highlight = @import("highlight.zig");
const Highlight = highlight.Highlight;
const Item = highlight.Item;
const Match = highlight.Match;
const Region = highlight.Region;
const Scope = highlight.Scope;
const Rx = render.Rx;
const Dialect = render.Dialect;

pub const Target = enum {
    textmate,
    language_configuration,
    highlightjs,
    vim,

    pub fn parse(text: []const u8) ?Target {
        for (std.enums.values(Target)) |t| if (std.mem.eql(u8, t.name(), text)) return t;
        return null;
    }

    pub fn name(self: Target) []const u8 {
        return switch (self) {
            .textmate => "textmate",
            .language_configuration => "language-configuration",
            .highlightjs => "highlightjs",
            .vim => "vim",
        };
    }
};

pub const Error = Allocator.Error || Writer.Error;

/// Where `--highlight all` writes the file of `target`, under its
/// directory (`id` is the language id, the scope-name's last part).
pub fn layoutPath(allocator: Allocator, h: *const Highlight, target: Target) Allocator.Error![]const u8 {
    return switch (target) {
        .textmate => allocator.print("vscode/syntaxes/{s}.tmLanguage.json", .{h.id}),
        .language_configuration => allocator.dupe(u8, "vscode/language-configuration.json"),
        .highlightjs => allocator.print("highlightjs/{s}.js", .{h.id}),
        .vim => allocator.print("vim/syntax/{s}.vim", .{h.id}),
    };
}

/// The file `target` of `h`; `grammarName` and `version` go into its
/// header (where the format has comments).
pub fn emit(allocator: Allocator, h: *const Highlight, target: Target, grammarName: []const u8, version: []const u8) Error![]const u8 {
    var out: Writer.Allocating = .init(allocator);
    var e: Emitter = .{ .allocator = allocator, .h = h, .w = &out.writer, .grammarName = grammarName, .version = version };
    switch (target) {
        .textmate => try e.textmate(),
        .language_configuration => try e.languageConfiguration(),
        .highlightjs => try e.highlightjs(),
        .vim => try e.vim(),
    }
    return out.written();
}

/// The text of `r` in `dialect` (analyze has checked that it has one).
pub fn regexText(allocator: Allocator, r: Rx, dialect: Dialect) Error![]const u8 {
    var out: Writer.Allocating = .init(allocator);
    var renderer: render.Renderer = .{ .w = &out.writer, .dialect = dialect };
    renderer.rx(r) catch |err| switch (err) {
        error.WriteFailed => return error.WriteFailed,
        error.Unrenderable => unreachable,
    };
    return out.written();
}

/// A pattern with its contexts as one regex in `dialect` (not vim).
pub fn patternText(allocator: Allocator, p: highlight.Pattern, dialect: Dialect) Error![]const u8 {
    var out: Writer.Allocating = .init(allocator);
    var renderer: render.Renderer = .{ .w = &out.writer, .dialect = dialect };
    writeMatch(&renderer, p.lineStart, p.lineEnd, p.looks, &.{.{ .scope = .keyword, .captured = false, .rx = .{ .node = p.core } }}, .none) catch |err| switch (err) {
        error.WriteFailed => return error.WriteFailed,
        error.Unrenderable => unreachable,
    };
    return out.written();
}

/// How a match's pieces are written: as one expression (`none`), each a
/// capturing group (`groups`), or from piece `n` on, the match ending
/// after it (Vim's `\ze`).
const Pieces = union(enum) { none, groups, only: usize };

/// `^`, the lookbehinds, the pieces, the lookaheads, `$` (`^` and the
/// lookbehinds belong to the first piece). The contexts apply to the whole
/// match: a piece is an element of a sequence (an alternation grouped)
/// unless it stands alone.
fn writeMatch(r: *render.Renderer, lineStart: bool, lineEnd: bool, looks: []const highlight.Context, pieces: []const highlight.Piece, how: Pieces) render.Error!void {
    const from = switch (how) {
        .only => |n| n,
        else => 0,
    };
    if (from == 0) {
        if (lineStart) try r.lineStart();
        for (looks) |l| if (l.kind == .before or l.kind == .not_before) try r.look(l.kind, l.node);
    }
    const alone = pieces.len == 1 and !lineStart and !lineEnd and looks.len == 0;
    for (pieces[from..], from..) |p, i| switch (how) {
        .none => try r.rx(if (alone) p.rx else .{ .seq = &.{p.rx} }),
        .groups => try r.capture(p.rx),
        .only => {
            try r.rx(.{ .seq = &.{p.rx} });
            if (i == from and i + 1 < pieces.len) try r.w.writeAll("\\ze");
        },
    };
    for (looks) |l| if (l.kind == .after or l.kind == .not_after) try r.look(l.kind, l.node);
    if (lineEnd) try r.lineEnd();
}

const Emitter = struct {
    allocator: Allocator,
    h: *const Highlight,
    w: *Writer,
    grammarName: []const u8,
    version: []const u8,

    fn indent(self: *Emitter, depth: usize) Error!void {
        try self.w.splatByteAll(' ', depth * 2);
    }

    fn plainText(self: *Emitter, p: highlight.Plain, dialect: Dialect) Error![]const u8 {
        return self.matchText(.{ .pieces = &.{.{ .scope = .keyword, .captured = false, .rx = p.rx }}, .lineStart = false, .lineEnd = false, .looks = p.looks }, dialect, .none);
    }

    fn matchText(self: *Emitter, m: Match, dialect: Dialect, how: Pieces) Error![]const u8 {
        var out: Writer.Allocating = .init(self.allocator);
        var r: render.Renderer = .{ .w = &out.writer, .dialect = dialect, .word = self.h.wordChars };
        writeMatch(&r, m.lineStart, m.lineEnd, m.looks, m.pieces, how) catch |err| switch (err) {
            error.WriteFailed => return error.WriteFailed,
            error.Unrenderable => unreachable,
        };
        return out.written();
    }

    // --- TextMate -----------------------------------------------------------

    fn tmScope(self: *Emitter, scope: Scope) Error![]const u8 {
        return std.mem.concat(self.allocator, u8, &.{ scope.names().textmate, ".", self.h.id });
    }

    fn textmate(self: *Emitter) Error!void {
        const w = self.w;
        try w.writeAll("{\n  \"comment\": ");
        try json.string(w, try std.mem.concat(self.allocator, u8, &.{ "Generated by nexus v", self.version, " from ", self.grammarName, "; do not edit." }));
        try w.writeAll(",\n  \"name\": ");
        try json.string(w, self.h.language);
        try w.writeAll(",\n  \"scopeName\": ");
        try json.string(w, self.h.scopeName);
        try w.writeAll(",\n  \"fileTypes\": [");
        for (self.h.extensions, 0..) |ext, i| {
            if (i > 0) try w.writeAll(", ");
            try json.string(w, ext);
        }
        try w.writeAll("],\n  \"patterns\": ");
        try self.tmItems(self.h.items, null, 1);
        try w.writeAll("\n}\n");
    }

    fn tmItems(self: *Emitter, items: []const Item, body: ?Rx, depth: usize) Error!void {
        const w = self.w;
        try w.writeAll("[\n");
        for (items, 0..) |item, i| {
            if (i > 0) try w.writeAll(",\n");
            try self.indent(depth + 1);
            switch (item) {
                .match => |m| try self.tmMatch(m),
                .region => |r| try self.tmRegion(r, depth + 1),
                .plain => |p| {
                    try w.writeAll("{\"match\": ");
                    try json.string(w, try self.plainText(p, .oniguruma));
                    try w.writeAll("}");
                },
            }
        }
        if (body) |b| {
            if (items.len > 0) try w.writeAll(",\n");
            try self.indent(depth + 1);
            try w.writeAll("{\"match\": ");
            try json.string(w, try regexText(self.allocator, b, .oniguruma));
            try w.writeAll("}");
        }
        try w.writeAll("\n");
        try self.indent(depth);
        try w.writeAll("]");
    }

    fn tmMatch(self: *Emitter, m: Match) Error!void {
        const w = self.w;
        if (m.pieces.len == 1) {
            try w.writeAll("{\"name\": ");
            try json.string(w, try self.tmScope(m.pieces[0].scope));
            try w.writeAll(", \"match\": ");
            try json.string(w, try self.matchText(m, .oniguruma, .none));
            try w.writeAll("}");
            return;
        }
        try w.writeAll("{\"match\": ");
        try json.string(w, try self.matchText(m, .oniguruma, .groups));
        try w.writeAll(", \"captures\": {");
        for (m.pieces, 1..) |p, n| {
            if (n > 1) try w.writeAll(", ");
            try w.print("\"{d}\": {{\"name\": ", .{n});
            try json.string(w, try self.tmScope(p.scope));
            try w.writeAll("}");
        }
        try w.writeAll("}}");
    }

    fn tmRegion(self: *Emitter, r: Region, depth: usize) Error!void {
        const w = self.w;
        try w.writeAll("{\n");
        if (r.scope) |s| {
            try self.indent(depth + 1);
            try w.writeAll("\"name\": ");
            try json.string(w, try self.tmScope(s));
            try w.writeAll(",\n");
        }
        try self.indent(depth + 1);
        try w.writeAll("\"begin\": ");
        try json.string(w, try regexText(self.allocator, .{ .literal = .{ .bytes = r.begin, .min = r.begin.len } }, .oniguruma));
        try w.writeAll(",\n");
        try self.indent(depth + 1);
        try w.writeAll("\"end\": ");
        try json.string(w, try regexText(self.allocator, r.end, .oniguruma));
        try w.writeAll(",\n");
        try self.indent(depth + 1);
        try w.writeAll("\"applyEndPatternLast\": true,\n");
        try self.indent(depth + 1);
        try w.writeAll("\"patterns\": ");
        try self.tmItems(r.items, r.body, depth + 1);
        try w.writeAll("\n");
        try self.indent(depth);
        try w.writeAll("}");
    }

    // --- VS Code language configuration --------------------------------------

    fn languageConfiguration(self: *Emitter) Error!void {
        const w = self.w;
        try w.writeAll("{\n  \"comments\": {");
        var sep = false;
        if (self.h.lineComment) |c| {
            try w.writeAll("\"lineComment\": ");
            try json.string(w, c);
            sep = true;
        }
        if (self.h.blockComment) |c| {
            if (sep) try w.writeAll(", ");
            try w.writeAll("\"blockComment\": [");
            try json.string(w, c[0]);
            try w.writeAll(", ");
            try json.string(w, c[1]);
            try w.writeAll("]");
        }
        try w.writeAll("},\n  \"brackets\": [");
        const brackets = try self.bracketPairs();
        for (brackets, 0..) |b, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll("[");
            try json.string(w, b[0]);
            try w.writeAll(", ");
            try json.string(w, b[1]);
            try w.writeAll("]");
        }
        const quotes = try self.regionPairs();
        try w.writeAll("],\n  \"autoClosingPairs\": [");
        var n: usize = 0;
        for (brackets) |b| {
            if (n > 0) try w.writeAll(", ");
            try w.writeAll("{\"open\": ");
            try json.string(w, b[0]);
            try w.writeAll(", \"close\": ");
            try json.string(w, b[1]);
            try w.writeAll("}");
            n += 1;
        }
        for (quotes) |q| {
            if (n > 0) try w.writeAll(", ");
            try w.writeAll("{\"open\": ");
            try json.string(w, q[0]);
            try w.writeAll(", \"close\": ");
            try json.string(w, q[1]);
            try w.writeAll(", \"notIn\": [\"string\", \"comment\"]}");
            n += 1;
        }
        try w.writeAll("],\n  \"surroundingPairs\": [");
        n = 0;
        for ([_][]const [2][]const u8{ brackets, quotes }) |pairs| for (pairs) |b| {
            if (n > 0) try w.writeAll(", ");
            try w.writeAll("[");
            try json.string(w, b[0]);
            try w.writeAll(", ");
            try json.string(w, b[1]);
            try w.writeAll("]");
            n += 1;
        };
        try w.writeAll("]");
        if (self.h.indent) |inc| {
            try w.writeAll(",\n  \"indentationRules\": {\n    \"increaseIndentPattern\": ");
            try json.string(w, try patternText(self.allocator, inc, .javascript));
            try w.writeAll(",\n    \"decreaseIndentPattern\": ");
            try json.string(w, try patternText(self.allocator, self.h.dedent.?, .javascript));
            try w.writeAll("\n  }");
        }
        try w.writeAll("\n}\n");
    }

    /// `( )`, `[ ]`, `{ }` and `< >` when both are literals listed as
    /// punctuation (directly, or as the token of a rule that is exactly
    /// that literal).
    fn bracketPairs(self: *Emitter) Error![]const [2][]const u8 {
        var pairs: std.ArrayList([2][]const u8) = .empty;
        for ([_][2][]const u8{ .{ "(", ")" }, .{ "[", "]" }, .{ "{", "}" }, .{ "<", ">" } }) |pair| {
            if (self.isPunctuation(pair[0]) and self.isPunctuation(pair[1])) try pairs.append(self.allocator, pair);
        }
        return pairs.toOwnedSlice(self.allocator);
    }

    fn isPunctuation(self: *Emitter, text: []const u8) bool {
        for (self.h.items) |item| {
            const m = switch (item) {
                .match => |m| m,
                .region, .plain => continue,
            };
            if (m.pieces.len != 1 or m.pieces[0].scope != .punctuation or m.looks.len > 0 or m.lineStart or m.lineEnd) continue;
            if (rxIs(m.pieces[0].rx, text)) return true;
        }
        return false;
    }

    /// Whether `r` matches exactly `text` (or has an alternative that is
    /// exactly `text`).
    fn rxIs(r: Rx, text: []const u8) bool {
        return switch (r) {
            .literal => |l| l.min == l.bytes.len and std.mem.eql(u8, l.bytes, text),
            .alt => |alts| for (alts) |a| {
                if (rxIs(a, text)) break true;
            } else false,
            .node => |n| text.len == 1 and n.* == .set and n.set.only() == text[0],
            .seq => false,
        };
    }

    /// The begin and end of each region whose end is a literal.
    fn regionPairs(self: *Emitter) Error![]const [2][]const u8 {
        var pairs: std.ArrayList([2][]const u8) = .empty;
        var buf: std.ArrayList(u8) = .empty;
        for (self.h.items) |item| {
            const r = switch (item) {
                .region => |r| r,
                .match, .plain => continue,
            };
            const end = (try regex.literal(r.end.node, &buf, self.allocator)) orelse continue;
            const pair: [2][]const u8 = .{ r.begin, try self.allocator.dupe(u8, end) };
            const seen = for (pairs.items) |p| {
                if (std.mem.eql(u8, p[0], pair[0]) and std.mem.eql(u8, p[1], pair[1])) break true;
            } else false;
            if (!seen) try pairs.append(self.allocator, pair);
        }
        return pairs.toOwnedSlice(self.allocator);
    }

    // --- highlight.js ---------------------------------------------------------

    fn highlightjs(self: *Emitter) Error!void {
        const w = self.w;
        try w.print(
            \\// Generated by nexus v{s} from {s}; do not edit.
            \\// A highlight.js (11 or later) language definition, an ES module:
            \\//   import {s}, {{ extensions }} from "./{s}.js";
            \\//   hljs.registerLanguage("{s}", {s});
            \\// Every word and token is matched by `contains`, in order; `keywords`
            \\// is empty.
            \\
            \\/** The file extensions of the language, for a host to map them. */
            \\export const extensions = [
        , .{ self.version, self.grammarName, self.h.id, self.h.id, self.h.id, self.h.id });
        for (self.h.extensions, 0..) |ext, i| {
            if (i > 0) try w.writeAll(", ");
            try json.string(w, ext);
        }
        try w.writeAll("];\n\nexport default function (hljs) {\n  return {\n    \"name\": ");
        try json.string(w, self.h.language);
        try w.writeAll(",\n    \"aliases\": [");
        for (self.h.extensions, 0..) |ext, i| {
            if (i > 0) try w.writeAll(", ");
            try json.string(w, ext);
        }
        try w.writeAll("],\n    \"keywords\": {},\n    \"contains\": ");
        try self.jsItems(self.h.items, null, 2);
        try w.writeAll("\n  };\n}\n");
    }

    fn jsItems(self: *Emitter, items: []const Item, body: ?Rx, depth: usize) Error!void {
        const w = self.w;
        try w.writeAll("[\n");
        for (items, 0..) |item, i| {
            if (i > 0) try w.writeAll(",\n");
            try self.indent(depth + 1);
            switch (item) {
                .match => |m| try self.jsMatch(m),
                .region => |r| try self.jsRegion(r, depth + 1),
                .plain => |p| {
                    try w.writeAll("{\"match\": ");
                    try json.string(w, try self.plainText(p, .javascript));
                    try w.writeAll("}");
                },
            }
        }
        if (body) |b| {
            if (items.len > 0) try w.writeAll(",\n");
            try self.indent(depth + 1);
            try w.writeAll("{\"match\": ");
            try json.string(w, try regexText(self.allocator, b, .javascript));
            try w.writeAll("}");
        }
        try w.writeAll("\n");
        try self.indent(depth);
        try w.writeAll("]");
    }

    fn jsMatch(self: *Emitter, m: Match) Error!void {
        const w = self.w;
        if (m.pieces.len == 1) {
            try w.writeAll("{\"scope\": ");
            try json.string(w, m.pieces[0].scope.names().hljs);
            try w.writeAll(", \"match\": ");
            try json.string(w, try self.matchText(m, .javascript, .none));
            try w.writeAll("}");
            return;
        }
        // Multi-match: one regex per piece; contexts join the first and
        // the last.
        try w.writeAll("{\"scope\": {");
        for (m.pieces, 1..) |p, n| {
            if (n > 1) try w.writeAll(", ");
            try w.print("\"{d}\": ", .{n});
            try json.string(w, p.scope.names().hljs);
        }
        try w.writeAll("}, \"match\": [");
        for (m.pieces, 0..) |p, i| {
            if (i > 0) try w.writeAll(", ");
            const first = i == 0;
            const last = i + 1 == m.pieces.len;
            var looks: std.ArrayList(highlight.Context) = .empty;
            for (m.looks) |l| {
                const behind = l.kind == .before or l.kind == .not_before;
                if ((behind and first) or (!behind and last)) try looks.append(self.allocator, l);
            }
            const one: Match = .{ .pieces = &.{p}, .lineStart = m.lineStart and first, .lineEnd = m.lineEnd and last, .looks = looks.items };
            try json.string(w, try self.matchText(one, .javascript, .none));
        }
        try w.writeAll("]}");
    }

    fn jsRegion(self: *Emitter, r: Region, depth: usize) Error!void {
        const w = self.w;
        try w.writeAll("{\n");
        if (r.scope) |s| {
            try self.indent(depth + 1);
            try w.writeAll("\"scope\": ");
            try json.string(w, s.names().hljs);
            try w.writeAll(",\n");
        }
        try self.indent(depth + 1);
        try w.writeAll("\"begin\": ");
        try json.string(w, try regexText(self.allocator, .{ .literal = .{ .bytes = r.begin, .min = r.begin.len } }, .javascript));
        try w.writeAll(",\n");
        try self.indent(depth + 1);
        try w.writeAll("\"end\": ");
        try json.string(w, try regexText(self.allocator, r.end, .javascript));
        try w.writeAll(",\n");
        try self.indent(depth + 1);
        try w.writeAll("\"contains\": ");
        try self.jsItems(r.items, r.body, depth + 1);
        try w.writeAll("\n");
        try self.indent(depth);
        try w.writeAll("}");
    }

    // --- Vim ------------------------------------------------------------------

    /// `rig` + `KeywordControl` for `keyword.control`.
    fn vimGroup(self: *Emitter, scope: Scope) Error![]const u8 {
        return std.mem.concat(self.allocator, u8, &.{ self.h.id, try camel(self.allocator, scope.names().name, '.') });
    }

    /// The group of an item within the region of `token`.
    fn vimInner(self: *Emitter, scope: Scope, token: []const u8) Error![]const u8 {
        return std.mem.concat(self.allocator, u8, &.{ try self.vimGroup(scope), "In", try camel(self.allocator, token, '_') });
    }

    fn vim(self: *Emitter) Error!void {
        const w = self.w;
        try w.print(
            \\" Vim syntax file
            \\" Language: {s}
            \\" Generated by nexus v{s} from {s}; do not edit.
            \\" Install as syntax/{s}.vim; with `autocmd BufRead,BufNewFile *.{s} setfiletype {s}`
            \\" in a ftdetect/{s}.vim beside it.
            \\
            \\if exists("b:current_syntax")
            \\  finish
            \\endif
            \\scriptencoding utf-8
            \\
            \\syn case match
            \\syn sync fromstart
            \\
            \\" Where two items start at one place, Vim takes the one defined last:
            \\" the items are defined from the last tried to the first.
            \\
        , .{ self.h.language, self.version, self.grammarName, self.h.id, self.h.extensions[0], self.h.id, self.h.id });
        var used: std.ArrayList([2][]const u8) = .empty;
        var seq: usize = 0;
        var defs: std.ArrayList([]const u8) = .empty;
        for (self.h.items) |item| try defs.append(self.allocator, try self.vimItem(item, null, &used, &seq));
        var i = defs.items.len;
        while (i > 0) {
            i -= 1;
            try w.writeAll(defs.items[i]);
        }
        try w.writeAll("\n");
        // Links: each scope's group to Vim's default group, every other
        // group to its scope's group.
        for (std.enums.values(Scope)) |scope| {
            const group = try self.vimGroup(scope);
            const isUsed = for (used.items) |u| {
                if (std.mem.eql(u8, u[0], group) or std.mem.eql(u8, u[1], group)) break true;
            } else false;
            if (isUsed) try w.print("hi def link {s} {s}\n", .{ group, scope.names().vim });
        }
        var links: std.ArrayList([2][]const u8) = .empty;
        for (used.items) |u| {
            if (u[1].len == 0 or std.mem.eql(u8, u[0], u[1])) continue;
            const dup = for (links.items) |l| {
                if (std.mem.eql(u8, l[0], u[0])) break true;
            } else false;
            if (!dup) try links.append(self.allocator, u);
        }
        std.mem.sort([2][]const u8, links.items, {}, struct {
            fn less(_: void, a: [2][]const u8, b: [2][]const u8) bool {
                return std.mem.lessThan(u8, a[0], b[0]);
            }
        }.less);
        for (links.items) |l| try w.print("hi def link {s} {s}\n", .{ l[0], l[1] });
        try w.print("\nlet b:current_syntax = \"{s}\"\n", .{self.h.id});
    }

    /// The first group of a match: its scope's (within the region of
    /// `token`, when not null).
    fn vimFirst(self: *Emitter, m: Match, token: ?[]const u8) Error![]const u8 {
        const scope = m.pieces[0].scope;
        return if (token) |t| self.vimInner(scope, t) else self.vimGroup(scope);
    }

    /// The definitions of `item` (inside the region of `token`, when not
    /// null). `used` collects [group, the scope group it links to, or ""];
    /// `seq` numbers the matches with captures.
    ///
    /// A match with captures is a chain: its first part matches where the
    /// rest follows (`\ze`), and names the next part's group as its
    /// `nextgroup`, which Vim tries right where it ends.
    fn vimItem(self: *Emitter, item: Item, token: ?[]const u8, used: *std.ArrayList([2][]const u8), seq: *usize) Error![]const u8 {
        var out: Writer.Allocating = .init(self.allocator);
        const w = &out.writer;
        const contained = if (token != null) " contained" else "";
        switch (item) {
            .plain => |p| try w.print("syn match {s}Plain \"\\v{s}\"\n", .{ self.h.id, try self.plainText(p, .vim) }),
            .match => |m| {
                const first = try self.vimFirst(m, token);
                try used.append(self.allocator, .{ first, try self.vimGroup(m.pieces[0].scope) });
                if (m.pieces.len == 1) {
                    try w.print("syn match {s} \"\\v{s}\"{s}\n", .{ first, try self.matchText(m, .vim, .none), contained });
                    return out.written();
                }
                seq.* += 1;
                var groups = try self.allocator.alloc([]const u8, m.pieces.len);
                groups[0] = first;
                for (groups[1..], m.pieces[1..], 2..) |*g, p, k| {
                    g.* = try self.allocator.print("{s}Seq{d}Part{d}", .{ self.h.id, seq.*, k });
                    try used.append(self.allocator, .{ g.*, try self.vimGroup(p.scope) });
                }
                for (m.pieces, 0..) |_, k| {
                    try w.print("syn match {s} \"\\v{s}\"", .{ groups[k], try self.matchText(m, .vim, .{ .only = k }) });
                    if (k > 0 or token != null) try w.writeAll(" contained");
                    if (k + 1 < groups.len) try w.print(" nextgroup={s}", .{groups[k + 1]});
                    try w.writeAll("\n");
                }
            },
            .region => |r| {
                const group = if (r.scope) |sc| try self.vimGroup(sc) else try std.mem.concat(self.allocator, u8, &.{ self.h.id, try camel(self.allocator, r.token, '_') });
                try used.append(self.allocator, .{ group, if (r.scope) |sc| try self.vimGroup(sc) else "" });
                var names: std.ArrayList([]const u8) = .empty;
                for (r.items) |sub| {
                    const name = try self.vimFirst(sub.match, r.token);
                    const dup = for (names.items) |o| {
                        if (std.mem.eql(u8, o, name)) break true;
                    } else false;
                    if (!dup) try names.append(self.allocator, name);
                }
                const begin = try regexText(self.allocator, .{ .literal = .{ .bytes = r.begin, .min = r.begin.len } }, .vim);
                const end = try regexText(self.allocator, r.end, .vim);
                try w.print("syn region {s} matchgroup={s} start=\"\\v{s}\"", .{ group, group, begin });
                if (r.body) |b| try w.print(" skip=\"\\v{s}\"", .{try regexText(self.allocator, b, .vim)});
                try w.print(" end=\"\\v{s}\" contains={s}\n", .{ end, try std.mem.join(self.allocator, ",", names.items) });
                var defs: std.ArrayList([]const u8) = .empty;
                for (r.items) |sub| try defs.append(self.allocator, try self.vimItem(sub, r.token, used, seq));
                var k = defs.items.len;
                while (k > 0) {
                    k -= 1;
                    try w.writeAll(defs.items[k]);
                }
            },
        }
        return out.written();
    }
};

/// `parts` joined, each capitalized: `KeywordControl`, `StringDq`.
fn camel(allocator: Allocator, text: []const u8, sep: u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var parts = std.mem.splitScalar(u8, text, sep);
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        try out.append(allocator, std.ascii.toUpper(part[0]));
        for (part[1..]) |c| try out.append(allocator, std.ascii.toLower(c));
    }
    return out.toOwnedSlice(allocator);
}
