const std = @import("std");
const MagicString = @import("magic_string").MagicString;

// 定义输出结构
const ScenarioResult = struct {
    name: []const u8,
    content: []const u8,
    map: []const u8, // JSON string of the map
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results = std.ArrayList(ScenarioResult).init(allocator);
    defer results.deinit();

    // Scenario 1: 复杂组合操作
    {
        const ms = try MagicString.init(allocator, "var x = 1");
        defer ms.deinit();

        try ms.appendLeft(0, "// Comment\n");
        try ms.overwrite(4, 5, "answer");
        try ms.appendRight(9, ";");

        const content = try ms.toString();

        const map_obj = try ms.generateMap(.{
            .source = "input.js",
            .file = "output.js",
            .include_content = true,
        });
        defer {
            map_obj.deinit();
            allocator.destroy(map_obj);
        }
        const map_json = try map_obj.toJSON(allocator);

        try results.append(.{
            .name = "complex_combination",
            .content = content, // ownership transferred to results, will need deep free logic or just leak for this short-lived process
            .map = map_json,
        });
    }

    // Scenario 2: 多次插入和删除
    {
        const ms = try MagicString.init(allocator, "1234567890");
        defer ms.deinit();

        try ms.overwrite(0, 2, "A"); // 12 -> A
        try ms.appendLeft(5, "-"); // after 5
        try ms.appendRight(5, "+"); // after 5
        try ms.overwrite(8, 10, ""); // 90 -> ""

        const content = try ms.toString();

        const map_obj = try ms.generateMap(.{
            .source = "input.js",
            .file = "output.js",
            .include_content = true,
        });
        defer {
            map_obj.deinit();
            allocator.destroy(map_obj);
        }
        const map_json = try map_obj.toJSON(allocator);

        try results.append(.{
            .name = "multiple_edits",
            .content = content,
            .map = map_json,
        });
    }

    // 输出到 stdout (JSON)
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("[\n");
    for (results.items, 0..) |res, i| {
        if (i > 0) try stdout.writeAll(",\n");
        try stdout.print("  {{\n    \"name\": \"{s}\",\n", .{res.name});
        try stdout.writeAll("    \"content\": ");
        try std.json.encodeJsonString(res.content, .{}, stdout);
        try stdout.writeAll(",\n    \"map\": ");
        // map 已经是 JSON 字符串，但我们需要将其作为字符串值嵌入，所以再次 encode
        // 或者我们可以直接解析它并嵌入对象，但这在 Zig 中比较麻烦。
        // 简单起见，我们把 map 作为字符串传递，在 JS 端 JSON.parse
        // 不，为了直接比较，我们应该让 map 也是对象。
        // 但这需要解析 map_json。
        // 让我们保持 map 为字符串，JS 端再 parse。
        try std.json.encodeJsonString(res.map, .{}, stdout);
        try stdout.writeAll("\n  }");
    }
    try stdout.writeAll("\n]\n");

    // 清理内存
    for (results.items) |res| {
        allocator.free(res.content);
        allocator.free(res.map);
    }
}
