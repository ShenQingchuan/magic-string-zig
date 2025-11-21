const std = @import("std");
const vlq = @import("vlq.zig");
const MagicString = @import("magic_string.zig").MagicString;
const Segment = @import("magic_string.zig").Segment;

// Helper function to write JSON value using std.json.fmt
fn writeJsonValue(writer: anytype, value: anytype) !void {
    const formatter = std.json.fmt(value, .{ .whitespace = .minified });
    try formatter.format(writer);
}

/// Source Map v3 生成器配置选项
pub const SourceMapOptions = struct {
    /// 生成代码的文件名（可选）
    file: ?[]const u8 = null,

    /// 源文件根路径（可选）
    source_root: ?[]const u8 = null,

    /// 源文件名（默认为 null，会使用 "source.js"）
    source: ?[]const u8 = null,

    /// 是否包含源文件内容
    include_content: bool = false,

    /// 是否美化 JSON 输出
    hires: bool = false,
};

/// Source Map v3 结构
///
/// 符合 Source Map v3 规范：
/// https://sourcemaps.info/spec.html
///
/// 核心字段说明：
/// - version: 固定为 3（Source Map v3）
/// - file: 生成的代码文件名
/// - sourceRoot: 源文件的根路径
/// - sources: 源文件列表
/// - sourcesContent: 源文件内容列表（可选）
/// - names: 符号名称列表（用于标识符映射）
/// - mappings: 编码的映射数据（VLQ Base64 格式）
pub const SourceMap = struct {
    version: u8 = 3,
    file: ?[]const u8 = null,
    source_root: ?[]const u8 = null,
    sources: []const []const u8,
    sources_content: ?[]const ?[]const u8 = null,
    names: []const []const u8,
    mappings: []const u8,

    allocator: std.mem.Allocator,

    /// 释放 Source Map 占用的内存
    pub fn deinit(self: *SourceMap) void {
        // 释放 sources 列表
        for (self.sources) |source| {
            self.allocator.free(source);
        }
        self.allocator.free(self.sources);

        // 释放 sourcesContent
        if (self.sources_content) |content| {
            for (content) |item| {
                if (item) |s| self.allocator.free(s);
            }
            self.allocator.free(content);
        }

        // 释放 names 列表
        for (self.names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.names);

        // 释放 file 和 source_root
        if (self.file) |file| self.allocator.free(file);
        if (self.source_root) |root| self.allocator.free(root);

        // 释放 mappings
        self.allocator.free(self.mappings);
    }

    /// 将 Source Map 序列化为 JSON 字符串
    ///
    /// 返回符合 Source Map v3 规范的 JSON 字符串
    pub fn toJSON(self: *const SourceMap, allocator: std.mem.Allocator) ![]const u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        // ArrayList.writer() 返回旧的 Writer，需要适配到新 API
        var old_writer = output.writer(allocator);
        var adapter = old_writer.adaptToNewApi(&.{});
        const writer = &adapter.new_interface;

        // 开始 JSON 对象
        try writer.writeAll("{");

        // version (必需)
        try writer.print("\"version\":{d}", .{self.version});

        // file (可选)
        if (self.file) |file| {
            try writer.writeAll(",\"file\":");
            try writeJsonValue(writer, file);
        }

        // sourceRoot (可选)
        if (self.source_root) |root| {
            try writer.writeAll(",\"sourceRoot\":");
            try writeJsonValue(writer, root);
        }

        // sources (必需)
        try writer.writeAll(",\"sources\":[");
        for (self.sources, 0..) |source, i| {
            if (i > 0) try writer.writeAll(",");
            try writeJsonValue(writer, source);
        }
        try writer.writeAll("]");

        // sourcesContent (可选)
        if (self.sources_content) |content| {
            try writer.writeAll(",\"sourcesContent\":[");
            for (content, 0..) |item, i| {
                if (i > 0) try writer.writeAll(",");
                if (item) |s| {
                    try writeJsonValue(writer, s);
                } else {
                    try writer.writeAll("null");
                }
            }
            try writer.writeAll("]");
        }

        // names (必需)
        try writer.writeAll(",\"names\":[");
        for (self.names, 0..) |name, i| {
            if (i > 0) try writer.writeAll(",");
            try writeJsonValue(writer, name);
        }
        try writer.writeAll("]");

        // mappings (必需)
        try writer.writeAll(",\"mappings\":");
        try writeJsonValue(writer, self.mappings);

        // 结束 JSON 对象
        try writer.writeAll("}");

        // 刷新缓冲区
        try writer.flush();

        return output.toOwnedSlice(allocator);
    }
};

/// Source Map 生成器
///
/// 负责从 MagicString 实例生成 Source Map
pub const SourceMapGenerator = struct {
    allocator: std.mem.Allocator,
    magic_string: *const MagicString,
    options: SourceMapOptions,

    pub fn init(allocator: std.mem.Allocator, magic_string: *const MagicString, options: SourceMapOptions) SourceMapGenerator {
        return .{
            .allocator = allocator,
            .magic_string = magic_string,
            .options = options,
        };
    }

    /// 生成 Source Map
    ///
    /// 算法说明：
    /// 1. 遍历所有 Segment
    /// 2. 为每个来自原始源码的字符生成映射
    /// 3. 使用 VLQ 编码压缩映射数据
    ///
    /// mappings 格式：
    /// - 行之间用 `;` 分隔
    /// - 同一行的段之间用 `,` 分隔
    /// - 每个段包含 1、4 或 5 个 VLQ 编码的字段：
    ///   [生成列, 源文件索引, 源行, 源列, 名称索引]
    pub fn generate(self: *SourceMapGenerator) !*SourceMap {
        // 准备源文件列表
        const source_name = self.options.source orelse "";
        const sources = try self.allocator.alloc([]const u8, 1);
        sources[0] = try self.allocator.dupe(u8, source_name);
        errdefer {
            for (sources) |s| self.allocator.free(s);
            self.allocator.free(sources);
        }

        // 准备源文件内容（如果需要）
        const sources_content = if (self.options.include_content) blk: {
            const content = try self.allocator.alloc(?[]const u8, 1);
            content[0] = try self.allocator.dupe(u8, self.magic_string.original);
            break :blk content;
        } else null;
        errdefer if (sources_content) |content| {
            for (content) |item| {
                if (item) |s| self.allocator.free(s);
            }
            self.allocator.free(content);
        };

        // 生成 mappings 字符串
        const mappings = try self.generateMappings();
        errdefer self.allocator.free(mappings);

        // 创建 Source Map 对象
        const map = try self.allocator.create(SourceMap);
        map.* = SourceMap{
            .allocator = self.allocator,
            .version = 3,
            .file = if (self.options.file) |f| try self.allocator.dupe(u8, f) else null,
            .source_root = if (self.options.source_root) |r| try self.allocator.dupe(u8, r) else null,
            .sources = sources,
            .sources_content = sources_content,
            .names = try self.allocator.alloc([]const u8, 0), // 不支持 names
            .mappings = mappings,
        };

        return map;
    }

    /// 生成 mappings 字符串
    ///
    /// mappings 编码说明：
    /// - 每行生成代码对应一行 mappings（单行代码用单行 mappings）
    /// - 行内的每个段描述一个映射关系
    /// - 使用相对偏移量编码（除了每行的第一个段）
    ///
    /// 每个段的字段（VLQ 编码）：
    /// 1. 生成代码的列偏移（相对于上一段）
    /// 2. 源文件索引（相对于上一段，我们只有一个源文件所以通常是 0）
    /// 3. 源代码的行偏移（相对于上一段）
    /// 4. 源代码的列偏移（相对于上一段）
    /// 5. 名称索引（可选，我们暂不使用）
    fn generateMappings(self: *SourceMapGenerator) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        const line_starts = try self.computeLineStartOffsets();
        defer self.allocator.free(line_starts);

        // 跟踪上一个映射的位置（用于计算相对偏移）
        var prev_gen_column: i32 = 0;
        var prev_source_index: i32 = 0;
        var prev_source_line: i32 = 0;
        var prev_source_column: i32 = 0;

        // 当前生成代码的位置
        var gen_line: usize = 0;
        var gen_column: usize = 0;
        var has_segment_in_line = false; // 跟踪当前行是否已经有 segment

        // 遍历所有 Segment
        for (self.magic_string.segments.items) |*segment| {
            // 处理 intro（插入在左侧的内容）
            if (segment.intro) |intro| {
                // 检查 intro 中是否有换行符
                for (intro) |c| {
                    if (c == '\n') {
                        // 遇到换行符，添加行分隔符并重置
                        if (has_segment_in_line) {
                            try result.append(self.allocator, ';');
                            has_segment_in_line = false;
                        } else {
                            // 如果当前行没有 segment，也需要添加空行标记
                            try result.append(self.allocator, ';');
                        }
                        gen_line += 1;
                        gen_column = 0;
                        prev_gen_column = 0; // 新行的第一个 segment 使用绝对位置
                    } else {
                        gen_column += 1;
                    }
                }
            }

            // 处理 Segment 的主体内容
            if (segment.source_offset) |source_offset| {
                if (segment.content.len > 0) {
                    const start_lc = lineColumnFromOffset(line_starts, source_offset);
                    var source_line = start_lc.line;
                    var source_column = start_lc.column;
                    var first_in_line = true;

                    for (segment.content) |c| {
                        if (c == '\n') {
                            if (has_segment_in_line) {
                                try result.append(self.allocator, ';');
                                has_segment_in_line = false;
                            } else {
                                try result.append(self.allocator, ';');
                            }
                            gen_line += 1;
                            gen_column = 0;
                            prev_gen_column = 0;
                            source_line += 1;
                            source_column = 0;
                            first_in_line = true;
                        } else {
                            if (first_in_line) {
                                try self.appendMapping(
                                    &result,
                                    gen_column,
                                    source_line,
                                    source_column,
                                    &has_segment_in_line,
                                    &prev_gen_column,
                                    &prev_source_index,
                                    &prev_source_line,
                                    &prev_source_column,
                                );
                                first_in_line = false;
                            }
                            gen_column += 1;
                            source_column += 1;
                        }
                    }
                }
            } else {
                // 这是插入的内容（overwrite 替换的内容）
                // 如果它覆盖了原始内容（即是替换操作），且有内容输出，需要生成映射
                if (segment.original_end > segment.original_start and segment.content.len > 0) {
                    const lc = lineColumnFromOffset(line_starts, segment.original_start);
                    var first_in_line = true;

                    for (segment.content) |c| {
                        if (c == '\n') {
                            if (has_segment_in_line) {
                                try result.append(self.allocator, ';');
                                has_segment_in_line = false;
                            } else {
                                try result.append(self.allocator, ';');
                            }
                            gen_line += 1;
                            gen_column = 0;
                            prev_gen_column = 0;
                            first_in_line = true;
                        } else {
                            if (first_in_line) {
                                try self.appendMapping(
                                    &result,
                                    gen_column,
                                    lc.line,
                                    lc.column,
                                    &has_segment_in_line,
                                    &prev_gen_column,
                                    &prev_source_index,
                                    &prev_source_line,
                                    &prev_source_column,
                                );
                                first_in_line = false;
                            }
                            gen_column += 1;
                        }
                    }
                } else {
                    for (segment.content) |c| {
                        if (c == '\n') {
                            if (has_segment_in_line) {
                                try result.append(self.allocator, ';');
                                has_segment_in_line = false;
                            } else {
                                try result.append(self.allocator, ';');
                            }
                            gen_line += 1;
                            gen_column = 0;
                            prev_gen_column = 0;
                        } else {
                            gen_column += 1;
                        }
                    }
                }
            }

            // 处理 outro（插入在右侧的内容）
            if (segment.outro) |outro| {
                // 检查 outro 中是否有换行符
                for (outro) |c| {
                    if (c == '\n') {
                        if (has_segment_in_line) {
                            try result.append(self.allocator, ';');
                            has_segment_in_line = false;
                        } else {
                            try result.append(self.allocator, ';');
                        }
                        gen_line += 1;
                        gen_column = 0;
                        prev_gen_column = 0;
                    } else {
                        gen_column += 1;
                    }
                }
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn appendMapping(
        self: *SourceMapGenerator,
        result: *std.ArrayList(u8),
        gen_column: usize,
        source_line: usize,
        source_column: usize,
        has_segment_in_line: *bool,
        prev_gen_column: *i32,
        prev_source_index: *i32,
        prev_source_line: *i32,
        prev_source_column: *i32,
    ) !void {
        const gen_col_delta = @as(i32, @intCast(gen_column)) - prev_gen_column.*;
        const source_index_delta = 0 - prev_source_index.*;
        const source_line_delta = @as(i32, @intCast(source_line)) - prev_source_line.*;
        const source_col_delta = @as(i32, @intCast(source_column)) - prev_source_column.*;

        const fields = [4]i32{ gen_col_delta, source_index_delta, source_line_delta, source_col_delta };
        const encoded = try vlq.encodeVLQSegment(self.allocator, &fields);
        defer self.allocator.free(encoded);

        if (has_segment_in_line.*) {
            try result.append(self.allocator, ',');
        }

        try result.appendSlice(self.allocator, encoded);
        has_segment_in_line.* = true;

        prev_gen_column.* = @as(i32, @intCast(gen_column));
        prev_source_index.* = 0;
        prev_source_line.* = @as(i32, @intCast(source_line));
        prev_source_column.* = @as(i32, @intCast(source_column));
    }

    fn computeLineStartOffsets(self: *SourceMapGenerator) ![]usize {
        var starts: std.ArrayList(usize) = .empty;
        errdefer starts.deinit(self.allocator);

        try starts.append(self.allocator, 0);

        for (self.magic_string.original, 0..) |c, idx| {
            if (c == '\n' and idx + 1 < self.magic_string.original.len) {
                try starts.append(self.allocator, idx + 1);
            }
        }

        return starts.toOwnedSlice(self.allocator);
    }

    fn lineColumnFromOffset(line_starts: []const usize, offset: usize) LineColumn {
        var left: usize = 0;
        var right: usize = line_starts.len;

        while (left + 1 < right) {
            const mid = left + (right - left) / 2;
            if (line_starts[mid] <= offset) {
                left = mid;
            } else {
                right = mid;
            }
        }

        return .{
            .line = left,
            .column = offset - line_starts[left],
        };
    }

    const LineColumn = struct {
        line: usize,
        column: usize,
    };
};

// ============================================================================
// 单元测试
// ============================================================================

test "SourceMap: 基础 JSON 生成" {
    const allocator = std.testing.allocator;

    const sources = try allocator.alloc([]const u8, 1);
    sources[0] = try allocator.dupe(u8, "test.js");

    const names = try allocator.alloc([]const u8, 0);

    var map = SourceMap{
        .allocator = allocator,
        .sources = sources,
        .names = names,
        .mappings = try allocator.dupe(u8, "AAAA"),
    };
    defer map.deinit();

    const json = try map.toJSON(allocator);
    defer allocator.free(json);

    // 验证包含必需字段
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sources\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mappings\"") != null);
}

test "SourceMap: 生成简单映射" {
    const allocator = std.testing.allocator;
    const MagicStringType = @import("magic_string.zig").MagicString;

    const ms = try MagicStringType.init(allocator, "abc");
    defer ms.deinit();

    var generator = SourceMapGenerator.init(allocator, ms, .{
        .file = "output.js",
        .source = "input.js",
    });

    const map = try generator.generate();
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    // 验证基本结构
    try std.testing.expectEqual(@as(u8, 3), map.version);
    try std.testing.expectEqualStrings("output.js", map.file.?);
    try std.testing.expectEqual(@as(usize, 1), map.sources.len);
    try std.testing.expectEqualStrings("input.js", map.sources[0]);
}
