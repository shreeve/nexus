//! Minimal @lang module: a pass-through Lexer wrapper.
const parser = @import("parser.zig");

pub const Lexer = struct {
    base: parser.BaseLexer,

    pub fn init(source: []const u8) Lexer {
        return .{ .base = parser.BaseLexer.init(source) };
    }
    pub fn next(self: *Lexer) parser.Token {
        return self.base.next();
    }
    pub fn reset(self: *Lexer) void {
        self.base.reset();
    }
};

pub const KwId = enum(u16) { GO = 1, STOP = 2 };

pub fn kwAs(text: []const u8) ?KwId {
    if (@import("std").mem.eql(u8, text, "go")) return .GO;
    if (@import("std").mem.eql(u8, text, "stop")) return .STOP;
    return null;
}
