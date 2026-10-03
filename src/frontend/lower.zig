//! Lowering of the frontend's S-expression tree into the lexer spec and the
//! grammar IR.
//!
//! The tree's shapes are declared by the @schema block of nexus.grammar, a
//! schema-mode grammar: generating parser.zig proves that every node the
//! frontend builds has its kind's slots with the declared types. The
//! lowerer reads the tree through the generated `parser.ir` accessors, so a
//! schema change is a compile error here, and checks only meaning: the
//! mistakes the tree can express (an unknown associativity, a position 0, a
//! missing conflict rationale, ...), each reported at a source position as
//! `error.LowerError`. There are no silent defaults.

const std = @import("std");
const diag = @import("../diag.zig");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Sexp = parser.Sexp;
const ir = parser.ir;
const grammar = @import("../grammar.zig");
const GrammarIR = grammar.GrammarIR;
const ParsedRule = grammar.ParsedRule;
const ParsedAlternative = grammar.ParsedAlternative;
const ParsedElement = grammar.ParsedElement;
const InfixDecl = grammar.InfixDecl;
const InfixOp = grammar.InfixOp;
const AsDirective = grammar.AsDirective;
const OpMapping = grammar.OpMapping;
const ErrorName = grammar.ErrorName;
const Schema = grammar.Schema;
const ActionTree = grammar.ActionTree;
const ActionList = grammar.ActionList;
const ActionItem = grammar.ActionItem;
const ActionElem = grammar.ActionElem;
const ConflictEntry = grammar.ConflictEntry;
const DisplayName = grammar.DisplayName;
const LexerSpec = grammar.LexerSpec;
const LexerRule = grammar.LexerRule;
const Guard = grammar.Guard;
const Action = grammar.Action;
const regex = @import("../lexgen/regex.zig");

pub const LowerError = error{ LowerError, OutOfMemory };

pub const GrammarLowerer = struct {
    allocator: Allocator,
    /// The grammar file; `.src` positions are offsets into its text.
    source: diag.Source,
    /// The parser that built the tree: its node spans locate a node that
    /// has no leaf (an empty `@conflicts`).
    spans: ?*const parser.Parser = null,

    /// Where the entries are: before any section marker, in @lexer, or in
    /// @parser. A tree without markers is @parser-section text.
    section: enum { preamble, lexer, parser } = .preamble,
    sectioned: bool = false,
    lexer: ?LexerSpec = null,
    /// Position of the first `tokens` keyword.
    tokensAt: ?u32 = null,
    hasParser: bool = false,
    scratch: std.ArrayList(u8) = .empty,

    rules: std.ArrayList(ParsedRule) = .empty,
    startSymbols: std.ArrayList([]const u8) = .empty,
    asDirectives: std.ArrayList(AsDirective) = .empty,
    opMappings: std.ArrayList(OpMapping) = .empty,
    errorNames: std.ArrayList(ErrorName) = .empty,
    displayNames: std.ArrayList(DisplayName) = .empty,
    infixOps: std.ArrayList(InfixOp) = .empty,
    infixBase: ?[]const u8 = null,
    infixLoc: diag.Source.Loc = .{ .line = 0, .col = 0 },
    lang: ?[]const u8 = null,
    conflicts: std.ArrayList(ConflictEntry) = .empty,
    kinds: std.ArrayList(Schema.Kind) = .empty,
    hasSchema: bool = false,
    /// The directives seen so far.
    directives: std.EnumSet(parser.Tag) = .empty,
    extraTags: std.ArrayList([]const u8) = .empty,
    tagsNode: ?Sexp = null,
    /// The first `@code = f` line.
    codeNode: ?Sexp = null,
    trivia: std.ArrayList([]const u8) = .empty,
    repair: ?grammar.RepairSpec = null,

    /// Lowers a parsed grammar file.
    pub fn lowerParsed(allocator: Allocator, parsed: *const @import("frontend.zig").Parsed) LowerError!GrammarIR {
        return lowerTree(.{ .allocator = allocator, .source = parsed.source, .spans = &parsed.parser }, parsed.sexp);
    }

    /// Lowers `sexp`, the tree of `source`.
    pub fn lower(allocator: Allocator, sexp: Sexp, source: diag.Source) LowerError!GrammarIR {
        return lowerTree(.{ .allocator = allocator, .source = source }, sexp);
    }

    fn lowerTree(lowerer: GrammarLowerer, sexp: Sexp) LowerError!GrammarIR {
        var self = lowerer;
        const allocator = self.allocator;
        const source = self.source;
        try self.lowerRoot(sexp);
        if (self.section == .lexer) try self.validateLexer(@intCast(source.text.len));
        if (self.lexer) |*spec| spec.langName = self.lang;
        if (self.codeNode) |node| if (self.lang == null)
            return self.fail(node, "@code = {s} needs @lang (the function is imported from the lang module)", .{self.text(ir.Code.name(node))});
        if (self.tagsNode) |node| if (!self.hasSchema)
            return self.fail(node, "@tags lists extra schema tags; it needs an @schema", .{});
        // Without a `name!` rule, the first rule is the start symbol.
        if (self.startSymbols.items.len == 0 and self.rules.items.len > 0)
            try self.startSymbols.append(allocator, self.rules.items[0].name);
        return GrammarIR{
            .rules = try self.rules.toOwnedSlice(allocator),
            .startSymbols = try self.startSymbols.toOwnedSlice(allocator),
            .asDirectives = try self.asDirectives.toOwnedSlice(allocator),
            .opMappings = try self.opMappings.toOwnedSlice(allocator),
            .errorNames = try self.errorNames.toOwnedSlice(allocator),
            .infix = if (self.infixBase) |base| InfixDecl{
                .baseRule = base,
                .ops = try self.infixOps.toOwnedSlice(allocator),
                .line = self.infixLoc.line,
                .col = self.infixLoc.col,
            } else null,
            .lang = self.lang,
            .schema = if (self.hasSchema) Schema{
                .kinds = try self.kinds.toOwnedSlice(allocator),
                .extraTags = try self.extraTags.toOwnedSlice(allocator),
            } else null,
            .conflicts = try self.conflicts.toOwnedSlice(allocator),
            .displayNames = try self.displayNames.toOwnedSlice(allocator),
            .trivia = try self.trivia.toOwnedSlice(allocator),
            .repair = self.repair,
            .lexer = self.lexer,
            .hasParser = self.hasParser or !self.sectioned,
        };
    }

    // --- Helpers ---

    fn stripQuotes(s: []const u8) []const u8 {
        if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
        return s;
    }

    /// The first source position inside `node`, if any.
    fn firstPos(node: Sexp) ?u32 {
        return switch (node) {
            .src => |s| s.pos,
            .list => |l| for (l.items()) |item| {
                if (firstPos(item)) |p| break p;
            } else null,
            else => null,
        };
    }

    /// Where `node` is: its first leaf, else the start of its span.
    fn posOf(self: *const GrammarLowerer, node: Sexp) u32 {
        return firstPos(node) orelse if (self.spans) |p| p.span(node).start else 0;
    }

    fn fail(self: *const GrammarLowerer, node: Sexp, comptime fmt: []const u8, args: anytype) LowerError {
        return self.failAt(self.posOf(node), fmt, args);
    }

    fn failAt(self: *const GrammarLowerer, pos: usize, comptime fmt: []const u8, args: anytype) LowerError {
        diag.errAt(self.source, pos, fmt, args);
        return error.LowerError;
    }

    fn failLine(self: *const GrammarLowerer, line: u32, col: u32, comptime fmt: []const u8, args: anytype) LowerError {
        diag.errLine(self.source.path, line, col, fmt, args);
        return error.LowerError;
    }

    fn loc(self: *const GrammarLowerer, node: Sexp) diag.Source.Loc {
        return self.source.at(self.posOf(node));
    }

    /// The text of a leaf.
    fn text(self: *const GrammarLowerer, leaf: Sexp) []const u8 {
        return leaf.getText(self.source.text);
    }

    /// The text of an optional leaf; null when it is absent.
    fn optText(self: *const GrammarLowerer, leaf: Sexp) ?[]const u8 {
        return if (leaf == .nil) null else self.text(leaf);
    }

    /// The body of a string literal with its escapes decoded
    /// (grammar.escapeAt); an unknown escape is an error at its backslash.
    fn string(self: *const GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const body = stripQuotes(self.text(node));
        if (std.mem.findScalar(u8, body, '\\') == null) return body;
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < body.len) {
            var e: grammar.Escape = .{ .byte = body[i], .len = 1 };
            if (body[i] == '\\') e = grammar.escapeAt(body, i) orelse
                return self.failAt(node.src.pos + 1 + i, "unknown escape sequence (the escapes are \\n \\r \\t \\0 \\\\ \\' \\\" and \\xHH)", .{});
            try out.append(self.allocator, e.byte);
            i += e.len;
        }
        return out.toOwnedSlice(self.allocator);
    }

    /// A parser literal (a terminal) as written, quotes and escapes kept:
    /// later stages name the terminal by its text. Its escapes are checked.
    fn literalText(self: *const GrammarLowerer, node: Sexp) LowerError![]const u8 {
        _ = try self.string(node);
        return self.text(node);
    }

    // --- Root ---

    fn lowerRoot(self: *GrammarLowerer, root: Sexp) LowerError!void {
        const entries = ir.Grammar.entries(root);
        for (entries) |entry| if (entry.isKind(.section)) {
            self.sectioned = true;
        };
        for (entries) |entry| try self.lowerEntry(entry);
    }

    fn lowerEntry(self: *GrammarLowerer, entry: Sexp) LowerError!void {
        const kind = entry.kind().?;
        switch (kind) {
            // Each directive but @as (one line per promoted token) appears
            // once; repeated blocks are not merged.
            .lang, .manifest, .op, .errors, .display, .infix, .schema, .tags, .trivia, .repair => {
                if (self.directives.contains(kind))
                    return self.fail(entry, "duplicate @{s}", .{if (kind == .manifest) "conflicts" else @tagName(kind)});
                self.directives.insert(kind);
            },
            else => {},
        }
        switch (kind) {
            .lang => try self.lowerLang(entry),
            .manifest => try self.lowerManifest(entry),
            .as => try self.lowerAs(entry),
            .op => try self.lowerOp(entry),
            .errors => try self.lowerErrors(entry),
            .display => try self.lowerDisplay(entry),
            .infix => try self.lowerInfix(entry),
            .schema => try self.lowerSchema(entry),
            .tags => {
                self.tagsNode = entry;
                try self.lowerNames(ir.Tags.names(entry), "@tags", &self.extraTags);
            },
            .trivia => try self.lowerNames(ir.Trivia.names(entry), "@trivia", &self.trivia),
            .repair => try self.lowerRepair(entry),
            .rule => {
                if (self.sectioned and self.section != .parser)
                    return self.fail(entry, "rules belong in the @parser section", .{});
                try self.lowerRule(entry);
            },
            .section => try self.lowerSection(entry),
            .state, .after, .tokens, .code, .lex_rule => {
                // lang.zig scans these only after `@lexer` (and before `@parser`).
                const spec = &self.lexer.?;
                switch (kind) {
                    .state => try self.lowerStateBlock(ir.State.vars(entry), spec),
                    .after => try self.lowerAfterBlock(ir.After.vars(entry), spec),
                    .tokens => try self.lowerTokensBlock(entry, spec),
                    .code => {
                        if (self.codeNode == null) self.codeNode = entry;
                        try spec.codeFunctions.append(self.allocator, self.text(ir.Code.name(entry)));
                    },
                    .lex_rule => try self.lowerLexRule(entry, spec),
                    else => unreachable,
                }
            },
            else => unreachable, // the role is typed with the kinds above
        }
    }

    // --- Sections ---

    fn lowerSection(self: *GrammarLowerer, node: Sexp) LowerError!void {
        const nameNode = ir.Section.name(node);
        if (std.mem.eql(u8, self.text(nameNode), "lexer")) {
            if (self.lexer != null) return self.fail(node, "duplicate @lexer section", .{});
            if (self.section == .parser) return self.fail(node, "the @lexer section comes before @parser", .{});
            self.lexer = .{ .fileName = self.source.path };
            self.section = .lexer;
        } else {
            if (self.hasParser) return self.fail(node, "duplicate @parser section", .{});
            // The marker's `@` directly precedes its name.
            if (self.section == .lexer) try self.validateLexer(nameNode.src.pos - 1);
            self.hasParser = true;
            self.section = .parser;
        }
    }

    // --- The @lexer section ---

    /// `state` block: `name = value` per variable.
    fn lowerStateBlock(self: *GrammarLowerer, vars: []const Sexp, spec: *LexerSpec) LowerError!void {
        for (vars) |assign| {
            const nameNode = ir.Assign.name(assign);
            const name = self.text(nameNode);
            for (spec.states.items) |st| if (std.mem.eql(u8, st.name, name))
                return self.fail(nameNode, "state variable '{s}' is declared twice", .{name});
            if (std.mem.eql(u8, name, "pre"))
                return self.fail(nameNode, "'pre' is the built-in whitespace count; choose another state variable name", .{});
            const value = try self.stateValue(name, ir.Assign.value(assign));
            try spec.states.append(self.allocator, .{ .name = name, .initialValue = value });
        }
    }

    /// `after` block: assignments applied whenever a token consumes input.
    fn lowerAfterBlock(self: *GrammarLowerer, vars: []const Sexp, spec: *LexerSpec) LowerError!void {
        for (vars) |assign| {
            const nameNode = ir.Assign.name(assign);
            const name = self.text(nameNode);
            const value = try self.stateValue(name, ir.Assign.value(assign));
            if (!isState(spec, name))
                return self.fail(nameNode, "after block assigns '{s}', which is not a declared state variable", .{name});
            try spec.afterActions.append(self.allocator, .{ .kind = .set, .variable = name, .value = value });
        }
    }

    /// A value assigned to `name`: an integer (see `valueOf`), `true` (1)
    /// or `false` (0).
    fn stateValue(self: *GrammarLowerer, name: []const u8, node: Sexp) LowerError!i32 {
        const t = self.text(node);
        if (std.mem.eql(u8, t, "true")) return 1;
        if (std.mem.eql(u8, t, "false")) return 0;
        // An INTEGER starts with a digit or `-`; anything else is a name.
        if (t[0] != '-' and !std.ascii.isDigit(t[0]))
            return self.fail(node, "state variable '{s}' needs an integer, true, or false; found '{s}'", .{ name, t });
        return self.valueOf(name, node);
    }

    /// An integer `name` can hold: a state variable is an i8, `pre` the u8
    /// count of blanks before the token.
    fn valueOf(self: *GrammarLowerer, name: []const u8, node: Sexp) LowerError!i32 {
        const t = self.text(node);
        const lo: i32, const hi: i32 = if (std.mem.eql(u8, name, "pre")) .{ 0, 255 } else .{ -128, 127 };
        const v = std.fmt.parseInt(i32, t, 10) catch hi + 1;
        if (v < lo or v > hi) return self.fail(node, "value {s} for '{s}' is out of range ({d}..{d})", .{ t, name, lo, hi });
        return v;
    }

    fn lowerTokensBlock(self: *GrammarLowerer, node: Sexp, spec: *LexerSpec) LowerError!void {
        if (self.tokensAt == null) self.tokensAt = ir.Tokens.keyword(node).src.pos;
        for (ir.Tokens.names(node)) |n| {
            const name = self.text(n);
            for (spec.tokens.items) |t| if (std.mem.eql(u8, t.name, name))
                return self.fail(n, "token '{s}' is declared twice", .{name});
            // The 8-byte Token keeps its category in a byte (one value is
            // the built-in `skip`).
            if (spec.tokens.items.len == 255)
                return self.fail(n, "too many tokens: at most 255 can be declared (a token's category is one byte)", .{});
            try spec.tokens.append(self.allocator, .{ .name = name });
        }
    }

    /// `pattern [@ guard & ...] → token, action...` or `@ guard ... → token ...`
    fn lowerLexRule(self: *GrammarLowerer, node: Sexp, spec: *LexerSpec) LowerError!void {
        const patternNode = ir.LexRule.pattern(node);
        const guardsNode = ir.LexRule.guards(node);
        const pattern = self.optText(patternNode) orelse "";
        // The pattern, or the `@` of a zero-width rule (the grammar gives
        // every rule one or the other).
        const at = (firstPos(patternNode) orelse firstPos(ir.Guards.at(guardsNode))).?;
        var guards: std.ArrayList(Guard) = .empty;
        if (guardsNode != .nil) for (ir.Guards.conds(guardsNode)) |g| try guards.append(self.allocator, try self.lowerGuard(g));
        const where = self.source.at(at);

        var literal: ?[]const u8 = null;
        if (pattern.len > 0) {
            var d: regex.Diagnostic = .{};
            const parsed = regex.parse(self.allocator, pattern, &d) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidPattern => return self.failAt(at + d.offset, "{s}", .{d.message}),
            };
            if (parsed.trail == null) {
                if (try regex.literal(parsed.main, &self.scratch, self.allocator)) |lit| literal = try self.allocator.dupe(u8, lit);
            }
        }

        var rule: LexerRule = .{
            .pattern = pattern,
            .guards = &.{},
            .token = self.text(ir.LexRule.token(node)),
            .actions = &.{},
            .literal = literal,
            .line = where.line,
            .col = where.col,
        };
        var actions: std.ArrayList(Action) = .empty;
        for (ir.LexRule.actions(node)) |a| try self.lowerLexAction(a, &rule, &actions);
        if (rule.hold and rule.rewind != null) return self.failAt(at, "a rule cannot both hold and rewind", .{});
        if (rule.hold and rule.isSkip) return self.failAt(at, "a held (zero-width) rule cannot also skip", .{});
        rule.guards = try guards.toOwnedSlice(self.allocator);
        rule.actions = try actions.toOwnedSlice(self.allocator);
        try spec.rules.append(self.allocator, rule);
    }

    /// `[!]var`, or `[!]var op n`.
    fn lowerGuard(self: *GrammarLowerer, node: Sexp) LowerError!Guard {
        const variable = self.text(ir.Guard.@"var"(node));
        const negated = ir.Guard.neg(node) != .nil;
        const opText = self.optText(ir.Guard.op(node)) orelse
            return .{ .variable = variable, .op = .truthy, .value = 0, .negated = negated };
        const ops = [_]struct { []const u8, Guard.Op }{
            .{ "==", .eq }, .{ "!=", .ne }, .{ ">=", .ge }, .{ "<=", .le }, .{ ">", .gt }, .{ "<", .lt },
        };
        // lang.zig scans exactly these six as `compare`.
        const op = for (ops) |o| {
            if (std.mem.eql(u8, o[0], opText)) break o[1];
        } else unreachable;
        return .{ .variable = variable, .op = op, .value = try self.valueOf(variable, ir.Guard.value(node)), .negated = negated };
    }

    fn lowerLexAction(self: *GrammarLowerer, node: Sexp, rule: *LexerRule, actions: *std.ArrayList(Action)) LowerError!void {
        switch (node.kind().?) {
            .set_action => {
                const name = self.text(ir.SetAction.name(node));
                try actions.append(self.allocator, .{ .kind = .set, .variable = name, .value = try self.stateValue(name, ir.SetAction.value(node)) });
            },
            .step_action => {
                // INCDEC: `++` or `--`.
                const op = self.text(ir.StepAction.op(node));
                try actions.append(self.allocator, .{ .kind = if (op[0] == '+') .inc else .dec, .variable = self.text(ir.StepAction.name(node)) });
            },
            .counted => {
                const fnNode = ir.Counted.@"fn"(node);
                const func = self.text(fnNode);
                if (!std.mem.eql(u8, func, "counted"))
                    return self.fail(fnNode, "unknown function '{s}' in the action (expected counted('c'))", .{func});
                try actions.append(self.allocator, .{ .kind = .counted, .variable = self.text(ir.Counted.name(node)), .char = try self.quotedByte(ir.Counted.char(node)) });
            },
            .lex_action => {
                const wordNode = ir.LexAction.word(node);
                const word = self.text(wordNode);
                // `word(arg)`: the parentheses are not in the tree.
                const arg = ir.LexAction.arg(node);
                const argText = self.optText(arg);
                const quoted = argText != null and argText.?[0] == '\'';
                if (std.mem.eql(u8, word, "skip") or std.mem.eql(u8, word, "hold")) {
                    if (arg != .nil) return self.fail(arg, "`{s}` takes no argument", .{word});
                    if (word[0] == 's') rule.isSkip = true else rule.hold = true;
                } else if (std.mem.eql(u8, word, "rewind")) {
                    if (argText == null or quoted) return self.fail(if (arg == .nil) wordNode else arg, "rewind takes a byte count, as in rewind(1)", .{});
                    const n = std.fmt.parseInt(i32, argText.?, 10) catch -1;
                    if (n < 0 or n > 65535) return self.fail(wordNode, "rewind({s}) is out of range", .{argText.?});
                    rule.rewind = @intCast(n);
                } else if (std.mem.eql(u8, word, "counting") or std.mem.eql(u8, word, "matching")) {
                    return self.fail(wordNode, "{s}() describes balanced nesting, which no finite automaton can recognize; use trailing context '/' for bounded lookahead or handle nesting in the lang Lexer wrapper", .{word});
                } else {
                    return self.fail(wordNode, "unknown lexer action '{s}' (expected {{...}}, skip, hold, or rewind(n))", .{word});
                }
            },
            else => unreachable, // the role is typed lex_action|set_action|step_action|counted
        }
    }

    /// The byte of a quoted `'c'` (escapes as in patterns).
    fn quotedByte(self: *GrammarLowerer, node: Sexp) LowerError!u8 {
        const quoted = self.text(node);
        const at = node.src.pos;
        var d: regex.Diagnostic = .{};
        const p = regex.parse(self.allocator, quoted, &d) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidPattern => return self.failAt(at + d.offset, "{s}", .{d.message}),
        };
        return (if (p.main.* == .set) p.main.set.only() else null) orelse
            self.failAt(at, "expected exactly one byte in quotes", .{});
    }

    fn isState(spec: *const LexerSpec, name: []const u8) bool {
        for (spec.states.items) |st| if (std.mem.eql(u8, st.name, name)) return true;
        return false;
    }

    fn isToken(spec: *const LexerSpec, name: []const u8) bool {
        if (std.mem.eql(u8, name, "skip")) return true;
        for (spec.tokens.items) |t| if (std.mem.eql(u8, t.name, name)) return true;
        return false;
    }

    /// Names the lexer rules use must be declared: tokens in `tokens` (plus
    /// the built-in `skip`), variables in `state` (guards may also test
    /// `pre`, and actions may assign it).
    /// `end` is where the section ends (reported when there is no `tokens`
    /// block).
    fn validateLexer(self: *GrammarLowerer, end: u32) LowerError!void {
        const spec = &self.lexer.?;
        for ([_][]const u8{ "eof", "err" }) |required| {
            if (!isToken(spec, required))
                return self.failAt(self.tokensAt orelse end, "the tokens block must declare '{s}' (the lexer emits it at end of input / on unmatched bytes)", .{required});
        }
        for (spec.rules.items) |r| {
            if (!isToken(spec, r.token)) return self.failLine(r.line, r.col, "token '{s}' is not declared in the tokens block", .{r.token});
            for (r.guards) |g| {
                if (!std.mem.eql(u8, g.variable, "pre") and !isState(spec, g.variable))
                    return self.failLine(r.line, r.col, "guard tests '{s}', which is not a declared state variable or 'pre'", .{g.variable});
            }
            for (r.actions) |a| {
                const v = a.variable.?;
                if (std.mem.eql(u8, v, "pre")) {
                    if (a.kind == .inc or a.kind == .dec) return self.failLine(r.line, r.col, "'pre' can only be assigned ({{pre = n}} or {{pre = counted('c')}})", .{});
                } else if (!isState(spec, v)) {
                    return self.failLine(r.line, r.col, "action assigns '{s}', which is not a declared state variable", .{v});
                }
            }
        }
    }

    // --- Directives ---

    fn lowerLang(self: *GrammarLowerer, node: Sexp) LowerError!void {
        self.lang = stripQuotes(self.text(ir.Lang.name(node)));
    }

    /// `@conflicts`, one entry per line; an empty block (like none) means
    /// the grammar must be conflict-free.
    fn lowerManifest(self: *GrammarLowerer, node: Sexp) LowerError!void {
        for (ir.Manifest.entries(node)) |entry| {
            const kindNode = ir.Conflict.kind(entry);
            const kindName = self.text(kindNode);
            const kind: @FieldType(ConflictEntry, "kind") = if (std.mem.eql(u8, kindName, "shift"))
                .shift
            else if (std.mem.eql(u8, kindName, "reduce"))
                .reduce
            else
                return self.fail(kindNode, "conflict kind must be `shift` or `reduce`, not '{s}'", .{kindName});
            const rule = try self.lowerRuleText(ir.Conflict.rule(entry));
            const overNode = ir.Conflict.over(entry);
            const over: ?[]const u8 = if (overNode == .nil) null else try self.lowerRuleText(overNode);
            if (kind == .shift and over != null)
                return self.fail(overNode, "a `shift` entry names one rule; `over` belongs to `reduce` entries", .{});
            if (kind == .reduce and over == null)
                return self.fail(entry, "a `reduce` entry names the winning rule `over` the losing one", .{});
            // An INTEGER: only its size can be wrong.
            const countNode = ir.Conflict.count(entry);
            const count = std.fmt.parseInt(u32, self.text(countNode), 10) catch
                return self.fail(countNode, "conflict count {s} is too large", .{self.text(countNode)});
            const reasonNode = ir.Conflict.reason(entry);
            const reasonRaw = self.optText(reasonNode) orelse
                return self.fail(entry, "conflict entry needs a `# rationale` comment", .{});
            const reason = std.mem.trim(u8, reasonRaw[1..], " \t\r");
            if (reason.len == 0) return self.fail(reasonNode, "conflict rationale is empty", .{});
            const l = self.loc(entry);
            try self.conflicts.append(self.allocator, .{
                .kind = kind,
                .rule = rule,
                .over = over,
                .count = count,
                .reason = reason,
                .line = l.line,
                .col = l.col,
            });
        }
    }

    /// A conflict entry's rule, `lhs → rhs`, kept verbatim (the LR stage
    /// compares it with whitespace normalized and `->` read as `→`).
    fn lowerRuleText(self: *GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const t = self.text(node);
        if (std.mem.find(u8, t, "\u{2192}") == null and std.mem.find(u8, t, "->") == null)
            return self.fail(node, "a conflict entry names a rule as `lhs → rhs`, not '{s}'", .{t});
        return t;
    }

    fn lowerAs(self: *GrammarLowerer, node: Sexp) LowerError!void {
        // The token is stored as its TokenCat name (`IDENT` → `ident`).
        const token = try std.ascii.allocLowerString(self.allocator, self.text(ir.As.token(node)));
        const sharedViaNode = ir.As.via(node);
        const sharedVia = self.optText(sharedViaNode);
        var groups: usize = 0;
        for (ir.As.groups(node)) |entry| {
            const permissive = ir.AsEntry.perm(entry) != .nil;
            const groupNode = ir.AsEntry.group(entry);
            const rule = self.text(groupNode);
            const viaNode = ir.AsEntry.via(entry);
            const via = self.optText(viaNode);
            if (std.mem.eql(u8, rule, "self")) {
                if (permissive) return self.fail(groupNode, "`self!` is not allowed: `self` is a checkpoint, not a group", .{});
                if (via != null) return self.fail(viaNode, "`self` has no lookup function", .{});
            } else groups += 1;
            try self.asDirectives.append(self.allocator, .{
                .token = token,
                .rule = rule,
                .permissive = permissive,
                .via = via orelse if (std.mem.eql(u8, rule, "self")) null else sharedVia,
            });
        }
        if (sharedVia != null and groups != 1)
            return self.fail(sharedViaNode, "`@as TOKEN via fn` names the lookup of a single group; give each group its own `via`", .{});
    }

    fn lowerOp(self: *GrammarLowerer, node: Sexp) LowerError!void {
        for (ir.Op.maps(node)) |entry| {
            const litNode = ir.OpMap.lit(entry);
            const tokNode = ir.OpMap.token(entry);
            const lit = stripQuotes(try self.literalText(litNode));
            const tok = stripQuotes(self.text(tokNode));
            for (self.opMappings.items) |m| if (std.mem.eql(u8, m.lit, lit))
                return self.fail(litNode, "@op maps \"{s}\" twice", .{lit});
            const at = self.loc(tokNode);
            try self.opMappings.append(self.allocator, .{ .lit = lit, .tok = tok, .line = at.line, .col = at.col });
        }
    }

    const Pair = struct { key: []const u8, name: []const u8, quoted: bool };

    /// `key: "name"`; the key is a LABEL or a STRING, the name a STRING.
    fn lowerPair(self: *GrammarLowerer, entry: Sexp) LowerError!Pair {
        const keyNode = ir.NamePair.key(entry);
        const key = self.text(keyNode);
        const quoted = key[0] == '"';
        if (quoted) _ = try self.literalText(keyNode);
        return .{ .key = key, .name = try self.string(ir.NamePair.name(entry)), .quoted = quoted };
    }

    fn lowerErrors(self: *GrammarLowerer, node: Sexp) LowerError!void {
        for (ir.Errors.pairs(node)) |entry| {
            const p = try self.lowerPair(entry);
            if (p.quoted) return self.fail(entry, "@errors names rules (`rule: \"name\"`); name tokens in @display", .{});
            for (self.errorNames.items) |e| if (std.mem.eql(u8, e.rule, p.key))
                return self.fail(entry, "@errors names '{s}' twice", .{p.key});
            const at = self.loc(entry);
            try self.errorNames.append(self.allocator, .{ .rule = p.key, .name = p.name, .line = at.line, .col = at.col });
        }
    }

    fn lowerDisplay(self: *GrammarLowerer, node: Sexp) LowerError!void {
        for (ir.Display.pairs(node)) |entry| {
            const p = try self.lowerPair(entry);
            if (!p.quoted and !(p.key[0] >= 'A' and p.key[0] <= 'Z'))
                return self.fail(entry, "@display names tokens (`TOKEN: \"name\"` or `\"lit\": \"name\"`); name rules in @errors", .{});
            for (self.displayNames.items) |d| if (std.mem.eql(u8, d.token, p.key))
                return self.fail(entry, "@display names {s} twice", .{p.key});
            const at = self.loc(entry);
            try self.displayNames.append(self.allocator, .{ .token = p.key, .name = p.name, .line = at.line, .col = at.col });
        }
    }

    fn lowerInfix(self: *GrammarLowerer, node: Sexp) LowerError!void {
        self.infixBase = self.text(ir.Infix.base(node));
        self.infixLoc = self.loc(node);
        var prec: u32 = 1;
        for (ir.Infix.levels(node)) |level| {
            for (ir.Level.ops(level)) |opNode| {
                const op = stripQuotes(try self.literalText(ir.InfixOp.op(opNode)));
                const assocNode = ir.InfixOp.assoc(opNode);
                const assocName = self.text(assocNode);
                const assoc = std.meta.stringToEnum(InfixOp.Assoc, assocName) orelse
                    return self.fail(assocNode, "associativity must be left, right or none, not '{s}'", .{assocName});
                try self.infixOps.append(self.allocator, .{ .op = op, .assoc = assoc, .prec = prec });
            }
            prec += 1;
        }
    }

    fn lowerSchema(self: *GrammarLowerer, node: Sexp) LowerError!void {
        self.hasSchema = true;
        for (ir.Schema.decls(node)) |decl| try self.lowerKindDecl(decl);
    }

    fn lowerKindDecl(self: *GrammarLowerer, decl: Sexp) LowerError!void {
        const roleNodes = ir.Roles.roles(ir.KindDecl.roles(decl));
        var roles: std.ArrayList(Schema.Role) = .empty;
        for (roleNodes, 0..) |roleNode, i| {
            const role = try self.lowerRole(roleNode);
            if (role.rest and i + 1 != roleNodes.len)
                return self.fail(roleNode, "rest role `...{s}` must be the last role", .{role.name});
            for (roles.items) |other| if (std.mem.eql(u8, other.name, role.name))
                return self.fail(roleNode, "duplicate role '{s}'", .{role.name});
            try roles.append(self.allocator, role);
        }

        var side: std.ArrayList([]const u8) = .empty;
        const sidesNode = ir.KindDecl.sides(decl);
        if (sidesNode != .nil) for (ir.Sides.names(sidesNode)) |s| {
            const name = self.text(s);
            for (roles.items) |r| if (std.mem.eql(u8, r.name, name))
                return self.fail(s, "'{s}' is both a slot role and a side-band role", .{name});
            for (side.items) |o| if (std.mem.eql(u8, o, name))
                return self.fail(s, "duplicate side-band role '{s}'", .{name});
            try side.append(self.allocator, name);
        };
        const wrapper = ir.KindDecl.wrapper(decl) != .nil;

        const roleSlice = try roles.toOwnedSlice(self.allocator);
        const sideSlice = try side.toOwnedSlice(self.allocator);
        for (ir.Kinds.names(ir.KindDecl.kinds(decl))) |nameNode| {
            const tag = stripQuotes(self.text(nameNode));
            if (tag.len == 0) return self.fail(nameNode, "empty kind name", .{});
            for (self.kinds.items) |k| if (std.mem.eql(u8, k.tag, tag))
                return self.fail(nameNode, "kind '{s}' is declared twice", .{tag});
            const l = self.loc(nameNode);
            try self.kinds.append(self.allocator, .{
                .tag = tag,
                .roles = roleSlice,
                .side = sideSlice,
                .wrapper = wrapper,
                .line = l.line,
                .col = l.col,
            });
        }
    }

    fn lowerRole(self: *GrammarLowerer, node: Sexp) LowerError!Schema.Role {
        const nameNode = ir.Role.name(node);
        const name = self.text(nameNode);
        if (name[0] == '_' or !std.ascii.isLower(name[0]))
            return self.fail(nameNode, "role names start with a lowercase letter: '{s}'", .{name});
        const typeNode = ir.Role.type(node);
        return .{
            .name = name,
            .type = if (typeNode == .nil) .any else try self.lowerRoleType(typeNode),
            .optional = ir.Role.opt(node) != .nil,
            .rest = ir.Role.rest(node) != .nil,
        };
    }

    /// A union of atoms: kind names, or one builtin type (`node`, `leaf`,
    /// `group`, `tag`, `tag(a | b)`, `any`) alone.
    fn lowerRoleType(self: *GrammarLowerer, node: Sexp) LowerError!Schema.RoleType {
        const atoms = ir.Type.atoms(node);
        var kinds: std.ArrayList([]const u8) = .empty;
        var builtin: ?Schema.RoleType = null;
        for (atoms) |atom| {
            if (atom.isKind(.tagset)) {
                const headNode = ir.Tagset.tag(atom);
                const head = self.text(headNode);
                if (!std.mem.eql(u8, head, "tag"))
                    return self.fail(headNode, "only `tag(...)` takes a value list, not '{s}(...)'", .{head});
                var values: std.ArrayList([]const u8) = .empty;
                for (ir.Tagset.values(atom)) |v| try values.append(self.allocator, stripQuotes(self.text(v)));
                if (builtin != null or atoms.len > 1) return self.fail(atom, "`tag(...)` cannot be combined with other types", .{});
                builtin = .{ .tag = try values.toOwnedSlice(self.allocator) };
                continue;
            }
            const raw = self.text(atom);
            const b: ?Schema.RoleType = if (raw[0] == '"')
                null
            else if (std.mem.eql(u8, raw, "node"))
                .node
            else if (std.mem.eql(u8, raw, "leaf"))
                .leaf
            else if (std.mem.eql(u8, raw, "group"))
                .group
            else if (std.mem.eql(u8, raw, "tag"))
                .{ .tag = &.{} }
            else if (std.mem.eql(u8, raw, "any"))
                .any
            else
                null;
            if (b) |t| {
                if (atoms.len > 1) return self.fail(atom, "`{s}` cannot be combined with other types in a union", .{raw});
                builtin = t;
            } else {
                try kinds.append(self.allocator, stripQuotes(raw));
            }
        }
        if (builtin) |b| return b;
        return .{ .kinds = try kinds.toOwnedSlice(self.allocator) };
    }

    fn lowerNames(self: *GrammarLowerer, names: []const Sexp, what: []const u8, out: *std.ArrayList([]const u8)) LowerError!void {
        for (names) |n| {
            const name = stripQuotes(self.text(n));
            for (out.items) |o| if (std.mem.eql(u8, o, name))
                return self.fail(n, "{s} names '{s}' twice", .{ what, name });
            try out.append(self.allocator, name);
        }
    }

    fn lowerRepair(self: *GrammarLowerer, node: Sexp) LowerError!void {
        var holes: std.ArrayList([]const u8) = .empty;
        var structure: std.ArrayList([]const u8) = .empty;
        var terminators: std.ArrayList([]const u8) = .empty;
        var holeLocs: std.ArrayList(grammar.RepairSpec.Loc) = .empty;
        var structureLocs: std.ArrayList(grammar.RepairSpec.Loc) = .empty;
        var terminatorLocs: std.ArrayList(grammar.RepairSpec.Loc) = .empty;
        for (ir.Repair.lines(node)) |line| {
            const classNode = ir.RepairLine.class(line);
            const which = self.text(classNode);
            const out = if (std.mem.eql(u8, which, "holes"))
                &holes
            else if (std.mem.eql(u8, which, "structure"))
                &structure
            else if (std.mem.eql(u8, which, "terminator"))
                &terminators
            else
                return self.fail(classNode, "@repair lines are `holes ...`, `structure ...` or `terminator ...`, not '{s}'", .{which});
            const locs = if (out == &holes) &holeLocs else if (out == &structure) &structureLocs else &terminatorLocs;
            for (ir.RepairLine.names(line)) |n| {
                // A literal keeps its quotes: it names the literal's symbol.
                try out.append(self.allocator, try self.symbolText(n));
                const at = self.loc(n);
                try locs.append(self.allocator, .{ .line = at.line, .col = at.col });
            }
        }
        try holeLocs.appendSlice(self.allocator, structureLocs.items);
        try holeLocs.appendSlice(self.allocator, terminatorLocs.items);
        self.repair = .{
            .holes = try holes.toOwnedSlice(self.allocator),
            .structure = try structure.toOwnedSlice(self.allocator),
            .terminators = try terminators.toOwnedSlice(self.allocator),
            .locs = try holeLocs.toOwnedSlice(self.allocator),
        };
    }

    // --- Rules ---

    fn lowerRule(self: *GrammarLowerer, node: Sexp) LowerError!void {
        const nameNode = ir.Rule.name(node);
        const isStart = nameNode.isKind(.start);
        const name = self.text(if (isStart) ir.Start.id(nameNode) else ir.Name.id(nameNode));
        if (isStart) {
            for (self.startSymbols.items) |s| if (std.mem.eql(u8, s, name))
                return self.fail(nameNode, "start symbol '{s}' is declared twice", .{name});
            try self.startSymbols.append(self.allocator, name);
        }

        var alts: std.ArrayList(ParsedAlternative) = .empty;
        for (ir.Rule.alts(node)) |altNode| try alts.append(self.allocator, try self.lowerAlt(altNode, nameNode));

        const l = self.loc(node);
        try self.rules.append(self.allocator, .{
            .name = name,
            .isStart = isStart,
            .alternatives = try alts.toOwnedSlice(self.allocator),
            .line = l.line,
            .col = l.col,
        });
    }

    fn lowerAlt(self: *GrammarLowerer, altNode: Sexp, ruleName: Sexp) LowerError!ParsedAlternative {
        // `<` or `>`.
        const hint = self.optText(ir.Alt.hint(altNode));

        // (exclude "c") hints are consumed here: they set the alternative's
        // excluded characters and never reach the element list.
        const elementsNode = ir.Alt.elements(altNode);
        var elements: std.ArrayList(ParsedElement) = .empty;
        var exclude: std.ArrayList(u8) = .empty;
        for (elementsNode.items()) |child| {
            if (child.isKind(.exclude)) {
                const c = try self.hintChar(ir.Exclude.char(child));
                if (std.mem.findScalar(u8, exclude.items, c) == null) try exclude.append(self.allocator, c);
                continue;
            }
            try elements.append(self.allocator, try self.lowerElement(child));
        }

        const elems = try elements.toOwnedSlice(self.allocator);
        var positions = logicalLength(elems);
        for (elems) |e| if (e.kind == .choice) for (e.choices) |c| {
            positions += c.len;
        };
        if (positions > ParsedAlternative.maxPositions)
            return self.fail(elementsNode, "this alternative has {d} elements; the limit is {d}", .{ positions, ParsedAlternative.maxPositions });
        const actionNode = ir.Alt.action(altNode);
        const actionTree: ?ActionTree = if (actionNode == .nil) null else try self.lowerAction(actionNode, logicalLength(elems));
        const optOutNode = ir.Alt.optout(altNode);
        const optOut = self.optText(optOutNode);
        if (optOut) |o| if (stripQuotes(o).len == 0) return self.fail(optOutNode, "an opt-out needs a reason", .{});

        const excludeChars = try exclude.toOwnedSlice(self.allocator);
        const l = self.loc(if (firstPos(elementsNode) != null) elementsNode else if (actionNode != .nil) actionNode else ruleName);
        return .{
            .elements = elems,
            .actionTree = actionTree,
            .optOut = if (optOut) |o| stripQuotes(o) else null,
            .excludeChars = excludeChars,
            .preferReduce = hint != null and hint.?[0] == '<',
            .preferShift = hint != null and hint.?[0] == '>',
            .line = l.line,
            .col = l.col,
        };
    }

    /// The byte of an `X "c"` hint.
    fn hintChar(self: *GrammarLowerer, node: Sexp) LowerError!u8 {
        const c = try self.string(node);
        if (c.len != 1) return self.fail(node, "X \"c\": the hint takes one byte, not \"{s}\"", .{stripQuotes(self.text(node))});
        return c[0];
    }

    /// Number of action positions a pattern has: one per element, and one
    /// per sub-element of a multi-element `[A B]` group.
    fn logicalLength(elements: []const ParsedElement) usize {
        var n: usize = 0;
        for (elements) |e| n += if (e.kind == .optGroup) e.subElements.len else 1;
        return n;
    }

    // --- Elements ---

    fn lowerElement(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        var elem: ParsedElement = switch (node.kind().?) {
            .ref => .{ .kind = .ident, .value = self.text(ir.Ref.name(node)) },
            .tok => .{ .kind = .token, .value = self.text(ir.Tok.name(node)) },
            .lit => .{ .kind = .string, .value = try self.literalText(ir.Lit.name(node)) },
            .at_ref => .{ .kind = .ident, .value = self.text(ir.AtRef.name(node)) },
            .list_req => try self.lowerListElement(node),
            .group => try self.lowerGroupKinded(node),
            .quantified => try self.lowerQuantifiedElement(node),
            .skip => try self.lowerSkipElement(node, ir.Skip.element(node), .nil),
            .skip_q => try self.lowerSkipElement(node, ir.SkipQ.element(node), ir.SkipQ.quant(node)),
            .label => try self.lowerLabeled(node),
            // Hints belong to the whole alternative (lowerAlt takes those).
            .exclude => return self.fail(node, "an `X \"c\"` hint applies to the whole alternative; write it outside ( ) and [ ]", .{}),
            // `element` (the items of `elements` and of group bodies) builds
            // only the kinds above; the roles that nest one are typed so.
            else => unreachable,
        };
        if (elem.line == 0) {
            const l = self.loc(node);
            elem.line = l.line;
            elem.col = l.col;
        }
        return elem;
    }

    /// `role:element` or `( ... ):role`; the element is never a skip or a
    /// label (the grammar labels only a primary, quantified or not).
    fn lowerLabeled(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        const nameNode = ir.Label.name(node);
        const name = self.text(nameNode);
        if (!std.mem.eql(u8, name, "_") and (name[0] == '_' or !std.ascii.isLower(name[0])))
            return self.fail(nameNode, "labels are role names (lowercase) or `_`: '{s}'", .{name});
        var elem = try self.lowerElement(ir.Label.element(node));
        const l = self.loc(nameNode);
        if (elem.kind == .optGroup) {
            if (elem.subElements.len != 1) return self.fail(node, "label '{s}' on a multi-element [...] group; label its elements", .{name});
            // `role:["x"]` labels the one element (as `[role:"x"]` does).
            const sub = try self.allocator.dupe(ParsedElement, elem.subElements);
            sub[0].label = name;
            sub[0].line = l.line;
            sub[0].col = l.col;
            elem.subElements = sub;
            return elem;
        }
        elem.label = name;
        elem.line = l.line;
        elem.col = l.col;
        return elem;
    }

    fn lowerListElement(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        const inner = ir.ListReq.inner(node);
        return switch (inner.kind().?) {
            .plain => .{ .kind = .reqList, .value = self.text(ir.Plain.item(inner)) },
            .opt_items_nosep => .{ .kind = .reqList, .value = self.text(ir.OptItemsNosep.item(inner)), .optionalItems = true },
            .sep_items => .{ .kind = .reqList, .value = self.text(ir.SepItems.item(inner)), .listSeparator = try self.symbolText(ir.SepItems.sep(inner)) },
            .opt_items => .{ .kind = .reqList, .value = self.text(ir.OptItems.item(inner)), .listSeparator = try self.symbolText(ir.OptItems.sep(inner)), .optionalItems = true },
            else => unreachable, // the role is typed plain|opt_items_nosep|sep_items|opt_items
        };
    }

    /// A literal (checked as above) or a token name: a list separator or a
    /// @repair name.
    fn symbolText(self: *GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const t = self.text(node);
        return if (t[0] == '"') self.literalText(node) else t;
    }

    // `(group KIND BODY ...)`, KIND ∈ _ (parens), opt ([...]), many ([X ...]).
    fn lowerGroupKinded(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        const kindNode = ir.Group.kind(node);
        const kind: ?parser.Tag = if (kindNode == .nil) null else kindNode.tag;

        // Every body has at least one element (`alt_elem`).
        var lowered: std.ArrayList([]const ParsedElement) = .empty;
        for (ir.Group.bodies(node)) |body| try lowered.append(self.allocator, try self.lowerAltBody(body));

        if (kind == .many) {
            // [X ...]: an optional comma-separated list of one item.
            if (lowered.items.len != 1 or !isSingleSimpleElem(lowered.items[0]))
                return self.fail(node, "`[X ...]` takes a single rule or token name", .{});
            return .{ .kind = .optList, .value = lowered.items[0][0].value };
        }

        // [X?], [X*], [A | B?] ...: brackets around what can match nothing.
        if (kind == .opt) for (lowered.items) |b| if (allCanBeEmpty(b))
            return self.fail(node, "[X?] and similar are ambiguous: the body of [...] can match nothing; write [X] or X?", .{});

        if (lowered.items.len > 1) {
            // (A | B | C): exactly one alternative; [A | B]: at most one.
            return .{
                .kind = .choice,
                .choices = try lowered.toOwnedSlice(self.allocator),
                .quantifier = if (kind == .opt) .optional else .one,
            };
        }
        const body = lowered.items[0];

        if (kind == null) return .{ .kind = .group, .subElements = body };

        // [L(X)]: an optional list with the same item, separator and item optionality.
        if (body.len == 1 and body[0].kind == .reqList and body[0].quantifier == .one and !body[0].skip and body[0].label == null) {
            const inner = body[0];
            return .{
                .kind = .optList,
                .value = inner.value,
                .optionalItems = inner.optionalItems,
                .listSeparator = inner.listSeparator,
            };
        }

        // [X]: the element itself with an optional quantifier.
        if (isSingleSimpleElem(body)) {
            var e = body[0];
            e.quantifier = .optional;
            return e;
        }
        if (body.len == 1 and body[0].label != null) {
            var e = body[0];
            e.quantifier = .optional;
            return e;
        }

        // [A B C]: expanded into alternatives downstream (stable positions).
        return .{ .kind = .optGroup, .value = body[0].value, .subElements = body };
    }

    fn lowerAltBody(self: *GrammarLowerer, body: Sexp) LowerError![]const ParsedElement {
        var out: std.ArrayList(ParsedElement) = .empty;
        for (body.items()) |child| try out.append(self.allocator, try self.lowerElement(child));
        return out.toOwnedSlice(self.allocator);
    }

    fn isSingleSimpleElem(elements: []const ParsedElement) bool {
        if (elements.len != 1) return false;
        const e = elements[0];
        if (e.skip or e.label != null) return false;
        if (e.quantifier != .one) return false;
        return e.kind == .ident or e.kind == .token;
    }

    fn lowerQuantifiedElement(self: *GrammarLowerer, node: Sexp) LowerError!ParsedElement {
        return self.quantified(node, try self.lowerElement(ir.Quantified.element(node)), ir.Quantified.quant(node));
    }

    /// `!element` (`quant` nil) or `!element quant`.
    fn lowerSkipElement(self: *GrammarLowerer, node: Sexp, element: Sexp, quant: Sexp) LowerError!ParsedElement {
        var inner = try self.lowerElement(element);
        inner.skip = true;
        return if (quant == .nil) inner else self.quantified(node, inner, quant);
    }

    /// `inner` with quantifier `quant`; [...] already is one (`?`).
    fn quantified(self: *GrammarLowerer, node: Sexp, inner: ParsedElement, quant: Sexp) LowerError!ParsedElement {
        if (inner.quantifier != .one or inner.kind == .optList or inner.kind == .optGroup)
            return self.fail(node, "an element takes one quantifier", .{});
        var e = inner;
        e.quantifier = quantifier(quant);
        return e;
    }

    /// Whether `e` can match no input as written (a rule it names may still
    /// derive the empty string). `L(X?)` cannot: it matches nothing as a
    /// list of one empty item, a tree of its own (`[L(X?)]` tells an absent
    /// list from that one, in a declared conflict).
    fn canBeEmpty(e: ParsedElement) bool {
        if (e.quantifier == .optional or e.quantifier == .zeroPlus) return true;
        return switch (e.kind) {
            .ident, .token, .string, .reqList => false,
            .optList, .optGroup => true,
            .group => allCanBeEmpty(e.subElements),
            .choice => for (e.choices) |c| {
                if (allCanBeEmpty(c)) break true;
            } else false,
        };
    }

    fn allCanBeEmpty(elements: []const ParsedElement) bool {
        for (elements) |e| if (!canBeEmpty(e)) return false;
        return true;
    }

    fn quantifier(node: Sexp) ParsedElement.Quantifier {
        return switch (node.kind().?) {
            .opt => .optional,
            .zero_plus => .zeroPlus,
            .one_plus => .onePlus,
            else => unreachable, // the role is typed opt|zero_plus|one_plus
        };
    }

    // --- Actions ---

    fn lowerAction(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionTree {
        return switch (node.kind().?) {
            .pos => .{ .pass = try self.lowerPosition(ir.Pos.n(node), length) },
            .null => .nil,
            .node, .list, .keep => .{ .list = try self.lowerActionList(node, length) },
            else => unreachable, // the role is typed pos|null|node|list|keep
        };
    }

    fn lowerPosition(self: *GrammarLowerer, nNode: Sexp, length: usize) LowerError!u16 {
        const t = self.text(nNode);
        const n = std.fmt.parseInt(u16, t, 10) catch
            return self.fail(nNode, "position {s} is too large", .{t});
        if (n == 0) return self.fail(nNode, "positions start at 1; 0 is not an element", .{});
        if (n > length) return self.fail(nNode, "position {d} is past the end of the pattern ({d} element{s})", .{ n, length, if (length == 1) "" else "s" });
        return n;
    }

    /// `(node ...)`, `(keep ...)` or `(list ...)`.
    fn lowerActionList(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionList {
        var head: ActionList.Head = .none;
        var itemNodes: []const Sexp = undefined;
        switch (node.kind().?) {
            .node => {
                head = .{ .tag = try self.tagWord(ir.Node.head(node)) };
                itemNodes = ir.Node.items(node);
            },
            .keep => {
                head = .{ .ref = .{ .ref = try self.lowerPosition(ir.Keep.n(node), length) } };
                itemNodes = ir.Keep.items(node);
            },
            .list => itemNodes = ir.List.items(node),
            else => unreachable,
        }
        var items: std.ArrayList(ActionItem) = .empty;
        for (itemNodes) |item| try items.append(self.allocator, try self.lowerActionItem(item, length));
        return .{ .head = head, .items = try items.toOwnedSlice(self.allocator) };
    }

    fn tagWord(self: *GrammarLowerer, node: Sexp) LowerError![]const u8 {
        const w = self.text(node);
        for (w) |c| if (c == '"' or c < ' ')
            return self.fail(node, "tag '{s}' contains a quote or control character", .{w});
        return w;
    }

    fn lowerActionItem(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionItem {
        if (node.isKind(.named)) {
            const roleNode = ir.Named.role(node);
            const role = self.text(roleNode);
            if (std.ascii.isUpper(role[0]) or role[0] == '_')
                return self.fail(roleNode, "role names start with a lowercase letter: '{s}'", .{role});
            return .{ .role = role, .elem = try self.lowerActionValue(ir.Named.value(node), length) };
        }
        return .{ .elem = try self.lowerActionValue(node, length) };
    }

    fn lowerActionValue(self: *GrammarLowerer, node: Sexp, length: usize) LowerError!ActionElem {
        return switch (node.kind().?) {
            .pos => .{ .ref = try self.lowerPosition(ir.Pos.n(node), length) },
            .spread => .{ .spread = try self.lowerPosition(ir.Spread.n(node), length) },
            .symid => .{ .symId = try self.lowerPosition(ir.Symid.n(node), length) },
            .null => .nil,
            .tag => .{ .tagLit = try self.tagWord(ir.Tag.word(node)) },
            .node, .list, .keep => blk: {
                const list = try self.allocator.create(ActionList);
                list.* = try self.lowerActionList(node, length);
                break :blk .{ .node = list };
            },
            else => unreachable, // the roles are typed with the kinds above
        };
    }
};
