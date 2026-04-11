//! em MUMPS Language Helper
//!
//! Language-specific support for the MUMPS parser, providing:
//! - Tag enum for AST node types
//! - Command IDs and abbreviation matching (CmdId, cmdAs)
//! - Function IDs and abbreviation matching (FnId, fnAs)
//! - System variable (ISV) IDs and matching (IsvId, isvAs)
//! - Structured system variable (SSVN) IDs and matching (SsvnId, ssvnAs)
//!
//! Uses efficient first-char dispatch with proper prefix matching:
//! - O(1) first character dispatch via switch
//! - O(m) case-insensitive prefix comparison where m = input length
//! - Rejects names shorter than minimum or longer than maximum

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;
const TokenCat = parser.TokenCat;

// =============================================================================
// LEXER WRAPPER
// =============================================================================
//
// Wraps the nexus-generated BaseLexer to provide MUMPS-specific scanning
// behavior that the declarative grammar cannot express:
//
//   - Pattern mode exit on whitespace, newlines, EOF, and `!` (with hold semantics)
//   - Indent dot-counting at line start
//   - Spaces token with adjacency exclusion (not after comma/paren)
//   - Pattern mode entry after `?`, `'?`, and `'` tokens
//

pub const Lexer = struct {
    base: BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn text(self: *const Lexer, tok: Token) []const u8 {
        return self.base.text(tok);
    }

    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }

    inline fn isWs(c: u8) bool {
        return c == ' ' or c == '\t';
    }

    pub fn next(self: *Lexer) Token {
        const src = self.base.source;
        const wsStart: u32 = self.base.pos;
        while (self.base.pos < src.len and isWs(src[self.base.pos])) {
            self.base.pos += 1;
        }
        const wsCount: u8 = @intCast(@min(self.base.pos - wsStart, 255));

        // Pattern mode exit on whitespace (HOLD): rewind so whitespace
        // is re-lexed on the next call as indent/spaces/pre.
        if (self.base.pat != 0 and wsCount > 0) {
            self.base.pat = 0;
            self.base.pos = wsStart;
            return Token{ .cat = .@"patend", .pre = 0, .pos = wsStart, .len = 0 };
        }

        // Indent with dot-counting at line start
        if (self.base.beg != 0 and wsCount >= 1) {
            self.base.beg = 0;
            var dotCount: u8 = 0;
            while (self.base.pos < src.len and src[self.base.pos] == '.') {
                self.base.pos += 1;
                dotCount +|= 1;
                while (self.base.pos < src.len and isWs(src[self.base.pos])) {
                    self.base.pos += 1;
                }
            }
            return Token{ .cat = .@"indent", .pre = dotCount, .pos = wsStart, .len = @intCast(self.base.pos - wsStart) };
        }

        // Spaces with adjacency exclusion: 2+ spaces mid-line signals an
        // argumentless command, but NOT when adjacent to arglist punctuation.
        if (self.base.beg == 0 and wsCount >= 2) {
            const prevCh: u8 = if (wsStart > 0) src[wsStart - 1] else 0;
            const nextCh: u8 = if (self.base.pos < src.len) src[self.base.pos] else 0;
            if (prevCh != ',' and prevCh != '(' and nextCh != ',' and nextCh != ')') {
                return Token{ .cat = .@"spaces", .pre = 0, .pos = wsStart, .len = wsCount };
            }
            // Excluded: whitespace absorbed into the next token's pre field.
            // Don't rewind -- lex the next real token from current position.
        }

        // EOF
        if (self.base.pos >= src.len) {
            if (self.base.pat != 0) {
                self.base.pat = 0;
                return Token{ .cat = .@"patend", .pre = wsCount, .pos = self.base.pos, .len = 0 };
            }
            return Token{ .cat = .@"eof", .pre = wsCount, .pos = self.base.pos, .len = 0 };
        }

        // Pattern mode: dedicated handler for all pattern-specific tokens
        if (self.base.pat != 0) {
            return self.lexPatternToken(wsCount);
        }

        // Normal lexing: delegate to generated BaseLexer.
        // Rewind only when whitespace is 0-1 chars (normal pre field).
        // When wsCount >= 2, we already decided not to emit SPACES (adjacency
        // exclusion above), so don't rewind or matchRules would re-emit SPACES.
        if (wsCount < 2) {
            self.base.pos = wsStart;
        }
        var tok = self.base.matchRules();
        if (wsCount >= 2) {
            tok.pre = wsCount;
        }

        // Reclassify leading-zero integers (01, 007) as zdigits for labels
        if (tok.cat == .@"integer" and tok.len > 1 and src[tok.pos] == '0') {
            tok.cat = .@"zdigits";
        }

        // Pattern mode entry after ?, '?, and ' tokens.
        // checkPatternMode does lookahead to disambiguate pattern starts
        // (like ?1N) from non-pattern uses (like ?1E+2 or bare ?).
        switch (tok.cat) {
            .@"question", .@"notques", .@"not" => {
                if (self.base.pat == 0) {
                    if (checkPatternMode(self.base.source, self.base.pos))
                        self.base.pat = 1;
                }
            },
            else => {},
        }

        return tok;
    }

    /// Lex a token while in pattern mode. Handles all pattern-specific tokens
    /// directly, avoiding BaseLexer issues with pattern-mode idents (must be
    /// single-char), numbers (integer only, no decimal/exponent), and hold
    /// semantics for pattern-terminating characters.
    fn lexPatternToken(self: *Lexer, wsCount: u8) Token {
        const src = self.base.source;
        const pos = self.base.pos;
        const c = src[pos];

        // Newline: exit pattern mode without consuming (hold)
        if (c == '\n' or c == '\r') {
            self.base.pat = 0;
            self.base.dep = 0;
            return Token{ .cat = .@"patend", .pre = wsCount, .pos = pos, .len = 0 };
        }

        // Underscore: always exits pattern mode (hold)
        if (c == '_') {
            self.base.pat = 0;
            return Token{ .cat = .@"patend", .pre = wsCount, .pos = pos, .len = 0 };
        }

        // At depth 0, these characters terminate the pattern (hold).
        // They belong to the enclosing expression, not the pattern.
        if (self.base.dep == 0) {
            switch (c) {
                '!', ')', ',', ':', '+' => {
                    self.base.pat = 0;
                    return Token{ .cat = .@"patend", .pre = wsCount, .pos = pos, .len = 0 };
                },
                else => {},
            }
        }

        // Pattern-specific tokens
        switch (c) {
            // Single-char pattern code (A, C, E, L, N, P, U, etc.)
            'A'...'Z', 'a'...'z' => {
                self.base.pos += 1;
                self.base.beg = 0;
                return Token{ .cat = .@"ident", .pre = wsCount, .pos = pos, .len = 1 };
            },
            // Repetition count: digits only (no decimal/exponent)
            '0'...'9' => {
                while (self.base.pos < src.len and src[self.base.pos] >= '0' and src[self.base.pos] <= '9') {
                    self.base.pos += 1;
                }
                self.base.beg = 0;
                return Token{ .cat = .@"integer", .pre = wsCount, .pos = pos, .len = @intCast(self.base.pos - pos) };
            },
            // Dot is a range separator in patterns (1.3 = "1 to 3 of"),
            // not a decimal point. Emit as dot to prevent number scanning.
            '.' => {
                self.base.pos += 1;
                self.base.beg = 0;
                return Token{ .cat = .@"dot", .pre = wsCount, .pos = pos, .len = 1 };
            },
            // Open paren: alternation group, track depth
            '(' => {
                self.base.dep += 1;
                self.base.pos += 1;
                self.base.beg = 0;
                return Token{ .cat = .@"lparen", .pre = wsCount, .pos = pos, .len = 1 };
            },
            // Close paren at dep > 0 (dep == 0 handled above as patend)
            ')' => {
                self.base.dep -= 1;
                self.base.pos += 1;
                self.base.beg = 0;
                return Token{ .cat = .@"rparen", .pre = wsCount, .pos = pos, .len = 1 };
            },
            // Fall through to matchRules for mode-invariant tokens:
            // string literal, question mark, apostrophe
            else => {
                self.base.beg = 0;
                var tok = self.base.matchRules();
                tok.pre = wsCount;
                return tok;
            },
        }
    }
};

// =============================================================================
// LEXER HELPERS
// =============================================================================

/// Check if we should enter pattern mode after ? or '?
///
/// MUMPS patterns look like ?1N3A but ?1E+2 is E-notation (not a pattern).
/// This function performs lookahead from the current position to disambiguate.
/// Returns true if pattern mode should be entered.
pub fn checkPatternMode(source: []const u8, pos: u32) bool {
    const p: usize = pos;
    var i: usize = 0;

    while (p + i < source.len) : (i += 1) {
        const ch = source[p + i];
        if ((ch < '0' or ch > '9') and ch != '.') break;
    }

    if (i > 0 and p + i < source.len) {
        const pc = source[p + i];
        const pcLower = pc | 0x20;

        if (pcLower == 'e') {
            const nextPos = p + i + 1;
            if (nextPos < source.len) {
                const nextChar = source[nextPos];
                if (nextChar == '+' or nextChar == '-') return false;
                if (nextChar >= '0' and nextChar <= '9') {
                    var j: usize = 1;
                    while (nextPos + j < source.len and source[nextPos + j] >= '0' and source[nextPos + j] <= '9') : (j += 1) {}
                    if (nextPos + j < source.len) {
                        const after = source[nextPos + j];
                        const afterLower = after | 0x20;
                        if (afterLower == 'a' or afterLower == 'c' or afterLower == 'e' or
                            afterLower == 'l' or afterLower == 'n' or afterLower == 'p' or
                            afterLower == 'u' or after == '"' or after == '\'' or
                            after == '.' or after == '(')
                        {
                            return true;
                        }
                    }
                    return false;
                }
            }
        }

        if (pcLower == 'a' or pcLower == 'c' or pcLower == 'e' or pcLower == 'l' or
            pcLower == 'n' or pcLower == 'p' or pcLower == 'u' or pc == '(' or
            pc == '"')
        {
            return true;
        }
        // ' triggers pattern mode only for negated pattern strings like ?1'"ABC",
        // NOT when followed by ? (which would be a '? operator, e.g. 0'?1N).
        if (pc == '\'') {
            const next = p + i + 1;
            return next >= source.len or source[next] != '?';
        }
    }

    return false;
}

// =============================================================================
// TAG ENUM (AST Node Types)
// =============================================================================

pub const Tag = enum(u8) {
    // Commands
    set,
    write,
    @"if",
    @"else",
    @"for",
    do,
    quit,
    new,
    kill,
    halt,
    hang,
    job,
    lock,
    use,
    open,
    close,
    read,
    tstart,
    tcommit,
    trollback,
    trestart,
    goto,
    xecute,
    merge,
    view,
    @"break",

    // Z-commands
    zwrite,
    zbreak,
    zhalt,
    zkill,

    // Structure
    routine,
    commands,
    expr,
    label,
    dots,
    call,
    ref,
    range,

    // Variables and references
    lvar,
    gvar,
    naked,
    ssvn,

    // Literals
    num,
    str,

    // Functions
    intrinsic,
    extrinsic,
    select,
    text,
    setfn,
    setisv,

    // Indirection
    @"@name",
    @"@args",
    @"@ref",
    @"@subs",
    @"@ssvn", // SSVN name indirection: ^$@X@(subs)

    // Operators / Actions
    @"=",
    @"!",
    @"#",
    posformat,
    @"?",
    @"?@",
    @"'?",
    @"'?@",
    @"+",
    @"-",
    @"*",
    @"/",
    @"\\",

    // Multi-part tags
    postcond,
    setmulti,
    exclusive,
    byref,
    pat,
    alt,
    @"lock+",
    @"lock-",
    @"lock=",
    multi,
    attr,
    params,
    keyword,
    char,
    charindir,
    prompt,
    env,
    uci,

    // Catch-all for unrecognized tags (including key:value patterns)
    _,
};

// =============================================================================
// COMMAND IDS
// =============================================================================

pub const CmdId = enum(u16) {
    BREAK = 100,
    CLOSE,
    DO,
    ELSE,
    FOR,
    GOTO,
    HALT,
    HANG,
    IF,
    JOB,
    KILL,
    LOCK,
    MERGE,
    NEW,
    OPEN,
    QUIT,
    READ,
    SET,
    TCOMMIT,
    TRESTART,
    TROLLBACK,
    TSTART,
    USE,
    VIEW,
    WRITE,
    XECUTE,

    // Z commands
    ZBREAK,
    ZHALT,
    ZKILL,
    ZWRITE,
};

// =============================================================================
// FUNCTION IDS
// =============================================================================

pub const FnId = enum(u16) {
    unknown = 0, // Parser sets id=0 for unrecognized functions
    ASCII = 200,
    CHAR,
    DATA,
    EXTRACT,
    FIND,
    FNUMBER,
    GET,
    INCREMENT,
    JUSTIFY,
    LENGTH,
    NAME,
    ORDER,
    PIECE,
    QLENGTH,
    QSUBSCRIPT,
    QUERY,
    RANDOM,
    REPLACE,
    REVERSE,
    SELECT,
    STACK,
    TEXT,
    TRANSLATE,
    VIEW,

    // Z functions
    ZDATE,
    ZDATETIME,
    ZLENGTH,
    ZMESSAGE,
    ZPREVIOUS,
    ZSEARCH,
    ZTIME,
    ZWRITE,
};

// =============================================================================
// SYSTEM VARIABLE IDS (Intrinsic Special Variables)
// =============================================================================

pub const IsvId = enum(u16) {
    unknown = 0, // Parser sets id=0 for unrecognized ISVs
    DEVICE = 300,
    ECODE,
    ESTACK,
    ETRAP,
    HOROLOG,
    IO,
    JOB,
    KEY,
    PRINCIPAL,
    QUIT,
    REFERENCE,
    STACK,
    STORAGE,
    SYSTEM,
    TEST,
    TLEVEL,
    TRESTART,
    X,
    Y,

    // Z system variables
    ZA,
    ZB,
    ZEOF,
    ZERROR,
    ZGBLDIR,
    ZHOROLOG,
    ZIO,
    ZJOB,
    ZKEY,
    ZLEVEL,
    ZNSPACE,
    ZPOSITION,
    ZROUTINES,
    ZSTATUS,
    ZSYSTEM,
    ZTRAP,
    ZVERSION,
};

// =============================================================================
// STRUCTURED SYSTEM VARIABLE IDS (^$GLOBAL, ^$JOB, etc.)
// =============================================================================

pub const SsvnId = enum(u16) {
    unknown = 0, // Parser sets id=0 for unrecognized SSVNs
    GLOBAL = 400,
    JOB,
    LOCK,
    ROUTINE,
    SYSTEM,
    ZENVIRONMENT,
};

// =============================================================================
// CORE MATCHING FUNCTION
// =============================================================================

/// Case-insensitive prefix match with length bounds.
/// Returns true if `name` is a valid abbreviation of `full` (min to full.len chars).
/// - name.len < min → false (too short)
/// - name.len > full.len → false (too long, e.g., "INCREMENTTTINGSTUFF")
/// - name must be a case-insensitive prefix of full
inline fn match(name: []const u8, full: []const u8, min: usize) bool {
    if (name.len < min or name.len > full.len) return false;
    for (name, 0..) |c, i| {
        if (std.ascii.toUpper(c) != full[i]) return false;
    }
    return true;
}

/// Case-insensitive exact match (for aliases)
inline fn exact(name: []const u8, target: []const u8) bool {
    if (name.len != target.len) return false;
    for (name, target) |a, b| {
        if (std.ascii.toUpper(a) != std.ascii.toUpper(b)) return false;
    }
    return true;
}

// =============================================================================
// COMMAND LOOKUP
// =============================================================================

/// Validate command name with abbreviation support.
/// Returns CmdId if valid, null otherwise.
///
/// Examples:
///   "S", "SE", "SET" → .SET
///   "SETX", "SETTER" → null (too long)
///   "TC", "TCOMMIT" → .TCOMMIT
///   "H" → .HANG (HALT requires full word)
pub fn cmdAs(name: []const u8) ?CmdId {
    if (name.len == 0) return null;

    return switch (std.ascii.toUpper(name[0])) {
        'B' => if (match(name, "BREAK", 1)) .BREAK else null,
        'C' => if (match(name, "CLOSE", 1)) .CLOSE else null,
        'D' => if (match(name, "DO", 1)) .DO else null,
        'E' => if (match(name, "ELSE", 1)) .ELSE else null,
        'F' => if (match(name, "FOR", 1)) .FOR else null,
        'G' => if (match(name, "GOTO", 1)) .GOTO else null,
        'H' => {
            // HALT requires full word (min=4), HANG can be abbreviated (min=1)
            if (match(name, "HALT", 4)) return .HALT;
            if (match(name, "HANG", 1)) return .HANG;
            return null;
        },
        'I' => if (match(name, "IF", 1)) .IF else null,
        'J' => if (match(name, "JOB", 1)) .JOB else null,
        'K' => if (match(name, "KILL", 1)) .KILL else null,
        'L' => if (match(name, "LOCK", 1)) .LOCK else null,
        'M' => if (match(name, "MERGE", 1)) .MERGE else null,
        'N' => if (match(name, "NEW", 1)) .NEW else null,
        'O' => if (match(name, "OPEN", 1)) .OPEN else null,
        'Q' => if (match(name, "QUIT", 1)) .QUIT else null,
        'R' => if (match(name, "READ", 1)) .READ else null,
        'S' => if (match(name, "SET", 1)) .SET else null,
        'T' => {
            // TC[OMMIT], TRE[START], TRO[LLBACK], TS[TART]
            if (name.len < 2) return null;
            return switch (std.ascii.toUpper(name[1])) {
                'C' => if (match(name, "TCOMMIT", 2)) .TCOMMIT else null,
                'R' => {
                    // TRE vs TRO - need third char
                    if (name.len < 3) return null;
                    return switch (std.ascii.toUpper(name[2])) {
                        'E' => if (match(name, "TRESTART", 3)) .TRESTART else null,
                        'O' => if (match(name, "TROLLBACK", 3)) .TROLLBACK else null,
                        else => null,
                    };
                },
                'S' => if (match(name, "TSTART", 2)) .TSTART else null,
                else => null,
            };
        },
        'U' => if (match(name, "USE", 1)) .USE else null,
        'V' => if (match(name, "VIEW", 1)) .VIEW else null,
        'W' => if (match(name, "WRITE", 1)) .WRITE else null,
        'X' => if (match(name, "XECUTE", 1)) .XECUTE else null,
        'Z' => {
            // ZB[REAK], ZHALT (full), ZK[ILL], ZW[RITE]
            if (name.len < 2) return null;
            return switch (std.ascii.toUpper(name[1])) {
                'B' => if (match(name, "ZBREAK", 2)) .ZBREAK else null,
                'H' => if (match(name, "ZHALT", 5)) .ZHALT else null,
                'K' => if (match(name, "ZKILL", 2)) .ZKILL else null,
                'W' => if (match(name, "ZWRITE", 2)) .ZWRITE else null,
                else => null,
            };
        },
        else => null,
    };
}

// =============================================================================
// FUNCTION LOOKUP
// =============================================================================

/// Validate intrinsic function name (WITHOUT $ prefix - grammar handles $ separately).
/// Returns FnId if valid, null otherwise.
/// Also handles non-prefix aliases like INCR → INCREMENT.
///
/// Examples:
///   "P", "PIE", "PIECE" → .PIECE
///   "PIECEX" → null (too long)
///   "INCR" → .INCREMENT (alias)
///   "F" → .FIND, "FN" → .FNUMBER (min length disambiguation)
pub fn fnAs(name: []const u8) ?FnId {
    if (name.len == 0) return null;

    return switch (std.ascii.toUpper(name[0])) {
        'A' => if (match(name, "ASCII", 1)) .ASCII else null,
        'C' => if (match(name, "CHAR", 1)) .CHAR else null,
        'D' => if (match(name, "DATA", 1)) .DATA else null,
        'E' => if (match(name, "EXTRACT", 1)) .EXTRACT else null,
        'F' => {
            // FN[UMBER] min=2, F[IND] min=1
            if (match(name, "FNUMBER", 2)) return .FNUMBER;
            if (match(name, "FIND", 1)) return .FIND;
            return null;
        },
        'G' => if (match(name, "GET", 1)) .GET else null,
        'I' => {
            // I[NCREMENT] min=1, plus INCR alias
            if (match(name, "INCREMENT", 1)) return .INCREMENT;
            if (exact(name, "INCR")) return .INCREMENT; // alias
            return null;
        },
        'J' => if (match(name, "JUSTIFY", 1)) .JUSTIFY else null,
        'L' => if (match(name, "LENGTH", 1)) .LENGTH else null,
        'N' => if (match(name, "NAME", 2)) .NAME else null, // NA[ME]
        'O' => if (match(name, "ORDER", 1)) .ORDER else null,
        'P' => if (match(name, "PIECE", 1)) .PIECE else null,
        'Q' => {
            // QL[ENGTH] min=2, QS[UBSCRIPT] min=2, Q[UERY] min=1
            if (name.len < 2) {
                return if (match(name, "QUERY", 1)) .QUERY else null;
            }
            return switch (std.ascii.toUpper(name[1])) {
                'L' => if (match(name, "QLENGTH", 2)) .QLENGTH else null,
                'S' => if (match(name, "QSUBSCRIPT", 2)) .QSUBSCRIPT else null,
                else => if (match(name, "QUERY", 1)) .QUERY else null,
            };
        },
        'R' => {
            // RE[VERSE] min=2, REPLACE min=7, R[ANDOM] min=1
            if (match(name, "REVERSE", 2)) return .REVERSE;
            if (match(name, "REPLACE", 7)) return .REPLACE;
            if (match(name, "RANDOM", 1)) return .RANDOM;
            return null;
        },
        'S' => {
            // ST[ACK] min=2, S[ELECT] min=1
            if (match(name, "STACK", 2)) return .STACK;
            if (match(name, "SELECT", 1)) return .SELECT;
            return null;
        },
        'T' => {
            // TR[ANSLATE] min=2, T[EXT] min=1
            if (match(name, "TRANSLATE", 2)) return .TRANSLATE;
            if (match(name, "TEXT", 1)) return .TEXT;
            return null;
        },
        'V' => if (match(name, "VIEW", 1)) .VIEW else null,
        'Z' => {
            if (name.len < 2) return null;
            return switch (std.ascii.toUpper(name[1])) {
                'D' => {
                    // ZDATETIME min=9, ZD[ATE] min=2
                    if (match(name, "ZDATETIME", 9)) return .ZDATETIME;
                    if (match(name, "ZDATE", 2)) return .ZDATE;
                    return null;
                },
                'I' => {
                    // ZINCR, ZINCREMENT → INCREMENT aliases
                    if (exact(name, "ZINCR")) return .INCREMENT;
                    if (exact(name, "ZINCREMENT")) return .INCREMENT;
                    return null;
                },
                'L' => if (match(name, "ZLENGTH", 2)) .ZLENGTH else null,
                'M' => if (match(name, "ZMESSAGE", 2)) .ZMESSAGE else null,
                'P' => if (match(name, "ZPREVIOUS", 2)) .ZPREVIOUS else null,
                'S' => if (match(name, "ZSEARCH", 7)) .ZSEARCH else null,
                'T' => {
                    // ZTIME min=5, ZT alias
                    if (match(name, "ZTIME", 5)) return .ZTIME;
                    if (exact(name, "ZT")) return .ZTIME; // alias
                    return null;
                },
                'W' => if (match(name, "ZWRITE", 6)) .ZWRITE else null,
                else => null,
            };
        },
        else => null,
    };
}

// =============================================================================
// SYSTEM VARIABLE LOOKUP
// =============================================================================

/// Validate system variable name (WITH $ prefix).
/// Returns IsvId if valid, null otherwise.
///
/// Examples:
///   "$H", "$HOROLOG" → .HOROLOG
///   "$T", "$TEST" → .TEST
///   "$X", "$Y" → .X, .Y
pub fn isvAs(name: []const u8) ?IsvId {
    if (name.len == 0) return null;

    return switch (std.ascii.toUpper(name[0])) {
        'D' => if (match(name, "DEVICE", 2)) .DEVICE else null, // DE[VICE] - $D is $DATA()
        'E' => {
            // EC[ODE], ES[TACK], ET[RAP]
            if (name.len < 2) return null;
            return switch (std.ascii.toUpper(name[1])) {
                'C' => if (match(name, "ECODE", 2)) .ECODE else null,
                'S' => if (match(name, "ESTACK", 2)) .ESTACK else null,
                'T' => if (match(name, "ETRAP", 2)) .ETRAP else null,
                else => null,
            };
        },
        'H' => if (match(name, "HOROLOG", 1)) .HOROLOG else null,
        'I' => if (match(name, "IO", 2)) .IO else null, // min=2 to avoid $I function
        'J' => if (match(name, "JOB", 1)) .JOB else null,
        'K' => if (match(name, "KEY", 1)) .KEY else null,
        'P' => if (match(name, "PRINCIPAL", 2)) .PRINCIPAL else null, // PR[INCIPAL] - $P is $PIECE()
        'Q' => if (match(name, "QUIT", 2)) .QUIT else null, // QU[IT] - $Q is $QUERY()
        'R' => if (match(name, "REFERENCE", 2)) .REFERENCE else null, // RE[FERENCE] - $R is $RANDOM()
        'S' => {
            // ST[ACK], S[TORAGE], SY[STEM]
            if (name.len < 2) {
                return if (match(name, "STORAGE", 1)) .STORAGE else null;
            }
            return switch (std.ascii.toUpper(name[1])) {
                'T' => if (match(name, "STACK", 2)) .STACK else null,
                'Y' => if (match(name, "SYSTEM", 2)) .SYSTEM else null,
                else => if (match(name, "STORAGE", 1)) .STORAGE else null,
            };
        },
        'T' => {
            // T[EST], TL[EVEL], TR[ESTART]
            if (name.len < 2) {
                return if (match(name, "TEST", 1)) .TEST else null;
            }
            return switch (std.ascii.toUpper(name[1])) {
                'L' => if (match(name, "TLEVEL", 2)) .TLEVEL else null,
                'R' => if (match(name, "TRESTART", 2)) .TRESTART else null,
                else => if (match(name, "TEST", 1)) .TEST else null,
            };
        },
        'X' => if (match(name, "X", 1)) .X else null,
        'Y' => if (match(name, "Y", 1)) .Y else null,
        'Z' => {
            if (name.len < 2) return null;
            return switch (std.ascii.toUpper(name[1])) {
                'A' => if (match(name, "ZA", 2)) .ZA else null,
                'B' => if (match(name, "ZB", 2)) .ZB else null,
                'E' => {
                    // ZEO[F], ZE[RROR]
                    if (name.len >= 3 and std.ascii.toUpper(name[2]) == 'O') {
                        return if (match(name, "ZEOF", 3)) .ZEOF else null;
                    }
                    return if (match(name, "ZERROR", 2)) .ZERROR else null;
                },
                'G' => if (match(name, "ZGBLDIR", 2)) .ZGBLDIR else null,
                'H' => if (match(name, "ZHOROLOG", 2)) .ZHOROLOG else null,
                'I' => if (match(name, "ZIO", 3)) .ZIO else null,
                'J' => if (match(name, "ZJOB", 2)) .ZJOB else null,
                'K' => if (match(name, "ZKEY", 4)) .ZKEY else null,
                'L' => if (match(name, "ZLEVEL", 2)) .ZLEVEL else null,
                'N' => if (match(name, "ZNSPACE", 3)) .ZNSPACE else null,
                'P' => if (match(name, "ZPOSITION", 4)) .ZPOSITION else null,
                'R' => if (match(name, "ZROUTINES", 3)) .ZROUTINES else null,
                'S' => {
                    // ZS[TATUS], ZSY[STEM]
                    if (name.len >= 3 and std.ascii.toUpper(name[2]) == 'Y') {
                        return if (match(name, "ZSYSTEM", 3)) .ZSYSTEM else null;
                    }
                    return if (match(name, "ZSTATUS", 2)) .ZSTATUS else null;
                },
                'T' => if (match(name, "ZTRAP", 2)) .ZTRAP else null,
                'V' => if (match(name, "ZVERSION", 2)) .ZVERSION else null,
                else => null,
            };
        },
        else => null,
    };
}

// =============================================================================
// STRUCTURED SYSTEM VARIABLE LOOKUP
// =============================================================================

/// Validate SSVN name (WITHOUT ^$ prefix - just the name part).
/// Returns SsvnId if valid, null otherwise.
///
/// Examples:
///   "G", "GLOBAL" → .GLOBAL
///   "J", "JOB" → .JOB
///   "SYS", "SYSTEM" → .SYSTEM
pub fn ssvnAs(name: []const u8) ?SsvnId {
    if (name.len == 0) return null;

    return switch (std.ascii.toUpper(name[0])) {
        'G' => if (match(name, "GLOBAL", 1)) .GLOBAL else null,
        'J' => if (match(name, "JOB", 1)) .JOB else null,
        'L' => if (match(name, "LOCK", 1)) .LOCK else null,
        'R' => if (match(name, "ROUTINE", 1)) .ROUTINE else null,
        'S' => if (match(name, "SYSTEM", 3)) .SYSTEM else null, // SYS[TEM]
        'Z' => if (match(name, "ZENVIRONMENT", 5)) .ZENVIRONMENT else null, // ZENV[IRONMENT]
        else => null,
    };
}

// =============================================================================
// TESTS
// =============================================================================

test "cmdAs - basic commands" {
    // Full names
    try std.testing.expectEqual(CmdId.SET, cmdAs("SET").?);
    try std.testing.expectEqual(CmdId.WRITE, cmdAs("WRITE").?);
    try std.testing.expectEqual(CmdId.QUIT, cmdAs("QUIT").?);

    // Minimum abbreviations
    try std.testing.expectEqual(CmdId.SET, cmdAs("S").?);
    try std.testing.expectEqual(CmdId.WRITE, cmdAs("W").?);
    try std.testing.expectEqual(CmdId.QUIT, cmdAs("Q").?);

    // Intermediate lengths
    try std.testing.expectEqual(CmdId.SET, cmdAs("SE").?);
    try std.testing.expectEqual(CmdId.MERGE, cmdAs("MER").?);

    // Case insensitive
    try std.testing.expectEqual(CmdId.SET, cmdAs("set").?);
    try std.testing.expectEqual(CmdId.SET, cmdAs("Set").?);
}

test "cmdAs - too long rejected" {
    try std.testing.expect(cmdAs("SETX") == null);
    try std.testing.expect(cmdAs("SETTER") == null);
    try std.testing.expect(cmdAs("MERGER") == null);
    try std.testing.expect(cmdAs("MERCOLA") == null);
}

test "cmdAs - HALT vs HANG" {
    // HALT requires full word (min=4)
    try std.testing.expectEqual(CmdId.HALT, cmdAs("HALT").?);
    try std.testing.expect(cmdAs("HAL") == null); // not HALT, not HANG

    // HANG can be abbreviated (min=1)
    try std.testing.expectEqual(CmdId.HANG, cmdAs("H").?);
    try std.testing.expectEqual(CmdId.HANG, cmdAs("HA").?);
    try std.testing.expectEqual(CmdId.HANG, cmdAs("HAN").?);
    try std.testing.expectEqual(CmdId.HANG, cmdAs("HANG").?);
}

test "cmdAs - T commands" {
    try std.testing.expectEqual(CmdId.TCOMMIT, cmdAs("TC").?);
    try std.testing.expectEqual(CmdId.TCOMMIT, cmdAs("TCOMMIT").?);
    try std.testing.expectEqual(CmdId.TSTART, cmdAs("TS").?);
    try std.testing.expectEqual(CmdId.TRESTART, cmdAs("TRE").?);
    try std.testing.expectEqual(CmdId.TROLLBACK, cmdAs("TRO").?);
    try std.testing.expect(cmdAs("T") == null);
    try std.testing.expect(cmdAs("TR") == null);
}

test "cmdAs - Z commands" {
    try std.testing.expectEqual(CmdId.ZBREAK, cmdAs("ZB").?);
    try std.testing.expectEqual(CmdId.ZKILL, cmdAs("ZK").?);
    try std.testing.expectEqual(CmdId.ZWRITE, cmdAs("ZW").?);
    try std.testing.expectEqual(CmdId.ZHALT, cmdAs("ZHALT").?);
    try std.testing.expect(cmdAs("Z") == null);
    try std.testing.expect(cmdAs("ZH") == null); // ZHALT requires full word
}

test "fnAs - basic functions" {
    try std.testing.expectEqual(FnId.PIECE, fnAs("PIECE").?);
    try std.testing.expectEqual(FnId.PIECE, fnAs("P").?);
    try std.testing.expectEqual(FnId.LENGTH, fnAs("LENGTH").?);
    try std.testing.expectEqual(FnId.LENGTH, fnAs("L").?);
}

test "fnAs - too long rejected" {
    try std.testing.expect(fnAs("PIECEX") == null);
    try std.testing.expect(fnAs("PIECEEE") == null);
    try std.testing.expect(fnAs("INCREMENTT") == null);
    try std.testing.expect(fnAs("INCREMENTTTINGSTUFF") == null);
}

test "fnAs - disambiguation by min length" {
    // F = FIND (min=1), FN = FNUMBER (min=2)
    try std.testing.expectEqual(FnId.FIND, fnAs("F").?);
    try std.testing.expectEqual(FnId.FIND, fnAs("FI").?);
    try std.testing.expectEqual(FnId.FNUMBER, fnAs("FN").?);
    try std.testing.expectEqual(FnId.FNUMBER, fnAs("FNU").?);

    // L[ENGTH] min=1
    try std.testing.expectEqual(FnId.LENGTH, fnAs("L").?);
    try std.testing.expectEqual(FnId.LENGTH, fnAs("LE").?);
    try std.testing.expectEqual(FnId.LENGTH, fnAs("LEN").?);
    try std.testing.expectEqual(FnId.LENGTH, fnAs("LENGTH").?);
}

test "fnAs - aliases" {
    // INCR → INCREMENT
    try std.testing.expectEqual(FnId.INCREMENT, fnAs("INCR").?);
    try std.testing.expectEqual(FnId.INCREMENT, fnAs("I").?);
    try std.testing.expectEqual(FnId.INCREMENT, fnAs("INCREMENT").?);

    // ZINCR, ZINCREMENT → INCREMENT
    try std.testing.expectEqual(FnId.INCREMENT, fnAs("ZINCR").?);
    try std.testing.expectEqual(FnId.INCREMENT, fnAs("ZINCREMENT").?);

    // ZT → ZTIME
    try std.testing.expectEqual(FnId.ZTIME, fnAs("ZT").?);
    try std.testing.expectEqual(FnId.ZTIME, fnAs("ZTIME").?);
}

test "fnAs - empty rejected" {
    try std.testing.expect(fnAs("") == null);
}

test "isvAs - basic ISVs" {
    // isvAs expects name WITHOUT $ prefix (grammar tokenizes $ separately)
    try std.testing.expectEqual(IsvId.HOROLOG, isvAs("H").?);
    try std.testing.expectEqual(IsvId.HOROLOG, isvAs("HOROLOG").?);
    try std.testing.expectEqual(IsvId.TEST, isvAs("T").?);
    try std.testing.expectEqual(IsvId.TEST, isvAs("TEST").?);
    try std.testing.expectEqual(IsvId.X, isvAs("X").?);
    try std.testing.expectEqual(IsvId.Y, isvAs("Y").?);
}

test "isvAs - IO requires min=2" {
    try std.testing.expectEqual(IsvId.IO, isvAs("IO").?);
    try std.testing.expect(isvAs("I") == null); // too short, conflicts with $I function
}

test "isvAs - Z ISVs" {
    try std.testing.expectEqual(IsvId.ZERROR, isvAs("ZE").?);
    try std.testing.expectEqual(IsvId.ZEOF, isvAs("ZEOF").?);
    try std.testing.expectEqual(IsvId.ZSTATUS, isvAs("ZS").?);
    try std.testing.expectEqual(IsvId.ZSYSTEM, isvAs("ZSY").?);
}

test "ssvnAs - basic SSVNs" {
    try std.testing.expectEqual(SsvnId.GLOBAL, ssvnAs("G").?);
    try std.testing.expectEqual(SsvnId.GLOBAL, ssvnAs("GLOBAL").?);
    try std.testing.expectEqual(SsvnId.JOB, ssvnAs("J").?);
    try std.testing.expectEqual(SsvnId.LOCK, ssvnAs("L").?);
    try std.testing.expectEqual(SsvnId.ROUTINE, ssvnAs("R").?);
    try std.testing.expectEqual(SsvnId.SYSTEM, ssvnAs("SYS").?);
    try std.testing.expectEqual(SsvnId.SYSTEM, ssvnAs("SYSTEM").?);
    try std.testing.expect(ssvnAs("S") == null); // too short for SYSTEM
}
