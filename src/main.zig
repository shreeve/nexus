//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [options] <grammar-file> [output-file]
//!        nexus check <grammar-file>
//!        nexus --dump-sexp <grammar-file> [output-file]
//!        nexus --help | --version
//!
//! Pipeline: frontend (the self-hosted grammar-file parser, lowered to the
//! lexer spec and GrammarIR) -> lexgen (lexer source) -> expand (desugared
//! Grammar) -> lr (automaton, lookaheads, table) -> codegen (the parser
//! module).

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
    _ = @import("frontend/lower.zig");
    _ = @import("semantics.zig");
    _ = @import("lexgen/lexgen.zig");
    _ = @import("lr/lr.zig");
    _ = @import("codegen/runtime.zig");
    _ = @import("codegen/codegen.zig");
}

const usage =
    \\Usage: nexus [options] <grammar-file> [output-file]
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
    \\  <grammar-file> [output-file]
    \\                  Generate the parser module (default output:
    \\                  src/parser.zig)
    \\  check           Check the grammar without writing anything
    \\  --dump-sexp     Write the frontend's S-expression tree of the grammar
    \\                  file to output-file (default: standard output)
    \\
    \\Options:
    \\  --spans         Record node spans and rule ids (always on with @schema)
    \\  --slr           Build SLR(1) tables instead of LALR(1)
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
    parseMode: lr.ParseMode = .lalr,
    grammarFile: []const u8,
    outputFile: []const u8,
};

pub fn main(init: std.process.Init) !void {
    // Nexus is a short-lived CLI: read one grammar, emit one parser, exit.
    // Everything is allocated from the process arena (no per-allocation
    // tracking cost; `free`/`deinit` calls are no-ops). Swap in `init.gpa`
    // to hunt allocation bugs.
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    var command: enum { generate, check, dump } = .generate;
    var opts: Options = .{ .grammarFile = undefined, .outputFile = "src/parser.zig" };
    var positional: [2][]const u8 = undefined;
    var count: usize = 0;
    for (args[1..], 1..) |arg, i| {
        if (eql(arg, "-h") or eql(arg, "--help")) {
            return writeStdout(io, help);
        } else if (eql(arg, "-V") or eql(arg, "--version")) {
            return writeStdout(io, "nexus " ++ version ++ "\n");
        } else if (eql(arg, "--dump-sexp")) {
            command = .dump;
        } else if (eql(arg, "-c") or eql(arg, "--comments")) {
            opts.emitComments = true;
        } else if (eql(arg, "--slr")) {
            opts.parseMode = .slr;
        } else if (eql(arg, "--spans")) {
            opts.spans = true;
        } else if (i == 1 and eql(arg, "check")) {
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

    switch (command) {
        .dump => return dumpSexp(allocator, io, positional[0], if (count == 2) positional[1] else null),
        .check => {
            if (count == 2) usageError("`nexus check` writes nothing; unexpected '{s}'", .{positional[1]});
            opts.checkMode = true;
        },
        .generate => if (count == 2) {
            opts.outputFile = positional[1];
        },
    }
    opts.grammarFile = positional[0];
    return generate(allocator, io, opts);
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

fn writeStdout(io: Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

/// `nexus --dump-sexp`: print the frontend's canonical tree of the grammar file.
fn dumpSexp(allocator: Allocator, io: Io, grammarFile: []const u8, outputPath: ?[]const u8) !void {
    const sourceText = try readGrammar(allocator, io, grammarFile);

    var parsed = frontend.parseGrammarSexp(allocator, sourceText, grammarFile) catch |err| {
        if (err != error.ParseError) diag.err("failed to parse {s}: {any}", .{ grammarFile, err });
        fail();
    };
    defer parsed.parser.deinit();

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try frontend.dumpSexp(writer, parsed.sexp, sourceText, 0);
    try writer.writeByte('\n');
    const bytes = writer.buffered();

    if (outputPath) |path| {
        try writeOutput(io, path, bytes);
        diag.info("Wrote S-expression dump to {s} ({d} bytes)", .{ path, bytes.len });
    } else {
        try writeStdout(io, bytes);
    }
}

/// `nexus [check] <grammar>`: run the pipeline and write the parser module
/// (in check mode, also lint the grammar IR, and write nothing).
fn generate(allocator: Allocator, io: Io, opts: Options) !void {
    const grammarFile = opts.grammarFile;
    const sourceText = try readGrammar(allocator, io, grammarFile);

    diag.info("Reading grammar from {s}", .{grammarFile});

    // The whole file through the self-hosted frontend, lowered into the
    // lexer spec and GrammarIR (whose strings are slices of sourceText).
    var parsed = frontend.parseGrammarSexp(allocator, sourceText, grammarFile) catch |err| {
        if (err != error.ParseError) diag.err("failed to parse {s}: {any}", .{ grammarFile, err });
        fail();
    };
    defer parsed.parser.deinit();

    var ir = GrammarLowerer.lower(allocator, parsed.sexp, parsed.source) catch |err| {
        if (err == error.OutOfMemory) diag.err("out of memory", .{});
        fail();
    };
    var lexerSpec = ir.lexer orelse {
        diag.errLine(grammarFile, 1, 1, "no @lexer section (a grammar file has an @lexer section, then an @parser section)", .{});
        fail();
    };
    if (!ir.hasParser) {
        const end = parsed.source.at(sourceText.len);
        diag.errLine(grammarFile, end.line, end.col, "no @parser section (a grammar file ends with an @parser section, which may be empty)", .{});
        fail();
    }
    lexerSpec.langName = ir.lang;

    diag.info("   Lexer: {d} states, {d} tokens, {d} rules", .{
        lexerSpec.states.items.len,
        lexerSpec.tokens.items.len,
        lexerSpec.rules.items.len,
    });

    var lexerGen = LexerGenerator.init(allocator, &lexerSpec);
    defer lexerGen.deinit();

    const lexerDecls = lexerGen.generateDecls() catch |err| switch (err) {
        error.LexerGenerationError => std.process.exit(1),
        else => {
            diag.err("lexer generation failed: {any}", .{err});
            std.process.exit(1);
        },
    };

    diag.info("   Parser: {d} rules, {d} start symbols", .{
        ir.rules.len,
        ir.startSymbols.len,
    });

    // Check mode: the lint (unreachable rules, as warnings), then every
    // check generation makes; nothing is written.
    const warnings = if (opts.checkMode) check.checkGrammar(allocator, &ir, grammarFile) else 0;

    // Without parser rules the output is the lexer alone
    var finalCode: []const u8 = undefined;

    if (ir.rules.len > 0) {
        var g = Grammar.init(allocator);
        defer g.deinit();
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

        // Validate all referenced symbols are defined
        if (check.validateSymbols(&g, &lexerSpec, grammarFile) > 0) fail();

        var result = lr.run(&g, .{
            .mode = opts.parseMode,
            .path = grammarFile,
        }) catch |err| {
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            std.process.exit(1);
        };
        defer result.automaton.deinit(allocator);

        diag.info("   Generated: {d} symbols, {d} rules, {d} states", .{
            g.symbols.items.len,
            g.rules.items.len,
            result.automaton.states.items.len,
        });
        if (result.table.conflicts > 0)
            diag.info("   {d} conflicts (as declared)", .{result.table.conflicts});

        // Emit the combined lexer + parser module
        finalCode = codegen.generate(allocator, &g, &result.automaton, &result.table, &lexerSpec, lexerDecls, .{
            .emitComments = opts.emitComments,
            .spans = opts.spans,
            .source = .{ .path = grammarFile, .text = sourceText },
        }) catch |err| {
            // Generation errors are reported where they are found.
            if (err == error.OutOfMemory) diag.err("out of memory", .{});
            std.process.exit(1);
        };
    } else {
        finalCode = try codegen.lexerModule(allocator, lexerSpec.langName, lexerDecls);
    }

    if (opts.checkMode) {
        if (warnings > 0) diag.info("{s}: no errors ({d} warnings)", .{ grammarFile, warnings }) else diag.info("{s}: no errors", .{grammarFile});
        return;
    }
    try writeOutput(io, opts.outputFile, finalCode);
    diag.info("Generated: {s}", .{opts.outputFile});
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

fn writeOutput(io: Io, path: []const u8, bytes: []const u8) !void {
    const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
        diag.err("cannot create {s}: {s}", .{ path, @errorName(err) });
        fail();
    };
    defer file.close(io);
    file.writeStreamingAll(io, bytes) catch |err| {
        diag.err("cannot write {s}: {s}", .{ path, @errorName(err) });
        fail();
    };
}
