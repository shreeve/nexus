//! Fixed text of the generated parser module: the pieces codegen.zig emits
//! verbatim, independent of the grammar.

/// Imports and constants at the top of every generated module.
pub const prelude =
    \\
    \\const std = @import("std");
    \\const maxArgs: usize = 32;
    \\
;

/// Fallback for the `simd.findByte` calls the generated lexer may make.
pub const simdStub =
    \\
    \\// SIMD helpers (fallback if simd.zig not available)
    \\const simd = struct {
    \\    fn findByte(haystack: []const u8, needle: u8) usize {
    \\        for (haystack, 0..) |c, i| if (c == needle) return i;
    \\        return haystack.len;
    \\    }
    \\};
    \\
    \\
;

/// The uniform S-expression node type.
pub const sexpType =
    \\
    \\// =============================================================================
    \\// S-Expression (AST Node) - 5 Clean Variants
    \\// =============================================================================
    \\
    \\pub const Sexp = union(enum) {
    \\    nil:  void,                                        // Empty (nothing)
    \\    tag:  Tag,                                         // Semantic type (1 byte)
    \\    src:  struct { pos: u32, len: u16, id: u16 },      // Source ref + identity (8 bytes)
    \\    str:  []const u8,                                  // Embedded string (16 bytes)
    \\    list: []const Sexp,                                // Compound: (tag child1 ...)
    \\
    \\    /// Get token text from source
    \\    pub fn getText(self: Sexp, source: []const u8) []const u8 {
    \\        return switch (self) {
    \\            .src => |s| source[s.pos..][0..s.len],
    \\            .str => |s| s,
    \\            else => "",
    \\        };
    \\    }
    \\
    \\    /// Format for debug output
    \\    pub fn write(self: Sexp, source: []const u8, w: anytype) !void {
    \\        switch (self) {
    \\            .nil => try w.writeAll("_"),
    \\            .tag => |t| try w.print("{s}", .{@tagName(t)}),
    \\            .src => |s| try w.print("{s}", .{source[s.pos..][0..s.len]}),
    \\            .str => |s| try w.print("\"{s}\"", .{s}),
    \\            .list => |items| {
    \\                try w.writeAll("(");
    \\                for (items, 0..) |item, i| {
    \\                    if (i > 0) try w.writeAll(" ");
    \\                    try item.write(source, w);
    \\                }
    \\                try w.writeAll(")");
    \\            },
    \\        }
    \\    }
    \\};
    \\
;

/// BaseParser: fields, init/deinit, the table-driven parse loop, and the
/// Sexp builders actions call. Ends by opening `executeAction`'s switch;
/// codegen emits one arm per rule after it.
pub const parserRuntime =
    \\
    \\// =============================================================================
    \\// PARSER
    \\// =============================================================================
    \\
    \\pub const BaseParser = struct {
    \\    arena: std.heap.ArenaAllocator,
    \\    lexer: Lexer,
    \\    source: []const u8,
    \\    current: Token,
    \\    injectedToken: ?u16 = null,
    \\    lastMatchedId: u16 = 0,
    \\
    \\    stateStack: std.ArrayListUnmanaged(u16) = .empty,
    \\    valueStack: std.ArrayListUnmanaged(Sexp) = .empty,
    \\    /// Spare capacity of the lists `keepList` returned, by address.
    \\    listSpare: std.AutoHashMapUnmanaged(usize, ListSpare) = .empty,
    \\
    \\    const ListSpare = struct { len: usize, capacity: usize };
    \\
    \\    pub fn init(backingAllocator: std.mem.Allocator, source: []const u8) BaseParser {
    \\        var p = BaseParser{
    \\            .arena = std.heap.ArenaAllocator.init(backingAllocator),
    \\            .lexer = Lexer.init(source),
    \\            .source = source,
    \\            .current = undefined,
    \\        };
    \\        p.current = p.lexer.next();
    \\        return p;
    \\    }
    \\
    \\    pub fn deinit(self: *BaseParser) void {
    \\        self.arena.deinit();
    \\    }
    \\
    \\    fn allocator(self: *BaseParser) std.mem.Allocator {
    \\        return self.arena.allocator();
    \\    }
    \\
    \\    pub fn printError(self: *BaseParser) void {
    \\        const pos: usize = @min(self.current.pos, self.source.len);
    \\        var line: usize = 1;
    \\        var col: usize = 1;
    \\        var i: usize = 0;
    \\        while (i < pos) : (i += 1) {
    \\            if (self.source[i] == '\n') {
    \\                line += 1;
    \\                col = 1;
    \\            } else {
    \\                col += 1;
    \\            }
    \\        }
    \\        std.debug.print("Parse error at line {d}, column {d}: unexpected {s}\n", .{
    \\            line,
    \\            col,
    \\            @tagName(self.current.cat),
    \\        });
    \\    }
    \\
    \\    fn doParse(self: *BaseParser, startSym: u16) !Sexp {
    \\        const startState = getStartState(startSym);
    \\        self.stateStack.clearRetainingCapacity();
    \\        self.valueStack.clearRetainingCapacity();
    \\        try self.stateStack.append(self.allocator(), startState);
    \\
    \\        while (true) {
    \\            const state = self.stateStack.getLast();
    \\            const sym = if (self.injectedToken) |inj| inj else self.tokenToSymbol(self.current);
    \\            var action = getAction(state, sym);
    \\
    \\            // X "c" check: if reducing and next char matches with pre==0, shift instead
    \\            if (action < -1 and self.current.pre == 0 and self.current.pos < self.source.len) {
    \\                if (getImmediateShift(state, self.source[self.current.pos])) |shiftTarget| {
    \\                    action = shiftTarget;
    \\                }
    \\            }
    \\
    \\            if (action == 0) {
    \\                return error.ParseError;
    \\            } else if (action == -1) {
    \\                return self.valueStack.getLast();
    \\            } else if (action > 0) {
    \\                // Shift
    \\                if (self.injectedToken != null) {
    \\                    try self.valueStack.append(self.allocator(), .nil);
    \\                    self.injectedToken = null;
    \\                } else {
    \\                    try self.valueStack.append(self.allocator(), .{ .src = .{
    \\                        .pos = self.current.pos,
    \\                        .len = self.current.len,
    \\                        .id  = if (self.lastMatchedId != 0) self.lastMatchedId else self.lexer.base.aux,
    \\                    } });
    \\                    self.lastMatchedId = 0;
    \\                    self.lexer.base.aux = 0;
    \\                    self.current = self.lexer.next();
    \\                }
    \\                try self.stateStack.append(self.allocator(), @intCast(action));
    \\            } else {
    \\                // Reduce
    \\                const ruleId: u16 = @intCast(-action - 2);
    \\                var pass: [maxArgs]Sexp = undefined;
    \\                const len = ruleLen[ruleId];
    \\                for (0..len) |i| {
    \\                    pass[len - 1 - i] = self.valueStack.pop().?;
    \\                    _ = self.stateStack.pop();
    \\                }
    \\
    \\                const result = self.executeAction(ruleId, pass[0..len]);
    \\
    \\                if (isAcceptRule(ruleId)) return result;
    \\
    \\                try self.valueStack.append(self.allocator(), result);
    \\
    \\                const gotoState = self.stateStack.getLast();
    \\                const next = getAction(gotoState, ruleLhs[ruleId]);
    \\                if (next <= 0) return error.ParseError;
    \\                try self.stateStack.append(self.allocator(), @intCast(next));
    \\            }
    \\        }
    \\    }
    \\
    \\    /// Spread list helper: [head, ...tail]
    \\    fn spreadList(self: *BaseParser, head: Sexp, tail: Sexp) Sexp {
    \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
    \\        out.append(self.allocator(), head) catch return .nil;
    \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
    \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
    \\    }
    \\
    \\    /// Spread only: [...tail]
    \\    fn spreadOnly(self: *BaseParser, tail: Sexp) Sexp {
    \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
    \\        if (tail == .list) for (tail.list) |item| out.append(self.allocator(), item) catch return .nil;
    \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
    \\    }
    \\
    \\    /// Default list handler
    \\    fn list(self: *BaseParser, pass: []Sexp) Sexp {
    \\        if (pass.len == 0) return .nil;
    \\        if (pass.len == 1) return pass[0];
    \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
    \\        for (pass) |v| out.append(self.allocator(), v) catch return .nil;
    \\        return .{ .list = out.toOwnedSlice(self.allocator()) catch &[_]Sexp{} };
    \\    }
    \\
    \\    /// Start a list holding the items of `base` (a list, else
    \\    /// nothing) for an action that appends to it. A list from
    \\    /// `keepList` is reused with its spare capacity, so a
    \\    /// left-recursive list grows in amortized O(1) per element.
    \\    fn extendList(self: *BaseParser, base: Sexp) !std.ArrayListUnmanaged(Sexp) {
    \\        if (base != .list) return .empty;
    \\        const items = base.list;
    \\        if (items.len > 0) if (self.listSpare.get(@intFromPtr(items.ptr))) |spare| {
    \\            if (spare.len == items.len) {
    \\                _ = self.listSpare.remove(@intFromPtr(items.ptr));
    \\                return .{ .items = @constCast(items), .capacity = spare.capacity };
    \\            }
    \\        };
    \\        var out: std.ArrayListUnmanaged(Sexp) = .empty;
    \\        try out.appendSlice(self.allocator(), items);
    \\        return out;
    \\    }
    \\
    \\    /// Finish a list from `extendList`, recording its spare capacity.
    \\    fn keepList(self: *BaseParser, out: *std.ArrayListUnmanaged(Sexp)) Sexp {
    \\        if (out.items.len > 0 and out.capacity > out.items.len) {
    \\            self.listSpare.put(self.allocator(), @intFromPtr(out.items.ptr), .{
    \\                .len = out.items.len,
    \\                .capacity = out.capacity,
    \\            }) catch {};
    \\        }
    \\        return .{ .list = out.items };
    \\    }
    \\
    \\    /// Build S-expression: (tag items...) with trailing nil trimming
    \\    inline fn sexp(self: *BaseParser, comptime tag: Tag, items: []const Sexp) Sexp {
    \\        if (items.len == 0) {
    \\            const result = self.allocator().alloc(Sexp, 1) catch return .nil;
    \\            result[0] = .{ .tag = tag };
    \\            return .{ .list = result };
    \\        }
    \\        var len = items.len;
    \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
    \\        const result = self.allocator().alloc(Sexp, len + 1) catch return .nil;
    \\        result[0] = .{ .tag = tag };
    \\        if (len > 0) @memcpy(result[1..][0..len], items[0..len]);
    \\        return .{ .list = result };
    \\    }
    \\
    \\    /// Build S-expression: (tag ...spread) - tag + spread items
    \\    inline fn sexpSpread(self: *BaseParser, comptime tag: Tag, spread: Sexp) Sexp {
    \\        const items = if (spread == .list) spread.list else &[_]Sexp{};
    \\        var len = items.len;
    \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
    \\        const result = self.allocator().alloc(Sexp, len + 1) catch return .nil;
    \\        result[0] = .{ .tag = tag };
    \\        if (len > 0) @memcpy(result[1..][0..len], items[0..len]);
    \\        return .{ .list = result };
    \\    }
    \\
    \\    /// Build S-expression: (tag pos ...spread) - tag + position + spread items
    \\    inline fn sexpPosSpread(self: *BaseParser, comptime tag: Tag, pos: Sexp, spread: Sexp) Sexp {
    \\        const items = if (spread == .list) spread.list else &[_]Sexp{};
    \\        var len = items.len;
    \\        while (len > 0 and items[len - 1] == .nil) len -= 1;
    \\        const skipPos = (pos == .nil and len == 0);
    \\        const total = if (skipPos) 1 else len + 2;
    \\        const result = self.allocator().alloc(Sexp, total) catch return .nil;
    \\        result[0] = .{ .tag = tag };
    \\        if (!skipPos) {
    \\            result[1] = pos;
    \\            if (len > 0) @memcpy(result[2..][0..len], items[0..len]);
    \\        }
    \\        return .{ .list = result };
    \\    }
    \\
    \\    fn executeAction(self: *BaseParser, ruleId: u16, pass: []Sexp) Sexp {
    \\        return switch (ruleId) {
    \\
;
