//! Rig language module for the Nexus-generated parser (src/parser.zig).
//!
//! The generated parser has two stages, each wrapped here and auto-wired
//! in by Nexus through `@hasDecl`:
//!
//!   stage   generated (parser.zig)   wrapper (this file)
//!   lex     BaseLexer                Lexer   — layout, keywords, position
//!   parse   BaseParser               Parser  — post-parse IR rewrites,
//!                                              diagnostics
//!
//! so `parser.Parser.init(allocator, source).parseProgram()` returns the
//! semantic IR described in docs/INTERNALS.md.
//!
//! Also here: `Tag` (re-exported from the generated parser), IR helpers
//! over the generated accessors, `BindingKind`, and the identifier
//! escaping that emit needs (`writeZigIdent`).

const std = @import("std");
const parser = @import("parser.zig");
const diag = @import("diag.zig");
const ir = parser.ir;
const BaseLexer = parser.BaseLexer;
const BaseParser = parser.BaseParser;
const Token = parser.Token;
const TokenCat = parser.TokenCat;
const Sexp = parser.Sexp;

// =============================================================================
// Tag and IR helpers
// =============================================================================

/// Every node kind and marker tag of the IR, generated from the `@schema`
/// in rig.grammar (which also gives each kind's roles).
pub const Tag = parser.Tag;

/// The declared return type of a `fun`; `_` for a `sub`, which has none.
pub fn returnType(fun_or_sub: Sexp) Sexp {
    return if (fun_or_sub.isKind(.fun)) ir.Fun.returns(fun_or_sub) else .nil;
}

/// A fallible `sub`: `sub save(p: Page)!`.
pub fn subFails(fun_or_sub: Sexp) bool {
    return fun_or_sub.isKind(.sub) and ir.Sub.fails(fun_or_sub) != .nil;
}

/// A module-level constant (`name = value`, or a `pub` one). Passes take
/// them before the other declarations, so functions anywhere in the
/// module see them.
pub fn isModuleConst(decl: Sexp) bool {
    return (if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl).isKind(.set);
}

/// An `if` or `while` condition that binds: `a as x`, or parts joined by
/// `and`, one of them `a as x`. `as` binds tighter than `and`, so
/// `a as x and x > 0 and b as y` is
/// `(and (and (as a x) (> x 0)) (as b y))`: its parts are the leaves of
/// the left spine, checked in order, each binding visible to the parts
/// after it and to the body.
pub fn bindsInCondition(cond: Sexp) bool {
    if (cond.isKind(.as)) return true;
    if (!cond.isKind(.@"and")) return false;
    return ir.get(cond, .right).isKind(.as) or bindsInCondition(ir.get(cond, .left));
}

/// Whether `cond` joins two parts of a binding condition: an `and` on
/// its left spine.
pub fn isConditionJoin(cond: Sexp) bool {
    return cond.isKind(.@"and") and bindsInCondition(cond);
}

/// `x[...]`: an index, or compile-time arguments (sema tells which).
pub fn isBracketList(e: Sexp) bool {
    return e.isKind(.index) or e.isKind(.inst);
}

/// Whether a call of `callee` is a method call: a member, or a member
/// followed by a bracket list (`v.put[2](x)`).
pub fn isMethodCallee(callee: Sexp) bool {
    if (callee.isKind(.member)) return true;
    return isBracketList(callee) and ir.get(callee, .object).isKind(.member);
}

/// A slice, `xs[a..b]`: an index node whose index is a range.
pub fn isRangeIndex(e: Sexp) bool {
    return e.isKind(.index) and ir.Index.index(e).isKind(.@"..");
}

/// Every child of a node, in slot order (absent optional slots are `_`),
/// for passes that visit all of them; empty for a leaf. Passes that need
/// a particular child read it by role (`parser.ir`).
pub fn children(node: Sexp) []const Sexp {
    if (node.kind() == null) return &.{};
    return node.items()[1..];
}

// =============================================================================
// BindingKind — the op slot of (set <op> ...)
// =============================================================================

/// Exhaustive view of the op slot, so dispatch sites must handle every
/// kind: `_` → default, `fixed` (`const x =`, and `new const x =`),
/// `shadow` (`new x =`), and the compound assignments (`x op= e`, one per
/// binary arithmetic, wrapping, bitwise, and shift operator). Every kind
/// but `default` is named after its tag in the schema's `op:tag(...)` for
/// `set`. `new const x = e` is the tag `shadow_fixed`, decoded as `fixed`:
/// it binds as `const x = e` does, and only declaring the name tells the
/// two apart (`shadows`).
pub const BindingKind = enum {
    default,
    fixed,
    shadow,
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"+%=",
    @"-%=",
    @"*%=",
    @"&=",
    @"|=",
    @"^=",
    @"<<=",
    @">>=",

    comptime {
        for (@typeInfo(BindingKind).@"enum".field_names[1..]) |f| {
            if (!@hasField(Tag, f)) @compileError("BindingKind." ++ f ++ " is not a tag of the IR");
        }
    }

    /// The binary operator a compound assignment applies (`+=` applies
    /// `+`), or null for a plain binding or assignment.
    pub fn operator(k: BindingKind) ?Tag {
        return switch (k) {
            .default, .fixed, .shadow => null,
            inline else => |c| @field(Tag, @tagName(c)[0 .. @tagName(c).len - 1]),
        };
    }
};

/// Decode the op slot of `(set <op> ...)`. Nexus builds it from the
/// schema's `op:tag(...)`, so any other value is unreachable.
pub fn bindingKindOf(op: Sexp) BindingKind {
    return switch (op) {
        .nil => .default,
        .tag => |t| switch (t) {
            .shadow_fixed => .fixed,
            inline else => |c| if (@hasField(BindingKind, @tagName(c))) @field(BindingKind, @tagName(c)) else unreachable,
        },
        else => unreachable,
    };
}

/// Whether the op slot of `(set <op> ...)` binds a new name even where
/// one is already visible: `new x = e` and `new const x = e`.
pub fn shadows(op: Sexp) bool {
    return op == .tag and (op.tag == .shadow or op.tag == .shadow_fixed);
}

// =============================================================================
// Keywords
// =============================================================================

/// Every Rig keyword is reserved, except `new`, which is a keyword only
/// at the start of a statement followed by a name or `const` (`new x =
/// ...`, `new const x = ...`), so
/// `fun new(...)` and `Point.new(...)` stay ordinary names.
const keywords = std.StaticStringMap(TokenCat).initComptime(.{
    .{ "and", .@"and" },
    .{ "as", .as },
    .{ "async", .async },
    .{ "await", .await },
    .{ "break", .@"break" },
    .{ "catch", .@"catch" },
    .{ "const", .@"const" },
    .{ "continue", .@"continue" },
    .{ "defer", .@"defer" },
    .{ "drop", .drop },
    .{ "else", .@"else" },
    .{ "enum", .@"enum" },
    .{ "errdefer", .@"errdefer" },
    .{ "error", .@"error" },
    .{ "extern", .@"extern" },
    .{ "false", .false },
    .{ "for", .@"for" },
    .{ "fun", .fun },
    .{ "if", .@"if" },
    .{ "impl", .impl },
    .{ "in", .in },
    .{ "match", .match },
    .{ "new", .new },
    .{ "not", .not },
    .{ "or", .@"or" },
    .{ "pass", .pass },
    .{ "pub", .@"pub" },
    .{ "raw", .raw },
    .{ "return", .@"return" },
    .{ "struct", .@"struct" },
    .{ "sub", .sub },
    .{ "test", .@"test" },
    .{ "trait", .trait },
    .{ "true", .true },
    .{ "try", .@"try" },
    .{ "type", .type },
    .{ "use", .use },
    .{ "when", .when },
    .{ "where", .where },
    .{ "while", .@"while" },
    .{ "yield", .yield },
    .{ "zig", .zig },
});

/// The token category of a reserved word, or null for a plain name.
pub fn keyword(word: []const u8) ?TokenCat {
    return keywords.get(word);
}

// =============================================================================
// Zig identifiers for emitted code
// =============================================================================

const zig_keywords = std.StaticStringMap(void).initComptime(.{
    .{"addrspace"},   .{"align"},   .{"allowzero"},   .{"and"},
    .{"anyframe"},    .{"anytype"}, .{"asm"},         .{"break"},
    .{"callconv"},    .{"catch"},   .{"comptime"},    .{"const"},
    .{"continue"},    .{"defer"},   .{"else"},        .{"enum"},
    .{"errdefer"},    .{"error"},   .{"export"},      .{"extern"},
    .{"fn"},          .{"for"},     .{"if"},          .{"inline"},
    .{"linksection"}, .{"noalias"}, .{"noinline"},    .{"nosuspend"},
    .{"opaque"},      .{"or"},      .{"orelse"},      .{"packed"},
    .{"pub"},         .{"resume"},  .{"return"},      .{"struct"},
    .{"suspend"},     .{"switch"},  .{"test"},        .{"threadlocal"},
    .{"try"},         .{"union"},   .{"unreachable"}, .{"var"},
    .{"volatile"},    .{"while"},
});

const zig_primitives = std.StaticStringMap(void).initComptime(.{
    .{"anyerror"}, .{"anyopaque"},      .{"bool"},         .{"c_char"},
    .{"c_int"},    .{"c_long"},         .{"c_longdouble"}, .{"c_longlong"},
    .{"c_short"},  .{"c_uint"},         .{"c_ulong"},      .{"c_ulonglong"},
    .{"c_ushort"}, .{"comptime_float"}, .{"comptime_int"}, .{"f128"},
    .{"f16"},      .{"f32"},            .{"f64"},          .{"f80"},
    .{"false"},    .{"isize"},          .{"noreturn"},     .{"null"},
    .{"true"},     .{"type"},           .{"undefined"},    .{"usize"},
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
// Position
//   Whitespace inside an expression never picks a form. A character that
//   both starts and continues an operand (`<x` and `a < b`, `f(x)` and
//   `(x)`, `?T` and `T?`, `.red` and `a.b`) is one token, and the parser
//   tells the forms apart by where it stands. The lexer still reads
//   position where the parser cannot: after a value (a name, a literal,
//   `)`, `]`, or a `?` / `!` suffix) a character continues it; anywhere
//   else it starts an operand, as a prefix:
//
//     `|x| ...` starts a closure's bar list; after a value `|` is
//     bitwise or.
//
//     `-x` at the start of a statement (or a match arm) that is nothing
//     but `-name` is a drop; otherwise `-x` is negation.
//
//     A prefix sigil touches its operand: `- b` and `< x` are errors,
//     so `a <- b` is not quietly `a < -b`. After a type's `]` the
//     parser decides (`[2]?T`), and the Parser wrapper checks the touch.
//
//   Token boundaries still matter, as in `!=` and `==`: `=!` is one
//   token, and an error wherever it stands, so `x =!y` is never quietly
//   `x = !y`.
//
// `if`
//   After `return`/`break`/`continue` or a value, `if` is a postfix guard
//   (`return x if done`), or the inline ternary when an `else` follows on
//   the same logical line (`a if c else b`). Elsewhere it opens a block.
//
// `of`
//   After a value directly inside [ ], `of` separates a fill literal's
//   count from its element (`[n of x]`). Elsewhere it is a name.
//
// `unique`
//   After a struct header's name or type parameters, `unique` marks the
//   struct unique (`struct Random unique`). Elsewhere it is a name.
//
// `from`, `static`
//   After a function's result type, on its header's line, `from` says
//   what the result views (`-> ?Item from a, b`), and `static` right
//   after it says the result views only what lives for the whole
//   program (`-> String from static`). Elsewhere each is a name.
//
// `..`
//   Before `]` (past any line break, which is whitespace inside
//   brackets), `..` ends an open range (`xs[a..]`, `xs[..]`):
//   DOTDOT_OPEN, so the expression before it ends there.

pub const Lexer = struct {
    base: BaseLexer,

    // Indentation: `levels[0..depth]` are the enclosing block columns.
    levels: [max_indent_depth]u32 = undefined,
    depth: u32 = 0,
    /// Per depth: the current line there opened a block that `else` may
    /// continue (it has a block `if`, `while`, or `for`). An `else` after
    /// any other block (a match arm) is a new line.
    takes_else: [max_indent_depth + 1]bool = @splat(false),
    /// Per depth: the block is the member list of a struct, enum, or
    /// error set, where a keyword may name a field or method.
    in_members: [max_indent_depth + 1]bool = @splat(false),
    /// The first token of the current statement, after any `pub`, and
    /// where it starts.
    line_head: TokenCat = .eof,
    head_pos: u32 = 0,
    column: u32 = 0,
    pending_outdents: u32 = 0,
    pending_newline: bool = false,
    pending_pos: u32 = 0,

    // Positions of the open ( and [; newlines inside them are whitespace.
    brackets: [max_nesting]u32 = undefined,
    nesting: u32 = 0,

    /// Category of the last token returned.
    last_cat: TokenCat = .eof,
    /// The last token ends an operand (`isValue`, or a `?` / `!` suffix
    /// after one), so a character after it continues the operand.
    after_value: bool = false,
    /// The last token is a `:` that starts a statement, and so starts its
    /// label; the name after it is the label.
    label_colon: bool = false,
    /// The last token is a statement's label: a statement starts after
    /// it, and it ends no operand.
    after_label: bool = false,
    /// The bracket nesting of the `while` header being lexed, whose first
    /// `:` there starts the step; null outside one.
    while_header: ?u32 = null,
    /// The line is a function's header, past the `->` of its result
    /// type, where `from` may follow the type (`isResultFrom`).
    fun_arrow: bool = false,
    /// Start and end of the last real (non-layout) token; an unexpected
    /// end of block or file is reported at its end.
    prev_pos: u32 = 0,
    prev_end: u32 = 0,
    prev_cat: TokenCat = .eof,
    /// The real token before that one, which a parse error's hint reads.
    before_cat: TokenCat = .eof,
    before_pos: u32 = 0,
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
        islands_too_deep,
        and_operator,
        or_operator,
        or_fallback,
        power_operator,
        increment,
        decrement,
        slash_comment,
        pin_sigil,
        control_in_string,
        lone_cr,
        leading_zero,
        radix_case,
        bad_number,
        too_long,
        fixed_assign,
        detached_prefix,
        semicolon,
        brace,

        pub fn message(e: LexError) []const u8 {
            return switch (e) {
                .none => "invalid token",
                .bad_char => "invalid character",
                .unterminated_string => "unterminated string",
                .control_in_string => "control character in a string; write it as an escape (`\\t`, `\\n`) in a double-quoted string",
                .lone_cr => "carriage return without a line feed; end lines with `\\n` or `\\r\\n`",
                .leading_zero => "a decimal number has no leading zero",
                .radix_case => "radix prefixes are lowercase: `0x`, `0b`, `0o`",
                .bad_number => "malformed number; `_` may separate digits, and a space or an operator ends a number",
                .too_long => "token is longer than 65535 bytes",
                .fixed_assign => "Rig has no `=!`: a binding that never changes is `const x = e`, and `x = !y` lends `y` to write",
                .detached_prefix => "a prefix sigil touches its operand",
                .semicolon => "unexpected `;`",
                .brace => "Rig has no braces: a block is the lines indented under its header",
                .tab_indent => "tab in indentation; indent with spaces",
                .bad_dedent => "indentation does not match any enclosing block",
                .first_line_indented => "unexpected indentation",
                .indent_too_deep => "indentation is nested too deeply",
                .nesting_too_deep => "brackets are nested too deeply",
                .islands_too_deep => "closures laid out inside brackets are nested too deeply",
                .and_operator => "`&&` is not a Rig operator; use `and`",
                .or_operator => "`||` is not a Rig operator; use `or`, or `??` for an optional's fallback",
                .or_fallback => "`||` is not a Rig operator; a fallback value for an optional is written with `??`: `x ?? 0`",
                .power_operator => "`**` is not a Rig operator",
                .increment => "Rig has no `++`; write `x += 1`",
                .decrement => "Rig has no `--`; write `x -= 1`",
                .slash_comment => "comments start with `#`; Rig has no `//` or `/* */` comments",
                .pin_sigil => "the pin sigil `@x` is reserved; `@` only starts a builtin call, `@name(...)`",
            };
        }
    };

    pub fn init(source: []const u8) Lexer {
        var lexer: Lexer = .{ .base = BaseLexer.init(source) };
        if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) lexer.base.pos = 3; // a UTF-8 byte order mark
        return lexer;
    }

    pub fn next(self: *Lexer) Token {
        const tok = self.produce();
        self.after_label = self.label_colon and tok.cat == .ident;
        self.label_colon = tok.cat == .colon and self.stmtStart();
        self.after_value = !self.after_label and (isValue(tok.cat) or (self.after_value and (tok.cat == .question or tok.cat == .not_sym)));
        self.last_cat = tok.cat;
        switch (tok.cat) {
            .@"while" => self.while_header = self.nesting,
            .newline, .indent, .outdent, .eof, .step_colon => self.while_header = null,
            else => {},
        }
        switch (tok.cat) {
            .arrow => if (self.nesting == 0 and (self.line_head == .fun or self.line_head == .@"extern")) {
                self.fun_arrow = true;
            },
            .newline, .indent, .outdent, .eof => self.fun_arrow = false,
            else => {},
        }
        if (tok.len > 0 and tok.cat != .err) { // a real token, not layout
            self.before_cat = self.prev_cat;
            self.before_pos = self.prev_pos;
            self.prev_cat = tok.cat;
            self.prev_pos = tok.pos;
            self.prev_end = tok.pos + tok.len;
        }
        if (self.closed_bars) {
            self.closed_bars = false;
            if (self.nesting > 0 and !self.inIsland() and self.lineEndsAfter()) {
                if (self.island_count == max_islands) return self.fail(.islands_too_deep, tok.pos);
                const column = self.lineIndent(tok.pos);
                self.islands[self.island_count] = .{ .nesting = self.nesting, .depth = self.depth, .column = column, .outer_column = self.column };
                self.island_count += 1;
                self.column = column;
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
        var t = probe.next();
        if (t.cat == .comment) t = probe.next();
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
            const tok = self.base.next();
            switch (tok.cat) {
                .comment => continue,
                // A comment longer than a token can hold.
                .err => if (tok.len == std.math.maxInt(u16) and self.base.source[tok.pos] == '#') continue,
                .skip => continue, // `\` line continuation
                .newline => {
                    if (!self.inIsland() and (self.nesting > 0 or self.last_cat == .eof)) continue;
                    return self.lineBreak(tok);
                },
                .eof => return self.endOfInput(tok),
                else => {},
            }
            if (self.last_cat == .eof and tok.pre > 0) return self.firstLineIndented(tok);
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

    /// The first token of the file is indented: with a tab, or spaces.
    fn firstLineIndented(self: *Lexer, tok: Token) Token {
        const src = self.base.source;
        var start = tok.pos;
        while (start > 0 and (src[start - 1] == ' ' or src[start - 1] == '\t')) start -= 1;
        if (std.mem.findScalar(u8, src[start..tok.pos], '\t')) |tab| return self.fail(.tab_indent, start + @as(u32, @intCast(tab)));
        return self.fail(.first_line_indented, tok.pos);
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
                '\n' => {
                    line = p + 1;
                    continue;
                },
                '\r' => if (p + 1 < src.len and src[p + 1] == '\n') {
                    line = p + 2;
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
            self.in_members[self.depth] = switch (self.line_head) {
                .@"struct", .@"enum", .@"error" => true,
                else => false,
            };
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
        if (self.takes_else[self.depth] and self.startsWithElse(pos)) {
            self.pending_newline = false;
        } else {
            self.pending_newline = true;
            self.takes_else[self.depth] = false;
        }
        return synthetic(.outdent, pos);
    }

    /// The line at `pos` starts with `else`, which continues the block
    /// that just closed, so no NEWLINE separates them.
    fn startsWithElse(self: *const Lexer, pos: u32) bool {
        var probe = self.base;
        probe.pos = pos;
        const tok = probe.next();
        return tok.cat == .ident and std.mem.eql(u8, self.base.text(tok), "else");
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
        const after_value = self.after_value;
        var out = tok;
        out.cat = switch (tok.cat) {
            .ident => self.classifyWord(tok),
            .lparen, .lbracket => blk: {
                if (self.nesting == max_nesting) return self.fail(.nesting_too_deep, tok.pos);
                self.brackets[self.nesting] = tok.pos;
                self.nesting += 1;
                break :blk tok.cat;
            },
            .rparen, .rbracket => blk: {
                if (self.nesting > 0) self.nesting -= 1;
                break :blk tok.cat;
            },
            .minus => if (!after_value and self.stmtStart() and self.isWholeDropStatement()) .drop_stmt else .minus,
            .at => if (self.isBuiltinCall()) .at else return self.fail(.pin_sigil, tok.pos),
            .bar => if (self.isCaptureBar(tok, after_value)) .bar_capture else .bar,
            .and_sym => return self.fail(.and_operator, tok.pos),
            // `||` where an operand starts is an empty closure bar list.
            .or_sym => if (!after_value) blk: {
                self.closed_bars = true;
                break :blk .bar_empty;
            } else return self.fail(if (self.literalFollows()) .or_fallback else .or_operator, tok.pos),
            .slash => if (self.charAfter(tok) == '/' or self.charAfter(tok) == '*') return self.fail(.slash_comment, tok.pos) else .slash,
            .power => return self.fail(.power_operator, tok.pos),
            // `=!` is no operator: a binding that never changes is
            // `const x = e`, and `x =!y` would pass for `x = !y`.
            .fixed_assign => return self.fail(.fixed_assign, tok.pos),
            // `xs[a..]`: an open range ends at the `]`.
            .dotdot => if (self.nextJoined().cat == .rbracket) .dotdot_open else .dotdot,
            // `while i < n : i += 1`: the step; any other `:` in the
            // header, as after a jump (`?? break :outer`), is a label's.
            .colon => if (self.while_header == self.nesting) .step_colon else .colon,
            // `get(k) ?? return none`: a jump as the fallback.
            .nullish => if (self.nextIsJump()) .nullish_jump else .nullish,
            .err => return self.lexError(tok),
            else => tok.cat,
        };
        // A prefix sigil touches its operand (`-b`, `<x`, `*T`); `i++`
        // is no increment.
        if (!after_value and isSigil(tok.cat) and isSpace(self.charAfter(tok))) {
            const twice = tok.pos > 0 and self.base.source[tok.pos - 1] == self.base.source[tok.pos];
            if (twice and tok.cat == .plus) return self.fail(.increment, tok.pos - 1);
            if (twice and tok.cat == .minus) return self.fail(.decrement, tok.pos - 1);
            return self.fail(.detached_prefix, tok.pos);
        }
        switch (out.cat) {
            .@"if", .@"while", .@"for" => self.takes_else[self.depth] = true,
            else => {},
        }
        if (self.stmtStart() or self.last_cat == .@"pub") {
            self.line_head = out.cat;
            self.head_pos = tok.pos;
        }
        return out;
    }

    fn classifyWord(self: *const Lexer, tok: Token) TokenCat {
        const word = self.base.text(tok);
        if (keyword(word)) |kw| switch (kw) {
            .@"if" => {
                switch (self.last_cat) {
                    .@"return", .@"break", .@"continue", .pass => return .post_if,
                    else => {},
                }
                if (!self.after_value) return .@"if";
                return if (self.elseFollows()) .ternary_if else .post_if;
            },
            .new => return if (self.stmtStart() and (self.nextIsName() or self.nextIsConst())) .new else .ident,
            else => return self.memberName() orelse kw,
        };
        if (self.inParens() and self.nextCat() == .colon) return .kwarg_name;
        if (std.mem.eql(u8, word, "of") and self.isFillOf()) return .of;
        if (std.mem.eql(u8, word, "unique") and self.isStructUnique()) return .unique;
        if (std.mem.eql(u8, word, "from") and self.isResultFrom()) return .from;
        if (std.mem.eql(u8, word, "static") and self.last_cat == .from) return .static;
        return .ident;
    }

    /// `from` after a function's result type says what the result views
    /// (`fun first(a: ?T, b: ?T) -> ?T from a`); anywhere else it is a
    /// name.
    fn isResultFrom(self: *const Lexer) bool {
        return self.fun_arrow and self.after_value and self.nesting == 0;
    }

    /// `unique` after a struct header's name or its type parameters marks
    /// the struct unique (`struct Random unique`, `struct Ring[T] unique`);
    /// anywhere else it is a name.
    fn isStructUnique(self: *const Lexer) bool {
        return self.line_head == .@"struct" and self.nesting == 0 and
            (self.last_cat == .ident or self.last_cat == .rbracket);
    }

    /// `of` after a value directly inside [ ] separates a fill literal's
    /// count from its element (`[n of x]`); anywhere else it is a name.
    fn isFillOf(self: *const Lexer) bool {
        return self.after_value and self.nesting > 0 and !self.inIsland() and
            self.base.source[self.brackets[self.nesting - 1]] == '[';
    }

    /// A keyword names a member where nothing else can stand: after
    /// `.`, before `:` inside ( ) (a keyword argument or payload field),
    /// and in a member list before `:` (a field) or after `fun` / `sub`
    /// (a method). After `@` it names a builtin (`@type(x)`).
    fn memberName(self: *const Lexer) ?TokenCat {
        switch (self.last_cat) {
            .dot, .at => return .ident,
            .fun, .sub => return if (self.in_members[self.depth]) .ident else null,
            else => {},
        }
        if (self.nextCat() != .colon) return null;
        if (self.inParens()) return .kwarg_name;
        return if (self.in_members[self.depth] and (self.stmtStart() or self.last_cat == .@"pub")) .ident else null;
    }

    /// `-name` is a whole statement, a drop: after `-` comes a name and
    /// then the end of the line, a comment, or a postfix guard. Anywhere
    /// else, `-x` is negation.
    fn isWholeDropStatement(self: *const Lexer) bool {
        var probe = self.base;
        const name = probe.next();
        if (name.cat != .ident or keyword(self.base.text(name)) != null) return false;
        const after = probe.next();
        return switch (after.cat) {
            .newline, .eof, .comment => true,
            .ident => std.mem.eql(u8, self.base.text(after), "if"),
            else => false,
        };
    }

    /// `@name(...)` is a builtin call; `@name` alone is the reserved pin
    /// sigil.
    fn isBuiltinCall(self: *const Lexer) bool {
        var probe = self.base;
        const name = probe.next();
        if (name.cat != .ident) return false;
        return probe.next().cat == .lparen;
    }

    /// The character right after `tok`, or 0 at the end of the source.
    fn charAfter(self: *const Lexer, tok: Token) u8 {
        const end = tok.pos + tok.len;
        return if (end < self.base.source.len) self.base.source[end] else 0;
    }

    /// A `|` that starts an operand opens a closure's bar list:
    /// `entry (, entry)* [,]` and a closing bar. An entry is a sigiled
    /// capture (`+x`, `<x`, `~x`, `?x`, `!x`) or a parameter name with
    /// an optional type (`a`, `a: Int`, `f: *fun(Int) -> Int`). The
    /// closing bar is the one this probe finds.
    fn isCaptureBar(self: *Lexer, tok: Token, after_value: bool) bool {
        if (self.capture_close) |close| if (close == tok.pos) {
            self.capture_close = null;
            self.closed_bars = true;
            return true;
        };
        if (after_value) return false;
        var probe = self.base;
        while (true) {
            var t = probe.next();
            if (t.cat == .plus or t.cat == .lt or t.cat == .tilde or t.cat == .question or t.cat == .not_sym) t = probe.next();
            // A keyword entry still makes a bar list, so that the parser
            // reports the keyword (`|when: Int|`).
            if (t.cat != .ident) return true;
            var sep = probe.next();
            if (sep.cat == .colon) sep = skipType(&probe) orelse return true;
            switch (sep.cat) {
                .bar => {
                    self.capture_close = sep.pos;
                    return true;
                },
                .comma => {
                    var after = probe;
                    const close = after.next();
                    if (close.cat == .bar) {
                        self.capture_close = close.pos;
                        return true;
                    }
                },
                else => return true,
            }
        }
    }

    /// Skip a parameter type in a bar list; returns the token after it
    /// (a `,` or `|` outside brackets), or null if the tokens cannot be a
    /// type.
    fn skipType(probe: *BaseLexer) ?Token {
        var depth: u32 = 0;
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    if (depth == 0) return null;
                    depth -= 1;
                },
                .comma, .bar => if (depth == 0) return t,
                .ident, .integer, .dot, .question, .not_sym, .star, .tilde, .arrow => {},
                // Arithmetic in an array size: `[N + 1]Int`.
                .plus, .minus, .slash, .percent => if (depth == 0) return null,
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
            const t = probe.next();
            switch (t.cat) {
                .eof => return false,
                .newline => if (depth == 0 and (self.nesting == 0 or self.inIsland())) return false,
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    if (depth == 0) return false;
                    depth -= 1;
                },
                .comma => if (depth == 0) return false,
                .ident => if (depth == 0 and std.mem.eql(u8, self.base.text(t), "else")) return true,
                else => {},
            }
        }
    }

    /// A statement starts here: at the start of a line, after `=>`,
    /// `defer`, or `errdefer`, or after a statement's label (`:outer`).
    fn stmtStart(self: *const Lexer) bool {
        return self.after_label or switch (self.last_cat) {
            .newline, .indent, .outdent, .eof, .fat_arrow, .@"defer", .@"errdefer" => true,
            else => false,
        };
    }

    /// Directly inside ( ), not in a closure body laid out there.
    fn inParens(self: *const Lexer) bool {
        return self.nesting > 0 and !self.inIsland() and self.base.source[self.brackets[self.nesting - 1]] == '(';
    }

    fn nextCat(self: *const Lexer) TokenCat {
        var probe = self.base;
        return probe.next().cat;
    }

    /// The next token, past comments, `\` line joins, and line breaks
    /// where they are whitespace (inside brackets).
    fn nextJoined(self: *const Lexer) Token {
        var probe = self.base;
        const joins = self.nesting > 0 and !self.inIsland();
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .comment, .skip => continue,
                .newline => if (!joins) return t,
                else => return t,
            }
        }
    }

    /// The next token is `return`, `break`, or `continue`.
    fn nextIsJump(self: *const Lexer) bool {
        const t = self.nextJoined();
        if (t.cat != .ident) return false;
        const kw = keyword(self.base.text(t)) orelse return false;
        return kw == .@"return" or kw == .@"break" or kw == .@"continue";
    }

    /// A literal comes next: a number, a string, or an array.
    fn literalFollows(self: *const Lexer) bool {
        return switch (self.nextJoined().cat) {
            .integer, .real, .string_sq, .string_dq, .lbracket => true,
            else => false,
        };
    }

    fn nextIsName(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.next();
        return t.cat == .ident and keyword(self.base.text(t)) == null;
    }

    fn nextIsConst(self: *const Lexer) bool {
        var probe = self.base;
        const t = probe.next();
        return t.cat == .ident and std.mem.eql(u8, self.base.text(t), "const");
    }

    /// Why the grammar produced an `err` token.
    fn lexError(self: *Lexer, tok: Token) Token {
        if (tok.len == std.math.maxInt(u16)) return self.fail(.too_long, tok.pos);
        const t = self.base.text(tok);
        return switch (t[0]) {
            '"', '\'' => self.stringError(tok.pos),
            '0'...'9' => self.fail(if (t.len > 1 and t[0] == '0' and std.mem.findScalar(u8, "XBO", t[1]) != null)
                .radix_case
            else if (t.len > 1 and t[0] == '0' and (std.ascii.isDigit(t[1]) or t[1] == '_'))
                .leading_zero
            else
                .bad_number, tok.pos),
            '\r' => self.fail(.lone_cr, tok.pos),
            ';' => self.fail(.semicolon, tok.pos),
            '{', '}' => self.fail(.brace, tok.pos),
            else => self.fail(.bad_char, tok.pos),
        };
    }

    /// A string starting at `open` that does not lex: a control character
    /// inside it, or no closing quote on its line.
    fn stringError(self: *Lexer, open: u32) Token {
        const src = self.base.source;
        const quote = src[open];
        var p = open + 1;
        while (p < src.len and src[p] != '\n') : (p += 1) {
            if (quote == '"' and src[p] == '\\' and p + 1 < src.len and src[p + 1] != '\n') {
                p += 1; // the escaped character
            } else if (src[p] == quote) {
                if (quote == '"' or p + 1 == src.len or src[p + 1] != quote) break;
                p += 1; // `''` in a single-quoted string
                continue;
            }
            const at_line_end = src[p] == '\r' and p + 1 < src.len and src[p + 1] == '\n';
            if ((src[p] < 0x20 or src[p] == 0x7f) and !at_line_end) return self.fail(.control_in_string, p);
        }
        return self.fail(.unterminated_string, open);
    }
};

/// Token categories that end an operand: a `(` / `[` / `?` / `!` or
/// another shared character after one of these continues it, as a
/// call, an index, a suffix, or an infix operator.
fn isValue(cat: TokenCat) bool {
    return switch (cat) {
        .ident,
        .integer,
        .real,
        .string_sq,
        .string_dq,
        .true,
        .false,
        .rparen,
        .rbracket,
        => true,
        else => false,
    };
}

/// The characters that start an operand as a prefix sigil.
fn isSigil(cat: TokenCat) bool {
    return switch (cat) {
        .minus, .lt, .plus, .star, .question, .not_sym, .tilde => true,
        else => false,
    };
}

/// Whitespace, or the end of the line or source, after a token.
fn isSpace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\r', '\n', '\\', '#', 0 => true,
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
    /// The definitions after the first rejected one that also leave
    /// out their parameter list, each reported, so that one run shows
    /// every header to fix.
    more_failures: std.ArrayList(diag.Diagnostic) = .empty,
    /// The node ids of the `(read place)`, `(write place)`, and
    /// `(move place)` receivers written in front of the call
    /// (`!v.push(x)`), not in parentheses.
    receiver_sigils: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// The node ids of the `-name` lines rewritten to `(neg name)`
    /// because their value is used, and whether it is a function's value.
    value_tails: std.AutoHashMapUnmanaged(parser.NodeId, bool) = .empty,
    /// The node ids of the `(share x)` and `(weak x)` whose operand has a
    /// `?` suffix inside parentheses that open right after the sigil
    /// (`*(T?)`), which the tree does not keep.
    paren_suffixes: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,
    /// The node ids of the fields and methods declared `pub`, which the
    /// member list holds without their `(pub ...)` wrapper.
    pub_members: std.AutoHashMapUnmanaged(parser.NodeId, void) = .empty,

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
        const tree = try self.rewrite(try self.parseTree());
        if (self.failure != null) return error.ParseError;
        return tree;
    }

    /// Parse without the IR rewrites: the grammar's own output.
    pub fn parseTree(self: *Parser) !Sexp {
        const tree = try self.base.parseProgram();
        if (tooDeep(tree, 0)) |deep| {
            self.reject(deep, "expression is nested too deeply or too long; split it with named intermediate values");
            return error.ParseError;
        }
        return tree;
    }

    /// Reject the tree at `node`, unless it is already rejected.
    fn reject(self: *Parser, node: Sexp, message: []const u8) void {
        if (self.failure != null) return;
        const at = self.span(node);
        self.failure = .{ .severity = .@"error", .pos = at.start, .end = at.end, .message = message };
    }

    /// The source span of a node (see `BaseParser.span`).
    pub fn span(self: *const Parser, sexp: Sexp) parser.Span {
        return self.base.span(sexp);
    }

    /// The first subtree nested `max_tree_depth` deep, or null.
    fn tooDeep(sexp: Sexp, depth: u32) ?Sexp {
        if (sexp != .list) return null;
        if (depth == max_tree_depth) return sexp;
        for (sexp.items()) |item| if (tooDeep(item, depth + 1)) |deep| return deep;
        return null;
    }

    /// Why parsing failed: at the token where the parser stopped, or the
    /// rejected tree. A token the parser did not expect is followed by
    /// what it expected there, when that is a short list.
    pub fn diagnostic(self: *Parser) diag.Diagnostic {
        if (self.failure) |f| return f;
        const failure = self.base.lastError().?;
        const tok = BaseLexer.makeToken(failure.cat, 0, failure.span.start, failure.span.end);
        const src = self.base.source;
        var pos = tok.pos;
        var end = tok.pos + tok.len;
        const lexer = &self.base.lexer;
        if (self.openRange(tok)) |d| return d;
        if (self.foreignWord(tok)) |d| return d;
        if (self.headerColon(tok)) |d| return d;
        const message: []const u8 = switch (tok.cat) {
            .err => return .{ .severity = .@"error", .pos = pos, .end = end, .message = switch (lexer.err) {
                .semicolon => self.semicolonMessage(tok),
                .detached_prefix => self.detachedPrefix(tok),
                .brace => self.format("unexpected `{c}`; {s}", .{ src[pos], lexer.err.message() }),
                else => lexer.err.message(),
            } },
            .eof, .outdent => blk: {
                pos = lexer.prev_end;
                end = pos;
                break :blk if (tok.cat == .eof) "unexpected end of file" else "unexpected end of block";
            },
            .newline => "unexpected end of line",
            .indent => "unexpected indentation",
            .post_if => "a postfix `if` guard must end a statement; write `a if c else b` for a value",
            .ident => self.format("unexpected name `{s}`", .{src[pos..end]}),
            else => if (keyword(src[pos..end]) != null)
                self.format("unexpected keyword `{s}`", .{src[pos..end]})
            else
                self.format("unexpected `{s}`", .{src[pos..end]}),
        };
        const expected = self.expectedHint(failure.state);
        const with_expected = if (expected) |hint| self.format("{s}; expected {s}", .{ message, hint }) else message;
        const hint = self.printHint(tok) orelse self.bracketHint(tok) orelse self.typeSuffixHint(tok) orelse tokenHint(tok) orelse reservedHint(src, tok, expected orelse "");
        const full = if (hint) |h| self.format("{s}; {s}", .{ with_expected, h }) else with_expected;
        return .{ .severity = .@"error", .pos = pos, .end = end, .message = full };
    }

    /// A range with a side left out where only a slice may leave one
    /// out: `for i in 0..`, `1.. =>`, `[..3]`. Reported at the `..`.
    fn openRange(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const at: Token, const side: []const u8 = switch (tok.cat) {
            .dotdot => .{ tok, "a start" },
            .dotdot_open => .{ tok, if (lexer.before_cat == .lbracket) "both ends" else "an end" },
            else => blk: {
                // The real token before this one; a layout token is not
                // one, so the last real token is.
                const cat, const pos = if (tok.len > 0) .{ lexer.before_cat, lexer.before_pos } else .{ lexer.prev_cat, lexer.prev_pos };
                if (cat != .dotdot or tok.cat == .err) return null;
                if (tok.cat == .assign and tok.pos == pos + 2) return self.inclusiveRange(pos);
                break :blk .{ .{ .cat = .dotdot, .pre = 0, .pos = pos, .len = 2 }, "an end" };
            },
        };
        return .{ .severity = .@"error", .pos = at.pos, .end = at.pos + at.len, .message = self.format("a range needs {s}; only a slice leaves a side open: `xs[a..]`, `xs[..b]`, `xs[..]`", .{side}) };
    }

    /// A word other languages use where Rig has its own form, at the
    /// start of a statement (`def f()`, `let x = 5`, `loop` before its
    /// block) or where it fails itself (`if x then`): reported at the
    /// word, with Rig's spelling.
    fn foreignWord(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const src = self.base.source;
        const at: Token = blk: {
            // The word the parser failed on, written where no Rig form
            // takes a name (`if x then`, `const x = 5`).
            if (tok.len > 0 and (tok.cat == .ident or keyword(src[tok.pos .. tok.pos + tok.len]) != null)) {
                const word = src[tok.pos .. tok.pos + tok.len];
                if (foreign_words.get(word)) |f| if (f.alone) break :blk tok;
            }
            // The statement's first word, right before the failure.
            const cat, const pos = if (tok.len > 0) .{ lexer.before_cat, lexer.before_pos } else .{ lexer.prev_cat, lexer.prev_pos };
            if (cat != .ident or pos != lexer.head_pos) return null;
            var end = pos;
            while (end < src.len and isIdentCont(src[end])) end += 1;
            break :blk BaseLexer.makeToken(.ident, 0, pos, end);
        };
        const word = src[at.pos .. at.pos + at.len];
        const f = foreign_words.get(word) orelse return null;
        return .{ .severity = .@"error", .pos = at.pos, .end = at.pos + at.len, .message = self.format("Rig has no `{s}`; {s}", .{ word, f.fix }) };
    }

    const Foreign = struct {
        fix: []const u8,
        /// Named even where the parse fails on the word itself, not only
        /// when it starts a statement: a keyword of Rig's, or a word that
        /// ends a header.
        alone: bool = false,
    };

    /// Other languages' words for forms Rig spells differently.
    const foreign_words = std.StaticStringMap(Foreign).initComptime(.{
        .{ "def", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "fn", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "func", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "function", Foreign{ .fix = "declare a function with `fun` (it returns a value) or `sub`" } },
        .{ "let", Foreign{ .fix = "bind a name with `x = 5`, or `const x = 5` for one that never changes" } },
        .{ "var", Foreign{ .fix = "bind a name with `x = 5`, or `const x = 5` for one that never changes" } },
        .{ "class", Foreign{ .fix = "declare a type with `struct`" } },
        .{ "impl", Foreign{ .fix = "methods go in the `struct` body", .alone = true } },
        .{ "switch", Foreign{ .fix = "write `match`" } },
        .{ "case", Foreign{ .fix = "a match arm is `pattern => ...`" } },
        .{ "elif", Foreign{ .fix = "write `else if`" } },
        .{ "elsif", Foreign{ .fix = "write `else if`" } },
        .{ "elseif", Foreign{ .fix = "write `else if`" } },
        .{ "unless", Foreign{ .fix = "write `if not`" } },
        .{ "until", Foreign{ .fix = "write `while not`" } },
        .{ "import", Foreign{ .fix = "use a module with `use name`" } },
        .{ "require", Foreign{ .fix = "use a module with `use name`" } },
        .{ "include", Foreign{ .fix = "use a module with `use name`" } },
        .{ "loop", Foreign{ .fix = "write `while true`" } },
        .{ "forever", Foreign{ .fix = "write `while true`" } },
        .{ "do", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
        .{ "begin", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
        .{ "then", Foreign{ .fix = "a block is the indented lines below the line that opens it", .alone = true } },
    });

    /// `if x:`, `while x:`, `struct S:`: a `:` ending a block's header,
    /// as in Python. Reported at the `:`.
    fn headerColon(self: *Parser, tok: Token) ?diag.Diagnostic {
        const lexer = &self.base.lexer;
        const src = self.base.source;
        const pos = switch (tok.cat) {
            // `while x:` reads the `:` as the start of a step.
            .indent, .newline => if (lexer.prev_cat == .step_colon) lexer.prev_pos else return null,
            .colon, .step_colon => blk: {
                var p = tok.pos + 1;
                while (p < src.len and (src[p] == ' ' or src[p] == '\r')) p += 1;
                if (p < src.len and src[p] != '\n' and src[p] != '#') return null;
                break :blk tok.pos;
            },
            else => return null,
        };
        return .{ .severity = .@"error", .pos = pos, .end = pos + 1, .message = "unexpected `:`; a block's header ends without one: remove the `:`, and indent the block below" };
    }

    /// `0..=3`: Rig's ranges exclude their end. Reported at the `..=`.
    fn inclusiveRange(self: *Parser, at: u32) diag.Diagnostic {
        var probe = BaseLexer.init(self.base.source);
        probe.pos = at + 3;
        const end = probe.next();
        const text = self.base.source[end.pos .. end.pos + end.len];
        const n = if (end.cat == .integer) std.fmt.parseInt(i64, text, 0) catch null else null;
        const fix = if (n) |v|
            self.format("`..={s}` is written `..{d}`", .{ text, v + 1 })
        else if (end.cat == .ident)
            self.format("`..={s}` is written `..{s} + 1`", .{ text, text })
        else
            "`..=b` is written `..b + 1`";
        return .{ .severity = .@"error", .pos = at, .end = at + 3, .message = self.format("a range excludes its end: {s}", .{fix}) };
    }

    /// A note for a parse error inside a bracket opened on an earlier
    /// line that nothing after the error closes: the innermost such
    /// bracket, which is likely the one left open.
    pub fn unclosedBracket(self: *Parser) ?diag.Diagnostic {
        if (self.failure != null) return null;
        const lexer = &self.base.lexer;
        const src = self.base.source;
        // How many of the open brackets the rest of the source closes.
        const at = self.base.lastError().?.span.start;
        var probe = BaseLexer.init(src);
        probe.pos = at;
        var depth: u32 = 0;
        var closed: u32 = 0;
        while (closed < lexer.nesting) {
            switch (probe.next().cat) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => if (depth > 0) {
                    depth -= 1;
                } else {
                    closed += 1;
                },
                .eof => break,
                else => {},
            }
        } else return null;
        const open = lexer.brackets[lexer.nesting - 1 - closed];
        if (std.mem.findScalar(u8, src[open..at], '\n') == null) return null;
        return .{ .severity = .note, .pos = open, .end = open + 1, .message = self.format("the `{c}` opened here is not closed", .{src[open]}) };
    }

    /// Why an unexpected token is not Rig: it starts a reserved form, or
    /// Rig spells what it starts differently.
    fn reservedHint(src: []const u8, tok: Token, expected: []const u8) ?[]const u8 {
        const in_pattern = std.mem.find(u8, expected, "a match arm") != null or std.mem.find(u8, expected, "a pattern") != null;
        // Only a function type's result must follow here.
        if (std.mem.eql(u8, expected, "`->`")) return "a function type writes its result after `->`: `fun(Int) -> Int`";
        return switch (tok.cat) {
            .real, .string_sq, .string_dq => if (in_pattern) "a pattern is a name, an integer, `true`, `false`, or an enum variant" else null,
            .@"else" => if (in_pattern) "the catch-all arm is `_`, or a name that binds the value" else null,
            .@"try" => "`try` blocks are reserved: propagate with `e!` or handle with `e catch ...`",
            .zig => "inline Zig is reserved: use `raw` blocks and `extern` declarations",
            .star => if (precededBy(src, tok.pos, "for")) "`for *x in` is reserved: iterate with `for x in xs`, `?xs`, or `!xs`" else null,
            .ident, .not_sym, .question => if (precededBy(src, tok.pos, "drop")) "a drop body takes its receiver in parentheses: `drop(!self)`" else null,
            else => null,
        };
    }

    /// Compile-time parameters and arguments written where Rig does not
    /// take them: in parentheses (`struct Wrap(T)`, `Vec(Int)` in a type,
    /// `pre n: Int`), on a type alias, or as a type an expression cannot
    /// spell (`Vec[[]Int]()`). Also a struct declared with `type`.
    fn bracketHint(self: *Parser, tok: Token) ?[]const u8 {
        const src = self.base.source;
        const before = std.mem.trimEnd(u8, src[0..tok.pos], if (tok.cat == .indent) " \r\n" else " ");
        var start = before.len;
        while (start > 0 and isIdentCont(before[start - 1])) start -= 1;
        const word = before[start..];
        const declared = std.mem.trimEnd(u8, before[0..start], " ");
        // `type` declares only an alias: `type Name = T`.
        if (word.len > 0 and endsWithWord(declared, "type")) switch (tok.cat) {
            .indent => return self.format("a struct is declared with `struct`: `struct {s}`", .{word}),
            .lbracket, .lparen => {
                const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
                if (std.mem.findScalar(u8, src[tok.pos..eol], '=') != null) return "a type alias takes no type parameters; generic aliases are not supported";
                return self.format("a struct is declared with `struct`: `struct {s}[T]`", .{word});
            },
            else => {},
        };
        const decl_kw: ?[]const u8 = for ([_][]const u8{ "struct", "enum", "fun", "sub" }) |kw| {
            if (endsWithWord(declared, kw)) break kw;
        } else null;
        switch (tok.cat) {
            .lparen => {
                if (word.len == 0) return null;
                if (decl_kw) |kw| if (!std.mem.eql(u8, kw, "fun") and !std.mem.eql(u8, kw, "sub")) return self.format("type parameters go in brackets: `{s} {s}[T]`", .{ kw, word });
                if (std.ascii.isUpper(word[0])) return self.format("type arguments go in brackets: `{s}[...]`", .{word});
                return null;
            },
            .lbracket => if (word.len > 0 and endsWithWord(declared, "error")) {
                return "an error set takes no type parameters";
            },
            .rbracket => if (before.len > 0 and before[before.len - 1] == '[') {
                return "empty brackets: give the compile-time arguments, as in `Vec[Int]()`";
            },
            .fun, .sub => if (self.base.lexer.nesting > 0 and src[self.base.lexer.brackets[self.base.lexer.nesting - 1]] == '[') {
                return "a function type has no expression spelling: as a type argument in an expression, name it with a `type` alias, or annotate the binding instead";
            },
            else => {},
        }
        if (std.mem.eql(u8, word, "pre") and self.base.lexer.inParens()) {
            return "compile-time parameters go in brackets after the name, before the run-time ones: `fun f[n: Int](x: Int)`";
        }
        if (tok.cat == .ident and tok.pos > 0 and src[tok.pos - 1] == ']') {
            return "a slice or array type has no expression spelling: as a type argument in an expression, name it with a `type` alias, or annotate the binding instead";
        }
        return null;
    }

    /// `print "hi"`: `print` named without its call's parentheses.
    fn printHint(self: *Parser, tok: Token) ?[]const u8 {
        const lex = &self.base.lexer;
        if (tok.len == 0 or lex.before_cat != .ident) return null;
        const src = self.base.source;
        var end = lex.before_pos;
        while (end < src.len and isIdentCont(src[end])) end += 1;
        if (!std.mem.eql(u8, src[lex.before_pos..end], "print")) return null;
        return "`print` is called with parentheses: `print(...)`";
    }

    /// A prefix sigil with whitespace after it (`- b`): named with the
    /// operand it should touch.
    fn detachedPrefix(self: *Parser, tok: Token) []const u8 {
        const src = self.base.source;
        var probe = BaseLexer.init(src);
        probe.pos = tok.pos + 1;
        const next = while (true) {
            const t = probe.next();
            if (t.cat != .skip and t.cat != .comment) break t;
        };
        const operand = switch (next.cat) {
            .ident, .integer, .real, .string_sq, .string_dq => src[next.pos .. next.pos + next.len],
            else => "x",
        };
        return self.format("a prefix `{c}` touches its operand: write `{c}{s}`", .{ src[tok.pos], src[tok.pos], operand });
    }

    /// A `;`, which Rig does not take: one ending a statement, Rust's
    /// fill literal `[x; n]`, or Rust's array type `[T; n]`.
    fn semicolonMessage(self: *Parser, tok: Token) []const u8 {
        const src = self.base.source;
        const lex = &self.base.lexer;
        if (lex.nesting == 0) {
            // `a = 1; b = 2`: another statement follows on the line.
            const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
            const rest = std.mem.trim(u8, src[tok.pos + 1 .. eol], " \r");
            if (rest.len > 0 and rest[0] != '#') return "unexpected `;`; Rig ends a statement at the end of its line; put each statement on its own line";
            return "unexpected `;`; Rig ends a statement at the end of its line; remove the `;`";
        }
        const open = lex.brackets[lex.nesting - 1];
        if (src[open] != '[') return "unexpected `;`";
        const either = "unexpected `;`; `[x; n]` is written `[n of x]`, and `[Int; 3]` is written `[3]Int`";
        const eol = std.mem.findScalarPos(u8, src, tok.pos, '\n') orelse src.len;
        const close = std.mem.findScalarPos(u8, src[0..eol], tok.pos, ']') orelse return either;
        const elem = std.mem.trim(u8, src[open + 1 .. tok.pos], " ");
        const len = std.mem.trim(u8, src[tok.pos + 1 .. close], " ");
        if (elem.len == 0 or len.len == 0 or std.mem.findAny(u8, elem, ",;") != null or std.mem.findAny(u8, len, ",;([") != null) return either;
        // `[Int; 3]`: the brackets stand where a type goes (after `:` or
        // `->`), or the element reads as a type: `Int`, `U8`, `T`, not a
        // constant such as `LIMIT`, nor a constructor call.
        const before = std.mem.trimEnd(u8, src[0..open], " ");
        const in_type = std.mem.endsWith(u8, before, ":") or std.mem.endsWith(u8, before, "->");
        const rest = elem[1..];
        const typelike = in_type or (std.ascii.isUpper(elem[0]) and std.mem.findScalar(u8, elem, '(') == null and
            (rest.len == 0 or std.mem.findAny(u8, rest, "abcdefghijklmnopqrstuvwxyz") != null or
                std.mem.findNone(u8, rest, "0123456789") == null));
        if (typelike) return self.format("unexpected `;`; an array type puts its length first: `[{s}]{s}`", .{ len, elem });
        return self.format("unexpected `;`; a fill literal puts its count first: `[{s} of {s}]`", .{ len, elem });
    }

    /// `sub()?`, `*fun(Int) -> Int` then `!`: a function type takes no
    /// suffix, so an optional one is written in parentheses.
    fn typeSuffixHint(self: *Parser, tok: Token) ?[]const u8 {
        if (tok.cat != .question and tok.cat != .not_sym) return null;
        const src = self.base.source;
        if (tok.pos == 0 or src[tok.pos - 1] != ')') return null;
        // The `(` that the `)` before the suffix closes.
        var depth: u32 = 0;
        var p = tok.pos;
        const open = while (p > 0) {
            p -= 1;
            switch (src[p]) {
                ')' => depth += 1,
                '(' => {
                    depth -= 1;
                    if (depth == 0) break p;
                },
                '\n' => return null,
                else => {},
            }
        } else return null;
        if (!endsWithWord(src[0..open], "sub") and !endsWithWord(src[0..open], "fun")) return null;
        var start = open - 3;
        while (start > 0 and (src[start - 1] == '*' or src[start - 1] == '~')) start -= 1;
        return self.format("a function type takes no suffix; write `({s}){c}`", .{ src[start..tok.pos], src[tok.pos] });
    }

    /// `[a, 2 of 3]`: a fill literal is the whole bracket. `Int??`: `??`
    /// is an operator, and where the parser does not take one, it was
    /// meant as two suffixes.
    fn tokenHint(tok: Token) ?[]const u8 {
        return switch (tok.cat) {
            .of => "a fill literal `[n of x]` holds one count and one element; it cannot share brackets with a list",
            .nullish => "`??` is the fallback operator; an optional of an optional is written `(T?)?`",
            // Where no operator could come: C and Rust's address-of.
            .ampersand => "Rig lends with `?x` (to read) or `!x` (to write)",
            else => null,
        };
    }

    fn endsWithWord(text: []const u8, word: []const u8) bool {
        return std.mem.endsWith(u8, text, word) and (text.len == word.len or !isIdentCont(text[text.len - word.len - 1]));
    }

    /// The word before `pos` is `word`.
    fn precededBy(src: []const u8, pos: u32, word: []const u8) bool {
        return endsWithWord(std.mem.trimEnd(u8, src[0..pos], " "), word);
    }

    /// The generated parser's expected set where it stopped (its
    /// `@display` and `@errors` names, distinct), or null when it names
    /// more than a few things.
    fn expectedHint(self: *Parser, state: u16) ?[]const u8 {
        var buf: [parser.maxExpected][]const u8 = undefined;
        const names = BaseParser.expectedNames(state, &buf);
        if (names.len == 0 or names.len > max_expected) return null;
        var out: std.Io.Writer.Allocating = .init(self.allocator());
        for (names, 0..) |n, i| {
            out.writer.writeAll(if (i == 0) "" else if (i + 1 == names.len) " or " else ", ") catch return null;
            out.writer.writeAll(n) catch return null;
        }
        return out.written();
    }

    /// The longest expected set a parse error lists.
    const max_expected = 3;

    fn format(self: *Parser, comptime fmt: []const u8, args: anytype) []const u8 {
        return self.allocator().print(fmt, args) catch "unexpected token";
    }

    fn allocator(self: *Parser) std.mem.Allocator {
        return self.base.allocator();
    }

    // -------------------------------------------------------------------------
    // Rewrites that need to inspect the tree:
    //
    //   * a closure's bar list (the grammar's `params`) splits into its
    //     captures and parameters:
    //       (lambda _ ((cap_clone v) a) _ body)  →  (lambda (captures (cap_clone v)) (a) _ body)
    //   * `for` source sigils move into the mode slot:
    //       (for iter x _ (read xs) body _)  →  (for read x _ xs body _)
    //   * a `-name` statement whose value is used is negation, not a drop:
    //     the last statement of a `fun` body, a `break` value, or the last
    //     statement of a branch, arm, `catch` handler, or loop `else`
    //     block whose value is used, becomes (neg name). (A
    //     closure has no declared result, so its body is not rewritten.)
    //   * a jump fallback belongs to the nearest `??` (the grammar reads
    //     it at the level of `catch`, after the chain before it):
    //       (?? (?? a b) (return v))  →  (?? a (?? b (return v)))
    //   * `?`, `!`, or `<` before a place followed by a method call is the
    //     receiver's mode:
    //       (write (call (member (member x v) push) 1))  →  (call (member (write (member x v)) push) 1)
    //
    // Every rewritten node keeps its node id, and so its span; the new
    // `captures` node and receiver sigil get their own (`newNode`).
    // -------------------------------------------------------------------------

    pub fn rewrite(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        if (sexp != .list) return sexp;
        var items = sexp.items();
        // A `for` source sigil is the loop's mode, taken before the
        // receiver rewrite can see it.
        if (sexp.kind() == .@"for") {
            const copy = try self.allocator().dupe(Sexp, items);
            normFor(copy);
            items = copy;
        }
        const walked = try self.allocator().alloc(Sexp, items.len);
        for (items, 0..) |child, i| walked[i] = try self.rewrite(child);
        const out: Sexp = .{ .list = parser.List.withId(walked, sexp.list.id) };
        switch (out.kind() orelse return out) {
            .module => self.moduleConsts(out),
            .@"struct", .@"enum", .errors, .generic_struct, .generic_enum => try self.pubMembers(out),
            .lambda => try self.splitBars(out, walked),
            .@"??" => return self.nearestFallback(out),
            .read, .write, .move => return self.receiverSigil(out),
            .share => try self.noteParenSuffix(out),
            .weak => {
                self.touchesOperand(out);
                try self.noteParenSuffix(out);
            },
            .read_view, .write_view, .shared => self.touchesOperand(out),
            // The body's value is returned.
            .fun => {
                try self.paramList(out);
                if (ir.Fun.returns(out) != .nil) try self.valueTail(ir.Fun.body(out), true);
            },
            .sub, .extern_fun, .extern_sub => try self.paramList(out),
            // The expression's value is bound or returned.
            .set => try self.valueTail(ir.Set.value(out), false),
            .@"return" => try self.valueTail(ir.Return.value(out), false),
            // A loop's value is always used.
            .@"break" => try self.valueTail(ir.Break.value(out), false),
            else => {},
        }
        return out;
    }

    /// A module-level binding is a constant, written with `=`: its
    /// `(set _ ...)` becomes `(set fixed ...)`, the fixed binding every
    /// pass reads. A `const` there is rejected, as it would say nothing
    /// more.
    fn moduleConsts(self: *Parser, module: Sexp) void {
        for (ir.Module.decls(module)) |decl| {
            const set = if (decl.isKind(.@"pub")) ir.Pub.decl(decl) else decl;
            if (!set.isKind(.set)) continue;
            switch (bindingKindOf(ir.Set.op(set))) {
                .default => @constCast(set.items())[ir.slot(.set, .op)] = .{ .tag = .fixed },
                .fixed => {
                    const src = self.base.source;
                    const target = self.span(ir.Set.target(set));
                    const value = self.span(ir.Set.value(set));
                    const ty = ir.Set.type(set);
                    const annot = if (ty == .nil) "" else src[target.end..self.span(ty).end];
                    const shown = src[value.start..value.end];
                    const short = shown.len <= 40 and std.mem.findScalar(u8, shown, '\n') == null;
                    self.reject(set, self.format("a module-level binding is already a constant; write `{s}{s} = {s}`", .{ src[target.start..target.end], annot, if (short) shown else "..." }));
                },
                else => {},
            }
        }
    }

    /// A function's parameter list is always written, even when empty,
    /// as its calls and its type write theirs: `sub main()`, not `sub
    /// main`. The grammar parses a definition without one so that the
    /// fix-it can show the header with it.
    fn paramList(self: *Parser, def: Sexp) std.mem.Allocator.Error!void {
        if (ir.get(def, .params) != .nil) return;
        const src = self.base.source;
        const name = ir.get(def, .name);
        const start = self.span(def).start;
        // The list goes after the name and its compile-time parameters.
        var at: usize = self.span(name).end;
        var probe = at;
        while (probe < src.len and src[probe] == ' ') probe += 1;
        if (probe < src.len and src[probe] == '[') {
            var depth: u32 = 0;
            while (probe < src.len) : (probe += 1) {
                if (src[probe] == '[') depth += 1;
                if (src[probe] == ']') {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            at = @min(probe + 1, src.len);
        }
        var end = at;
        while (end < src.len and src[end] != '\n' and src[end] != '#') end += 1;
        const rest = std.mem.trimEnd(u8, src[at..end], " \t\r");
        const message = self.format("write `{s}(){s}`: a function's parameter list is always written, even when empty", .{ src[start..at], rest });
        if (self.failure == null) return self.reject(name, message);
        const at_name = self.span(name);
        try self.more_failures.append(self.allocator(), .{ .severity = .@"error", .pos = at_name.start, .end = at_name.end, .message = message });
    }

    /// The rejections after the first (`diagnostic()`), in source order.
    pub fn moreDiagnostics(self: *const Parser) []const diag.Diagnostic {
        return if (self.failure != null) self.more_failures.items else &.{};
    }

    /// `pub` on a field or method: the member stands in the member list
    /// as itself, as every pass reads it, and its id is recorded
    /// (`isPubMember`).
    fn pubMembers(self: *Parser, node: Sexp) std.mem.Allocator.Error!void {
        const is_enum = node.isKind(.@"enum") or node.isKind(.generic_enum) or node.isKind(.errors);
        for (@constCast(ir.rest(node, .members))) |*m| {
            if (!m.isKind(.@"pub")) continue;
            const inner = ir.Pub.decl(m.*);
            // A bare name is a variant; in a struct, the checker rejects
            // it, and any other member that is not a field or method.
            switch (inner.kind() orelse .variant) {
                .@":", .default, .fun, .sub => {},
                .drop_decl => self.reject(m.*, "a `drop` body is never called by name, so it takes no `pub`"),
                .@"pub" => self.reject(inner, "`pub` is written once"),
                else => if (is_enum) self.reject(m.*, "an enum's variants are always public; remove the `pub`"),
            }
            if (inner == .list) try self.pub_members.put(self.allocator(), inner.list.id, {});
            m.* = inner;
        }
    }

    /// Whether `member`, a field or method, is declared `pub`.
    pub fn isPubMember(self: *const Parser, member: Sexp) bool {
        return member == .list and self.pub_members.contains(member.list.id);
    }

    /// `a ?? b ?? return v`: the grammar reads a jump fallback after the
    /// whole chain before it, `(a ?? b) ?? return v`; `??` is
    /// right-associative, so the jump goes to the innermost right side,
    /// `a ?? (b ?? return v)`. A parenthesized left side keeps its
    /// grouping: it starts after the node that holds it.
    fn nearestFallback(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const right = ir.@"??".right(node);
        switch (right.kind() orelse return node) {
            .@"return", .@"break", .@"continue" => {},
            else => return node,
        }
        const left = ir.@"??".left(node);
        if (!left.isKind(.@"??") or self.span(left).start != self.span(node).start) return node;
        return self.attachFallback(left, right);
    }

    /// `chain ?? jump`, the jump attached to the last right side of the
    /// `??` chain that is not parenthesized.
    fn attachFallback(self: *Parser, chain: Sexp, jump: Sexp) std.mem.Allocator.Error!Sexp {
        const inner = ir.@"??".right(chain);
        const grouped = !inner.isKind(.@"??") or self.span(inner).end != self.span(chain).end;
        const new_right = if (grouped)
            try self.base.newNode(.@"??", &.{ inner, jump }, .{ .start = self.span(inner).start, .end = self.span(jump).end })
        else
            try self.attachFallback(inner, jump);
        return self.base.newNode(.@"??", &.{ ir.@"??".left(chain), new_right }, .{ .start = self.span(chain).start, .end = self.span(jump).end });
    }

    /// `*(T?)`, `~(T?)`, `*(~T?)`: a `?` suffix sits inside parentheses
    /// within a chain of handles, so it belongs to what a handle holds.
    /// In `*T?`, `*~T?`, and `*(T)?` every suffix follows the whole chain:
    /// each handle and each suffix layer starts at the token after the
    /// sigil before it.
    fn noteParenSuffix(self: *Parser, node: Sexp) std.mem.Allocator.Error!void {
        var e = node;
        while (true) {
            const at = self.afterSigil(e);
            var op = ir.get(e, .operand);
            if (op.isKind(.share) or op.isKind(.weak)) {
                if (self.span(op).start == at) {
                    e = op;
                    continue;
                }
                // `*(~T?)`: a parenthesized handle with a suffix of its own.
                while (op.isKind(.share) or op.isKind(.weak)) op = ir.get(op, .operand);
                if (op.isKind(.propagate_none)) try self.paren_suffixes.put(self.allocator(), node.list.id, {});
                return;
            }
            while (op.isKind(.propagate_none)) : (op = ir.PropagateNone.value(op)) {
                if (self.span(op).start != at) return self.paren_suffixes.put(self.allocator(), node.list.id, {});
            }
            return;
        }
    }

    /// A type's prefix sigil touches its operand. The lexer checks every
    /// other prefix; a sigil after a type's `]` (`[]*T`) reads to it as a
    /// suffix, which may stand apart.
    fn touchesOperand(self: *Parser, node: Sexp) void {
        const at = self.span(node).start;
        const src = self.base.source;
        if (!isSpace(if (at + 1 < src.len) src[at + 1] else 0) or self.failure != null) return;
        self.failure = .{ .severity = .@"error", .pos = at, .end = at + 1, .message = self.detachedPrefix(.{ .cat = .err, .pre = 0, .pos = at, .len = 1 }) };
    }

    /// Whether `node`, a `share` or `weak`, has a parenthesized suffix in
    /// its operand: `*(T?)`, not `*T?` or `*(T)?`.
    pub fn hasParenSuffix(self: *const Parser, node: Sexp) bool {
        return node == .list and self.paren_suffixes.contains(node.list.id);
    }

    /// Whether `node` is a receiver sigil the wrapper moved onto the
    /// receiver: `!v` in `!v.push(x)`, not in `(!v).push(x)`.
    pub fn isReceiverSigil(self: *const Parser, node: Sexp) bool {
        return node == .list and self.receiver_sigils.contains(node.list.id);
    }

    /// Where the token after the sigil that starts `node` starts, past
    /// any whitespace, line joins, and comments.
    fn afterSigil(self: *const Parser, node: Sexp) u32 {
        var probe = BaseLexer.init(self.base.source);
        probe.pos = self.span(node).start + 1;
        while (true) {
            const t = probe.next();
            switch (t.cat) {
                .comment, .newline, .skip => continue,
                else => return t.pos,
            }
        }
    }

    /// `?`, `!`, and `<` before a place (a name and the fields and elements
    /// after it) followed by a method call apply to the place; the call
    /// and every postfix after it apply to the lent or moved place:
    ///   (write (propagate_none (call (member v pop))))
    ///   → (propagate_none (call (member (write v) pop)))
    /// The sigil reaches the receiver of the chain's first method call.
    /// A `!` reaches one that is a value no name holds too: one a call
    /// that is no method call makes (`!mk().bump()` is
    /// `(!mk()).bump()`), a literal, or a parenthesized expression
    /// (`!(+s).bump()`); a call of a call's value is walked through to
    /// the first call (`!a.b(x)(y).g()` is `(!a).b(x)(y).g()`). Anything
    /// else keeps its
    /// sigil outside: a chain that is all place (`!x.v`), a `?` or `<`
    /// chain whose head is called (`<f(x).g()`), and one whose spine is
    /// parenthesized (`!(v.pop())`), which starts after the token after
    /// the sigil, a `(`.
    fn receiverSigil(self: *Parser, node: Sexp) std.mem.Allocator.Error!Sexp {
        const tag: parser.Tag = node.kind().?;
        const at = self.afterSigil(node);
        // `!` lends any value to write, so its chain may start from a
        // value no name holds: a call that is no method call
        // (`!mk().bump()`), a literal (`![a, b][0].bump()`), or a
        // parenthesized expression (`!(+s).bump()`).
        const any_head = tag == .write;
        // The chain from the operand down to its head, outermost first.
        var chain: std.ArrayList(Sexp) = .empty;
        var e = ir.get(node, .operand);
        while (true) {
            if (self.span(e).start != at) {
                if (!any_head or chain.items.len == 0) return node;
                try chain.append(self.allocator(), e);
                break;
            }
            try chain.append(self.allocator(), e);
            e = switch (e.kind() orelse break) {
                .propagate, .propagate_none => ir.get(e, .value),
                .member, .index, .inst => ir.get(e, .object),
                // A call of a call's value (`a.b(x)(y)`) is walked to
                // the first call, as before.
                .call => if (any_head and !isMethodCallee(ir.Call.callee(e)) and !ir.Call.callee(e).isKind(.call)) break else ir.Call.callee(e),
                else => if (any_head) break else return node,
            };
        }
        const spine = chain.items;
        const n = spine.len;
        // Grow the place up from the head through fields and elements,
        // stopping at the member a call follows, directly or after a
        // bracket list (`!v.put[2](x)`, compile-time arguments): the
        // method.
        var top = n - 1;
        while (top > 0) {
            const up = spine[top - 1];
            if (up.isKind(.member) and top >= 2 and spine[top - 2].isKind(.call)) break;
            if (up.isKind(.member) and top >= 3 and isBracketList(spine[top - 2]) and spine[top - 3].isKind(.call)) break;
            if (!up.isKind(.member) and !up.isKind(.index)) return node;
            top -= 1;
        }
        if (top == 0) return node;
        const place = spine[top];
        var out = try self.base.newNode(tag, &.{place}, .{ .start = self.span(node).start, .end = self.span(place).end });
        try self.receiver_sigils.put(self.allocator(), out.list.id, {});
        var i = top;
        while (i > 0) {
            i -= 1;
            const link = spine[i];
            const slot = switch (link.kind().?) {
                .propagate => ir.slot(.propagate, .value),
                .propagate_none => ir.slot(.propagate_none, .value),
                .member => ir.slot(.member, .object),
                .index => ir.slot(.index, .object),
                .inst => ir.slot(.inst, .object),
                .call => ir.slot(.call, .callee),
                else => unreachable,
            };
            const copy = try self.allocator().dupe(Sexp, link.items());
            copy[slot] = out;
            out = .{ .list = parser.List.withId(copy, link.list.id) };
        }
        return out;
    }

    /// `(lambda _ entries _ body)`: sigiled entries are captures, the
    /// rest parameters. Captures come first.
    fn splitBars(self: *Parser, node: Sexp, items: []Sexp) std.mem.Allocator.Error!void {
        const bars = ir.Lambda.params(node);
        var caps: std.ArrayList(Sexp) = .empty;
        var params: std.ArrayList(Sexp) = .empty;
        for (bars.items()) |e| {
            const is_capture = if (e.kind()) |k| switch (k) {
                .cap_clone, .cap_move, .cap_weak, .cap_read, .cap_write => true,
                else => false,
            } else false;
            if (!is_capture) {
                try params.append(self.allocator(), e);
                continue;
            }
            if (params.items.len > 0) self.reject(e, "captures come before parameters in a closure's bar list: `|+v, a| ...`");
            try caps.append(self.allocator(), e);
        }
        items[ir.slot(.lambda, .captures)] = if (caps.items.len > 0) try self.base.newNode(.captures, caps.items, .{
            .start = self.span(caps.items[0]).start,
            .end = self.span(caps.items[caps.items.len - 1]).end,
        }) else .nil;
        items[ir.slot(.lambda, .params)] = if (params.items.len > 0) .{ .list = parser.List.withId(params.items, bars.list.id) } else .nil;
    }

    /// `sexp` (already walked, so its lists are freshly allocated) is in
    /// value position, `function` when it is a function's body: a
    /// trailing `(drop x)` there is `(neg x)`.
    fn valueTail(self: *Parser, sexp: Sexp, function: bool) std.mem.Allocator.Error!void {
        const kind = sexp.kind() orelse return;
        const items = @constCast(sexp.items());
        switch (kind) {
            .drop => {
                items[0] = .{ .tag = .neg };
                try self.value_tails.put(self.allocator(), sexp.list.id, function);
            },
            .block => {
                const stmts = ir.Block.stmts(sexp);
                if (stmts.len > 0) try self.valueTail(stmts[stmts.len - 1], function);
            },
            .@"if" => {
                try self.valueTail(ir.If.then(sexp), false);
                try self.valueTail(ir.If.@"else"(sexp), false);
            },
            .match => for (ir.Match.arms(sexp)) |arm| try self.valueTail(ir.Arm.body(arm), false),
            .@"catch" => try self.valueTail(ir.Catch.handler(sexp), false),
            .@"while" => try self.valueTail(ir.While.@"else"(sexp), false),
            .@"for" => try self.valueTail(ir.For.@"else"(sexp), false),
            else => {},
        }
    }

    /// For a `-name` line that is a value (`valueTail`): whether it is a
    /// function's value; null for any other node.
    pub fn valueTailOf(self: *const Parser, node: Sexp) ?bool {
        if (node != .list) return null;
        return self.value_tails.get(node.list.id);
    }

    /// Promote the source's `?xs` / `!xs` / `<xs` wrapper into the mode.
    fn normFor(items: []Sexp) void {
        const node = Sexp.listOf(items);
        if (ir.For.mode(node).tag != .iter) return;
        const source = ir.For.source(node);
        const kind = source.kind() orelse return;
        switch (kind) {
            .read, .write, .move => {
                items[ir.slot(.@"for", .mode)] = .{ .tag = kind };
                items[ir.slot(.@"for", .source)] = ir.get(source, .operand);
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
            std.debug.print("source: {s}\n  at `{s}`\n", .{ source, lx.base.text(got) });
            return e;
        };
    }
}

test "keywords are reserved; `new` only at statement start" {
    try testing.expectEqual(TokenCat.@"else", keyword("else").?);
    try testing.expect(keyword("fn") == null);
    for ([_][]const u8{ "trait", "impl", "where", "async", "await", "yield", "when", "const" }) |w| {
        try testing.expect(keyword(w) != null);
    }
    try testing.expect(keyword("var") == null);
    try expectCats("new x = 1", &.{ .new, .ident, .assign, .integer });
    try expectCats("p = Point.new(1)", &.{ .ident, .assign, .ident, .dot, .ident, .lparen, .integer, .rparen });
}

test "`unique` is a keyword only after a struct header's name or type parameters" {
    try testing.expect(keyword("unique") == null);
    try expectCats("struct R unique", &.{ .@"struct", .ident, .unique });
    try expectCats("pub struct R unique # note", &.{ .@"pub", .@"struct", .ident, .unique });
    try expectCats("struct R[T] unique", &.{ .@"struct", .ident, .lbracket, .ident, .rbracket, .unique });
    try expectCats("struct R[unique]", &.{ .@"struct", .ident, .lbracket, .ident, .rbracket });
    try expectCats("struct unique", &.{ .@"struct", .ident });
    try expectCats("enum E unique", &.{ .@"enum", .ident, .ident });
    try expectCats("unique = x.unique", &.{ .ident, .assign, .ident, .dot, .ident });
    try expectCats("struct R\n  unique: Bool", &.{ .@"struct", .ident, .indent, .ident, .colon, .ident });
    try expectCats("f(unique: 1)", &.{ .ident, .lparen, .kwarg_name, .colon, .integer, .rparen });
}

test "`from` and `static` are keywords only after a function's result type" {
    try testing.expect(keyword("from") == null and keyword("static") == null);
    try expectCats("fun f(a: ?T) -> ?T from a", &.{ .fun, .ident, .lparen, .kwarg_name, .colon, .question, .ident, .rparen, .arrow, .question, .ident, .from, .ident });
    try expectCats("pub fun f() -> String from static", &.{ .@"pub", .fun, .ident, .lparen, .rparen, .arrow, .ident, .from, .static });
    try expectCats("fun f() -> T? from a, b", &.{ .fun, .ident, .lparen, .rparen, .arrow, .ident, .question, .from, .ident, .comma, .ident });
    try expectCats("extern fun f(s: String) -> String from s", &.{ .@"extern", .fun, .ident, .lparen, .kwarg_name, .colon, .ident, .rparen, .arrow, .ident, .from, .ident });
    try expectCats("fun span(from: Int) -> Int", &.{ .fun, .ident, .lparen, .kwarg_name, .colon, .ident, .rparen, .arrow, .ident });
    try expectCats("from = static", &.{ .ident, .assign, .ident });
    try expectCats("f = |x: Int| x\nfrom = 1", &.{ .ident, .assign, .bar_capture, .ident, .colon, .ident, .bar_capture, .ident, .newline, .ident });
    try expectCats("fun f() -> Int\n  from", &.{ .fun, .ident, .lparen, .rparen, .arrow, .ident, .indent, .ident });
    try expectCats("fun f(g: fun(Int) -> Int, from: Int)", &.{ .fun, .ident, .lparen, .kwarg_name, .colon, .fun, .lparen, .ident, .rparen, .arrow, .ident, .comma, .kwarg_name });
}

test "a prefix sigil touches its operand; after a value it is infix or a suffix" {
    for ([_][]const u8{ "a < b", "a<b", "a <b", "a< b" }) |src| try expectCats(src, &.{ .ident, .lt, .ident });
    for ([_][]const u8{ "a - 1", "a-1", "a -1" }) |src| try expectCats(src, &.{ .ident, .minus, .integer });
    try expectCats("x = <y", &.{ .ident, .assign, .lt, .ident });
    try expectCats("x = < y", &.{ .ident, .assign, .err });
    try expectCats("x = * y", &.{ .ident, .assign, .err });
    try expectCats("f(! x)", &.{ .ident, .lparen, .err });
    try expectCats("T? x! T ? x !", &.{ .ident, .question, .ident, .not_sym, .ident, .question, .ident, .not_sym });
    try expectCats("a | b | c", &.{ .ident, .bar, .ident, .bar, .ident });
    try expectCats("f = |a, +b| a", &.{ .ident, .assign, .bar_capture, .ident, .comma, .plus, .ident, .bar_capture, .ident });
    try expectCats("f = | +b , a | a", &.{ .ident, .assign, .bar_capture, .plus, .ident, .comma, .ident, .bar_capture, .ident });
}

test "`name:` is a keyword argument inside ( ), a name inside [ ]" {
    try expectCats("fun f[n: Int](x: Int)", &.{ .fun, .ident, .lbracket, .ident, .colon, .ident, .rbracket, .lparen, .kwarg_name, .colon, .ident, .rparen });
    try expectCats("pre = 1", &.{ .ident, .assign, .integer });
}

test "a statement label ends no operand" {
    try expectCats(":a if x", &.{ .colon, .ident, .@"if", .ident });
    try expectCats(":a -x", &.{ .colon, .ident, .drop_stmt, .ident });
}

test "a `while` header's first `:` starts its step; another after a jump is a label's" {
    try expectCats("while x : y", &.{ .@"while", .ident, .step_colon, .ident });
    try expectCats("while f(a: 1) : y", &.{ .@"while", .ident, .lparen, .kwarg_name, .colon, .integer, .rparen, .step_colon, .ident });
    try expectCats("while x : y = a ?? break :b", &.{ .@"while", .ident, .step_colon, .ident, .assign, .ident, .nullish_jump, .@"break", .colon, .ident });
    try expectCats("x = a ?? break :b", &.{ .ident, .assign, .ident, .nullish_jump, .@"break", .colon, .ident });
}

test "minus: infix, negation, drop" {
    try expectCats("a - b", &.{ .ident, .minus, .ident });
    try expectCats("a -b", &.{ .ident, .minus, .ident });
    try expectCats("-x", &.{ .drop_stmt, .ident });
    try expectCats("- x", &.{.err});
    try expectCats("-x + 1", &.{ .minus, .ident, .plus, .integer });
    try expectCats("y = -x", &.{ .ident, .assign, .minus, .ident });
    try expectCats("defer -x", &.{ .@"defer", .drop_stmt, .ident });
}

test "if: block, guard, ternary" {
    try expectCats("if c", &.{ .@"if", .ident });
    try expectCats("return if c", &.{ .@"return", .post_if, .ident });
    try expectCats("return x if c", &.{ .@"return", .ident, .post_if, .ident });
    try expectCats("x = a if c else b", &.{ .ident, .assign, .ident, .ternary_if, .ident, .@"else", .ident });
    try expectCats("f(a if c else b)", &.{ .ident, .lparen, .ident, .ternary_if, .ident, .@"else", .ident, .rparen });
}

test "layout: indentation, joined lines, tabs" {
    try expectCats("a\n  b\nc", &.{ .ident, .indent, .ident, .outdent, .newline, .ident, .eof });
    try expectCats("f(1,\n  2)\nx", &.{ .ident, .lparen, .integer, .comma, .integer, .rparen, .newline, .ident });
    try expectCats("a\n\tb", &.{ .ident, .err });
    try expectCats("a\n    b\n  c", &.{ .ident, .indent, .ident, .err });
}

test "closure bar lists: typed parameters, empty bars, owned star" {
    try expectCats("f = |+v, a: Int| a", &.{ .ident, .assign, .bar_capture, .plus, .ident, .comma, .ident, .colon, .ident, .bar_capture, .ident });
    try expectCats("f = |?v, !w, a| a", &.{ .ident, .assign, .bar_capture, .question, .ident, .comma, .not_sym, .ident, .comma, .ident, .bar_capture, .ident });
    try expectCats("g = || 1", &.{ .ident, .assign, .bar_empty, .integer });
    try expectCats("h = *|a| a", &.{ .ident, .assign, .star, .bar_capture, .ident, .bar_capture, .ident });
    try expectCats("x = a | b", &.{ .ident, .assign, .ident, .bar, .ident });
    try expectCats("x = a * b", &.{ .ident, .assign, .ident, .star, .ident });
    try expectCats("x = a || b", &.{ .ident, .assign, .ident, .err });
}

/// `n` copies of `c`, for building long test strings.
fn chars(comptime c: u8, comptime n: usize) *const [n]u8 {
    const s: [n]u8 = @splat(c);
    return &s;
}

test "tokens longer than 65535 bytes: a comment is skipped, anything else is an error" {
    try expectCats("#" ++ chars('c', 70000) ++ "\nx", &.{ .ident, .eof });
    var lx = Lexer.init("x = " ++ chars('y', 70000));
    _ = lx.next();
    _ = lx.next();
    try testing.expectEqual(TokenCat.err, lx.next().cat);
    try testing.expectEqual(Lexer.LexError.too_long, lx.err);
}

test "layout: a closure body inside brackets is laid out in blocks" {
    try expectCats("f(*|x|\n  g(x)\n  h)\ny", &.{
        .ident,  .lparen,  .star,   .bar_capture, .ident,  .bar_capture,
        .indent, .ident,   .lparen, .ident,       .rparen, .newline,
        .ident,  .outdent, .rparen, .newline,     .ident,
    });
    // Coming back to the closure's line ends the body.
    try expectCats("f(||\n  g\n, 1)", &.{ .ident, .lparen, .bar_empty, .indent, .ident, .outdent, .comma, .integer, .rparen });
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
    var p = Parser.init(testing.allocator, "for x in ?xs\n  print(x)\n");
    defer p.deinit();
    const tree = try p.parseProgram();
    const loop = ir.Module.decls(tree)[0];
    try testing.expectEqual(Tag.read, ir.For.mode(loop).tag);
    try testing.expectEqualStrings("xs", ir.For.source(loop).getText(p.base.source));
}

test "parser: a receiver sigil moves onto the place before the method" {
    const source = "!x.v[0].push(1)\n(!v).push(2)\n!(v.pop())\n!f(x).g()\n?p.m()\n?(p.m())\n?f(x).g()\n!(+s).g()\n!a.b(x)(y).g()\n";
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parseProgram();
    const stmts = ir.Module.decls(tree);
    // (call (member (write (index (member x v) 0)) push) 1)
    const recv = ir.Member.object(ir.Call.callee(stmts[0]));
    try testing.expect(recv.isKind(.write) and p.isReceiverSigil(recv));
    const s = p.span(recv);
    try testing.expectEqualStrings("!x.v[0]", source[s.start..s.end]);
    try testing.expect(ir.Write.operand(recv).isKind(.index));
    // Parentheses keep their meaning, and are not a receiver sigil.
    const long = ir.Member.object(ir.Call.callee(stmts[1]));
    try testing.expect(long.isKind(.write) and !p.isReceiverSigil(long));
    try testing.expect(stmts[2].isKind(.write));
    // `!` lends any value to write: a called head is the receiver.
    const made = ir.Member.object(ir.Call.callee(stmts[3]));
    try testing.expect(made.isKind(.write) and p.isReceiverSigil(made));
    try testing.expect(ir.Write.operand(made).isKind(.call));
    // `?` reaches the receiver too, and lends a parenthesized call.
    const read = ir.Member.object(ir.Call.callee(stmts[4]));
    try testing.expect(read.isKind(.read) and p.isReceiverSigil(read));
    try testing.expect(stmts[5].isKind(.read));
    // A `?` before a called head lends the result.
    try testing.expect(stmts[6].isKind(.read));
    // A parenthesized receiver is lent to write by `!`.
    const paren = ir.Member.object(ir.Call.callee(stmts[7]));
    try testing.expect(paren.isKind(.write) and p.isReceiverSigil(paren));
    try testing.expect(ir.Write.operand(paren).isKind(.clone));
    // A call of a call's value: the first method call's receiver, `a`.
    var head = stmts[8];
    while (!head.isKind(.write)) head = if (head.isKind(.call)) ir.Call.callee(head) else ir.get(head, .object);
    try testing.expect(p.isReceiverSigil(head) and ir.Write.operand(head) == .src);
}

test "parser: bar lists split into captures and parameters, all with node ids" {
    const source = "f = |+c, a| a + c\n";
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    const raw = try p.parseTree();
    const tree = try p.rewrite(raw);
    const set = ir.Module.decls(tree)[0];
    try testing.expectEqual(ir.Module.decls(raw)[0].list.id, set.list.id);
    const lambda = ir.Set.value(set);
    const captures = ir.Lambda.captures(lambda);
    try testing.expect(captures.isKind(.captures));
    try testing.expectEqual(@as(usize, 1), ir.Lambda.params(lambda).items().len);
    const s = p.span(lambda);
    try testing.expectEqualStrings("|+c, a| a + c", source[s.start..s.end]);
    // The wrapper's `captures` node gets its own id, spanning its entries.
    try testing.expect(captures.list.id != 0);
    const cs = p.span(captures);
    try testing.expectEqualStrings("+c", source[cs.start..cs.end]);
}

fn parses(source: []const u8) !void {
    var p = Parser.init(testing.allocator, source);
    defer p.deinit();
    _ = try p.parseProgram();
}

test "parser: every form parses" {
    try parses(
        \\use m
        \\
        \\type Id = U64
        \\
        \\struct Wrap[T]
        \\  value: T
        \\
        \\  fun get(?self) -> T
        \\    self.value
        \\
        \\enum Shape
        \\  circle(radius: Int)
        \\  empty()
        \\  dot
        \\
        \\enum Code
        \\  ok = 200
        \\
        \\error Net
        \\  timeout
        \\
        \\struct P
        \\  n: Int
        \\
        \\  drop(!self)
        \\    print(self.n)
        \\
        \\struct Random unique
        \\  seed: Int
        \\
        \\pub struct Ring[T] unique
        \\  item: T
        \\
        \\extern fun abs(n: Int) -> Int
        \\extern fun tick(n: Int)
        \\extern sub halt()
        \\extern count: Int
        \\
        \\pub fun f[c: Int](a: Int, b: Int = 2) -> Int!
        \\  a
        \\
        \\test "t"
        \\  print(1)
        \\
        \\sub main()
        \\  x = 1
        \\  const y: [2]Int = [1, 2]
        \\  const y2 = y
        \\  new x = x + 1
        \\  new x: Int = x + 1
        \\  new const x = x + 1
        \\  new const y2: [2]Int = y
        \\  x += 1
        \\  x <<= 2
        \\  z = <w
        \\  -z
        \\  if x > 1
        \\    print(x, y)
        \\  else if not (x < 0 and true)
        \\    return
        \\  if m as v
        \\    print(v)
        \\  :outer while x < 3 : x += 1
        \\    break :outer
        \\  while m as v
        \\    continue
        \\  else
        \\    break
        \\  for a, i in ?xs
        \\    print(a[i])
        \\  else
        \\    print(0)
        \\  match s
        \\    .circle(r) => print(r)
        \\    1..3 => print(-1)
        \\    _
        \\      print(2)
        \\  g = |+c, <d, ~e, k: Int, j| c + k
        \\  h = *|+c| c.set(@size(Int))
        \\  i = || print(1)
        \\  v = f(1, b: 3) catch 0
        \\  u = f(1)!
        \\  t = f(1) catch |err| 0
        \\  q = a ?? b
        \\  o = 1 if c else 2
        \\  defer print(1)
        \\  raw
        \\    print(@intCast(x))
        \\  print(+a, <b, ?c, !d, *e, ~f, v.w[0])
        \\  n: fun() -> Int = f
        \\  n2: *sub(Int, ?Wrap[Int]) = h
        \\  n3: sub() = i
        \\  o2: *Wrap[Int]? = none
        \\  p2 = Pair[Int, String].make(f[3](1), v[0])
        \\  o3: []~Int = o
        \\  return x
        \\
    );
}

test "parser: a definition writes its parameter list, even when empty" {
    const cases = [_][2][]const u8{
        .{ "sub main\n  pass\n", "write `sub main()`: a function's parameter list is always written, even when empty" },
        .{ "fun answer -> Int  # the answer\n  42\n", "write `fun answer() -> Int`" },
        .{ "fun first[T, n: Int] -> T?\n  none\n", "write `fun first[T, n: Int]() -> T?`" },
        .{ "sub save!\n  pass\n", "write `sub save()!`" },
        .{ "struct S\n  n: Int\n\n  pub fun get -> Int\n    1\n", "write `fun get() -> Int`" },
        .{ "extern fun now -> Int\n", "write `extern fun now() -> Int`" },
        .{ "extern sub halt\n", "write `extern sub halt()`" },
        .{ "extern zig \"z.zig\"\n  pub fun one -> Int\n", "write `fun one() -> Int`" },
    };
    for (cases) |c| {
        var p = Parser.init(testing.allocator, c[0]);
        defer p.deinit();
        try testing.expectError(error.ParseError, p.parseProgram());
        const d = p.diagnostic();
        testing.expect(std.mem.startsWith(u8, d.message, c[1])) catch |e| {
            std.debug.print("source: {s}\n  got: {s}\n", .{ c[0], d.message });
            return e;
        };
    }
}

test "a keyword after `@` names a builtin" {
    try expectCats("@type(x)", &.{ .at, .ident, .lparen, .ident, .rparen });
    try expectCats("@size(@type(x))", &.{ .at, .ident, .lparen, .at, .ident, .lparen, .ident, .rparen, .rparen });
}
