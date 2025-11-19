const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建 magic-string 库模块
    const magic_string_module = b.addModule("magic_string", .{
        .root_source_file = b.path("src/magic_string.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加单元测试
    const tests = b.addTest(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "运行所有单元测试");
    test_step.dependOn(&run_tests.step);

    // 添加性能基准测试
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("bench/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast, // 基准测试使用最优化
    });
    bench.linkLibC();
    bench.root_module.addImport("magic_string", magic_string_module);

    b.installArtifact(bench);

    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "运行性能基准测试");
    bench_step.dependOn(&run_bench.step);
}
