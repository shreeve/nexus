//! lsp.zig: a language server (LSP 3.17) on standard input and output for
//! the language of one grammar file, written by `nexus --editor` beside
//! the grammar's parser (`parser.zig`), its table (`language.zig`) and the
//! language's functions (`hooks.zig`, docs/LSP.md).
//!
//! From the grammar alone it gives syntax errors as you type, semantic
//! tokens, folding, selection ranges and keyword completion. Every other
//! feature waits behind a function of `hooks.zig`, and a function left as
//! `lsp.todo` is never called: its features are not advertised. The
//! overrides (`parseDiagnostics`, `tokens`, `symbols`, `folds`) replace the
//! grammar's answers with the language's own.
//!
//! Messages are JSON-RPC, each after a `Content-Length` header. Positions
//! count UTF-16 code units, or bytes when the client offers `utf-8`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const parser = @import("parser.zig");
const hooks = @import("hooks.zig");
const language = @import("language.zig");

// =============================================================================
// What the language's functions read and return
// =============================================================================

/// A function of `hooks.zig` not yet written: `pub const describe =
/// lsp.todo;`. Its features are not advertised and it is never called.
pub const Todo = struct {};
pub const todo: Todo = .{};

/// A position: a file and a byte offset in its text.
pub const Pos = struct { path: []const u8, offset: u32 };

/// A byte range of a file.
pub const Span = struct { path: []const u8, start: u32, end: u32 };

/// LSP's symbol kinds, in its numbering.
pub const SymbolKind = enum(u8) {
    file = 1,
    module,
    namespace,
    package,
    class,
    method,
    property,
    field,
    constructor,
    @"enum",
    interface,
    function,
    variable,
    constant,
    string,
    number,
    boolean,
    array,
    object,
    key,
    null,
    enum_member,
    @"struct",
    event,
    operator,
    type_parameter,
};

/// A declaration. `id` is equal for one declaration wherever it is seen:
/// the declaring file and the offset of the declaration is enough.
pub const Symbol = struct {
    id: []const u8,
    name: []const u8,
    kind: SymbolKind,
    decl: Span,
    /// One line: a signature or a type.
    detail: []const u8 = "",
    /// Markdown.
    doc: []const u8 = "",
};

/// A type, as the language names it to itself.
pub const TypeId = u64;

/// What `describe` describes.
pub const Subject = union(enum) { symbol: Symbol, type: TypeId };

pub const Description = struct {
    markdown: []const u8,
    /// Where the subject is declared, when it is.
    decl: ?Span = null,
};

pub const Param = struct { name: []const u8, type: []const u8 = "", doc: []const u8 = "" };

pub const Signature = struct {
    label: []const u8,
    params: []const Param = &.{},
    result: []const u8 = "",
    doc: []const u8 = "",
};

/// The signatures of the call around a position, the one that applies
/// and the parameter the position is in.
pub const SignatureHelp = struct {
    signatures: []const Signature,
    active: u32 = 0,
    param: u32 = 0,
};

pub const Severity = enum(u8) { @"error" = 1, warning, info, hint };

pub const Note = struct { span: Span, message: []const u8 };

pub const Diagnostic = struct {
    span: Span,
    severity: Severity = .@"error",
    message: []const u8,
    notes: []const Note = &.{},
};

/// The open files: their paths and their texts, which the language reads
/// in place of the files on disk.
pub const Overlay = struct {
    io: std.Io,
    paths: []const []const u8,
    texts: []const []const u8,

    /// The text of an open file.
    pub fn get(self: Overlay, path: []const u8) ?[]const u8 {
        for (self.paths, self.texts) |p, t| if (std.mem.eql(u8, p, path)) return t;
        return null;
    }

    /// The text of a file: the open file's, else the file on disk's.
    pub fn read(self: Overlay, arena: Allocator, path: []const u8) ![]const u8 {
        if (self.get(path)) |text| return text;
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(max_message_bytes));
    }
};

/// What `analyze` returns: the language's analysis, its diagnostics, and
/// every file it read.
pub fn Analyzed(comptime A: type) type {
    return struct {
        analysis: A,
        diagnostics: []const Diagnostic = &.{},
        files: []const []const u8 = &.{},
    };
}

/// The scopes of `@highlight`, the semantic token types the server
/// declares (`legend`).
pub const Scope = enum(u8) {
    keyword,
    keyword_control,
    keyword_operator,
    constant,
    constant_numeric,
    constant_symbol,
    string,
    string_escape,
    comment,
    operator,
    punctuation,
    type,
    function,
    function_builtin,
    label,
    storage_modifier,
    variable_parameter,
    variable_special,
    invalid,
};

/// The semantic token types, one per `Scope`, as `package.json` declares
/// them.
pub const legend = [_][]const u8{
    "keyword",         "keywordControl",    "keywordOperator", "constant",        "constantNumeric",
    "constantSymbol",  "string",            "stringEscape",    "comment",         "operator",
    "punctuation",     "type",              "function",        "functionBuiltin", "label",
    "storageModifier", "variableParameter", "variableSpecial", "invalid",
};

/// A semantic token: a byte range of the file and its scope.
pub const Token = struct { start: u32, len: u32, scope: Scope };

/// An entry of the outline. `start`..`end` is all of it; `name_start`..
/// `name_end` is what the editor selects.
pub const OutlineItem = struct {
    name: []const u8,
    kind: SymbolKind,
    start: u32,
    end: u32,
    name_start: u32,
    name_end: u32,
    detail: []const u8 = "",
    children: []const OutlineItem = &.{},
};

/// A folding range: the lines from the line of `start` to that of `end`.
pub const Fold = struct { start: u32, end: u32, comment: bool = false };

// =============================================================================
// Which functions the language has written
// =============================================================================

const Analysis = if (@hasDecl(hooks, "Analysis")) hooks.Analysis else void;

fn has(comptime name: []const u8) bool {
    return @hasDecl(hooks, name) and @TypeOf(@field(hooks, name)) != Todo;
}

/// The characters that ask for completion: the language's
/// `completionTriggers`, if it declares them.
const triggers: []const []const u8 = if (@hasDecl(hooks, "completionTriggers")) hooks.completionTriggers else &.{};

comptime {
    for ([_][]const u8{ "symbolAt", "typeAt", "members", "visible", "signatures", "describe", "modules", "references", "renamable" }) |name| {
        if (has(name) and !has("analyze")) @compileError("hooks." ++ name ++ " reads an analysis: write hooks.analyze too");
    }
}

const BaseParser = parser.BaseParser;
const start: parser.Start = std.enums.values(parser.Start)[0];

// =============================================================================
// Framing
// =============================================================================

/// The largest message the server reads.
const max_message_bytes = 64 << 20;

const FrameError = error{ BadHeader, MessageTooLarge };

/// The body of the next message, in `a`; null at the end of input between
/// messages.
fn readMessage(r: *std.Io.Reader, a: Allocator) (FrameError || Allocator.Error || std.Io.Reader.Error)!?[]u8 {
    var length: ?usize = null;
    var headers = false;
    while (true) {
        const raw = r.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.BadHeader,
            error.ReadFailed => return error.ReadFailed,
        } orelse {
            if (headers) return error.EndOfStream;
            return null;
        };
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) {
            if (headers) break;
            continue;
        }
        headers = true;
        const colon = std.mem.findScalar(u8, line, ':') orelse return error.BadHeader;
        if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "Content-Length")) continue;
        length = std.fmt.parseInt(usize, std.mem.trim(u8, line[colon + 1 ..], " \t"), 10) catch return error.BadHeader;
    }
    const n = length orelse return error.BadHeader;
    if (n > max_message_bytes) return error.MessageTooLarge;
    return try r.readAllocAll(a, n);
}

fn writeMessage(w: *std.Io.Writer, body: []const u8) std.Io.Writer.Error!void {
    try w.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try w.writeAll(body);
    try w.flush();
}

// =============================================================================
// Positions
// =============================================================================

const Encoding = enum { utf16, utf8 };

const Position = struct { line: u32, character: u32 };
const Range = struct { start: Position, end: Position };

const bom = "\xEF\xBB\xBF";

/// The lines of a text: where each starts. A line ends at `\n`, `\r\n` or
/// a lone `\r`; a byte order mark is no part of the first line.
const Lines = struct {
    text: []const u8,
    starts: []const u32,
    encoding: Encoding,

    fn init(a: Allocator, text: []const u8, encoding: Encoding) Allocator.Error!Lines {
        var starts: std.ArrayList(u32) = .empty;
        try starts.append(a, if (std.mem.startsWith(u8, text, bom)) bom.len else 0);
        var i: usize = 0;
        while (i < text.len) : (i += 1) switch (text[i]) {
            '\n' => try starts.append(a, @intCast(i + 1)),
            '\r' => {
                if (i + 1 < text.len and text[i + 1] == '\n') i += 1;
                try starts.append(a, @intCast(i + 1));
            },
            else => {},
        };
        return .{ .text = text, .starts = starts.items, .encoding = encoding };
    }

    fn lineOf(self: Lines, at: u32) u32 {
        var lo: usize = 0;
        var hi: usize = self.starts.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (self.starts[mid] <= at) lo = mid else hi = mid;
        }
        return @intCast(lo);
    }

    /// The position of byte `byte`, clamped to the text; an offset inside
    /// a character is the position before it.
    fn position(self: Lines, byte: u32) Position {
        const at: u32 = @intCast(@min(byte, self.text.len));
        const line = self.lineOf(at);
        var i: usize = self.starts[line];
        var units: u32 = 0;
        while (i < at) {
            const c = self.text[i];
            if (c == '\n' or c == '\r') break;
            const n = sequenceLength(self.text[i..]);
            if (i + n > at) break;
            units += switch (self.encoding) {
                .utf8 => @intCast(n),
                .utf16 => if (n == 4) 2 else 1,
            };
            i += n;
        }
        return .{ .line = line, .character = units };
    }

    fn range(self: Lines, a: u32, b: u32) Range {
        return .{ .start = self.position(a), .end = self.position(@max(a, b)) };
    }

    /// The byte offset of a position, clamped to its line.
    fn offset(self: Lines, pos: Position) u32 {
        if (pos.line >= self.starts.len) return @intCast(self.text.len);
        const end = self.lineEnd(pos.line);
        var i: usize = self.starts[pos.line];
        var units: u32 = 0;
        while (i < end and units < pos.character) {
            const n = sequenceLength(self.text[i..]);
            units += switch (self.encoding) {
                .utf8 => @intCast(n),
                .utf16 => if (n == 4) 2 else 1,
            };
            i += n;
        }
        return @intCast(@min(i, end));
    }

    /// Where `line` ends, before its line ending.
    fn lineEnd(self: Lines, line: u32) u32 {
        if (line + 1 >= self.starts.len) return @intCast(self.text.len);
        var end = self.starts[line + 1];
        if (end > 0 and self.text[end - 1] == '\n') end -= 1;
        if (end > 0 and self.text[end - 1] == '\r') end -= 1;
        return @max(end, self.starts[line]);
    }
};

/// The bytes of the UTF-8 character `s` starts with; 1 for a byte that
/// starts none, or a sequence cut short.
fn sequenceLength(s: []const u8) usize {
    const n = std.unicode.utf8ByteSequenceLength(s[0]) catch return 1;
    if (n > s.len) return 1;
    for (s[1..n]) |c| if (c & 0xC0 != 0x80) return 1;
    return n;
}

// =============================================================================
// URIs
// =============================================================================

/// The path a `file:` URI names, percent-decoded; null for any other URI.
fn uriToPath(a: Allocator, uri: []const u8) Allocator.Error!?[]u8 {
    const scheme = "file://";
    if (!std.ascii.startsWithIgnoreCase(uri, scheme)) return null;
    var rest = uri[scheme.len..];
    const slash = std.mem.findScalar(u8, rest, '/') orelse return null;
    const host = rest[0..slash];
    if (host.len > 0 and !std.ascii.eqlIgnoreCase(host, "localhost")) return null;
    rest = rest[slash..];
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        if (rest[i] == '%' and i + 2 < rest.len) {
            if (std.fmt.parseInt(u8, rest[i + 1 .. i + 3], 16)) |byte| {
                try out.append(a, byte);
                i += 2;
                continue;
            } else |_| {}
        }
        try out.append(a, rest[i]);
    }
    return out.items;
}

/// The `file:` URI of an absolute path.
fn pathToUri(a: Allocator, path: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "file://");
    for (path) |c| {
        if (std.ascii.isAlphanumeric(c) or std.mem.findScalar(u8, "-._~/", c) != null) {
            try out.append(a, c);
        } else try out.print(a, "%{X:0>2}", .{c});
    }
    return out.items;
}

// =============================================================================
// The server
// =============================================================================

const Code = enum(i32) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    request_failed = -32803,
    server_not_initialized = -32002,
};

/// Serve until `exit` or the end of input. The status is 0 after
/// `shutdown` then `exit`, else 1; a leak in a safety-checked build is
/// reported on stderr and makes it 1.
pub fn run(io: std.Io) u8 {
    var sa: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    var status: u8 = 1;
    {
        var in_buffer: [64 * 1024]u8 = undefined;
        var in = std.Io.File.stdin().readerStreaming(io, &in_buffer);
        var out_buffer: [64 * 1024]u8 = undefined;
        var out = std.Io.File.stdout().writerStreaming(io, &out_buffer);
        var server: Server = .{ .gpa = sa.allocator(), .io = io, .out = &out.interface };
        defer server.deinit();
        status = server.serve(&in.interface);
    }
    const leaks = sa.deinit();
    if (leaks > 0) {
        std.debug.print("{s}-lsp: {d} allocation{s} leaked\n", .{ language.id, leaks, if (leaks == 1) "" else "s" });
        return 1;
    }
    return status;
}

/// An open document. `version` is a tick of the server's clock, new with
/// each text; `failed`: the error of the failed analysis its opening or
/// saving ran, until an analysis succeeds.
const Doc = struct {
    uri: []u8,
    path: []u8,
    text: []u8,
    version: u64,
    failed: ?[]const u8 = null,

    fn deinit(d: *Doc, gpa: Allocator) void {
        gpa.free(d.uri);
        gpa.free(d.path);
        gpa.free(d.text);
    }
};

/// The most analyses the server holds; making one more drops the one used
/// least recently.
const max_analyses = 8;

/// An analysis of one program, in an arena of its own: its root, what
/// `analyze` returned, the version of each open document it read, and the
/// ticks it was made and last used at.
const Held = struct {
    arena: std.heap.ArenaAllocator,
    root: []const u8,
    value: *Analysis,
    diagnostics: []const Diagnostic,
    files: []const []const u8,
    read: []const Read,
    made: u64,
    used: u64,

    const Read = struct { path: []const u8, version: u64 };

    /// Whether the analysis is of `path`'s program: its root, a file it
    /// read, or a file its diagnostics name.
    fn covers(h: *const Held, path: []const u8) bool {
        if (std.mem.eql(u8, h.root, path) or containsPath(h.files, path)) return true;
        for (h.diagnostics) |d| if (std.mem.eql(u8, d.span.path, path)) return true;
        return false;
    }

    /// The version of the open document `path` the analysis read.
    fn versionOf(h: *const Held, path: []const u8) ?u64 {
        for (h.read) |r| if (std.mem.eql(u8, r.path, path)) return r.version;
        return null;
    }
};

const Server = struct {
    gpa: Allocator,
    io: std.Io,
    out: *std.Io.Writer,
    encoding: Encoding = .utf16,
    initialized: bool = false,
    shut_down: bool = false,
    docs: std.ArrayList(Doc) = .empty,
    /// The program root (`initializationOptions.root`); without it, each
    /// file's program is that of the newest analysis that covers it, else
    /// the file's own.
    root: ?[]u8 = null,
    analyses: std.ArrayList(Held) = .empty,
    /// Counts up: document versions and analysis ticks.
    clock: u64 = 0,
    /// The hash of the diagnostics last sent to each URI, for the URIs
    /// whose last diagnostics were not empty.
    sent: std.array_hash_map.String(u64) = .empty,

    fn deinit(s: *Server) void {
        for (s.docs.items) |*d| d.deinit(s.gpa);
        s.docs.deinit(s.gpa);
        if (s.root) |r| s.gpa.free(r);
        for (s.analyses.items) |*h| h.arena.deinit();
        s.analyses.deinit(s.gpa);
        for (s.sent.keys()) |k| s.gpa.free(k);
        s.sent.deinit(s.gpa);
    }

    fn tick(s: *Server) u64 {
        s.clock += 1;
        return s.clock;
    }

    fn serve(s: *Server, in: *std.Io.Reader) u8 {
        var arena: std.heap.ArenaAllocator = .init(s.gpa);
        defer arena.deinit();
        while (true) {
            _ = arena.reset(.retain_capacity);
            const a = arena.allocator();
            const body = (readMessage(in, a) catch return 1) orelse return 1;
            const msg = std.json.parseFromSliceLeaky(Value, a, body, .{}) catch {
                s.respondError(a, .null, .parse_error, "the message is not JSON") catch return 1;
                continue;
            };
            if (msg != .object) continue;
            const method = str(msg.object.get("method")) orelse continue;
            const id = msg.object.get("id");
            const params = msg.object.get("params") orelse .null;
            if (std.mem.eql(u8, method, "exit")) return if (s.shut_down) 0 else 1;
            s.handle(a, method, id, params) catch |err| switch (err) {
                error.OutOfMemory, error.WriteFailed => return 1,
            };
        }
    }

    fn handle(s: *Server, a: Allocator, method: []const u8, id: ?Value, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const eql = std.mem.eql;
        if (eql(u8, method, "initialize")) {
            s.initialized = true;
            return s.respond(a, id orelse return, try s.initializeResult(a, params));
        }
        if (!s.initialized) {
            if (id) |i| try s.respondError(a, i, .server_not_initialized, "initialize first");
            return;
        }
        if (eql(u8, method, "shutdown")) {
            s.shut_down = true;
            return s.respond(a, id orelse return, null);
        }
        if (eql(u8, method, "textDocument/didOpen")) return s.didOpen(a, params);
        if (eql(u8, method, "textDocument/didChange")) return s.didChange(a, params);
        if (eql(u8, method, "textDocument/didSave")) return s.didSave(a, params);
        if (eql(u8, method, "textDocument/didClose")) return s.didClose(a, params);
        const i = id orelse return; // other notifications
        const doc = s.docOf(params) orelse return s.respondError(a, i, .invalid_params, "no open document");
        const result: Result = if (eql(u8, method, "textDocument/semanticTokens/full"))
            try s.semanticTokens(a, doc)
        else if (eql(u8, method, "textDocument/foldingRange"))
            try s.foldingRanges(a, doc)
        else if ((comptime has("symbols")) and eql(u8, method, "textDocument/documentSymbol"))
            try s.documentSymbols(a, doc)
        else if ((comptime parser.nodeStore) and eql(u8, method, "textDocument/selectionRange"))
            try s.selectionRanges(a, doc, params)
        else if (eql(u8, method, "textDocument/completion"))
            try s.completion(a, doc, params)
        else if ((comptime canHover()) and eql(u8, method, "textDocument/hover"))
            try s.hover(a, doc, params)
        else if ((comptime has("symbolAt")) and eql(u8, method, "textDocument/definition"))
            try s.definition(a, doc, params)
        else if ((comptime has("typeAt") and has("describe")) and eql(u8, method, "textDocument/typeDefinition"))
            try s.typeDefinition(a, doc, params)
        else if ((comptime has("symbolAt")) and eql(u8, method, "textDocument/references"))
            try s.references(a, doc, params, false)
        else if ((comptime has("symbolAt")) and eql(u8, method, "textDocument/documentHighlight"))
            try s.references(a, doc, params, true)
        else if ((comptime has("symbolAt")) and eql(u8, method, "textDocument/rename"))
            try s.rename(a, doc, params)
        else if ((comptime has("signatures")) and eql(u8, method, "textDocument/signatureHelp"))
            try s.signatureHelp(a, doc, params)
        else if ((comptime has("format")) and eql(u8, method, "textDocument/formatting"))
            try s.formatting(a, doc)
        else
            return s.respondError(a, i, .method_not_found, method);
        switch (result) {
            .json => |j| try s.respondRaw(a, i, j),
            .failed => |m| try s.respondError(a, i, .request_failed, m),
        }
    }

    /// A request's answer: its JSON, or why it could not be answered.
    const Result = union(enum) { json: []const u8, failed: []const u8 };

    fn canHover() bool {
        return has("describe") and (has("symbolAt") or has("typeAt"));
    }

    fn initializeResult(s: *Server, a: Allocator, params: Value) error{OutOfMemory}![]const u8 {
        if (field(params, &.{ "capabilities", "general", "positionEncodings" })) |encs| if (encs == .array) {
            for (encs.array.items) |e| if (str(e)) |name| if (std.mem.eql(u8, name, "utf-8")) {
                s.encoding = .utf8;
            };
        };
        if (str(field(params, &.{ "initializationOptions", "root" }))) |r| if (r.len > 0) {
            s.root = try s.gpa.dupe(u8, r);
        };
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        j.beginObject() catch return error.OutOfMemory;
        writeCapabilities(&j, s.encoding) catch return error.OutOfMemory;
        j.objectField("serverInfo") catch return error.OutOfMemory;
        j.write(.{ .name = language.id ++ "-lsp" }) catch return error.OutOfMemory;
        j.endObject() catch return error.OutOfMemory;
        return out.written();
    }

    fn writeCapabilities(j: *std.json.Stringify, encoding: Encoding) std.Io.Writer.Error!void {
        try j.objectField("capabilities");
        try j.beginObject();
        try j.objectField("positionEncoding");
        try j.write(if (encoding == .utf8) "utf-8" else "utf-16");
        try j.objectField("textDocumentSync");
        try j.write(.{ .openClose = true, .change = 1, .save = .{ .includeText = false } });
        try j.objectField("semanticTokensProvider");
        try j.write(.{ .legend = .{ .tokenTypes = legend, .tokenModifiers = [_][]const u8{} }, .full = true });
        // Without node spans or a folds function, the editor's own
        // indentation folding serves better than comment runs alone.
        if (parser.nodeStore or has("folds")) {
            try j.objectField("foldingRangeProvider");
            try j.write(true);
        }
        if (parser.nodeStore) {
            try j.objectField("selectionRangeProvider");
            try j.write(true);
        }
        if (has("symbols")) {
            try j.objectField("documentSymbolProvider");
            try j.write(true);
        }
        try j.objectField("completionProvider");
        try j.write(.{ .triggerCharacters = triggers });
        if (canHover()) {
            try j.objectField("hoverProvider");
            try j.write(true);
        }
        if (has("symbolAt")) {
            inline for (.{ "definitionProvider", "referencesProvider", "documentHighlightProvider", "renameProvider" }) |name| {
                try j.objectField(name);
                try j.write(true);
            }
        }
        if (has("typeAt") and has("describe")) {
            try j.objectField("typeDefinitionProvider");
            try j.write(true);
        }
        if (has("signatures")) {
            try j.objectField("signatureHelpProvider");
            try j.write(.{ .triggerCharacters = [_][]const u8{ "(", "," } });
        }
        if (has("format")) {
            try j.objectField("documentFormattingProvider");
            try j.write(true);
        }
        try j.endObject();
    }

    // --- Documents ------------------------------------------------------------

    fn docOf(s: *Server, params: Value) ?*Doc {
        const uri = str(field(params, &.{ "textDocument", "uri" })) orelse return null;
        for (s.docs.items) |*d| if (std.mem.eql(u8, d.uri, uri)) return d;
        return null;
    }

    fn didOpen(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const uri = str(field(params, &.{ "textDocument", "uri" })) orelse return;
        const text = str(field(params, &.{ "textDocument", "text" })) orelse return;
        if (s.docOf(params)) |d| {
            s.gpa.free(d.text);
            d.text = try s.gpa.dupe(u8, text);
            d.version = s.tick();
        } else {
            const path = try uriToPath(a, uri);
            try s.docs.append(s.gpa, .{
                .uri = try s.gpa.dupe(u8, uri),
                .path = try s.gpa.dupe(u8, path orelse ""),
                .text = try s.gpa.dupe(u8, text),
                .version = s.tick(),
            });
        }
        try s.analyzeAndPublish(a, s.docOf(params).?);
    }

    fn didChange(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const d = s.docOf(params) orelse return;
        const changes = field(params, &.{"contentChanges"}) orelse return;
        if (changes != .array or changes.array.items.len == 0) return;
        const text = str(field(changes.array.items[changes.array.items.len - 1], &.{"text"})) orelse return;
        s.gpa.free(d.text);
        d.text = try s.gpa.dupe(u8, text);
        d.version = s.tick();
        try s.publish(a, d);
    }

    fn didSave(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const d = s.docOf(params) orelse return;
        try s.analyzeAndPublish(a, d);
    }

    fn didClose(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const d = s.docOf(params) orelse return;
        try s.sendDiagnostics(a, d.uri, "[]");
        const i = (@intFromPtr(d) - @intFromPtr(s.docs.items.ptr)) / @sizeOf(Doc);
        d.deinit(s.gpa);
        _ = s.docs.orderedRemove(i);
    }

    // --- Analyses ------------------------------------------------------------

    /// The analysis of `path`'s program: the root's, when the client names
    /// one; else the newest that covers `path`.
    fn ownerOf(s: *Server, path: []const u8) ?*Held {
        var best: ?*Held = null;
        for (s.analyses.items) |*h| {
            if (s.root) |r| {
                if (std.mem.eql(u8, h.root, r)) return h;
                continue;
            }
            if (!h.covers(path)) continue;
            if (best == null or h.made > best.?.made) best = h;
        }
        return best;
    }

    /// The analysis a request on `d` reads, marked as used.
    fn analysisFor(s: *Server, d: *Doc) ?*Held {
        const h = s.ownerOf(d.path) orelse return null;
        h.used = s.tick();
        return h;
    }

    /// The root of `d`'s program.
    fn rootOf(s: *Server, d: *Doc) []const u8 {
        if (s.root) |r| return r;
        if (s.ownerOf(d.path)) |h| return h.root;
        return d.path;
    }

    // --- Diagnostics ------------------------------------------------------------

    /// Run `analyze` (when written) on the program of `d`, then publish
    /// every file's diagnostics that changed.
    fn analyzeAndPublish(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        if (comptime has("analyze")) if (d.path.len > 0) try s.analyzeProgram(a, d);
        try s.publishAll(a);
    }

    /// Hold what `analyze` makes of the program of `d`, in place of the
    /// last analysis of the same root. An analysis that fails keeps the
    /// last one, and says so: in the log, and in a diagnostic on `d` until
    /// an analysis succeeds.
    fn analyzeProgram(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        var paths: std.ArrayList([]const u8) = .empty;
        var texts: std.ArrayList([]const u8) = .empty;
        for (s.docs.items) |o| if (o.path.len > 0) {
            try paths.append(a, o.path);
            try texts.append(a, o.text);
        };
        // Everything the analysis keeps is in its arena: the analysis may
        // keep the root it is given, and the last analysis of this root,
        // which may hold the root now, is dropped below.
        var arena: std.heap.ArenaAllocator = .init(s.gpa);
        const ha = arena.allocator();
        const root = try ha.dupe(u8, s.rootOf(d));
        const got = hooks.analyze(ha, root, .{ .io = s.io, .paths = paths.items, .texts = texts.items }) catch |err| {
            const message = try std.fmt.allocPrint(a, "the analysis of {s} failed: {s}", .{ root, @errorName(err) });
            arena.deinit();
            d.failed = @errorName(err);
            try s.notify(a, "window/logMessage", .{ .type = 1, .message = message });
            return;
        };
        var read: std.ArrayList(Held.Read) = .empty;
        for (s.docs.items) |o| if (o.path.len > 0) try read.append(ha, .{ .path = try ha.dupe(u8, o.path), .version = o.version });
        const value = try ha.create(Analysis);
        value.* = got.analysis;
        const now = s.tick();
        const held: Held = .{
            .arena = arena,
            .root = root,
            .value = value,
            .diagnostics = got.diagnostics,
            .files = got.files,
            .read = read.items,
            .made = now,
            .used = now,
        };
        const slot = for (s.analyses.items) |*h| {
            if (std.mem.eql(u8, h.root, root)) {
                h.arena.deinit();
                break h;
            }
        } else if (s.analyses.items.len < max_analyses) try s.analyses.addOne(s.gpa) else lru: {
            var oldest = &s.analyses.items[0];
            for (s.analyses.items[1..]) |*h| if (h.used < oldest.used) {
                oldest = h;
            };
            oldest.arena.deinit();
            break :lru oldest;
        };
        slot.* = held;
        for (s.docs.items) |*o| if (o == d or slot.covers(o.path)) {
            o.failed = null;
        };
    }

    fn isOpen(s: *Server, path: []const u8) bool {
        for (s.docs.items) |d| if (std.mem.eql(u8, d.path, path)) return true;
        return false;
    }

    /// Publish what changed of every file's diagnostics: each open
    /// document's, each file's an analysis names, and an empty list for a
    /// file that had some and no longer has.
    fn publishAll(s: *Server, a: Allocator) error{ OutOfMemory, WriteFailed }!void {
        for (s.docs.items) |*d| try s.publish(a, d);
        var named: std.ArrayList([]const u8) = .empty;
        for (s.analyses.items) |h| for (h.diagnostics) |diag| {
            if (s.isOpen(diag.span.path) or containsPath(named.items, diag.span.path)) continue;
            try named.append(a, diag.span.path);
        };
        std.mem.sort([]const u8, named.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.order(u8, x, y) == .lt;
            }
        }.lt);
        var uris: std.ArrayList([]const u8) = .empty;
        for (named.items) |p| {
            const uri = try pathToUri(a, p);
            try uris.append(a, uri);
            try s.sendFileDiagnostics(a, p, null);
        }
        // What was sent to a file neither open nor named: clear it.
        var stale: std.ArrayList([]const u8) = .empty;
        for (s.sent.keys()) |uri| {
            if (containsPath(uris.items, uri)) continue;
            const open = for (s.docs.items) |d| {
                if (std.mem.eql(u8, d.uri, uri)) break true;
            } else false;
            if (!open) try stale.append(a, try a.dupe(u8, uri));
        }
        for (stale.items) |uri| try s.sendDiagnostics(a, uri, "[]");
    }

    /// Publish an open document's diagnostics: its parse errors, then its
    /// program's analysis's while it read this text.
    fn publish(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        const parsed = try parseDiagnostics(a, d.path, d.text);
        try s.sendFileDiagnostics(a, d.path, .{ .text = d.text, .parsed = parsed, .version = d.version, .failed = d.failed, .uri = d.uri });
    }

    const Open = struct { text: []const u8, parsed: []const Diagnostic, version: u64, failed: ?[]const u8, uri: []const u8 };

    fn sendFileDiagnostics(s: *Server, a: Allocator, path: []const u8, open: ?Open) error{ OutOfMemory, WriteFailed }!void {
        var list: std.ArrayList(Diagnostic) = .empty;
        if (open) |o| try list.appendSlice(a, o.parsed);
        if (open) |o| if (o.failed) |err| try list.append(a, .{
            .span = .{ .path = path, .start = 0, .end = 0 },
            .message = try std.fmt.allocPrint(a, "the analysis failed: {s}", .{err}),
        });
        if (s.ownerOf(path)) |h| if (open == null or h.versionOf(path) == open.?.version) {
            for (h.diagnostics) |d| if (std.mem.eql(u8, d.span.path, path)) try list.append(a, d);
        };
        const text = if (open) |o| o.text else try s.fileText(a, path);
        const lines = try Lines.init(a, text, s.encoding);
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        writeDiagnostics(s, a, &j, lines, list.items) catch return error.OutOfMemory;
        try s.sendDiagnostics(a, if (open) |o| o.uri else try pathToUri(a, path), out.written());
    }

    fn writeDiagnostics(s: *Server, a: Allocator, j: *std.json.Stringify, lines: Lines, list: []const Diagnostic) !void {
        try j.beginArray();
        for (list) |d| {
            try j.beginObject();
            try j.objectField("range");
            try j.write(lines.range(d.span.start, d.span.end));
            try j.objectField("severity");
            try j.write(@backingInt(d.severity));
            try j.objectField("source");
            try j.write(language.id);
            try j.objectField("message");
            try j.write(d.message);
            if (d.notes.len > 0) {
                try j.objectField("relatedInformation");
                try j.beginArray();
                for (d.notes) |n| {
                    const nlines = try Lines.init(a, try s.fileText(a, n.span.path), s.encoding);
                    try j.write(.{
                        .location = .{ .uri = try pathToUri(a, n.span.path), .range = nlines.range(n.span.start, n.span.end) },
                        .message = n.message,
                    });
                }
                try j.endArray();
            }
            try j.endObject();
        }
        try j.endArray();
    }

    fn notify(s: *Server, a: Allocator, method: []const u8, params: anytype) error{ OutOfMemory, WriteFailed }!void {
        const body = try std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .method = method, .params = params }, .{});
        try writeMessage(s.out, body);
    }

    /// Send a file's diagnostics, unless they are the ones last sent to it
    /// (no diagnostics, when none were sent).
    fn sendDiagnostics(s: *Server, a: Allocator, uri: []const u8, diagnostics: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const hash = std.hash.Wyhash.hash(0, diagnostics);
        const empty = std.mem.eql(u8, diagnostics, "[]");
        if (s.sent.getIndex(uri)) |i| {
            if (empty) {
                const key = s.sent.keys()[i];
                s.sent.swapRemoveAt(i);
                s.gpa.free(key);
            } else if (s.sent.values()[i] == hash) return else s.sent.values()[i] = hash;
        } else {
            if (empty) return;
            try s.sent.put(s.gpa, try s.gpa.dupe(u8, uri), hash);
        }
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        j.write(.{ .jsonrpc = "2.0", .method = "textDocument/publishDiagnostics" }) catch return error.OutOfMemory;
        // Splice the params in after the opening fields.
        const head = out.written();
        const body = try std.fmt.allocPrint(a, "{s},\"params\":{{\"uri\":{f},\"diagnostics\":{s}}}}}", .{ head[0 .. head.len - 1], std.json.fmt(uri, .{}), diagnostics });
        try writeMessage(s.out, body);
    }

    /// The text of a file: the open document's, else the file on disk
    /// (empty when it cannot be read).
    fn fileText(s: *Server, a: Allocator, path: []const u8) error{OutOfMemory}![]const u8 {
        for (s.docs.items) |d| if (std.mem.eql(u8, d.path, path)) return d.text;
        return std.Io.Dir.cwd().readFileAlloc(s.io, path, a, .limited(max_message_bytes)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => "",
        };
    }

    // --- Responses ------------------------------------------------------------

    fn respond(s: *Server, a: Allocator, id: Value, result: anytype) error{ OutOfMemory, WriteFailed }!void {
        const T = @TypeOf(result);
        if (T == []const u8 or T == []u8) return s.respondRaw(a, id, result);
        const body = try std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .result = result }, .{});
        try writeMessage(s.out, body);
    }

    fn respondRaw(s: *Server, a: Allocator, id: Value, result: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{s}}}", .{ std.json.fmt(id, .{}), result });
        try writeMessage(s.out, body);
    }

    fn respondError(s: *Server, a: Allocator, id: Value, code: Code, message: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const body = try std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .@"error" = .{ .code = @backingInt(code), .message = message } }, .{});
        try writeMessage(s.out, body);
    }

    fn json(a: Allocator, v: anytype) error{OutOfMemory}!Result {
        return .{ .json = try std.json.Stringify.valueAlloc(a, v, .{ .emit_null_optional_fields = false }) };
    }

    // --- From the grammar ------------------------------------------------------------

    fn semanticTokens(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}!Result {
        const toks: []const Token = if (comptime has("tokens"))
            hooks.tokens(a, d.path, d.text) catch return .{ .failed = "tokens failed" }
        else
            try grammarTokens(a, d.text);
        const lines = try Lines.init(a, d.text, s.encoding);
        var data: std.ArrayList(u32) = .empty;
        var prev: Position = .{ .line = 0, .character = 0 };
        for (toks) |t| {
            // A token over several lines is one token per line.
            var at = t.start;
            const end = @min(t.start + t.len, @as(u32, @intCast(d.text.len)));
            while (at < end) {
                const p = lines.position(at);
                const stop = @min(end, lines.lineEnd(p.line));
                const len = lines.position(stop).character -| p.character;
                if (len > 0) {
                    try data.appendSlice(a, &.{ p.line - prev.line, if (p.line == prev.line) p.character - prev.character else p.character, len, @backingInt(t.scope), 0 });
                    prev = p;
                }
                if (p.line + 1 >= lines.starts.len) break;
                at = @max(stop + 1, lines.starts[p.line + 1]);
            }
        }
        return json(a, .{ .data = data.items });
    }

    fn foldingRanges(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}!Result {
        const folds: []const Fold = if (comptime has("folds"))
            hooks.folds(a, d.path, d.text) catch return .{ .failed = "folds failed" }
        else
            try grammarFolds(a, d.text);
        const lines = try Lines.init(a, d.text, s.encoding);
        const FR = struct { startLine: u32, endLine: u32, kind: ?[]const u8 = null };
        var out: std.ArrayList(FR) = .empty;
        for (folds) |f| {
            const first = lines.lineOf(f.start);
            const last = lines.lineOf(f.end -| 1);
            if (last > first) try out.append(a, .{ .startLine = first, .endLine = last, .kind = if (f.comment) "comment" else null });
        }
        // One fold a line: the longest that starts there.
        std.mem.sort(FR, out.items, {}, struct {
            fn lt(_: void, x: FR, y: FR) bool {
                return x.startLine < y.startLine or (x.startLine == y.startLine and x.endLine > y.endLine);
            }
        }.lt);
        var kept: usize = 0;
        for (out.items) |f| {
            if (kept > 0 and out.items[kept - 1].startLine == f.startLine) continue;
            out.items[kept] = f;
            kept += 1;
        }
        return json(a, out.items[0..kept]);
    }

    fn documentSymbols(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}!Result {
        if (comptime !has("symbols")) unreachable;
        const items = hooks.symbols(a, d.path, d.text) catch return .{ .failed = "symbols failed" };
        const lines = try Lines.init(a, d.text, s.encoding);
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        writeOutline(&j, lines, items) catch return error.OutOfMemory;
        return .{ .json = out.written() };
    }

    fn writeOutline(j: *std.json.Stringify, lines: Lines, items: []const OutlineItem) std.Io.Writer.Error!void {
        try j.beginArray();
        for (items) |it| {
            try j.beginObject();
            try j.objectField("name");
            try j.write(it.name);
            if (it.detail.len > 0) {
                try j.objectField("detail");
                try j.write(it.detail);
            }
            try j.objectField("kind");
            try j.write(@backingInt(it.kind));
            try j.objectField("range");
            try j.write(lines.range(it.start, it.end));
            try j.objectField("selectionRange");
            try j.write(lines.range(it.name_start, it.name_end));
            if (it.children.len > 0) {
                try j.objectField("children");
                try writeOutline(j, lines, it.children);
            }
            try j.endObject();
        }
        try j.endArray();
    }

    fn selectionRanges(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const lines = try Lines.init(a, d.text, s.encoding);
        const tree = try parseTree(a, d.text);
        const solid = try Solid.init(a, d.text);
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        const positions = field(params, &.{"positions"}) orelse return .{ .failed = "no positions" };
        if (positions != .array) return .{ .failed = "no positions" };
        j.beginArray() catch return error.OutOfMemory;
        for (positions.array.items) |pv| {
            const at = lines.offset(position(pv) orelse continue);
            // The spans around `at`, outermost first, each from its first
            // solid token to its last and inside the one before it, then
            // the token at `at`: the one it is in, else the one it ends.
            var found: std.ArrayList(parser.Span) = .empty;
            if (tree) |t| for (t.roots) |root| try spansAround(a, t.base, root, at, &found);
            for (solid.tokensAt(at)) |tok| if (tok) |t| try found.append(a, .{ .start = t.pos, .end = t.pos + t.len });
            var chain: std.ArrayList(parser.Span) = .empty;
            for (found.items) |span| {
                const trimmed = solid.trim(span);
                if (at < trimmed.start or at > trimmed.end) continue;
                if (chain.items.len > 0) {
                    const outer = chain.getLast();
                    if (std.meta.eql(outer, trimmed) or trimmed.start < outer.start or trimmed.end > outer.end) continue;
                }
                try chain.append(a, trimmed);
            }
            var depth: usize = 0;
            var i = chain.items.len;
            if (i == 0) {
                j.write(.{ .range = lines.range(at, at) }) catch return error.OutOfMemory;
                continue;
            }
            while (i > 0) : (depth += 1) {
                i -= 1;
                j.beginObject() catch return error.OutOfMemory;
                j.objectField("range") catch return error.OutOfMemory;
                j.write(lines.range(chain.items[i].start, chain.items[i].end)) catch return error.OutOfMemory;
                if (i > 0) j.objectField("parent") catch return error.OutOfMemory;
            }
            for (0..depth) |_| j.endObject() catch return error.OutOfMemory;
        }
        j.endArray() catch return error.OutOfMemory;
        return .{ .json = out.written() };
    }

    fn completion(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const lines = try Lines.init(a, d.text, s.encoding);
        const at = lines.offset(position(field(params, &.{"position"})) orelse return .{ .failed = "no position" });
        const Item = struct { label: []const u8, kind: u8, detail: ?[]const u8 = null, documentation: ?struct { kind: []const u8 = "markdown", value: []const u8 } = null };
        var items: std.ArrayList(Item) = .empty;
        const pos: Pos = .{ .path = d.path, .offset = at };
        if (comptime has("members")) if (s.analysis(d)) |an| {
            if (hooks.members(an, a, pos) catch null) |members| {
                for (members) |m| try items.append(a, .{ .label = m.name, .kind = completionKind(m.kind), .detail = nonEmpty(m.detail), .documentation = if (m.doc.len > 0) .{ .value = m.doc } else null });
                return json(a, .{ .isIncomplete = false, .items = items.items });
            }
        };
        if (comptime has("modules")) if (s.analysis(d)) |an| {
            if (hooks.modules(an, a, pos) catch null) |names| {
                for (names) |n| try items.append(a, .{ .label = n, .kind = 9 });
                return json(a, .{ .isIncomplete = false, .items = items.items });
            }
        };
        if (comptime has("visible")) if (s.analysis(d)) |an| {
            const symbols = hooks.visible(an, a, pos) catch &.{};
            for (symbols) |m| try items.append(a, .{ .label = m.name, .kind = completionKind(m.kind), .detail = nonEmpty(m.detail), .documentation = if (m.doc.len > 0) .{ .value = m.doc } else null });
        };
        for (try keywordsAt(a, d.text, at)) |k| {
            const seen = for (items.items) |it| {
                if (std.mem.eql(u8, it.label, k)) break true;
            } else false;
            if (!seen) try items.append(a, .{ .label = k, .kind = 14 });
        }
        return json(a, .{ .isIncomplete = false, .items = items.items });
    }

    // --- From the language's functions ------------------------------------------------------------

    /// The analysis of `d`'s program.
    fn analysis(s: *Server, d: *Doc) ?*Analysis {
        const h = s.analysisFor(d) orelse return null;
        return h.value;
    }

    fn posOf(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!?Pos {
        const lines = try Lines.init(a, d.text, s.encoding);
        const p = position(field(params, &.{"position"})) orelse return null;
        return .{ .path = d.path, .offset = lines.offset(p) };
    }

    fn location(s: *Server, a: Allocator, span: Span) error{OutOfMemory}!struct { uri: []const u8, range: Range } {
        const lines = try Lines.init(a, try s.fileText(a, span.path), s.encoding);
        return .{ .uri = try pathToUri(a, span.path), .range = lines.range(span.start, span.end) };
    }

    fn hover(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        var desc: ?Description = null;
        if (comptime has("symbolAt") and has("describe")) {
            if (hooks.symbolAt(an, a, pos) catch null) |sym| desc = hooks.describe(an, a, .{ .symbol = sym }) catch null;
        }
        if (comptime has("typeAt") and has("describe")) if (desc == null) {
            if (hooks.typeAt(an, a, pos) catch null) |t| desc = hooks.describe(an, a, .{ .type = t }) catch null;
        };
        const got = desc orelse return json(a, null);
        return json(a, .{ .contents = .{ .kind = "markdown", .value = got.markdown } });
    }

    fn definition(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !has("symbolAt")) unreachable;
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return json(a, null);
        return json(a, try s.location(a, sym.decl));
    }

    fn typeDefinition(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !(has("typeAt") and has("describe"))) unreachable;
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const t = (hooks.typeAt(an, a, pos) catch null) orelse return json(a, null);
        const desc = (hooks.describe(an, a, .{ .type = t }) catch null) orelse return json(a, null);
        const decl = desc.decl orelse return json(a, null);
        return json(a, try s.location(a, decl));
    }

    /// Every span that uses `sym`: the language's `references`, else every
    /// token whose `symbolAt` is `sym` of every file the analysis of `d`'s
    /// program read and every open document of that program.
    fn uses(s: *Server, a: Allocator, d: *Doc, an: *Analysis, sym: Symbol) error{OutOfMemory}![]const Span {
        if (comptime has("references")) return hooks.references(an, a, sym) catch &.{};
        if (comptime !has("symbolAt")) unreachable;
        var out: std.ArrayList(Span) = .empty;
        var files: std.ArrayList([]const u8) = .empty;
        const owner = s.ownerOf(d.path);
        if (owner) |h| try files.appendSlice(a, h.files);
        for (s.docs.items) |o| if (o.path.len > 0 and s.ownerOf(o.path) == owner and !containsPath(files.items, o.path)) try files.append(a, o.path);
        for (files.items) |path| {
            const text = try s.fileText(a, path);
            var lexer = parser.Lexer.init(text);
            while (true) {
                const t = lexer.next();
                if (t.cat == .eof) break;
                const found = (hooks.symbolAt(an, a, .{ .path = path, .offset = t.pos }) catch null) orelse continue;
                if (std.mem.eql(u8, found.id, sym.id)) try out.append(a, .{ .path = path, .start = t.pos, .end = t.pos + t.len });
            }
        }
        return out.items;
    }

    fn references(s: *Server, a: Allocator, d: *Doc, params: Value, here: bool) error{OutOfMemory}!Result {
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return json(a, null);
        const spans = try s.uses(a, d, an, sym);
        const withDecl = if (field(params, &.{ "context", "includeDeclaration" })) |v| v == .bool and v.bool else here;
        if (here) {
            const lines = try Lines.init(a, d.text, s.encoding);
            const H = struct { range: Range };
            var out: std.ArrayList(H) = .empty;
            for (spans) |sp| if (std.mem.eql(u8, sp.path, d.path)) try out.append(a, .{ .range = lines.range(sp.start, sp.end) });
            return json(a, out.items);
        }
        const L = struct { uri: []const u8, range: Range };
        var out: std.ArrayList(L) = .empty;
        for (spans) |sp| {
            const isDecl = std.mem.eql(u8, sp.path, sym.decl.path) and sp.start == sym.decl.start;
            if (isDecl and !withDecl) continue;
            const loc = try s.location(a, sp);
            try out.append(a, .{ .uri = loc.uri, .range = loc.range });
        }
        return json(a, out.items);
    }

    fn rename(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const an = s.analysis(d) orelse return .{ .failed = "no analysis yet: save the file" };
        const pos = try s.posOf(a, d, params) orelse return .{ .failed = "no position" };
        const name = str(field(params, &.{"newName"})) orelse return .{ .failed = "no new name" };
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return .{ .failed = "nothing to rename here" };
        if (comptime has("renamable")) if (!hooks.renamable(an, sym)) return .{ .failed = "this name cannot be renamed" };
        // The new name must lex as one token of the old name's category.
        const declText = try s.fileText(a, sym.decl.path);
        const old = oneToken(declText[@min(sym.decl.start, declText.len)..@min(sym.decl.end, declText.len)]) orelse return .{ .failed = "the declaration is not one token" };
        const new = oneToken(name) orelse return .{ .failed = "the new name is not one token" };
        if (new != old) return .{ .failed = "the new name is not a name of the same kind" };
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        const spans = try s.uses(a, d, an, sym);
        var files: std.ArrayList([]const u8) = .empty;
        for (spans) |sp| if (!containsPath(files.items, sp.path)) try files.append(a, sp.path);
        if (!containsSpan(spans, sym.decl)) if (!containsPath(files.items, sym.decl.path)) try files.append(a, sym.decl.path);
        j.beginObject() catch return error.OutOfMemory;
        j.objectField("changes") catch return error.OutOfMemory;
        j.beginObject() catch return error.OutOfMemory;
        for (files.items) |path| {
            const lines = try Lines.init(a, try s.fileText(a, path), s.encoding);
            j.objectField(try pathToUri(a, path)) catch return error.OutOfMemory;
            j.beginArray() catch return error.OutOfMemory;
            for (spans) |sp| if (std.mem.eql(u8, sp.path, path)) {
                j.write(.{ .range = lines.range(sp.start, sp.end), .newText = name }) catch return error.OutOfMemory;
            };
            if (std.mem.eql(u8, sym.decl.path, path) and !containsSpan(spans, sym.decl))
                j.write(.{ .range = lines.range(sym.decl.start, sym.decl.end), .newText = name }) catch return error.OutOfMemory;
            j.endArray() catch return error.OutOfMemory;
        }
        j.endObject() catch return error.OutOfMemory;
        j.endObject() catch return error.OutOfMemory;
        return .{ .json = out.written() };
    }

    fn signatureHelp(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !has("signatures")) unreachable;
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const help = (hooks.signatures(an, a, pos) catch null) orelse return json(a, null);
        const P = struct { label: []const u8, documentation: ?[]const u8 = null };
        const S = struct { label: []const u8, documentation: ?[]const u8 = null, parameters: []const P };
        var sigs: std.ArrayList(S) = .empty;
        for (help.signatures) |sig| {
            var ps: std.ArrayList(P) = .empty;
            for (sig.params) |p| try ps.append(a, .{
                .label = if (p.type.len > 0) try std.fmt.allocPrint(a, "{s}: {s}", .{ p.name, p.type }) else p.name,
                .documentation = nonEmpty(p.doc),
            });
            try sigs.append(a, .{ .label = sig.label, .documentation = nonEmpty(sig.doc), .parameters = ps.items });
        }
        return json(a, .{ .signatures = sigs.items, .activeSignature = help.active, .activeParameter = help.param });
    }

    fn formatting(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}!Result {
        if (comptime !has("format")) unreachable;
        const text = (hooks.format(a, d.path, d.text) catch return .{ .failed = "format failed" }) orelse return json(a, null);
        const lines = try Lines.init(a, d.text, s.encoding);
        return json(a, [_]struct { range: Range, newText: []const u8 }{.{ .range = lines.range(0, @intCast(d.text.len)), .newText = text }});
    }
};

// =============================================================================
// The grammar's answers
// =============================================================================

/// The parse diagnostics of a text: the language's `parseDiagnostics`, else
/// the strict parse's error.
fn parseDiagnostics(a: Allocator, path: []const u8, text: []const u8) error{OutOfMemory}![]const Diagnostic {
    if (comptime has("parseDiagnostics")) return hooks.parseDiagnostics(a, path, text) catch &.{};
    var p = BaseParser.init(a, text);
    _ = p.parse(start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const f = p.lastError() orelse return &.{};
            var out: std.Io.Writer.Allocating = .init(a);
            p.writeError(&out.writer) catch return error.OutOfMemory;
            // `line:col: message`: the position is the diagnostic's range.
            var message = out.written();
            if (std.mem.findScalar(u8, message, ' ')) |sp| if (sp > 0 and message[sp - 1] == ':') {
                message = message[sp + 1 ..];
            };
            const list = try a.alloc(Diagnostic, 1);
            list[0] = .{ .span = .{ .path = path, .start = f.span.start, .end = f.span.end }, .message = message };
            return list;
        },
    };
    return &.{};
}

/// A tree of the text, through the tolerant parse when the grammar has
/// `@repair`: the root, or the pieces an incomplete parse built.
const Tree = struct { base: *BaseParser, roots: []const parser.Sexp, whole: bool = true };

fn parseTree(a: Allocator, text: []const u8) error{OutOfMemory}!?Tree {
    const p = try a.create(BaseParser);
    p.* = BaseParser.init(a, text);
    if (parser.hasRepair) {
        const r = p.parseTolerant(start, 64) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        if (r.sexp != .nil) return .{ .base = p, .roots = try a.dupe(parser.Sexp, &.{r.sexp}) };
        return .{ .base = p, .roots = r.pieces, .whole = false };
    }
    const root = p.parse(start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    return .{ .base = p, .roots = try a.dupe(parser.Sexp, &.{root}) };
}

/// The spans of the nodes around `at`, outermost first.
fn spansAround(a: Allocator, p: *BaseParser, s: parser.Sexp, at: u32, out: *std.ArrayList(parser.Span)) error{OutOfMemory}!void {
    if (s != .list) return;
    const span = p.span(s);
    if (at < span.start or at > span.end) return;
    if (out.items.len == 0 or !std.meta.eql(out.getLast(), span)) try out.append(a, span);
    for (s.items()) |child| try spansAround(a, p, child, at, out);
}

/// The solid tokens of a text: each token with text other than blanks and
/// line ends that is not a comment. A node's span runs on to the next
/// token, so it takes in the blank lines, comments and zero-width layout
/// tokens after it; its folds and selection ranges end at its last solid
/// token.
const Solid = struct {
    toks: []const parser.Token,

    fn init(a: Allocator, text: []const u8) error{OutOfMemory}!Solid {
        var out: std.ArrayList(parser.Token) = .empty;
        var lexer = parser.Lexer.init(text);
        while (true) {
            const t = lexer.next();
            if (t.cat == .eof) break;
            if (t.len == 0 or language.tokenScope(t.cat) == .comment) continue;
            if (std.mem.trim(u8, text[t.pos..][0..t.len], " \t\r\n").len == 0) continue;
            try out.append(a, t);
        }
        return .{ .toks = out.items };
    }

    /// `span` from its first solid token to its last; unchanged without one.
    fn trim(self: Solid, span: parser.Span) parser.Span {
        const toks = self.toks;
        // The first token at or after the start.
        var lo: usize = 0;
        var hi: usize = toks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (toks[mid].pos < span.start) lo = mid + 1 else hi = mid;
        }
        const first = lo;
        // The first token from there that ends past the end.
        hi = toks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (toks[mid].pos + toks[mid].len <= span.end) lo = mid + 1 else hi = mid;
        }
        if (lo == first) return span;
        return .{ .start = toks[first].pos, .end = toks[lo - 1].pos + toks[lo - 1].len };
    }

    /// The solid token `at` is in and the one that ends at `at`, either
    /// null when there is none.
    fn tokensAt(self: Solid, at: u32) [2]?parser.Token {
        const toks = self.toks;
        // The first token that starts after `at`.
        var lo: usize = 0;
        var hi: usize = toks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (toks[mid].pos <= at) lo = mid + 1 else hi = mid;
        }
        var out: [2]?parser.Token = .{ null, null };
        if (lo > 0 and at < toks[lo - 1].pos + toks[lo - 1].len) out[0] = toks[lo - 1];
        // The token before: it ends at `at` when `at` starts the token
        // after it, or follows it.
        const before = if (out[0] != null) lo -| 2 else lo -| 1;
        if (lo > 0 and before < toks.len and toks[before].pos + toks[before].len == at and toks[before].pos < at) out[1] = toks[before];
        return out;
    }
};

/// The semantic tokens the grammar gives: each token's `@highlight` scope.
fn grammarTokens(a: Allocator, text: []const u8) error{OutOfMemory}![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var lexer = parser.Lexer.init(text);
    while (true) {
        const t = lexer.next();
        if (t.cat == .eof) break;
        const scope = language.wordScope(text[t.pos..][0..t.len]) orelse language.tokenScope(t.cat) orelse continue;
        try out.append(a, .{ .start = t.pos, .len = t.len, .scope = scope });
    }
    return out.items;
}

/// The folds the grammar gives: every node whose solid tokens span several
/// lines, and every run of comment lines.
fn grammarFolds(a: Allocator, text: []const u8) error{OutOfMemory}![]const Fold {
    var out: std.ArrayList(Fold) = .empty;
    if (parser.nodeStore) if (try parseTree(a, text)) |t| {
        // The nodes under a whole tree's root, which is all of the text;
        // the pieces of an incomplete one.
        const solid = try Solid.init(a, text);
        const nodes = if (t.whole) t.roots[0].items() else t.roots;
        for (nodes) |node| try nodeFolds(a, t.base, solid, node, &out);
    };
    // Runs of comment tokens on consecutive lines.
    var lexer = parser.Lexer.init(text);
    var comments: ?Fold = null;
    var lastLineEnd: u32 = 0;
    while (true) {
        const t = lexer.next();
        if (t.cat == .eof) break;
        const isComment = language.tokenScope(t.cat) == .comment;
        if (!isComment) {
            if (comments) |r| try out.append(a, r);
            comments = null;
            continue;
        }
        const between = text[@min(lastLineEnd, t.pos)..t.pos];
        const adjacent = comments != null and std.mem.count(u8, between, "\n") <= 1;
        if (adjacent) comments.?.end = t.pos + t.len else {
            if (comments) |r| try out.append(a, r);
            comments = .{ .start = t.pos, .end = t.pos + t.len, .comment = true };
        }
        lastLineEnd = t.pos + t.len;
    }
    if (comments) |r| try out.append(a, r);
    return out.items;
}

fn nodeFolds(a: Allocator, p: *BaseParser, solid: Solid, s: parser.Sexp, out: *std.ArrayList(Fold)) error{OutOfMemory}!void {
    if (s != .list) return;
    const span = solid.trim(p.span(s));
    if (std.mem.findScalar(u8, p.source[span.start..span.end], '\n') != null) try out.append(a, .{ .start = span.start, .end = span.end });
    for (s.items()) |child| try nodeFolds(a, p, solid, child, out);
}

/// The words of `language.words` the grammar takes at `at`, in place of the
/// word the position is in: each word the parse reads past when it follows
/// the text before that word. None when that text has an error of its own.
fn keywordsAt(a: Allocator, text: []const u8, at: u32) error{OutOfMemory}![]const []const u8 {
    var begin: usize = @min(at, text.len);
    while (begin > 0 and language.isWord(text[begin - 1])) begin -= 1;
    if (!try parsesTo(a, text[0..begin], begin)) return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    var trial: std.ArrayList(u8) = .empty;
    try trial.appendSlice(a, text[0..begin]);
    for (language.words) |word| {
        trial.items.len = begin;
        try trial.appendSlice(a, word);
        if (try parsesTo(a, trial.items, begin + word.len)) try out.append(a, word);
    }
    return out.items;
}

/// Whether the parse of `text` succeeds or fails no earlier than `end`.
fn parsesTo(a: Allocator, text: []const u8, end: usize) error{OutOfMemory}!bool {
    var p = BaseParser.init(a, text);
    _ = p.parse(start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return if (p.lastError()) |f| f.span.start >= end else false,
    };
    return true;
}

/// The category of the one token `text` is; null when it is not one token.
fn oneToken(text: []const u8) ?parser.TokenCat {
    var lexer = parser.Lexer.init(text);
    const t = lexer.next();
    if (t.cat == .eof or t.pos != 0 or t.len != text.len) return null;
    if (lexer.next().cat != .eof) return null;
    return t.cat;
}

// =============================================================================
// JSON helpers
// =============================================================================

fn field(v: ?Value, path: []const []const u8) ?Value {
    var cur = v orelse return null;
    for (path) |name| {
        if (cur != .object) return null;
        cur = cur.object.get(name) orelse return null;
    }
    return cur;
}

fn str(v: ?Value) ?[]const u8 {
    const x = v orelse return null;
    return if (x == .string) x.string else null;
}

fn int(v: ?Value) ?u32 {
    const x = v orelse return null;
    return if (x == .integer and x.integer >= 0) std.math.cast(u32, x.integer) else null;
}

fn position(v: ?Value) ?Position {
    return .{ .line = int(field(v, &.{"line"})) orelse return null, .character = int(field(v, &.{"character"})) orelse return null };
}

fn nonEmpty(s: []const u8) ?[]const u8 {
    return if (s.len > 0) s else null;
}

fn containsPath(paths: []const []const u8, path: []const u8) bool {
    for (paths) |p| if (std.mem.eql(u8, p, path)) return true;
    return false;
}

fn containsSpan(spans: []const Span, span: Span) bool {
    for (spans) |sp| if (sp.start == span.start and std.mem.eql(u8, sp.path, span.path)) return true;
    return false;
}

/// LSP's completion item kind for a symbol kind.
fn completionKind(k: SymbolKind) u8 {
    return switch (k) {
        .method => 2,
        .function => 3,
        .constructor => 4,
        .field => 5,
        .variable => 6,
        .class => 7,
        .interface => 8,
        .module, .namespace, .package => 9,
        .property => 10,
        .@"enum" => 13,
        .enum_member => 20,
        .constant => 21,
        .@"struct" => 22,
        .event => 23,
        .operator => 24,
        .type_parameter => 25,
        .file => 17,
        else => 1,
    };
}
