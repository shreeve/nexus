//! The lang module of keywords.grammar: no wrappers, only tests of the
//! lookups `@keywords` generates (`CmdId`/`cmdAs`, `FnId`/`fnAs`,
//! `WordId`/`wordAs`), which a lang wrapper may call too.

const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");
const CmdId = parser.CmdId;
const FnId = parser.FnId;
const WordId = parser.WordId;

/// A lang module may re-export a group's generated table (declaring its
/// own would be a compile error of the parser).
pub const wordAs = parser.wordAs;

test "ids count from the base, in the order the terminals are written" {
    try testing.expectEqual(100, @backingInt(CmdId.SET));
    try testing.expectEqual(103, @backingInt(CmdId.HALT));
    try testing.expectEqual(107, @backingInt(CmdId.TRESTART));
    try testing.expectEqual(8, std.enums.values(CmdId).len);
    try testing.expectEqual(200, @backingInt(FnId.LENGTH));
    try testing.expectEqual(1, @backingInt(WordId.BEGIN_KW));
    try testing.expectEqual(3, @backingInt(WordId.NIL_P));
}

test "an abbreviation accepts every prefix at least as long as its head" {
    try testing.expectEqual(CmdId.SET, parser.cmdAs("s").?);
    try testing.expectEqual(CmdId.SET, parser.cmdAs("se").?);
    try testing.expectEqual(CmdId.SET, parser.cmdAs("set").?);
    try testing.expectEqual(null, parser.cmdAs("sets"));
    try testing.expectEqual(CmdId.TROLLBACK, parser.cmdAs("tro").?);
    try testing.expectEqual(CmdId.TROLLBACK, parser.cmdAs("TROLLBACK").?);
    try testing.expectEqual(CmdId.TRESTART, parser.cmdAs("tre").?);
    try testing.expectEqual(null, parser.cmdAs("tr"));
    try testing.expectEqual(null, parser.cmdAs("t"));
    try testing.expectEqual(null, parser.cmdAs("trollbackx"));
}

test "an exact word accepts only itself" {
    try testing.expectEqual(CmdId.HALT, parser.cmdAs("halt").?);
    try testing.expectEqual(CmdId.HANG, parser.cmdAs("ha").?);
    try testing.expectEqual(CmdId.HANG, parser.cmdAs("han").?);
    try testing.expectEqual(null, parser.cmdAs("hal"));
    try testing.expectEqual(FnId.ZDATEH, parser.fnAs("zdateh").?);
    try testing.expectEqual(FnId.ZDATE, parser.fnAs("zdat").?);
    try testing.expectEqual(null, parser.fnAs("zdatehx"));
}

test "an alias spells its target" {
    try testing.expectEqual(CmdId.ZWRITE, parser.cmdAs("zt").?);
    try testing.expectEqual(CmdId.ZWRITE, parser.cmdAs("ZW").?);
    try testing.expectEqual(null, parser.cmdAs("zti"));
}

test "caseless groups fold ASCII case; others match exactly" {
    try testing.expectEqual(CmdId.WRITE, parser.cmdAs("wRiTe").?);
    try testing.expectEqual(FnId.PIECE, parser.fnAs("Pie").?);
    try testing.expectEqual(WordId.END, parser.wordAs("end").?);
    try testing.expectEqual(null, parser.wordAs("END"));
    try testing.expectEqual(WordId.NIL_P, parser.wordAs("nil?").?);
    try testing.expectEqual(null, parser.wordAs("nil"));
}

test "no word, and words past the longest keyword, are no keyword" {
    try testing.expectEqual(null, parser.cmdAs(""));
    try testing.expectEqual(null, parser.wordAs(""));
    try testing.expectEqual(null, parser.cmdAs("trestartx"));
    try testing.expectEqual(null, parser.cmdAs("\xff"));
}
