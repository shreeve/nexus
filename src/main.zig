//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [options] <grammar-file> <output-file>
//!        nexus check [--messages] <grammar-file>
//!        nexus --dump-sexp <grammar-file> [output-file]
//!        nexus --describe <grammar-file> [output-file]
//!        nexus --highlight <target> <grammar-file> [output-file]
//!        nexus --editor [--lang <file>] <grammar-file> <directory>
//!        nexus --help | --version
//!
//! Pipeline: frontend (the self-hosted grammar-file parser, lowered to the
//! lexer spec and GrammarIR) -> lexgen (lexer source) -> highlight (with
//! @highlight: the entries checked against the lexer) -> semantics (with
//! @schema: actions resolved against the schema) -> expand (desugared
//! Grammar) -> semantics.checkTypes (with @schema) -> check (defined
//! symbols, reachable rules, token binding, `X "c"` hint resolution) -> lr
//! (automaton, lookaheads, table) -> messages (with @messages: the
//! examples run through the table) -> codegen (the parser module).
//! `--describe`, `--highlight` and `--editor` run the whole pipeline, then
//! write the grammar's JSON description, one of its editor files, or its
//! VS Code extension and language server (lsp/editor.zig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const diag = @import("diag.zig");
const frontend = @import("frontend/frontend.zig");
const GrammarLowerer = frontend.GrammarLowerer;
const LexerGenerator = @import("lexgen/lexgen.zig").LexerGenerator;
const grammar = @import("grammar.zig");
const Grammar = grammar.Grammar;
const expand = @import("expand.zig");
const semantics = @import("semantics.zig");
const check = @import("check.zig");
const lr = @import("lr/lr.zig");
const codegen = @import("codegen/codegen.zig");
const highlight = @import("highlight/highlight.zig");
const emit = @import("highlight/emit.zig");
const describe = @import("describe.zig");
const messages = @import("messages.zig");
const editor = @import("lsp/editor.zig");
const names = @import("lsp/names.zig");
const identity = @import("lsp/identity.zig");

const max_grammar_bytes: usize = 1 << 20; // 1 MiB cap for .grammar file reads
/// An alternative that expands into this many rules or more is named in
/// the progress output: each combination of its optional parts is a rule
/// of its own (GRAMMAR.md, "Clause rules").
const widestNote: usize = 32;

test {
    _ = @import("diag.zig");
    _ = @import("grammar.zig");
    _ = @import("frontend/lower.zig");
    _ = @import("semantics.zig");
    _ = @import("lexgen/lexgen.zig");
    _ = @import("lr/lr.zig");
    _ = @import("codegen/runtime.zig");
    _ = @import("codegen/codegen.zig");
    _ = @import("highlight/render.zig");
    _ = @import("highlight/highlight.zig");
    _ = @import("lsp/names.zig");
    _ = @import("json.zig");
}

const usage =
    \\Usage: nexus [options] <grammar-file> <output-file>
    \\       nexus check [--messages] <grammar-file>
    \\       nexus --dump-sexp <grammar-file> [output-file]
    \\       nexus --describe <grammar-file> [output-file]
    \\       nexus --highlight <target> <grammar-file> [output-file]
    \\       nexus --editor [--lang <file>] <grammar-file> <directory>
    \\       nexus --help | --version
    \\
;

const help = "nexus " ++ version ++ " — one grammar file in, one Zig parser module out\n\n" ++
    \\Reads a .grammar file (an @lexer section, then an @parser section) and
    \\writes a standalone Zig module with its DFA lexer, LALR(1) parser and,
    \\with @schema, the verified semantic layer.
    \\
    \\
++ usage ++
    \\
    \\Commands:
    \\  <grammar-file> <output-file>
    \\                  Generate the parser module into output-file
    \\  check           Check the grammar without writing anything; with
    \\                  --messages, print the coverage of its @messages on
    \\                  standard output: each place a message can key on
    \\                  that has none, with the shortest example that
    \\                  reaches it and its automatic message
    \\  --dump-sexp     Write the frontend's S-expression tree of the grammar
    \\                  file to output-file (default: standard output)
    \\  --describe      Write the grammar as JSON (tokens, lexer rules, keywords,
    \\                  @highlight, schema) to output-file (default: standard
    \\                  output)
    \\  --highlight     Write an editor file from the grammar's @highlight to
    \\                  output-file (default: standard output); <target> is
    \\                  textmate, language-configuration, highlightjs or vim.
    \\                  `--highlight all` writes all four into a directory:
    \\                  vscode/syntaxes/<id>.tmLanguage.json,
    \\                  vscode/language-configuration.json,
    \\                  vim/syntax/<id>.vim, highlightjs/<id>.js (<id>: the
    \\                  last part of the scope-name)
    \\  --editor        Write the language's VS Code extension and language
    \\                  server into a directory (docs/LSP.md): the files of
    \\                  `--highlight all`, vscode/package.json and extension.js,
    \\                  and server/ (build.zig; in src/, main.zig, lsp.zig,
    \\                  parser.zig, language.zig and the lang module). Every
    \\                  file is written again but server/src/hooks.zig, the
    \\                  language's functions, written only when missing. The
    \\                  grammar needs @highlight; with @lang, --lang <file>
    \\                  names its lang module, which is copied with the files
    \\                  it imports
    \\
    \\An output-file of - is standard output. Output replaces the file
    \\atomically (through a symlink, the file it names), keeping its mode;
    \\other hard links to it keep the old contents. The grammar file itself
    \\is never replaced.
    \\
    \\Options:
    \\  --spans         Record node spans and rule ids (always on with @schema)
    \\  -c, --comments  Write each grammar rule as a comment above its action
    \\  -h, --help      Show this help
    \\  -V, --version   Show the version
    \\
    \\Errors are reported as file:line:col: error: <message>; the exit
    \\status is 0 on success, 1 on any error, 2 on a usage error.
    \\
    \\Examples:
    \\  nexus calc.grammar src/parser.zig
    \\  nexus check calc.grammar
    \\  nexus --dump-sexp nexus.grammar
    \\  nexus --highlight textmate calc.grammar calc.tmLanguage.json
    \\  nexus --highlight all calc.grammar editors
    \\  nexus --editor calc.grammar editors
    \\
;

const version = @import("version.zig").version;

const Options = struct {
    checkMode: bool = false,
    /// `check --messages`: write the coverage of `@messages`.
    coverage: bool = false,
    emitComments: bool = false,
    spans: bool = false,
    /// `--editor`: the parser module has the language server's completion
    /// functions.
    completion: bool = false,
    /// `--editor --lang`: the lang module.
    langModule: ?[]const u8 = null,
    grammarFile: []const u8,
    outputFile: []const u8,
};

pub fn main(init: std.process.Init) !void {
    // Nexus is a short-lived CLI: read one grammar, emit one parser, exit.
    // Everything lives in the process arena and is freed at exit.
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    var command: Command = .generate;
    // null: `--highlight all`, every editor file into a directory.
    var target: ?emit.Target = null;
    var opts: Options = .{ .grammarFile = undefined, .outputFile = undefined };
    var positional: [2][]const u8 = undefined;
    var count: usize = 0;
    var generationOption: ?[]const u8 = null;
    var a: usize = 1;
    while (a < args.len) : (a += 1) {
        const arg = args[a];
        if (eql(arg, "-h") or eql(arg, "--help")) {
            return writeStdout(io, help);
        } else if (eql(arg, "-V") or eql(arg, "--version")) {
            return writeStdout(io, "nexus " ++ version ++ "\n");
        } else if (eql(arg, "--dump-sexp") or eql(arg, "--describe") or eql(arg, "--highlight") or eql(arg, "--editor")) {
            const next: Command = if (eql(arg, "--dump-sexp")) .dump else if (eql(arg, "--describe")) .describe else if (eql(arg, "--editor")) .editor else .highlight;
            if (command == .check) usageError("{s} and check are separate commands", .{arg});
            if (command != .generate) usageError("{s} and {s} are separate commands", .{ command.name(), arg });
            command = next;
            if (next == .highlight) {
                a += 1;
                if (a == args.len) usageError("--highlight needs a target: textmate, language-configuration, highlightjs, vim or all", .{});
                if (!eql(args[a], "all")) target = emit.Target.parse(args[a]) orelse
                    usageError("unknown --highlight target '{s}' (textmate, language-configuration, highlightjs, vim or all)", .{args[a]});
            }
        } else if (eql(arg, "--messages")) {
            opts.coverage = true;
        } else if (eql(arg, "--lang")) {
            a += 1;
            if (a == args.len) usageError("--lang needs the lang module's file", .{});
            opts.langModule = args[a];
        } else if (eql(arg, "-c") or eql(arg, "--comments")) {
            opts.emitComments = true;
            generationOption = arg;
        } else if (eql(arg, "--spans")) {
            opts.spans = true;
            generationOption = arg;
        } else if (count == 0 and eql(arg, "check")) {
            if (command != .generate) usageError("{s} and check are separate commands", .{command.name()});
            command = .check;
        } else if (arg.len > 1 and arg[0] == '-') {
            usageError("unknown option '{s}'", .{arg});
        } else if (count < 2) {
            positional[count] = arg;
            count += 1;
        } else {
            usageError("unexpected argument '{s}'", .{arg});
        }
    }
    if (count == 0) usageError("no grammar file given", .{});
    const output: ?[]const u8 = if (count == 2) positional[1] else null;
    if (output) |path| if (command != .check) refuseGrammarAsOutput(io, positional[0], path);

    switch (command) {
        .dump, .describe, .highlight, .editor => if (generationOption) |o| usageError("{s} has no effect on {s}", .{ o, command.name() }),
        else => {},
    }
    if (opts.langModule != null and command != .editor) usageError("--lang is an option of --editor", .{});
    if (opts.coverage and command != .check) usageError("--messages is an option of check", .{});
    switch (command) {
        .dump => return dumpSexp(allocator, io, positional[0], output orelse "-"),
        .check => {
            if (output) |path| usageError("`nexus check` writes nothing; unexpected '{s}'", .{path});
            opts.checkMode = true;
        },
        .describe, .highlight => {
            opts.checkMode = true;
            opts.outputFile = output orelse "-";
            if (command == .highlight and target == null) {
                const dir = output orelse usageError("--highlight all writes a directory: nexus --highlight all <grammar-file> <directory>", .{});
                if (eql(dir, "-")) usageError("--highlight all writes a directory, not standard output", .{});
            }
        },
        .editor => {
            const dir = output orelse usageError("--editor writes a directory: nexus --editor <grammar-file> <directory>", .{});
            if (eql(dir, "-")) usageError("--editor writes a directory, not standard output", .{});
            opts.outputFile = dir;
            // The server's folds and selection ranges read node spans, and
            // its keyword completion the parse table.
            opts.spans = true;
            opts.completion = true;
        },
        .generate => opts.outputFile = output orelse usageError("no output file given (nexus <grammar-file> <output-file>)", .{}),
    }
    opts.grammarFile = positional[0];
    const built = try build(allocator, io, opts);
    switch (command) {
        .generate => {
            try writeOutput(io, opts.outputFile, built.code);
            diag.info("Generated: {s}", .{if (eql(opts.outputFile, "-")) "standard output" else opts.outputFile});
        },
        .check => {
            diag.info("{s}: no errors", .{opts.grammarFile});
            if (opts.coverage) writeStdout(io, built.coverage);
        },
        .describe => {
            const bytes = try describe.write(allocator, .{
                .version = version,
                .grammarFile = opts.grammarFile,
                .ir = &built.ir,
                .spec = &built.spec,
                .g = if (built.g) |*g| g else null,
                .highlight = if (built.highlight) |*h| h else null,
                .lsp = if (built.lsp) |*l| l else null,
            });
            try writeOutput(io, opts.outputFile, bytes);
            if (!eql(opts.outputFile, "-")) diag.info("Wrote the description to {s} ({d} bytes)", .{ opts.outputFile, bytes.len });
        },
        .highlight => {
            const h = if (built.highlight) |*h| h else {
                diag.errLine(opts.grammarFile, 1, 1, "the grammar has no @highlight, so it has no editor files", .{});
                fail();
            };
            const name = std.fs.path.basename(opts.grammarFile);
            const one = target orelse {
                // Every file, into the layout of emit.layout.
                for (std.enums.values(emit.Target)) |t| {
                    const path = try std.fs.path.join(allocator, &.{ opts.outputFile, try emit.layoutPath(allocator, h, t) });
                    std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(path).?) catch |err| {
                        diag.err("cannot create {s}: {s}", .{ std.fs.path.dirname(path).?, @errorName(err) });
                        fail();
                    };
                    try writeOutput(io, path, try emit.emit(allocator, h, t, name, version));
                    diag.info("Wrote {s}", .{path});
                }
                return;
            };
            const bytes = try emit.emit(allocator, h, one, name, version);
            try writeOutput(io, opts.outputFile, bytes);
            if (!eql(opts.outputFile, "-")) diag.info("Wrote the {s} file to {s} ({d} bytes)", .{ one.name(), opts.outputFile, bytes.len });
        },
        .editor => try writeEditor(allocator, io, opts, &built),
        .dump => unreachable,
    }
}

/// `nexus --editor`: the files of lsp/editor.zig under `opts.outputFile`.
fn writeEditor(allocator: Allocator, io: Io, opts: Options, built: *const Built) !void {
    const h = if (built.highlight) |*h| h else {
        diag.errLine(opts.grammarFile, 1, 1, "the grammar has no @highlight, so it has no editor files", .{});
        fail();
    };
    const g = if (built.g) |*g| g else {
        diag.errLine(opts.grammarFile, 1, 1, "the grammar has no parser rules, so it has no language server", .{});
        fail();
    };
    var copied: []const editor.Copied = &.{};
    if (g.lang) |lang| {
        const module = opts.langModule orelse usageError("the grammar has @lang = \"{s}\": give its lang module with --lang <file>", .{lang});
        switch (try editor.langFiles(allocator, io, module, lang)) {
            .files => |files| copied = files,
            .bad => |path| {
                diag.err("cannot copy {s} into the server: it cannot be read, or it is outside the directory of {s}", .{ path, module });
                fail();
            },
            .clash => |path| {
                diag.err("the server has its own {s}; the lang module {s} cannot bring one", .{ path, module });
                fail();
            },
        }
    } else if (opts.langModule) |module| usageError("--lang {s}: the grammar has no @lang", .{module});

    // The extension's identity: the language's own file, read before
    // anything is written, else the defaults, written once below.
    const cwd = std.Io.Dir.cwd();
    const identityPath = try std.fs.path.join(allocator, &.{ opts.outputFile, "vscode/identity.json" });
    const base = try identity.defaults(allocator, h);
    var id = base;
    const identityText: ?[]const u8 = cwd.readFileAlloc(io, identityPath, allocator, .limited(1 << 20)) catch |err| switch (err) {
        // No identity.json yet; or no directory for it, which the writing
        // below reports.
        error.FileNotFound, error.NotDir => null,
        else => {
            diag.err("cannot read {s}: {s}", .{ identityPath, @errorName(err) });
            fail();
        },
    };
    if (identityText) |text| id = identity.parse(allocator, identityPath, text, base) catch |err| switch (err) {
        error.Reported => fail(),
        error.OutOfMemory => return error.OutOfMemory,
    };

    const name = std.fs.path.basename(opts.grammarFile);
    const in: editor.Input = .{ .h = h, .g = g, .spec = &built.spec, .keywordGroups = built.ir.keywordGroups, .grammarName = name, .version = version, .identity = id, .lsp = if (built.lsp) |*l| l else null };
    const File = struct { path: []const u8, bytes: []const u8 };
    var files: std.ArrayList(File) = .empty;
    for (std.enums.values(emit.Target)) |t|
        try files.append(allocator, .{ .path = try emit.layoutPath(allocator, h, t), .bytes = try emit.emit(allocator, h, t, name, version) });
    try files.append(allocator, .{ .path = "vscode/package.json", .bytes = try editor.packageJson(allocator, in) });
    try files.append(allocator, .{ .path = "vscode/extension.js", .bytes = try editor.extensionJs(allocator, in) });
    try files.append(allocator, .{ .path = "vscode/README.md", .bytes = try editor.readme(allocator, in) });
    try files.append(allocator, .{ .path = "vscode/.vscodeignore", .bytes = try editor.vscodeIgnore(allocator, in) });
    try files.append(allocator, .{ .path = "vscode/.gitignore", .bytes = "node_modules/\ndist/\nbin/\n*.vsix\n.vscode-test/\n" });
    try files.append(allocator, .{ .path = "server/build.zig", .bytes = try editor.buildZig(allocator, in) });
    try files.append(allocator, .{ .path = "server/.gitignore", .bytes = ".zig-cache/\nzig-out/\n" });
    try files.append(allocator, .{ .path = "server/src/main.zig", .bytes = try editor.mainZig(allocator, in) });
    try files.append(allocator, .{ .path = "server/src/lsp.zig", .bytes = try std.mem.concat(allocator, u8, &.{ "//! Generated by nexus v" ++ version ++ " — do not edit\n", editor.server_template }) });
    try files.append(allocator, .{ .path = "server/src/parser.zig", .bytes = built.code });
    try files.append(allocator, .{ .path = "server/src/language.zig", .bytes = try editor.languageZig(allocator, in) });
    if (built.lsp != null) try files.append(allocator, .{ .path = "server/src/scopes.zig", .bytes = try std.mem.concat(allocator, u8, &.{ "//! Generated by nexus v" ++ version ++ " — do not edit\n", editor.scopes_template }) });
    for (copied) |c| try files.append(allocator, .{ .path = try std.fs.path.join(allocator, &.{ "server/src", c.path }), .bytes = c.text });

    for (files.items) |f| {
        const path = try std.fs.path.join(allocator, &.{ opts.outputFile, f.path });
        makeParent(io, path);
        try writeOutput(io, path, f.bytes);
        diag.info("Wrote {s}", .{path});
    }
    // The language's own files: written once, never replaced.
    if (identityText != null) {
        diag.info("Kept {s}", .{identityPath});
    } else {
        try writeOutput(io, identityPath, try identity.write(allocator, base));
        diag.info("Wrote {s}", .{identityPath});
    }
    const hooks = try std.fs.path.join(allocator, &.{ opts.outputFile, "server/src/hooks.zig" });
    if (cwd.statFile(io, hooks, .{})) |_| {
        diag.info("Kept {s}", .{hooks});
    } else |_| {
        try writeOutput(io, hooks, try editor.hooksZig(allocator, in));
        diag.info("Wrote {s}", .{hooks});
    }
}

fn makeParent(io: Io, path: []const u8) void {
    const dir = std.fs.path.dirname(path) orelse return;
    std.Io.Dir.cwd().createDirPath(io, dir) catch |err| {
        diag.err("cannot create {s}: {s}", .{ dir, @errorName(err) });
        fail();
    };
}

const Command = enum {
    generate,
    check,
    dump,
    describe,
    highlight,
    editor,

    fn name(self: Command) []const u8 {
        return switch (self) {
            .generate => "generation",
            .check => "check",
            .dump => "--dump-sexp",
            .describe => "--describe",
            .highlight => "--highlight",
            .editor => "--editor",
        };
    }
};

/// A usage error when `output` names the grammar file itself (by any
/// spelling or link): writing it would destroy the grammar. Two paths name
/// one file when their inode, size and times agree (`Stat` carries no
/// device number).
fn refuseGrammarAsOutput(io: Io, grammarFile: []const u8, output: []const u8) void {
    if (eql(output, "-")) return;
    const cwd = std.Io.Dir.cwd();
    const g = cwd.statFile(io, grammarFile, .{}) catch return;
    const o = cwd.statFile(io, output, .{}) catch return;
    if (g.inode == o.inode and g.size == o.size and
        g.mtime.nanoseconds == o.mtime.nanoseconds and g.ctime.nanoseconds == o.ctime.nanoseconds)
        usageError("the output file '{s}' is the grammar file", .{output});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// A command-line mistake: the message and the usage, exit status 2.
fn usageError(comptime fmt: []const u8, args: anytype) noreturn {
    diag.err(fmt, args);
    std.debug.print("{s}Run `nexus --help` for more.\n", .{usage});
    std.process.exit(2);
}

/// Writes `bytes` to standard output; a reader that went away first (a
/// broken pipe) is no error.
fn writeStdout(io: Io, bytes: []const u8) void {
    std.Io.File.stdout().writeStreamingAll(io, bytes) catch |err| switch (err) {
        error.BrokenPipe => {},
        else => {
            diag.err("cannot write standard output: {s}", .{@errorName(err)});
            fail();
        },
    };
}

/// `nexus --dump-sexp`: write the frontend's canonical tree of the grammar file.
fn dumpSexp(allocator: Allocator, io: Io, grammarFile: []const u8, outputPath: []const u8) !void {
    const sourceText = try readGrammar(allocator, io, grammarFile);

    const parsed = frontend.parseGrammarSexp(allocator, sourceText, grammarFile) catch |err| {
        if (err != error.ParseError) diag.err("failed to parse {s}: {any}", .{ grammarFile, err });
        fail();
    };

    var output: std.Io.Writer.Allocating = .init(allocator);
    const writer = &output.writer;
    try frontend.dumpSexp(writer, parsed.sexp, sourceText, 0);
    try writer.writeByte('\n');
    const bytes = writer.buffered();

    try writeOutput(io, outputPath, bytes);
    if (!eql(outputPath, "-")) diag.info("Wrote S-expression dump to {s} ({d} bytes)", .{ outputPath, bytes.len });
}

/// What the pipeline makes of a grammar file.
const Built = struct {
    ir: grammar.GrammarIR,
    spec: grammar.LexerSpec,
    /// The generated grammar; null without parser rules.
    g: ?Grammar,
    highlight: ?highlight.Highlight,
    /// `@lsp`, read against the schema.
    lsp: ?names.Lsp = null,
    /// The parser module; empty in check mode.
    code: []const u8,
    /// `check --messages`: the coverage report.
    coverage: []const u8 = "",
};

/// Runs the whole pipeline on the grammar file; any error is reported and
/// exits.
fn build(allocator: Allocator, io: Io, opts: Options) !Built {
    const grammarFile = opts.grammarFile;
    const sourceText = try readGrammar(allocator, io, grammarFile);

    diag.info("Reading grammar from {s}", .{grammarFile});

    // The whole file through the self-hosted frontend, lowered into the
    // lexer spec and GrammarIR (whose strings are slices of sourceText).
    const parsed = frontend.parseGrammarSexp(allocator, sourceText, grammarFile) catch |err| {
        if (err != error.ParseError) diag.err("failed to parse {s}: {any}", .{ grammarFile, err });
        fail();
    };

    var ir = GrammarLowerer.lowerParsed(allocator, &parsed) catch |err| {
        if (err == error.OutOfMemory) diag.err("out of memory", .{});
        fail();
    };
    var lexerSpec = ir.lexer orelse {
        diag.errLine(grammarFile, 1, 1, "no @lexer section (a grammar file has an @lexer section, then an @parser section)", .{});
        fail();
    };

    var lexerGen = LexerGenerator.init(allocator, &lexerSpec);

    const lexerDecls = lexerGen.generateDecls() catch |err| {
        // Its own errors are reported where they are found.
        if (err != error.LexerGenerationError) diag.err("lexer generation failed: {s}", .{@errorName(err)});
        fail();
    };

    diag.info("   Lexer: {d} tokens, {d} rules, {d} DFA states", .{
        lexerSpec.tokens.items.len,
        lexerSpec.rules.items.len,
        lexerGen.dfa.numStates,
    });

    const highlighted: ?highlight.Highlight = if (ir.highlight) |lines|
        highlight.analyze(allocator, lines, &lexerSpec, ir.keywordGroups, parsed.source) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        }
    else
        null;

    diag.info("   Parser: {d} rules, {d} start symbols", .{
        ir.rules.len,
        ir.startSymbols.len,
    });

    // Without parser rules the output is the lexer alone
    var finalCode: []const u8 = "";
    var final: ?Grammar = null;
    var coverage: []const u8 = "0 of 0 places have a message\n";
    var lsp: ?names.Lsp = null;

    if (ir.rules.len > 0) {
        var g = Grammar.init(allocator);
        // Schema mode: resolve every action against @schema first.
        var sem: ?semantics.Result = null;
        if (ir.schema != null) sem = semantics.resolve(allocator, &ir, &lexerSpec, grammarFile) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };
        // `@lsp` names the schema's kinds and roles and the lexer's tokens.
        const oneToken: names.OneToken = .{ .ctx = &lexerGen, .call = struct {
            fn call(ctx: *const anyopaque, text: []const u8) ?[]const u8 {
                const gen: *const LexerGenerator = @ptrCast(@alignCast(ctx));
                return gen.oneToken(text);
            }
        }.call };
        if (ir.lsp) |lines| lsp = names.analyze(allocator, lines, &ir.schema.?, &lexerSpec, ir.trivia, parsed.source, oneToken) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };
        expand.processGrammar(&g, &ir, .{
            .path = grammarFile,
            .resolved = if (sem) |s| s.resolved else null,
            .infix = if (sem) |s| s.infix else null,
        }) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };
        if (sem) |s| {
            g.schema = s.schema;
            semantics.checkTypes(allocator, &g, grammarFile) catch |err| {
                if (err == error.OutOfMemory) diag.err("out of memory", .{});
                fail();
            };
        }

        // Every symbol is defined, and a start symbol reaches every rule.
        if (check.validateSymbols(&g, &ir, &lexerSpec, grammarFile) > 0) fail();
        const unreached = check.checkReachable(allocator, &g, &ir, grammarFile) catch {
            diag.err("out of memory", .{});
            fail();
        };
        if (unreached > 0) fail();
        // Each lexer token's terminal, then each `X "c"` hint's.
        const unbound = check.bindTokens(&g, &lexerSpec, grammarFile) catch {
            diag.err("out of memory", .{});
            fail();
        };
        if (unbound > 0) fail();
        const unresolved = check.resolveHints(&g, &lexerSpec, grammarFile) catch {
            diag.err("out of memory", .{});
            fail();
        };
        if (unresolved > 0) fail();

        var result = lr.run(&g, .{ .path = grammarFile }) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };

        // Every check ran on the `@infix` chain; the parser is generated
        // from the folded table when it parses the same (lr.foldable).
        if (ir.infix) |decl| if (decl.ops.len > 0 and lr.foldable(&g, &result.table, decl)) {
            var folded = Grammar.init(allocator);
            const ok = fold: {
                expand.processGrammar(&folded, &ir, .{
                    .path = grammarFile,
                    .resolved = if (sem) |s| s.resolved else null,
                    .infix = if (sem) |s| s.infix else null,
                    .foldInfix = true,
                }) catch break :fold false;
                if (sem) |s| folded.schema = s.schema;
                if ((check.bindTokens(&folded, &lexerSpec, grammarFile) catch break :fold false) > 0) break :fold false;
                if ((check.resolveHints(&folded, &lexerSpec, grammarFile) catch break :fold false) > 0) break :fold false;
                const r = lr.runFolded(&folded, &g, &result.table) catch break :fold false;
                result = r orelse break :fold false;
                break :fold true;
            };
            if (ok) g = folded;
        };

        diag.info("   Generated: {d} symbols, {d} rules, {d} states", .{
            g.symbols.items.len,
            g.rules.items.len,
            result.automaton.states.items.len,
        });
        if (result.table.conflictList.len > 0)
            diag.info("   {d} conflicts (as declared)", .{result.table.conflictList.len});
        if (g.widest) |w| if (w.rules >= widestNote)
            diag.info("   Expanded: rule '{s}' (line {d}): one alternative makes {d} rules, one per combination of its [...] groups and choices", .{ w.rule, w.line, w.rules });

        // The `@messages` examples, through the table the parser has.
        const msgInput: messages.Input = .{
            .g = &g,
            .auto = &result.automaton,
            .tbl = &result.table,
            .la = &result.lookaheads,
            .spec = &lexerSpec,
            .lexer = &lexerGen,
            .path = grammarFile,
        };
        const entries: ?[]const messages.Entry = if (ir.messages) |list|
            messages.compute(allocator, msgInput, list) catch |err| {
                if (err == error.OutOfMemory) diag.err("out of memory", .{});
                fail();
            }
        else
            null;
        if (opts.coverage) {
            var report: std.Io.Writer.Allocating = .init(allocator);
            try messages.writeCoverage(allocator, &report.writer, msgInput, entries orelse &.{});
            coverage = report.written();
        }

        // `@lsp words` against the words the grammar offers itself.
        if (lsp) |*l| if (l.words.len > 0) if (highlighted) |*h| {
            const offered = try editor.grammarWords(allocator, &g, &lexerSpec, h);
            names.checkWords(l, offered, h.wordChars, parsed.source) catch fail();
        };

        final = g;
        // Emit the combined lexer + parser module (checked in check mode
        // too: codegen checks names)
        finalCode = codegen.generate(allocator, &g, &result.automaton, &result.table, &lexerSpec, lexerDecls, .{
            .emitComments = opts.emitComments,
            .spans = opts.spans,
            .completion = opts.completion,
            .source = parsed.source,
            .messages = entries,
        }) catch |err| {
            // Generation errors are reported where they are found.
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };
    } else {
        finalCode = try codegen.lexerModule(allocator, lexerSpec.langName, lexerDecls);
    }
    return .{ .ir = ir, .spec = lexerSpec, .g = final, .highlight = highlighted, .lsp = lsp, .code = finalCode, .coverage = coverage };
}

/// Exit with status 1 after the error has been reported.
fn fail() noreturn {
    std.process.exit(1);
}

fn readGrammar(allocator: Allocator, io: Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_grammar_bytes)) catch |err| {
        if (err == error.StreamTooLong) {
            diag.err("cannot read {s}: larger than {d} bytes", .{ path, max_grammar_bytes });
        } else diag.err("cannot read {s}: {s}", .{ path, @errorName(err) });
        fail();
    };
}

/// Write `bytes` to `path` (`-`: standard output) through a temporary file
/// that replaces `path` only once complete, so a failed write leaves any
/// previous file intact.
fn writeOutput(io: Io, path: []const u8, bytes: []const u8) !void {
    if (eql(path, "-")) return writeStdout(io, bytes);
    writeReplacing(io, path, bytes) catch |err| {
        diag.err("cannot write {s}: {s}", .{ path, @errorName(err) });
        fail();
    };
}

fn writeReplacing(io: Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    // A device or a pipe (/dev/null) cannot be replaced: write into it.
    const stat: ?std.Io.File.Stat = cwd.statFile(io, path, .{}) catch null;
    if (stat) |st| if (st.kind == .character_device or st.kind == .named_pipe) {
        const file = try cwd.openFile(io, path, .{ .mode = .write_only });
        defer file.close(io);
        return file.writeStreamingAll(io, bytes);
    };
    // Through a symlink, the file it names is replaced, in its own
    // directory, and keeps its mode. (Another hard link to the file keeps
    // the old contents: a replace makes a new file.)
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const target = if (stat != null) buf[0..try cwd.realPathFile(io, path, &buf)] else path;
    var af = try cwd.createFileAtomic(io, target, .{ .replace = true });
    defer af.deinit(io);
    if (stat) |st| try af.file.setPermissions(io, st.permissions);
    try af.file.writeStreamingAll(io, bytes);
    try af.replace(io);
}
