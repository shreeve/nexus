//! nexus — generate a standalone Zig lexer + LR parser from a .grammar file.
//!
//! Usage: nexus [--slr] [--spans] [-c] <grammar-file> [output-file]
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
const check = @import("check.zig");
const automaton = @import("lr/automaton.zig");
const lookahead = @import("lr/lookahead.zig");
const table = @import("lr/table.zig");
const conflicts = @import("lr/conflicts.zig");
const codegen = @import("codegen/codegen.zig");

const max_grammar_bytes: usize = 1 << 20; // 1 MiB cap for .grammar file reads

test {
    _ = @import("frontend/lower.zig");
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
    spans: bool = false,
    parseMode: lookahead.ParseMode = .lalr,
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
        } else if (std.mem.eql(u8, arg, "--spans")) {
            opts.spans = true;
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

    var parsed = frontend.parseGrammarSexp(allocator, sourceText) catch |err| {
        diag.err("failed to parse {s}: {any}", .{ grammarFile, err });
        if (err == error.ParseError) {
            diag.info("  (hint: run `./bin/nexus {s} /tmp/out.zig` for parser-generator diagnostics)", .{grammarFile});
        }
        return;
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

    const lexerDecls = lexerGen.generateDecls() catch |err| {
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

    var parsed = frontend.parseGrammarSexp(allocator, sourceText) catch |err| {
        diag.err("failed to parse @parser section: {any}", .{err});
        return;
    };
    defer parsed.parser.deinit();

    var ir = GrammarLowerer.lower(allocator, parsed.sexp, parsed.parserBody) catch |err| {
        diag.err("lowering failed: {any}", .{err});
        return;
    };

    if (ir.lang == null) ir.lang = lexerParser.spec.langName;

    diag.info("   Parser: {d} rules, {d} start symbols", .{
        ir.rules.len,
        ir.startSymbols.len,
    });

    if (opts.checkMode) {
        diag.info("\nChecking grammar...", .{});
        _ = check.checkGrammar(allocator, &ir);
        return;
    }

    // Without parser rules the output is the lexer alone
    var finalCode: []const u8 = undefined;

    if (ir.rules.len > 0) {
        var g = Grammar.init(allocator);
        defer g.deinit();
        expand.processGrammar(&g, &ir) catch |err| {
            diag.err("grammar processing failed: {any}", .{err});
            return;
        };

        // Validate all referenced symbols are defined
        const validationErrors = check.validateSymbols(&g, &lexerParser.spec);
        if (validationErrors > 0) {
            diag.err("found {d} undefined symbol(s)", .{validationErrors});
            return;
        }

        var auto = automaton.build(&g) catch |err| {
            diag.err("automaton construction failed: {any}", .{err});
            return;
        };
        defer auto.deinit(allocator);

        const la = lookahead.compute(&g, &auto, opts.parseMode) catch |err| {
            diag.err("lookahead computation failed: {any}", .{err});
            return;
        };

        diag.info("   Generated: {d} symbols, {d} rules, {d} states", .{
            g.symbols.items.len,
            g.rules.items.len,
            auto.states.items.len,
        });

        // Build the parse table (resolves and records conflicts), then emit
        // the combined lexer + parser module
        const tbl = table.build(&g, &auto, la) catch |err| {
            diag.err("parser generation failed: {any}", .{err});
            return;
        };
        finalCode = codegen.generate(allocator, &g, &auto, &tbl, &lexerParser.spec, lexerDecls, .{
            .emitComments = opts.emitComments,
            .spans = opts.spans,
        }) catch |err| {
            diag.err("parser generation failed: {any}", .{err});
            return;
        };

        conflicts.report(allocator, &tbl, g.expectConflicts);
    } else {
        finalCode = try codegen.lexerModule(allocator, lexerParser.spec.langName, lexerDecls);
    }

    try writeOutput(io, opts.outputFile, finalCode);
    diag.info("Generated: {s}", .{opts.outputFile});
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
