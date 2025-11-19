const std = @import("std");
const vlq = @import("vlq.zig");
const MagicString = @import("magic_string.zig").MagicString;
const Segment = @import("magic_string.zig").Segment;

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
        var output = std.ArrayList(u8).init(allocator);
        errdefer output.deinit();

        const writer = output.writer();

        // 开始 JSON 对象
        try writer.writeAll("{");

        // version (必需)
        try writer.print("\"version\":{d}", .{self.version});

        // file (可选)
        if (self.file) |file| {
            try writer.writeAll(",\"file\":");
            try std.json.encodeJsonString(file, .{}, writer);
        }

        // sourceRoot (可选)
        if (self.source_root) |root| {
            try writer.writeAll(",\"sourceRoot\":");
            try std.json.encodeJsonString(root, .{}, writer);
        }

        // sources (必需)
        try writer.writeAll(",\"sources\":[");
        for (self.sources, 0..) |source, i| {
            if (i > 0) try writer.writeAll(",");
            try std.json.encodeJsonString(source, .{}, writer);
        }
        try writer.writeAll("]");

        // sourcesContent (可选)
        if (self.sources_content) |content| {
            try writer.writeAll(",\"sourcesContent\":[");
            for (content, 0..) |item, i| {
                if (i > 0) try writer.writeAll(",");
                if (item) |s| {
                    try std.json.encodeJsonString(s, .{}, writer);
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
            try std.json.encodeJsonString(name, .{}, writer);
        }
        try writer.writeAll("]");

        // mappings (必需)
        try writer.writeAll(",\"mappings\":");
        try std.json.encodeJsonString(self.mappings, .{}, writer);

        // 结束 JSON 对象
        try writer.writeAll("}");

        return output.toOwnedSlice();
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

        // 准备源文件内容（如果需要）
        const sources_content = if (self.options.include_content) blk: {
            const content = try self.allocator.alloc(?[]const u8, 1);
            content[0] = try self.allocator.dupe(u8, self.magic_string.original);
            break :blk content;
        } else null;

        // 生成 mappings 字符串
        const mappings = try self.generateMappings();

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
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

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
        for (self.magic_string.segments.items, 0..) |*segment, i| {
            // 处理 intro（插入在左侧的内容）
            if (segment.intro) |intro| {
                // 检查 intro 中是否有换行符
                for (intro) |c| {
                    if (c == '\n') {
                        // 遇到换行符，添加行分隔符并重置
                        if (has_segment_in_line) {
                            try result.append(';');
                            has_segment_in_line = false;
                        } else {
                            // 如果当前行没有 segment，也需要添加空行标记
                            try result.append(';');
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
                // 这是来自原始源码的内容，需要创建映射
                // 一个 Segment 作为一个整体映射（不是每个字符）
                if (segment.content.len > 0) {
                    // 计算相对偏移
                    const gen_col_delta = @as(i32, @intCast(gen_column)) - prev_gen_column;
                    const source_index_delta = 0 - prev_source_index; // 始终是文件 0
                    const source_line_delta = 0 - prev_source_line; // 单行代码
                    const source_col_delta = @as(i32, @intCast(source_offset)) - prev_source_column;

                    // 编码 VLQ segment（4 字段）
                    const fields = [4]i32{ gen_col_delta, source_index_delta, source_line_delta, source_col_delta };
                    const encoded = try vlq.encodeVLQSegment(self.allocator, &fields);
                    defer self.allocator.free(encoded);

                    // 添加逗号分隔符（除了当前行的第一个 segment）
                    if (has_segment_in_line) {
                        try result.append(',');
                    }

                    try result.appendSlice(encoded);
                    has_segment_in_line = true;

                    // 更新上一个位置
                    prev_gen_column = @as(i32, @intCast(gen_column));
                    prev_source_index = 0;
                    prev_source_line = 0;
                    prev_source_column = @as(i32, @intCast(source_offset));

                    // 检查 segment content 中是否有换行符
                    for (segment.content) |c| {
                        if (c == '\n') {
                            // 遇到换行符，添加行分隔符并重置
                            if (has_segment_in_line) {
                                try result.append(';');
                                has_segment_in_line = false;
                            } else {
                                try result.append(';');
                            }
                            gen_line += 1;
                            gen_column = 0;
                            prev_gen_column = 0;
                        } else {
                            gen_column += 1;
                        }
                    }
                }
            } else {
                // 这是插入的内容（overwrite 替换的内容）
                // magic-string 会为被替换范围的开始位置生成一个映射
                // 检查前一个 segment 是否有 source_offset，如果有，说明这是替换的开始
                if (i > 0) {
                    const prev_seg = &self.magic_string.segments.items[i - 1];
                    if (prev_seg.source_offset) |prev_offset| {
                        // 为替换的开始位置生成映射，指向前一个 segment 结束后的原始位置
                        const replaced_source_pos = prev_offset + prev_seg.content.len;

                        // 计算相对偏移
                        const gen_col_delta = @as(i32, @intCast(gen_column)) - prev_gen_column;
                        const source_index_delta = 0 - prev_source_index;
                        const source_line_delta = 0 - prev_source_line;
                        const source_col_delta = @as(i32, @intCast(replaced_source_pos)) - prev_source_column;

                        // 编码 VLQ segment
                        const fields = [4]i32{ gen_col_delta, source_index_delta, source_line_delta, source_col_delta };
                        const encoded = try vlq.encodeVLQSegment(self.allocator, &fields);
                        defer self.allocator.free(encoded);

                        // 添加逗号分隔符
                        if (has_segment_in_line) {
                            try result.append(',');
                        }

                        try result.appendSlice(encoded);
                        has_segment_in_line = true;

                        // 更新上一个位置（但不更新 gen_column，因为这是插入的内容）
                        prev_gen_column = @as(i32, @intCast(gen_column));
                        prev_source_index = 0;
                        prev_source_line = 0;
                        prev_source_column = @as(i32, @intCast(replaced_source_pos));
                    }
                }

                // 检查插入内容中是否有换行符
                for (segment.content) |c| {
                    if (c == '\n') {
                        if (has_segment_in_line) {
                            try result.append(';');
                            has_segment_in_line = false;
                        } else {
                            try result.append(';');
                        }
                        gen_line += 1;
                        gen_column = 0;
                        prev_gen_column = 0;
                    } else {
                        gen_column += 1;
                    }
                }
            }

            // 处理 outro（插入在右侧的内容）
            if (segment.outro) |outro| {
                // 检查 outro 中是否有换行符
                for (outro) |c| {
                    if (c == '\n') {
                        if (has_segment_in_line) {
                            try result.append(';');
                            has_segment_in_line = false;
                        } else {
                            try result.append(';');
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

        return result.toOwnedSlice();
    }
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
