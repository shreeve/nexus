//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [options] <grammar-file> <output-file>
//!        nexus check <grammar-file>
//!        nexus --dump-sexp <grammar-file> [output-file]
//!        nexus --help | --version
//!
//! Pipeline: frontend (the self-hosted grammar-file parser, lowered to the
//! lexer spec and GrammarIR) -> lexgen (lexer source) -> semantics (with
//! @schema: actions resolved against the schema) -> expand (desugared
//! Grammar) -> semantics.checkTypes (with @schema) -> check (defined
//! symbols, reachable rules, token binding, `X "c"` hint resolution) -> lr
//! (automaton, lookaheads, table) -> codegen (the parser module).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const diag = @import("diag.zig");
const frontend = @import("frontend/frontend.zig");
const GrammarLowerer = frontend.GrammarLowerer;
const LexerGenerator = @import("lexgen/lexgen.zig").LexerGenerator;
const Grammar = @import("grammar.zig").Grammar;
const expand = @import("expand.zig");
const semantics = @import("semantics.zig");
const check = @import("check.zig");
const lr = @import("lr/lr.zig");
const codegen = @import("codegen/codegen.zig");

const max_grammar_bytes: usize = 1 << 20; // 1 MiB cap for .grammar file reads

test {
    _ = @import("diag.zig");
    _ = @import("grammar.zig");
    _ = @import("frontend/lower.zig");
    _ = @import("semantics.zig");
    _ = @import("lexgen/lexgen.zig");
    _ = @import("lr/lr.zig");
    _ = @import("codegen/runtime.zig");
    _ = @import("codegen/codegen.zig");
}

const usage =
    \\Usage: nexus [options] <grammar-file> <output-file>
    \\       nexus check <grammar-file>
    \\       nexus --dump-sexp <grammar-file> [output-file]
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
    \\  check           Check the grammar without writing anything
    \\  --dump-sexp     Write the frontend's S-expression tree of the grammar
    \\                  file to output-file (default: standard output)
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
    \\
;

const version = @import("version.zig").version;

const Options = struct {
    checkMode: bool = false,
    emitComments: bool = false,
    spans: bool = false,
    grammarFile: []const u8,
    outputFile: []const u8,
};

pub fn main(init: std.process.Init) !void {
    // Nexus is a short-lived CLI: read one grammar, emit one parser, exit.
    // Everything lives in the process arena and is freed at exit.
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    var command: enum { generate, check, dump } = .generate;
    var opts: Options = .{ .grammarFile = undefined, .outputFile = undefined };
    var positional: [2][]const u8 = undefined;
    var count: usize = 0;
    var generationOption: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (eql(arg, "-h") or eql(arg, "--help")) {
            return writeStdout(io, help);
        } else if (eql(arg, "-V") or eql(arg, "--version")) {
            return writeStdout(io, "nexus " ++ version ++ "\n");
        } else if (eql(arg, "--dump-sexp")) {
            if (command == .check) usageError("--dump-sexp and check are separate commands", .{});
            command = .dump;
        } else if (eql(arg, "-c") or eql(arg, "--comments")) {
            opts.emitComments = true;
            generationOption = arg;
        } else if (eql(arg, "--spans")) {
            opts.spans = true;
            generationOption = arg;
        } else if (count == 0 and eql(arg, "check")) {
            if (command == .dump) usageError("--dump-sexp and check are separate commands", .{});
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
        .dump => {
            if (generationOption) |o| usageError("{s} has no effect on --dump-sexp", .{o});
            return dumpSexp(allocator, io, positional[0], output orelse "-");
        },
        .check => {
            if (output) |path| usageError("`nexus check` writes nothing; unexpected '{s}'", .{path});
            opts.checkMode = true;
        },
        .generate => opts.outputFile = output orelse usageError("no output file given (nexus <grammar-file> <output-file>)", .{}),
    }
    opts.grammarFile = positional[0];
    return generate(allocator, io, opts);
}

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

/// `nexus [check] <grammar>`: run the pipeline and write the parser module
/// (in check mode, write nothing).
fn generate(allocator: Allocator, io: Io, opts: Options) !void {
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

    diag.info("   Parser: {d} rules, {d} start symbols", .{
        ir.rules.len,
        ir.startSymbols.len,
    });

    // Without parser rules the output is the lexer alone
    var finalCode: []const u8 = undefined;

    if (ir.rules.len > 0) {
        var g = Grammar.init(allocator);
        // Schema mode: resolve every action against @schema first.
        var sem: ?semantics.Result = null;
        if (ir.schema != null) sem = semantics.resolve(allocator, &ir, &lexerSpec, grammarFile) catch |err| {
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

        diag.info("   Generated: {d} symbols, {d} rules, {d} states", .{
            g.symbols.items.len,
            g.rules.items.len,
            result.automaton.states.items.len,
        });
        if (result.table.conflictList.len > 0)
            diag.info("   {d} conflicts (as declared)", .{result.table.conflictList.len});

        // Emit the combined lexer + parser module
        finalCode = codegen.generate(allocator, &g, &result.automaton, &result.table, &lexerSpec, lexerDecls, .{
            .emitComments = opts.emitComments,
            .spans = opts.spans,
            .source = parsed.source,
        }) catch |err| {
            // Generation errors are reported where they are found.
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            fail();
        };
    } else {
        finalCode = try codegen.lexerModule(allocator, lexerSpec.langName, lexerDecls);
    }

    if (opts.checkMode) {
        diag.info("{s}: no errors", .{grammarFile});
        return;
    }
    try writeOutput(io, opts.outputFile, finalCode);
    diag.info("Generated: {s}", .{if (eql(opts.outputFile, "-")) "standard output" else opts.outputFile});
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
