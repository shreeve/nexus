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
//   - `=!` Tag renamed `fixed_bind` (was `const_assign` in Zag)
// Added by Rig:
//   - ownership: move, read, write, clone, drop, share, weak, pin, raw
//   - bindings:  fixed_bind, move_assign, shadow
//   - control:   try_block, catch_block, propagate
//   - iteration: for_read, for_write, for_move
//   - meta:      pre, pre_param, pre_block

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
    @"extern_var",
    @"extern_const",
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
    // ALL normalized binding forms share a single uniform 5-child shape:
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
    // The `shadow` Tag enum entry serves dual purposes: as a kind tag in
    // the set's slot, AND as a generic "explicit shadowing" marker.
    // `move` likewise doubles as both an ownership-wrapper Tag and a
    // kind tag — context (position 1 of `set` vs head of an expression)
    // disambiguates.
    @"set",             // NORMALIZED universal binding head; see kind discriminator above
    @"shadow",          // RAW from parser; also serves as kind tag in normalized `set`
    @"fixed_bind",      // RAW from parser: x =! expr        (folded to `set fixed` by normalize)
    @"typed_assign",    // RAW from parser: name : T = expr  (folded to `set _` by normalize)
    @"typed_fixed",     // RAW from parser: name : T =! expr (folded to `set fixed` by normalize)
    @"move_assign",     // RAW from parser: x <- expr        (folded to `set move` by normalize)
    @"=",
    @"+=",
    @"-=",
    @"*=",
    @"/=",

    // Control flow
    @"if",
    @"while",
    // for: (for <mode> binding source body else?)
    //   mode is one of `read`, `write`, `move`, `none`
    // SPEC §"Semantic IR Nodes" specifies the (for mode ...) shape.
    @"for",
    @"for_ptr",         // Zag-inherited pointer iteration, kept separate
                        // because it has an extra binding
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
    @".",               // raw member access from parser
    @"member",          // normalized `.` (cosmetic rename)
    @"deref",
    @"index",
    @"array",
    @"record",
    @"pair",            // raw `name: expr` from parser
    @"kwarg",           // normalized `pair` (cosmetic rename)

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
    @"?",               // raw optional type from parser (type position)
    @"optional",        // normalized `?T` (cosmetic rename)
    @"ptr",
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
//   x?   tight + value-ender prev  → prop_q       (else `question`)
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

            // ? → question | prop_q | read_pfx
            //
            //   tight + value-ender preceding   → prop_q     (postfix propagation `expr?`)
            //   isPrefixSigil                   → read_pfx   (`?T`, `?x`, `?user`)
            //   else                            → question
            if (tok.cat == .question) {
                if (tok.pre == 0 and isValueCat(self.last_cat)) {
                    var prop = tok;
                    prop.cat = .prop_q;
                    self.last_cat = .prop_q;
                    return prop;
                }
                if (self.isPrefixSigil(tok)) {
                    var rp = tok;
                    rp.cat = .read_pfx;
                    self.last_cat = .read_pfx;
                    return rp;
                }
            }

            // ! → not_sym | write_pfx
            //
            //   isPrefixSigil  → write_pfx   (`!user`, `!T`)
            //   else           → not_sym
            if (tok.cat == .not_sym) {
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
            .prop_q,
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
            .prop_q,
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

    fn walk(self: *Parser, sexp: Sexp) std.mem.Allocator.Error!Sexp {
        switch (sexp) {
            .nil, .tag, .src, .str => return sexp,
            .list => |items| {
                if (items.len == 0) return sexp;
                if (items[0] != .tag) return self.walkChildren(sexp);

                return switch (items[0].tag) {
                    // All bindings collapse into (set <kind> name type-or-_ expr).
                    .@"=" => try self.normBind(items, .nil, null, false),
                    .@"+=" => try self.normBind(items, .{ .tag = .@"+=" }, null, false),
                    .@"-=" => try self.normBind(items, .{ .tag = .@"-=" }, null, false),
                    .@"*=" => try self.normBind(items, .{ .tag = .@"*=" }, null, false),
                    .@"/=" => try self.normBind(items, .{ .tag = .@"/=" }, null, false),
                    .@"fixed_bind" => try self.normBind(items, .{ .tag = .fixed }, null, false),
                    .@"shadow" => try self.normBind(items, .{ .tag = .shadow }, null, false),
                    .@"move_assign" => try self.normBind(items, .{ .tag = .@"move" }, null, false),
                    .@"typed_assign" => try self.normBind(items, .nil, items[2], true),
                    .@"typed_fixed" => try self.normBind(items, .{ .tag = .fixed }, items[2], true),
                    .@"extern_var" => try self.normExternDecl(items, false),
                    .@"extern_const" => try self.normExternDecl(items, true),
                    .@"." => try self.rewriteHead(items, .member),
                    .@"pair" => try self.rewriteHead(items, .kwarg),
                    .@"?" => try self.rewriteHead(items, .optional),
                    .@"for" => try self.normFor(items, false),
                    .@"for_ptr" => try self.normFor(items, true),
                    else => try self.walkChildren(sexp),
                };
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

    /// Universal binding rewriter. Every raw binding form folds into:
    ///
    ///   (set <kind> name type-or-_ expr)
    fn normBind(
        self: *Parser,
        items: []const Sexp,
        kind: Sexp,
        type_node_in: ?Sexp,
        typed: bool,
    ) !Sexp {
        const min_arity: usize = if (typed) 4 else 3;
        if (items.len < min_arity) return self.walkChildren(.{ .list = items });

        const target = try self.walk(items[1]);
        const expr_raw = if (typed) items[3] else items[2];
        const expr = try self.walk(expr_raw);
        const type_node = if (type_node_in) |t| try self.walk(t) else Sexp{ .nil = {} };

        const out = try self.allocator().alloc(Sexp, 5);
        out[0] = .{ .tag = .set };
        out[1] = kind;
        out[2] = target;
        out[3] = type_node;
        out[4] = expr;
        return Sexp{ .list = out };
    }

    /// (extern_var name type)   → (extern _     name type)
    /// (extern_const name type) → (extern fixed name type)
    fn normExternDecl(self: *Parser, items: []const Sexp, fixed: bool) !Sexp {
        if (items.len < 3) return self.walkChildren(.{ .list = items });
        const name = try self.walk(items[1]);
        const t = try self.walk(items[2]);
        const out = try self.allocator().alloc(Sexp, 4);
        out[0] = .{ .tag = .@"extern" };
        out[1] = if (fixed) Sexp{ .tag = .fixed } else Sexp{ .nil = {} };
        out[2] = name;
        out[3] = t;
        return Sexp{ .list = out };
    }

    /// Per SPEC §"Semantic IR Nodes":
    ///   (for binding _ source body else?) →
    ///     (for <mode> binding source' body else?)
    /// where mode is one of `read`, `write`, `move`, or `_` (nil) for "no
    /// mode" (default iteration).
    fn normFor(self: *Parser, items: []const Sexp, is_ptr: bool) !Sexp {
        if (is_ptr) return self.walkChildren(.{ .list = items });
        if (items.len < 4) return self.walkChildren(.{ .list = items });

        const binding = try self.walk(items[1]);
        const raw_source = items[3];
        const source = try self.walk(raw_source);

        var mode: Sexp = .{ .nil = {} };
        var unwrapped_source = source;
        if (source == .list and source.list.len >= 2 and source.list[0] == .tag) {
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

        const body = try self.walk(items[4]);
        const has_else = items.len >= 6;
        const else_body = if (has_else) try self.walk(items[5]) else Sexp{ .nil = {} };

        const out_len: usize = if (has_else) 6 else 5;
        const out = try self.allocator().alloc(Sexp, out_len);
        out[0] = .{ .tag = .@"for" };
        out[1] = mode;
        out[2] = binding;
        out[3] = unwrapped_source;
        out[4] = body;
        if (has_else) out[5] = else_body;
        return Sexp{ .list = out };
    }

    /// Replace head tag, walk children. Used by simple cosmetic renames
    /// (`(. obj name)` → `(member obj name)`, etc.).
    fn rewriteHead(self: *Parser, items: []const Sexp, new_tag: Tag) !Sexp {
        var out = try self.allocator().alloc(Sexp, items.len);
        out[0] = .{ .tag = new_tag };
        for (items[1..], 1..) |child, i| {
            out[i] = try self.walk(child);
        }
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

test "rewrite: = becomes (set _ ...)" {
    const tag_eq = Sexp{ .tag = .@"=" };
    const x = Sexp{ .str = "x" };
    const one = Sexp{ .str = "1" };
    var raw_items = [_]Sexp{ tag_eq, x, one };
    const raw = Sexp{ .list = &raw_items };

    var p = Parser.init(std.testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(raw);

    try std.testing.expect(out == .list);
    try std.testing.expect(out.list[0] == .tag);
    try std.testing.expectEqual(Tag.set, out.list[0].tag);
    try std.testing.expect(out.list[1] == .nil);   // default kind
}

test "rewrite: move_assign folds into (set move ...)" {
    const tag_ma = Sexp{ .tag = .move_assign };
    const a = Sexp{ .str = "a" };
    const b = Sexp{ .str = "b" };
    var raw_items = [_]Sexp{ tag_ma, a, b };
    const raw = Sexp{ .list = &raw_items };

    var p = Parser.init(std.testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(raw);

    try std.testing.expectEqual(Tag.set, out.list[0].tag);
    try std.testing.expect(out.list[1] == .tag);
    try std.testing.expectEqual(Tag.@"move", out.list[1].tag);
    try std.testing.expect(out.list[3] == .nil);   // type slot
}

test "rewrite: pair becomes kwarg" {
    const tag_p = Sexp{ .tag = .pair };
    const n_node = Sexp{ .str = "name" };
    const v = Sexp{ .str = "Steve" };
    var raw_items = [_]Sexp{ tag_p, n_node, v };
    const raw = Sexp{ .list = &raw_items };

    var p = Parser.init(std.testing.allocator, "");
    defer p.deinit();
    const out = try p.rewrite(raw);

    try std.testing.expectEqual(Tag.kwarg, out.list[0].tag);
}
