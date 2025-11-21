const std = @import("std");
const testing = std.testing;
const MagicString = @import("magic_string").MagicString;
const MagicStringStack = @import("magic_string").MagicStringStack;

test "基础功能: 初始化和 toString" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "Hello, World!");
    defer ms.deinit();

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello, World!", result);
}

test "基础功能: 空字符串" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "");
    defer ms.deinit();

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("", result);
}

test "基础功能: Unicode 支持" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "你好 🎉");
    defer ms.deinit();

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("你好 🎉", result);
}

test "appendLeft: 在开头插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "world");
    defer ms.deinit();

    try ms.appendLeft(0, "Hello ");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello world", result);
}

test "appendLeft: 在中间插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "ac");
    defer ms.deinit();

    try ms.appendLeft(1, "b");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("abc", result);
}

test "appendLeft: 多次插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "world");
    defer ms.deinit();

    try ms.appendLeft(0, "Hello ");
    try ms.appendLeft(0, ">>> ");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello >>> world", result);
}

test "appendRight: 在末尾插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "Hello");
    defer ms.deinit();

    try ms.appendRight(5, " world");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello world", result);
}

test "appendRight: 在中间插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "ac");
    defer ms.deinit();

    try ms.appendRight(1, "b");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("abc", result);
}

test "appendRight: 多次插入" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "Hello");
    defer ms.deinit();

    try ms.appendRight(5, " world");
    try ms.appendRight(5, " <<<");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello world <<<", result);
}

test "混合操作: appendLeft 和 appendRight" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.appendLeft(0, "// Comment\n");
    try ms.appendRight(9, ";");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("// Comment\nvar x = 1;", result);
}

test "overwrite: 替换整个字符串" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "problems = 99");
    defer ms.deinit();

    try ms.overwrite(0, 8, "answer");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("answer = 99", result);
}

test "overwrite: 替换部分内容" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.overwrite(4, 5, "answer");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("var answer = 1", result);
}

test "overwrite: 用空字符串替换（删除）" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.overwrite(0, 4, "");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("x = 1", result);
}

test "overwrite: 保留之前的 appendLeft/Right" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.appendLeft(0, "// Start\n");
    try ms.appendRight(9, ";");
    try ms.overwrite(4, 5, "answer");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("// Start\nvar answer = 1;", result);
}

test "overwrite: 多次替换" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1 + 2");
    defer ms.deinit();

    try ms.overwrite(4, 5, "a");
    try ms.overwrite(8, 9, "10");
    try ms.overwrite(12, 13, "20");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("var a = 10 + 20", result);
}

test "overwrite: 在替换后的位置 appendLeft" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "abc");
    defer ms.deinit();

    try ms.overwrite(1, 2, "XXX");
    try ms.appendLeft(1, ">>>");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("a>>>XXXc", result);
}

test "overwrite: 在替换后的位置 appendRight" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "abc");
    defer ms.deinit();

    try ms.overwrite(1, 2, "XXX");
    try ms.appendRight(1, "<<<");

    const result = try ms.toString();
    defer allocator.free(result);

    try testing.expectEqualStrings("a<<<XXXc", result);
}

test "Source Map: 基础生成" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "abc");
    defer ms.deinit();

    const map = try ms.generateMap(.{});
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    try testing.expectEqual(@as(u8, 3), map.version);
    try testing.expectEqual(@as(usize, 1), map.sources.len);
}

test "Source Map: overwrite 操作" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.overwrite(4, 5, "answer");

    const result = try ms.toString();
    defer allocator.free(result);
    try testing.expectEqualStrings("var answer = 1", result);

    const map = try ms.generateMap(.{});
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    try testing.expectEqual(@as(u8, 3), map.version);
    try testing.expect(map.mappings.len > 0);
}

test "Source Map: appendLeft 操作" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "hello");
    defer ms.deinit();

    try ms.appendLeft(0, ">>> ");

    const result = try ms.toString();
    defer allocator.free(result);
    try testing.expectEqualStrings(">>> hello", result);

    const map = try ms.generateMap(.{});
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    try testing.expectEqual(@as(u8, 3), map.version);
}

test "Source Map: 复杂操作组合" {
    const allocator = testing.allocator;

    const ms = try MagicString.init(allocator, "var x = 1");
    defer ms.deinit();

    try ms.appendLeft(0, "// Comment\n");
    try ms.overwrite(4, 5, "answer");
    try ms.appendRight(9, ";");

    const result = try ms.toString();
    defer allocator.free(result);
    try testing.expectEqualStrings("// Comment\nvar answer = 1;", result);

    const map = try ms.generateMap(.{});
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    try testing.expectEqual(@as(u8, 3), map.version);
}

test "MagicStringStack: commit and rollback" {
    const allocator = testing.allocator;
    const stack = try MagicStringStack.init(allocator, "world");
    defer stack.deinit();

    try stack.appendLeft(0, "Hello ");

    const first = try stack.toString();
    defer allocator.free(first);
    try testing.expectEqualStrings("Hello world", first);

    try stack.commit();
    try stack.overwrite(6, 11, "Zig");

    const second = try stack.toString();
    defer allocator.free(second);
    try testing.expectEqualStrings("Hello Zig", second);

    try stack.rollback();

    const reverted = try stack.toString();
    defer allocator.free(reverted);
    try testing.expectEqualStrings("Hello world", reverted);
}

test "MagicStringStack: multiple commits" {
    const allocator = testing.allocator;
    const stack = try MagicStringStack.init(allocator, "let value = compute();");
    defer stack.deinit();

    try stack.appendLeft(0, "// header\n");
    try stack.overwrite(4, 9, "result");
    try stack.commit();

    const stage_two_source = try stack.toString();
    defer allocator.free(stage_two_source);

    try stack.appendRight(stage_two_source.len, "\nconsole.log(result);");
    const compute_pattern = "compute()";
    const compute_idx = std.mem.indexOf(u8, stage_two_source, compute_pattern) orelse unreachable;
    try stack.overwrite(compute_idx, compute_idx + compute_pattern.len, "track()");

    const output = try stack.toString();
    defer allocator.free(output);

    try testing.expectEqualStrings("// header\nlet result = track();\nconsole.log(result);", output);
}
