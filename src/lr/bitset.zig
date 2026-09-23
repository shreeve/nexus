//! Fixed-width bit sets over symbol ids, the set representation of the LR
//! stages (FIRST, FOLLOW, and LALR lookahead sets).
//!
//! A `BitSet` is a view of caller-owned words; `SetArray` allocates many
//! equal-width sets in one block so a whole family of sets (one per symbol,
//! one per nonterminal transition) is a single allocation.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Word = u64;
const wordBits = @bitSizeOf(Word);

pub fn wordsFor(bits: usize) usize {
    return (bits + wordBits - 1) / wordBits;
}

pub const BitSet = struct {
    words: []Word,

    pub fn set(self: BitSet, i: usize) void {
        self.words[i / wordBits] |= @as(Word, 1) << @intCast(i % wordBits);
    }

    pub fn isSet(self: BitSet, i: usize) bool {
        return (self.words[i / wordBits] >> @intCast(i % wordBits)) & 1 != 0;
    }

    /// self |= other; returns whether self changed.
    pub fn unionWith(self: BitSet, other: BitSet) bool {
        var changed: Word = 0;
        for (self.words, other.words) |*w, o| {
            changed |= o & ~w.*;
            w.* |= o;
        }
        return changed != 0;
    }

    pub fn copyFrom(self: BitSet, other: BitSet) void {
        @memcpy(self.words, other.words);
    }

    pub fn clear(self: BitSet) void {
        @memset(self.words, 0);
    }

    pub fn count(self: BitSet) usize {
        var n: usize = 0;
        for (self.words) |w| n += @popCount(w);
        return n;
    }

    pub fn isEmpty(self: BitSet) bool {
        for (self.words) |w| if (w != 0) return false;
        return true;
    }

    /// Whether every member of self is in other.
    pub fn isSubsetOf(self: BitSet, other: BitSet) bool {
        for (self.words, other.words) |w, o| if (w & ~o != 0) return false;
        return true;
    }

    pub fn eql(self: BitSet, other: BitSet) bool {
        return std.mem.eql(Word, self.words, other.words);
    }

    /// Members in ascending order.
    pub fn iterator(self: BitSet) Iterator {
        return .{ .words = self.words, .index = 0, .current = if (self.words.len > 0) self.words[0] else 0 };
    }

    pub const Iterator = struct {
        words: []const Word,
        index: usize,
        current: Word,

        pub fn next(it: *Iterator) ?u16 {
            while (it.current == 0) {
                it.index += 1;
                if (it.index >= it.words.len) return null;
                it.current = it.words[it.index];
            }
            const bit = @ctz(it.current);
            it.current &= it.current - 1;
            return @intCast(it.index * wordBits + bit);
        }
    };
};

/// `len` sets of `bits` bits each, zero-initialized, in one allocation.
pub const SetArray = struct {
    words: []Word,
    stride: usize,
    len: usize,

    pub fn init(allocator: Allocator, len: usize, bits: usize) !SetArray {
        const stride = wordsFor(bits);
        const words = try allocator.alloc(Word, stride * len);
        @memset(words, 0);
        return .{ .words = words, .stride = stride, .len = len };
    }

    pub fn deinit(self: *SetArray, allocator: Allocator) void {
        allocator.free(self.words);
        self.* = undefined;
    }

    pub fn get(self: SetArray, i: usize) BitSet {
        return .{ .words = self.words[i * self.stride ..][0..self.stride] };
    }
};

test "set, test, iterate in order" {
    const a = std.testing.allocator;
    var arr = try SetArray.init(a, 2, 130);
    defer arr.deinit(a);
    const s = arr.get(0);
    for ([_]usize{ 129, 0, 64, 63, 5 }) |i| s.set(i);
    try std.testing.expect(s.isSet(64) and !s.isSet(65));
    try std.testing.expectEqual(@as(usize, 5), s.count());
    var it = s.iterator();
    var got: [5]u16 = undefined;
    var n: usize = 0;
    while (it.next()) |i| : (n += 1) got[n] = i;
    try std.testing.expectEqualSlices(u16, &.{ 0, 5, 63, 64, 129 }, got[0..n]);

    const t = arr.get(1);
    try std.testing.expect(t.isEmpty());
    try std.testing.expect(t.unionWith(s));
    try std.testing.expect(!t.unionWith(s));
    try std.testing.expect(t.eql(s) and s.isSubsetOf(t));
}
