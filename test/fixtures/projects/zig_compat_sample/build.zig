const std = @import("std");

// Portable across Zig 0.13-0.16: 0.14+ build tests from a root module, while 0.13
// takes the root source file directly. The condition is comptime-known, so the
// untaken branch is never analyzed.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tests = if (@hasField(std.Build.TestOptions, "root_module"))
        b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path("src/calc.zig"),
            .target = target,
            .optimize = optimize,
        }) })
    else
        b.addTest(.{
            .root_source_file = b.path("src/calc.zig"),
            .target = target,
            .optimize = optimize,
        });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
