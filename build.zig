//! Nexus — Build Configuration
//!
//! Builds the nexus tool that reads .grammar files and generates
//! parser.zig (lexer + SLR(1) parser producing S-expressions).
//!
//! Usage:
//!   zig build                    — build nexus
//!   zig build run -- <args>      — run with arguments

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nexus_mod = b.createModule(.{
        .root_source_file = b.path("src/nexus.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "nexus",
        .root_module = nexus_mod,
    });

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = ".." } },
        .dest_sub_path = "bin/nexus",
    });
    b.getInstallStep().dependOn(&install.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run nexus");
    run_step.dependOn(&run_cmd.step);

    const test_cmd = b.addSystemCommand(&.{ "bash", "test/run" });
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
