//! Rig language module for the Nexus-generated parser (src/parser.zig).
//!
//! The generated parser has two stages, each wrapped here and auto-wired
//! in by Nexus through `@hasDecl`:
//!
//!   stage   generated (parser.zig)   wrapper (this file)
//!   lex     BaseLexer                Lexer   — layout, keywords, spacing
//!   parse   BaseParser               Parser  — post-parse IR rewrites,
//!                                              diagnostics
//!
//! so `parser.Parser.init(allocator, source).parseProgram()` returns the
//! semantic IR described in docs/INTERNALS.md.
//!
//! Also here: the IR `Tag` enum, `BindingKind`, and the identifier
//! escaping that emit needs (`writeZigIdent`).

const std = @import("std");
const parser = @import("parser.zig");
const diag = @import("diag.zig");
const ir = @import("ir.zig");
const BaseLexer = parser.BaseLexer;
const BaseParser = parser.BaseParser;
const Token = parser.Token;
const TokenCat = parser.TokenCat;
const Sexp = parser.Sexp;

// =============================================================================
// Tag — IR node heads and marker tags
// =============================================================================

/// Node shapes are defined in `ir.zig`; an absent optional slot is `_`.
pub const Tag = enum(u8) {
    // Declarations
    @"module",
    @"use",
    @"fun",
    @"sub",
    @"lambda",
    @"struct",
    @"enum",
    @"errors",
    @"type",            // type alias: (type Name T)
    @"generic_type",    // (generic_type Name params-or-_ members...)
    @"generic_enum",    // (generic_enum Name params members...)
    @"test",
    @"pub",
    @"extern",          // (extern _ name T): extern variable
    @"extern_fun",      // (extern_fun name params returns)
    @"extern_sub",      // (extern_sub name params)
    @"drop_decl",       // (drop_decl (param) block): user-defined drop
    @"zig",             // reserved: rejected by sema
    @"labeled",         // (labeled name stmt)

    // Members and parameters
    @":",               // (: name T)
    @"default",         // (default name T expr)
    @"valued",          // enum member with a value: (valued name expr)
    @"variant",         // payload variant: (variant name params)
    @"pre_param",       // (pre_param name T)

    // Bindings: (set <kind> target type-or-_ expr); see BindingKind.
    @"set",
    @"fixed",
    @"shadow",
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"&=",
    @"|=",
    @"^=",
    @"<<=",
    @">>=",
    @"drop",            // (drop name): `-name` statement

    // Control flow
    @"if",              // (if cond then else): block if, ternary, guard
    @"as",              // (as expr name): optional binding in an if/while condition
    @"while",           // (while cond step body else)
    @"for",             // (for mode binding index source body else)
    @"iter",            // for modes
    @"ptr",
    @"match",
    @"arm",             // (arm pattern body)
    @"range_pattern",
    @"variant_pattern", // .circle(r)
    @"enum_lit",        // .red
    @"return",
    @"break",           // (break value label)
    @"continue",        // (continue label)
    @"defer",
    @"errdefer",
    @"raw_block",
    @"pre_block",       // reserved: rejected by sema
    @"pre",             // reserved: rejected by sema
    @"try_block",       // reserved: rejected by sema
    @"catch_block",
    @"catch",           // (catch expr name handler)
    @"propagate",       // expr!
    @"block",

    // Closures
    @"captures",
    @"cap_clone",       // |+x|
    @"cap_weak",        // |~x|
    @"cap_move",        // |<x|

    // Calls and access
    @"call",
    @"builtin",         // @name(args)
    @"member",
    @"index",
    @"array",
    @"kwarg",

    // Operators
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"neg",
    @"not",
    @"and",
    @"or",
    @"==",
    @"!=",
    @"<",
    @">",
    @"<=",
    @">=",
    @"&",
    @"|",
    @"^",
    @"<<",
    @">>",
    @"??",
    @"..",

    // Ownership sigils in expression position
    @"move",            // <x
    @"read",            // ?x
    @"write",           // !x
    @"clone",           // +x
    @"share",           // *x
    @"weak",            // ~x (also ~T in type position)
    @"pin",             // @x, reserved

    // Types
    @"optional",        // T?
    @"error_union",     // T!
    @"borrow_read",     // ?T
    @"borrow_write",    // !T
    @"shared",          // *T
    @"generic_inst",    // Box(Int)
    @"slice",           // []T
    @"array_type",      // [N]T
    @"fun_type",        // fun(A, B) R

    _,
};

// =============================================================================
// BindingKind — the kind slot of (set <kind> ...)
// =============================================================================

/// Exhaustive view of the kind slot, so dispatch sites must handle every
/// kind: `_` → default, `fixed` (`=!`), `shadow` (`new x =`), `move`
/// (`<-`), and the compound assignments (`x op= e`, one per binary
/// arithmetic, bitwise, and shift operator).
pub const BindingKind = enum {
    default,
    fixed,
    shadow,
    @"move",
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"&=",
    @"|=",
    @"^=",
    @"<<=",
    @">>=",

    /// The binary operator a compound assignment applies, or null for a
    /// plain binding or assignment.
    pub fn operator(k: BindingKind) ?Tag {
        return switch (k) {
            .default, .fixed, .shadow, .@"move" => null,
            .@"+=" => .@"+",
            .@"-=" => .@"-",
            .@"*=" => .@"*",
            .@"/=" => .@"/",
            .@"%=" => .@"%",
            .@"&=" => .@"&",
            .@"|=" => .@"|",
            .@"^=" => .@"^",
            .@"<<=" => .@"<<",
            .@">>=" => .@">>",
        };
    }
};

pub const BindingKindError = error{InvalidBindingKind};

/// Decode the kind slot of `(set <kind> ...)`. An unknown kind means the
/// IR is corrupt, so it is an error rather than a silent default.
pub fn bindingKindOf(kind_slot: Sexp) BindingKindError!BindingKind {
    if (kind_slot == .nil) return .default;
    if (kind_slot != .tag) return error.InvalidBindingKind;
    return switch (kind_slot.tag) {
        .fixed => .fixed,
        .shadow => .shadow,
        .@"move" => .@"move",
        .@"+=" => .@"+=",
        .@"-=" => .@"-=",
        .@"*=" => .@"*=",
        .@"/=" => .@"/=",
        .@"%=" => .@"%=",
        .@"&=" => .@"&=",
        .@"|=" => .@"|=",
        .@"^=" => .@"^=",
        .@"<<=" => .@"<<=",
        .@">>=" => .@">>=",
        else => error.InvalidBindingKind,
    };
}

// =============================================================================
// Keywords
// =============================================================================

/// Every Rig keyword is reserved, except `new`, which is a keyword only
/// at the start of a statement followed by a name (`new x = ...`), so
/// `fun new(...)` and `Point.new(...)` stay ordinary names.
const keywords = std.StaticStringMap(TokenCat).initComptime(.{
    .{ "and", .@"and" },
    .{ "as", .@"as" },
    .{ "break", .@"break" },
    .{ "catch", .@"catch" },
    .{ "continue", .@"continue" },
    .{ "defer", .@"defer" },
    .{ "drop", .@"drop" },
    .{ "else", .@"else" },
    .{ "enum", .@"enum" },
    .{ "errdefer", .@"errdefer" },
    .{ "error", .@"error" },
    .{ "extern", .@"extern" },
    .{ "false", .@"false" },
    .{ "for", .@"for" },
    .{ "fun", .@"fun" },
    .{ "if", .@"if" },
    .{ "in", .@"in" },
    .{ "match", .@"match" },
    .{ "new", .@"new" },
    .{ "not", .@"not" },
    .{ "or", .@"or" },
    .{ "pre", .@"pre" },
    .{ "pub", .@"pub" },
    .{ "raw", .@"raw" },
    .{ "return", .@"return" },
    .{ "struct", .@"struct" },
    .{ "sub", .@"sub" },
    .{ "test", .@"test" },
    .{ "true", .@"true" },
    .{ "try", .@"try" },
    .{ "type", .@"type" },
    .{ "use", .@"use" },
    .{ "while", .@"while" },
    .{ "zig", .@"zig" },
});

/// The token category of a reserved word, or null for a plain name.
pub fn keyword(word: []const u8) ?TokenCat {
    return keywords.get(word);
}

// =============================================================================
// Zig identifiers for emitted code
// =============================================================================

const zig_keywords = std.StaticStringMap(void).initComptime(.{
    .{"addrspace"},   .{"align"},       .{"allowzero"},   .{"and"},
    .{"anyframe"},    .{"anytype"},     .{"asm"},         .{"break"},
    .{"callconv"},    .{"catch"},       .{"comptime"},    .{"const"},
    .{"continue"},    .{"defer"},       .{"else"},        .{"enum"},
    .{"errdefer"},    .{"error"},       .{"export"},      .{"extern"},
    .{"fn"},          .{"for"},         .{"if"},          .{"inline"},
    .{"linksection"}, .{"noalias"},     .{"noinline"},    .{"nosuspend"},
    .{"opaque"},      .{"or"},          .{"orelse"},      .{"packed"},
    .{"pub"},         .{"resume"},      .{"return"},      .{"struct"},
    .{"suspend"},     .{"switch"},      .{"test"},        .{"threadlocal"},
    .{"try"},         .{"union"},       .{"unreachable"}, .{"var"},
    .{"volatile"},    .{"while"},
});

const zig_primitives = std.StaticStringMap(void).initComptime(.{
    .{"anyerror"},       .{"anyopaque"},     .{"bool"},        .{"c_char"},
    .{"c_int"},          .{"c_long"},        .{"c_longdouble"}, .{"c_longlong"},
    .{"c_short"},        .{"c_uint"},        .{"c_ulong"},     .{"c_ulonglong"},
    .{"c_ushort"},       .{"comptime_float"}, .{"comptime_int"}, .{"f128"},
    .{"f16"},            .{"f32"},           .{"f64"},         .{"f80"},
    .{"false"},          .{"isize"},         .{"noreturn"},    .{"null"},
    .{"true"},           .{"type"},          .{"undefined"},   .{"usize"},
    .{"void"},
});

/// Names the emitted prelude declares (`panic` is the root module's panic
/// handler), and the prefix of emitter temporaries. A Rig name that
/// collides with one of these is renamed.
const emitter_names = std.StaticStringMap(void).initComptime(.{
    .{"std"}, .{"rig"}, .{"panic"},
});
const emitter_prefix = "__rig";

fn isZigIntType(name: []const u8) bool {
    if (name.len < 2 or (name[0] != 'i' and name[0] != 'u')) return false;
    for (name[1..]) |c| if (c < '0' or c > '9') return false;
    return true;
}

/// Write `name` as a Zig identifier that denotes the Rig name and nothing
/// else:
///   * a Zig keyword or primitive (`var`, `fn`, `u8`, `type`) is quoted:
///     `@"var"`;
///   * a name the emitter itself declares (`std`, `rig`, `__rig*`) gets a
///     `'` suffix, which no Rig identifier can contain: `@"rig'"`;
///   * anything else is written as is.
pub fn writeZigIdent(w: *std.Io.Writer, name: []const u8) std.Io.Writer.Error!void {
    if (emitter_names.has(name) or std.mem.startsWith(u8, name, emitter_prefix)) {
        try w.print("@\"{s}'\"", .{name});
    } else if (zig_keywords.has(name) or zig_primitives.has(name) or isZigIntType(name)) {
        try w.print("@\"{s}\"", .{name});
    } else {
        try w.writeAll(name);
    }
}

// =============================================================================
// Lexer — layout and token classification over the generated BaseLexer
// =============================================================================
//
// Layout
//   Leading spaces set a line's indentation; deeper lines open a block
//   (INDENT), shallower ones close blocks (OUTDENT) and must land on an
//   enclosing level. Blank and comment-only lines are ignored. Inside
//   ( ) and [ ] newlines are whitespace, so an expression may span lines.
//   A trailing `\` also joins the next line. Tabs are rejected in
//   indentation.
//
//   Closure bodies inside brackets: a closure's bar list that ends its
//   line inside ( ) or [ ] opens a layout island, so the body below is
//   laid out in blocks like anywhere else:
//
//       sig.subscribe(*|~sig|
//         if sig.upgrade() as s
//           print(s.get()))
//
//   The island closes when a line comes back to the indentation of the
//   line the closure started on, or when the bracket around it closes;
//   its open blocks end there.
//
// Spacing
//   A character that touches its operand and not the preceding value is a
//   prefix; otherwise it is infix (or a suffix when it touches the value):
//
//     `a < b`, `a<b` less-than        `<x`, `f <x` move
//     `a * b`         multiply        `*x`, `f *x` share, `*T` shared type
//     `a | b`         bitwise or      `|x| ...`    closure bar list
//     `f(x)`, `a[i]`  call, index     `f (x)`, `f [1]`  new operand of f
//     `a.b`           member          `.red`, `f .red`  enum literal
//     `x!`, `T?`      suffix          `!x`, `?x`   write / read borrow
//
//   `-x` at the start of a statement that is nothing but `-name` is a
//   drop; otherwise `-x` is negation.
//
// `if`
//   After `return`/`break`/`continue` or a value, `if` is a postfix guard
//   (`return x if done`), or the inline ternary when an `else` follows on
//   the same logical line (`a if c else b`). Elsewhere it opens a block.

pub const Lexer = struct {
    base: BaseLexer,

    // Indentation: `levels[0..depth]` are the enclosing block columns.
    levels: [max_indent_depth]u32 = undefined,
    depth: u32 = 0,
    /// Per depth: the current line there opened a block that `else` or
    /// `catch` may continue (it has a block `if`, `while`, `for`, or
    /// `try`). An `else` after any other block (a match arm) is a new
    /// line.
    takes_else: [max_indent_depth + 1]bool = @splat(false),
    column: u32 = 0,
    pending_outdents: u32 = 0,
    pending_newline: bool = false,
    pending_pos: u32 = 0,

    // Open ( and [; newlines inside them are whitespace.
    brackets: [max_nesting]u8 = undefined,
    nesting: u32 = 0,

    /// Category of the last token returned.
    last_cat: TokenCat = .eof,
    /// End of the last real (non-layout) token: where an unexpected end
    /// of block or file is reported.
    prev_end: u32 = 0,
    /// A newline or `\` continuation was skipped since the last token.
    joined: bool = false,
    /// Position of the `|` that closes the bar list being lexed.
    capture_close: ?u32 = null,
    /// The last token closed a closure's bar list.
    closed_bars: bool = false,
    /// Layout islands: closure bodies laid out inside brackets, innermost
    /// last.
    islands: [max_islands]Island = undefined,
    island_count: u32 = 0,
    /// A token held back until pending OUTDENTs are returned.
    pending_token: ?Token = null,

    /// Why the last `.err` token was produced.
    err: LexError = .none,

    pub const max_indent_depth = 64;
    pub const max_nesting = 512;
    pub const max_islands = 32;

    /// A closure body laid out inside brackets. Its blocks sit on the
    /// layout stack above `depth`; `column` is the indentation of the
    /// line the closure starts on, and the layout state to restore is
    /// `depth` / `outer_column`.
    const Island = struct { nesting: u32, depth: u32, column: u32, outer_column: u32 };

    pub const LexError = enum {
        none,
        bad_char,
        unterminated_string,
        tab_indent,
        bad_dedent,
        first_line_indented,
        indent_too_deep,
        nesting_too_deep,
        and_operator,
        or_operator,
        power_operator,

        pub fn message(e: LexError) []const u8 {
            return switch (e) {
                .none => "invalid token",
                .bad_char => "invalid character",
                .unterminated_string => "unterminated string",
                .tab_indent => "tab in indentation; indent with spaces",
                .bad_dedent => "indentation does not match any enclosing block",
                .first_line_indented => "unexpected indentation",
                .indent_too_deep => "indentation is nested too deeply",
                .nesting_too_deep => "brackets are nested too deeply",
                .and_operator => "`&&` is not a Rig operator; use `and`",
                .or_operator => "`||` is not a Rig operator; use `or`",
                .power_operator => "`**` is not a Rig operator",
            };
        }
    };

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn next(self: *Lexer) Token {
        const tok = self.produce();
        self.last_cat = tok.cat;
        if (tok.len > 0) { // a real token, not layout
            self.joined = false;
            self.prev_end = tok.pos + tok.len;
        }
        if (self.closed_bars) {
            self.closed_bars = false;
            if (self.nesting > 0 and !self.inIsland() and self.lineEndsAfter()) {
                if (self.island_count == max_islands) return self.fail(.nesting_too_deep, tok.pos);
                self.islands[self.island_count] = .{
                    .nesting = self.nesting,
                    .depth = self.depth,
                    .column = self.lineIndent(tok.pos),
                    .outer_column = self.column,
                };
                self.island_count += 1;
                self.column = self.islands[self.island_count - 1].column;
            }
        }
        return tok;
    }

    /// Newlines at the current bracket depth are layout: the innermost
    /// island is open at this depth.
    fn inIsland(self: *const Lexer) bool {
        return self.island_count > 0 and self.islands[self.island_count - 1].nesting == self.nesting;
    }

    /// Nothing but a comment follows on the current line.
    fn lineEndsAfter(self: *const Lexer) bool {
        var probe = self.base;
        var t = probe.matchRules();
        if (t.cat == .comment) t = probe.matchRules();
        return t.cat == .newline or t.cat == .eof;
    }

    /// Indentation of the line containing `pos`.
    fn lineIndent(self: *const Lexer, pos: u32) u32 {
        var start = pos;
        while (start > 0 and self.base.source[start - 1] != '\n') start -= 1;
        var p = start;
        while (p < self.base.source.len and self.base.source[p] == ' ') p += 1;
        return p - start;
    }

    /// Close the innermost island: its open blocks end here. Returns the
    /// first OUTDENT, with the rest pending and `after` held back, or
    /// null when no block was open.
    fn closeIsland(self: *Lexer, pos: u32, after: ?Token) ?Token {
        self.island_count -= 1;
        const island = self.islands[self.island_count];
        const open = self.depth - island.depth;
        self.depth = island.depth;
        self.column = island.outer_column;
        if (open == 0) return null;
        self.pending_outdents = open - 1;
        self.pending_pos = pos;
        self.pending_newline = false;
        self.pending_token = after;
        return synthetic(.outdent, pos);
    }

    fn produce(self: *Lexer) Token {
        if (self.pending_outdents > 0) {
            self.pending_outdents -= 1;
            return synthetic(.outdent, self.pending_pos);
        }
        if (self.pending_newline) {
            self.pending_newline = false;
            return synthetic(.newline, self.pending_pos);
        }
        if (self.pending_token) |t| {
            self.pending_token = null;
            return self.classify(t);
        }

        while (true) {
            const tok = self.base.matchRules();
            switch (tok.cat) {
                .comment => continue,
                .skip => { // `\` line continuation
                    self.joined = true;
                    continue;
                },
                .newline => {
                    if (self.inIsland()) return self.lineBreak(tok);
                    if (self.nesting > 0 or self.last_cat == .eof) {
                        self.joined = true;
                        continue;
                    }
                    return self.lineBreak(tok);
                },
                .eof => return self.endOfInput(tok),
                else => {},
            }
            if (self.last_cat == .eof and self.columnOf(tok.pos) > 0) {
                return self.fail(.first_line_indented, tok.pos);
            }
            return self.classify(tok);
        }
    }

    fn synthetic(cat: TokenCat, pos: u32) Token {
        return .{ .cat = cat, .pre = 0, .pos = pos, .len = 0 };
    }

    fn fail(self: *Lexer, e: LexError, pos: u32) Token {
        self.err = e;
        return .{ .cat = .err, .pre = 0, .pos = pos, .len = 0 };
    }

    fn columnOf(self: *const Lexer, pos: u32) u32 {
        var i = pos;
        while (i > 0 and self.base.source[i - 1] != '\n') i -= 1;
        return pos - i;
    }

    // -------------------------------------------------------------------------
    // Layout
    // -------------------------------------------------------------------------

    /// A newline outside brackets: find the next line with content and
    /// turn its indentation into NEWLINE, INDENT, or OUTDENTs.
    fn lineBreak(self: *Lexer, nl: Token) Token {
        const src = self.base.source;
        var line: u32 = nl.pos + nl.len;
        while (true) {
            var p = line;
            var tab: ?u32 = null;
            while (p < src.len and (src[p] == ' ' or src[p] == '\t')) : (p += 1) {
                if (src[p] == '\t' and tab == null) tab = p;
            }
            if (p >= src.len) {
                self.base.pos = @intCast(src.len);
                return self.endOfInput(synthetic(.eof, @intCast(src.len)));
            }
            switch (src[p]) {
                '\n', '\r' => {
                    line = p + 1;
                    continue;
                },
                '#' => {
                    while (p < src.len and src[p] != '\n') p += 1;
                    line = p;
                    continue;
                },
                else => {},
            }
            if (tab) |t| return self.fail(.tab_indent, t);
            self.base.pos = line;
            // Back at the closure's own line: the island ends and the
            // bracketed expression continues.
            if (self.inIsland() and p - line <= self.islands[self.island_count - 1].column) {
                self.joined = true;
                return self.closeIsland(p, null) orelse self.produce();
            }
            return self.indentTo(p - line, p, nl);
        }
    }

    fn indentTo(self: *Lexer, width: u32, pos: u32, nl: Token) Token {
        if (width > self.column) {
            if (self.depth == max_indent_depth) return self.fail(.indent_too_deep, pos);
            self.levels[self.depth] = self.column;
            self.depth += 1;
            self.column = width;
            self.takes_else[self.depth] = false;
            return synthetic(.indent, pos);
        }
        if (width == self.column) {
            self.takes_else[self.depth] = false;
            return nl;
        }

        var closed: u32 = 0;
        while (self.column > width) {
            if (self.depth == 0) return self.fail(.bad_dedent, pos);
            self.depth -= 1;
            self.column = self.levels[self.depth];
            closed += 1;
        }
        if (self.column != width) return self.fail(.bad_dedent, pos);

        self.pending_outdents = closed - 1;
        self.pending_pos = pos;
        if (self.takes_else[self.depth] and self.startsWithContinuation(pos)) {
            self.pending_newline = false;
        } else {
            self.pending_newline = true;
            self.takes_else[self.depth] = false;
        }
        return synthetic(.outdent, pos);
    }

    /// The line at `pos` starts with `else` or `catch`, which continue the
    /// block that just closed, so no NEWLINE separates them.
    fn startsWithContinuation(self: *const Lexer, pos: u32) bool {
        var probe = self.base;
        probe.pos = pos;
        const tok = probe.matchRules();
        if (tok.cat != .ident) return false;
        const word = self.base.text(tok);
        return std.mem.eql(u8, word, "else") or std.mem.eql(u8, word, "catch");
    }

    fn endOfInput(self: *Lexer, eof: Token) Token {
        if (self.depth > 0) {
            self.pending_outdents = self.depth - 1;
            self.pending_pos = eof.pos;
            self.depth = 0;
            self.column = 0;
            return synthetic(.outdent, eof.pos);
        }
        return eof;
    }

    // -------------------------------------------------------------------------
    // Classification
    // -------------------------------------------------------------------------

    fn classify(self: *Lexer, tok: Token) Token {
        // The bracket around an island closes: so do the island's blocks.
        if ((tok.cat == .rparen or tok.cat == .rbracket) and self.inIsland()) {
            if (self.closeIsland(tok.pos, tok)) |outdent| return outdent;
        }
        var out = tok;
        out.cat = switch (tok.cat) {
            .ident => self.classifyWord(tok),
            .dot => if (self.isEnumLiteralDot(tok)) .dot_lit else .dot,
            .lparen, .lbracket => blk: {
                if (self.nesting == max_nesting) return self.fail(.nesting_too_deep, tok.pos);
                self.brackets[self.nesting] = self.base.source[tok.pos];
                self.nesting += 1;
                if (!self.touchesValue(tok)) break :blk tok.cat;
                break :blk if (tok.cat == .lparen) .lparen_call else .lbracket_index;
            },
            .rparen, .rbracket => blk: {
                if (self.nesting > 0) self.nesting -= 1;
                break :blk tok.cat;
            },
            .minus => self.classifyMinus(tok),
            .lt => if (self.isPrefix(tok)) .move_pfx else .lt,
            .plus => if (self.isPrefix(tok)) .clone_pfx else .plus,
            .star => if (self.isPrefix(tok) or self.isOwnedClosureStar(tok)) .share_pfx else .star,
            .at => if (self.isPrefix(tok) and !self.isBuiltinCall(tok)) .pin_pfx else .at,
            .question => if (self.touchesValue(tok)) .suffix_q else if (self.isPrefix(tok)) .read_pfx else .question,
            .not_sym => if (self.touchesValue(tok)) .suffix_bang else if (self.isPrefix(tok)) .write_pfx else .not_sym,
            .bar => if (self.isCaptureBar(tok)) .bar_capture else .bar,
            .and_sym => return self.fail(.and_operator, tok.pos),
            // `||` where an operand starts is an empty closure bar list.
            .or_sym => if (!isValue(self.last_cat) or (self.spacedBefore(tok) and self.touchesNext(tok))) blk: {
                self.closed_bars = true;
                break :blk .bar_empty;
            } else return self.fail(.or_operator, tok.pos),
            .power => return self.fail(.power_operator, tok.pos),
            .err => return self.fail(self.lexErrorAt(tok), tok.pos),
            else => tok.cat,
        };
        switch (out.cat) {
            .@"if", .@"while", .@"for", .@"try" => self.takes_else[self.depth] = true,
            else => {},
        }
        return out;
    }

    fn classifyWord(self: *const Lexer, tok: Token) TokenCat {
        const word = self.base.text(tok);
        if (keyword(word)) |kw| switch (kw) {
            .@"if" => {
                switch (self.last_cat) {
                    .@"return", .@"break", .@"continue" => return .post_if,
                    else => {},
                }
                if (!isValue(self.last_cat)) return .@"if";
                return if (self.elseFollows()) .ternary_if else .post_if;
            },
            .@"new" => return if (self.atStatementStart() and self.nextIsName()) .@"new" else .ident,
            else => return kw,
        };
        if (self.inParens() and self.nextCat() == .colon) return .kwarg_name;
        return .ident;
    }

    /// `-` is infix when spaced after or attached to a value (`a - b`,
    /// `a-b`); otherwise a prefix: a drop when `-name` is a whole
    /// statement, negation otherwise.
    fn classifyMinus(self: *const Lexer, tok: Token) TokenCat {
        if (!self.isPrefix(tok)) return .minus;
        if ((self.atStatementStart() or self.last_cat == .@"defer" or self.last_cat == .@"errdefer") and
            self.isWholeDropStatement())
        {
            return .drop_stmt;
        }
        return .minus_prefix;
    }

    /// After `-` comes a name and then the end of the line, a comment, or
    /// a postfix guard.
    fn isWholeDropStatement(self: *const Lexer) bool {
        var probe = self.base;
        const name = probe.matchRules();
        if (name.cat != .ident or name.pre != 0 or keyword(self.base.text(name)) != null) return false;
        const after = probe.matchRules();
        return switch (after.cat) {
            .newline, .eof, .comment => true,
            .ident => std.mem.eql(u8, self.base.text(after), "if"),
            else => false,
        };
    }

    /// The character touches its operand, and does not touch a preceding
    /// value (`<x`, `f <x`, but not `a<b` or `a < b`).
    fn isPrefix(self: *const Lexer, tok: Token) bool {
        const end = tok.pos + tok.len;
        if (end >= self.base.source.len or !isOperandStart(self.base.source[end])) return false;
        return !isValue(self.last_cat) or self.spacedBefore(tok);
    }

    /// The token touches the value before it (`f(`, `a[`, `T?`, `x!`).
    fn touchesValue(self: *const Lexer, tok: Token) bool {
        return isValue(self.last_cat) and !self.spacedBefore(tok);
    }

    fn spacedBefore(self: *const Lexer, tok: Token) bool {
        return tok.pre > 0 or self.joined;
    }

    /// `.name` starts an enum literal unless it touches a value (member
    /// access). A `.` that begins a continuation line inside brackets is
    /// member access, so method chains can be split across lines.
    fn isEnumLiteralDot(self: *const Lexer, tok: Token) bool {
        const end = tok.pos + tok.len;
        if (end >= self.base.source.len or !isIdentStart(self.base.source[end])) return false;
        if (!isValue(self.last_cat)) return true;
        return tok.pre > 0 and !self.joined;
    }

    /// `@name(` is a builtin call; `@name` alone is the (reserved) pin.
    fn isBuiltinCall(self: *const Lexer, tok: Token) bool {
        var p = tok.pos + tok.len;
        const src = self.base.source;
        while (p < src.len and isIdentCont(src[p])) p += 1;
        return p < src.len and src[p] == '(';
    }

    /// `*` directly before a closure's bar list: `*|+v| ...`, `*|| ...`.
    fn isOwnedClosureStar(self: *const Lexer, tok: Token) bool {
        const end = tok.pos + tok.len;
        if (end >= self.base.source.len or self.base.source[end] != '|') return false;
        return !isValue(self.last_cat) or self.spacedBefore(tok);
    }

    /// The token touches the one after it.
    fn touchesNext(self: *const Lexer, tok: Token) bool {
        const end = tok.pos + tok.len;
        return end < self.base.source.len and isOperandStart(self.base.source[end]);
    }

    /// An opening bar touches its first entry and is followed by
    /// `entry (, entry)*` and a closing bar touching the last entry. An
    /// entry is a sigiled capture (`+x`, `<x`, `~x`) or a parameter name
    /// with an optional type (`a`, `a: Int`, `f: *fun(Int) Int`). The
    /// closing bar is recognized by position.
    fn isCaptureBar(self: *Lexer, tok: Token) bool {
        if (self.capture_close) |close| if (close == tok.pos) {
            self.capture_close = null;
            self.closed_bars = true;
            return true;
        };
        if (!self.isPrefix(tok)) return false;
        var probe = self.base;
        while (true) {
            var t = probe.matchRules();
            if (t.cat == .plus or t.cat == .lt or t.cat == .tilde) {
                const name = probe.matchRules();
                if (name.pre != 0) return false;
                t = name;
            }
            if (t.cat != .ident or keyword(self.base.text(t)) != null) return false;
            var sep = probe.matchRules();
            if (sep.cat == .colon) sep = skipType(&probe) orelse return false;
            switch (sep.cat) {
                .bar => {
                    if (sep.pre != 0) return false;
                    self.capture_close = sep.pos;
                    return true;
                },
                .comma => {},
                else => return false,
            }
        }
    }

    /// Skip a parameter type in a bar list; returns the token after it
    /// (a `,` or `|` outside brackets), or null if the tokens cannot be a
    /// type.
    fn skipType(probe: *BaseLexer) ?Token {
        var depth: u32 = 0;
        while (true) {
            const t = probe.matchRules();
            switch (t.cat) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    if (depth == 0) return null;
                    depth -= 1;
                },
                .comma, .bar => if (depth == 0) return t,
                .ident, .integer, .dot, .question, .not_sym, .star, .tilde => {},
                else => return null,
            }
        }
    }

    /// Scan ahead on the current logical line for an `else` at this
    /// nesting level (the ternary form `a if c else b`).
    fn elseFollows(self: *const Lexer) bool {
        var probe = self.base;
        var depth: u32 = 0;
        while (true) {
            const t = probe.matchRules();
            switch (t.cat) {
                .eof => return false,
                .newline => if (depth == 0 and (self.nesting == 0 or self.inIsland())) return false,
                .lparen, .lbracket, .lbrace => depth += 1,
                .rparen, .rbracket, .rbrace => {
                    if (depth == 0) return false;
                    depth -= 1;
                },
                .comma => if (depth == 0) return false,
                .ident => if (depth == 0 and std.mem.eql(u8, self.base.text(t), "else")) return true,
                else => {},
            }
        }
    }

    fn atStatementStart(self: *const Lexer) bool {
        return switch (self.last_cat) {
            .newline, .indent, .outdent, .eof => true,
            else => false,
        };
    }

    fn inParens(self: *const Lexer) bool {
        return self.nesting > 0 and self.brackets[self.nesting - 1] == '(';
    }

    fn nextCat(self: *const Lexer) TokenCat {
        var probe = self.base;
        return probe.matchRules().cat;
    }

    fn nextIsName(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.matchRules();
        return t.cat == .ident and keyword(self.base.text(t)) == null;
    }

    fn lexErrorAt(self: *const Lexer, tok: Token) LexError {
        const c = self.base.source[tok.pos];
        return if (c == '"' or c == '\'') .unterminated_string else .bad_char;
    }
};

/// Token categories that end an operand: a following `(` / `[` / `?` /
/// `!` touching one of these is a suffix, not a prefix.
fn isValue(cat: TokenCat) bool {
    return switch (cat) {
        .ident, .integer, .real, .string_sq, .string_dq, .@"true", .@"false",
        .rparen, .rbracket, .suffix_q, .suffix_bang,
        => true,
        else => false,
    };
}

fn isOperandStart(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9') or switch (c) {
        '(', '[', '"', '\'', '.', '<', '?', '!', '+', '-', '*', '~', '@' => true,
        else => false,
    };
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentCont(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

// =============================================================================
// Parser — post-parse rewrites and diagnostics over the generated BaseParser
// =============================================================================

pub const Parser = struct {
    base: BaseParser,
    /// Set when parsing succeeded but the tree was rejected.
    failure: ?diag.Diagnostic = null,

    /// Every pass walks the tree recursively; deeper trees are rejected
    /// here instead of exhausting the stack later.
    pub const max_tree_depth = 1000;

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Parser {
        return .{ .base = BaseParser.init(alloc, source) };
    }

    pub fn deinit(self: *Parser) void {
        self.base.deinit();
    }

    /// Parse and rewrite into the semantic IR. On `error.ParseError`,
    /// `diagnostic()` describes the failure.
    pub fn parseProgram(self: *Parser) !Sexp {
        const tree = try self.walk(try self.parseTree());
        if (self.failure != null) return error.ParseError;
        return tree;
    }

    /// Parse without the IR rewrites: the grammar's own output.
    pub fn parseTree(self: *Parser) !Sexp {
        // A file with no statements is an empty module; the grammar's
        // `program` needs at least one.
        if (self.base.current.cat == .eof) {
            const empty = try self.allocator().alloc(Sexp, 1);
            empty[0] = .{ .tag = .@"module" };
            return .{ .list = empty };
        }
        const tree = try self.base.parseProgram();
        if (tooDeep(tree, 0)) |pos| {
            self.failure = .{ .severity = .@"error", .pos = pos, .message = "expression is nested too deeply" };
            return error.ParseError;
        }
        return tree;
    }

    /// Position inside the first subtree nested deeper than
    /// `max_tree_depth`, or null.
    fn tooDeep(sexp: Sexp, depth: u32) ?u32 {
        const items = switch (sexp) {
            .list => |l| l,
            else => return null,
        };
        if (depth == max_tree_depth) return firstPos(sexp);
        for (items) |item| if (tooDeep(item, depth + 1)) |pos| return pos;
        return null;
    }

    /// The first source position in `sexp` (without recursion: the
    /// subtree may be arbitrarily deep).
    fn firstPos(sexp: Sexp) u32 {
        var node = sexp;
        descend: while (node == .list) {
            for (node.list) |item| if (item == .src) return item.src.pos;
            for (node.list) |item| if (item == .list) {
                node = item;
                continue :descend;
            };
            break;
        }
        return if (node == .src) node.src.pos else 0;
    }

    /// Why parsing failed: at the token where the parser stopped, or the
    /// rejected tree.
    pub fn diagnostic(self: *Parser) diag.Diagnostic {
        if (self.failure) |f| return f;
        const tok = self.base.current;
        const src = self.base.source;
        const message: []const u8 = switch (tok.cat) {
            .err => self.base.lexer.err.message(),
            .eof => return .{ .severity = .@"error", .pos = self.base.lexer.prev_end, .message = "unexpected end of file" },
            .outdent => return .{ .severity = .@"error", .pos = self.base.lexer.prev_end, .message = "unexpected end of block" },
            .newline => "unexpected end of line",
            .indent => "unexpected indentation",
            .post_if => "a postfix `if` guard must end a statement; write `a if c else b` for a value",
            .ident => self.format("unexpected name `{s}`", .{src[tok.pos..][0..tok.len]}),
            else => if (keyword(src[tok.pos..][0..tok.len]) != null)
                self.format("unexpected keyword `{s}`", .{src[tok.pos..][0..tok.len]})
            else
                self.format("unexpected `{s}`", .{src[tok.pos..][0..tok.len]}),
        };
        return .{ .severity = .@"error", .pos = tok.pos, .message = message };
    }

    fn format(self: *Parser, comptime fmt: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.allocator(), fmt, args) catch "unexpected token";
    }

    fn allocator(self: *Parser) std.mem.Allocator {
        return self.base.arena.allocator();
    }

    // -------------------------------------------------------------------------
    // Rewrites that need to inspect the tree:
    //
    //   * every node gets all the slots its schema (`ir.zig`) gives it:
    //     absent trailing optional slots become `_`;
    //   * `for` source sigils move into the mode slot:
    //       (for iter x _ (read xs) body)  →  (for read x _ xs body)
    //   * a closure's bar list splits into its captures and parameters:
    //       (lambda ((cap_clone v) a) ...)  →  (lambda (captures (cap_clone v)) (a) ...)
    //   * a `-name` statement whose value is used is negation, not a drop:
    //     the last statement of a `fun` body, or of a branch or arm whose
    //     value is used, becomes (neg name).
    // -------------------------------------------------------------------------

    pub fn rewrite(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        return self.walk(sexp);
    }

    fn walk(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        const items = switch (sexp) {
            .list => |l| l,
            else => return sexp,
        };
        const walked = try self.allocator().alloc(Sexp, items.len);
        for (items, 0..) |child, i| walked[i] = try self.walk(child);
        if (walked.len >= 2 and walked[0] == .tag and walked[0].tag == .@"lambda") try self.splitBars(walked);
        const out = try ir.pad(self.allocator(), walked);
        if (out.len == 0 or out[0] != .tag) return .{ .list = out };
        switch (out[0].tag) {
            .@"for" => normFor(out),
            // (fun name params returns body): the body's value is returned.
            .@"fun" => if (out.len >= 5 and out[3] != .nil) valueTail(out[4]),
            // (set kind target type expr): the expression's value is bound.
            .@"set" => if (out.len >= 5) valueTail(out[4]),
            else => {},
        }
        return .{ .list = out };
    }

    /// `(lambda entries ...)`: sigiled entries are captures, the rest
    /// parameters. Captures come first.
    fn splitBars(self: *Parser, items: []Sexp) std.mem.Allocator.Error!void {
        const entries: []const Sexp = if (items[1] == .list) items[1].list else &.{};
        var caps: std.ArrayListUnmanaged(Sexp) = .empty;
        var params: std.ArrayListUnmanaged(Sexp) = .empty;
        try caps.append(self.allocator(), .{ .tag = .@"captures" });
        for (entries) |e| {
            const is_capture = e == .list and e.list.len > 0 and e.list[0] == .tag and switch (e.list[0].tag) {
                .@"cap_clone", .@"cap_move", .@"cap_weak" => true,
                else => false,
            };
            if (!is_capture) {
                try params.append(self.allocator(), e);
                continue;
            }
            if (params.items.len > 0 and self.failure == null) {
                self.failure = .{ .severity = .@"error", .pos = firstPos(e), .message = "captures come before parameters in a closure's bar list: `|+v, a| ...`" };
            }
            try caps.append(self.allocator(), e);
        }
        items[1] = if (caps.items.len > 1) .{ .list = caps.items } else .nil;
        if (items.len >= 3) items[2] = if (params.items.len > 0) .{ .list = params.items } else .nil;
    }

    /// `sexp` (already walked, so its lists are freshly allocated) is in
    /// value position: a trailing `(drop x)` there is `(neg x)`.
    fn valueTail(sexp: Sexp) void {
        if (sexp != .list or sexp.list.len == 0 or sexp.list[0] != .tag) return;
        const items = @constCast(sexp.list);
        switch (items[0].tag) {
            .@"drop" => items[0] = .{ .tag = .@"neg" },
            .@"block" => if (items.len >= 2) valueTail(items[items.len - 1]),
            .@"if" => {
                valueTail(items[2]);
                valueTail(items[3]);
            },
            .@"match" => for (items[2..]) |arm| valueTail(arm.list[2]),
            else => {},
        }
    }

    /// Promote the source's `?xs` / `!xs` / `<xs` wrapper into the mode.
    fn normFor(items: []Sexp) void {
        if (items[1] != .tag or items[1].tag != .iter) return;
        const source = items[4];
        if (source != .list or source.list.len < 2 or source.list[0] != .tag) return;
        switch (source.list[0].tag) {
            .@"read", .@"write", .@"move" => {
                items[1] = source.list[0];
                items[4] = source.list[1];
            },
            else => {},
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn expectCats(source: []const u8, expected: []const TokenCat) !void {
    var lx = Lexer.init(source);
    for (expected) |want| {
        const got = lx.next();
        testing.expectEqual(want, got.cat) catch |e| {
            std.debug.print("source: {s}\n  at `{s}`\n", .{ source, lx.text(got) });
            return e;
        };
    }
}

test "keywords are reserved; `new` only at statement start" {
    try testing.expectEqual(TokenCat.@"else", keyword("else").?);
    try testing.expect(keyword("fn") == null);
    try testing.expect(keyword("var") == null);
    try expectCats("new x = 1", &.{ .@"new", .ident, .assign, .integer });
    try expectCats("p = Point.new(1)", &.{ .ident, .assign, .ident, .dot, .ident, .lparen_call, .integer, .rparen });
}

test "spacing decides prefix vs infix" {
    try expectCats("a < b", &.{ .ident, .lt, .ident });
    try expectCats("a<b", &.{ .ident, .lt, .ident });
    try expectCats("f <x", &.{ .ident, .move_pfx, .ident });
    try expectCats("a * b", &.{ .ident, .star, .ident });
    try expectCats("x = *b", &.{ .ident, .assign, .share_pfx, .ident });
    try expectCats("a | b | c", &.{ .ident, .bar, .ident, .bar, .ident });
    try expectCats("f = |a, +b| a", &.{ .ident, .assign, .bar_capture, .ident, .comma, .clone_pfx, .ident, .bar_capture, .ident });
    try expectCats("f(x) f (x)", &.{ .ident, .lparen_call, .ident, .rparen, .ident, .lparen, .ident, .rparen });
    try expectCats("a[i] f [1]", &.{ .ident, .lbracket_index, .ident, .rbracket, .ident, .lbracket, .integer, .rbracket });
    try expectCats("a.b f .c", &.{ .ident, .dot, .ident, .ident, .dot_lit, .ident });
    try expectCats("return .red", &.{ .@"return", .dot_lit, .ident });
    try expectCats("T? x!", &.{ .ident, .suffix_q, .ident, .suffix_bang });
}

test "minus: infix, negation, drop" {
    try expectCats("a - b", &.{ .ident, .minus, .ident });
    try expectCats("a -b", &.{ .ident, .minus_prefix, .ident });
    try expectCats("-x", &.{.drop_stmt, .ident});
    try expectCats("-x + 1", &.{ .minus_prefix, .ident, .plus, .integer });
    try expectCats("y = -x", &.{ .ident, .assign, .minus_prefix, .ident });
}

test "if: block, guard, ternary" {
    try expectCats("if c", &.{ .@"if", .ident });
    try expectCats("return if c", &.{ .@"return", .post_if, .ident });
    try expectCats("return x if c", &.{ .@"return", .ident, .post_if, .ident });
    try expectCats("x = a if c else b", &.{ .ident, .assign, .ident, .ternary_if, .ident, .@"else", .ident });
    try expectCats("f(a if c else b)", &.{ .ident, .lparen_call, .ident, .ternary_if, .ident, .@"else", .ident, .rparen });
}

test "layout: indentation, joined lines, tabs" {
    try expectCats("a\n  b\nc", &.{ .ident, .indent, .ident, .outdent, .newline, .ident, .eof });
    try expectCats("f(1,\n  2)\nx", &.{ .ident, .lparen_call, .integer, .comma, .integer, .rparen, .newline, .ident });
    try expectCats("a\n\tb", &.{ .ident, .err });
    try expectCats("a\n    b\n  c", &.{ .ident, .indent, .ident, .err });
}

test "closure bar lists: typed parameters, empty bars, owned star" {
    try expectCats("f = |+v, a: Int| a", &.{ .ident, .assign, .bar_capture, .clone_pfx, .ident, .comma, .ident, .colon, .ident, .bar_capture, .ident });
    try expectCats("g = || 1", &.{ .ident, .assign, .bar_empty, .integer });
    try expectCats("h = *|a| a", &.{ .ident, .assign, .share_pfx, .bar_capture, .ident, .bar_capture, .ident });
    try expectCats("x = a | b", &.{ .ident, .assign, .ident, .bar, .ident });
    try expectCats("x = a * b", &.{ .ident, .assign, .ident, .star, .ident });
    try expectCats("x = a || b", &.{ .ident, .assign, .ident, .err });
}

test "layout: a closure body inside brackets is laid out in blocks" {
    try expectCats("f(*|x|\n  g(x)\n  h)\ny", &.{
        .ident,  .lparen_call, .share_pfx, .bar_capture, .ident, .bar_capture,
        .indent, .ident,       .lparen_call, .ident,     .rparen, .newline,
        .ident,  .outdent,     .rparen,    .newline,     .ident,
    });
    // Coming back to the closure's line ends the body.
    try expectCats("f(||\n  g\n, 1)", &.{ .ident, .lparen_call, .bar_empty, .indent, .ident, .outdent, .comma, .integer, .rparen });
}

test "writeZigIdent escapes Zig keywords and emitter names" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeZigIdent(&w, "var");
    try w.writeAll(" ");
    try writeZigIdent(&w, "u8");
    try w.writeAll(" ");
    try writeZigIdent(&w, "rig");
    try w.writeAll(" ");
    try writeZigIdent(&w, "count");
    try testing.expectEqualStrings("@\"var\" @\"u8\" @\"rig'\" count", w.buffered());
}

test "parser: for-source sigil moves into the mode slot" {
    var read_items = [_]Sexp{ .{ .tag = .@"read" }, .{ .str = "xs" } };
    var raw_items = [_]Sexp{
        .{ .tag = .@"for" },  .{ .tag = .iter }, .{ .str = "x" }, .nil,
        .{ .list = &read_items }, .{ .str = "body" },
    };
    var p = Parser.init(testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(.{ .list = &raw_items });
    try testing.expectEqual(Tag.@"read", out.list[1].tag);
    try testing.expect(out.list[4] == .str);
}
