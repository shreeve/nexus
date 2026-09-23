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
}

pub fn main(init: std.process.Init) !void {
    // Nexus is a short-lived CLI: read one grammar, emit one parser, exit.
    // The process-wide arena is the idiomatic allocator for this shape:
    //
    //   - Avoids `std.heap.DebugAllocator`'s O(n) per-alloc tracking overhead,
    //     which made MUMPS generation ~700x slower in Debug (23s vs 33ms).
    //   - Keeps stderr clean (arena doesn't leak-check; previous `init.gpa` usage
    //     surfaced ~400 pre-existing "leaks" that only matter if nexus is ever
    //     embedded in a long-running process — not the current use case).
    //   - Individual `.free()` / `.deinit()` calls become harmless no-ops.
    //
    // If you ever need to hunt allocation bugs (e.g., before refactoring nexus
    // into a library), swap `init.arena.allocator()` → `init.gpa` below.
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        std.debug.print("Usage: nexus <grammar-file> [output-file]\n", .{});
        std.debug.print("       nexus check <grammar-file>\n", .{});
        std.debug.print("       nexus --help\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        std.debug.print(
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
        , .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--dump-sexp")) {
        if (args.len < 3) {
            std.debug.print("Usage: nexus --dump-sexp <grammar-file> [output-file]\n", .{});
            return;
        }
        const grammarFile = args[2];
        const outputPath: ?[]const u8 = if (args.len >= 4) args[3] else null;

        const sourceText = std.Io.Dir.cwd().readFileAlloc(io, grammarFile, allocator, .limited(max_grammar_bytes)) catch |err| {
            std.debug.print("Error reading {s}: {any}\n", .{ grammarFile, err });
            return err;
        };

        var parsed = frontend.parseGrammarSexp(allocator, sourceText) catch |err| {
            std.debug.print("❌ Failed to parse {s}: {any}\n", .{ grammarFile, err });
            if (err == error.ParseError) {
                std.debug.print("  (hint: run `./bin/nexus {s} /tmp/out.zig` for parser-generator diagnostics)\n", .{grammarFile});
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
            const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
                std.debug.print("Error creating {s}: {any}\n", .{ path, err });
                return err;
            };
            defer file.close(io);
            try file.writeStreamingAll(io, bytes);
            std.debug.print("✅ Wrote S-expression dump to {s} ({d} bytes)\n", .{ path, bytes.len });
        } else {
            std.debug.print("{s}", .{bytes});
        }
        return;
    }

    const checkMode = std.mem.eql(u8, args[1], "check") or std.mem.eql(u8, args[1], "--check");

    // Parse option flags from remaining args
    var comments = false;
    var parseMode: lookahead.ParseMode = .lalr;
    var positionalStart: usize = if (checkMode) 2 else 1;
    for (args[positionalStart..]) |arg| {
        if (std.mem.eql(u8, arg, "--comments") or std.mem.eql(u8, arg, "-c")) {
            comments = true;
            positionalStart += 1;
        } else if (std.mem.eql(u8, arg, "--slr")) {
            parseMode = .slr;
            positionalStart += 1;
        } else break;
    }

    const grammarFile = if (positionalStart < args.len) args[positionalStart] else {
        std.debug.print("Usage: nexus <grammar-file> [output-file]\n", .{});
        return;
    };
    const outputFile = if (positionalStart + 1 < args.len) args[positionalStart + 1] else "src/parser.zig";

    // Read grammar file
    const sourceText = std.Io.Dir.cwd().readFileAlloc(io, grammarFile, allocator, .limited(max_grammar_bytes)) catch |err| {
        std.debug.print("Error reading {s}: {any}\n", .{ grammarFile, err });
        return err;
    };

    std.debug.print("📖 Reading grammar from {s}\n", .{grammarFile});

    // Find @lexer section
    const lexerStart = frontend.findSection(sourceText, "@lexer");
    if (lexerStart == null) {
        std.debug.print("❌ No @lexer section found in {s}\n", .{grammarFile});
        return;
    }

    // Parse lexer section
    var lexerParser = LexerParser.init(allocator, sourceText[lexerStart.? + 6 ..]);
    defer lexerParser.deinit();

    lexerParser.parseLexerSection() catch |err| {
        std.debug.print("❌ Lexer parse error at line {d}: {any}\n", .{ lexerParser.line, err });
        return;
    };

    std.debug.print("   Lexer: {d} states, {d} tokens, {d} rules\n", .{
        lexerParser.spec.states.items.len,
        lexerParser.spec.tokens.items.len,
        lexerParser.spec.rules.items.len,
    });

    // The lexer generator needs @lang before the @parser section is parsed
    if (frontend.scanLangDirective(sourceText)) |name| lexerParser.spec.langName = name;

    // Generate lexer code
    var lexerGen = LexerGenerator.init(allocator, &lexerParser.spec);
    defer lexerGen.deinit();

    const lexerCode = lexerGen.generate() catch |err| {
        std.debug.print("❌ Lexer generation error: {any}\n", .{err});
        return;
    };

    // Find @parser section
    const parserStart = frontend.findSection(sourceText, "@parser");
    if (parserStart == null) {
        std.debug.print("❌ No @parser section found in {s}\n", .{grammarFile});
        return;
    }
    var finalCode: []const u8 = lexerCode;

    if (parserStart) |ps| {
        _ = ps;
        std.debug.print("   Parsing @parser section...\n", .{});

        // Parse the @parser section through the self-hosted frontend and
        // lower the resulting S-expression tree into GrammarIR. The lowerer
        // extracts text from .src nodes into slices backed by sourceText
        // (which outlives main), so the parser's arena is freed as soon as
        // lowering returns.
        var parsed = frontend.parseGrammarSexp(allocator, sourceText) catch |err| {
            std.debug.print("❌ Failed to parse @parser section: {any}\n", .{err});
            return;
        };
        defer parsed.parser.deinit();

        var ir = GrammarLowerer.lower(allocator, parsed.sexp, parsed.parserBody) catch |err| {
            std.debug.print("❌ Lowerer error: {any}\n", .{err});
            return;
        };

        if (ir.lang == null) ir.lang = lexerParser.spec.langName;

        std.debug.print("   Parser: {d} rules, {d} start symbols\n", .{
            ir.rules.len,
            ir.startSymbols.len,
        });

        // Run semantic checks
        if (checkMode) {
            std.debug.print("\n🔍 Checking grammar...\n", .{});
            const checkErrors = check.checkGrammar(allocator, &ir);
            if (checkErrors > 0) return;
            return;
        }

        // Only generate parser if there are rules
        if (ir.rules.len > 0) {
            var g = Grammar.init(allocator);
            defer g.deinit();
            expand.processGrammar(&g, &ir) catch |err| {
                std.debug.print("❌ Grammar processing error: {any}\n", .{err});
                return;
            };

            // Validate all referenced symbols are defined
            const validationErrors = check.validateSymbols(&g, &lexerParser.spec);
            if (validationErrors > 0) {
                std.debug.print("❌ Found {d} undefined symbol(s)\n", .{validationErrors});
                return;
            }

            var auto = automaton.build(&g) catch |err| {
                std.debug.print("❌ Automaton build error: {any}\n", .{err});
                return;
            };
            defer auto.deinit(allocator);

            const la = lookahead.compute(&g, &auto, parseMode) catch |err| {
                std.debug.print("❌ Lookahead computation error: {any}\n", .{err});
                return;
            };

            std.debug.print("   Generated: {d} symbols, {d} rules, {d} states\n", .{
                g.symbols.items.len,
                g.rules.items.len,
                auto.states.items.len,
            });

            // Build the parse table (resolves and records conflicts), then
            // emit the combined lexer + parser module
            const tbl = table.build(&g, &auto, la) catch |err| {
                std.debug.print("❌ Parser generation error: {any}\n", .{err});
                return;
            };
            finalCode = codegen.generate(allocator, &g, &auto, &tbl, &lexerParser.spec, lexerCode, comments) catch |err| {
                std.debug.print("❌ Parser generation error: {any}\n", .{err});
                return;
            };

            conflicts.report(allocator, &tbl, g.expectConflicts);
        }
    }

    // Write output
    const file = std.Io.Dir.cwd().createFile(io, outputFile, .{}) catch |err| {
        std.debug.print("Error creating {s}: {any}\n", .{ outputFile, err });
        return err;
    };
    defer file.close(io);

    try file.writeStreamingAll(io, finalCode);

    std.debug.print("✅ Generated: {s}\n", .{outputFile});
}
