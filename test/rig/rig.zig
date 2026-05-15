//! Rig `@lang` module — the single source of truth for all Rig-specific
//! behavior layered on top of Nexus's generated parser.
//!
//! The generated parser has two stages, each with a Nexus-generated raw
//! producer and a Rig-specific wrapper auto-wired in via `@hasDecl`:
//!
//!   stage    raw producer (parser.zig, generated)   wrapper (this file)
//!   ─────    ────────────────────────────────────   ───────────────────
//!   lex      BaseLexer                              Lexer
//!   parse    BaseParser   (grammar actions → Sexp)  Parser  (rewrites
//!                                                            into the
//!                                                            normalized
//!                                                            semantic IR)
//!
//! `parser.Parser` (the auto-wire alias) resolves to `rig.Parser` here,
//! so `parser.Parser.init(allocator, source).parseProgram()` returns
//! the fully-rewritten IR in one call. Rig is the first Nexus consumer
//! to actually exercise the `Parser` auto-wire end-to-end.
//!
//! Plus the supporting tables/enums:
//!
//!   * `Tag`         — semantic node-type enum (head Tags + kind markers)
//!   * `BindingKind` — exhaustive enum used by the M2/M3 kind dispatches
//!   * `keywordAs`   — identifier → keyword promotion for the parser
//!
//! Anything language-specific that isn't expressible in `rig.grammar`
//! belongs here.

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const BaseParser = parser.BaseParser;
const Token = parser.Token;
const TokenCat = parser.TokenCat;
const Sexp = parser.Sexp;

// =============================================================================
// Tag enum — semantic node types for S-expression output
// =============================================================================
//
// Inherited from Zag with renames per SPEC:
//   - `comptime` paths are renamed to `pre`
// Added by Rig:
//   - ownership: move, read, write, clone, drop, share, weak, pin, raw
//   - bindings:  the unified `(set <kind> name type-or-_ expr)` head
//   - control:   try_block, catch_block, propagate
//   - iteration: for-mode tags `iter`, `read`, `write`, `move`, `ptr`
//                in the unified `(for <mode> binding1 binding2-or-_ source body)` shape
//   - meta:      pre, pre_param, pre_block
//
// The grammar now emits the normalized IR shape directly via Nexus's
// tag-literal-at-child-position support (Nexus 0.10.x+), so the Tag
// enum is sized to the **normalized** vocabulary — not the historical
// raw-vs-normalized union. See docs/SEMANTIC-SEXP.md for the full
// emitted-shape catalog.

pub const Tag = enum(u8) {
    // Module structure
    @"module",
    @"use",
    @"enum",
    @"struct",
    @"packed",
    @"labeled",
    @"type",
    @"pub",
    @"extern",
    @"export",
    @"callconv",
    @"opaque",
    @"generic_type",    // type Box(T) ...
    @"fixed",           // generic "fixed/immutable" kind marker (used in extern, etc.)
    @"volatile_ptr",
    @"many_ptr",
    @"sentinel_ptr",
    @"array_type",
    @"aligned",
    @"errors",
    @"test",
    @"zig",
    @"null",
    @"unreachable",
    @"undefined",
    @"as",
    @"??",
    @"catch",
    @"ternary",
    @"builtin",
    @"error_union",

    // Routines
    @"fun",
    @"sub",
    @"return",

    // Bindings (Rig)
    //
    // ALL binding forms share a single uniform 5-child shape, emitted
    // directly by the grammar via Nexus tag-literal-at-child support:
    //
    //   (set <kind> name type-or-_ expr)
    //
    // where <kind> is one of:
    //   _       — default `=` (M2 disambiguates bind vs rebind)
    //   fixed   — `=!` (immutable bind)
    //   shadow  — `new x = expr` (explicit shadow)
    //   move    — `x <- expr` (move-assign sugar)
    //   +=, -=, *=, /=  — compound assignment (op as kind tag)
    //
    // `shadow` and `move` Tag entries serve dual purposes: as kind tags
    // in the set's slot, AND as ownership-wrapper / shadow-marker Tags
    // in their other contexts. Position disambiguates (items[1] of `set`
    // is a kind; everywhere else it's the wrapper meaning).
    @"set",
    @"shadow",
    @"=",
    @"+=",
    @"-=",
    @"*=",
    @"/=",

    // Control flow
    @"if",
    @"while",
    // for: (for <mode> binding1 binding2-or-_ source body else?)
    //   mode is one of `iter` (default), `read`, `write`, `move`, `ptr`
    // The grammar emits the unified shape directly (no separate `for_ptr`).
    @"for",
    @"match",
    @"arm",
    @"range_pattern",
    @"enum_pattern",
    @"enum_lit",        // .strict (inferred-type enum value)
    @"break",
    @"continue",
    @"defer",
    @"errdefer",
    @"try",             // prefix: try expr
    @"try_block",       // value-yielding try INDENT body OUTDENT
    @"catch_block",     // catch |err| INDENT body OUTDENT
    @"propagate",       // expr?  (suffix propagation)
    @"inline",
    @"lambda",

    // Calls and access
    @"addr_of",
    @"call",
    @"member",          // obj.name (grammar emits this directly)
    @"deref",
    @"index",
    @"array",
    @"record",
    @"kwarg",           // name: value (kwarg / record-field; grammar emits directly)

    // Operators — arithmetic
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"**",
    @"neg",
    @"not",

    // Operators — comparison
    @"==",
    @"!=",
    @"<",
    @">",
    @"<=",
    @">=",

    // Operators — logical
    @"||",
    @"&&",

    // Operators — bitwise
    @"&",
    @"|",
    @"^",
    @"<<",
    @">>",

    // Operators — pipe and range
    @"|>",
    @"..",

    // Type annotations and type constructors
    @"typed",
    @"valued",
    @"default",
    @":",
    @"optional",        // `T?` (suffix optional; grammar emits directly)
    @"borrow_read",     // `?T` in type position — read-borrowed parameter/return
    @"borrow_write",    // `!T` in type position — write-borrowed parameter/return
    @"ptr",
    @"iter",            // for-mode: default value iteration (no sigil, no `*`)
    @"const_ptr",
    @"sentinel_slice",
    @"fn_type",
    @"error_merge",
    @"pre_param",       // (Zag: comptime_param)
    @"anon_init",
    @"slice",

    // Rig ownership ops (expression position; from atom rules and rewriter)
    @"move",            // <x
    @"read",            // ?x
    @"write",           // !x
    @"clone",           // +x
    @"drop",            // -x  (statement position)
    @"share",           // *x
    @"weak",            // ~x
    @"pin",             // @x
    @"raw",             // %x

    // Compile-time
    @"pre",             // pre block / pre fun / pre-call (Zag: comptime)
    @"pre_block",       // pre INDENT body OUTDENT

    // Structure
    @"block",

    _,
};

// =============================================================================
// BindingKind — exhaustive enum for the kind slot of `(set <kind> ...)`
// =============================================================================
//
// The normalized binding shape is:
//
//     (set <kind> name type-or-_ expr)
//
// `<kind>` is one of: `_` (nil), or a Tag (`.fixed`, `.shadow`, `.@"move"`,
// `.@"+="`, etc.). At dispatch sites we want Zig to FORCE us to handle
// every kind — so we map the kind slot into this exhaustive enum (no
// trailing `_,` member). `rig.bindingKindOf(kind_slot)` is the
// converter; consumers (M2 walkSet, M3 emitSet, scanMutations) switch on
// this enum and the compiler refuses to build a switch missing any arm.

pub const BindingKind = enum {
    default,    // `=`            — kind slot is `_` (nil)
    fixed,      // `=!`           — kind slot is `.fixed`
    shadow,     // `new x = ...`  — kind slot is `.shadow`
    @"move",    // `<-`           — kind slot is `.@"move"`
    @"+=",      // compound add-assign
    @"-=",      // compound sub-assign
    @"*=",      // compound mul-assign
    @"/=",      // compound div-assign
};

/// Decode the kind slot of a normalized binding form `(set <kind> ...)`
/// into the exhaustive `BindingKind` enum.
///
/// A kind slot we don't recognize falls through to `.default` rather
/// than panicking; in practice the normalizer only ever emits the
/// kinds listed above, so an unknown kind would indicate IR corruption.
pub fn bindingKindOf(kind_slot: Sexp) BindingKind {
    if (kind_slot == .nil) return .default;
    if (kind_slot != .tag) return .default;
    return switch (kind_slot.tag) {
        .fixed => .fixed,
        .shadow => .shadow,
        .@"move" => .@"move",
        .@"+=" => .@"+=",
        .@"-=" => .@"-=",
        .@"*=" => .@"*=",
        .@"/=" => .@"/=",
        else => .default,
    };
}

// =============================================================================
// Keyword lookup — maps identifier text to parser symbol IDs
// =============================================================================
//
// Inherited from Zag set, with these Rig deltas:
//   removed: `comptime`  (replaced by `pre`)
//   added:   `pre`, `new`

pub const KeywordId = enum(u16) {
    FUN,
    SUB,
    USE,
    IF,
    ELSE,
    WHILE,
    FOR,
    IN,
    MATCH,
    RETURN,
    BREAK,
    CONTINUE,
    DEFER,
    ERRDEFER,
    TRY,
    FN,
    PUB,
    EXTERN,
    EXPORT,
    INLINE,
    VOLATILE,
    CONST,
    ALIGN,
    CALLCONV,
    ENUM,
    STRUCT,
    PACKED,
    OPAQUE,
    ERROR,
    TYPE,
    TEST,
    PRE,            // Rig: replaces COMPTIME
    NEW,            // Rig: explicit shadowing
    ZIG,
    NULL,
    UNREACHABLE,
    UNDEFINED,
    AS,
    CATCH,
    TRUE,
    FALSE,
    AND,
    OR,
    NOT,
    COMMENT,
    NEWLINE,
    IDENT,
    INTEGER,
    REAL,
    STRING_SQ,
    STRING_DQ,
    INDENT,
    OUTDENT,
};

const keywordMap = std.StaticStringMap(KeywordId).initComptime(.{
    .{ "fun", .FUN },
    .{ "sub", .SUB },
    .{ "use", .USE },
    .{ "if", .IF },
    .{ "else", .ELSE },
    .{ "while", .WHILE },
    .{ "for", .FOR },
    .{ "in", .IN },
    .{ "match", .MATCH },
    .{ "return", .RETURN },
    .{ "break", .BREAK },
    .{ "continue", .CONTINUE },
    .{ "defer", .DEFER },
    .{ "errdefer", .ERRDEFER },
    .{ "try", .TRY },
    .{ "fn", .FN },
    .{ "pub", .PUB },
    .{ "extern", .EXTERN },
    .{ "export", .EXPORT },
    .{ "inline", .INLINE },
    .{ "volatile", .VOLATILE },
    .{ "const", .CONST },
    .{ "align", .ALIGN },
    .{ "callconv", .CALLCONV },
    .{ "enum", .ENUM },
    .{ "struct", .STRUCT },
    .{ "packed", .PACKED },
    .{ "opaque", .OPAQUE },
    .{ "error", .ERROR },
    .{ "type", .TYPE },
    .{ "test", .TEST },
    .{ "pre", .PRE },         // Rig
    .{ "new", .NEW },         // Rig
    .{ "zig", .ZIG },
    .{ "null", .NULL },
    .{ "unreachable", .UNREACHABLE },
    .{ "undefined", .UNDEFINED },
    .{ "as", .AS },
    .{ "catch", .CATCH },
    .{ "true", .TRUE },
    .{ "false", .FALSE },
    .{ "and", .AND },
    .{ "or", .OR },
    .{ "not", .NOT },
});

pub fn keywordAs(name: []const u8) ?KeywordId {
    return keywordMap.get(name);
}

// =============================================================================
// Lexer — indentation + sigil-classifying wrapper around generated BaseLexer
// =============================================================================
//
// Indentation logic copied verbatim from Zag's well-tested implementation.
//
// Rig-specific classifications layered on top:
//
//   <x   tight + expression-start  → move_pfx     (else `lt`)
//   +x   tight + expression-start  → clone_pfx    (else `plus`)
//   %x   tight + expression-start  → raw_pfx      (else `percent`)
//   @x   tight + expression-start  → pin_pfx      (when ident not followed by `(`;
//                                                  builtin call `@name(...)` stays `at`)
//   -x   tight + statement-start   → drop_stmt    (else `minus_prefix` per Zag rule
//                                                  or infix `minus`)
//   x?   tight + value-ender prev  → suffix_q     (else `question`)
//
// Ownership prefixes that ALSO need rewriter classification (because
// the bare token is also infix or has a type-rule role that would
// conflict with the atom-rule alternative):
//   ?x   tight + expression context  → read_pfx    (else `question` for postfix unused)
//   !x   tight + expression context  → write_pfx   (else `not_sym`)
//   *x   tight + expression context  → share_pfx   (else `star`; `.*` deref preserved
//                                                   by the `last_cat == .dot` exclusion)
//
// `~x` (weak) needs no rewriter token: `~` has no infix role in Rig V1
// (we drop Zag's bit-not), so the grammar's `unary = "~" unary → (weak 2)`
// is unambiguous.

pub const Lexer = struct {
    base: BaseLexer,

    // Indentation tracking (mirrored from Zag)
    indent_level: u32 = 0,
    indent_stack: [64]u32 = .{0} ** 64,
    indent_depth: u8 = 0,
    indent_pending: u8 = 0,
    indent_queued: ?Token = null,
    indent_trailing_newline: bool = false,

    // Rewriter context
    last_cat: TokenCat = .eof,
    flow_if_active: bool = false,
    bracket_depth: u8 = 0,

    // After classifying an opening `|` as bar_capture, expect the closing
    // `|` (after one ident) to also be bar_capture. Cleared on any other
    // structural token.
    pending_close_bar: bool = false,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
        self.indent_level = 0;
        self.indent_depth = 0;
        self.indent_pending = 0;
        self.indent_queued = null;
        self.indent_trailing_newline = false;
        self.last_cat = .eof;
        self.flow_if_active = false;
        self.bracket_depth = 0;
        self.pending_close_bar = false;
    }

    pub fn next(self: *Lexer) Token {
        if (self.indent_queued) |q| {
            self.indent_queued = null;
            self.last_cat = q.cat;
            return q;
        }
        if (self.indent_pending > 0) {
            self.indent_pending -= 1;
            if (self.indent_pending == 0 and self.indent_trailing_newline) {
                self.indent_trailing_newline = false;
                self.indent_queued = Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            }
            self.last_cat = .outdent;
            return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        }

        while (true) {
            const tok = self.base.matchRules();

            // Skip comment tokens
            if (tok.cat == .comment) continue;

            // Collapse repeated newlines, but still process indent changes on the last one
            if (tok.cat == .newline and (self.last_cat == .newline or self.last_cat == .indent or self.last_cat == .outdent or self.last_cat == .eof)) {
                var ws: u32 = 0;
                while (self.base.pos + ws < self.base.source.len) {
                    const ch = self.base.source[self.base.pos + ws];
                    if (ch == ' ' or ch == '\t') {
                        ws += 1;
                    } else break;
                }
                const dup_at_eof = self.base.pos + ws >= self.base.source.len;
                const dup_next = if (!dup_at_eof) self.base.source[self.base.pos + ws] else 0;
                const dup_is_empty = dup_at_eof or dup_next == '\n' or dup_next == '\r';
                if (dup_is_empty) continue;
                if (dup_next == '#' and ws == self.indent_level) continue;
                if (ws != self.indent_level) {
                    self.flow_if_active = false;
                    const result = self.handleIndent(tok);
                    self.last_cat = result.cat;
                    return result;
                }
                continue;
            }

            if (tok.cat == .newline) {
                self.flow_if_active = false;
                const result = self.handleIndent(tok);
                self.last_cat = result.cat;
                return result;
            }

            if (tok.cat == .eof) {
                self.flow_if_active = false;
                if (self.indent_depth > 0) {
                    self.indent_depth -= 1;
                    if (self.indent_depth > 0) {
                        self.indent_pending = self.indent_depth;
                        self.indent_depth = 0;
                    }
                    self.indent_level = 0;
                    self.indent_trailing_newline = false;
                    self.last_cat = .outdent;
                    return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                }
                self.last_cat = .eof;
                return tok;
            }

            // Bracket depth tracking
            if (tok.cat == .lbracket) self.bracket_depth += 1;
            if (tok.cat == .rbracket and self.bracket_depth > 0) self.bracket_depth -= 1;

            // .{ → fuse into dot_lbrace token for anonymous struct init
            if (tok.cat == .dot and self.base.pos < self.base.source.len and
                self.base.source[self.base.pos] == '{')
            {
                var fused = tok;
                fused.cat = .dot_lbrace;
                fused.len = 2;
                self.base.pos += 1;
                self.base.brace += 1;
                self.last_cat = .dot_lbrace;
                return fused;
            }

            // . → dot | dot_lit
            //
            // dot_lit fires when at expression-start (last_cat is not a
            // value-ender) AND the next char starts an ident. This is the
            // enum literal form `.strict`. Member-access `obj.name` stays
            // as `dot` (last_cat is ident → value-ender).
            if (tok.cat == .dot and !isValueCat(self.last_cat) and
                self.base.pos < self.base.source.len and
                isIdentStart(self.base.source[self.base.pos]))
            {
                var dl = tok;
                dl.cat = .dot_lit;
                self.last_cat = .dot_lit;
                return dl;
            }

            // -----------------------------------------------------------------
            // Rig sigil classification (in order of token category)
            // -----------------------------------------------------------------

            // - → minus | minus_prefix | drop_stmt
            if (tok.cat == .minus) {
                var classified = tok;
                classified.cat = self.classifyMinus(tok);
                self.last_cat = classified.cat;
                return classified;
            }

            // < → lt | move_pfx
            if (tok.cat == .lt) {
                if (self.isPrefixSigil(tok)) {
                    var move = tok;
                    move.cat = .move_pfx;
                    self.last_cat = .move_pfx;
                    return move;
                }
            }

            // + → plus | clone_pfx
            if (tok.cat == .plus) {
                if (self.isPrefixSigil(tok)) {
                    var clone = tok;
                    clone.cat = .clone_pfx;
                    self.last_cat = .clone_pfx;
                    return clone;
                }
            }

            // % → percent | raw_pfx
            if (tok.cat == .percent) {
                if (self.isPrefixSigil(tok)) {
                    var raw = tok;
                    raw.cat = .raw_pfx;
                    self.last_cat = .raw_pfx;
                    return raw;
                }
            }

            // @ → at | pin_pfx
            //
            // pin_pfx wins when: looks like a prefix sigil AND the next ident
            // is NOT followed by `(` (which would make it a builtin call).
            if (tok.cat == .at) {
                if (self.isPrefixSigil(tok) and self.atIsPinNotBuiltin()) {
                    var pin = tok;
                    pin.cat = .pin_pfx;
                    self.last_cat = .pin_pfx;
                    return pin;
                }
            }

            // ? → question | suffix_q | read_pfx
            //
            //   tight + value-ender preceding   → suffix_q   (T? optional suffix in type
            //                                                 context; reserved for future
            //                                                 optional-propagation in expr
            //                                                 context — `?` family is
            //                                                 optional / null)
            //   isPrefixSigil                   → read_pfx   (`?T`, `?x`, `?user`)
            //   else                            → question
            if (tok.cat == .question) {
                if (tok.pre == 0 and isValueCat(self.last_cat)) {
                    var prop = tok;
                    prop.cat = .suffix_q;
                    self.last_cat = .suffix_q;
                    return prop;
                }
                if (self.isPrefixSigil(tok)) {
                    var rp = tok;
                    rp.cat = .read_pfx;
                    self.last_cat = .read_pfx;
                    return rp;
                }
            }

            // ! → not_sym | write_pfx | suffix_bang
            //
            //   tight + value-ender preceding   → suffix_bang   (T! fallible type;
            //                                                    parser-state-dispatched
            //                                                    so this is type-only — see
            //                                                    grammar's `type SUFFIX_BANG`)
            //   isPrefixSigil                   → write_pfx     (`!user`, `!T` write borrow)
            //   else                            → not_sym
            if (tok.cat == .not_sym) {
                if (tok.pre == 0 and isValueCat(self.last_cat)) {
                    var sb = tok;
                    sb.cat = .suffix_bang;
                    self.last_cat = .suffix_bang;
                    return sb;
                }
                if (self.isPrefixSigil(tok)) {
                    var wp = tok;
                    wp.cat = .write_pfx;
                    self.last_cat = .write_pfx;
                    return wp;
                }
            }

            // * → star | share_pfx
            //
            //   isPrefixSigil  → share_pfx   (`*user`, `*T`; `.*` deref excluded
            //                                  via the `last_cat == .dot` check
            //                                  inside isPrefixSigil)
            //   else           → star
            if (tok.cat == .star) {
                if (self.isPrefixSigil(tok)) {
                    var sp = tok;
                    sp.cat = .share_pfx;
                    self.last_cat = .share_pfx;
                    return sp;
                }
            }

            // | → bar | bar_capture
            //
            // Opening `|` is classified when probe sees `ident |` ahead.
            // After that, `pending_close_bar` is set and the next `|`
            // (after the captured ident) is auto-classified.
            if (tok.cat == .bar) {
                if (self.pending_close_bar) {
                    self.pending_close_bar = false;
                    var cap = tok;
                    cap.cat = .bar_capture;
                    self.last_cat = .bar_capture;
                    return cap;
                }
                if (self.isCapturePipe()) {
                    var cap = tok;
                    cap.cat = .bar_capture;
                    self.last_cat = .bar_capture;
                    self.pending_close_bar = true;
                    return cap;
                }
            }

            // if → if | post_if | ternary_if (Zag classification, kept verbatim)
            if (tok.cat == .ident) {
                const ident_text = self.base.source[tok.pos..][0..tok.len];
                if (std.mem.eql(u8, ident_text, "if") and self.flow_if_active and
                    self.base.paren == 0 and self.base.brace == 0 and self.bracket_depth == 0)
                {
                    var post = tok;
                    post.cat = .post_if;
                    self.flow_if_active = false;
                    self.last_cat = .post_if;
                    return post;
                }
                if (std.mem.eql(u8, ident_text, "if") and !self.flow_if_active and
                    isValueCat(self.last_cat) and self.hasElseOnLine())
                {
                    var ternary = tok;
                    ternary.cat = .ternary_if;
                    self.last_cat = .ternary_if;
                    return ternary;
                }
                if (std.mem.eql(u8, ident_text, "return") or
                    std.mem.eql(u8, ident_text, "break") or
                    std.mem.eql(u8, ident_text, "continue"))
                {
                    self.flow_if_active = true;
                }

                // ident → kwarg_name when inside parens AND immediately followed
                // by `:` (constructor / call kwarg sugar). The grammar's `arg`
                // rule then accepts `KWARG_NAME ":" expr → (pair 1 3)`.
                if (self.base.paren > 0 and self.nextSignificantIsColon()) {
                    var kw = tok;
                    kw.cat = .kwarg_name;
                    self.last_cat = .kwarg_name;
                    return kw;
                }
            }

            self.last_cat = tok.cat;
            return tok;
        }
    }

    // -------------------------------------------------------------------------
    // Sigil classification helpers
    // -------------------------------------------------------------------------

    /// True when this `<sigil>` token should be reclassified as a prefix
    /// operator. Mirrors Zag's `classifyMinus` rule, which handles three
    /// surface forms uniformly:
    ///
    ///   `<x`         (statement start)        prefix
    ///   `f <x`       (Ruby-style arg pos)     prefix          (last_cat value, pre > 0)
    ///   `a < b`      (infix less-than)        NOT prefix      (space after)
    ///   `a<b`        (compact infix)          NOT prefix      (last_cat value, pre == 0)
    ///   `= <x`       (after assign etc.)      prefix          (last_cat NOT value)
    ///
    /// Conditions:
    ///   1. Operand-like char immediately follows (no space after).
    ///   2. Either (a) we're in expression-start context, or
    ///      (b) we're in arg position (value-ender preceded with space).
    fn isPrefixSigil(self: *const Lexer, tok: Token) bool {
        const end = tok.pos + tok.len;
        if (end >= self.base.source.len) return false;
        const c = self.base.source[end];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') return false;
        if (!isOperandStart(c)) return false;

        // `.*` is postfix deref, not share/anything. Don't rewrite.
        if (self.last_cat == .dot) return false;

        if (!isValueCat(self.last_cat)) return true;
        if (tok.pre > 0) return true;
        return false;
    }

    /// `@` is pin (not builtin) when followed by ident NOT followed by `(`.
    /// `@name(` is a builtin call; `@name` (no paren) is pin.
    fn atIsPinNotBuiltin(self: *const Lexer) bool {
        var p = self.base.pos;
        // Already past the `@`. Must have an ident-start char.
        if (p >= self.base.source.len) return false;
        const c0 = self.base.source[p];
        if (!isIdentStart(c0)) return false;
        // Skip the ident
        p += 1;
        while (p < self.base.source.len and isIdentCont(self.base.source[p])) : (p += 1) {}
        // If followed by `(` it's a builtin call; otherwise pin
        if (p >= self.base.source.len) return true;
        return self.base.source[p] != '(';
    }

    /// Reclassify `-` per Zag's rule, plus drop_stmt at statement-start.
    fn classifyMinus(self: *const Lexer, tok: Token) TokenCat {
        const end = tok.pos + tok.len;
        const space_after = end >= self.base.source.len or
            self.base.source[end] == ' ' or self.base.source[end] == '\t' or
            self.base.source[end] == '\n' or self.base.source[end] == '\r';

        // Drop statement: `-x` at statement start, tight, ident operand
        if (!space_after and isStmtStart(self.last_cat)) {
            const c = self.base.source[end];
            if (isIdentStart(c)) return .drop_stmt;
        }

        if (space_after) return .minus;
        if (!canEndExpr(self.last_cat) or tok.pre > 0) return .minus_prefix;
        return .minus;
    }

    fn canEndExpr(cat: TokenCat) bool {
        return switch (cat) {
            .ident, .integer, .real, .string_sq, .string_dq,
            .true, .false,
            .rparen, .rbracket, .rbrace,
            .suffix_q,
            => true,
            else => false,
        };
    }

    fn isStmtStart(cat: TokenCat) bool {
        return switch (cat) {
            .newline, .indent, .outdent, .eof => true,
            else => false,
        };
    }

    fn isValueCat(cat: TokenCat) bool {
        return switch (cat) {
            .ident, .integer, .real, .string_sq, .string_dq,
            .true, .false,
            .rparen, .rbracket, .rbrace,
            .suffix_q,
            => true,
            else => false,
        };
    }

    fn isOperandStart(c: u8) bool {
        return isIdentStart(c) or
            (c >= '0' and c <= '9') or
            c == '(' or c == '[' or c == '{' or
            c == '"' or c == '\'' or
            // sigils chaining is allowed in V1 lexer; the parser/normalizer
            // decides legality (e.g., `<+x` would parse but normalize will
            // typically reject)
            c == '<' or c == '?' or c == '!' or c == '+' or c == '-' or
            c == '*' or c == '~' or c == '@' or c == '%' or c == '.';
    }

    fn isIdentStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isIdentCont(c: u8) bool {
        return isIdentStart(c) or (c >= '0' and c <= '9');
    }

    // -------------------------------------------------------------------------
    // Indentation handling — copied verbatim from Zag (well-tested)
    // -------------------------------------------------------------------------

    fn handleIndent(self: *Lexer, nl_tok: Token) Token {
        if (self.base.paren > 0 or self.base.brace > 0) return nl_tok;

        var ws: u32 = 0;
        while (self.base.pos + ws < self.base.source.len) {
            const ch = self.base.source[self.base.pos + ws];
            if (ch == ' ' or ch == '\t') {
                ws += 1;
            } else break;
        }
        // Scan past blank lines to find the first content line's indent
        var line_start = self.base.pos;
        while (line_start + ws < self.base.source.len) {
            const ch = self.base.source[line_start + ws];
            if (ch == '\n' or ch == '\r') {
                line_start = line_start + ws + 1;
                ws = 0;
                while (line_start + ws < self.base.source.len) {
                    const wc = self.base.source[line_start + ws];
                    if (wc == ' ' or wc == '\t') {
                        ws += 1;
                    } else break;
                }
                continue;
            }
            break;
        }
        const at_eof = line_start + ws >= self.base.source.len;
        if (!at_eof) {
            const next_ch = self.base.source[line_start + ws];
            if (next_ch == '#' and ws == self.indent_level) {
                return nl_tok;
            }
        }
        var ws_eff = ws;
        if (at_eof) ws_eff = 0;

        if (ws_eff > self.indent_level) {
            if (self.indent_depth >= 63)
                return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            self.indent_stack[self.indent_depth] = self.indent_level;
            self.indent_depth += 1;
            self.indent_level = ws_eff;
            return Token{ .cat = .indent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
        } else if (ws_eff < self.indent_level) {
            var count: u8 = 0;
            var next_level = self.indent_level;
            while (next_level > ws_eff) {
                if (self.indent_depth == 0)
                    return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                self.indent_depth -= 1;
                next_level = self.indent_stack[self.indent_depth];
                count += 1;
            }
            if (next_level != ws_eff)
                return Token{ .cat = .err, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            self.indent_level = ws_eff;
            if (count > 0) {
                const needs_newline = !at_eof and !self.nextTokenIsElse();
                if (count > 1) {
                    self.indent_pending = count - 1;
                    self.indent_trailing_newline = needs_newline;
                } else if (needs_newline) {
                    self.indent_queued = Token{ .cat = .newline, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
                }
                return Token{ .cat = .outdent, .pre = 0, .pos = @intCast(self.base.pos), .len = 0 };
            }
            return nl_tok;
        }
        return nl_tok;
    }

    fn nextTokenIsElse(self: *const Lexer) bool {
        var probe = self.base;
        const tok = probe.matchRules();
        if (tok.cat != .ident) return false;
        const ident_text = self.base.source[tok.pos..][0..tok.len];
        // Block-continuation keywords that should NOT be split off the
        // preceding block by an injected newline.
        return std.mem.eql(u8, ident_text, "else") or
            std.mem.eql(u8, ident_text, "catch");
    }

    fn hasElseOnLine(self: *const Lexer) bool {
        var probe = self.base;
        var depth: i32 = 0;
        while (true) {
            const tok = probe.matchRules();
            switch (tok.cat) {
                .newline, .eof => return false,
                .lparen => depth += 1,
                .rparen => depth -= 1,
                .lbracket => depth += 1,
                .rbracket => depth -= 1,
                .lbrace => depth += 1,
                .rbrace => depth -= 1,
                .ident => {
                    if (depth == 0 and tok.len == 4 and
                        std.mem.eql(u8, self.base.source[tok.pos..][0..4], "else"))
                        return true;
                },
                else => {},
            }
        }
    }

    fn isCapturePipe(self: *const Lexer) bool {
        var probe = self.base;
        const tok1 = probe.matchRules();
        if (tok1.cat != .ident) return false;
        const tok2 = probe.matchRules();
        return tok2.cat == .bar;
    }

    /// Probe ahead: is the next significant token a `:` ?
    fn nextSignificantIsColon(self: *const Lexer) bool {
        var probe = self.base;
        const tok = probe.matchRules();
        return tok.cat == .colon;
    }
};

// =============================================================================
// Parser — parse-stage rewriter (BaseParser + sexp normalization)
// =============================================================================
//
// `BaseParser` (in parser.zig, generated by Nexus) is the parse-stage
// raw producer — it consumes tokens from `Lexer` and emits raw S-
// expressions via the grammar's per-rule actions.
//
// `Parser` (this struct) is the language-specific wrapper that runs
// BaseParser, then walks the raw Sexp tree and rewrites it into the
// normalized semantic IR documented in `docs/SEMANTIC-SEXP.md`. M2
// (ownership checker) and M3 (Zig emitter) consume Parser's output, not
// BaseParser's.
//
// Nexus auto-wires `parser.Parser = if (@hasDecl(rig, "Parser")) rig.Parser else BaseParser;`
// at the parser.zig top level, so `parser.Parser.init(allocator, source)`
// from anywhere in the Rig codebase picks up this wrapper automatically,
// and `parser.parseProgram(allocator, source)` returns the fully-rewritten
// IR via the top-level convenience helper.

pub const Parser = struct {
    base: BaseParser,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Parser {
        return .{ .base = BaseParser.init(alloc, source) };
    }

    pub fn deinit(self: *Parser) void {
        self.base.deinit();
    }

    pub fn printError(self: *Parser) void {
        self.base.printError();
    }

    /// Expose the underlying raw token for diagnostics (callers reach
    /// for this on parse failure to build a span).
    pub fn current(self: *const Parser) Token {
        return self.base.current;
    }

    /// Parse + rewrite. Returns the normalized semantic IR.
    pub fn parseProgram(self: *Parser) !Sexp {
        const raw = try self.base.parseProgram();
        return self.rewrite(raw);
    }

    /// Standalone rewriter — kept public so unit tests can feed in
    /// hand-built raw Sexps without going through a real parse.
    pub fn rewrite(self: *Parser, sexp: Sexp) !Sexp {
        return self.walk(sexp);
    }

    fn allocator(self: *Parser) std.mem.Allocator {
        return self.base.arena.allocator();
    }

    /// The grammar emits the normalized IR shape directly for nearly
    /// everything (using the tag-literal-at-child-position feature added
    /// in Nexus 0.10.x+). The Parser's only remaining responsibility is
    /// **inspection-requiring transforms** that can't be expressed in a
    /// declarative grammar action — currently just one: consuming the
    /// `for` source's outer ownership-wrapper (`(read xs)` etc.) into
    /// the `for` form's mode slot.
    ///
    /// Walks children for everything else so cosmetic renames in nested
    /// positions still work consistently.
    fn walk(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        switch (sexp) {
            .nil, .tag, .src, .str => return sexp,
            .list => |items| {
                if (items.len == 0) return sexp;
                if (items[0] == .tag and items[0].tag == .@"for") {
                    return try self.normFor(items);
                }
                return self.walkChildren(sexp);
            },
        }
    }

    fn walkChildren(self: *Parser, sexp: Sexp) !Sexp {
        const items = sexp.list;
        var out = try self.allocator().alloc(Sexp, items.len);
        for (items, 0..) |child, i| {
            out[i] = try self.walk(child);
        }
        return Sexp{ .list = out };
    }

    /// Consume the source's outer ownership wrapper into the for-mode slot.
    ///
    /// Raw from grammar:    (for <mode> binding1 binding2 source body else?)
    /// where mode is one of:
    ///   `iter` — default value iteration, no sigil and no `*`
    ///   `ptr`  — `for *x in xs`
    /// When mode is `iter`, the source MAY be a `(read X)` / `(write X)`
    /// / `(move X)` wrapper from the source's `?xs` / `!xs` / `<xs`
    /// sigil. We promote that wrapper into the mode slot and unwrap
    /// the source to its inner expression — the one transform Nexus
    /// can't do declaratively (it requires inspecting a child).
    ///
    /// `ptr` mode is left alone (V1 doesn't combine `*` and sigil).
    fn normFor(self: *Parser, items: []const Sexp) !Sexp {
        if (items.len < 6) return self.walkChildren(.{ .list = items });

        const raw_mode = items[1];
        const binding1 = try self.walk(items[2]);
        const binding2 = try self.walk(items[3]);
        const raw_source = items[4];
        const source = try self.walk(raw_source);

        var mode: Sexp = raw_mode;
        var unwrapped_source = source;

        const mode_is_iter = (raw_mode == .tag and raw_mode.tag == .iter);
        if (mode_is_iter and source == .list and source.list.len >= 2 and
            source.list[0] == .tag)
        {
            switch (source.list[0].tag) {
                .@"read" => {
                    mode = .{ .tag = .@"read" };
                    unwrapped_source = source.list[1];
                },
                .@"write" => {
                    mode = .{ .tag = .@"write" };
                    unwrapped_source = source.list[1];
                },
                .@"move" => {
                    mode = .{ .tag = .@"move" };
                    unwrapped_source = source.list[1];
                },
                else => {},
            }
        }

        const body = try self.walk(items[5]);
        const has_else = items.len >= 7;
        const else_body = if (has_else) try self.walk(items[6]) else Sexp{ .nil = {} };

        const out_len: usize = if (has_else) 7 else 6;
        const out = try self.allocator().alloc(Sexp, out_len);
        out[0] = .{ .tag = .@"for" };
        out[1] = mode;
        out[2] = binding1;
        out[3] = binding2;
        out[4] = unwrapped_source;
        out[5] = body;
        if (has_else) out[6] = else_body;
        return Sexp{ .list = out };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "keywordAs - core Rig keywords" {
    try std.testing.expectEqual(KeywordId.FUN, keywordAs("fun").?);
    try std.testing.expectEqual(KeywordId.SUB, keywordAs("sub").?);
    try std.testing.expectEqual(KeywordId.PRE, keywordAs("pre").?);
    try std.testing.expectEqual(KeywordId.NEW, keywordAs("new").?);
    try std.testing.expectEqual(KeywordId.IF, keywordAs("if").?);
    try std.testing.expectEqual(KeywordId.CATCH, keywordAs("catch").?);
    try std.testing.expectEqual(KeywordId.TRY, keywordAs("try").?);
    try std.testing.expectEqual(KeywordId.TRUE, keywordAs("true").?);
}

test "keywordAs - comptime is gone (replaced by pre)" {
    try std.testing.expect(keywordAs("comptime") == null);
}

test "keywordAs - inherited from Zag still present" {
    try std.testing.expectEqual(KeywordId.DEFER, keywordAs("defer").?);
    try std.testing.expectEqual(KeywordId.ERRDEFER, keywordAs("errdefer").?);
    try std.testing.expectEqual(KeywordId.EXTERN, keywordAs("extern").?);
    try std.testing.expectEqual(KeywordId.PACKED, keywordAs("packed").?);
    try std.testing.expectEqual(KeywordId.VOLATILE, keywordAs("volatile").?);
    try std.testing.expectEqual(KeywordId.CALLCONV, keywordAs("callconv").?);
    try std.testing.expectEqual(KeywordId.INLINE, keywordAs("inline").?);
    try std.testing.expectEqual(KeywordId.ENUM, keywordAs("enum").?);
    try std.testing.expectEqual(KeywordId.STRUCT, keywordAs("struct").?);
    try std.testing.expectEqual(KeywordId.ERROR, keywordAs("error").?);
    try std.testing.expectEqual(KeywordId.TEST, keywordAs("test").?);
    try std.testing.expectEqual(KeywordId.ZIG, keywordAs("zig").?);
    try std.testing.expectEqual(KeywordId.NULL, keywordAs("null").?);
    try std.testing.expectEqual(KeywordId.UNDEFINED, keywordAs("undefined").?);
    try std.testing.expectEqual(KeywordId.UNREACHABLE, keywordAs("unreachable").?);
}

test "keywordAs - non-keywords" {
    try std.testing.expect(keywordAs("loadUser") == null);
    try std.testing.expect(keywordAs("user") == null);
    try std.testing.expect(keywordAs("packet") == null);
    try std.testing.expect(keywordAs("") == null);
    try std.testing.expect(keywordAs("var") == null);    // intentionally not a keyword
    try std.testing.expect(keywordAs("let") == null);    // intentionally not a keyword
}

// -----------------------------------------------------------------------------
// Parser (sexp rewriter) tests
//
// These tests exercise `Parser.rewrite` against hand-built raw Sexps,
// without going through a real parse. `Parser` wraps a `BaseParser`
// internally; for these tests we initialize it with an empty source and
// never call `parseProgram`, just `rewrite`. The arena owned by the
// BaseParser inside `Parser` provides the allocator for the rewritten
// tree, and `Parser.deinit` frees it.
// -----------------------------------------------------------------------------

// The Parser (sexp rewriter) now does ONE inspection-requiring
// transform: consuming the `for` source's outer ownership wrapper
// into the for's mode slot. Everything else (binding renames,
// kind-tagging, cosmetic renames like `.` → `member`, `pair` → `kwarg`)
// is done by the grammar directly via the tag-literal-at-child-position
// feature in Nexus 0.10.x+.

test "parser: for-sigil consumption (iter → read)" {
    // Raw from grammar: (for iter x _ (read xs) body)
    // Expected after rewrite: (for read x _ xs body)
    const xs_src = Sexp{ .str = "xs" };
    var read_items = [_]Sexp{ .{ .tag = .@"read" }, xs_src };
    const read_wrap = Sexp{ .list = &read_items };

    const x_src = Sexp{ .str = "x" };
    const body = Sexp{ .str = "body" };
    var raw_items = [_]Sexp{
        .{ .tag = .@"for" },
        .{ .tag = .iter }, // mode = iter (default from grammar)
        x_src,
        .{ .nil = {} },
        read_wrap,
        body,
    };
    const raw = Sexp{ .list = &raw_items };

    var p = Parser.init(std.testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(raw);

    try std.testing.expectEqual(Tag.@"for", out.list[0].tag);
    try std.testing.expect(out.list[1] == .tag);
    try std.testing.expectEqual(Tag.@"read", out.list[1].tag); // mode promoted to read
    try std.testing.expect(out.list[4] == .str);                // source unwrapped to xs
}

test "parser: for with no sigil keeps iter mode" {
    const x_src = Sexp{ .str = "x" };
    const xs_src = Sexp{ .str = "xs" };
    const body = Sexp{ .str = "body" };
    var raw_items = [_]Sexp{
        .{ .tag = .@"for" },
        .{ .tag = .iter },
        x_src,
        .{ .nil = {} },
        xs_src,
        body,
    };
    const raw = Sexp{ .list = &raw_items };

    var p = Parser.init(std.testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(raw);

    try std.testing.expectEqual(Tag.@"for", out.list[0].tag);
    try std.testing.expectEqual(Tag.iter, out.list[1].tag); // mode stays iter
}

test "parser: for ptr leaves source alone" {
    // (for ptr p _ items body) — when grammar already set ptr mode,
    // the Parser should NOT inspect/unwrap the source.
    const p_src = Sexp{ .str = "p" };
    const items_src = Sexp{ .str = "items" };
    const body = Sexp{ .str = "body" };
    var raw_items = [_]Sexp{
        .{ .tag = .@"for" },
        .{ .tag = .@"ptr" }, // mode = ptr (set by grammar)
        p_src,
        .{ .nil = {} },
        items_src,
        body,
    };
    const raw = Sexp{ .list = &raw_items };

    var par = Parser.init(std.testing.allocator, "");
    defer par.deinit();
    const out = try par.rewrite(raw);

    try std.testing.expectEqual(Tag.@"for", out.list[0].tag);
    try std.testing.expectEqual(Tag.@"ptr", out.list[1].tag); // mode preserved
}
