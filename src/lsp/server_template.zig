//! lsp.zig: a language server (LSP 3.17) on standard input and output for
//! the language of one grammar file, written by `nexus --editor` beside
//! the grammar's parser (`parser.zig`), its table (`language.zig`) and the
//! language's functions (`hooks.zig`, docs/LSP.md).
//!
//! From the grammar alone it gives syntax errors as you type, semantic
//! tokens, folding, selection ranges and keyword completion; with `@lsp`,
//! also the outline, definition, references, highlights, rename, the names
//! in scope and after `.`, and hover, across the files of the workspace,
//! from the names, scopes, imports and members the grammar declares
//! (scopes.zig). Every other feature waits behind a function of
//! `hooks.zig`, and a function left as `lsp.todo` is never called: its
//! features are not advertised. A function the language writes replaces
//! the grammar's answers (`parseDiagnostics`, `tokens`, `symbols`, `folds`,
//! and with `@lsp` `symbolAt`, `describe`, `visible` and `members`).
//!
//! The client may name the features it wants (`features`), and a command
//! that checks the program on open and save (`check`), whose
//! `PATH:LINE:COL: error: MESSAGE` lines are diagnostics too.
//!
//! Messages are JSON-RPC, each after a `Content-Length` header. Positions
//! count UTF-16 code units, or bytes when the client offers `utf-8`.

const std = @import("std");
const builtin = @import("builtin");
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

/// The semantic token types the server declares (`legend`): the scopes of
/// `@highlight`, then LSP's types that no scope stands for, which only
/// `@lsp`'s `color` lines give.
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
    namespace,
    class,
    @"enum",
    interface,
    @"struct",
    type_parameter,
    variable,
    property,
    enum_member,
    event,
    method,
    macro,
    regexp,
    decorator,
};

/// The semantic token types, one per `Scope`: the scopes', then LSP's.
pub const legend = scope_legend ++ type_legend;

/// The token types of `@highlight`'s scopes, as `package.json` declares
/// them.
pub const scope_legend = [_][]const u8{
    "keyword",         "keywordControl",    "keywordOperator", "constant",        "constantNumeric",
    "constantSymbol",  "string",            "stringEscape",    "comment",         "operator",
    "punctuation",     "type",              "function",        "functionBuiltin", "label",
    "storageModifier", "variableParameter", "variableSpecial", "invalid",
};

/// LSP's token types that no scope stands for, as LSP names them. VS Code
/// knows each, so `package.json` declares none and gives none a scope.
pub const type_legend = [_][]const u8{
    "namespace", "class",      "enum",  "interface", "struct", "typeParameter", "variable",
    "property",  "enumMember", "event", "method",    "macro",  "regexp",        "decorator",
};

// Each type of the legend is its `Scope` in camel case.
comptime {
    const types = std.enums.values(Scope);
    if (legend.len != types.len) @compileError("the legend and Scope differ in length");
    for (types, legend) |s, name| {
        var camel: []const u8 = "";
        var upper = false;
        for (@tagName(s)) |c| {
            if (c == '_') {
                upper = true;
                continue;
            }
            camel = camel ++ .{if (upper) std.ascii.toUpper(c) else c};
            upper = false;
        }
        if (!std.mem.eql(u8, camel, name)) @compileError("the legend's " ++ name ++ " is not Scope's " ++ @tagName(s));
    }
}

/// LSP's semantic token modifiers, as the server declares them
/// (`modifier_legend`, in order).
pub const Modifiers = packed struct(u32) {
    declaration: bool = false,
    definition: bool = false,
    readonly: bool = false,
    static: bool = false,
    deprecated: bool = false,
    abstract: bool = false,
    async: bool = false,
    modification: bool = false,
    documentation: bool = false,
    default_library: bool = false,
    _: u22 = 0,
};

/// The semantic token modifiers, one per field of `Modifiers`, as LSP
/// names them.
pub const modifier_legend = [_][]const u8{
    "declaration", "definition", "readonly",     "static",        "deprecated",
    "abstract",    "async",      "modification", "documentation", "defaultLibrary",
};

/// A semantic token: a byte range of the file, its scope and its
/// modifiers.
pub const Token = struct { start: u32, len: u32, scope: Scope, modifiers: Modifiers = .{} };

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

/// What the server logs of an import whose name names no file
/// (`unresolvedImport`): its line, its line and a sentence after it, or
/// nothing, for a name that needs no file.
pub const Unresolved = union(enum) { plain, hint: []const u8, quiet };

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
    if (has("tokens") and @typeInfo(@TypeOf(hooks.tokens)).@"fn".param_types.len != 4)
        @compileError("hooks.tokens adjusts the grammar's tokens: pub fn tokens(arena: std.mem.Allocator, path: []const u8, text: []const u8, grammar: []const lsp.Token) ![]const lsp.Token");
}

/// Whether the grammar declares its names and scopes (`@lsp`), which
/// scopes.zig indexes each open file by.
const has_names = @hasDecl(language, "names");
const scopes = if (has_names) language.scopes else struct {};
const NameIndex = if (has_names) scopes.Index else void;

/// Whether the grammar's names answer for the language's function `name`:
/// with `@lsp`, until the language writes it. `symbolAt` stands for
/// definition, references, document highlight and rename; `symbols` for
/// the outline; `describe` for hover; `visible` for the names completion
/// offers; `members` for those it offers after `.`.
fn byNames(comptime name: []const u8) bool {
    return has_names and !has(name);
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
///
/// One task reads the messages, the worker runs `analyze` and the checker
/// runs the check command; each hands what it has to the main loop through
/// one queue, and the main loop alone keeps the server's state and writes.
/// Where tasks cannot run concurrently, the main loop reads, and analyses
/// and checks run as they are asked for.
pub fn run(io: std.Io) u8 {
    var sa: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    var status: u8 = 1;
    {
        var in_buffer: [64 * 1024]u8 = undefined;
        var in = std.Io.File.stdin().readerStreaming(io, &in_buffer);
        var out_buffer: [64 * 1024]u8 = undefined;
        var out = std.Io.File.stdout().writerStreaming(io, &out_buffer);
        var events: [64]Event = undefined;
        var queue: std.Io.Queue(Event) = .init(&events);
        var server: Server = .{ .gpa = sa.allocator(), .io = io, .out = &out.interface, .queue = &queue };
        defer server.deinit();
        if (io.concurrent(readAll, .{ io, sa.allocator(), &in.interface, &queue })) |reader| {
            var r = reader;
            status = server.serve();
            queue.close(io);
            r.cancel(io);
        } else |_| {
            server.inline_jobs = true;
            status = server.serveInline(&in.interface);
        }
        server.stopWorker();
    }
    const leaks = sa.deinit();
    if (leaks > 0) {
        std.debug.print("{s}-lsp: {d} allocation{s} leaked\n", .{ language.id, leaks, if (leaks == 1) "" else "s" });
        return 1;
    }
    return status;
}

/// What the main loop waits for: a message's body, in the server's
/// allocator (null at the end of input or a message it cannot frame), an
/// analysis the worker finished, or a check the checker finished.
const Event = union(enum) { message: ?[]u8, analyzed: *Job, checked: *Check };

/// Read messages into the queue until the end of input.
fn readAll(io: std.Io, gpa: Allocator, in: *std.Io.Reader, queue: *std.Io.Queue(Event)) void {
    while (true) {
        const body = readMessage(in, gpa) catch null;
        queue.putOne(io, .{ .message = body }) catch {
            if (body) |b| gpa.free(b);
            return;
        };
        if (body == null) return;
    }
}

/// An analysis for the worker: its root, the document whose opening or
/// saving asked for it, a copy of every open document's path, text and
/// version, and what `analyze` made of them; all in its own arena.
const Job = struct {
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    root: []const u8,
    uri: []const u8,
    paths: []const []const u8,
    texts: []const []const u8,
    read: []const Held.Read,
    result: anyerror!Analyzed(Analysis) = error.NotRun,

    /// Run `analyze`, then hand the job to the main loop.
    fn run(job: *Job, queue: *std.Io.Queue(Event)) void {
        if (comptime has("analyze")) {
            job.result = hooks.analyze(job.arena.allocator(), job.root, .{ .io = job.io, .paths = job.paths, .texts = job.texts });
        }
        queue.putOneUncancelable(job.io, .{ .analyzed = job }) catch {};
    }
};

/// The most output of a check the server reads, its standard output and
/// standard error together; past it, the command is stopped.
const max_check_output = 4 << 20;

/// How long a check may run, in milliseconds, unless the client says
/// (`checkTimeout`).
const default_check_timeout = 60_000;

/// A check for the checker: the command (`key`, its words joined by NUL
/// bytes), the root of the program it checks, the directory it runs in, the
/// version of the saved text of each open document, and what came of it;
/// all in its own arena.
const Check = struct {
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    key: []const u8,
    root: []const u8,
    cwd: []const u8,
    timeout: u32,
    read: []const Held.Read,
    result: Outcome = .{ .failed = "" },

    /// The diagnostics the output names, or why there are none: the
    /// command did not start, ran out of time, or failed and named nothing.
    const Outcome = union(enum) { diagnostics: []const Diagnostic, failed: []const u8 };

    /// Run the command, then hand the check to the main loop; a check
    /// canceled (the server exits) is not handed back.
    fn run(c: *Check, queue: *std.Io.Queue(Event)) void {
        c.result = c.runCommand() catch |err| switch (err) {
            error.Canceled => return,
            error.OutOfMemory => .{ .failed = "the check ran out of memory" },
        };
        queue.putOneUncancelable(c.io, .{ .checked = c }) catch {};
    }

    fn runCommand(c: *Check) error{ Canceled, OutOfMemory }!Outcome {
        const a = c.arena.allocator();
        const io = c.io;
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, c.key, 0);
        while (it.next()) |w| try words.append(a, w);
        const argv = words.items;
        // In a process group of its own, so that stopping it stops what it
        // started too.
        var child = std.process.spawn(io, .{
            .argv = argv,
            .cwd = .{ .path = c.cwd },
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
            .pgid = if (builtin.os.tag == .windows) null else 0,
        }) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => return .{ .failed = try a.print("the check of {s} could not run {s}: {s}", .{ c.root, std.fs.path.basename(argv[0]), @errorName(err) }) },
        };
        var waited = false;
        defer if (!waited) stop(&child, io);
        var streams: std.Io.File.MultiReader.Buffer(2) = undefined;
        var mr: std.Io.File.MultiReader = undefined;
        mr.init(a, io, streams.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer mr.deinit();
        const deadline = (std.Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(c.timeout), .clock = .awake } }).toDeadline(io);
        var ended = false;
        while (true) {
            mr.fill(4096, deadline) catch |err| switch (err) {
                error.EndOfStream => {
                    ended = true;
                    break;
                },
                error.Timeout => return .{ .failed = try a.print("the check of {s} took longer than {d} ms", .{ c.root, c.timeout }) },
                error.Canceled => return error.Canceled,
                error.ConcurrencyUnavailable => return .{ .failed = try a.print("the check of {s} could not read its output", .{c.root}) },
            };
            if (mr.reader(0).bufferedLen() + mr.reader(1).bufferedLen() > max_check_output) break;
        }
        const out = try mr.toOwnedSlice(0);
        const err_out = try mr.toOwnedSlice(1);
        var term: ?std.process.Child.Term = null;
        if (ended) {
            term = child.wait(io) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => null,
            };
            waited = term != null;
        }
        var found: Found = .{ .a = a, .io = io, .cwd = c.cwd };
        try found.scan(err_out);
        try found.scan(out);
        const diagnostics = found.finish();
        if (diagnostics.len == 0) if (term) |t| if (!t.success()) {
            const line = firstLine(err_out) orelse firstLine(out) orelse "";
            return .{ .failed = try a.print("the check of {s} {f}{s}{s}", .{ c.root, t, if (line.len > 0) ": " else "", line }) };
        };
        return .{ .diagnostics = diagnostics };
    }

    /// Stop a command that has not ended: everything in its process group,
    /// then the command itself, which it waits for.
    fn stop(child: *std.process.Child, io: std.Io) void {
        if (builtin.os.tag != .windows) if (child.id) |pid| std.posix.kill(-pid, .KILL) catch {};
        child.kill(io);
    }

    /// The first line of `text` that is not blank, at most 200 bytes of it.
    fn firstLine(text: []const u8) ?[]const u8 {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len > 0) return line[0..@min(line.len, 200)];
        }
        return null;
    }
};

/// The diagnostics of a check's output: each line `PATH:LINE:COL: error:
/// MESSAGE`, or `warning:`, is one, and each `note:` line a note of the one
/// before it in the same output. PATH is relative to the directory the
/// check ran in; LINE and COL count from 1, COL in bytes. A line of a file
/// that cannot be read is left out.
const Found = struct {
    a: Allocator,
    io: std.Io,
    cwd: []const u8,
    list: std.ArrayList(Diagnostic) = .empty,
    notes: std.ArrayList(std.ArrayList(Note)) = .empty,
    files: std.array_hash_map.String(?Lines) = .empty,

    const Kind = enum { @"error", warning, note };

    fn scan(f: *Found, output: []const u8) error{OutOfMemory}!void {
        var last: ?usize = null;
        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |raw| {
            const got = parseLine(std.mem.trimEnd(u8, raw, "\r")) orelse continue;
            const span = try f.place(got.path, got.line, got.col) orelse continue;
            const message = try f.a.dupe(u8, got.message);
            if (got.kind == .note) {
                const i = last orelse continue;
                try f.notes.items[i].append(f.a, .{ .span = span, .message = message });
                continue;
            }
            last = f.list.items.len;
            try f.list.append(f.a, .{ .span = span, .severity = if (got.kind == .warning) .warning else .@"error", .message = message });
            try f.notes.append(f.a, .empty);
        }
    }

    fn finish(f: *Found) []const Diagnostic {
        for (f.list.items, f.notes.items) |*d, n| d.notes = n.items;
        return f.list.items;
    }

    /// The span at LINE:COL of the file `path` as it is on disk, to the end
    /// of the word there (`@highlight`'s word-chars), else of no width;
    /// null when the file cannot be read.
    fn place(f: *Found, path: []const u8, line: u32, col: u32) error{OutOfMemory}!?Span {
        const full = try std.fs.path.resolveAlloc(f.a, &.{ f.cwd, path });
        const entry = try f.files.getOrPut(f.a, full);
        if (!entry.found_existing) {
            const text: ?[]const u8 = std.Io.Dir.cwd().readFileAlloc(f.io, full, f.a, .limited(max_message_bytes)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null,
            };
            entry.value_ptr.* = if (text) |t| try Lines.init(f.a, t, .utf8) else null;
        }
        const lines = entry.value_ptr.* orelse return null;
        if (line - 1 >= lines.starts.len) return .{ .path = entry.key_ptr.*, .start = @intCast(lines.text.len), .end = @intCast(lines.text.len) };
        const stop = lines.lineEnd(line - 1);
        const at = @min(lines.starts[line - 1] +| (col - 1), stop);
        var end = at;
        while (end < stop and language.isWord(lines.text[end])) end += 1;
        return .{ .path = entry.key_ptr.*, .start = at, .end = end };
    }

    const Line = struct { path: []const u8, line: u32, col: u32, kind: Kind, message: []const u8 };

    /// `PATH:LINE:COL: KIND: MESSAGE`, LINE and COL at least 1; PATH may
    /// hold colons (a drive letter), and MESSAGE may be empty.
    fn parseLine(line: []const u8) ?Line {
        var from: usize = 0;
        while (std.mem.findPos(u8, line, from, ": ")) |sep| : (from = sep + 1) {
            const rest = line[sep + 2 ..];
            const kind: Kind = for (std.enums.values(Kind)) |k| {
                const word = @tagName(k);
                if (std.mem.startsWith(u8, rest, word) and std.mem.startsWith(u8, rest[word.len..], ":")) break k;
            } else continue;
            const head = line[0..sep];
            const c2 = std.mem.findScalarLast(u8, head, ':') orelse continue;
            const c1 = std.mem.findScalarLast(u8, head[0..c2], ':') orelse continue;
            if (c1 == 0) continue;
            const ln = std.fmt.parseInt(u32, head[c1 + 1 .. c2], 10) catch continue;
            const col = std.fmt.parseInt(u32, head[c2 + 1 ..], 10) catch continue;
            if (ln == 0 or col == 0) continue;
            const message = rest[@tagName(kind).len + 1 ..];
            return .{ .path = head[0..c1], .line = ln, .col = col, .kind = kind, .message = std.mem.trim(u8, message, " \t") };
        }
        return null;
    }
};

/// A change to a document's text: `len` bytes at `start` became `new_len`
/// bytes, making version `version`.
const Edit = struct { version: u64, start: u32, len: u32, new_len: u32 };

/// The most edits a document keeps; past it, positions in the texts
/// analyses read are no longer mapped.
const max_edits = 4096;

/// An open document. `version` is a tick of the server's clock, new with
/// each change; `opened`, the version it opened with; `saved`, the version
/// opened or saved last, the text on disk; `log` holds the edits that made
/// each version after `log_from`; `failed`: the error of the failed
/// analysis its opening or saving asked for, until an analysis succeeds.
const Doc = struct {
    uri: []u8,
    path: []u8,
    text: []u8,
    version: u64,
    opened: u64,
    saved: u64,
    log: std.ArrayList(Edit) = .empty,
    log_from: u64,
    failed: ?[]const u8 = null,
    /// The names of a version of its text (`@lsp`).
    names: ?*Names = null,

    fn deinit(d: *Doc, gpa: Allocator) void {
        gpa.free(d.uri);
        gpa.free(d.path);
        gpa.free(d.text);
        d.log.deinit(gpa);
        d.dropNames(gpa);
    }

    fn dropNames(d: *Doc, gpa: Allocator) void {
        const n = d.names orelse return;
        n.arena.deinit();
        gpa.destroy(n);
        d.names = null;
    }

    /// Offset `at` of the text of version `from`, in the text now; null
    /// where an edit since replaced the text, or when the log does not
    /// reach back to `from`. An end offset (`end`) stays before text
    /// inserted at it; a start offset moves past it.
    fn forward(d: *const Doc, from: u64, at: u32, end: bool) ?u32 {
        if (from < d.log_from) return null;
        var p = at;
        for (d.log.items) |e| {
            if (e.version <= from) continue;
            if (end) {
                if (p <= e.start) continue;
                if (p <= e.start + e.len) return null;
            } else {
                if (p < e.start) continue;
                if (p < e.start + e.len) return null;
            }
            p = p - e.len + e.new_len;
        }
        return p;
    }

    /// Offset `at` of the text now, in the text of version `to`; null
    /// inside text an edit since wrote, or when the log does not reach
    /// back to `to`.
    fn backward(d: *const Doc, to: u64, at: u32) ?u32 {
        if (to < d.log_from) return null;
        var p = at;
        var i = d.log.items.len;
        while (i > 0) {
            i -= 1;
            const e = d.log.items[i];
            if (e.version <= to) break;
            if (p < e.start) continue;
            if (p < e.start + e.new_len) return null;
            p = p - e.new_len + e.len;
        }
        return p;
    }

    /// Forget the edits before version `from`.
    fn prune(d: *Doc, from: u64) void {
        if (from <= d.log_from) return;
        var kept: usize = 0;
        for (d.log.items) |e| if (e.version > from) {
            d.log.items[kept] = e;
            kept += 1;
        };
        d.log.items.len = kept;
        d.log_from = from;
    }
};

/// The index of the names of one version of a document's text, in an
/// arena of its own.
const Names = struct { arena: std.heap.ArenaAllocator, version: u64, index: NameIndex };

/// The index of a file not open, read from disk, in an arena of its own:
/// the text it read, and the request that last used it.
const Cached = struct {
    arena: std.heap.ArenaAllocator,
    text: []const u8,
    index: NameIndex,
    used: u64,

    fn destroy(c: *Cached, gpa: Allocator) void {
        c.arena.deinit();
        gpa.destroy(c);
    }
};

/// The most files read from disk whose indexes the server keeps; reading
/// one more drops the one used least recently, unless the request under
/// way uses them all.
const max_cached = 256;

/// The most files of the workspace references and rename read.
const max_workspace_files = 20000;

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

/// The most checks whose diagnostics the server holds, one per command;
/// holding one more drops the one made first.
const max_checked = 64;

/// The diagnostics of the last check of one command, in an arena of its
/// own: the command (`Check.key`), the name its diagnostics give as their
/// source (the command's first word, without its directory), the version
/// of the saved text of each open document, and the tick it was made at.
const Checked = struct {
    arena: std.heap.ArenaAllocator,
    key: []const u8,
    source: []const u8,
    diagnostics: []const Diagnostic,
    read: []const Held.Read,
    made: u64,

    fn versionOf(c: *const Checked, path: []const u8) ?u64 {
        for (c.read) |r| if (std.mem.eql(u8, r.path, path)) return r.version;
        return null;
    }
};

/// The features a client may ask for, by their names in
/// `initializationOptions.features`; without that option, all of them.
/// `definition` is go to definition and to type definition; `references`
/// the references and the highlights; `check` the check command.
const Feature = enum {
    diagnostics,
    semanticTokens,
    folding,
    selection,
    symbols,
    hover,
    definition,
    references,
    rename,
    completion,
    signature,
    formatting,
    check,
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
    queue: *std.Io.Queue(Event),
    /// Analyses run as they are asked for, not on the worker.
    inline_jobs: bool = false,
    /// The analysis the worker runs, and the worker.
    running: ?*Job = null,
    worker: ?std.Io.Future(void) = null,
    /// The analyses asked for while one runs: one per root, with the
    /// document that asked last.
    pending: std.ArrayList(Pending) = .empty,
    /// The ids, as JSON, of the `nexus/idle` requests waiting for every
    /// analysis asked for to finish.
    idle: std.ArrayList([]u8) = .empty,
    /// The workspace's folders (`workspaceFolders`, else `rootUri`), whose
    /// files of the language's extensions references and rename search.
    folders: std.ArrayList([]u8) = .empty,
    /// The files of module names (`initializationOptions.modules`).
    modules: std.array_hash_map.String([]u8) = .empty,
    /// The import names logged as naming no file: each is logged once.
    unresolved: std.array_hash_map.String(void) = .empty,
    /// The indexes of files read from disk (`@lsp`), by path, each kept
    /// while its text on disk is the one it read.
    cached: std.array_hash_map.String(*Cached) = .empty,
    /// Counts the requests, for the cache's eviction.
    requests: u64 = 0,
    /// The features the client asks for (`initializationOptions.features`).
    features: std.EnumSet(Feature) = .full,
    /// The check command (`initializationOptions.check`), its words as the
    /// client gives them, `${file}` and `${root}` not yet replaced; empty
    /// without one.
    check: std.ArrayList([]u8) = .empty,
    /// How long a check may run (`initializationOptions.checkTimeout`), in
    /// milliseconds.
    check_timeout: u32 = default_check_timeout,
    /// The check the checker runs, and the checker.
    checking: ?*Check = null,
    checker: ?std.Io.Future(void) = null,
    /// The checks asked for and not yet begun: one per command (its key),
    /// with the root of the document that asked last.
    check_pending: std.ArrayList(CheckPending) = .empty,
    /// The last diagnostics of each command checked.
    checked: std.ArrayList(Checked) = .empty,
    /// Whether the last check failed: a failure is logged when the check
    /// before it did not fail.
    check_failed: bool = false,

    const Pending = struct { root: []u8, uri: []u8 };
    const CheckPending = struct { key: []u8, root: []u8 };

    fn deinit(s: *Server) void {
        for (s.docs.items) |*d| d.deinit(s.gpa);
        s.docs.deinit(s.gpa);
        if (s.root) |r| s.gpa.free(r);
        for (s.analyses.items) |*h| h.arena.deinit();
        s.analyses.deinit(s.gpa);
        for (s.sent.keys()) |k| s.gpa.free(k);
        s.sent.deinit(s.gpa);
        for (s.pending.items) |p| {
            s.gpa.free(p.root);
            s.gpa.free(p.uri);
        }
        s.pending.deinit(s.gpa);
        for (s.idle.items) |i| s.gpa.free(i);
        s.idle.deinit(s.gpa);
        for (s.folders.items) |f| s.gpa.free(f);
        s.folders.deinit(s.gpa);
        for (s.modules.keys(), s.modules.values()) |k, v| {
            s.gpa.free(k);
            s.gpa.free(v);
        }
        s.modules.deinit(s.gpa);
        for (s.unresolved.keys()) |k| s.gpa.free(k);
        s.unresolved.deinit(s.gpa);
        for (s.cached.keys(), s.cached.values()) |k, c| {
            s.gpa.free(k);
            c.destroy(s.gpa);
        }
        s.cached.deinit(s.gpa);
        for (s.check.items) |w| s.gpa.free(w);
        s.check.deinit(s.gpa);
        for (s.check_pending.items) |p| {
            s.gpa.free(p.key);
            s.gpa.free(p.root);
        }
        s.check_pending.deinit(s.gpa);
        for (s.checked.items) |*c| c.arena.deinit();
        s.checked.deinit(s.gpa);
    }

    fn tick(s: *Server) u64 {
        s.clock += 1;
        return s.clock;
    }

    /// Wait for the analysis the worker runs, stop the check the checker
    /// runs (and the command with it), and drop both.
    fn stopWorker(s: *Server) void {
        if (s.worker) |*w| w.await(s.io);
        s.worker = null;
        if (s.checker) |*w| w.cancel(s.io);
        s.checker = null;
        // What finished but was never handled.
        var events: [1]Event = undefined;
        while ((s.queue.get(s.io, &events, 0) catch 0) == 1) switch (events[0]) {
            .message => |body| if (body) |b| s.gpa.free(b),
            .analyzed => |job| {
                if (s.running == job) s.running = null;
                job.arena.deinit();
                s.gpa.destroy(job);
            },
            .checked => |c| {
                if (s.checking == c) s.checking = null;
                c.arena.deinit();
                s.gpa.destroy(c);
            },
        };
        if (s.running) |job| {
            job.arena.deinit();
            s.gpa.destroy(job);
        }
        s.running = null;
        if (s.checking) |c| {
            c.arena.deinit();
            s.gpa.destroy(c);
        }
        s.checking = null;
    }

    /// Whether an analysis or a check asked for has not yet landed.
    fn busy(s: *const Server) bool {
        return s.running != null or s.checking != null;
    }

    /// Whether the client asks for `f`.
    fn on(s: *const Server, f: Feature) bool {
        return s.features.contains(f);
    }

    /// Handle what the queue brings until `exit` or the end of input.
    fn serve(s: *Server) u8 {
        var arena: std.heap.ArenaAllocator = .init(s.gpa);
        defer arena.deinit();
        while (true) {
            const event = s.queue.getOneUncancelable(s.io) catch return 1;
            _ = arena.reset(.retain_capacity);
            const a = arena.allocator();
            switch (event) {
                .message => |body| {
                    const b = body orelse return 1;
                    defer s.gpa.free(b);
                    if (s.dispatch(a, b) catch return 1) |status| return status;
                },
                .analyzed => |job| s.finish(a, job) catch return 1,
                .checked => |c| s.finishCheck(a, c) catch return 1,
            }
        }
    }

    /// Read and handle messages until `exit` or the end of input, and
    /// handle each analysis and check as it finishes.
    fn serveInline(s: *Server, in: *std.Io.Reader) u8 {
        var arena: std.heap.ArenaAllocator = .init(s.gpa);
        defer arena.deinit();
        while (true) {
            _ = arena.reset(.retain_capacity);
            const a = arena.allocator();
            const body = (readMessage(in, a) catch return 1) orelse return 1;
            if (s.dispatch(a, body) catch return 1) |status| return status;
            var events: [1]Event = undefined;
            while ((s.queue.get(s.io, &events, 0) catch 0) == 1) switch (events[0]) {
                .message => unreachable,
                .analyzed => |job| s.finish(a, job) catch return 1,
                .checked => |c| s.finishCheck(a, c) catch return 1,
            };
        }
    }

    /// Handle one message; the status to exit with after `exit`.
    fn dispatch(s: *Server, a: Allocator, body: []const u8) error{ OutOfMemory, WriteFailed }!?u8 {
        const msg = std.json.parseFromSliceLeaky(Value, a, body, .{}) catch {
            try s.respondError(a, .null, .parse_error, "the message is not JSON");
            return null;
        };
        if (msg != .object) return null;
        const method = str(msg.object.get("method")) orelse return null;
        const id = msg.object.get("id");
        const params = msg.object.get("params") orelse .null;
        if (std.mem.eql(u8, method, "exit")) return if (s.shut_down) 0 else 1;
        try s.handle(a, method, id, params);
        return null;
    }

    fn handle(s: *Server, a: Allocator, method: []const u8, id: ?Value, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const eql = std.mem.eql;
        if (eql(u8, method, "initialize")) {
            s.initialized = true;
            var unknown: std.ArrayList([]const u8) = .empty;
            try s.respond(a, id orelse return, try s.initializeResult(a, params, &unknown));
            for (unknown.items) |name| try s.notify(a, "window/logMessage", .{ .type = 2, .message = try a.print("features: {s} is no feature of the server", .{name}) });
            return;
        }
        if (!s.initialized) {
            if (id) |i| try s.respondError(a, i, .server_not_initialized, "initialize first");
            return;
        }
        if (eql(u8, method, "shutdown")) {
            s.shut_down = true;
            return s.respond(a, id orelse return, null);
        }
        if (eql(u8, method, "nexus/idle")) {
            const i = id orelse return;
            if (!s.busy()) return s.respond(a, i, null);
            return s.idle.append(s.gpa, try std.json.Stringify.valueAlloc(s.gpa, i, .{}));
        }
        if (eql(u8, method, "textDocument/didOpen")) return s.didOpen(a, params);
        if (eql(u8, method, "textDocument/didChange")) return s.didChange(a, params);
        if (eql(u8, method, "textDocument/didSave")) return s.didSave(a, params);
        if (eql(u8, method, "textDocument/didClose")) return s.didClose(a, params);
        const i = id orelse return; // other notifications
        s.requests += 1;
        const doc = s.docOf(params) orelse return s.respondError(a, i, .invalid_params, "no open document");
        const result: Result = if (s.on(.semanticTokens) and eql(u8, method, "textDocument/semanticTokens/full"))
            try s.semanticTokens(a, doc)
        else if (s.on(.folding) and eql(u8, method, "textDocument/foldingRange"))
            try s.foldingRanges(a, doc)
        else if ((comptime has("symbols") or byNames("symbols")) and s.on(.symbols) and eql(u8, method, "textDocument/documentSymbol"))
            try s.documentSymbols(a, doc)
        else if ((comptime parser.nodeStore) and s.on(.selection) and eql(u8, method, "textDocument/selectionRange"))
            try s.selectionRanges(a, doc, params)
        else if (s.on(.completion) and eql(u8, method, "textDocument/completion"))
            try s.completion(a, doc, params)
        else if ((comptime canHover() or byNames("describe")) and s.on(.hover) and eql(u8, method, "textDocument/hover"))
            try s.hover(a, doc, params)
        else if ((comptime has("symbolAt") or byNames("symbolAt")) and s.on(.definition) and eql(u8, method, "textDocument/definition"))
            try s.definition(a, doc, params)
        else if ((comptime has("typeAt") and has("describe")) and s.on(.definition) and eql(u8, method, "textDocument/typeDefinition"))
            try s.typeDefinition(a, doc, params)
        else if ((comptime has("symbolAt") or byNames("symbolAt")) and s.on(.references) and eql(u8, method, "textDocument/references"))
            try s.references(a, doc, params, false)
        else if ((comptime has("symbolAt") or byNames("symbolAt")) and s.on(.references) and eql(u8, method, "textDocument/documentHighlight"))
            try s.references(a, doc, params, true)
        else if ((comptime has("symbolAt") or byNames("symbolAt")) and s.on(.rename) and eql(u8, method, "textDocument/rename"))
            try s.rename(a, doc, params)
        else if ((comptime has("signatures")) and s.on(.signature) and eql(u8, method, "textDocument/signatureHelp"))
            try s.signatureHelp(a, doc, params)
        else if ((comptime has("format")) and s.on(.formatting) and eql(u8, method, "textDocument/formatting"))
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

    /// Take the client's options, and answer with the capabilities; each
    /// name of `features` that is no feature goes in `unknown`.
    fn initializeResult(s: *Server, a: Allocator, params: Value, unknown: *std.ArrayList([]const u8)) error{OutOfMemory}![]const u8 {
        if (field(params, &.{ "initializationOptions", "features" })) |fs| if (fs == .array) {
            s.features = .empty;
            for (fs.array.items) |f| {
                const name = str(f) orelse {
                    try unknown.append(a, try std.json.Stringify.valueAlloc(a, f, .{}));
                    continue;
                };
                if (std.meta.stringToEnum(Feature, name)) |feature| s.features.insert(feature) else try unknown.append(a, name);
            }
        };
        if (field(params, &.{ "initializationOptions", "check" })) |c| if (c == .array) {
            for (c.array.items) |w| if (str(w)) |word| try s.check.append(s.gpa, try s.gpa.dupe(u8, word));
            // A command with a word that is not a string, or no command, is none.
            if (s.check.items.len != c.array.items.len or (s.check.items.len > 0 and s.check.items[0].len == 0)) {
                for (s.check.items) |w| s.gpa.free(w);
                s.check.clearRetainingCapacity();
            }
        };
        if (int(field(params, &.{ "initializationOptions", "checkTimeout" }))) |ms| if (ms > 0) {
            s.check_timeout = ms;
        };
        if (field(params, &.{ "capabilities", "general", "positionEncodings" })) |encs| if (encs == .array) {
            for (encs.array.items) |e| if (str(e)) |name| if (std.mem.eql(u8, name, "utf-8")) {
                s.encoding = .utf8;
            };
        };
        if (str(field(params, &.{ "initializationOptions", "root" }))) |r| if (r.len > 0) {
            s.root = try s.gpa.dupe(u8, r);
        };
        if (field(params, &.{ "initializationOptions", "modules" })) |m| if (m == .object) {
            var it = m.object.iterator();
            while (it.next()) |e| if (str(e.value_ptr.*)) |path| if (path.len > 0 and !s.modules.contains(e.key_ptr.*)) {
                try s.modules.put(s.gpa, try s.gpa.dupe(u8, e.key_ptr.*), try s.gpa.dupe(u8, path));
            };
        };
        if (field(params, &.{"workspaceFolders"})) |fs| if (fs == .array) {
            for (fs.array.items) |f| if (try uriToPath(a, str(field(f, &.{"uri"})) orelse continue)) |p| try s.folders.append(s.gpa, try s.gpa.dupe(u8, p));
        };
        if (s.folders.items.len == 0) if (str(field(params, &.{"rootUri"}))) |uri| if (try uriToPath(a, uri)) |p| {
            try s.folders.append(s.gpa, try s.gpa.dupe(u8, p));
        };
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        j.beginObject() catch return error.OutOfMemory;
        s.writeCapabilities(&j) catch return error.OutOfMemory;
        j.objectField("serverInfo") catch return error.OutOfMemory;
        j.write(.{ .name = language.id ++ "-lsp" }) catch return error.OutOfMemory;
        j.endObject() catch return error.OutOfMemory;
        return out.written();
    }

    /// The capabilities of the features the server can give and the client
    /// asks for.
    fn writeCapabilities(s: *const Server, j: *std.json.Stringify) std.Io.Writer.Error!void {
        try j.objectField("capabilities");
        try j.beginObject();
        try j.objectField("positionEncoding");
        try j.write(if (s.encoding == .utf8) "utf-8" else "utf-16");
        try j.objectField("textDocumentSync");
        try j.write(.{ .openClose = true, .change = 2, .save = .{ .includeText = false } });
        if (s.on(.semanticTokens)) {
            try j.objectField("semanticTokensProvider");
            try j.write(.{ .legend = .{ .tokenTypes = legend, .tokenModifiers = modifier_legend }, .full = true });
        }
        // Without node spans or a folds function, the editor's own
        // indentation folding serves better than comment runs alone.
        if ((parser.nodeStore or has("folds")) and s.on(.folding)) {
            try j.objectField("foldingRangeProvider");
            try j.write(true);
        }
        if (parser.nodeStore and s.on(.selection)) {
            try j.objectField("selectionRangeProvider");
            try j.write(true);
        }
        if ((has("symbols") or byNames("symbols")) and s.on(.symbols)) {
            try j.objectField("documentSymbolProvider");
            try j.write(true);
        }
        if (s.on(.completion)) {
            try j.objectField("completionProvider");
            try j.write(.{ .triggerCharacters = triggers });
        }
        if ((canHover() or byNames("describe")) and s.on(.hover)) {
            try j.objectField("hoverProvider");
            try j.write(true);
        }
        if (has("symbolAt") or byNames("symbolAt")) {
            if (s.on(.definition)) {
                try j.objectField("definitionProvider");
                try j.write(true);
            }
            if (s.on(.references)) {
                try j.objectField("referencesProvider");
                try j.write(true);
                try j.objectField("documentHighlightProvider");
                try j.write(true);
            }
            if (s.on(.rename)) {
                try j.objectField("renameProvider");
                try j.write(true);
            }
        }
        if (has("typeAt") and has("describe") and s.on(.definition)) {
            try j.objectField("typeDefinitionProvider");
            try j.write(true);
        }
        if (has("signatures") and s.on(.signature)) {
            try j.objectField("signatureHelpProvider");
            try j.write(.{ .triggerCharacters = [_][]const u8{ "(", "," } });
        }
        if (has("format") and s.on(.formatting)) {
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
            d.opened = d.version;
            d.saved = d.version;
            d.dropNames(s.gpa);
            d.log.clearRetainingCapacity();
            d.log_from = d.version;
        } else {
            const path = try uriToPath(a, uri);
            const version = s.tick();
            try s.docs.append(s.gpa, .{
                .uri = try s.gpa.dupe(u8, uri),
                .path = try s.gpa.dupe(u8, path orelse ""),
                .text = try s.gpa.dupe(u8, text),
                .version = version,
                .opened = version,
                .saved = version,
                .log_from = version,
            });
        }
        try s.logUnresolved(a, s.docOf(params).?);
        try s.analyzeAndCheck(a, s.docOf(params).?);
    }

    /// Ask for the analysis and the check of `d`'s program, which `d`'s
    /// opening or saving asks for; an analysis publishes when it lands, so
    /// without one, publish now.
    fn analyzeAndCheck(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        const analyzing = try s.askAnalysis(d);
        try s.askCheck(d);
        if (!analyzing) try s.publishAll(a);
    }

    /// Apply each change in turn: a range and its new text, or the whole
    /// new text.
    fn didChange(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const d = s.docOf(params) orelse return;
        const changes = field(params, &.{"contentChanges"}) orelse return;
        if (changes != .array) return;
        for (changes.array.items) |change| {
            const new = str(field(change, &.{"text"})) orelse continue;
            var lo: u32 = 0;
            var hi: u32 = @intCast(d.text.len);
            if (field(change, &.{"range"})) |range| {
                const lines = try Lines.init(a, d.text, s.encoding);
                lo = lines.offset(position(field(range, &.{"start"})) orelse continue);
                hi = @max(lo, lines.offset(position(field(range, &.{"end"})) orelse continue));
            }
            const text = try std.mem.concat(s.gpa, u8, &.{ d.text[0..lo], new, d.text[hi..] });
            s.gpa.free(d.text);
            d.text = text;
            d.version = s.tick();
            d.dropNames(s.gpa);
            if (d.log.items.len == max_edits) {
                d.log.clearRetainingCapacity();
                d.log_from = d.version;
            } else try d.log.append(s.gpa, .{ .version = d.version, .start = lo, .len = hi - lo, .new_len = @intCast(new.len) });
        }
        try s.publish(a, d);
    }

    fn didSave(s: *Server, a: Allocator, params: Value) error{ OutOfMemory, WriteFailed }!void {
        const d = s.docOf(params) orelse return;
        d.saved = d.version;
        try s.logUnresolved(a, d);
        try s.analyzeAndCheck(a, d);
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

    /// Ask for an analysis of the program of `d`: now, when the worker is
    /// free; else after the one it runs, once per root. Whether one was
    /// asked for: none without `analyze`, or for a document without a path.
    fn askAnalysis(s: *Server, d: *Doc) error{ OutOfMemory, WriteFailed }!bool {
        if (comptime !has("analyze")) return false;
        if (d.path.len == 0) return false;
        const root = s.rootOf(d);
        if (s.running == null) {
            try s.startJob(root, d.uri);
            return true;
        }
        for (s.pending.items) |*p| if (std.mem.eql(u8, p.root, root)) {
            s.gpa.free(p.uri);
            p.uri = try s.gpa.dupe(u8, d.uri);
            return true;
        };
        const owned_root = try s.gpa.dupe(u8, root);
        errdefer s.gpa.free(owned_root);
        try s.pending.append(s.gpa, .{ .root = owned_root, .uri = try s.gpa.dupe(u8, d.uri) });
        return true;
    }

    /// Hand the worker an analysis of `root` over a copy of the open
    /// documents; where tasks cannot run concurrently, run it here.
    fn startJob(s: *Server, root: []const u8, uri: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const job = try s.gpa.create(Job);
        job.* = .{ .arena = .init(s.gpa), .io = s.io, .root = undefined, .uri = undefined, .paths = undefined, .texts = undefined, .read = undefined };
        errdefer {
            job.arena.deinit();
            s.gpa.destroy(job);
        }
        const ja = job.arena.allocator();
        // Everything the analysis keeps is in its arena: the analysis may
        // keep the root it is given, and the last analysis of this root,
        // which may hold the root now, is dropped when this one lands.
        job.root = try ja.dupe(u8, root);
        job.uri = try ja.dupe(u8, uri);
        var paths: std.ArrayList([]const u8) = .empty;
        var texts: std.ArrayList([]const u8) = .empty;
        var read: std.ArrayList(Held.Read) = .empty;
        for (s.docs.items) |o| if (o.path.len > 0) {
            const path = try ja.dupe(u8, o.path);
            try paths.append(ja, path);
            try texts.append(ja, try ja.dupe(u8, o.text));
            try read.append(ja, .{ .path = path, .version = o.version });
        };
        job.paths = paths.items;
        job.texts = texts.items;
        job.read = read.items;
        s.running = job;
        if (!s.inline_jobs) {
            if (s.io.concurrent(Job.run, .{ job, s.queue })) |w| {
                s.worker = w;
                return;
            } else |_| s.inline_jobs = true;
        }
        job.run(s.queue);
    }

    /// Hold what the worker made of the program of `job.root`, in place of
    /// the last analysis of the same root, then start the next analysis
    /// and publish what changed. An analysis that fails keeps the last
    /// one, and says so: in the log, and in a diagnostic on the document
    /// that asked for it until an analysis succeeds.
    fn finish(s: *Server, a: Allocator, job: *Job) error{ OutOfMemory, WriteFailed }!void {
        if (s.worker) |*w| w.await(s.io);
        s.worker = null;
        s.running = null;
        var asker: ?*Doc = null;
        for (s.docs.items) |*d| if (std.mem.eql(u8, d.uri, job.uri)) {
            asker = d;
        };
        if (job.result) |got| {
            try s.hold(job, got);
            for (s.docs.items) |*o| if (o == asker or s.analyses.items[s.analyses.items.len - 1].covers(o.path)) {
                o.failed = null;
            };
        } else |err| {
            const message = try std.fmt.allocPrint(a, "the analysis of {s} failed: {s}", .{ job.root, @errorName(err) });
            job.arena.deinit();
            s.gpa.destroy(job);
            if (asker) |d| d.failed = @errorName(err);
            try s.notify(a, "window/logMessage", .{ .type = 1, .message = message });
        }
        if (s.pending.items.len > 0) {
            const next = s.pending.orderedRemove(0);
            defer s.gpa.free(next.root);
            defer s.gpa.free(next.uri);
            try s.startJob(next.root, next.uri);
        }
        try s.startNextCheck();
        s.pruneLogs();
        try s.publishAll(a);
        try s.answerIdle(a);
    }

    /// Answer the `nexus/idle` requests waiting, once nothing asked for is
    /// under way.
    fn answerIdle(s: *Server, a: Allocator) error{ OutOfMemory, WriteFailed }!void {
        if (s.busy()) return;
        for (s.idle.items) |i| {
            try writeMessage(s.out, try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":null}}", .{i}));
            s.gpa.free(i);
        }
        s.idle.clearRetainingCapacity();
    }

    // --- Checks ------------------------------------------------------------

    /// Ask for a check of `d`'s program, when the client gives a check
    /// command and asks for `check`: the command with `${file}` and
    /// `${root}` in place; after the analyses and the check under way, once
    /// per command. None for a document without a path.
    fn askCheck(s: *Server, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        if (s.check.items.len == 0 or !s.on(.check) or d.path.len == 0) return;
        const root = s.rootOf(d);
        var key: std.ArrayList(u8) = .empty;
        defer key.deinit(s.gpa);
        for (s.check.items, 0..) |word, n| {
            if (n > 0) try key.append(s.gpa, 0);
            var rest = word;
            while (rest.len > 0) {
                if (std.mem.startsWith(u8, rest, "${file}")) {
                    try key.appendSlice(s.gpa, d.path);
                    rest = rest["${file}".len..];
                } else if (std.mem.startsWith(u8, rest, "${root}")) {
                    try key.appendSlice(s.gpa, root);
                    rest = rest["${root}".len..];
                } else {
                    try key.append(s.gpa, rest[0]);
                    rest = rest[1..];
                }
            }
        }
        for (s.check_pending.items) |*p| if (std.mem.eql(u8, p.key, key.items)) {
            const owned = try s.gpa.dupe(u8, root);
            s.gpa.free(p.root);
            p.root = owned;
            return s.startNextCheck();
        };
        const owned_key = try s.gpa.dupe(u8, key.items);
        errdefer s.gpa.free(owned_key);
        try s.check_pending.append(s.gpa, .{ .key = owned_key, .root = try s.gpa.dupe(u8, root) });
        try s.startNextCheck();
    }

    /// Start the check asked for first, when the checker is free and no
    /// analysis runs: a check follows the analyses asked for with it, so
    /// the two never compete, and each publishes in turn.
    fn startNextCheck(s: *Server) error{ OutOfMemory, WriteFailed }!void {
        if (s.checking != null or s.running != null or s.check_pending.items.len == 0) return;
        const next = s.check_pending.orderedRemove(0);
        defer s.gpa.free(next.key);
        defer s.gpa.free(next.root);
        try s.startCheck(next.key, next.root);
    }

    /// Hand the checker the command `key` of the program of `root`, run in
    /// the first workspace folder, else the root's directory; where tasks
    /// cannot run concurrently, run it here.
    fn startCheck(s: *Server, key: []const u8, root: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const c = try s.gpa.create(Check);
        c.* = .{ .arena = .init(s.gpa), .io = s.io, .key = undefined, .root = undefined, .cwd = undefined, .timeout = s.check_timeout, .read = undefined };
        errdefer {
            c.arena.deinit();
            s.gpa.destroy(c);
        }
        const ca = c.arena.allocator();
        c.key = try ca.dupe(u8, key);
        c.root = try ca.dupe(u8, root);
        c.cwd = try ca.dupe(u8, if (s.folders.items.len > 0) s.folders.items[0] else std.fs.path.dirname(root) orelse "/");
        var read: std.ArrayList(Held.Read) = .empty;
        for (s.docs.items) |o| if (o.path.len > 0) {
            try read.append(ca, .{ .path = try ca.dupe(u8, o.path), .version = o.saved });
        };
        c.read = read.items;
        s.checking = c;
        if (!s.inline_jobs) {
            if (s.io.concurrent(Check.run, .{ c, s.queue })) |w| {
                s.checker = w;
                return;
            } else |_| s.inline_jobs = true;
        }
        c.run(s.queue);
    }

    /// Hold what the checker found, in place of the last diagnostics of
    /// the same command, then start the next check and publish what
    /// changed. A check that failed drops them, and is logged unless the
    /// check before it failed too.
    fn finishCheck(s: *Server, a: Allocator, c: *Check) error{ OutOfMemory, WriteFailed }!void {
        if (s.checker) |*w| w.await(s.io);
        s.checker = null;
        s.checking = null;
        for (s.checked.items, 0..) |*h, i| if (std.mem.eql(u8, h.key, c.key)) {
            h.arena.deinit();
            _ = s.checked.orderedRemove(i);
            break;
        };
        switch (c.result) {
            .diagnostics => |list| {
                s.check_failed = false;
                if (s.checked.items.len == max_checked) {
                    s.checked.items[0].arena.deinit();
                    _ = s.checked.orderedRemove(0);
                }
                const first = c.key[0 .. std.mem.findScalar(u8, c.key, 0) orelse c.key.len];
                try s.checked.append(s.gpa, .{
                    .arena = c.arena,
                    .key = c.key,
                    .source = std.fs.path.basename(first),
                    .diagnostics = list,
                    .read = c.read,
                    .made = s.tick(),
                });
                s.gpa.destroy(c);
            },
            .failed => |why| {
                const message = try a.dupe(u8, why);
                c.arena.deinit();
                s.gpa.destroy(c);
                if (!s.check_failed) try s.notify(a, "window/logMessage", .{ .type = 1, .message = message });
                s.check_failed = true;
            },
        }
        try s.startNextCheck();
        s.pruneLogs();
        try s.publishAll(a);
        try s.answerIdle(a);
    }

    /// `span`, in the text on disk when the check `c` began, in the text
    /// now: through the edits since the saved version `c` read of an open
    /// document, else (it opened since) since the version opened or saved
    /// last.
    fn checkNow(s: *Server, c: *const Checked, span: Span) ?Span {
        const d = s.docAt(span.path) orelse return span;
        const read = c.versionOf(span.path) orelse d.saved;
        return moved(d, if (read >= d.opened) read else d.saved, span);
    }

    /// Hold a finished job's analysis, last in `analyses`, in place of the
    /// analysis of the same root or else of the one used least recently
    /// when the server holds the most it may.
    fn hold(s: *Server, job: *Job, got: Analyzed(Analysis)) error{OutOfMemory}!void {
        const value = try job.arena.allocator().create(Analysis);
        value.* = got.analysis;
        const now = s.tick();
        const held: Held = .{
            .arena = job.arena,
            .root = job.root,
            .value = value,
            .diagnostics = got.diagnostics,
            .files = got.files,
            .read = job.read,
            .made = now,
            .used = now,
        };
        s.gpa.destroy(job);
        var drop: ?usize = null;
        for (s.analyses.items, 0..) |h, i| if (std.mem.eql(u8, h.root, held.root)) {
            drop = i;
        };
        if (drop == null and s.analyses.items.len == max_analyses) {
            drop = 0;
            for (s.analyses.items, 0..) |h, i| if (h.used < s.analyses.items[drop.?].used) {
                drop = i;
            };
        }
        if (drop) |i| {
            s.analyses.items[i].arena.deinit();
            _ = s.analyses.orderedRemove(i);
        }
        try s.analyses.append(s.gpa, held);
    }

    /// Forget the edits no held or running analysis needs: those before
    /// the oldest version of each document that one read.
    fn pruneLogs(s: *Server) void {
        for (s.docs.items) |*d| {
            var oldest: u64 = d.version;
            for (s.analyses.items) |*h| if (h.versionOf(d.path)) |v| {
                oldest = @min(oldest, v);
            };
            if (s.running) |job| for (job.read) |r| if (std.mem.eql(u8, r.path, d.path)) {
                oldest = @min(oldest, r.version);
            };
            // A check's diagnostics move from the saved text it read.
            if (s.check.items.len > 0) {
                oldest = @min(oldest, d.saved);
                for (s.checked.items) |*c| if (c.versionOf(d.path)) |v| if (v >= d.opened) {
                    oldest = @min(oldest, v);
                };
                if (s.checking) |c| for (c.read) |r| if (std.mem.eql(u8, r.path, d.path)) {
                    oldest = @min(oldest, r.version);
                };
            }
            d.prune(oldest);
        }
    }

    /// The open document of `path`.
    fn docAt(s: *Server, path: []const u8) ?*Doc {
        if (path.len == 0) return null;
        for (s.docs.items) |*d| if (std.mem.eql(u8, d.path, path)) return d;
        return null;
    }

    /// `span`, in the text the analysis `h` read, in the text now: the
    /// same in a file not open or whose text `h` read from disk; null
    /// where an edit since replaced text in it.
    fn toNow(s: *Server, h: *const Held, span: Span) ?Span {
        const d = s.docAt(span.path) orelse return span;
        return moved(d, h.versionOf(span.path) orelse return span, span);
    }

    /// `span` of the text of `d`'s version `from`, in its text now; null
    /// where an edit since replaced text in it.
    fn moved(d: *const Doc, from: u64, span: Span) ?Span {
        if (from == d.version) return span;
        const last = d.forward(from, span.end, true) orelse return null;
        const first = if (span.start == span.end) last else d.forward(from, span.start, false) orelse return null;
        return .{ .path = span.path, .start = first, .end = last };
    }

    /// Offset `at` of `d`'s text now, in the text the analysis `h` read;
    /// null inside text written since.
    fn toRead(h: *const Held, d: *const Doc, at: u32) ?u32 {
        const to = h.versionOf(d.path) orelse return at;
        if (to == d.version) return at;
        return d.backward(to, at);
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
        if (s.on(.diagnostics)) for (s.analyses.items) |h| for (h.diagnostics) |diag| {
            if (s.isOpen(diag.span.path) or containsPath(named.items, diag.span.path)) continue;
            try named.append(a, diag.span.path);
        };
        for (s.checked.items) |c| for (c.diagnostics) |diag| {
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

    /// Publish an open document's diagnostics: its parse errors, its uses
    /// of names nothing defines (with `@lsp`'s `undefined`, when the
    /// language has no `analyze`), then its program's analysis's while it
    /// read this text; then the checks'.
    fn publish(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        var parsed: []const Diagnostic = &.{};
        if (s.on(.diagnostics)) {
            parsed = try parseDiagnostics(a, d.path, d.text);
            if (comptime has_names and !has("analyze") and language.names.undefined != null) {
                const ix = try s.nameIndex(d);
                parsed = try std.mem.concat(a, Diagnostic, &.{ parsed, try ix.undefinedNames(a, d.path) });
            }
        }
        try s.sendFileDiagnostics(a, d.path, .{ .text = d.text, .parsed = parsed, .version = d.version, .failed = d.failed, .uri = d.uri });
    }

    const Open = struct { text: []const u8, parsed: []const Diagnostic, version: u64, failed: ?[]const u8, uri: []const u8 };

    /// A diagnostic to publish, and the name of what gave it.
    const Shown = struct { d: Diagnostic, source: []const u8 = language.id };

    fn sendFileDiagnostics(s: *Server, a: Allocator, path: []const u8, open: ?Open) error{ OutOfMemory, WriteFailed }!void {
        var list: std.ArrayList(Shown) = .empty;
        if (open) |o| for (o.parsed) |d| try list.append(a, .{ .d = d });
        if (s.on(.diagnostics)) {
            if (open) |o| if (o.failed) |err| try list.append(a, .{ .d = .{
                .span = .{ .path = path, .start = 0, .end = 0 },
                .message = try std.fmt.allocPrint(a, "the analysis failed: {s}", .{err}),
            } });
            // The analysis's, moved with the edits since it read the file;
            // none in an open file it did not read.
            if (s.ownerOf(path)) |h| if (open == null or h.versionOf(path) != null) {
                for (h.diagnostics) |d| if (std.mem.eql(u8, d.span.path, path)) {
                    const span = s.toNow(h, d.span) orelse continue;
                    var notes: std.ArrayList(Note) = .empty;
                    for (d.notes) |n| try notes.append(a, .{ .span = s.toNow(h, n.span) orelse continue, .message = n.message });
                    try list.append(a, .{ .d = .{ .span = span, .severity = d.severity, .message = d.message, .notes = notes.items } });
                };
            };
        }
        // Each check's, moved with the edits since the saved text it read;
        // one that another check gave too, once.
        const own = list.items.len;
        for (s.checked.items) |*c| for (c.diagnostics) |d| if (std.mem.eql(u8, d.span.path, path)) {
            const span = s.checkNow(c, d.span) orelse continue;
            const seen = for (list.items[own..]) |o| {
                if (o.d.span.start == span.start and o.d.span.end == span.end and o.d.severity == d.severity and
                    std.mem.eql(u8, o.d.message, d.message) and std.mem.eql(u8, o.source, c.source)) break true;
            } else false;
            if (seen) continue;
            var notes: std.ArrayList(Note) = .empty;
            for (d.notes) |n| try notes.append(a, .{ .span = s.checkNow(c, n.span) orelse continue, .message = n.message });
            try list.append(a, .{ .d = .{ .span = span, .severity = d.severity, .message = d.message, .notes = notes.items }, .source = c.source });
        };
        const text = if (open) |o| o.text else try s.fileText(a, path);
        const lines = try Lines.init(a, text, s.encoding);
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        writeDiagnostics(s, a, &j, lines, list.items) catch return error.OutOfMemory;
        try s.sendDiagnostics(a, if (open) |o| o.uri else try pathToUri(a, path), out.written());
    }

    fn writeDiagnostics(s: *Server, a: Allocator, j: *std.json.Stringify, lines: Lines, list: []const Shown) !void {
        try j.beginArray();
        for (list) |shown| {
            const d = shown.d;
            try j.beginObject();
            try j.objectField("range");
            try j.write(lines.range(d.span.start, d.span.end));
            try j.objectField("severity");
            try j.write(@backingInt(d.severity));
            try j.objectField("source");
            try j.write(shown.source);
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
        const grammar = try s.grammarTokensOf(a, d);
        const toks: []const Token = if (comptime has("tokens"))
            hooks.tokens(a, d.path, d.text, grammar) catch return .{ .failed = "tokens failed" }
        else
            grammar;
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
                    try data.appendSlice(a, &.{ p.line - prev.line, if (p.line == prev.line) p.character - prev.character else p.character, len, @backingInt(t.scope), @bitCast(t.modifiers) });
                    prev = p;
                }
                if (p.line + 1 >= lines.starts.len) break;
                at = @max(stop + 1, lines.starts[p.line + 1]);
            }
        }
        return json(a, .{ .data = data.items });
    }

    /// The semantic tokens of `d` the grammar gives: each token's
    /// `@highlight` scope, and with `@lsp`, in place of it or beside it, the
    /// scope and modifiers of its `color` lines (`scopes.tokens`).
    fn grammarTokensOf(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}![]const Token {
        const base = try grammarTokens(a, d.text);
        if (comptime !has_names) return base;
        const q = try s.nameRequest(a, d);
        const named = try scopes.tokens(&q.r, q.f);
        if (named.len == 0) return base;
        var out: std.ArrayList(Token) = try .initCapacity(a, base.len + named.len);
        var i: usize = 0;
        var n: usize = 0;
        while (i < base.len or n < named.len) {
            if (n < named.len and (i == base.len or named[n].start <= base[i].start)) {
                if (i < base.len and base[i].start == named[n].start) i += 1;
                out.appendAssumeCapacity(named[n]);
                n += 1;
            } else {
                out.appendAssumeCapacity(base[i]);
                i += 1;
            }
        }
        return out.items;
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
        const items = if (comptime has("symbols"))
            hooks.symbols(a, d.path, d.text) catch return .{ .failed = "symbols failed" }
        else if (comptime has_names)
            try (try s.nameIndex(d)).outline(a)
        else
            unreachable;
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
        // After `.` (a member) or where a qualified name goes: the members
        // of what is before it, without keywords.
        if (comptime byNames("members")) {
            const q = try s.nameRequest(a, d);
            if (try q.r.membersAt(q.f, at)) |members| {
                for (members) |g| {
                    const m = try g.file.ix.symbol(a, g.file.path, g.def);
                    const detail = if (m.detail.len > 0) m.detail else try g.file.ix.typeText(a, g.def);
                    try items.append(a, .{ .label = m.name, .kind = completionKind(m.kind), .detail = nonEmpty(detail), .documentation = if (m.doc.len > 0) .{ .value = m.doc } else null });
                }
                return json(a, .{ .isIncomplete = false, .items = items.items });
            }
        }
        if (comptime byNames("visible")) {
            const ix = try s.nameIndex(d);
            if (ix.wantsNames(at)) for (try ix.visibleAt(a, at)) |di| {
                const m = try ix.symbol(a, d.path, di);
                const detail = if (m.detail.len > 0) m.detail else try ix.typeText(a, di);
                try items.append(a, .{ .label = m.name, .kind = completionKind(m.kind), .detail = nonEmpty(detail), .documentation = if (m.doc.len > 0) .{ .value = m.doc } else null });
            };
        }
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

    /// The request's position, in the text the analysis of `d`'s program
    /// read; null inside text written since.
    fn posOf(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!?Pos {
        const lines = try Lines.init(a, d.text, s.encoding);
        const p = position(field(params, &.{"position"})) orelse return null;
        const at = lines.offset(p);
        const h = s.ownerOf(d.path) orelse return .{ .path = d.path, .offset = at };
        return .{ .path = d.path, .offset = toRead(h, d, at) orelse return null };
    }

    /// A span the analysis of `d`'s program gave, in the text now.
    fn spanNow(s: *Server, d: *Doc, span: Span) ?Span {
        const h = s.ownerOf(d.path) orelse return span;
        return s.toNow(h, span);
    }

    fn location(s: *Server, a: Allocator, span: Span) error{OutOfMemory}!struct { uri: []const u8, range: Range } {
        const lines = try Lines.init(a, try s.fileText(a, span.path), s.encoding);
        return .{ .uri = try pathToUri(a, span.path), .range = lines.range(span.start, span.end) };
    }

    fn hover(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !canHover()) return s.namesHover(a, d, params);
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
        if (comptime !has("symbolAt")) return s.namesDefinition(a, d, params);
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return json(a, null);
        return json(a, try s.location(a, s.spanNow(d, sym.decl) orelse return json(a, null)));
    }

    fn typeDefinition(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !(has("typeAt") and has("describe"))) unreachable;
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const t = (hooks.typeAt(an, a, pos) catch null) orelse return json(a, null);
        const desc = (hooks.describe(an, a, .{ .type = t }) catch null) orelse return json(a, null);
        const decl = desc.decl orelse return json(a, null);
        return json(a, try s.location(a, s.spanNow(d, decl) orelse return json(a, null)));
    }

    /// Every span that uses `sym`, in the text now: the language's
    /// `references`, else every token whose `symbolAt` is `sym` of every
    /// file the analysis of `d`'s program read and every open document of
    /// that program. A use in text written since the analysis is not one.
    fn uses(s: *Server, a: Allocator, d: *Doc, an: *Analysis, sym: Symbol) error{OutOfMemory}![]const Span {
        var out: std.ArrayList(Span) = .empty;
        if (comptime has("references")) {
            const got = hooks.references(an, a, sym) catch &.{};
            for (got) |sp| try out.append(a, s.spanNow(d, sp) orelse continue);
            return out.items;
        }
        if (comptime !has("symbolAt")) unreachable;
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
                const at = if (owner) |h| (if (s.docAt(path)) |o| toRead(h, o, t.pos) orelse continue else t.pos) else t.pos;
                const found = (hooks.symbolAt(an, a, .{ .path = path, .offset = at }) catch null) orelse continue;
                if (std.mem.eql(u8, found.id, sym.id)) try out.append(a, .{ .path = path, .start = t.pos, .end = t.pos + t.len });
            }
        }
        return out.items;
    }

    fn references(s: *Server, a: Allocator, d: *Doc, params: Value, here: bool) error{OutOfMemory}!Result {
        if (comptime !has("symbolAt")) return s.namesReferences(a, d, params, here);
        const an = s.analysis(d) orelse return json(a, null);
        const pos = try s.posOf(a, d, params) orelse return json(a, null);
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return json(a, null);
        const spans = try s.uses(a, d, an, sym);
        const decl = s.spanNow(d, sym.decl);
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
            const isDecl = if (decl) |dc| std.mem.eql(u8, sp.path, dc.path) and sp.start == dc.start else false;
            if (isDecl and !withDecl) continue;
            const loc = try s.location(a, sp);
            try out.append(a, .{ .uri = loc.uri, .range = loc.range });
        }
        return json(a, out.items);
    }

    fn rename(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        if (comptime !has("symbolAt")) return s.namesRename(a, d, params);
        const an = s.analysis(d) orelse return .{ .failed = "no analysis yet: save the file" };
        const pos = try s.posOf(a, d, params) orelse return .{ .failed = "no position" };
        const name = str(field(params, &.{"newName"})) orelse return .{ .failed = "no new name" };
        const sym = (hooks.symbolAt(an, a, pos) catch null) orelse return .{ .failed = "nothing to rename here" };
        if (comptime has("renamable")) if (!hooks.renamable(an, sym)) return .{ .failed = "this name cannot be renamed" };
        // Every use must be where the analysis saw it.
        if (s.ownerOf(d.path)) |h| for (s.docs.items) |*o| if (h.versionOf(o.path)) |v| if (v != o.version)
            return .{ .failed = "a file of the program changed since its analysis: save it first" };
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

    // --- From the grammar's names (`@lsp`) ---------------------------------

    /// The names of `d`'s text now, indexed once per version.
    fn nameIndex(s: *Server, d: *Doc) error{OutOfMemory}!*const NameIndex {
        if (comptime !has_names) unreachable;
        if (d.names) |n| if (n.version == d.version) return &n.index;
        d.dropNames(s.gpa);
        const n = try s.gpa.create(Names);
        n.* = .{ .arena = .init(s.gpa), .version = d.version, .index = undefined };
        n.index = scopes.index(n.arena.allocator(), d.text) catch |err| {
            n.arena.deinit();
            s.gpa.destroy(n);
            return err;
        };
        d.names = n;
        return &n.index;
    }

    /// Log each import of `d` whose name names no file (`window/logMessage`):
    /// no module's (the `modules` option, `resolveImport`), and no file at
    /// the path it makes beside `d`; with the setting to set, and the
    /// language's `unresolvedImport`. Each name once in the server's life;
    /// a document without a path, which imports modules alone, never.
    fn logUnresolved(s: *Server, a: Allocator, d: *Doc) error{ OutOfMemory, WriteFailed }!void {
        if (comptime !has_names or language.names.imports.len == 0) return;
        if (d.path.len == 0) return;
        const w = try a.create(Workspace);
        w.* = .{ .s = s, .a = a, .doc = d };
        var r: scopes.Resolver = .init(a, w.world());
        const f: scopes.File = .{ .path = d.path, .ix = try s.nameIndex(d) };
        for (f.ix.imports, 0..) |im, i| {
            if (im.name.len == 0 or s.unresolved.contains(im.name)) continue;
            if (try r.importPath(f, @intCast(i))) |path| {
                if (s.docAt(path) != null) continue;
                if (std.Io.Dir.cwd().access(s.io, path, .{})) |_| continue else |_| {}
            }
            try s.unresolved.put(s.gpa, try s.gpa.dupe(u8, im.name), {});
            const said: Unresolved = if (comptime has("unresolvedImport")) hooks.unresolvedImport(a, im.name) catch .plain else .plain;
            if (said == .quiet) continue;
            // The file a module of the name would be, as an example.
            const made = if (language.names.imports[im.line].file) |pattern|
                try std.mem.replaceOwned(u8, a, pattern, "{}", im.name)
            else if (std.fs.path.extension(im.name).len > 0 or language.names.extensions.len == 0)
                im.name
            else
                try a.print("{s}.{s}", .{ im.name, language.names.extensions[0] });
            const example = try a.print("/path/to/{s}", .{std.fs.path.basename(made)});
            const message = try a.print("the import \"{s}\" in {s} names no file. For a module, set {s}.server.modules (the modules option) to its file, as {{{f}: {f}}}.{s}{s}", .{
                im.name,
                d.path,
                language.settings,
                std.json.fmt(im.name, .{}),
                std.json.fmt(example, .{}),
                if (said == .hint) " " else "",
                if (said == .hint) said.hint else "",
            });
            try s.notify(a, "window/logMessage", .{ .type = 2, .message = message });
        }
    }

    /// The index of `text`, the text of the file at `path` on disk: the
    /// one kept while the file's text is the one it read.
    fn diskIndex(s: *Server, a: Allocator, path: []const u8, text: []const u8) error{OutOfMemory}!*const NameIndex {
        if (comptime !has_names) unreachable;
        if (s.cached.get(path)) |c| {
            if (std.mem.eql(u8, c.text, text)) {
                c.used = s.requests;
                return &c.index;
            }
            // Read already by this request, in another text: this one is
            // the request's own.
            if (c.used == s.requests) {
                const ix = try a.create(NameIndex);
                ix.* = try scopes.index(a, text);
                return ix;
            }
            const kv = s.cached.fetchSwapRemove(path).?;
            s.gpa.free(kv.key);
            kv.value.destroy(s.gpa);
        }
        if (s.cached.count() >= max_cached) {
            var oldest: ?usize = null;
            for (s.cached.values(), 0..) |c, i| if (c.used < s.requests and (oldest == null or c.used < s.cached.values()[oldest.?].used)) {
                oldest = i;
            };
            if (oldest) |i| {
                const key = s.cached.keys()[i];
                const c = s.cached.values()[i];
                s.cached.swapRemoveAt(i);
                s.gpa.free(key);
                c.destroy(s.gpa);
            }
        }
        const c = try s.gpa.create(Cached);
        c.* = .{ .arena = .init(s.gpa), .text = "", .index = undefined, .used = s.requests };
        const ca = c.arena.allocator();
        c.text = ca.dupe(u8, text) catch |err| {
            c.destroy(s.gpa);
            return err;
        };
        c.index = scopes.index(ca, c.text) catch |err| {
            c.destroy(s.gpa);
            return err;
        };
        const key = s.gpa.dupe(u8, path) catch |err| {
            c.destroy(s.gpa);
            return err;
        };
        s.cached.put(s.gpa, key, c) catch |err| {
            s.gpa.free(key);
            c.destroy(s.gpa);
            return err;
        };
        return &c.index;
    }

    /// The files of one request: each one's index (a text in place of the
    /// file's, the open document's, else the file on disk's), and the
    /// files of module names (the `modules` setting, else the language's
    /// `resolveImport`).
    const Workspace = struct {
        s: *Server,
        a: Allocator,
        /// The document of the request, which may have no path.
        doc: *Doc,
        /// Texts in place of the files' own (a rename's, made).
        texts: []const scopes.Text = &.{},
        loaded: std.StringHashMapUnmanaged(?*const NameIndex) = .empty,
        read: std.StringHashMapUnmanaged(?[]const u8) = .empty,

        const vtable: scopes.World.VTable = .{ .load = load, .module = module };

        fn world(w: *Workspace) scopes.World {
            return .{ .ptr = w, .vtable = &vtable };
        }

        fn load(ptr: *anyopaque, path: []const u8) error{OutOfMemory}!?*const NameIndex {
            const w: *Workspace = @ptrCast(@alignCast(ptr));
            if (w.loaded.get(path)) |ix| return ix;
            const ix = try w.indexOf(path);
            try w.loaded.put(w.a, try w.a.dupe(u8, path), ix);
            return ix;
        }

        fn indexOf(w: *Workspace, path: []const u8) error{OutOfMemory}!?*const NameIndex {
            for (w.texts) |t| if (std.mem.eql(u8, t.path, path)) {
                const ix = try w.a.create(NameIndex);
                ix.* = try scopes.index(w.a, t.text);
                return ix;
            };
            if (std.mem.eql(u8, path, w.doc.path)) return try w.s.nameIndex(w.doc);
            if (w.s.docAt(path)) |d| return try w.s.nameIndex(d);
            const text = (try w.textOf(path)) orelse return null;
            return try w.s.diskIndex(w.a, path, text);
        }

        /// The text of the file at `path`: its text in place, the open
        /// document's, else the file on disk's; null when it cannot be
        /// read.
        fn textOf(w: *Workspace, path: []const u8) error{OutOfMemory}!?[]const u8 {
            for (w.texts) |t| if (std.mem.eql(u8, t.path, path)) return t.text;
            if (std.mem.eql(u8, path, w.doc.path)) return w.doc.text;
            if (w.s.docAt(path)) |d| return d.text;
            if (w.read.get(path)) |t| return t;
            const got: ?[]const u8 = if (!std.fs.path.isAbsolute(path)) null else std.Io.Dir.cwd().readFileAlloc(w.s.io, path, w.a, .limited(max_message_bytes)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null,
            };
            try w.read.put(w.a, try w.a.dupe(u8, path), got);
            return got;
        }

        fn module(ptr: *anyopaque, from: []const u8, name: []const u8) error{OutOfMemory}!?[]const u8 {
            const w: *Workspace = @ptrCast(@alignCast(ptr));
            if (w.s.modules.get(name)) |path| return path;
            if (comptime has("resolveImport")) return hooks.resolveImport(w.a, from, name) catch null;
            return null;
        }

        /// The files at `paths` that hold any of `names`, and `extra`'s,
        /// each once, by path.
        fn holding(w: *Workspace, paths: []const []const u8, needles: []const []const u8, extra: []const []const u8) error{OutOfMemory}![]const []const u8 {
            var out: std.ArrayList([]const u8) = .empty;
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (extra) |p| if (!(try seen.getOrPut(w.a, p)).found_existing) try out.append(w.a, p);
            for (paths) |p| {
                if ((try seen.getOrPut(w.a, p)).found_existing) continue;
                const t = (try w.textOf(p)) orelse continue;
                for (needles) |n| if (n.len == 0 or std.mem.find(u8, t, n) != null) {
                    try out.append(w.a, p);
                    break;
                };
            }
            std.mem.sort([]const u8, out.items, {}, struct {
                fn lt(_: void, x: []const u8, y: []const u8) bool {
                    return std.mem.order(u8, x, y) == .lt;
                }
            }.lt);
            return out.items;
        }
    };

    /// The files of the workspace: every open document's, and each file
    /// of the language's extensions under the workspace's folders (in none
    /// whose name starts with `.`).
    fn workspaceFiles(s: *Server, a: Allocator) error{OutOfMemory}![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        for (s.docs.items) |d| if (d.path.len > 0) try out.append(a, d.path);
        for (s.folders.items) |folder| {
            var dir = std.Io.Dir.cwd().openDir(s.io, folder, .{ .iterate = true }) catch continue;
            defer dir.close(s.io);
            var walker = try dir.walkSelectively(a);
            defer walker.deinit();
            while (walker.next(s.io) catch null) |entry| switch (entry.kind) {
                .directory => if (entry.basename[0] != '.') walker.enter(s.io, entry) catch {},
                .file => {
                    const ext = std.fs.path.extension(entry.basename);
                    const ours = for (language.names.extensions) |e| {
                        if (ext.len > 1 and std.mem.eql(u8, ext[1..], e)) break true;
                    } else false;
                    if (!ours) continue;
                    if (out.items.len >= max_workspace_files) break;
                    try out.append(a, try std.fs.path.join(a, &.{ folder, entry.path }));
                },
                else => {},
            };
        }
        return out.items;
    }

    /// A request's names: its workspace, a resolver over it, and `d`.
    const Request = struct {
        w: *Workspace,
        r: scopes.Resolver,
        f: scopes.File,

        /// The text of the file at `path` the request read.
        fn textIn(q: *Request, path: []const u8) error{OutOfMemory}![]const u8 {
            const f = (try q.r.load(path)) orelse return "";
            return f.ix.text;
        }
    };

    fn nameRequest(s: *Server, a: Allocator, d: *Doc) error{OutOfMemory}!*Request {
        const w = try a.create(Workspace);
        w.* = .{ .s = s, .a = a, .doc = d };
        const q = try a.create(Request);
        q.* = .{ .w = w, .r = .init(a, w.world()), .f = .{ .path = d.path, .ix = try s.nameIndex(d) } };
        return q;
    }

    /// The request's position in `d`'s text now.
    fn offsetIn(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!?u32 {
        const lines = try Lines.init(a, d.text, s.encoding);
        return lines.offset(position(field(params, &.{"position"})) orelse return null);
    }

    /// The location of `from..to` of the file at `path`, whose text is
    /// `text`: `d`'s URI for its own path.
    fn locationOf(s: *Server, a: Allocator, d: *Doc, path: []const u8, text: []const u8, from: u32, to: u32) error{OutOfMemory}!struct { uri: []const u8, range: Range } {
        const lines = try Lines.init(a, text, s.encoding);
        return .{ .uri = if (std.mem.eql(u8, path, d.path)) d.uri else try pathToUri(a, path), .range = lines.range(from, to) };
    }

    fn namesDefinition(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const q = try s.nameRequest(a, d);
        const at = try s.offsetIn(a, d, params) orelse return json(a, null);
        const t = (try q.r.targetAt(q.f, at)) orelse return json(a, null);
        return switch (t) {
            .def => |g| json(a, try s.locationOf(a, d, g.file.path, g.file.ix.text, g.file.ix.defs[g.def].start, g.file.ix.defs[g.def].end)),
            .file => |f| json(a, try s.locationOf(a, d, f.path, f.ix.text, 0, 0)),
            // A name of a namespace has no definition.
            .nominal => json(a, null),
        };
    }

    fn namesReferences(s: *Server, a: Allocator, d: *Doc, params: Value, here: bool) error{OutOfMemory}!Result {
        const q = try s.nameRequest(a, d);
        const at = try s.offsetIn(a, d, params) orelse return json(a, null);
        const t = (try q.r.targetAt(q.f, at)) orelse return json(a, null);
        const withDecl = if (field(params, &.{ "context", "includeDeclaration" })) |v| v == .bool and v.bool else here;
        if (here) {
            const lines = try Lines.init(a, d.text, s.encoding);
            const H = struct { range: Range };
            var out: std.ArrayList(H) = .empty;
            for (try q.r.references(t, &.{d.path})) |sp| try out.append(a, .{ .range = lines.range(sp.start, sp.end) });
            return json(a, out.items);
        }
        const home: []const u8 = switch (t) {
            .def => |g| g.file.path,
            .file => |f| f.path,
            .nominal => d.path,
        };
        // A file's imports hold its name, or a module's that names it.
        var needles: std.ArrayList([]const u8) = .empty;
        if (t == .file) {
            const base = std.fs.path.basename(t.file.path);
            try needles.append(a, base[0 .. base.len - std.fs.path.extension(base).len]);
            for (s.modules.keys(), s.modules.values()) |name, path| if (std.mem.eql(u8, path, t.file.path)) try needles.append(a, name);
        } else try needles.append(a, t.name());
        const paths = try q.w.holding(try s.workspaceFiles(a), needles.items, &.{ d.path, home });
        const L = struct { uri: []const u8, range: Range };
        var out: std.ArrayList(L) = .empty;
        for (try q.r.references(t, paths)) |sp| {
            if (!withDecl and t == .def and std.mem.eql(u8, sp.path, home) and sp.start == t.def.file.ix.defs[t.def.def].start) continue;
            const loc = try s.locationOf(a, d, sp.path, try q.textIn(sp.path), sp.start, sp.end);
            try out.append(a, .{ .uri = loc.uri, .range = loc.range });
        }
        return json(a, out.items);
    }

    fn namesRename(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const q = try s.nameRequest(a, d);
        const at = try s.offsetIn(a, d, params) orelse return .{ .failed = "no position" };
        const name = str(field(params, &.{"newName"})) orelse return .{ .failed = "no new name" };
        const t = (try q.r.targetAt(q.f, at)) orelse return .{ .failed = "nothing to rename here" };
        // The new name must lex as one token of the old name's category.
        if (t != .file) {
            const old = oneToken(t.name()) orelse return .{ .failed = "the declaration is not one token" };
            const new = oneToken(name) orelse return .{ .failed = "the new name is not one token" };
            if (new != old) return .{ .failed = "the new name is not a name of the same kind" };
        }
        const home: []const u8 = switch (t) {
            .def => |g| g.file.path,
            else => d.path,
        };
        const paths = try q.w.holding(try s.workspaceFiles(a), &.{ t.name(), name }, &.{ d.path, home });
        const spans = switch (try scopes.renameSpans(&q.r, t, paths)) {
            .spans => |got| got,
            .refused => |why| return .{ .failed = why },
        };
        const after = try a.create(Workspace);
        after.* = .{ .s = s, .a = a, .doc = d, .texts = try scopes.renamed(&q.r, spans, name) };
        var r2: scopes.Resolver = .init(a, after.world());
        if (try scopes.renameRefusal(&q.r, &r2, t, name, spans, paths)) |why| return .{ .failed = why };
        var out: std.Io.Writer.Allocating = .init(a);
        var j: std.json.Stringify = .{ .writer = &out.writer };
        j.beginObject() catch return error.OutOfMemory;
        j.objectField("changes") catch return error.OutOfMemory;
        j.beginObject() catch return error.OutOfMemory;
        var done: std.ArrayList([]const u8) = .empty;
        for (spans) |sp| {
            if (containsPath(done.items, sp.path)) continue;
            try done.append(a, sp.path);
            const E = struct { range: Range, newText: []const u8 };
            var edits: std.ArrayList(E) = .empty;
            for (spans) |x| if (std.mem.eql(u8, x.path, sp.path)) {
                const loc = try s.locationOf(a, d, x.path, try q.textIn(x.path), x.start, x.end);
                try edits.append(a, .{ .range = loc.range, .newText = name });
            };
            j.objectField(if (std.mem.eql(u8, sp.path, d.path)) d.uri else try pathToUri(a, sp.path)) catch return error.OutOfMemory;
            j.write(edits.items) catch return error.OutOfMemory;
        }
        j.endObject() catch return error.OutOfMemory;
        j.endObject() catch return error.OutOfMemory;
        return .{ .json = out.written() };
    }

    /// Markdown for the name at the position: the detail of what it names
    /// (else its name) as code, its type, and its doc.
    fn namesHover(s: *Server, a: Allocator, d: *Doc, params: Value) error{OutOfMemory}!Result {
        const q = try s.nameRequest(a, d);
        const at = try s.offsetIn(a, d, params) orelse return json(a, null);
        const t = (try q.r.targetAt(q.f, at)) orelse return json(a, null);
        if (t != .def) return json(a, null);
        const g = t.def;
        const sym = try g.file.ix.symbol(a, g.file.path, g.def);
        var md: std.ArrayList(u8) = .empty;
        try md.print(a, "```{s}\n{s}\n```", .{ language.id, if (sym.detail.len > 0) sym.detail else sym.name });
        const ty = try g.file.ix.typeText(a, g.def);
        if (sym.detail.len == 0 and ty.len > 0) try md.print(a, "\n\nType: `{s}`", .{ty});
        if (sym.doc.len > 0) try md.print(a, "\n\n{s}", .{sym.doc});
        return json(a, .{ .contents = .{ .kind = "markdown", .value = md.items } });
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
/// every error the tolerant parse repairs past when the grammar has
/// `@repair`, else the strict parse's error.
fn parseDiagnostics(a: Allocator, path: []const u8, text: []const u8) error{OutOfMemory}![]const Diagnostic {
    if (comptime has("parseDiagnostics")) return hooks.parseDiagnostics(a, path, text) catch &.{};
    var p = BaseParser.init(a, text);
    const failures: []const parser.Failure = if (parser.hasRepair) tolerant: {
        const r = p.parseTolerant(start, 64) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return &.{},
        };
        break :tolerant r.failures;
    } else strict: {
        _ = p.parse(start) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break :strict if (p.lastError()) |f| try a.dupe(parser.Failure, &.{f}) else &.{},
        };
        break :strict &.{};
    };
    const list = try a.alloc(Diagnostic, failures.len);
    for (list, failures) |*d, f| {
        var out: std.Io.Writer.Allocating = .init(a);
        p.writeFailure(&out.writer, f) catch return error.OutOfMemory;
        // `line:col: message`: the position is the diagnostic's range.
        var message = out.written();
        if (std.mem.findScalar(u8, message, ' ')) |sp| if (sp > 0 and message[sp - 1] == ':') {
            message = message[sp + 1 ..];
        };
        // The offending token, or the end of a line before it (zero width).
        const end = if (f.at == f.span.start) f.span.end else f.at;
        d.* = .{ .span = .{ .path = path, .start = f.at, .end = end }, .message = message };
    }
    return list;
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

/// The most bytes after the word at the position a trial keeps, which a
/// lang Lexer may read ahead into.
const trial_tail = 256;

/// The words of `language.words` the language takes at `at` as keywords,
/// in place of the word the position is in. The text before that word is
/// parsed once, through the lang module's `Parser` and `Lexer` when it has
/// them, up to the word; then each word is read by the lexer from where it
/// stopped and tested against the parse stack there (`parser.pauseAt`,
/// `parser.takesAt`). A word is offered where the parser takes it as other
/// than what a name that is no word (the word with its last letter again)
/// would be, followed by the text after the word, or by such a name: a
/// lang Lexer may read a word as a keyword only before a name. None when
/// the text before the word has an error of its own.
fn keywordsAt(a: Allocator, text: []const u8, at: u32) error{OutOfMemory}![]const []const u8 {
    var begin: usize = @min(at, text.len);
    while (begin > 0 and language.isWord(text[begin - 1])) begin -= 1;
    var end: usize = @min(at, text.len);
    while (end < text.len and language.isWord(text[end])) end += 1;
    // The parse pauses before the blanks before the word, whose layout
    // tokens the lexer reads with each word (a line end before a word is
    // read the same before any word).
    var from = begin;
    while (from > 0 and std.mem.findScalar(u8, " \t\r\n", text[from - 1]) != null) from -= 1;
    const p = try a.create(parser.Parser);
    p.* = parser.Parser.init(a, text);
    const base: *BaseParser = if (parser.Parser == BaseParser) p else &p.base;
    const paused = (parser.pauseAt(base, start, @intCast(from)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    }) orelse return &.{};
    const after = text[end..@min(text.len, end + trial_tail)];
    var trial: std.ArrayList(u8) = .empty;
    try trial.appendSlice(a, text[0..begin]);
    var out: std.ArrayList([]const u8) = .empty;
    for (language.words) |word| {
        const name = try std.mem.concat(a, u8, &.{ word, word[word.len - 1 ..] });
        const named = try std.mem.concat(a, u8, &.{ " ", name, after });
        for ([_][]const u8{ after, named }) |rest| {
            const sym = (try takes(a, base, &paused, &trial, begin, word, rest)) orelse continue;
            if (try takes(a, base, &paused, &trial, begin, name, rest) == sym) continue;
            try out.append(a, word);
            break;
        }
    }
    return out.items;
}

/// The symbol the paused parse takes `word` at `begin` as, `after` after
/// it; null when it does not take it. `trial` holds the text up to
/// `begin`.
fn takes(a: Allocator, base: *BaseParser, paused: *const parser.Paused, trial: *std.ArrayList(u8), begin: usize, word: []const u8, after: []const u8) error{OutOfMemory}!?u16 {
    trial.items.len = begin;
    try trial.appendSlice(a, word);
    try trial.appendSlice(a, after);
    return parser.takesAt(base, paused, trial.items, @intCast(begin), @intCast(word.len));
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
