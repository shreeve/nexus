//! Nexus — Build Configuration
//!
//! Builds bin/nexus, which reads a .grammar file and generates a parser
//! module (DFA lexer + LALR(1) parser producing S-expressions).
//!
//! Usage:
//!   zig build                    — build nexus
//!   zig build run -- <args>      — run with arguments
//!   zig build unit               — the generator's unit tests
//!   zig build test               — the whole suite (test/run)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nexus_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
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
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run nexus");
    run_step.dependOn(&run_cmd.step);

    // The generator's Zig unit tests (lowering, patterns and automata, the
    // LR core, semantics, the runtime template), in a separate test binary;
    // the `nexus` executable never links this code. `test/run` runs them as
    // unit/nexus.
    const unit_tests = b.addRunArtifact(b.addTest(.{ .root_module = nexus_mod }));
    const unit_step = b.step("unit", "Run the generator's unit tests");
    unit_step.dependOn(&unit_tests.step);

    // The whole suite (test/README.md), unit tests included.
    const test_cmd = b.addSystemCommand(&.{"bash"});
    test_cmd.addFileArg(b.path("test/run"));
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run the test suite (test/run)");
    test_step.dependOn(&test_cmd.step);
}
