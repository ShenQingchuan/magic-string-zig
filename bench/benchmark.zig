const std = @import("std");
const MagicString = @import("magic_string").MagicString;

const BENCH_ITERATIONS = 10000;

pub fn main() !void {
    // 使用 C 分配器以获得更好的性能
    const allocator = std.heap.c_allocator;

    std.debug.print("运行基准测试 (迭代次数: {d})\n", .{BENCH_ITERATIONS});
    std.debug.print("========================================\n", .{});

    // 基准测试 1: 初始化和 toString
    try benchmarkInitToString(allocator);

    // 基准测试 2: appendLeft 操作
    try benchmarkAppendLeft(allocator);

    // 基准测试 3: appendRight 操作
    try benchmarkAppendRight(allocator);

    // 基准测试 4: overwrite 操作
    try benchmarkOverwrite(allocator);

    // 基准测试 5: 复杂组合操作
    try benchmarkComplex(allocator);

    // 基准测试 6: Source Map 生成
    try benchmarkSourceMap(allocator);
}

fn benchmarkInitToString(allocator: std.mem.Allocator) !void {
    const source = "Hello, World! This is a test string for benchmarking.";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        const result = try ms.toString();
        defer allocator.free(result);
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 1 - 初始化和 toString: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}

fn benchmarkAppendLeft(allocator: std.mem.Allocator) !void {
    const source = "world";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.appendLeft(0, "Hello ");
        try ms.appendLeft(0, ">>> ");

        const result = try ms.toString();
        defer allocator.free(result);
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 2 - appendLeft 操作: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}

fn benchmarkAppendRight(allocator: std.mem.Allocator) !void {
    const source = "Hello";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.appendRight(5, " world");
        try ms.appendRight(5, " <<<");

        const result = try ms.toString();
        defer allocator.free(result);
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 3 - appendRight 操作: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}

fn benchmarkOverwrite(allocator: std.mem.Allocator) !void {
    const source = "var x = 1 + 2";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.overwrite(4, 5, "a");
        try ms.overwrite(8, 9, "10");
        try ms.overwrite(12, 13, "20");

        const result = try ms.toString();
        defer allocator.free(result);
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 4 - overwrite 操作: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}

fn benchmarkComplex(allocator: std.mem.Allocator) !void {
    const source = "var x = 1";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.appendLeft(0, "// Comment\n");
        try ms.overwrite(4, 5, "answer");
        try ms.appendRight(9, ";");

        const result = try ms.toString();
        defer allocator.free(result);
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 5 - 复杂组合操作: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}

fn benchmarkSourceMap(allocator: std.mem.Allocator) !void {
    const source = "var x = 1";
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < BENCH_ITERATIONS) : (i += 1) {
        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.appendLeft(0, "// Comment\n");
        try ms.overwrite(4, 5, "answer");
        try ms.appendRight(9, ";");

        const map = try ms.generateMap(.{});
        defer {
            map.deinit();
            allocator.destroy(map);
        }
    }

    const elapsed = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
    std.debug.print("基准测试 6 - Source Map 生成: {d:.2} ms ({d:.2} μs/次)\n", .{ elapsed_ms, elapsed_ms * 1000 / BENCH_ITERATIONS });
}
