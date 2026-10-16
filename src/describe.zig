//! describe.zig: `nexus --describe`, a grammar as JSON for other tools.
//!
//! The format (`"format": 1`) is documented in docs/GRAMMAR.md,
//! "Describing a grammar". Keys come in a fixed order and every list in
//! the grammar's order, so one grammar gives the same bytes every run.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const json = @import("json.zig");
const grammar = @import("grammar.zig");
const regex = @import("lexgen/regex.zig");
const render = @import("highlight/render.zig");
const highlight = @import("highlight/highlight.zig");
const emit = @import("highlight/emit.zig");
const codegen = @import("codegen/codegen.zig");

pub const format = 1;

pub const Input = struct {
    version: []const u8,
    grammarFile: []const u8,
    ir: *const grammar.GrammarIR,
    spec: *const grammar.LexerSpec,
    /// The generated grammar; null for a grammar without parser rules.
    g: ?*const grammar.Grammar,
    highlight: ?*const highlight.Highlight,
};

pub const Error = Allocator.Error || Writer.Error;

pub fn write(allocator: Allocator, in: Input) Error![]const u8 {
    var out: Writer.Allocating = .init(allocator);
    var d: Describer = .{ .allocator = allocator, .w = &out.writer, .in = in };
    try d.all();
    return out.written();
}

const Describer = struct {
    allocator: Allocator,
    w: *Writer,
    in: Input,

    fn regexOf(self: *Describer, node: *const regex.Node) Error![]const u8 {
        return emit.regexText(self.allocator, .{ .node = node }, .bytes);
    }

    fn all(self: *Describer) Error!void {
        const w = self.w;
        try w.print("{{\n  \"format\": {d},\n  \"nexus\": ", .{format});
        try json.string(w, self.in.version);
        try w.writeAll(",\n  \"grammar\": ");
        try json.string(w, self.in.grammarFile);
        try w.writeAll(",\n  \"lang\": ");
        try json.optString(w, self.in.ir.lang);
        try w.writeAll(",\n  \"tokens\": [");
        try self.tokens();
        try w.writeAll("],\n  \"rules\": [");
        try self.rules();
        try w.writeAll("],\n  \"states\": [");
        for (self.in.spec.states.items, 0..) |st, i| {
            try self.item(i);
            try w.writeAll("{\"name\": ");
            try json.string(w, st.name);
            try w.print(", \"initial\": {d}}}", .{st.initialValue});
        }
        try self.close(self.in.spec.states.items.len);
        try w.writeAll("],\n  \"after\": [");
        try self.actions(self.in.spec.afterActions.items);
        try w.writeAll("],\n  \"keywords\": {");
        try self.keywords();
        try w.writeAll("},\n  \"trivia\": [");
        for (self.in.ir.trivia, 0..) |t, i| {
            if (i > 0) try w.writeAll(", ");
            try json.string(w, t);
        }
        try w.writeAll("],\n  \"highlight\": ");
        if (self.in.highlight) |h| try self.highlightOf(h) else try w.writeAll("null");
        try w.writeAll(",\n  \"schema\": ");
        if (self.in.ir.schema) |s| try self.schema(s) else try w.writeAll("null");
        try w.writeAll("\n}\n");
    }

    /// Before the `i`-th item of a list written one item per line.
    fn item(self: *Describer, i: usize) Error!void {
        try self.w.writeAll(if (i == 0) "\n    " else ",\n    ");
    }

    /// After a list of `n` items written one per line.
    fn close(self: *Describer, n: usize) Error!void {
        if (n > 0) try self.w.writeAll("\n  ");
    }

    fn tokens(self: *Describer) Error!void {
        const w = self.w;
        for (self.in.spec.tokens.items, 0..) |name, i| {
            try self.item(i);
            try w.writeAll("{\"name\": ");
            try json.string(w, name);
            const terminal = self.terminalOf(name);
            try w.writeAll(", \"terminal\": ");
            if (terminal) |t| try w.print("{d}", .{t}) else try w.writeAll("null");
            try w.writeAll(", \"display\": ");
            var display: ?[]const u8 = null;
            if (terminal) |t| {
                display = try codegen.symbolDisplayName(self.allocator, self.in.g.?, self.in.g.?.symbols.items[t]);
            } else for (self.in.ir.displayNames) |dn| {
                if (std.ascii.eqlIgnoreCase(dn.token, name)) display = dn.name;
            }
            try json.optString(w, display);
            try w.writeAll("}");
        }
        try self.close(self.in.spec.tokens.items.len);
    }

    /// The grammar symbol the parser reads token `name` as.
    fn terminalOf(self: *Describer, name: []const u8) ?u16 {
        const g = self.in.g orelse return null;
        if (std.mem.eql(u8, name, "eof")) return g.endId;
        if (g.promotable()) |tok| if (std.mem.eql(u8, tok, name)) {
            for (g.symbols.items) |sym| if (sym.kind == .terminal and std.ascii.eqlIgnoreCase(sym.name, tok)) return sym.id;
            return null;
        };
        return g.terminalOf(name);
    }

    fn rules(self: *Describer) Error!void {
        const w = self.w;
        for (self.in.spec.rules.items, 0..) |rule, i| {
            try self.item(i);
            try w.print("{{\"line\": {d}, \"token\": ", .{rule.line});
            try json.optString(w, if (std.mem.eql(u8, rule.token, "skip")) null else rule.token);
            try w.writeAll(", \"pattern\": ");
            if (rule.pattern.len == 0) {
                try w.writeAll("null, \"regex\": null, \"literal\": null, \"trail\": null");
            } else {
                var d: regex.Diagnostic = .{};
                // The lowerer has parsed every pattern.
                const p = regex.parse(self.allocator, rule.pattern, &d) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidPattern => unreachable,
                };
                try json.string(w, rule.pattern);
                try w.writeAll(", \"regex\": ");
                try json.string(w, try self.regexOf(p.main));
                try w.writeAll(", \"literal\": ");
                try json.optString(w, rule.literal);
                try w.writeAll(", \"trail\": ");
                if (p.trail) |t| try json.string(w, try self.regexOf(t)) else try w.writeAll("null");
            }
            try w.writeAll(", \"guards\": [");
            for (rule.guards, 0..) |g, k| {
                if (k > 0) try w.writeAll(", ");
                try w.writeAll("{\"var\": ");
                try json.string(w, g.variable);
                try w.print(", \"negated\": {}, \"op\": ", .{g.negated});
                if (g.op == .truthy) {
                    try w.writeAll("null, \"value\": null}");
                } else {
                    try json.string(w, switch (g.op) {
                        .eq => "==",
                        .ne => "!=",
                        .gt => ">",
                        .lt => "<",
                        .ge => ">=",
                        .le => "<=",
                        .truthy => unreachable,
                    });
                    try w.print(", \"value\": {d}}}", .{g.value});
                }
            }
            try w.print("], \"skip\": {}, \"hold\": {}, \"rewind\": ", .{ rule.isSkip, rule.hold });
            if (rule.rewind) |n| try w.print("{d}", .{n}) else try w.writeAll("null");
            try w.writeAll(", \"actions\": [");
            try self.actions(rule.actions);
            try w.writeAll("]}");
        }
        try self.close(self.in.spec.rules.items.len);
    }

    fn actions(self: *Describer, list: []const grammar.Action) Error!void {
        const w = self.w;
        for (list, 0..) |a, k| {
            if (k > 0) try w.writeAll(", ");
            try w.print("{{\"kind\": \"{s}\", \"var\": ", .{@tagName(a.kind)});
            try json.string(w, a.variable.?);
            switch (a.kind) {
                .set => try w.print(", \"value\": {d}", .{a.value.?}),
                .counted => {
                    try w.writeAll(", \"char\": ");
                    try json.string(w, &.{a.char.?});
                },
                .inc, .dec => {},
            }
            try w.writeAll("}");
        }
    }

    fn keywords(self: *Describer) Error!void {
        const w = self.w;
        for (self.in.ir.keywordGroups, 0..) |group, i| {
            try self.item(i);
            try json.string(w, group.name);
            try w.print(": {{\"caseless\": {}, \"base\": {d}, \"entries\": [", .{ group.caseless, group.base });
            for (group.entries, 0..) |e, k| {
                if (k > 0) try w.writeAll(", ");
                try w.writeAll("{\"word\": ");
                try json.string(w, e.word);
                try w.print(", \"min\": {d}, \"id\": {d}, \"terminal\": ", .{ e.min, group.base + e.terminal });
                const name = group.terminals[e.terminal];
                try json.optString(w, if (e.alias) null else name);
                try w.writeAll(", \"alias_of\": ");
                try json.optString(w, if (e.alias) name else null);
                try w.writeAll("}");
            }
            try w.writeAll("]}");
        }
        try self.close(self.in.ir.keywordGroups.len);
    }

    fn highlightOf(self: *Describer, h: *const highlight.Highlight) Error!void {
        const w = self.w;
        try w.writeAll("{\n    \"language\": ");
        try json.string(w, h.language);
        try w.writeAll(",\n    \"scope_name\": ");
        try json.string(w, h.scopeName);
        try w.writeAll(",\n    \"extensions\": [");
        for (h.extensions, 0..) |e, i| {
            if (i > 0) try w.writeAll(", ");
            try json.string(w, e);
        }
        try w.writeAll("],\n    \"line_comment\": ");
        try json.optString(w, h.lineComment);
        try w.writeAll(",\n    \"block_comment\": ");
        if (h.blockComment) |c| {
            try w.writeAll("[");
            try json.string(w, c[0]);
            try w.writeAll(", ");
            try json.string(w, c[1]);
            try w.writeAll("]");
        } else try w.writeAll("null");
        try w.writeAll(",\n    \"indent\": ");
        if (h.indent) |p| try json.string(w, try emit.patternText(self.allocator, p, .bytes)) else try w.writeAll("null");
        try w.writeAll(",\n    \"dedent\": ");
        if (h.dedent) |p| try json.string(w, try emit.patternText(self.allocator, p, .bytes)) else try w.writeAll("null");
        try w.writeAll(",\n    \"word_chars\": ");
        try json.string(w, try self.regexOf(&.{ .set = h.wordChars }));
        try w.writeAll(",\n    \"entries\": [");
        for (h.entries, 0..) |e, i| {
            try w.writeAll(if (i == 0) "\n      " else ",\n      ");
            try w.print("{{\"line\": {d}, \"scope\": \"{s}\", \"literals\": [", .{ e.line, e.scope.names().name });
            for (e.literals, 0..) |l, k| {
                if (k > 0) try w.writeAll(", ");
                try json.string(w, l);
            }
            try w.writeAll("], \"tokens\": [");
            for (e.tokens, 0..) |t, k| {
                if (k > 0) try w.writeAll(", ");
                try json.string(w, t);
            }
            try w.writeAll("], \"groups\": [");
            for (e.groups, 0..) |g, k| {
                if (k > 0) try w.writeAll(", ");
                try json.string(w, g);
            }
            try w.writeAll("], \"pattern\": ");
            try json.optString(w, e.pattern);
            try w.writeAll(", \"regex\": ");
            if (e.pieces.len == 0) {
                try w.writeAll("null");
            } else {
                var out: Writer.Allocating = .init(self.allocator);
                var r: render.Renderer = .{ .w = &out.writer, .dialect = .bytes };
                for (e.pieces) |p| {
                    (if (e.pieces.len == 1) r.rx(p.rx) else r.capture(p.rx)) catch |err| switch (err) {
                        error.WriteFailed => return error.WriteFailed,
                        error.Unrenderable => unreachable, // bytes renders every pattern
                    };
                }
                try json.string(w, out.written());
            }
            try w.writeAll(", \"captures\": [");
            if (e.pieces.len > 1) for (e.pieces, 0..) |p, k| {
                if (k > 0) try w.writeAll(", ");
                try w.print("{{\"scope\": \"{s}\", \"captured\": {}, \"regex\": ", .{ p.scope.names().name, p.captured });
                try json.string(w, try emit.regexText(self.allocator, p.rx, .bytes));
                try w.writeAll("}");
            };
            try w.print("], \"line_start\": {}, \"line_end\": {}, \"contexts\": [", .{ e.lineStart, e.lineEnd });
            for (e.contexts, 0..) |c, k| {
                if (k > 0) try w.writeAll(", ");
                try w.print("{{\"kind\": \"{s}\", \"pattern\": ", .{c.kind.name()});
                try json.string(w, c.text);
                try w.writeAll(", \"regex\": ");
                try json.string(w, try self.regexOf(c.node));
                try w.writeAll("}");
            }
            try w.writeAll("], \"within\": ");
            try json.optString(w, e.within);
            try w.writeAll("}");
        }
        try w.writeAll("\n    ]\n  }");
    }

    fn schema(self: *Describer, s: grammar.Schema) Error!void {
        const w = self.w;
        try w.writeAll("{\"kinds\": [");
        for (s.kinds, 0..) |k, i| {
            try self.item(i);
            try w.writeAll("{\"name\": ");
            try json.string(w, k.tag);
            try w.writeAll(", \"roles\": [");
            for (k.roles, 0..) |r, n| {
                if (n > 0) try w.writeAll(", ");
                try w.writeAll("{\"name\": ");
                try json.string(w, r.name);
                try w.writeAll(", \"type\": ");
                try json.string(w, try self.roleType(r.type));
                try w.print(", \"optional\": {}, \"rest\": {}}}", .{ r.optional, r.rest });
            }
            try w.writeAll("], \"side\": [");
            for (k.side, 0..) |name, n| {
                if (n > 0) try w.writeAll(", ");
                try json.string(w, name);
            }
            try w.print("], \"wrapper\": {}}}", .{k.wrapper});
        }
        try self.close(s.kinds.len);
        try w.writeAll("]}");
    }

    /// A role's type as written: `any`, `node`, `leaf`, `group`, `tag`,
    /// `tag(a|b)`, or kinds `a|b`.
    fn roleType(self: *Describer, t: grammar.Schema.RoleType) Error![]const u8 {
        return switch (t) {
            .any => "any",
            .node => "node",
            .leaf => "leaf",
            .group => "group",
            .tag => |values| if (values.len == 0) "tag" else try std.mem.concat(self.allocator, u8, &.{ "tag(", try std.mem.join(self.allocator, "|", values), ")" }),
            .kinds => |kinds| try std.mem.join(self.allocator, "|", kinds),
        };
    }
};
