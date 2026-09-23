//! Runtime template for generated parser modules.
//!
//! This is a real Zig file: it compiles on its own and its tests run with
//! `zig build test-runtime`. codegen.zig embeds it and composes the output
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
//!   types      Tag, Role, Start, Token, TokenCat, Lexer
//!   config     nodeStore, elemEnds, keepTrailingNils, hasTrivia, hasRepair,
//!              numSymbols, endSymbol, errorSymbol, xExcludes
//!   tables     ruleLhs, ruleLen
//!   functions  getAction, getImmediateShift, startState, startMarker,
//!              tokenToSymbol, executeAction, expectedIn, symbolName, isTrivia,
//!              repairCandidates, repairClass, ruleSideLabels, slotOf,
//!              restSlotOf, roleAt, restRoleOf

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
    pub fn write(self: Sexp, source: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .nil => try w.writeAll("_"),
            .tag => |t| try w.writeAll(nameOf(t)),
            .src => |s| {
                try w.writeAll(source[s.pos..][0..s.len]);
                if (s.id != 0) try w.print("#{d}", .{s.id});
            },
            .str => |s| try w.print("\"{s}\"", .{s}),
            .list => |l| {
                try w.writeAll("(");
                for (l.items(), 0..) |item, i| {
                    if (i > 0) try w.writeAll(" ");
                    try item.write(source, w);
                }
                try w.writeAll(")");
            },
        }
    }
};

/// The name of a Tag or Role value, "?" for one the enum does not name
/// (without a schema, Role is empty and a collected Tag is non-exhaustive).
fn nameOf(value: anytype) []const u8 {
    return std.enums.tagName(@TypeOf(value), value) orelse "?";
}

// @end

// @section parser

// =============================================================================
// Parser
// =============================================================================

/// Per node: its source span and the rule that built it.
pub const NodeInfo = struct { span: Span, rule: u16 };

/// NodeInfo per NodeId, in fixed-size chunks that never move (appending
/// never copies the store).
const NodeStore = struct {
    chunks: std.ArrayListUnmanaged(*[chunkLen]NodeInfo) = .empty,
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

/// A side-band role recorded at reduce time (not placed in the tree).
pub const SideEntry = struct { node: NodeId, role: Role, span: Span };

/// A side-band label of a rule: `role` is recorded from element `pass`.
pub const SideLabel = struct { role: Role, pass: u16 };

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
pub const RepairClass = enum {
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
    if (comptime @hasField(Lexer, "aux")) {
        const id = lexer.aux;
        lexer.aux = 0;
        return id;
    } else if (comptime @hasField(Lexer, "base") and @hasField(@FieldType(Lexer, "base"), "aux")) {
        const id = lexer.base.aux;
        lexer.base.aux = 0;
        return id;
    } else return 0;
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
    /// Set when a builder could not allocate; the parse then fails.
    outOfMemory: bool = false,
    /// A parse has begun (the next one re-reads the input).
    started: bool = false,

    stateStack: std.ArrayListUnmanaged(u16) = .empty,
    valueStack: std.ArrayListUnmanaged(Sexp) = .empty,
    /// Spare capacity of the lists `keepList` returned, by address.
    listSpare: std.AutoHashMapUnmanaged(usize, ListSpare) = .empty,
    /// Node id of the list `extendList` is growing (0 = none).
    extending: NodeId = 0,

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
    sides: std.ArrayListUnmanaged(SideEntry) = .empty,
    reduction: Reduction = .{},
    /// End of the last shifted token: where every reduction ends.
    lastEnd: u32 = 0,

    triviaTokens: std.ArrayListUnmanaged(Token) = .empty,
    failure: ?Failure = null,
    scratch: std.ArrayListUnmanaged(u16) = .empty,

    const ListSpare = struct { len: usize, capacity: usize };

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
        p.current = p.lexer.next();
        return p;
    }

    pub fn deinit(self: *BaseParser) void {
        self.arena.deinit();
    }

    fn allocator(self: *BaseParser) std.mem.Allocator {
        return self.arena.allocator();
    }

    // @slot startMethods

    /// Parse the whole input as `start`.
    pub fn parse(self: *BaseParser, start: Start) !Sexp {
        try self.begin(start);
        while (true) {
            const state = self.stateStack.getLast();
            const sym = self.lookahead();
            const action = self.actionFor(state, sym);
            if (action > 0) {
                try self.shift(@intCast(action));
            } else if (action < -1) {
                try self.reduce(@intCast(-action - 2));
            } else if (action == -1) {
                return self.valueStack.getLast();
            } else {
                self.recordFailure(state, sym);
                return error.ParseError;
            }
        }
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
    ///      inserted anyway, never twice in the same configuration (stack
    ///      depth, state, token) since the last token was consumed, so
    ///      several insertions can complete an unfinished construct.
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
        var tried: std.ArrayListUnmanaged(RepairKey) = .empty;
        while (true) {
            const state = self.stateStack.getLast();
            const sym = self.lookahead();
            const action = self.actionFor(state, sym);
            if (action > 0) {
                if (self.pendingInsert == null and self.injectedToken == null) tried.clearRetainingCapacity();
                try self.shift(@intCast(action));
            } else if (action < -1) {
                try self.reduce(@intCast(-action - 2));
            } else if (action == -1) {
                result.sexp = self.valueStack.getLast();
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
                    try self.advance();
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
    /// when there is none.
    fn chooseInsertion(self: *BaseParser, next: u16, tried: []const RepairKey) !?u16 {
        const state = self.stateStack.getLast();
        const nextClass = if (next == endSymbol) RepairClass.structure else repairClass(next);
        const real = nextClass == .none or nextClass == .hole;
        for (repairCandidates(state)) |candidate| {
            if (real and repairClass(candidate) != .terminator) continue;
            if (try self.accepts(&.{ candidate, next })) return candidate;
        }
        if (real) return null;
        const depth: u32 = @intCast(self.stateStack.items.len);
        for (repairCandidates(state)) |candidate| {
            const seen = for (tried) |k| {
                if (k.depth == depth and k.state == state and k.token == candidate) break true;
            } else false;
            if (!seen and try self.accepts(&.{candidate})) return candidate;
        }
        return null;
    }

    fn begin(self: *BaseParser, start: Start) !void {
        // Token positions are u32.
        if (self.source.len > std.math.maxInt(u32)) return error.InputTooLarge;
        // Every parse reads the input from the start (a parser may parse
        // again, e.g. tolerantly after a failed strict parse). Node ids
        // keep counting, so earlier trees stay valid.
        if (self.started) {
            self.lexer = Lexer.init(self.source);
            self.current = self.lexer.next();
            self.lastMatchedId = 0;
            self.triviaTokens.clearRetainingCapacity();
        }
        self.started = true;
        self.stateStack.clearRetainingCapacity();
        self.valueStack.clearRetainingCapacity();
        self.failure = null;
        self.pendingInsert = null;
        self.outOfMemory = false;
        try self.stateStack.append(self.allocator(), startState(start));
        if (nodeStore) self.lastEnd = 0;
        self.injectedToken = startMarker(start);
        if (nodeStore) {
            if (self.nodes.len == 0) _ = try self.nodes.add(self.allocator(), .{ .span = .empty, .rule = 0 });
        }
        if (hasTrivia) try self.skipTrivia();
    }

    inline fn lookahead(self: *BaseParser) u16 {
        if (self.injectedToken) |marker| return marker;
        if (self.pendingInsert) |token| return token;
        return tokenToSymbol(self, self.current);
    }

    /// The table action, with the `X "c"` override: when the table reduces
    /// on the hinted token and it touches the previous token, shift
    /// instead. (Never for a start marker or an inserted token.)
    inline fn actionFor(self: *const BaseParser, state: u16, sym: u16) i16 {
        const action = getAction(state, sym);
        if (xExcludes.len > 0 and action < -1 and self.current.pre == 0 and self.pendingInsert == null and self.injectedToken == null) {
            if (getImmediateShift(state, sym)) |target| return target;
        }
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
        } else {
            const tok = self.current;
            const id = if (self.lastMatchedId != 0) self.lastMatchedId else takeLexerId(&self.lexer);
            self.lastMatchedId = 0;
            const end = tok.pos + tok.len;
            try self.pushEntry(target, .{ .src = .{ .pos = tok.pos, .len = tok.len, .id = id } }, tok.pos, end);
            if (nodeStore) self.lastEnd = end;
            try self.advance();
        }
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
        // result then replaces them (a reduction of nothing pushes it).
        const result = executeAction(self, ruleId, self.valueStack.items[base..]);
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
        if (value != .list) return;
        const l = value.list;
        if (l.id != 0 and l.id < self.nodes.len) {
            const info = self.nodes.at(l.id);
            if (!info.span.isEmpty()) return;
            info.span = .{ .start = at, .end = at };
        }
        for (l.items()) |child| self.placeEmpty(child, at);
    }

    /// Fetch the next token, moving trivia to the trivia channel.
    fn advance(self: *BaseParser) !void {
        self.current = self.lexer.next();
        if (hasTrivia) try self.skipTrivia();
    }

    fn skipTrivia(self: *BaseParser) !void {
        while (isTrivia(self.current.cat)) {
            try self.triviaTokens.append(self.allocator(), self.current);
            _ = takeLexerId(&self.lexer);
            self.current = self.lexer.next();
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
    /// list spans the hull of its children.
    pub fn span(self: *const BaseParser, s: Sexp) Span {
        switch (s) {
            .src => |x| return .{ .start = x.pos, .end = x.pos + x.len },
            .list => |l| {
                if (nodeStore and l.id != 0 and l.id < self.nodes.len) return self.nodes.at(l.id).span;
                var result: ?Span = null;
                for (l.items()) |child| {
                    const cs = self.span(child);
                    if (cs.isEmpty()) continue;
                    result = if (result) |r| .{ .start = r.start, .end = cs.end } else cs;
                }
                return result orelse .empty;
            },
            else => return .empty,
        }
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
        const out = try self.allocator().alloc(Sexp, children.len + 1);
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
        if (self.nodes.len == 0) _ = try self.nodes.add(self.allocator(), .{ .span = .empty, .rule = 0 });
        return self.nodes.add(self.allocator(), .{ .span = extent, .rule = wrapperRule });
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
        const out = self.allocator().dupe(Sexp, items) catch return self.oomNil();
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

    /// The default action: nothing, the one element, or an untagged list.
    fn list(self: *BaseParser, pass: []Sexp, comptime use: ListUse) Sexp {
        if (pass.len == 0) return .nil;
        if (pass.len == 1) return pass[0];
        const out = self.allocator().dupe(Sexp, pass) catch return self.oomNil();
        return self.node(out, use);
    }

    /// `()`: an empty list.
    fn emptyList(self: *BaseParser, comptime use: ListUse) Sexp {
        return self.node(&.{}, use);
    }

    /// `[head, ...tail]`
    fn spreadList(self: *BaseParser, head: Sexp, tail: Sexp, comptime use: ListUse) Sexp {
        const rest = tail.items();
        const out = self.allocator().alloc(Sexp, rest.len + 1) catch return self.oomNil();
        out[0] = head;
        @memcpy(out[1..], rest);
        return self.node(out, use);
    }

    /// Start a list holding the items of `base` (a list, else nothing)
    /// for an action that appends to it. A list from `keepList` is reused
    /// with its spare capacity, so a left-recursive list grows in amortized
    /// O(1) per element; it keeps its node id.
    fn extendList(self: *BaseParser, base: Sexp) !std.ArrayListUnmanaged(Sexp) {
        self.extending = 0;
        if (base != .list) return .empty;
        self.extending = base.list.id;
        const items = base.list.items();
        if (items.len > 0) if (self.listSpare.get(@intFromPtr(items.ptr))) |spare| {
            if (spare.len == items.len) {
                _ = self.listSpare.remove(@intFromPtr(items.ptr));
                return .{ .items = @constCast(items), .capacity = spare.capacity };
            }
        };
        var out: std.ArrayListUnmanaged(Sexp) = .empty;
        try out.appendSlice(self.allocator(), items);
        return out;
    }

    /// Finish a list from `extendList`, recording its spare capacity.
    fn keepList(self: *BaseParser, out: *std.ArrayListUnmanaged(Sexp), comptime use: ListUse) Sexp {
        out.shrinkRetainingCapacity(trimmedLen(out.items));
        if (out.items.len > 0 and out.capacity > out.items.len) {
            self.listSpare.put(self.allocator(), @intFromPtr(out.items.ptr), .{
                .len = out.items.len,
                .capacity = out.capacity,
            }) catch return self.oomNil();
        }
        var id: NodeId = 0;
        if (nodeStore and use == .tree) {
            if (self.extending != 0) {
                id = self.extending;
                self.nodes.at(id).* = .{ .span = self.reductionSpan(), .rule = self.reduction.rule };
            } else id = self.newNodeId();
        }
        self.extending = 0;
        return .{ .list = List.withId(out.items, id) };
    }

    /// Finish a list built from scratch.
    fn finishList(self: *BaseParser, out: *std.ArrayListUnmanaged(Sexp), comptime use: ListUse) Sexp {
        out.shrinkRetainingCapacity(trimmedLen(out.items));
        const items = out.toOwnedSlice(self.allocator()) catch return self.oomNil();
        return self.node(items, use);
    }

    /// `(tag items...)`
    inline fn sexp(self: *BaseParser, comptime tag: Tag, items: []const Sexp) Sexp {
        const len = trimmedLen(items);
        const out = self.allocator().alloc(Sexp, len + 1) catch return self.oomNil();
        out[0] = .{ .tag = tag };
        @memcpy(out[1..], items[0..len]);
        return self.node(out, .tree);
    }

    /// `(tag ...spread)`
    inline fn sexpSpread(self: *BaseParser, comptime tag: Tag, spread: Sexp) Sexp {
        const items = spread.items();
        const len = trimmedLen(items);
        const out = self.allocator().alloc(Sexp, len + 1) catch return self.oomNil();
        out[0] = .{ .tag = tag };
        @memcpy(out[1..], items[0..len]);
        return self.node(out, .tree);
    }

    /// `(tag pos ...spread)`; just `(tag)` when both are empty (and
    /// positions are not fixed by a schema).
    inline fn sexpPosSpread(self: *BaseParser, comptime tag: Tag, pos: Sexp, spread: Sexp) Sexp {
        const items = spread.items();
        const len = trimmedLen(items);
        const bare = !keepTrailingNils and pos == .nil and len == 0;
        const out = self.allocator().alloc(Sexp, if (bare) 1 else len + 2) catch return self.oomNil();
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
        const want = expectedIn(f.state);
        for (want, 0..) |sym, i| {
            if (i > 0) try w.writeAll(if (i + 1 == want.len) " or " else ", ");
            try w.writeAll(symbolName(sym));
        }
        if (want.len == 0) try w.writeAll("nothing");
        try w.writeAll(", got ");
        const got = symbolName(f.symbol);
        try w.writeAll(if (f.symbol == errorSymbol or got.len == 0) @tagName(f.cat) else got);
    }

    pub fn printError(self: *const BaseParser) void {
        var buf: [512]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        self.writeError(&w) catch {};
        std.debug.print("Parse error at {s}\n", .{w.buffered()});
    }

    /// What `state` accepts, reader-named: the `@errors` rules it waits
    /// for, then the tokens none of them begins with.
    pub fn expected(state: u16) []const u16 {
        return expectedIn(state);
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

    /// Whether `symbols` can be consumed from the current state, simulating
    /// reductions on a scratch copy of the state stack.
    fn accepts(self: *BaseParser, symbols: []const u16) !bool {
        const stack = &self.scratch;
        stack.clearRetainingCapacity();
        try stack.appendSlice(self.allocator(), self.stateStack.items);
        for (symbols) |sym| {
            while (true) {
                const action = getAction(stack.getLast(), sym);
                if (action == 0) return false;
                if (action == -1) return true;
                if (action > 0) {
                    try stack.append(self.allocator(), @intCast(action));
                    break;
                }
                const rule: u16 = @intCast(-action - 2);
                stack.shrinkRetainingCapacity(stack.items.len - ruleLen[rule]);
                const next = getAction(stack.getLast(), ruleLhs[rule]);
                if (next <= 0) return false;
                try stack.append(self.allocator(), @intCast(next));
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
    /// for a list without a node id.
    pub fn writeFacts(self: *const BaseParser, w: *std.Io.Writer, root: Sexp) std.Io.Writer.Error!void {
        if (!nodeStore) @compileError("writeFacts needs the node store (@schema or --spans)");
        try self.factsOf(w, root);
    }

    fn factsOf(self: *const BaseParser, w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!void {
        if (s != .list) return;
        const l = s.list;
        const items = l.items();
        if (l.id != 0) {
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
                        try self.factChild(w, child);
                    }
                    try w.writeAll(")\n");
                    break;
                };
                if (items[i] == .nil) continue;
                try w.print("(role {d} ", .{l.id});
                if (if (k) |t| roleAt(t, i) else null) |role| try writeName(w, nameOf(role)) else try w.print("{d}", .{i});
                try w.writeByte(' ');
                try self.factChild(w, items[i]);
                try w.writeAll(")\n");
            }
            for (self.sidesOf(l.id)) |e| {
                try w.print("(side {d} ", .{l.id});
                try writeName(w, nameOf(e.role));
                try w.print(" {d} {d})\n", .{ e.span.start, e.span.len() });
            }
        }
        for (items) |child| try self.factsOf(w, child);
    }

    fn factChild(self: *const BaseParser, w: *std.Io.Writer, s: Sexp) std.Io.Writer.Error!void {
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
            .list => |l| if (l.id != 0) try w.print("{d}", .{l.id}) else {
                try w.writeByte('(');
                for (l.items(), 0..) |child, i| {
                    if (i > 0) try w.writeByte(' ');
                    try self.factChild(w, child);
                }
                try w.writeByte(')');
            },
        }
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
        if (std.debug.runtime_safety) std.debug.panic(what ++ "(.{s}): not a schema node: {s}", .{ @tagName(role), @tagName(node) });
        return null;
    }

    fn missing(kind: @"ir.Tag", role: @"ir.Role", comptime what: []const u8, value: anytype) @TypeOf(value) {
        if (std.debug.runtime_safety) {
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
    if (std.debug.runtime_safety and !node.isKind(kind)) {
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

const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,
    aux: u16 = 0,

    fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    fn next(self: *Lexer) Token {
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

const nodeStore = true;
const keepTrailingNils = true;
const hasTrivia = true;
const hasRepair = true;
const elemEnds = true;
const numSymbols = 16;
const endSymbol: u16 = 1;
const errorSymbol: u16 = 2;
const xExcludes = [_]struct { sym: u16, shift: u16 }{};

// 0 $accept, 1 $end, 2 error, 3 prog, 4 stmts, 5 stmt, 6 expr, 7 term,
// 8 NEWLINE, 9 IDENT, 10 "=", 11 "+", 12 "(", 13 ")", 14 prog!, 15 $accept_prog
const ruleLhs = [_]u16{ 3, 4, 4, 5, 5, 6, 6, 7, 7, 15 };
const ruleLen = [_]u8{ 2, 1, 3, 3, 1, 1, 3, 1, 3, 2 };

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

fn getAction(state: u16, sym: u16) i16 {
    return parseTable[state][sym];
}

/// Hand-built from the table, with `expr` named "an expression".
fn expectedIn(state: u16) []const u16 {
    return switch (state) {
        2, 9, 10, 12 => &.{6},
        11 => &.{ 9, 12 },
        4 => &.{ 1, 8 },
        6 => &.{ 1, 8, 10, 11 },
        5, 8, 15, 17 => &.{ 1, 8, 11 },
        13 => &.{ 11, 13 },
        else => &.{},
    };
}

fn getImmediateShift(_: u16, _: u16) ?i16 {
    return null;
}

fn startState(_: Start) u16 {
    return 0;
}

fn startMarker(_: Start) u16 {
    return 14;
}

fn isTrivia(cat: TokenCat) bool {
    return cat == .comment;
}

fn tokenToSymbol(_: *BaseParser, token: Token) u16 {
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

fn repairCandidates(state: u16) []const u16 {
    // Hand-built: the hole (IDENT) where the state accepts it, else NEWLINE.
    return switch (state) {
        2, 9, 10, 11, 12 => &.{9},
        4, 5, 6, 7, 8, 14, 15, 16, 17, 18 => &.{8},
        else => &.{},
    };
}

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
            var out: std.ArrayListUnmanaged(Sexp) = .empty;
            out.append(self.allocator(), pass[0]) catch break :blk self.oomNil();
            break :blk self.finishList(&out, .spread);
        },
        2 => blk: {
            var out = self.extendList(pass[0]) catch break :blk self.oomNil();
            out.append(self.allocator(), pass[2]) catch break :blk self.oomNil();
            break :blk self.keepList(&out, .spread);
        },
        3 => self.sexp(.set, &.{ pass[0], pass[2] }),
        4 => pass[0],
        5 => self.list(pass, .tree),
        6 => self.sexp(.add, &.{ pass[0], pass[2] }),
        7 => self.list(pass, .tree),
        8 => pass[1],
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
    var out: std.ArrayListUnmanaged(Sexp) = .empty;
    try out.append(p.allocator(), items[0]);
    var l = p.finishList(&out, .tree);
    for (items[1..], 1..) |item, i| {
        p.reduction = .{ .rule = 2, .start = 0 };
        p.lastEnd = @intCast(2 * i + 1);
        var grown = try p.extendList(l);
        try grown.append(p.allocator(), item);
        const next = p.keepList(&grown, .tree);
        try testing.expectEqual(l.list.id, next.list.id);
        l = next;
    }
    try testing.expectEqual(@as(u32, 1), p.nodeCount());
    try testing.expectEqual(Span{ .start = 0, .end = 5 }, p.span(l));
    try testing.expectEqual(@as(?u16, 2), p.ruleOf(l));
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

    var q = BaseParser.init(testing.allocator, "a b");
    defer q.deinit();
    try testing.expectError(error.ParseError, q.parse(.prog));
    try testing.expectEqualStrings("1:3: expected end of input, newline, \"=\" or \"+\", got identifier", try errorText(&q));

    var r = BaseParser.init(testing.allocator, "a + ?");
    defer r.deinit();
    try testing.expectError(error.ParseError, r.parse(.prog));
    try testing.expectEqualStrings("1:5: expected identifier or \"(\", got err", try errorText(&r));
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
