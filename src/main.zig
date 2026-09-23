//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [--slr] [-c] <grammar-file> [output-file]
//!        nexus check <grammar-file>
//!        nexus --dump-sexp <grammar-file> [output-file]
//!
//! Pipeline: frontend (lexer section + self-hosted @parser section, lowered
//! to GrammarIR) -> lexgen (lexer source) -> expand (desugared Grammar) ->
//! lr (automaton, lookaheads, table) -> codegen (the parser module).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const diag = @import("diag.zig");
const frontend = @import("frontend/frontend.zig");
const LexerParser = frontend.LexerParser;
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
    _ = @import("lr/lr.zig");
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
    \\      --dump-sexp Parse the @parser section via the self-hosted
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
        return;
    }

    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        std.debug.print(help, .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--dump-sexp")) {
        if (args.len < 3) {
            std.debug.print("Usage: nexus --dump-sexp <grammar-file> [output-file]\n", .{});
            return;
        }
        return dumpSexp(allocator, io, args[2], if (args.len >= 4) args[3] else null);
    }

    const checkMode = std.mem.eql(u8, args[1], "check") or std.mem.eql(u8, args[1], "--check");

    // Parse option flags from remaining args
    var opts: Options = .{ .checkMode = checkMode, .grammarFile = undefined, .outputFile = undefined };
    var positionalStart: usize = if (checkMode) 2 else 1;
    for (args[positionalStart..]) |arg| {
        if (std.mem.eql(u8, arg, "--comments") or std.mem.eql(u8, arg, "-c")) {
            opts.emitComments = true;
            positionalStart += 1;
        } else if (std.mem.eql(u8, arg, "--slr")) {
            opts.parseMode = .slr;
            positionalStart += 1;
        } else break;
    }

    opts.grammarFile = if (positionalStart < args.len) args[positionalStart] else {
        std.debug.print("Usage: nexus <grammar-file> [output-file]\n", .{});
        return;
    };
    opts.outputFile = if (positionalStart + 1 < args.len) args[positionalStart + 1] else "src/parser.zig";

    return generate(allocator, io, opts);
}

/// `nexus --dump-sexp`: print the frontend's canonical tree for the @parser section.
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
    try frontend.dumpSexp(writer, parsed.sexp, parsed.parserBody, 0);
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

    // Lexer section
    const lexerStart = frontend.findSection(sourceText, "@lexer") orelse {
        diag.err("no @lexer section found in {s}", .{grammarFile});
        return;
    };

    var lexerParser = LexerParser.init(allocator, sourceText[lexerStart + 6 ..]);
    defer lexerParser.deinit();

    lexerParser.parseLexerSection() catch |err| {
        diag.err("lexer parse error at line {d}: {any}", .{ lexerParser.line, err });
        return;
    };

    diag.info("   Lexer: {d} states, {d} tokens, {d} rules", .{
        lexerParser.spec.states.items.len,
        lexerParser.spec.tokens.items.len,
        lexerParser.spec.rules.items.len,
    });

    // The lexer generator needs @lang before the @parser section is parsed
    if (frontend.scanLangDirective(sourceText)) |name| lexerParser.spec.langName = name;

    var lexerGen = LexerGenerator.init(allocator, &lexerParser.spec);
    defer lexerGen.deinit();

    const lexerCode = lexerGen.generate() catch |err| {
        diag.err("lexer generation failed: {any}", .{err});
        return;
    };

    // Parser section: parse it through the self-hosted frontend and lower the
    // resulting S-expression tree into GrammarIR. The IR's strings are slices
    // of sourceText.
    if (frontend.findSection(sourceText, "@parser") == null) {
        diag.err("no @parser section found in {s}", .{grammarFile});
        return;
    }
    diag.info("   Parsing @parser section...", .{});

    var parsed = frontend.parseGrammarSexp(allocator, sourceText, grammarFile) catch |err| {
        if (err != error.ParseError) diag.err("failed to parse the @parser section of {s}: {any}", .{ grammarFile, err });
        fail();
    };
    defer parsed.parser.deinit();

    var ir = GrammarLowerer.lower(allocator, parsed.sexp, parsed.source) catch |err| {
        if (err == error.OutOfMemory) diag.err("out of memory", .{});
        fail();
    };

    if (ir.lang == null) ir.lang = lexerParser.spec.langName;

    diag.info("   Parser: {d} rules, {d} start symbols", .{
        ir.rules.len,
        ir.startSymbols.len,
    });

    if (opts.checkMode) {
        diag.info("\nChecking grammar...", .{});
        var failed = check.checkGrammar(allocator, &ir) > 0;
        if (ir.schema != null) {
            _ = semantics.resolve(allocator, &ir, &lexerParser.spec, grammarFile) catch {
                failed = true;
            };
        }
        if (failed) fail();
        return;
    }

    // Without parser rules the output is the lexer alone
    var finalCode: []const u8 = lexerCode;

    if (ir.rules.len > 0) {
        var g = Grammar.init(allocator);
        defer g.deinit();
        // Schema mode: resolve every action against @schema first.
        var sem: ?semantics.Result = null;
        if (ir.schema != null) sem = semantics.resolve(allocator, &ir, &lexerParser.spec, grammarFile) catch |err| {
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
        const validationErrors = check.validateSymbols(&g, &lexerParser.spec);
        if (validationErrors > 0) {
            diag.err("found {d} undefined symbol(s)", .{validationErrors});
            return;
        }

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
        finalCode = codegen.generate(allocator, &g, &result.automaton, &result.table, &lexerParser.spec, lexerCode, opts.emitComments) catch |err| {
            diag.err("parser generation failed: {any}", .{err});
            return;
        };
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
        diag.err("cannot read {s}: {any}", .{ path, err });
        return err;
    };
}

fn writeOutput(io: Io, path: []const u8, bytes: []const u8) !void {
    const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
        diag.err("cannot create {s}: {any}", .{ path, err });
        return err;
    };
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}
