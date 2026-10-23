//! hooks.zig: what the Tally language server knows beyond the grammar.
//!
//! `nexus --editor` wrote this file once and never writes it again; it
//! is the language's to fill in (docs/LSP.md). lsp.zig calls only the
//! functions written here: each `= lsp.todo` leaves its features off.
//! Replace one with a function of the signature above it to turn them on.
//!
//! The editor suite's modules/ server: the hooks.zig `--editor` writes,
//! with `resolveImport` written. `use std_NAME` imports NAME.tally beside
//! the importing file.

const std = @import("std");
const lsp = @import("lsp.zig");
const parser = @import("parser.zig");

// --- The parse: these replace what lsp.zig derives from the grammar ------

/// The errors of one file as it parses, in place of the grammar's: every
/// error the tolerant parse repairs past with `@repair`, else the strict
/// parse's one error.
/// pub fn parseDiagnostics(arena: std.mem.Allocator, path: []const u8, text: []const u8) ![]const lsp.Diagnostic
pub const parseDiagnostics = lsp.todo;

/// The semantic tokens of a file, in order, in place of each token's
/// `@highlight` scope.
/// pub fn tokens(arena: std.mem.Allocator, path: []const u8, text: []const u8) ![]const lsp.Token
pub const tokens = lsp.todo;

/// The outline of a file. Turns on the outline and breadcrumbs.
/// pub fn symbols(arena: std.mem.Allocator, path: []const u8, text: []const u8) ![]const lsp.OutlineItem
pub const symbols = lsp.todo;

/// The folding ranges of a file, in place of its nodes over several lines
/// and its runs of comments.
/// pub fn folds(arena: std.mem.Allocator, path: []const u8, text: []const u8) ![]const lsp.Fold
pub const folds = lsp.todo;

/// The file formatted, or null when it is formatted already. Turns on
/// Format Document.
/// pub fn format(arena: std.mem.Allocator, path: []const u8, text: []const u8) !?[]const u8
pub const format = lsp.todo;

/// The file an import of `@lsp` names when its name is a module's, not
/// a path; null to take the name as a path relative to the file `from`.
/// The client's `modules` setting answers before it.
/// pub fn resolveImport(arena: std.mem.Allocator, from: []const u8, name: []const u8) !?[]const u8
pub fn resolveImport(arena: std.mem.Allocator, from: []const u8, name: []const u8) !?[]const u8 {
    if (!std.mem.startsWith(u8, name, "std_")) return null;
    const dir = std.fs.path.dirname(from) orelse return null;
    return try std.fs.path.join(arena, &.{ dir, try arena.print("{s}.tally", .{name["std_".len..]}) });
}

// --- The analysis: the program checked as a whole -------------------------

/// What `analyze` keeps for the functions below.
pub const Analysis = struct {};

/// Check the program `root` belongs to (the file opened or saved, or the
/// client's `root` option), reading files with `overlay.read`, which
/// gives an open file's text in place of the file on disk. Runs when a
/// file is opened or saved; what it returns lives until the next run.
/// Every function below reads it, so writing any of them needs this one.
/// pub fn analyze(arena: std.mem.Allocator, root: []const u8, overlay: lsp.Overlay) !lsp.Analyzed(Analysis)
pub const analyze = lsp.todo;

/// The declaration the name at `at` refers to (or declares). Turns on go
/// to definition, references, document highlight and rename.
/// pub fn symbolAt(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) !?lsp.Symbol
pub const symbolAt = lsp.todo;

/// The type of the expression at `at`. With `describe`, turns on hover
/// over expressions and go to type definition.
/// pub fn typeAt(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) !?lsp.TypeId
pub const typeAt = lsp.todo;

/// Markdown for a symbol or a type, and where the type is declared.
/// Turns on hover.
/// pub fn describe(a: *Analysis, arena: std.mem.Allocator, subject: lsp.Subject) !?lsp.Description
pub const describe = lsp.todo;

/// The members of what is before the `.` (or the language's member
/// operator) at `at`; null when `at` is not after one. Completion offers
/// them alone.
/// pub fn members(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) !?[]const lsp.Symbol
pub const members = lsp.todo;

/// The names an import at `at` can name; null when `at` is not in one.
/// pub fn modules(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) !?[]const []const u8
pub const modules = lsp.todo;

/// The names in scope at `at`. Completion offers them with the keywords.
/// pub fn visible(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) ![]const lsp.Symbol
pub const visible = lsp.todo;

/// The signatures of the call around `at`. Turns on signature help.
/// pub fn signatures(a: *Analysis, arena: std.mem.Allocator, at: lsp.Pos) !?lsp.SignatureHelp
pub const signatures = lsp.todo;

/// Every use of `symbol`, its declaration included, in place of asking
/// `symbolAt` at every token of every file the analysis read.
/// pub fn references(a: *Analysis, arena: std.mem.Allocator, symbol: lsp.Symbol) ![]const lsp.Span
pub const references = lsp.todo;

/// Whether `symbol` may be renamed (not one of the standard library's).
/// pub fn renamable(a: *Analysis, symbol: lsp.Symbol) bool
pub const renamable = lsp.todo;

/// The characters that open completion besides word characters.
pub const completionTriggers: []const []const u8 = &.{};
