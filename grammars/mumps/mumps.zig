//! em MUMPS language module for the generated parser (`@lang = "mumps"`):
//!
//! - the Lexer wrapper (the escape hatch for what mumps.grammar can't say)
//! - the keyword IDs and lookups the parser generates from mumps.grammar's
//!   `@keywords`: CmdId/cmdAs, FnId/fnAs, IsvId/isvAs, SsvnId/ssvnAs (the
//!   grammar's `@as` lookups), re-exported for the rest of em
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
// KEYWORDS (the grammar's `@as` lookups)
// =============================================================================
//
// mumps.grammar's `@keywords` lists every command, function, special variable
// and structured system variable name as the standard writes it, with its
// abbreviations; Nexus generates each group's ID enum and lookup into the
// parser, and rejects two entries that accept one word. Each lookup takes the
// name in any case; a function's or special variable's name follows `$` (the
// grammar lexes `$` separately), a structured system variable's `^$`.

pub const CmdId = parser.CmdId;
pub const cmdAs = parser.cmdAs;
pub const FnId = parser.FnId;
pub const fnAs = parser.fnAs;
pub const IsvId = parser.IsvId;
pub const isvAs = parser.isvAs;
pub const SsvnId = parser.SsvnId;
pub const ssvnAs = parser.ssvnAs;

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
    try t.expectEqual(CmdId.ZSAVE, cmdAs("zs").?);
    try t.expectEqual(CmdId.ZSAVE, cmdAs("ZSAV").?);
    try t.expectEqual(CmdId.ZSAVE, cmdAs("ZSAVE").?);
    try t.expectEqual(CmdId.ZSHOW, cmdAs("ZSH").?);
    try t.expectEqual(CmdId.ZINSERT, cmdAs("ZI").?);
    try t.expectEqual(CmdId.ZREMOVE, cmdAs("zr").?);
    try t.expectEqual(CmdId.ZPRINT, cmdAs("ZP").?);
    try t.expectEqual(FnId.ZPREVIOUS, fnAs("ZP").?);
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
    try t.expectEqual(IsvId.ZDIRECTORY, isvAs("zdir").?);
    try t.expectEqual(@as(?IsvId, null), isvAs("ZD"));
    try t.expectEqual(IsvId.ZTIMESTAMP, isvAs("zts").?);
    try t.expectEqual(IsvId.ZTIMEZONE, isvAs("ZTZ").?);
    try t.expectEqual(IsvId.ZTRAP, isvAs("ZT").?);
    try t.expectEqual(IsvId.NAMESPACE, isvAs("namespace").?);
    try t.expectEqual(@as(?IsvId, null), isvAs("NAMESP"));
    try t.expectEqual(FnId.ZF, fnAs("zf").?);
    try t.expectEqual(SsvnId.SYSTEM, ssvnAs("SYS").?);
    // Too short, too long, not a prefix, empty.
    for ([_][]const u8{ "", "T", "TR", "HAL", "ZH", "ZSV", "ZSAVES", "SETX", "MERCOLA" }) |w| try t.expect(cmdAs(w) == null);
    for ([_][]const u8{ "", "NX", "REP", "ZTI", "PIECEX", "INCREMENTT" }) |w| try t.expect(fnAs(w) == null);
    for ([_][]const u8{ "", "E", "STO", "STORAGES", "ZK" }) |w| try t.expect(isvAs(w) == null);
    for ([_][]const u8{ "", "S", "ZENV" }) |w| try t.expect(ssvnAs(w) == null);
}
