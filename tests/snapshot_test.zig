const std = @import("std");
const MagicString = @import("magic_string").MagicString;

// 定义输出结构
const ScenarioResult = struct {
    name: []const u8,
    content: []const u8,
    map: []const u8, // JSON string of the map
};

// Helper function to write JSON using std.json.fmt
fn writeJsonValue(writer: *std.Io.Writer, value: anytype) !void {
    const formatter = std.json.fmt(value, .{ .whitespace = .minified });
    try formatter.format(writer);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results: std.ArrayList(ScenarioResult) = .empty;
    defer results.deinit(allocator);

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

        try results.append(allocator, .{
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

        try results.append(allocator, .{
            .name = "multiple_edits",
            .content = content,
            .map = map_json,
        });
    }

    // Scenario 3: 多行插桩与多次 insert
    {
        const raw_source =
            \\function math(a, b) {
            \\  const sum = a + b;
            \\  return sum;
            \\}
            \\
        ;
        const source = std.mem.trim(u8, raw_source, " \n\r\t");

        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.appendLeft(0, "/* header */\n");

        const brace_idx = std.mem.indexOfScalar(u8, source, '{') orelse unreachable;
        try ms.appendLeft(brace_idx + 1, "\n  console.time(\"math\");");

        const sum_line = "  const sum = a + b;";
        const sum_idx = std.mem.indexOf(u8, source, sum_line) orelse unreachable;
        try ms.appendRight(sum_idx + sum_line.len, "\n  console.log(sum);");

        const return_line = "  return sum;";
        const return_idx = std.mem.indexOf(u8, source, return_line) orelse unreachable;
        try ms.appendLeft(return_idx, "  console.timeEnd(\"math\");\n");
        try ms.overwrite(return_idx, return_idx + return_line.len, "  return sum * 2;");

        const closing_idx = std.mem.lastIndexOfScalar(u8, source, '}') orelse unreachable;
        try ms.appendRight(closing_idx + 1, "\n// done");

        try ms.appendRight(source.len, "\n/* footer */");

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

        try results.append(allocator, .{
            .name = "instrumented_function",
            .content = content,
            .map = map_json,
        });
    }

    // Scenario 4: 多处 wrap 与边界插入
    {
        const raw_source =
            \\let result = format(user.firstName);
            \\result += ':' + format(user.lastName);
            \\return result;
            \\
        ;
        const source = std.mem.trim(u8, raw_source, " \n\r\t");

        const ms = try MagicString.init(allocator, source);
        defer ms.deinit();

        try ms.overwrite(0, "let".len, "const");

        const first_call = "format(user.firstName)";
        const first_start = std.mem.indexOf(u8, source, first_call) orelse unreachable;
        try ms.appendLeft(first_start, "track(");
        try ms.appendRight(first_start + first_call.len, ", \"first\")");

        const second_call = "format(user.lastName)";
        const second_start = std.mem.indexOf(u8, source, second_call) orelse unreachable;
        try ms.appendLeft(second_start, "track(");
        try ms.appendRight(second_start + second_call.len, ", \"last\")");

        const return_idx = std.mem.indexOf(u8, source, "return result;") orelse unreachable;
        try ms.appendLeft(return_idx, "// finalize\n");

        const first_line_sep = ";\n";
        const first_line_idx = std.mem.indexOf(u8, source, first_line_sep) orelse unreachable;
        try ms.appendRight(first_line_idx + 1, " // init done");

        try ms.appendRight(source.len, "\nconsole.log(result);");

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

        try results.append(allocator, .{
            .name = "tracked_calls",
            .content = content,
            .map = map_json,
        });
    }

    // 输出到 stdout (JSON)
    const stdout_file = std.fs.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("[\n");
    for (results.items, 0..) |res, i| {
        if (i > 0) try stdout.writeAll(",\n");
        try stdout.print("  {{\n    \"name\": \"{s}\",\n", .{res.name});
        try stdout.writeAll("    \"content\": ");
        try writeJsonValue(stdout, res.content);
        try stdout.writeAll(",\n    \"map\": ");
        // map 已经是 JSON 字符串，但我们需要将其作为字符串值嵌入，所以再次 encode
        try writeJsonValue(stdout, res.map);
        try stdout.writeAll("\n  }");
    }
    try stdout.writeAll("\n]\n");

    // Flush the output buffer
    try stdout.flush();

    // 清理内存
    for (results.items) |res| {
        allocator.free(res.content);
        allocator.free(res.map);
    }
}
