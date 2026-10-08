//! em MUMPS language module for the generated parser (`@lang = "mumps"`):
//!
//! - the Lexer wrapper (the escape hatch for what mumps.grammar can't say)
//! - the keyword IDs and abbreviation tables: CmdId/cmdAs, FnId/fnAs,
//!   SvId/svAs, IsvId/isvAs, SsvnId/ssvnAs (the grammar's `@as` lookups)
//! - the keywords VIEW takes (viewKeywords)
//!
//! The tree's node kinds (parser.Tag) come from mumps.grammar's @schema.

const std = @import("std");
const parser = @import("parser.zig");
const BaseLexer = parser.BaseLexer;
const Token = parser.Token;

// =============================================================================
// LEXER WRAPPER
// =============================================================================
//
// mumps.grammar declares every token shape, the pattern-mode entry and exit
// rules, INDENT, SPACES and zdigits. The generated BaseLexer does all the
// scanning; this wrapper adds the one thing a lexer rule cannot say: the end
// of input ends a pattern (`X?1N` at EOF yields PATEND, then EOF), since no
// rule can match at the end of input.

pub const Lexer = struct {
    base: BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = BaseLexer.init(source) };
    }

    pub fn next(self: *Lexer) Token {
        var tok = self.base.next();
        if (tok.cat == .eof and self.base.pat != 0) {
            self.base.pat = 0;
            tok.cat = .patend;
        }
        return tok;
    }
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
    ZSYSTEM,
    ZWRITE,
};

// =============================================================================
// FUNCTION IDS
// =============================================================================

pub const FnId = enum(u16) {
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
    ZCONVERT,
    ZDATE,
    ZDATEH,
    ZDATETIME,
    ZLENGTH,
    ZMESSAGE,
    ZPREVIOUS,
    ZSEARCH,
    ZTIME,
    ZWRITE,

    // Obsolete: $ORDER's predecessor in the 1977-1990 standards
    NEXT,
};

// =============================================================================
// SYSTEM VARIABLE IDS (Intrinsic Special Variables)
// =============================================================================

pub const IsvId = enum(u16) {
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
    ZUT,
    ZVERSION,
};

/// The special variables SET can assign, for the grammar's SV terminal
/// (`S $X=0`, `S ($X,$Y)=0`, `S $ZE=""`); each id is the variable's IsvId.
pub const SvId = enum(u16) {
    ECODE = @backingInt(IsvId.ECODE),
    ETRAP = @backingInt(IsvId.ETRAP),
    X = @backingInt(IsvId.X),
    Y = @backingInt(IsvId.Y),
    ZERROR = @backingInt(IsvId.ZERROR),
};

// =============================================================================
// STRUCTURED SYSTEM VARIABLE IDS (^$GLOBAL, ^$JOB, etc.)
// =============================================================================

pub const SsvnId = enum(u16) {
    GLOBAL = 400,
    JOB,
    LOCK,
    ROUTINE,
    SYSTEM,
    ZENVIRONMENT,
};

// =============================================================================
// KEYWORD TABLES (the grammar's `@as` lookups)
// =============================================================================
//
// Each keyword is written as the standard writes it: the bracketed part is
// optional, so `H[ANG]` is H, HA, HAN or HANG, in any case, and `HALT` must be
// written in full. `ALIAS=NAME` makes the exact word ALIAS another spelling of
// NAME. No two entries accept the same word (checked at compile time), so the
// order of a table does not matter.

pub fn cmdAs(name: []const u8) ?CmdId {
    return lookup(CmdId, &commands, name);
}

/// The name follows `$` (the grammar lexes `$` separately), as for isvAs.
pub fn fnAs(name: []const u8) ?FnId {
    return lookup(FnId, &functions, name);
}

pub fn isvAs(name: []const u8) ?IsvId {
    return lookup(IsvId, &variables, name);
}

/// A special variable SET can assign; the name follows `$`.
pub fn svAs(name: []const u8) ?SvId {
    return std.enums.fromInt(SvId, @backingInt(isvAs(name) orelse return null));
}

/// The name follows `^$`.
pub fn ssvnAs(name: []const u8) ?SsvnId {
    return lookup(SsvnId, &structured, name);
}

/// The keywords VIEW takes, none with parameters, in any case. em checks
/// no characters for validity, so "BADCHAR" (check them) and "NOBADCHAR"
/// (do not) both do nothing. Any other VIEW is an error naming it
/// (docs/user/FEATURES.md).
pub const viewKeywords = [_][]const u8{ "BADCHAR", "NOBADCHAR" };

/// Whether `name` is one of viewKeywords.
pub fn isViewKeyword(name: []const u8) bool {
    for (viewKeywords) |k| if (std.ascii.eqlIgnoreCase(k, name)) return true;
    return false;
}

const commands = keywords(CmdId, &.{
    "B[REAK]",   "C[LOSE]",    "D[O]",        "E[LSE]",   "F[OR]",   "G[OTO]",
    "HALT",      "H[ANG]",     "I[F]",        "J[OB]",    "K[ILL]",  "L[OCK]",
    "M[ERGE]",   "N[EW]",      "O[PEN]",      "Q[UIT]",   "R[EAD]",  "S[ET]",
    "TC[OMMIT]", "TRE[START]", "TRO[LLBACK]", "TS[TART]", "U[SE]",   "V[IEW]",
    "W[RITE]",   "X[ECUTE]",   "ZB[REAK]",    "ZHALT",    "ZK[ILL]", "ZSY[STEM]",
    "ZW[RITE]",
});

const functions = keywords(FnId, &.{
    "A[SCII]",              "C[HAR]",      "D[ATA]",     "E[XTRACT]",    "F[IND]",    "FN[UMBER]",
    "G[ET]",                "I[NCREMENT]", "J[USTIFY]",  "L[ENGTH]",     "NA[ME]",    "N[EXT]",
    "O[RDER]",              "P[IECE]",     "QL[ENGTH]",  "QS[UBSCRIPT]", "Q[UERY]",   "R[ANDOM]",
    "RE[VERSE]",            "REPLACE",     "S[ELECT]",   "ST[ACK]",      "T[EXT]",    "TR[ANSLATE]",
    "V[IEW]",               "ZCO[NVERT]",  "ZD[ATE]",    "ZDATEH",       "ZDATETIME", "ZINCR=INCREMENT",
    "ZINCREMENT=INCREMENT", "ZL[ENGTH]",   "ZM[ESSAGE]", "ZP[REVIOUS]",  "ZSEARCH",   "ZTIME",
    "ZT=ZTIME",             "ZWRITE",
});

// $STORAGE is $S or the full name: $ST... is $STACK.
const variables = keywords(IsvId, &.{
    "D[EVICE]",  "EC[ODE]",     "ES[TACK]",    "ET[RAP]",   "H[OROLOG]",   "I[O]",
    "J[OB]",     "K[EY]",       "P[RINCIPAL]", "Q[UIT]",    "R[EFERENCE]", "ST[ACK]",
    "S=STORAGE", "STORAGE",     "SY[STEM]",    "T[EST]",    "TL[EVEL]",    "TR[ESTART]",
    "X",         "Y",           "ZA",          "ZB",        "ZEO[F]",      "ZE[RROR]",
    "ZG[BLDIR]", "ZH[OROLOG]",  "ZIO",         "ZJ[OB]",    "ZKEY",        "ZL[EVEL]",
    "ZNS[PACE]", "ZPOS[ITION]", "ZRO[UTINES]", "ZS[TATUS]", "ZSY[STEM]",   "ZT[RAP]",
    "ZUT",       "ZV[ERSION]",
});

const structured = keywords(SsvnId, &.{
    "G[LOBAL]", "J[OB]", "L[OCK]", "R[OUTINE]", "SYS[TEM]", "ZENVI[RONMENT]",
});

fn Keyword(comptime Id: type) type {
    return struct { name: []const u8, min: usize, id: Id };
}

/// A table's entries grouped by initial letter.
fn keywords(comptime Id: type, comptime specs: []const []const u8) [26][]const Keyword(Id) {
    @setEvalBranchQuota(100_000);
    var entries: [specs.len]Keyword(Id) = undefined;
    for (specs, &entries) |spec, *e| {
        const eq = std.mem.findScalar(u8, spec, '=');
        const word = spec[0 .. eq orelse spec.len];
        const open = std.mem.findScalar(u8, word, '[') orelse word.len;
        const name = word[0..open] ++ (if (open < word.len) word[open + 1 .. word.len - 1] else "");
        e.* = .{ .name = name, .min = open, .id = @field(Id, if (eq) |i| spec[i + 1 ..] else name) };
    }
    for (entries, 0..) |a, i| for (entries[i + 1 ..]) |b| {
        // Two entries overlap when both accept the shortest word both allow.
        const n = @max(a.min, b.min);
        if (n <= @min(a.name.len, b.name.len) and std.mem.eql(u8, a.name[0..n], b.name[0..n]))
            @compileError(a.name ++ " and " ++ b.name ++ " both accept " ++ a.name[0..n]);
    };
    var byLetter: [26][]const Keyword(Id) = @splat(&.{});
    for (entries) |e| byLetter[e.name[0] - 'A'] = byLetter[e.name[0] - 'A'] ++ .{e};
    const result = byLetter;
    return result;
}

fn lookup(comptime Id: type, table: *const [26][]const Keyword(Id), name: []const u8) ?Id {
    if (name.len == 0) return null;
    const first = std.ascii.toUpper(name[0]);
    if (first < 'A' or first > 'Z') return null;
    entry: for (table[first - 'A']) |e| {
        if (name.len < e.min or name.len > e.name.len) continue;
        for (name[1..], e.name[1..name.len]) |c, k| {
            if (std.ascii.toUpper(c) != k) continue :entry;
        }
        return e.id;
    }
    return null;
}

// =============================================================================
// TESTS
// =============================================================================

test "keyword abbreviations" {
    const t = std.testing;
    try t.expectEqual(CmdId.SET, cmdAs("s").?);
    try t.expectEqual(CmdId.MERGE, cmdAs("Mer").?);
    try t.expectEqual(CmdId.HANG, cmdAs("HAN").?);
    try t.expectEqual(CmdId.HALT, cmdAs("HALT").?);
    try t.expectEqual(CmdId.TROLLBACK, cmdAs("TRO").?);
    try t.expectEqual(CmdId.ZSYSTEM, cmdAs("zsy").?);
    try t.expectEqual(CmdId.ZSYSTEM, cmdAs("ZSYSTEM").?);
    try t.expectEqual(IsvId.ZSYSTEM, isvAs("ZSY").?);
    try t.expectEqual(FnId.FIND, fnAs("F").?);
    try t.expectEqual(FnId.FNUMBER, fnAs("FN").?);
    try t.expectEqual(FnId.INCREMENT, fnAs("zincr").?);
    try t.expectEqual(FnId.NEXT, fnAs("N").?);
    try t.expectEqual(FnId.NAME, fnAs("NA").?);
    try t.expectEqual(FnId.ZTIME, fnAs("ZT").?);
    try t.expectEqual(IsvId.STORAGE, isvAs("S").?);
    try t.expectEqual(IsvId.STORAGE, isvAs("storage").?);
    try t.expectEqual(IsvId.STACK, isvAs("ST").?);
    try t.expectEqual(IsvId.DEVICE, isvAs("D").?);
    try t.expectEqual(IsvId.IO, isvAs("I").?);
    try t.expectEqual(IsvId.REFERENCE, isvAs("R").?);
    try t.expectEqual(IsvId.ZEOF, isvAs("ZEO").?);
    try t.expectEqual(IsvId.ZERROR, isvAs("ZE").?);
    try t.expectEqual(SsvnId.SYSTEM, ssvnAs("SYS").?);
    // Too short, too long, not a prefix, empty.
    for ([_][]const u8{ "", "T", "TR", "HAL", "ZH", "ZS", "SETX", "MERCOLA" }) |w| try t.expect(cmdAs(w) == null);
    for ([_][]const u8{ "", "NX", "REP", "ZTI", "PIECEX", "INCREMENTT" }) |w| try t.expect(fnAs(w) == null);
    for ([_][]const u8{ "", "E", "STO", "STORAGES", "ZK" }) |w| try t.expect(isvAs(w) == null);
    for ([_][]const u8{ "", "S", "ZENV" }) |w| try t.expect(ssvnAs(w) == null);
}

test "settable special variables" {
    const t = std.testing;
    try t.expectEqual(SvId.X, svAs("x").?);
    try t.expectEqual(SvId.ECODE, svAs("EC").?);
    try t.expectEqual(SvId.ETRAP, svAs("etrap").?);
    try t.expectEqual(SvId.ZERROR, svAs("ZE").?);
    try t.expectEqual(SvId.ZERROR, svAs("zerror").?);
    try t.expectEqual(@backingInt(IsvId.Y), @backingInt(svAs("Y").?));
    // Special variables SET may not assign, and non-names.
    for ([_][]const u8{ "", "H", "J", "T", "ZT", "ZTRAP", "ZS", "ZSTATUS", "ZA", "ZB", "E" }) |w| try t.expect(svAs(w) == null);
}
