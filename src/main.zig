//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [--slr] [--spans] [-c] <grammar-file> [output-file]
//!        nexus check <grammar-file>
//!        nexus --dump-sexp <grammar-file> [output-file]
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
    \\Usage: nexus <grammar-file> [output-file]
    \\       nexus check <grammar-file>
    \\       nexus --help
    \\
;

const help =
    \\nexus — Universal Parser Generator
    \\
    \\Reads a .grammar file with @lexer and @parser sections and generates
    \\a combined parser.zig module containing both lexer and parser.
    \\
    \\Usage: nexus <grammar-file> [output-file]
    \\       nexus check <grammar-file>
    \\       nexus --dump-sexp <grammar-file> [output-file]
    \\
    \\Options:
    \\  -c, --comments  Include grammar-rule comments in generated code
    \\      --slr       Use SLR(1) instead of LALR(1) for parse tables
    \\      --spans     Record node spans and rule ids in the generated
    \\                  parser (always on for grammars with @schema)
    \\      --dump-sexp Parse the grammar file with the self-hosted
    \\                  frontend and write its canonical S-expression
    \\                  tree to the output file (or stdout)
    \\  -h, --help      Show this help
    \\
    \\Examples:
    \\  nexus lang.grammar src/parser.zig
    \\  nexus --dump-sexp nexus.grammar test/golden/nexus.sexp
    \\
;

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

    if (args.len < 2) {
        std.debug.print(usage, .{});
        fail();
    }

    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        std.debug.print(help, .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--dump-sexp")) {
        if (args.len < 3 or args.len > 4) {
            std.debug.print("Usage: nexus --dump-sexp <grammar-file> [output-file]\n", .{});
            fail();
        }
        return dumpSexp(allocator, io, args[2], if (args.len >= 4) args[3] else null);
    }

    const checkMode = std.mem.eql(u8, args[1], "check") or std.mem.eql(u8, args[1], "--check");

    // Options may come before or after the file names; anything else that
    // starts with `-` is an error, never a file name or silently ignored.
    var opts: Options = .{ .checkMode = checkMode, .grammarFile = undefined, .outputFile = undefined };
    var positionals: [2][]const u8 = undefined;
    var count: usize = 0;
    const maxPositionals: usize = if (checkMode) 1 else 2;
    for (args[if (checkMode) 2 else 1..]) |arg| {
        if (std.mem.eql(u8, arg, "--comments") or std.mem.eql(u8, arg, "-c")) {
            opts.emitComments = true;
        } else if (std.mem.eql(u8, arg, "--slr")) {
            opts.parseMode = .slr;
        } else if (std.mem.eql(u8, arg, "--spans")) {
            opts.spans = true;
        } else if (arg.len > 1 and arg[0] == '-') {
            diag.err("unknown option '{s}' (see nexus --help)", .{arg});
            fail();
        } else if (count == maxPositionals) {
            diag.err("unexpected argument '{s}'", .{arg});
            std.debug.print(usage, .{});
            fail();
        } else {
            positionals[count] = arg;
            count += 1;
        }
    }
    if (count == 0) {
        std.debug.print(usage, .{});
        fail();
    }
    opts.grammarFile = positionals[0];
    opts.outputFile = if (count > 1) positionals[1] else "src/parser.zig";

    return generate(allocator, io, opts);
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
        std.debug.print("{s}", .{bytes});
    }
}

/// `nexus [check] <grammar>`: run the pipeline and write the parser module
/// (or, in check mode, lint the grammar IR and stop).
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

    // `check`: lint, then everything generation checks, without output.
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
        if (warnings > 0) diag.info("{d} warning(s); no errors", .{warnings}) else diag.info("No issues found", .{});
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
