//! Runtime template for generated parser modules.
//!
//! This is a real Zig file: it compiles on its own and its tests run with
//! `zig build unit`. codegen.zig embeds it and composes the output
//! module from its sections (see runtime.zig):
//!
//!   // @section NAME     starts a section; it runs to the next `// @end`.
//!   // @slot NAME        (inside a section) replaced by generated code.
//!
//! Everything outside the sections is a test fixture: a small hand-written
//! grammar (tables produced by Nexus) standing in for the generated
//! declarations the runtime refers to. None of it is emitted.
//!
//! Generated interface (codegen declares these in every module):
//!   types      Tag, Role, Start, Token, TokenCat, BaseLexer, Lexer
//!   config     nodeStore, elemEnds, keepTrailingNils, hasTrivia, hasRepair,
//!              asGroups, numSymbols, endSymbol, errorSymbol, xExcludes,
//!              maxExpected
//!   tables     ruleLhs, ruleLen, ruleValue, parseTable, xExcludeStart,
//!              expectedSymbols, expectedOffsets, expectedOf, repairTokens,
//!              repairOffsets
//!   functions  startState, startMarker, tokenToSymbol, promote,
//!              executeAction, symbolName, isTrivia, repairClass,
//!              ruleSideLabels, slotOf, restSlotOf, roleAt, restRoleOf

const std = @import("std");

// @section sexp

// =============================================================================
// S-expressions
// =============================================================================

/// Dense per-parse node number; 0 = no node store entry.
pub const NodeId = u32;

/// A byte range [start, end) of the source.
pub const Span = struct {
    start: u32,
    end: u32,

    pub const empty: Span = .{ .start = 0, .end = 0 };

    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }

    pub fn isEmpty(self: Span) bool {
        return self.start == self.end;
    }
};

/// A source leaf: token position and length, plus the token id attribute
/// (an `@as` keyword ordinal, or the lexer's `aux` value; see `takeLexerId`).
pub const Src = struct { pos: u32, len: u16, id: u16 };

/// A list node: its items and its node id (0 when the parse keeps no node
/// store, or for lists built outside the parser, e.g. by a lang wrapper).
pub const List = struct {
    ptr: [*]const Sexp,
    len: u32,
    id: NodeId = 0,

    pub const empty: List = .{ .ptr = &[_]Sexp{}, .len = 0 };

    /// A list over `xs` with no node id.
    pub fn of(xs: []const Sexp) List {
        return .{ .ptr = xs.ptr, .len = @intCast(xs.len) };
    }

    /// A list over `xs` carrying node id `id` (e.g. a rewritten node
    /// keeping the id, and so the span, of the node it replaces).
    pub fn withId(xs: []const Sexp, id: NodeId) List {
        return .{ .ptr = xs.ptr, .len = @intCast(xs.len), .id = id };
    }

    pub fn items(self: List) []const Sexp {
        return self.ptr[0..self.len];
    }
};

/// The uniform tree value: 24 bytes, O(1) dispatch on the head tag.
pub const Sexp = union(enum) {
    nil,
    tag: Tag,
    src: Src,
    str: []const u8,
    list: List,

    comptime {
        std.debug.assert(@sizeOf(Sexp) == 24);
    }

    /// A list value over `xs` with no node id.
    pub fn listOf(xs: []const Sexp) Sexp {
        return .{ .list = List.of(xs) };
    }

    /// The items of a list; empty for any other value.
    pub fn items(self: Sexp) []const Sexp {
        return switch (self) {
            .list => |l| l.items(),
            else => &.{},
        };
    }

    /// The head tag of a tag-headed list.
    pub fn kind(self: Sexp) ?Tag {
        if (self != .list or self.list.len == 0) return null;
        const head = self.list.ptr[0];
        return if (head == .tag) head.tag else null;
    }

    pub fn isKind(self: Sexp, t: Tag) bool {
        const k = self.kind() orelse return false;
        return k == t;
    }

    /// The text of a leaf or string; empty otherwise.
    pub fn getText(self: Sexp, source: []const u8) []const u8 {
        return switch (self) {
            .src => |s| source[s.pos..][0..s.len],
            .str => |s| s,
            else => "",
        };
    }

    /// Print the tree on one line: `_`, tags by name, leaves as their text
    /// followed by `#id` when the id attribute is non-zero, strings quoted.
    /// error.WriteFailed also reports the walk running out of memory.
    pub fn write(self: Sexp, source: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeNested(self, w, source, writeAtom);
    }

    fn writeAtom(source: []const u8, w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!?[]const Sexp {
        switch (s) {
            .nil => try w.writeAll("_"),
            .tag => |t| try w.writeAll(nameOf(t)),
            .src => |x| {
                try w.writeAll(source[x.pos..][0..x.len]);
                if (x.id != 0) try w.print("#{d}", .{x.id});
            },
            .str => |x| try w.print("\"{s}\"", .{x}),
            .list => |l| return l.items(),
        }
        return null;
    }
};

/// The name of a Tag or Role value, "?" for one the enum does not name
/// (without a schema Role is empty, and so is Tag when no action builds a
/// tag: both are then non-exhaustive).
fn nameOf(value: anytype) []const u8 {
    return std.enums.tagName(@TypeOf(value), value) orelse "?";
}

/// The explicit stack of a tree walk: per open list, its items not yet
/// visited. Ordinary input builds trees of any depth (a long operator
/// chain is a tree as deep as it is long), so no walk of a tree recurses
/// on the native stack. Shallow walks use the frames inline; deeper ones
/// move them to page memory.
const Walk = struct {
    small: [32][]const Sexp = undefined,
    big: [][]const Sexp = &.{},
    len: usize = 0,

    fn frames(self: *Walk) [][]const Sexp {
        return if (self.big.len > 0) self.big else &self.small;
    }

    fn push(self: *Walk, items: []const Sexp) error{OutOfMemory}!void {
        var f = self.frames();
        if (self.len == f.len) {
            const grown = try std.heap.page_allocator.alloc([]const Sexp, f.len * 2);
            @memcpy(grown[0..self.len], f);
            if (self.big.len > 0) std.heap.page_allocator.free(self.big);
            self.big = grown;
            f = grown;
        }
        f[self.len] = items;
        self.len += 1;
    }

    /// The unvisited items of the innermost open list.
    fn top(self: *Walk) ?*[]const Sexp {
        return if (self.len == 0) null else &self.frames()[self.len - 1];
    }

    fn pop(self: *Walk) void {
        self.len -= 1;
    }

    /// The next item in pre-order, closing the lists it leaves; null at
    /// the end of the walk.
    fn next(self: *Walk) ?Sexp {
        while (self.top()) |rest| {
            if (rest.len > 0) {
                defer rest.* = rest.*[1..];
                return rest.*[0];
            }
            self.pop();
        }
        return null;
    }

    fn deinit(self: *Walk) void {
        if (self.big.len > 0) std.heap.page_allocator.free(self.big);
    }
};

/// Write `root` as nested parentheses with a space between items.
/// `atom(ctx, w, s)` writes a value and returns null, or returns the items
/// of a list to open.
fn writeNested(
    root: Sexp,
    w: *std.Io.Writer,
    ctx: anytype,
    comptime atom: fn (@TypeOf(ctx), *std.Io.Writer, Sexp) std.Io.Writer.Error!?[]const Sexp,
) std.Io.Writer.Error!void {
    var walk: Walk = .{};
    defer walk.deinit();
    var s = root;
    while (true) {
        // Whether the next item of the innermost list follows another.
        var sep = true;
        if (try atom(ctx, w, s)) |items| {
            try w.writeByte('(');
            walk.push(items) catch return error.WriteFailed;
            sep = false;
        }
        while (true) {
            const rest = walk.top() orelse return;
            if (rest.len > 0) {
                if (sep) try w.writeByte(' ');
                s = rest.*[0];
                rest.* = rest.*[1..];
                break;
            }
            walk.pop();
            try w.writeByte(')');
            sep = true;
        }
    }
}

// @end

// @section parser

// =============================================================================
// Parser
// =============================================================================

/// Per node: its source span and the rule that built it.
const NodeInfo = struct { span: Span, rule: u16 };

/// NodeInfo per NodeId, in fixed-size chunks that never move (appending
/// never copies the store).
const NodeStore = struct {
    chunks: std.ArrayList(*[chunkLen]NodeInfo) = .empty,
    len: u32 = 0,

    const chunkLen = 128;

    inline fn add(self: *NodeStore, a: std.mem.Allocator, info: NodeInfo) !NodeId {
        const id = self.len;
        if (id % chunkLen == 0) try self.addChunk(a);
        self.chunks.items[id / chunkLen][id % chunkLen] = info;
        self.len = id + 1;
        return id;
    }

    fn addChunk(self: *NodeStore, a: std.mem.Allocator) !void {
        try self.chunks.append(a, try a.create([chunkLen]NodeInfo));
    }

    inline fn at(self: *const NodeStore, id: NodeId) *NodeInfo {
        return &self.chunks.items[id / chunkLen][id % chunkLen];
    }
};

/// The parse table's action for `sym` in `state`: 0 = error, > 0 = shift
/// or goto, -1 = accept, <= -2 = reduce rule (-a - 2), or `hinted`.
inline fn getAction(state: u16, sym: u16) i16 {
    return parseTable[state][sym];
}

/// Whether rule `r` is a pass-through `A → B`: one element, and its value.
inline fn isPassThrough(r: u16) bool {
    return ruleLen[r] == 1 and ruleValue[r] == 2;
}

/// The cell of a reduction an `X "c"` hint overrides: `hintedAction`
/// decides it (no rule has this number: rules are fewer than 32766).
const hinted: i16 = std.math.minInt(i16);

/// What `state` expects, reader-named: list `expectedOf[state]` of
/// `expectedSymbols`.
fn expectedIn(state: u16) []const u16 {
    const i = expectedOf[state];
    return expectedSymbols[expectedOffsets[i]..expectedOffsets[i + 1]];
}

/// The action of a `hinted` cell: shift to the hint's state when the token
/// touches the previous one, else the table's reduction.
fn hintedAction(state: u16, sym: u16, touching: bool) i16 {
    for (xExcludes[xExcludeStart[state]..xExcludeStart[state + 1]]) |x| {
        if (x.sym == sym) return if (touching) @intCast(x.shift) else x.reduce;
    }
    unreachable; // every hinted cell has its exclude
}

/// The tokens tolerant repair may insert in `state`, best first.
fn repairCandidates(state: u16) []const u16 {
    if (!hasRepair) return &.{};
    return repairTokens[repairOffsets[state]..repairOffsets[state + 1]];
}

/// The symbol `tokenToSymbol` gives the promotable token when `@as`
/// decides it per state; no grammar symbol has it.
const needsPromotion: u16 = std.math.maxInt(u16);

/// The length of an `@as` group's symbol map: an entry for every value of
/// its Id enum up to the largest it names.
fn idCount(comptime Id: type) usize {
    var n: usize = 0;
    for (@typeInfo(Id).@"enum".field_values) |v| n = @max(n, v + 1);
    return n;
}

/// A side-band role recorded at reduce time (not placed in the tree).
const SideEntry = struct { node: NodeId, role: Role, span: Span };

/// A side-band label of a rule: `role` is recorded from element `pass`.
const SideLabel = struct { role: Role, pass: u16 };

/// A parse error: the offending token and the state that rejected it.
pub const Failure = struct {
    span: Span,
    /// Grammar symbol of the offending token.
    symbol: u16,
    cat: TokenCat,
    state: u16,
};

/// Result of `parseTolerant`.
pub const Tolerant = struct {
    /// The tree; `.nil` when the parse could not be completed.
    sexp: Sexp,
    /// The first error, as the strict parse reports it (null when the
    /// input was valid).
    failure: ?Failure,
    /// Tokens inserted plus tokens deleted.
    repairs: u32,
    /// Zero-width tokens inserted (holes and structure).
    insertions: u32 = 0,
    /// Offending tokens deleted.
    deletions: u32 = 0,
    complete: bool,
};

/// A token's role in tolerant repair, from `@repair`.
const RepairClass = enum {
    /// Not fabricable: real input.
    none,
    /// `holes`: a value-carrying token that may be minted with empty text.
    hole,
    /// `structure`: layout a lexer mints (INDENT, OUTDENT, ...).
    structure,
    /// `terminator`: structure that ends a statement (NEWLINE); the only
    /// insertion allowed in front of real input.
    terminator,
};

/// The id attribute of the token the lexer just produced, cleared as it is
/// read. It is the `aux: u16` field of the generated BaseLexer, which a lang
/// `Lexer` wrapper reaches as `base.aux` (set it before returning a token,
/// e.g. MUMPS stores the dot level of a line there). The parser stores it in
/// the token's `src.id` unless an `@as` keyword match supplies the id.
fn takeLexerId(lexer: *Lexer) u16 {
    const base: *BaseLexer = if (Lexer == BaseLexer) lexer else &lexer.base;
    defer base.aux = 0;
    return base.aux;
}

comptime {
    if (Lexer != BaseLexer and !(@hasField(Lexer, "base") and @FieldType(Lexer, "base") == BaseLexer))
        @compileError("the lang module's Lexer wrapper must hold the generated lexer in a field `base: BaseLexer`");
}

pub const BaseParser = struct {
    arena: std.heap.ArenaAllocator,
    lexer: Lexer,
    source: []const u8,
    current: Token,
    /// A start marker to shift before any input (set by `parse`).
    injectedToken: ?u16 = null,
    /// A zero-width token the tolerant driver inserts before `current`.
    pendingInsert: ?u16 = null,
    /// `@as` keyword ordinal of `current`, stored in its `src.id`.
    lastMatchedId: u16 = 0,
    /// The `@as` lookups of `current`, one per group: the keyword ordinal
    /// plus one, `noKeyword`, or 0 before the lookup. A lookup does not
    /// depend on the state, so it runs once per token.
    keywordIds: [asGroups]u32 = @splat(0),
    /// Set when a builder could not allocate; the parse then fails.
    outOfMemory: bool = false,
    /// A parse has begun (the next one re-reads the input).
    started: bool = false,

    /// The free bytes of the allocator's current chunk, and the size of
    /// its next one (see `allocator`).
    bumpPos: usize = 0,
    bumpEnd: usize = 0,
    bumpNext: usize = bumpFirst,

    stateStack: std.ArrayList(u16) = .empty,
    valueStack: std.ArrayList(Sexp) = .empty,
    /// Per value-stack entry, the list `keepExtended` left there with its
    /// capacity, for `extendBy` to grow in place. Indexed like
    /// `valueStack`, sized to its capacity. An entry only ever describes a
    /// live buffer: `extendBy` clears the one it takes (its buffer may
    /// move and be freed), a rule passing a list on moves the entry with
    /// it, and each parse starts with none (its memory is reused).
    spares: []Spare = &.{},

    // Node store (when `nodeStore`): per value-stack entry where it
    // starts, and per node its span and rule, indexed by NodeId (entry 0
    // unused). An entry starts at its first token, or at the next token
    // when it consumed none. A reduction then extends from its first
    // element's start to the end of the last token shifted (`lastEnd`),
    // and is empty when start >= end. With `elemEnds` (side-band labels or
    // nested nodes) each entry's end is kept too. Both are indexed like
    // `valueStack` and sized to its capacity (the stack top is its length).
    starts: []u32 = &.{},
    ends: []u32 = &.{},
    nodes: NodeStore = .{},
    sides: std.ArrayList(SideEntry) = .empty,
    reduction: Reduction = .{},
    /// End of the last shifted token: where every reduction ends.
    lastEnd: u32 = 0,

    triviaTokens: std.ArrayList(Token) = .empty,
    failure: ?Failure = null,
    scratch: std.ArrayList(u16) = .empty,

    const Spare = struct {
        items: [*]const Sexp,
        len: u32,
        capacity: u32,

        const none: Spare = .{ .items = &.{}, .len = 0, .capacity = 0 };
    };

    /// The reduction in progress: its rule and where it starts (it ends at
    /// `lastEnd`); with `elemEnds`, also the stack index of its first
    /// element and the first node id it built.
    const Reduction = struct {
        rule: u16 = 0,
        start: u32 = 0,
        base: u32 = 0,
        firstNode: NodeId = 0,
    };

    pub fn init(backingAllocator: std.mem.Allocator, source: []const u8) BaseParser {
        var p = BaseParser{
            .arena = std.heap.ArenaAllocator.init(backingAllocator),
            .lexer = Lexer.init(source),
            .source = source,
            .current = undefined,
        };
        p.setCurrent(p.lexer.next());
        return p;
    }

    pub fn deinit(self: *BaseParser) void {
        self.arena.deinit();
    }

    /// Start over on `source`, keeping the memory the parser holds for the
    /// next parses: the trees, node ids and errors of earlier parses, and
    /// everything from `allocator`, are gone.
    pub fn reset(self: *BaseParser, source: []const u8) void {
        var arena = self.arena;
        _ = arena.reset(.retain_capacity);
        self.* = .{ .arena = arena, .lexer = Lexer.init(source), .source = source, .current = undefined };
        self.setCurrent(self.lexer.next());
    }

    /// The parser's allocator, which holds the trees: a bump allocator over
    /// chunks of the arena (single-threaded, so allocation is a bounds check
    /// and an add; the arena's own allocation is atomic). A lang Parser
    /// wrapper allocates what it builds here too. Everything is freed by
    /// `deinit` (or `reset`).
    pub fn allocator(self: *BaseParser) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &bumpVTable };
    }

    /// `n` items for a list: the allocator's fast path, inline.
    inline fn allocItems(self: *BaseParser, n: usize) error{OutOfMemory}![]Sexp {
        const start = std.mem.alignForward(usize, self.bumpPos, @alignOf(Sexp));
        const end = start + n * @sizeOf(Sexp);
        if (end > self.bumpEnd) return self.allocator().alloc(Sexp, n);
        self.bumpPos = end;
        return @as([*]Sexp, @ptrFromInt(start))[0..n];
    }

    const bumpVTable: std.mem.Allocator.VTable = .{
        .alloc = bumpAlloc,
        .resize = bumpResize,
        .remap = bumpRemap,
        .free = bumpFree,
    };

    /// Chunks grow from `bumpFirst` to `bumpLast` bytes; a request larger
    /// than `bumpLast / 4` goes to the arena by itself.
    const bumpFirst = 4096;
    const bumpLast = 1 << 20;

    fn bumpAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *BaseParser = @ptrCast(@alignCast(ctx));
        const start = alignment.forward(self.bumpPos);
        if (start + len <= self.bumpEnd) {
            self.bumpPos = start + len;
            return @ptrFromInt(start);
        }
        return self.bumpRefill(len, alignment, ra);
    }

    fn bumpRefill(self: *BaseParser, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const arena = self.arena.allocator();
        if (len > bumpLast / 4) return arena.rawAlloc(len, alignment, ra);
        const size = @max(self.bumpNext, len + alignment.toByteUnits());
        const chunk = arena.rawAlloc(size, .@"16", ra) orelse return null;
        self.bumpNext = @min(size * 2, bumpLast);
        const start = alignment.forward(@intFromPtr(chunk));
        self.bumpPos = start + len;
        self.bumpEnd = @intFromPtr(chunk) + size;
        return @ptrFromInt(start);
    }

    /// The last allocation grows or shrinks in place; any other only
    /// shrinks.
    fn bumpResize(ctx: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
        const self: *BaseParser = @ptrCast(@alignCast(ctx));
        const start = @intFromPtr(memory.ptr);
        if (start + memory.len != self.bumpPos) return new_len <= memory.len;
        if (start + new_len > self.bumpEnd) return false;
        self.bumpPos = start + new_len;
        return true;
    }

    fn bumpRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        return if (bumpResize(ctx, memory, alignment, new_len, ra)) memory.ptr else null;
    }

    fn bumpFree(ctx: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
        const self: *BaseParser = @ptrCast(@alignCast(ctx));
        const start = @intFromPtr(memory.ptr);
        if (start + memory.len == self.bumpPos) self.bumpPos = start;
    }

    // @slot startMethods

    /// Parse the whole input as `start`. The state, the current token's
    /// symbol and the next action live in locals: the symbol changes only
    /// when a token is shifted, except that `@as` promotion depends on the
    /// state, so a promotable token is promoted again after each
    /// reduction. A run of pass-throughs (an operand climbing a chain of
    /// `A → B` rules) keeps the state below it and writes the stack once.
    pub fn parse(self: *BaseParser, start: Start) !Sexp {
        try self.begin(start);
        // The start marker, which the start state shifts before any input.
        if (self.injectedToken) |marker| try self.shift(@intCast(getAction(self.stateStack.last().?, marker)));
        var state = self.stateStack.last().?;
        var raw = tokenToSymbol(self.current);
        var sym = self.promoted(raw);
        var action = self.strictAction(state, sym);
        while (true) {
            if (action > 0) {
                state = @intCast(action);
                try self.shiftToken(state);
                raw = tokenToSymbol(self.current);
                sym = self.promoted(raw);
                action = self.strictAction(state, sym);
            } else if (action < -1) {
                var rule: u16 = @intCast(-action - 2);
                if (isPassThrough(rule) and !(asGroups > 0 and raw == needsPromotion)) {
                    const states = self.stateStack.items;
                    const below = states[states.len - 2];
                    while (true) {
                        state = @intCast(getAction(below, ruleLhs[rule]));
                        action = self.strictAction(state, sym);
                        if (action >= -1) break;
                        rule = @intCast(-action - 2);
                        if (!isPassThrough(rule)) break;
                    }
                    states[states.len - 1] = state;
                } else {
                    state = try self.reduceOrPass(rule);
                    if (asGroups > 0 and raw == needsPromotion) sym = self.promoted(raw);
                    action = self.strictAction(state, sym);
                }
            } else if (action == -1) {
                return self.valueStack.last().?;
            } else {
                self.recordFailure(state, sym);
                return error.ParseError;
            }
        }
    }

    /// The symbol of the current token, `raw` from `tokenToSymbol`, after
    /// `@as` promotion in the current state.
    inline fn promoted(self: *BaseParser, raw: u16) u16 {
        if (asGroups > 0 and raw == needsPromotion) return promote(self, self.current);
        return raw;
    }

    /// Parse `start`, repairing syntax errors for an editor: the parse goes
    /// on past an error with the tree built the normal way. The rules:
    ///
    ///   1. The first error is recorded exactly as the strict parse reports
    ///      it (token, state, expected set); repairs never replace it, and a
    ///      repaired parse still returns it: recovery is not acceptance.
    ///   2. Only tokens the grammar declares in `@repair` are ever inserted,
    ///      as zero-width tokens at the offending token, taken from the
    ///      state's generated candidate list (holes, then structure; fewer
    ///      further fabrications first).
    ///   3. What the offending token admits: end of input and structure
    ///      tokens (lexer scaffolding) admit any candidate; real input
    ///      admits only a `terminator` (a statement boundary splits what
    ///      the user wrote without inventing meaning in front of it: no
    ///      holes, no block structure before real code).
    ///   4. An insertion must let the offending token be consumed (shifted,
    ///      or accepted at end of input). At end of input or a structure
    ///      token, when none does, a candidate the state can shift is
    ///      inserted anyway, so several insertions can complete an
    ///      unfinished construct. Since the last token was consumed, the
    ///      same token is inserted in the same state again only on a
    ///      shallower stack: a repeat at the same depth is a cycle, and one
    ///      on a deeper stack only nests the construct further.
    ///   5. With no admissible insertion the offending token is deleted,
    ///      except end of input, which is never deleted: the parse ends
    ///      there, incomplete.
    ///   6. At most `budget` repairs (insertions plus deletions); when they
    ///      are spent the parse ends, incomplete.
    ///
    /// Strict parsing (`parse`) is a separate entry point and pays nothing.
    pub fn parseTolerant(self: *BaseParser, start: Start, budget: u32) !Tolerant {
        if (!hasRepair) @compileError("parseTolerant needs a @repair section in the grammar");
        try self.begin(start);
        var result: Tolerant = .{ .sexp = .nil, .failure = null, .repairs = 0, .complete = false };
        // Configurations repaired since the last consumed token (rule 4).
        var tried: std.ArrayList(RepairKey) = .empty;
        while (true) {
            const state = self.stateStack.last().?;
            const sym = self.lookahead();
            const action = self.actionFor(state, sym);
            if (action > 0) {
                if (self.pendingInsert == null and self.injectedToken == null) tried.clearRetainingCapacity();
                try self.shift(@intCast(action));
            } else if (action < -1) {
                _ = try self.reduceOrPass(@intCast(-action - 2));
            } else if (action == -1) {
                result.sexp = self.valueStack.last().?;
                result.complete = true;
                break;
            } else {
                // An inserted token is always acceptable (rule 4).
                std.debug.assert(self.pendingInsert == null);
                if (self.failure == null) self.recordFailure(state, sym);
                if (result.repairs == budget) break;
                if (try self.chooseInsertion(sym, tried.items)) |token| {
                    try tried.append(self.allocator(), .{ .depth = @intCast(self.stateStack.items.len), .state = state, .token = token });
                    self.pendingInsert = token;
                    result.insertions += 1;
                } else if (sym == endSymbol) {
                    break;
                } else {
                    try self.deleteToken();
                    tried.clearRetainingCapacity();
                    result.deletions += 1;
                }
                result.repairs += 1;
            }
        }
        result.failure = self.failure;
        return result;
    }

    const RepairKey = struct { depth: u32, state: u16, token: u16 };

    /// The insertion rules 3 and 4 allow before `next`, best first; null
    /// when there is none. An insertion already tried in this state, at
    /// this depth or above, since the last consumed token is not repeated.
    fn chooseInsertion(self: *BaseParser, next: u16, tried: []const RepairKey) !?u16 {
        const state = self.stateStack.last().?;
        const nextClass = if (next == endSymbol) RepairClass.structure else repairClass(next);
        const real = nextClass == .none or nextClass == .hole;
        const depth: u32 = @intCast(self.stateStack.items.len);
        for (repairCandidates(state)) |candidate| {
            if (real and repairClass(candidate) != .terminator) continue;
            if (!wasTried(tried, depth, state, candidate) and try self.accepts(candidate, next)) return candidate;
        }
        if (real) return null;
        for (repairCandidates(state)) |candidate| {
            if (!wasTried(tried, depth, state, candidate) and try self.accepts(candidate, null)) return candidate;
        }
        return null;
    }

    fn wasTried(tried: []const RepairKey, depth: u32, state: u16, token: u16) bool {
        for (tried) |k| if (k.depth <= depth and k.state == state and k.token == token) return true;
        return false;
    }

    fn begin(self: *BaseParser, start: Start) !void {
        // Token positions are u32.
        if (self.source.len > std.math.maxInt(u32)) return error.InputTooLarge;
        // Every parse reads the input from the start (a parser may parse
        // again, e.g. tolerantly after a failed strict parse). Node ids
        // keep counting, so earlier trees stay valid.
        if (self.started) {
            self.lexer = Lexer.init(self.source);
            self.setCurrent(self.lexer.next());
            self.lastMatchedId = 0;
            self.triviaTokens.clearRetainingCapacity();
        }
        self.started = true;
        @memset(self.spares, .none);
        self.stateStack.clearRetainingCapacity();
        self.valueStack.clearRetainingCapacity();
        self.failure = null;
        self.pendingInsert = null;
        self.outOfMemory = false;
        try self.stateStack.append(self.allocator(), startState(start));
        if (nodeStore) self.lastEnd = 0;
        self.injectedToken = startMarker(start);
        try self.ensureNodeStore();
        if (hasTrivia) try self.skipTrivia();
    }

    inline fn lookahead(self: *BaseParser) u16 {
        if (self.injectedToken) |marker| return marker;
        if (self.pendingInsert) |token| return token;
        const sym = tokenToSymbol(self.current);
        if (asGroups > 0 and sym == needsPromotion) return promote(self, self.current);
        return sym;
    }

    /// Make `tok` the current token (forgetting the keyword lookups of the
    /// one before).
    inline fn setCurrent(self: *BaseParser, tok: Token) void {
        self.current = tok;
        if (asGroups > 0) self.keywordIds = @splat(0);
    }

    /// `@as` promotion of the current token, `text`, to one group: the
    /// group's symbol for the keyword, else the group's fallback symbol,
    /// when the state takes it (with any action when `permissive`, else by
    /// a shift). The keyword's ordinal becomes the leaf's id. (A
    /// non-exhaustive Id enum may give an ordinal past the map: it has no
    /// symbol of its own.)
    inline fn tryPromote(
        self: *BaseParser,
        comptime group: usize,
        text: []const u8,
        comptime lookup: anytype,
        comptime toSymbol: []const u16,
        comptime fallback: u16,
        comptime permissive: bool,
    ) ?u16 {
        const id = self.keywordId(group, text, lookup) orelse return null;
        const state = self.stateStack.last().?;
        for ([_]u16{ if (id < toSymbol.len) toSymbol[id] else 0, fallback }) |sym| {
            if (sym == 0) continue;
            const action = getAction(state, sym);
            if (if (permissive) action != 0 else action > 0) {
                self.lastMatchedId = id;
                return sym;
            }
        }
        return null;
    }

    /// The ordinal `lookup` gives the current token's `text` in `group`,
    /// looked up once per token.
    inline fn keywordId(self: *BaseParser, comptime group: usize, text: []const u8, comptime lookup: anytype) ?u16 {
        const known = self.keywordIds[group];
        if (known != 0) return if (known == noKeyword) null else @intCast(known - 1);
        const id: ?u16 = if (lookup(text)) |k| @backingInt(k) else null;
        self.keywordIds[group] = if (id) |i| @as(u32, i) + 1 else noKeyword;
        return id;
    }

    const noKeyword = std.math.maxInt(u32);

    /// The table action, with the `X "c"` override: when the table reduces
    /// on the hinted token and it touches the previous token, shift
    /// instead. (Never for a start marker or an inserted token.)
    inline fn actionFor(self: *const BaseParser, state: u16, sym: u16) i16 {
        const action = getAction(state, sym);
        if (xExcludes.len > 0 and action == hinted)
            return hintedAction(state, sym, self.current.pre == 0 and self.pendingInsert == null and self.injectedToken == null);
        return action;
    }

    /// `actionFor` on a token of the input.
    inline fn strictAction(self: *const BaseParser, state: u16, sym: u16) i16 {
        const action = getAction(state, sym);
        if (xExcludes.len > 0 and action == hinted) return hintedAction(state, sym, self.current.pre == 0);
        return action;
    }

    fn shift(self: *BaseParser, target: u16) !void {
        if (self.injectedToken != null) {
            try self.pushEntry(target, .nil, self.current.pos, self.lastEnd);
            self.injectedToken = null;
        } else if (self.pendingInsert != null) {
            const pos = self.current.pos;
            try self.pushEntry(target, .{ .src = .{ .pos = pos, .len = 0, .id = 0 } }, pos, pos);
            if (nodeStore) self.lastEnd = pos;
            self.pendingInsert = null;
        } else try self.shiftToken(target);
    }

    /// Shift the current token, a token of the input.
    inline fn shiftToken(self: *BaseParser, target: u16) !void {
        const tok = self.current;
        // The lexer's id is taken even when an `@as` ordinal replaces it,
        // so it never reaches the next token.
        const lexerId = takeLexerId(&self.lexer);
        const id = if (asGroups > 0 and self.lastMatchedId != 0) self.lastMatchedId else lexerId;
        if (asGroups > 0) self.lastMatchedId = 0;
        const end = tok.pos + tok.len;
        try self.pushEntry(target, .{ .src = .{ .pos = tok.pos, .len = tok.len, .id = id } }, tok.pos, end);
        if (nodeStore) self.lastEnd = end;
        try self.advance();
    }

    /// Push a state, its value, and (with a node store) where the value
    /// starts and ends. The stacks grow together: the state stack is always
    /// one longer than the others, so one capacity check covers them all.
    inline fn pushEntry(self: *BaseParser, state: u16, value: Sexp, start: u32, end: u32) !void {
        const n = self.valueStack.items.len;
        if (n == self.valueStack.capacity) try self.growStacks();
        self.valueStack.items.len = n + 1;
        self.valueStack.items[n] = value;
        self.stateStack.items.len = n + 2;
        self.stateStack.items[n + 1] = state;
        if (nodeStore) self.starts[n] = start;
        if (elemEnds) self.ends[n] = end;
    }

    fn growStacks(self: *BaseParser) !void {
        const a = self.allocator();
        try self.valueStack.ensureUnusedCapacity(a, 1);
        const capacity = self.valueStack.capacity;
        try self.stateStack.ensureTotalCapacity(a, capacity + 1);
        if (nodeStore) self.starts = try a.realloc(self.starts, capacity);
        if (elemEnds) self.ends = try a.realloc(self.ends, capacity);
        const old = self.spares.len;
        self.spares = try a.realloc(self.spares, capacity);
        @memset(self.spares[old..], .none);
    }

    /// The value-stack index of `pass[0]`, the first element of the
    /// reduction in progress.
    fn stackIndex(self: *const BaseParser, pass: []const Sexp) usize {
        return (@intFromPtr(pass.ptr) - @intFromPtr(self.valueStack.items.ptr)) / @sizeOf(Sexp);
    }

    /// Reduce by `ruleId`. A pass-through `A → B` (the value of its one
    /// element) only replaces the top state with the goto on A: the value,
    /// its start and end, and its spare stay; it builds no node, so it
    /// places no empty element and records no side-band role.
    /// It returns the new top state.
    inline fn reduceOrPass(self: *BaseParser, ruleId: u16) !u16 {
        if (isPassThrough(ruleId)) {
            const states = self.stateStack.items;
            const next = getAction(states[states.len - 2], ruleLhs[ruleId]);
            std.debug.assert(next > 0); // every reduction has a goto
            states[states.len - 1] = @intCast(next);
            return @intCast(next);
        }
        try self.reduce(ruleId);
        return self.stateStack.items[self.stateStack.items.len - 1];
    }

    fn reduce(self: *BaseParser, ruleId: u16) !void {
        const len = ruleLen[ruleId];
        const base = self.valueStack.items.len - len;
        const top = self.stateStack.items.len - len;

        if (nodeStore) {
            // An element that consumed nothing starts at the next token,
            // past the blanks after this reduction's last token (lastEnd).
            // When the reduction consumed something, place its trailing
            // empty elements at lastEnd so that spans nest.
            if (len > 0 and self.starts[base] < self.lastEnd) {
                var k = base + len;
                while (k > base and self.starts[k - 1] > self.lastEnd) : (k -= 1) {
                    self.starts[k - 1] = self.lastEnd;
                    self.placeEmpty(self.valueStack.items[k - 1], self.lastEnd);
                }
            }
            self.reduction.rule = ruleId;
            self.reduction.start = if (len > 0) self.starts[base] else self.current.pos;
            if (elemEnds) {
                self.reduction.base = @intCast(base);
                self.reduction.firstNode = self.nodes.len;
            }
        }

        // The action reads its elements in place on the value stack; the
        // result then replaces them (a reduction of nothing pushes it). A
        // rule whose value is nil or one of its elements has no action.
        // A list passed on keeps its spare, to grow in place in the rule
        // that extends it.
        const result: Sexp = switch (ruleValue[ruleId]) {
            0 => executeAction(self, ruleId, self.valueStack.items[base..]),
            1 => .nil,
            else => |n| blk: {
                if (n > 2) {
                    self.spares[base] = self.spares[base + n - 2];
                    self.spares[base + n - 2] = .none;
                }
                break :blk self.valueStack.items[base + n - 2];
            },
        };
        if (self.outOfMemory) return error.OutOfMemory;
        const next = getAction(self.stateStack.items[top - 1], ruleLhs[ruleId]);
        std.debug.assert(next > 0); // every reduction has a goto

        if (nodeStore) try self.recordSides(ruleId, result);
        if (len > 0) {
            self.valueStack.items.len = base + 1;
            self.valueStack.items[base] = result;
            self.stateStack.items.len = top + 1;
            self.stateStack.items[top] = @intCast(next);
            // starts[base] already holds the reduction's start (its first
            // element's).
            if (elemEnds) self.ends[base] = self.lastEnd;
        } else {
            try self.pushEntry(@intCast(next), result, self.reduction.start, self.lastEnd);
        }
    }

    /// Move the nodes of an empty value (a subtree that consumed nothing)
    /// to `at`.
    fn placeEmpty(self: *BaseParser, value: Sexp, at: u32) void {
        // Most empty values are leaves or flat lists: no walk.
        if (!self.placeNode(value, at)) return;
        for (value.list.items()) |item| {
            if (item == .list) break;
        } else return;
        var walk: Walk = .{};
        defer walk.deinit();
        var s = value;
        while (true) {
            if (self.placeNode(s, at)) walk.push(s.list.items()) catch {
                self.outOfMemory = true;
                return;
            };
            s = walk.next() orelse return;
        }
    }

    /// Place an empty list's node at `at`; whether its items need placing
    /// too (false for a non-list, or a node already placed).
    inline fn placeNode(self: *BaseParser, s: Sexp, at: u32) bool {
        if (s != .list) return false;
        const id = s.list.id;
        if (id != 0 and id < self.nodes.len) {
            const info = self.nodes.at(id);
            if (!info.span.isEmpty()) return false;
            info.span = .{ .start = at, .end = at };
        }
        return true;
    }

    /// Fetch the next token, moving trivia to the trivia channel.
    fn advance(self: *BaseParser) !void {
        self.setCurrent(self.lexer.next());
        if (hasTrivia) try self.skipTrivia();
    }

    /// Drop the current token, and its lexer id with it.
    fn deleteToken(self: *BaseParser) !void {
        _ = takeLexerId(&self.lexer);
        try self.advance();
    }

    fn skipTrivia(self: *BaseParser) !void {
        while (isTrivia(self.current.cat)) {
            try self.triviaTokens.append(self.allocator(), self.current);
            _ = takeLexerId(&self.lexer);
            self.setCurrent(self.lexer.next());
        }
    }

    /// Tokens of the grammar's `@trivia` kinds, in source order.
    pub fn trivia(self: *const BaseParser) []const Token {
        return self.triviaTokens.items;
    }

    // -------------------------------------------------------------------------
    // Node store, spans, side-band roles
    // -------------------------------------------------------------------------

    /// The span of the reduction in progress.
    inline fn reductionSpan(self: *const BaseParser) Span {
        return spanOf(.{ .start = self.reduction.start, .end = self.lastEnd });
    }

    /// The span of an extent: empty at its start when it consumed no
    /// tokens.
    fn spanOf(extent: Span) Span {
        return if (extent.start < extent.end) extent else .{ .start = extent.start, .end = extent.start };
    }

    /// The extent of elements lo..hi (0-based, inclusive) of the reduction.
    fn elemsExtent(self: *const BaseParser, lo: usize, hi: usize) Span {
        if (!elemEnds) @compileError("element extents need elemEnds");
        const base = self.reduction.base;
        return .{ .start = self.starts[base + lo], .end = self.ends[base + hi] };
    }

    /// A new node id for a list the current reduction builds.
    inline fn newNodeId(self: *BaseParser) NodeId {
        if (!nodeStore) return 0;
        return self.addNode(self.reductionSpan());
    }

    inline fn addNode(self: *BaseParser, extent: Span) NodeId {
        return self.nodes.add(self.allocator(), .{ .span = extent, .rule = self.reduction.rule }) catch {
            self.outOfMemory = true;
            return 0;
        };
    }

    fn recordSides(self: *BaseParser, ruleId: u16, result: Sexp) !void {
        if (!elemEnds) return;
        const labels = ruleSideLabels(ruleId);
        if (labels.len == 0 or result != .list) return;
        const id = result.list.id;
        if (id == 0 or id < self.reduction.firstNode) return;
        for (labels) |label| {
            try self.sides.append(self.allocator(), .{
                .node = id,
                .role = label.role,
                .span = spanOf(self.elemsExtent(label.pass, label.pass)),
            });
        }
    }

    /// Source span of a value. Leaves span their token. A list with a node
    /// id spans its reduction: first to last consumed token, including
    /// tokens (keywords, punctuation) that are not in the tree. Any other
    /// list spans the hull of its children: from the least start to the
    /// greatest end of the non-empty spans below it, whatever order an
    /// action put them in. Panics if the walk runs out of memory (its stack
    /// is far smaller than the tree it walks).
    pub fn span(self: *const BaseParser, s: Sexp) Span {
        if (self.ownSpan(s)) |own| return own;
        var hull: ?Span = null;
        var walk: Walk = .{};
        defer walk.deinit();
        var x = s;
        while (true) {
            if (self.ownSpan(x)) |own| {
                if (!own.isEmpty()) hull = if (hull) |h| .{ .start = @min(h.start, own.start), .end = @max(h.end, own.end) } else own;
            } else walk.push(x.list.items()) catch @panic("out of memory");
            x = walk.next() orelse return hull orelse .empty;
        }
    }

    /// The span of a value that is not a hull: a leaf's, a node's, empty
    /// for any other non-list; null for a list without a node id.
    fn ownSpan(self: *const BaseParser, s: Sexp) ?Span {
        return switch (s) {
            .src => |x| .{ .start = x.pos, .end = x.pos + x.len },
            .list => |l| if (nodeStore and l.id != 0 and l.id < self.nodes.len) self.nodes.at(l.id).span else null,
            else => .empty,
        };
    }

    /// The rule that built a list node (null without a node id, or for a
    /// node a lang wrapper made with `newNode`).
    pub fn ruleOf(self: *const BaseParser, s: Sexp) ?u16 {
        if (!nodeStore or s != .list) return null;
        const id = s.list.id;
        if (id == 0 or id >= self.nodes.len) return null;
        const rule = self.nodes.at(id).rule;
        return if (rule == wrapperRule) null else rule;
    }

    /// The rule recorded for nodes built outside a reduction.
    const wrapperRule = std.math.maxInt(u16);

    /// A `(tag children...)` node built outside a reduction, e.g. by a lang
    /// `Parser` wrapper for an `@wrapper` kind: allocated in the parser's
    /// arena, with a fresh node id recording `extent` as its span (so
    /// `span`, facts and `ir` accessors work as for parsed nodes; `ruleOf`
    /// is null). Without a node store the node has no id.
    pub fn newNode(self: *BaseParser, tag: Tag, children: []const Sexp, extent: Span) !Sexp {
        const out = try self.allocItems(children.len + 1);
        out[0] = .{ .tag = tag };
        @memcpy(out[1..], children);
        return .{ .list = List.withId(out, try self.wrapperNodeId(extent)) };
    }

    /// An untagged list built outside a reduction (a `group` value), with a
    /// node id recording `extent` like `newNode`.
    pub fn newList(self: *BaseParser, items: []const Sexp, extent: Span) !Sexp {
        const out = try self.allocator().dupe(Sexp, items);
        return .{ .list = List.withId(out, try self.wrapperNodeId(extent)) };
    }

    fn wrapperNodeId(self: *BaseParser, extent: Span) !NodeId {
        if (!nodeStore) return 0;
        try self.ensureNodeStore();
        return self.nodes.add(self.allocator(), .{ .span = extent, .rule = wrapperRule });
    }

    /// Start the node store with its unused entry 0 (node ids are 1-based).
    fn ensureNodeStore(self: *BaseParser) !void {
        if (nodeStore and self.nodes.len == 0) _ = try self.nodes.add(self.allocator(), .{ .span = .empty, .rule = 0 });
    }

    /// Number of node ids in use (ids run 1 .. nodeCount()).
    pub fn nodeCount(self: *const BaseParser) u32 {
        return self.nodes.len -| 1;
    }

    /// The side-band roles recorded for node `id`.
    fn sidesOf(self: *const BaseParser, id: NodeId) []const SideEntry {
        const all = self.sides.items;
        var lo: usize = 0;
        var hi: usize = all.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (all[mid].node < id) lo = mid + 1 else hi = mid;
        }
        var end = lo;
        while (end < all.len and all[end].node == id) end += 1;
        return all[lo..end];
    }

    /// The span a side-band role of `s` recorded (e.g. the `=` of a `set`).
    pub fn sideRole(self: *const BaseParser, s: Sexp, role: Role) ?Span {
        if (s != .list or s.list.id == 0) return null;
        for (self.sidesOf(s.list.id)) |e| if (e.role == role) return e.span;
        return null;
    }

    // -------------------------------------------------------------------------
    // Tree builders (called by the generated actions)
    // -------------------------------------------------------------------------

    /// Record an allocation failure; the reduction then fails the parse.
    fn oomNil(self: *BaseParser) Sexp {
        self.outOfMemory = true;
        return .nil;
    }

    /// Whether an untagged list can reach the tree (and so gets a node id)
    /// or is only ever spread into another list (plumbing: no node id).
    /// The generator decides per rule (see codegen/actions.zig).
    const ListUse = enum { tree, spread };

    /// A list node of the current reduction over freshly built `items`.
    inline fn node(self: *BaseParser, items: []const Sexp, comptime use: ListUse) Sexp {
        return .{ .list = List.withId(items, if (use == .tree) self.newNodeId() else 0) };
    }

    /// A list node over exactly `items` (fixed positions).
    fn build(self: *BaseParser, items: []const Sexp, comptime use: ListUse) Sexp {
        const out = self.allocItems(items.len) catch return self.oomNil();
        @memcpy(out, items);
        return self.node(out, use);
    }

    /// A nested node of the current reduction: its span covers just the
    /// elements lo..hi (0-based, inclusive) it references.
    fn nested(self: *BaseParser, s: Sexp, lo: usize, hi: usize) Sexp {
        if (nodeStore and s == .list and s.list.id != 0) {
            self.nodes.at(s.list.id).span = spanOf(self.elemsExtent(lo, hi));
        }
        return s;
    }

    /// A nested node that references no elements: empty, at the start of
    /// the reduction.
    fn nestedEmpty(self: *BaseParser, s: Sexp) Sexp {
        if (nodeStore and s == .list and s.list.id != 0) {
            const at = self.reduction.start;
            self.nodes.at(s.list.id).span = .{ .start = at, .end = at };
        }
        return s;
    }

    /// Length of `items` without trailing nils (all of it when positions
    /// are fixed by a schema).
    fn trimmedLen(items: []const Sexp) usize {
        var len = items.len;
        if (!keepTrailingNils) {
            while (len > 0 and items[len - 1] == .nil) len -= 1;
        }
        return len;
    }

    /// `~N` of an element that is no leaf: an empty leaf where element `i`
    /// starts. Without a node store element starts are not kept: it is
    /// placed at the first element from `i` on that spans something, else
    /// at the next token.
    fn emptyLeaf(self: *BaseParser, pass: []const Sexp, i: usize) Sexp {
        const pos = if (nodeStore)
            self.starts[self.stackIndex(pass) + i]
        else for (pass[i..]) |e| {
            const s = self.span(e);
            if (!s.isEmpty()) break s.start;
        } else self.current.pos;
        return .{ .src = .{ .pos = pos, .len = 0, .id = 0 } };
    }

    /// `()`: an empty list.
    fn emptyList(self: *BaseParser, comptime use: ListUse) Sexp {
        return self.node(&.{}, use);
    }

    /// `[head, ...tail]`
    fn spreadList(self: *BaseParser, head: Sexp, tail: Sexp, comptime use: ListUse) Sexp {
        const rest = tail.items();
        const out = self.allocItems(rest.len + 1) catch return self.oomNil();
        out[0] = head;
        @memcpy(out[1..], rest);
        return self.node(out, use);
    }

    /// A list `extendBy` opened for an action that appends to it.
    const Extension = struct { items: [*]Sexp, len: usize, capacity: usize };

    /// Open a list holding the items of element `n` (a list, else nothing)
    /// with room for `extra` more. A list `keepExtended` left on the value
    /// stack is reused with its spare capacity, growing in place when it
    /// is the allocator's last block, so a left-recursive list grows in
    /// amortized O(1) per element; it keeps its node id.
    fn extendBy(self: *BaseParser, pass: []const Sexp, n: usize, extra: usize) error{OutOfMemory}!Extension {
        const base = pass[n];
        const items: []const Sexp = if (base == .list) base.list.items() else &.{};
        const need = items.len + extra;
        const spare = &self.spares[self.stackIndex(pass) + n];
        if (items.len > 0 and spare.items == items.ptr and spare.len == items.len) {
            const buf: [*]Sexp = @constCast(items.ptr);
            const capacity = spare.capacity;
            spare.* = .none;
            if (need <= capacity) return .{ .items = buf, .len = items.len, .capacity = capacity };
            const start = @intFromPtr(buf);
            const grown = growCapacity(capacity, need);
            if (start + capacity * @sizeOf(Sexp) == self.bumpPos and start + grown * @sizeOf(Sexp) <= self.bumpEnd) {
                self.bumpPos = start + grown * @sizeOf(Sexp);
                return .{ .items = buf, .len = items.len, .capacity = grown };
            }
        }
        const capacity = growCapacity(0, need);
        const out = try self.allocItems(capacity);
        @memcpy(out[0..items.len], items);
        return .{ .items = out.ptr, .len = items.len, .capacity = capacity };
    }

    /// A capacity of at least `need`, grown from `capacity` by half plus 2.
    fn growCapacity(capacity: usize, need: usize) usize {
        var c = capacity;
        while (c < need) c += c / 2 + 2;
        return c;
    }

    /// Finish a list from `extendBy(pass, n, ...)` holding `len` items,
    /// without its trailing nils unless `keepNils` (a list of one item per
    /// element: `X*`, `L(X?)`, ...), recording its spare capacity where
    /// the reduction's value goes. It takes over the node id of element
    /// `n` (still on the value stack), so that nested extensions each keep
    /// their own.
    fn keepExtended(self: *BaseParser, out: Extension, len: usize, pass: []const Sexp, n: usize, comptime use: ListUse, comptime keepNils: bool) Sexp {
        const items = if (keepNils) out.items[0..len] else out.items[0..trimmedLen(out.items[0..len])];
        self.spares[self.stackIndex(pass)] = .{ .items = items.ptr, .len = @intCast(items.len), .capacity = @intCast(out.capacity) };
        var id: NodeId = 0;
        if (nodeStore and use == .tree) {
            const base = pass[n];
            id = if (base == .list) base.list.id else 0;
            if (id != 0) {
                self.nodes.at(id).* = .{ .span = self.reductionSpan(), .rule = self.reduction.rule };
            } else id = self.newNodeId();
        }
        return .{ .list = List.withId(items, id) };
    }

    /// Finish a list allocated at its length and filled.
    fn finishItems(self: *BaseParser, out: []Sexp, comptime use: ListUse) Sexp {
        return self.node(out[0..trimmedLen(out)], use);
    }

    /// An item of a list an action builds from its elements alone.
    const Item = union(enum) { elem: u16, tag: Tag, nil };

    /// A list node over `items`, known at compile time (so each call
    /// stores its items directly); unless positions are fixed (`trim`
    /// false, or a schema), without its trailing nils.
    fn buildOf(self: *BaseParser, comptime items: []const Item, pass: []const Sexp, comptime use: ListUse, comptime trim: bool) Sexp {
        const out = self.allocItems(items.len) catch return self.oomNil();
        inline for (out[0..items.len], items) |*o, it| o.* = switch (it) {
            .elem => |i| pass[i],
            .tag => |t| .{ .tag = t },
            .nil => .nil,
        };
        return self.node(if (trim) out[0..trimmedLen(out)] else out, use);
    }

    /// `(tag items...)`
    fn sexp(self: *BaseParser, tag: Tag, items: []const Sexp) Sexp {
        const len = trimmedLen(items);
        const out = self.allocItems(len + 1) catch return self.oomNil();
        out[0] = .{ .tag = tag };
        @memcpy(out[1..], items[0..len]);
        return self.node(out, .tree);
    }

    /// `(tag ...spread)`
    fn sexpSpread(self: *BaseParser, tag: Tag, spread: Sexp) Sexp {
        return self.sexp(tag, spread.items());
    }

    /// `(tag pos ...spread)`; just `(tag)` when both are empty (and
    /// positions are not fixed by a schema).
    fn sexpPosSpread(self: *BaseParser, tag: Tag, pos: Sexp, spread: Sexp) Sexp {
        const items = spread.items();
        const len = trimmedLen(items);
        const bare = !keepTrailingNils and pos == .nil and len == 0;
        const out = self.allocItems(if (bare) 1 else len + 2) catch return self.oomNil();
        out[0] = .{ .tag = tag };
        if (!bare) {
            out[1] = pos;
            @memcpy(out[2..], items[0..len]);
        }
        return self.node(out, .tree);
    }

    // -------------------------------------------------------------------------
    // Diagnostics
    // -------------------------------------------------------------------------

    fn recordFailure(self: *BaseParser, state: u16, sym: u16) void {
        const tok = self.current;
        self.failure = .{
            .span = .{ .start = tok.pos, .end = tok.pos + tok.len },
            .symbol = sym,
            .cat = tok.cat,
            .state = state,
        };
    }

    /// The error of the last failed parse (the first one, for
    /// `parseTolerant`).
    pub fn lastError(self: *const BaseParser) ?Failure {
        return self.failure;
    }

    /// 1-based line and column of a byte offset.
    pub fn lineCol(self: *const BaseParser, pos: u32) struct { line: u32, col: u32 } {
        const end: usize = @min(pos, self.source.len);
        var line: u32 = 1;
        var lineStart: usize = 0;
        for (self.source[0..end], 0..) |c, i| {
            if (c == '\n') {
                line += 1;
                lineStart = i + 1;
            }
        }
        return .{ .line = line, .col = @intCast(end - lineStart + 1) };
    }

    /// `line:col: expected A, B or C, got D` for the last error.
    pub fn writeError(self: *const BaseParser, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const f = self.failure orelse return;
        const at = self.lineCol(f.span.start);
        try w.print("{d}:{d}: expected ", .{ at.line, at.col });
        var buf: [maxExpected][]const u8 = undefined;
        const want = expectedNames(f.state, &buf);
        for (want, 0..) |name, i| {
            if (i > 0) try w.writeAll(if (i + 1 == want.len) " or " else ", ");
            try w.writeAll(name);
        }
        if (want.len == 0) try w.writeAll("nothing");
        try w.writeAll(", got ");
        const got = symbolName(f.symbol);
        try w.writeAll(if (f.symbol == errorSymbol or got.len == 0) @tagName(f.cat) else got);
    }

    /// `Parse error at ` and `writeError`'s text on standard error.
    pub fn printError(self: *const BaseParser) void {
        var buffer: [256]u8 = undefined;
        const stderr = std.debug.lockStderr(&buffer);
        defer std.debug.unlockStderr();
        const w = &stderr.file_writer.interface;
        w.writeAll("Parse error at ") catch return;
        self.writeError(w) catch return;
        w.writeByte('\n') catch return;
    }

    /// What `state` accepts, reader-named: the `@errors` rules it waits
    /// for, then the tokens none of them begins with.
    pub fn expected(state: u16) []const u16 {
        return expectedIn(state);
    }

    /// The reader names of what `state` accepts, in `expected` order, each
    /// once (tokens sharing an `@display` name are named once), in `buf`:
    /// `[maxExpected][]const u8` always has room.
    pub fn expectedNames(state: u16, buf: [][]const u8) []const []const u8 {
        var n: usize = 0;
        for (expectedIn(state)) |sym| {
            const name = symbolName(sym);
            if (name.len == 0) continue;
            for (buf[0..n]) |seen| {
                if (std.mem.eql(u8, seen, name)) break;
            } else {
                buf[n] = name;
                n += 1;
            }
        }
        return buf[0..n];
    }

    /// The reader-facing name of a grammar symbol, as `writeError` prints
    /// it: its `@errors` or `@display` name, a literal as written, a token
    /// name in lower case; empty for other rules.
    pub fn symbolText(sym: u16) []const u8 {
        return symbolName(sym);
    }

    // -------------------------------------------------------------------------
    // Tolerant repair
    // -------------------------------------------------------------------------

    /// Whether the inserted `insert`, then the current token as `current`
    /// (when given), can be consumed from the current state; `current` is
    /// decided as `actionFor` decides it, with its `X "c"` override (it
    /// keeps the symbol `@as` promoted it to here). The simulation leaves
    /// the state stack as it is: reductions pop the states it pushed
    /// (`scratch`), then hide states of the real stack (`depth` of them
    /// stay in view).
    fn accepts(self: *BaseParser, insert: u16, current: ?u16) !bool {
        const pushed = &self.scratch;
        pushed.clearRetainingCapacity();
        var depth = self.stateStack.items.len;
        for ([_]?u16{ insert, current }, 0..) |s, i| {
            const sym = s orelse break;
            while (true) {
                const top = pushed.last() orelse self.stateStack.items[depth - 1];
                var action = getAction(top, sym);
                if (xExcludes.len > 0 and action == hinted) action = hintedAction(top, sym, i == 1 and self.current.pre == 0);
                if (action == 0) return false;
                if (action == -1) return true;
                if (action > 0) {
                    try pushed.append(self.allocator(), @intCast(action));
                    break;
                }
                const rule: u16 = @intCast(-action - 2);
                const fromPushed = @min(ruleLen[rule], pushed.items.len);
                pushed.shrinkRetainingCapacity(pushed.items.len - fromPushed);
                depth -= ruleLen[rule] - fromPushed;
                const next = getAction(pushed.last() orelse self.stateStack.items[depth - 1], ruleLhs[rule]);
                if (next <= 0) return false;
                try pushed.append(self.allocator(), @intCast(next));
            }
        }
        return true;
    }

    // -------------------------------------------------------------------------
    // Facts export
    // -------------------------------------------------------------------------

    /// Write the tree as flat facts, one per line, in pre-order:
    ///   (node ID KIND START END)        every list with a node id
    ///   (role ID ROLE CHILD...)         each non-nil child (a rest role
    ///                                   lists all its children)
    ///   (side ID ROLE START LEN)        each side-band role
    /// ROLE is the schema role name, else the child's index in the list.
    /// KIND is the head tag, or `group` for an untagged list. A CHILD is a
    /// node id, `leaf POS LEN`, `tag NAME`, `str "TEXT"`, or `(CHILD...)`
    /// for a list without a node id. error.WriteFailed also reports the
    /// walk running out of memory.
    pub fn writeFacts(self: *const BaseParser, w: *std.Io.Writer, root: Sexp) std.Io.Writer.Error!void {
        if (!nodeStore) @compileError("writeFacts needs the node store (@schema or --spans)");
        var walk: Walk = .{};
        defer walk.deinit();
        var s = root;
        while (true) {
            if (s == .list) {
                if (s.list.id != 0) try self.nodeFacts(w, s);
                walk.push(s.list.items()) catch return error.WriteFailed;
            }
            s = walk.next() orelse return;
        }
    }

    /// The facts of one node: its `node` line, its `role` and `side` lines.
    fn nodeFacts(self: *const BaseParser, w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!void {
        const l = s.list;
        const items = l.items();
        const k = s.kind();
        const sp = self.span(s);
        try w.print("(node {d} ", .{l.id});
        if (k) |t| try writeName(w, nameOf(t)) else try w.writeAll("group");
        try w.print(" {d} {d})\n", .{ sp.start, sp.end });
        var i: usize = if (k != null) 1 else 0;
        while (i < items.len) : (i += 1) {
            if (k) |t| if (restRoleOf(t)) |rest| if (i >= rest.slot) {
                try w.print("(role {d} ", .{l.id});
                try writeName(w, nameOf(rest.role));
                for (items[i..]) |child| {
                    try w.writeByte(' ');
                    try factChild(w, child);
                }
                try w.writeAll(")\n");
                break;
            };
            if (items[i] == .nil) continue;
            try w.print("(role {d} ", .{l.id});
            if (if (k) |t| roleAt(t, i) else null) |role| try writeName(w, nameOf(role)) else try w.print("{d}", .{i});
            try w.writeByte(' ');
            try factChild(w, items[i]);
            try w.writeAll(")\n");
        }
        for (self.sidesOf(l.id)) |e| {
            try w.print("(side {d} ", .{l.id});
            try writeName(w, nameOf(e.role));
            try w.print(" {d} {d})\n", .{ e.span.start, e.span.len() });
        }
    }

    fn factChild(w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!void {
        try writeNested(s, w, {}, factAtom);
    }

    fn factAtom(_: void, w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!?[]const Sexp {
        switch (s) {
            .nil => try w.writeAll("_"),
            .tag => |t| {
                try w.writeAll("tag ");
                try writeName(w, nameOf(t));
            },
            .src => |x| try w.print("leaf {d} {d}", .{ x.pos, x.len }),
            .str => |x| {
                try w.writeAll("str ");
                try writeQuoted(w, x);
            },
            .list => |l| if (l.id != 0) try w.print("{d}", .{l.id}) else return l.items(),
        }
        return null;
    }

    /// A name as a bare symbol, or quoted when it has s-expression syntax.
    fn writeName(w: *std.Io.Writer, name: []const u8) std.Io.Writer.Error!void {
        const plain = name.len > 0 and for (name) |c| {
            if (c <= ' ' or c == '(' or c == ')' or c == '"' or c == '\\' or c == 0x7f) break false;
        } else true;
        if (plain) try w.writeAll(name) else try writeQuoted(w, name);
    }

    fn writeQuoted(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
        try w.writeByte('"');
        for (text) |c| switch (c) {
            '"', '\\' => {
                try w.writeByte('\\');
                try w.writeByte(c);
            },
            '\n' => try w.writeAll("\\n"),
            '\t' => try w.writeAll("\\t"),
            else => if (c < ' ' or c == 0x7f) try w.print("\\x{x:0>2}", .{c}) else try w.writeByte(c),
        };
        try w.writeByte('"');
    }
};

// @end

// @section ir

// =============================================================================
// IR accessors (from @schema)
// =============================================================================

// Inside `ir`, generated kind and role names (a kind `tag` has the view
// `ir.Tag`) could shadow the module's own names, so `ir` refers to them
// through these aliases, whose names no kind or role can take.
const @"ir.Sexp" = Sexp;
const @"ir.Tag" = Tag;
const @"ir.Role" = Role;

/// Role-based access to schema nodes. `get`/`rest` look the slot up by the
/// node's kind; the per-kind views (`ir.Set.target(node)`) are resolved at
/// compile time. Asking for a role the node's kind does not have panics in
/// safety-checked builds and yields nil (or no items) otherwise.
pub const ir = struct {
    /// The child in `role` (nil when absent).
    pub fn get(node: @"ir.Sexp", role: @"ir.Role") @"ir.Sexp" {
        const k = kindFor(node, "ir.get", role) orelse return .nil;
        const at = slotOf(k, role) orelse return missing(k, role, "ir.get", @as(@"ir.Sexp", .nil));
        const items = node.list.items();
        return if (at < items.len) items[at] else .nil;
    }

    /// The children in rest role `role`.
    pub fn rest(node: @"ir.Sexp", role: @"ir.Role") []const @"ir.Sexp" {
        const k = kindFor(node, "ir.rest", role) orelse return &.{};
        const at = restSlotOf(k, role) orelse return missing(k, role, "ir.rest", @as([]const @"ir.Sexp", &.{}));
        const items = node.list.items();
        return if (at < items.len) items[at..] else &.{};
    }

    /// Whether nodes of `kind` have `role` (slot or rest role).
    pub fn has(kind: @"ir.Tag", role: @"ir.Role") bool {
        return slotOf(kind, role) != null or restSlotOf(kind, role) != null;
    }

    /// The slot of `role` in nodes of `kind` (the head is slot 0), at
    /// compile time; a compile error when `kind` has no such slot role. For
    /// lang Parser wrappers that build or rewrite nodes:
    /// `items[ir.slot(.set, .value)] = v`.
    pub fn slot(comptime kind: @"ir.Tag", comptime role: @"ir.Role") usize {
        return comptime slotOf(kind, role) orelse
            @compileError("kind '" ++ @tagName(kind) ++ "' has no slot role '" ++ @tagName(role) ++ "'");
    }

    /// The first slot of rest role `role` in nodes of `kind`, at compile
    /// time; a compile error when `kind` has no such rest role.
    pub fn restSlot(comptime kind: @"ir.Tag", comptime role: @"ir.Role") usize {
        return comptime restSlotOf(kind, role) orelse
            @compileError("kind '" ++ @tagName(kind) ++ "' has no rest role '" ++ @tagName(role) ++ "'");
    }

    /// The fixed length of `kind` nodes: the head plus one slot per slot
    /// role (rest children follow).
    pub fn width(comptime kind: @"ir.Tag") usize {
        return comptime blk: {
            var n: usize = 1;
            while (roleAt(kind, n) != null) n += 1;
            break :blk n;
        };
    }

    fn kindFor(node: @"ir.Sexp", comptime what: []const u8, role: @"ir.Role") ?@"ir.Tag" {
        if (node.kind()) |k| return k;
        if (@import("builtin").optimize.runtimeSafety()) std.debug.panic(what ++ "(.{s}): not a schema node: {s}", .{ @tagName(role), @tagName(node) });
        return null;
    }

    fn missing(kind: @"ir.Tag", role: @"ir.Role", comptime what: []const u8, value: anytype) @TypeOf(value) {
        if (@import("builtin").optimize.runtimeSafety()) {
            const hint = if (slotOf(kind, role) != null) " (a slot role; use ir.get)" else if (restSlotOf(kind, role) != null) " (a rest role; use ir.rest)" else "";
            std.debug.panic(what ++ ": kind '{s}' has no role '{s}'{s}", .{ @tagName(kind), @tagName(role), hint });
        }
        return value;
    }

    // @slot views
};

/// Slot `slot` of `node`, a node of `kind` (checked in safety builds).
fn @"ir.at"(node: Sexp, comptime kind: Tag, comptime slot: usize, comptime what: []const u8) Sexp {
    @"ir.check"(node, kind, what);
    const items = node.items();
    return if (slot < items.len) items[slot] else .nil;
}

/// The children of `node` from `slot` on.
fn @"ir.restAt"(node: Sexp, comptime kind: Tag, comptime slot: usize, comptime what: []const u8) []const Sexp {
    @"ir.check"(node, kind, what);
    const items = node.items();
    return if (slot < items.len) items[slot..] else &.{};
}

fn @"ir.check"(node: Sexp, comptime kind: Tag, comptime what: []const u8) void {
    if (@import("builtin").optimize.runtimeSafety() and !node.isKind(kind)) {
        const actual = if (node.kind()) |k| @tagName(k) else @tagName(node);
        std.debug.panic(what ++ ": node is '{s}', not '" ++ @tagName(kind) ++ "'", .{actual});
    }
}

// @end

// =============================================================================
// Test fixture (not emitted)
//
// The grammar (tables generated by Nexus; symbol ids noted per line):
//
//   prog!  = stmts                  → (prog ...1)
//   stmts  = stmt                   → (1)
//          | stmts NEWLINE stmt     → (...1 3)
//   stmt   = IDENT "=" expr         → (set 1 3)   side label: eq = 2
//          | expr                   → 1
//   expr   = term
//          | expr "+" term          → (add 1 3)
//   term   = IDENT
//          | "(" expr ")"           → 2
//
// with `#...` comments as trivia, a `@schema` of set/add/prog, and
// `@repair holes IDENT, terminator NEWLINE`.
// =============================================================================

const Tag = enum(u8) { prog, set, add };
const Role = enum(u16) { target, value, left, right, stmts, eq };
const Start = enum(u16) { prog = 3 };

const TokenCat = enum(u8) { ident, eq, plus, lparen, rparen, newline, comment, eof, err };
const Token = struct { pos: u32, len: u16, cat: TokenCat, pre: u8 };

const BaseLexer = struct {
    source: []const u8,
    pos: u32 = 0,
    aux: u16 = 0,

    fn init(source: []const u8) BaseLexer {
        return .{ .source = source };
    }

    fn next(self: *BaseLexer) Token {
        const start0 = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] == ' ') self.pos += 1;
        const pre: u8 = @intCast(self.pos - start0);
        const start = self.pos;
        if (self.pos >= self.source.len) return .{ .pos = start, .len = 0, .cat = .eof, .pre = pre };
        const c = self.source[self.pos];
        self.pos += 1;
        const cat: TokenCat = switch (c) {
            '=' => .eq,
            '+' => .plus,
            '(' => .lparen,
            ')' => .rparen,
            '\n' => .newline,
            '#' => blk: {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
                break :blk .comment;
            },
            'a'...'z' => blk: {
                while (self.pos < self.source.len and self.source[self.pos] >= 'a' and self.source[self.pos] <= 'z') self.pos += 1;
                // The token id attribute: identifiers starting with `q` carry id 7.
                if (c == 'q') self.aux = 7;
                break :blk .ident;
            },
            else => .err,
        };
        return .{ .pos = start, .len = @intCast(self.pos - start), .cat = cat, .pre = pre };
    }
};
const Lexer = BaseLexer;

const nodeStore = true;
const keepTrailingNils = true;
const hasTrivia = true;
const hasRepair = true;
const asGroups = 0;
const elemEnds = true;
const numSymbols = 16;
const endSymbol: u16 = 1;
const errorSymbol: u16 = 2;
const maxExpected = 4;
const xExcludes = [_]struct { sym: u16, shift: u16, reduce: i16 }{};
const xExcludeStart = [_]u32{};

// 0 $accept, 1 $end, 2 error, 3 prog, 4 stmts, 5 stmt, 6 expr, 7 term,
// 8 NEWLINE, 9 IDENT, 10 "=", 11 "+", 12 "(", 13 ")", 14 prog!, 15 $accept_prog
const ruleLhs = [_]u16{ 3, 4, 4, 5, 5, 6, 6, 7, 7, 15 };
const ruleLen = [_]u8{ 2, 1, 3, 3, 1, 1, 3, 1, 3, 2 };
const ruleValue = [_]u8{ 0, 0, 0, 0, 2, 2, 0, 2, 3, 0 };

const sparse = [_][]const i16{
    &.{ 3, 1, 14, 2 },
    &.{ 1, -1 },
    &.{ 4, 4, 5, 8, 6, 5, 7, 7, 9, 6, 12, 9 },
    &.{ 1, -1 },
    &.{ 1, -2, 8, 10 },
    &.{ 1, -6, 8, -6, 11, 11 },
    &.{ 1, -9, 8, -9, 10, 12, 11, -9 },
    &.{ 1, -7, 8, -7, 11, -7, 13, -7 },
    &.{ 1, -3, 8, -3 },
    &.{ 6, 13, 7, 7, 9, 14, 12, 9 },
    &.{ 5, 15, 6, 5, 7, 7, 9, 6, 12, 9 },
    &.{ 7, 16, 9, 14, 12, 9 },
    &.{ 6, 17, 7, 7, 9, 14, 12, 9 },
    &.{ 11, 11, 13, 18 },
    &.{ 1, -9, 8, -9, 11, -9, 13, -9 },
    &.{ 1, -4, 8, -4 },
    &.{ 1, -8, 8, -8, 11, -8, 13, -8 },
    &.{ 1, -5, 8, -5, 11, 11 },
    &.{ 1, -10, 8, -10, 11, -10, 13, -10 },
};

const parseTable = blk: {
    var t: [sparse.len][numSymbols]i16 = @splat(@splat(0));
    for (sparse, 0..) |row, state| {
        var i: usize = 0;
        while (i < row.len) : (i += 2) t[state][@intCast(row[i])] = row[i + 1];
    }
    break :blk t;
};

// Expected lists, hand-built from the table with `expr` named "an
// expression": {}, {expr}, {IDENT "("}, {$end NEWLINE},
// {$end NEWLINE "=" "+"}, {$end NEWLINE "+"}, {"+" ")"}.
const expectedSymbols = [_]u16{ 6, 9, 12, 1, 8, 1, 8, 10, 11, 1, 8, 11, 11, 13 };
const expectedOffsets = [_]u32{ 0, 0, 1, 3, 5, 9, 12, 14 };
const expectedOf = [_]u16{ 0, 0, 1, 0, 3, 5, 4, 0, 5, 1, 1, 2, 1, 6, 0, 5, 0, 5, 0 };

fn startState(_: Start) u16 {
    return 0;
}

fn startMarker(_: Start) u16 {
    return 14;
}

fn isTrivia(cat: TokenCat) bool {
    return cat == .comment;
}

fn promote(_: *BaseParser, _: Token) u16 {
    unreachable; // no @as group
}

fn tokenToSymbol(token: Token) u16 {
    return switch (token.cat) {
        .eof => 1,
        .newline => 8,
        .ident => 9,
        .eq => 10,
        .plus => 11,
        .lparen => 12,
        .rparen => 13,
        else => 2,
    };
}

fn symbolName(sym: u16) []const u8 {
    return switch (sym) {
        1 => "end of input",
        6 => "an expression",
        8 => "newline",
        9 => "identifier",
        10 => "\"=\"",
        11 => "\"+\"",
        12 => "\"(\"",
        13 => "\")\"",
        else => "",
    };
}

// Repair candidates, hand-built: the hole (IDENT) where the state accepts
// it (states 2, 9-12), else NEWLINE (states 4-8, 14-18).
const repairTokens = [_]u16{ 9, 8, 8, 8, 8, 8, 9, 9, 9, 9, 8, 8, 8, 8, 8 };
const repairOffsets = [_]u32{ 0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15 };

fn repairClass(sym: u16) RepairClass {
    return switch (sym) {
        9 => .hole,
        8 => .terminator,
        else => .none,
    };
}

fn ruleSideLabels(rule: u16) []const SideLabel {
    return switch (rule) {
        3 => &.{.{ .role = .eq, .pass = 1 }},
        else => &.{},
    };
}

fn slotOf(kind: Tag, role: Role) ?usize {
    return switch (kind) {
        .set => switch (role) {
            .target => 1,
            .value => 2,
            else => null,
        },
        .add => switch (role) {
            .left => 1,
            .right => 2,
            else => null,
        },
        .prog => null,
    };
}

fn restSlotOf(kind: Tag, role: Role) ?usize {
    return switch (kind) {
        .prog => if (role == .stmts) 1 else null,
        else => null,
    };
}

fn roleAt(kind: Tag, slot: usize) ?Role {
    return switch (kind) {
        .set => switch (slot) {
            1 => .target,
            2 => .value,
            else => null,
        },
        .add => switch (slot) {
            1 => .left,
            2 => .right,
            else => null,
        },
        .prog => null,
    };
}

fn restRoleOf(kind: Tag) ?struct { role: Role, slot: usize } {
    return switch (kind) {
        .prog => .{ .role = .stmts, .slot = 1 },
        else => null,
    };
}

fn executeAction(self: *BaseParser, ruleId: u16, pass: []Sexp) Sexp {
    return switch (ruleId) {
        0 => self.sexpSpread(.prog, pass[1]),
        1 => blk: {
            const out = self.allocItems(1) catch break :blk self.oomNil();
            out[0] = pass[0];
            break :blk self.finishItems(out, .spread);
        },
        2 => blk: {
            const out = self.extendBy(pass, 0, 1) catch break :blk self.oomNil();
            out.items[out.len] = pass[2];
            break :blk self.keepExtended(out, out.len + 1, pass, 0, .spread, false);
        },
        3 => self.buildOf(&.{ .{ .tag = .set }, .{ .elem = 0 }, .{ .elem = 2 } }, pass, .tree, true),
        6 => self.buildOf(&.{ .{ .tag = .add }, .{ .elem = 0 }, .{ .elem = 2 } }, pass, .tree, true),
        else => unreachable,
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn render(p: *BaseParser, s: Sexp) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(p.allocator());
    try s.write(p.source, &out.writer);
    return out.written();
}

fn facts(p: *BaseParser, s: Sexp) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(p.allocator());
    try p.writeFacts(&out.writer, s);
    return out.written();
}

fn errorText(p: *BaseParser) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(p.allocator());
    try p.writeError(&out.writer);
    return out.written();
}

test "Sexp is 24 bytes; list helpers" {
    try testing.expectEqual(24, @sizeOf(Sexp));
    const kids = [_]Sexp{ .{ .tag = .add }, .nil };
    const s = Sexp{ .list = List.withId(&kids, 5) };
    try testing.expectEqual(@as(usize, 2), s.items().len);
    try testing.expectEqual(Tag.add, s.kind().?);
    try testing.expect(s.isKind(.add));
    try testing.expect(!s.isKind(.set));
    try testing.expectEqual(@as(?Tag, null), Sexp.listOf(&.{}).kind());
    try testing.expectEqual(@as(usize, 0), (Sexp{ .tag = .set }).items().len);
}

test "parse builds the tree; the printer shows src ids" {
    var p = BaseParser.init(testing.allocator, "a = b + qc\nd");
    defer p.deinit();
    const tree = try p.parse(.prog);
    try testing.expectEqualStrings("(prog (set a (add b qc#7)) d)", try render(&p, tree));
}

test "spans cover the reduction, including tokens not in the tree" {
    //                                        0123456789
    var p = BaseParser.init(testing.allocator, "x = (b + c)\ny");
    defer p.deinit();
    const tree = try p.parse(.prog);
    const set = tree.items()[1];
    try testing.expectEqual(Span{ .start = 0, .end = 11 }, p.span(set));
    // `(b + c)` passes the inner `add` through: its span excludes the parens.
    const add = ir.get(set, .value);
    try testing.expectEqual(Span{ .start = 5, .end = 10 }, p.span(add));
    try testing.expectEqual(Span{ .start = 0, .end = 13 }, p.span(tree));
    try testing.expectEqual(@as(?u16, 3), p.ruleOf(set));
    try testing.expectEqual(@as(?u16, 6), p.ruleOf(add));
    try testing.expectEqual(@as(?u16, null), p.ruleOf(set.items()[1]));
    // Node ids are dense and start at 1.
    try testing.expect(p.nodeCount() >= 3);
    try testing.expect(set.list.id >= 1 and set.list.id <= p.nodeCount());
}

test "a list without a node id spans its children's hull in any order" {
    //                                        01234
    var p = BaseParser.init(testing.allocator, "ab cd");
    defer p.deinit();
    const kids = [_]Sexp{ .{ .tag = .add }, .{ .src = .{ .pos = 3, .len = 2, .id = 0 } }, .nil, .{ .src = .{ .pos = 0, .len = 2, .id = 0 } } };
    try testing.expectEqual(Span{ .start = 0, .end = 5 }, p.span(Sexp.listOf(&kids)));
    try testing.expectEqual(Span.empty, p.span(Sexp.listOf(kids[0..1])));
}

test "a token's lexer id never reaches the next token" {
    var p = BaseParser.init(testing.allocator, "qa b");
    defer p.deinit();
    try p.begin(.prog);
    // Drop `qa` (id 7) without shifting it, as a tolerant deletion does.
    try p.deleteToken();
    try testing.expectEqual(@as(u16, 0), takeLexerId(&p.lexer));
}

test "a plumbing list spread into its parent gets no node" {
    var p = BaseParser.init(testing.allocator, "a\nb\nc\nd");
    defer p.deinit();
    const tree = try p.parse(.prog);
    try testing.expectEqualStrings("(prog a b c d)", try render(&p, tree));
    // stmts only ever spreads into prog (its rules build with `.spread`):
    // prog is the one node.
    try testing.expectEqual(@as(u32, 1), p.nodeCount());
    try testing.expectEqual(Span{ .start = 0, .end = 7 }, p.span(tree));
}

test "a list that reaches the tree keeps its node id as it grows" {
    var p = BaseParser.init(testing.allocator, "a b c");
    defer p.deinit();
    try p.begin(.prog);
    // Build `(a)`, then extend it twice, as a left-recursive rule does.
    const items = [_]Sexp{ .{ .src = .{ .pos = 0, .len = 1, .id = 0 } }, .{ .src = .{ .pos = 2, .len = 1, .id = 0 } }, .{ .src = .{ .pos = 4, .len = 1, .id = 0 } } };
    p.reduction = .{ .rule = 1, .start = 0 };
    p.lastEnd = 1;
    const out = try p.allocItems(1);
    out[0] = items[0];
    try p.pushEntry(4, p.finishItems(out, .tree), 0, 1);
    for (items[1..], 1..) |item, i| {
        // The reduction `stmts = stmts IDENT → (...1 2)` with the stack
        // holding the list and the new item.
        p.reduction = .{ .rule = 2, .start = 0 };
        p.lastEnd = @intCast(2 * i + 1);
        try p.pushEntry(9, item, item.src.pos, item.src.pos + 1);
        const pass = p.valueStack.items[0..2];
        const grown = try p.extendBy(pass, 0, 1);
        // From the second extension on, the list grows in place.
        if (i > 1) try testing.expectEqual(pass[0].list.ptr, grown.items);
        grown.items[grown.len] = pass[1];
        const next = p.keepExtended(grown, grown.len + 1, pass, 0, .tree, false);
        try testing.expectEqual(pass[0].list.id, next.list.id);
        p.valueStack.items.len = 1;
        p.stateStack.items.len = 2;
        p.valueStack.items[0] = next;
    }
    const l = p.valueStack.items[0];
    try testing.expectEqual(@as(u32, 1), p.nodeCount());
    try testing.expectEqual(Span{ .start = 0, .end = 5 }, p.span(l));
    try testing.expectEqual(@as(?u16, 2), p.ruleOf(l));

    // `(...1 (...2 3))`: an extension nested in another; each list keeps
    // its own id.
    const out2 = try p.allocItems(1);
    out2[0] = items[1];
    try p.pushEntry(4, p.finishItems(out2, .tree), 2, 3);
    const pass = p.valueStack.items[0..2];
    const m = pass[1];
    try testing.expectEqual(@as(u32, 2), p.nodeCount());
    const outer = try p.extendBy(pass, 0, 1);
    const inner = try p.extendBy(pass, 1, 1);
    inner.items[inner.len] = items[2];
    const innerList = p.keepExtended(inner, inner.len + 1, pass, 1, .tree, false);
    outer.items[outer.len] = innerList;
    const outerList = p.keepExtended(outer, outer.len + 1, pass, 0, .tree, false);
    try testing.expectEqual(m.list.id, innerList.list.id);
    try testing.expectEqual(l.list.id, outerList.list.id);
    try testing.expectEqual(@as(u32, 2), p.nodeCount());
}

test "~N of an element that is no leaf is an empty leaf where it starts" {
    var p = BaseParser.init(testing.allocator, "a = b");
    defer p.deinit();
    try p.begin(.prog);
    try p.pushEntry(9, .{ .src = .{ .pos = 0, .len = 1, .id = 0 } }, 0, 1);
    try p.pushEntry(10, .nil, 2, 2);
    const leaf = p.emptyLeaf(p.valueStack.items, 1);
    try testing.expectEqual(Src{ .pos = 2, .len = 0, .id = 0 }, leaf.src);
}

test "side-band roles record a span without a tree slot" {
    var p = BaseParser.init(testing.allocator, "ab  =  c");
    defer p.deinit();
    const tree = try p.parse(.prog);
    const set = tree.items()[1];
    try testing.expectEqual(Span{ .start = 4, .end = 5 }, p.sideRole(set, .eq).?);
    try testing.expectEqual(@as(?Span, null), p.sideRole(set, .target));
    try testing.expectEqual(@as(?Span, null), p.sideRole(tree, .eq));
}

test "trivia tokens leave the parse stream and are kept with spans" {
    var p = BaseParser.init(testing.allocator, "#top\na # one\nb#two");
    defer p.deinit();
    // The leading comment is trivia; the newline after it is not.
    try testing.expectError(error.ParseError, p.parse(.prog));
    var q = BaseParser.init(testing.allocator, "a # one\nb#two");
    defer q.deinit();
    const tree = try q.parse(.prog);
    try testing.expectEqualStrings("(prog a b)", try render(&q, tree));
    const t = q.trivia();
    try testing.expectEqual(@as(usize, 2), t.len);
    try testing.expectEqual(@as(u32, 2), t[0].pos);
    try testing.expectEqual(@as(u16, 5), t[0].len);
    try testing.expectEqual(@as(u32, 9), t[1].pos);
}

test "parse errors carry the token span and the expected set" {
    var p = BaseParser.init(testing.allocator, "a =\nb");
    defer p.deinit();
    try testing.expectError(error.ParseError, p.parse(.prog));
    const f = p.lastError().?;
    try testing.expectEqual(Span{ .start = 3, .end = 4 }, f.span);
    try testing.expectEqual(TokenCat.newline, f.cat);
    try testing.expectEqualStrings("1:4: expected an expression, got newline", try errorText(&p));
    var names: [maxExpected][]const u8 = undefined;
    const want = BaseParser.expectedNames(f.state, &names);
    try testing.expectEqual(@as(usize, 1), want.len);
    try testing.expectEqualStrings("an expression", want[0]);

    var q = BaseParser.init(testing.allocator, "a b");
    defer q.deinit();
    try testing.expectError(error.ParseError, q.parse(.prog));
    try testing.expectEqualStrings("1:3: expected end of input, newline, \"=\" or \"+\", got identifier", try errorText(&q));

    var r = BaseParser.init(testing.allocator, "a + ?");
    defer r.deinit();
    try testing.expectError(error.ParseError, r.parse(.prog));
    try testing.expectEqualStrings("1:5: expected identifier or \"(\", got err", try errorText(&r));
    // printError writes the same text to standard error.
    _ = &BaseParser.printError;
}

test "the tolerant driver inserts holes and deletes stray tokens" {
    // `a = ` misses its value before a newline (a terminator, so layout): a
    // zero-width IDENT is inserted.
    var p = BaseParser.init(testing.allocator, "a = \nb");
    defer p.deinit();
    const r = try p.parseTolerant(.prog, 8);
    try testing.expect(r.complete);
    try testing.expectEqual(@as(u32, 1), r.repairs);
    try testing.expectEqual(@as(u32, 1), r.insertions);
    try testing.expectEqualStrings("(prog (set a ) b)", try render(&p, r.sexp));
    try testing.expectEqual(TokenCat.newline, r.failure.?.cat);
    const hole = ir.get(r.sexp.items()[1], .value);
    try testing.expectEqual(@as(u16, 0), hole.src.len);
    try testing.expectEqual(@as(u32, 4), hole.src.pos);

    // `a b`: a terminator is inserted in front of the real token `b`.
    var q = BaseParser.init(testing.allocator, "a b");
    defer q.deinit();
    const s = try q.parseTolerant(.prog, 8);
    try testing.expect(s.complete);
    try testing.expectEqualStrings("(prog a b)", try render(&q, s.sexp));

    // `)` cannot be repaired by insertion: it is deleted.
    var t = BaseParser.init(testing.allocator, "a )+ b");
    defer t.deinit();
    const u = try t.parseTolerant(.prog, 8);
    try testing.expect(u.complete);
    try testing.expectEqualStrings("(prog (add a b))", try render(&t, u.sexp));
    try testing.expectEqual(@as(u32, 1), u.repairs);
    try testing.expectEqual(@as(u32, 1), u.deletions);

    // Valid input: no failure, no repairs.
    var y = BaseParser.init(testing.allocator, "a");
    defer y.deinit();
    const z = try y.parseTolerant(.prog, 8);
    try testing.expect(z.complete and z.failure == null and z.repairs == 0);
}

test "tolerant parsing never puts a hole in front of real input" {
    // A hole before `+` would make `a = <hole> + b`; the real token is
    // deleted instead.
    var p = BaseParser.init(testing.allocator, "a = + b");
    defer p.deinit();
    const r = try p.parseTolerant(.prog, 8);
    try testing.expect(r.complete);
    try testing.expectEqualStrings("(prog (set a b))", try render(&p, r.sexp));
    try testing.expectEqual(@as(u32, 0), r.insertions);
    try testing.expectEqual(@as(u32, 1), r.deletions);
}

test "tolerant parsing: end of input takes holes and is never deleted" {
    var p = BaseParser.init(testing.allocator, "a =");
    defer p.deinit();
    const r = try p.parseTolerant(.prog, 8);
    try testing.expect(r.complete);
    try testing.expectEqualStrings("(prog (set a ))", try render(&p, r.sexp));
    try testing.expectEqual(TokenCat.eof, r.failure.?.cat);

    // `(a` needs a `)`, which is not fabricable: the parse ends at end of
    // input, incomplete, without deleting it.
    var q = BaseParser.init(testing.allocator, "(a");
    defer q.deinit();
    const s = try q.parseTolerant(.prog, 8);
    try testing.expect(!s.complete);
    try testing.expectEqual(@as(u32, 0), s.repairs);
    try testing.expectEqual(TokenCat.eof, s.failure.?.cat);

    // `a = (`: a hole is inserted though `)` is still missing (the hole
    // makes progress), once; then the parse ends.
    var t = BaseParser.init(testing.allocator, "a = (");
    defer t.deinit();
    const u = try t.parseTolerant(.prog, 8);
    try testing.expect(!u.complete);
    try testing.expectEqual(@as(u32, 1), u.insertions);
    try testing.expectEqual(@as(u32, 0), u.deletions);
}

test "tolerant parsing keeps the first error and honors the budget" {
    var p = BaseParser.init(testing.allocator, "a = + b\n) c");
    defer p.deinit();
    const r = try p.parseTolerant(.prog, 8);
    try testing.expect(r.complete);
    try testing.expectEqualStrings("(prog (set a b) c)", try render(&p, r.sexp));
    try testing.expectEqual(@as(u32, 2), r.deletions);
    // The first error, as the strict parse reports it.
    try testing.expectEqual(Span{ .start = 4, .end = 5 }, r.failure.?.span);
    try testing.expectEqualStrings("1:5: expected an expression, got \"+\"", try errorText(&p));

    var q = BaseParser.init(testing.allocator, ") ) ) a");
    defer q.deinit();
    const s = try q.parseTolerant(.prog, 2);
    try testing.expect(!s.complete);
    try testing.expectEqual(@as(u32, 2), s.repairs);
    try testing.expectEqual(Span{ .start = 0, .end = 1 }, s.failure.?.span);

    var t = BaseParser.init(testing.allocator, "a b");
    defer t.deinit();
    const u = try t.parseTolerant(.prog, 0);
    try testing.expect(!u.complete);
    try testing.expectEqual(@as(u32, 0), u.repairs);
    try testing.expect(u.failure != null);
}

test "ir slots are known at compile time" {
    try testing.expectEqual(@as(usize, 1), comptime ir.slot(.set, .target));
    try testing.expectEqual(@as(usize, 2), comptime ir.slot(.add, .right));
    try testing.expectEqual(@as(usize, 1), comptime ir.restSlot(.prog, .stmts));
    try testing.expectEqual(@as(usize, 3), comptime ir.width(.set));
    try testing.expectEqual(@as(usize, 1), comptime ir.width(.prog));
    // A wrapper fills a role by its slot.
    var items: [ir.width(.set)]Sexp = @splat(.nil);
    items[0] = .{ .tag = .set };
    items[ir.slot(.set, .value)] = .{ .src = .{ .pos = 4, .len = 1, .id = 0 } };
    try testing.expectEqual(@as(u32, 4), ir.get(Sexp.listOf(&items), .value).src.pos);
}

test "ir accessors: by role and through per-kind positions" {
    var p = BaseParser.init(testing.allocator, "a = b + c");
    defer p.deinit();
    const tree = try p.parse(.prog);
    try testing.expectEqual(@as(usize, 1), ir.rest(tree, .stmts).len);
    const set = ir.rest(tree, .stmts)[0];
    try testing.expectEqualStrings("a", ir.get(set, .target).getText(p.source));
    const add = ir.get(set, .value);
    try testing.expect(add.isKind(.add));
    try testing.expectEqualStrings("c", @"ir.at"(add, .add, 2, "ir.Add.right").getText(p.source));
    try testing.expect(ir.has(.set, .target));
    try testing.expect(!ir.has(.set, .left));
    try testing.expect(ir.has(.prog, .stmts));
}

test "facts export" {
    //                                        01234567
    var p = BaseParser.init(testing.allocator, "a = b\nc");
    defer p.deinit();
    const tree = try p.parse(.prog);
    // Ids follow construction order: set = 1, prog = 2 (the stmts list
    // between them is plumbing: no node).
    try testing.expectEqualStrings(
        \\(node 2 prog 0 7)
        \\(role 2 stmts 1 leaf 6 1)
        \\(node 1 set 0 5)
        \\(role 1 target leaf 0 1)
        \\(role 1 value leaf 4 1)
        \\(side 1 eq 2 1)
        \\
    , try facts(&p, tree));
}

test "a wrapper builds nodes with ids and spans" {
    var p = BaseParser.init(testing.allocator, "a = b");
    defer p.deinit();
    const tree = try p.parse(.prog);
    const set = tree.items()[1];
    const before = p.nodeCount();
    const add = try p.newNode(.add, &.{ ir.get(set, .target), ir.get(set, .value) }, .{ .start = 0, .end = 5 });
    try testing.expectEqual(before + 1, p.nodeCount());
    try testing.expectEqualStrings("(add a b)", try render(&p, add));
    try testing.expectEqual(Span{ .start = 0, .end = 5 }, p.span(add));
    try testing.expectEqual(@as(?u16, null), p.ruleOf(add));
    try testing.expectEqualStrings("b", ir.get(add, .right).getText(p.source));
    const group = try p.newList(&.{ .nil, .nil }, .{ .start = 4, .end = 4 });
    try testing.expectEqual(Span{ .start = 4, .end = 4 }, p.span(group));
    try testing.expect(group.list.id == add.list.id + 1);
    try testing.expectEqualStrings(
        \\(node 3 add 0 5)
        \\(role 3 left leaf 0 1)
        \\(role 3 right leaf 4 1)
        \\
    , try facts(&p, add));
}

test "facts quote names with s-expression syntax" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try BaseParser.writeName(&out.writer, "a(b");
    try BaseParser.writeName(&out.writer, "+=");
    try testing.expectEqualStrings("\"a(b\"+=", out.written());
}

test "the parse allocator bumps through arena chunks" {
    var p = BaseParser.init(testing.allocator, "");
    defer p.deinit();
    const a = p.allocator();
    // The last allocation grows and shrinks in place; it can be freed.
    var buf = try a.alloc(u8, 10);
    try testing.expect(a.resize(buf, 100));
    buf = buf.ptr[0..100];
    try testing.expect(a.resize(buf, 50));
    buf = buf.ptr[0..50];
    const next = try a.alloc(u64, 2);
    try testing.expect(std.mem.isAligned(@intFromPtr(next.ptr), @alignOf(u64)));
    // An earlier one only shrinks.
    try testing.expect(!a.resize(buf, 60));
    try testing.expect(a.resize(buf, 40));
    a.free(next);
    try testing.expectEqual(@intFromPtr(next.ptr), p.bumpPos);
    // Allocations past a chunk take a new one; large ones go to the arena.
    for (0..1000) |i| {
        const items = try p.allocItems(i % 7);
        @memset(items, .nil);
    }
    const big = try a.alloc(u8, BaseParser.bumpLast);
    @memset(big, 1);
    try testing.expect(!a.resize(big, BaseParser.bumpLast + 1));
}

test "reset parses new input in the memory the parser holds" {
    var p = BaseParser.init(testing.allocator, "a = b + (c + d)\ne");
    defer p.deinit();
    _ = try p.parse(.prog);
    const capacity = p.arena.queryCapacity();
    p.reset("x = y\nz");
    try testing.expectEqual(@as(?Failure, null), p.lastError());
    try testing.expectEqual(@as(u32, 0), p.nodeCount());
    const tree = try p.parse(.prog);
    try testing.expectEqualStrings("(prog (set x y) z)", try render(&p, tree));
    try testing.expectEqual(Span{ .start = 0, .end = 5 }, p.span(tree.items()[1]));
    try testing.expectEqual(capacity, p.arena.queryCapacity());
    p.reset("a b");
    try testing.expectError(error.ParseError, p.parse(.prog));
    try testing.expectEqualStrings("1:3: expected end of input, newline, \"=\" or \"+\", got identifier", try errorText(&p));
}

test "an allocation failure fails the parse with error.OutOfMemory" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(testing.allocator);
    for (0..300) |_| try source.appendSlice(testing.allocator, "a = b + (c + d)\n");
    try source.appendSlice(testing.allocator, "e");
    var failures: usize = 0;
    var index: usize = 0;
    while (true) : (index += 1) {
        var failing: std.testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = index });
        var p = BaseParser.init(failing.allocator(), source.items);
        defer p.deinit();
        if (p.parse(.prog)) |tree| {
            try testing.expectEqual(@as(usize, 302), tree.items().len);
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            failures += 1;
        }
    }
    try testing.expect(failures > 3);
}

test "a long left-recursive list grows in place" {
    const n = 100_000;
    const source = try testing.allocator.alloc(u8, 2 * n - 1);
    defer testing.allocator.free(source);
    for (source, 0..) |*c, i| c.* = if (i % 2 == 0) 'a' else '\n';
    var p = BaseParser.init(testing.allocator, source);
    defer p.deinit();
    const tree = try p.parse(.prog);
    try testing.expectEqual(@as(usize, n + 1), tree.items().len);
    // Each statement is a token-sized leaf: amortized growth keeps the
    // memory linear (well under the quadratic 24 * n * n / 2 bytes).
    try testing.expect(p.arena.queryCapacity() < 64 * n * @sizeOf(Sexp));
}

test "tree walks keep their stack on the heap: a tree a million levels deep" {
    var p = BaseParser.init(testing.allocator, "x");
    defer p.deinit();
    const depth = 1_000_000;
    // ((( ... x ... ))): the one leaf at the bottom.
    var s: Sexp = .{ .src = .{ .pos = 0, .len = 1, .id = 0 } };
    for (0..depth) |_| {
        const one = try p.allocator().alloc(Sexp, 1);
        one[0] = s;
        s = Sexp.listOf(one);
    }
    var out: std.Io.Writer.Discarding = .init(&.{});
    try s.write(p.source, &out.writer);
    try testing.expectEqual(2 * depth + 1, out.fullCount());
    try testing.expectEqual(Span{ .start = 0, .end = 1 }, p.span(s));

    const root = try p.newNode(.prog, &.{s}, .{ .start = 0, .end = 1 });
    out = .init(&.{});
    try p.writeFacts(&out.writer, root);
    const lines = "(node 1 prog 0 1)\n".len + "(role 1 stmts )\n".len + "leaf 0 1".len;
    try testing.expectEqual(lines + 2 * depth, out.fullCount());
}
