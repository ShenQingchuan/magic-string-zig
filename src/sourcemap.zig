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

pub const DecodedSegment = struct {
    generated_column: usize,
    source_index: ?usize = null,
    source_line: usize = 0,
    source_column: usize = 0,
    name_index: ?usize = null,
};

pub const DecodedLine = struct {
    segments: []DecodedSegment,
};

pub const DecodedSourceMap = struct {
    allocator: std.mem.Allocator,
    file: ?[]const u8 = null,
    source_root: ?[]const u8 = null,
    sources: []const []const u8,
    sources_content: ?[]const ?[]const u8 = null,
    names: []const []const u8,
    mappings: []DecodedLine,

    pub fn deinit(self: *DecodedSourceMap) void {
        for (self.sources) |source| {
            self.allocator.free(source);
        }
        self.allocator.free(self.sources);

        if (self.sources_content) |content| {
            for (content) |entry| {
                if (entry) |s| self.allocator.free(s);
            }
            self.allocator.free(content);
        }

        for (self.names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.names);

        for (self.mappings) |line| {
            self.allocator.free(line.segments);
        }
        self.allocator.free(self.mappings);

        if (self.file) |file| self.allocator.free(file);
        if (self.source_root) |root| self.allocator.free(root);
    }
};

fn encodeDecodedMappings(allocator: std.mem.Allocator, lines: []const DecodedLine) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var prev_gen_column: i32 = 0;
    var prev_source_index: i32 = 0;
    var prev_source_line: i32 = 0;
    var prev_source_column: i32 = 0;
    var prev_name_index: i32 = 0;

    for (lines, 0..) |line, line_idx| {
        if (line_idx > 0) {
            try result.append(allocator, ';');
            prev_gen_column = 0;
        }

        for (line.segments, 0..) |segment, seg_idx| {
            if (seg_idx > 0) {
                try result.append(allocator, ',');
            }

            const gen_col_delta = @as(i32, @intCast(segment.generated_column)) - prev_gen_column;
            prev_gen_column = @as(i32, @intCast(segment.generated_column));

            var fields = std.ArrayList(i32).empty;
            defer fields.deinit(allocator);

            try fields.append(allocator, gen_col_delta);

            if (segment.source_index) |source_idx| {
                const source_delta = @as(i32, @intCast(source_idx)) - prev_source_index;
                prev_source_index = @as(i32, @intCast(source_idx));
                try fields.append(allocator, source_delta);

                const line_delta = @as(i32, @intCast(segment.source_line)) - prev_source_line;
                prev_source_line = @as(i32, @intCast(segment.source_line));
                try fields.append(allocator, line_delta);

                const column_delta = @as(i32, @intCast(segment.source_column)) - prev_source_column;
                prev_source_column = @as(i32, @intCast(segment.source_column));
                try fields.append(allocator, column_delta);

                if (segment.name_index) |name_idx| {
                    const name_delta = @as(i32, @intCast(name_idx)) - prev_name_index;
                    prev_name_index = @as(i32, @intCast(name_idx));
                    try fields.append(allocator, name_delta);
                } else {
                    prev_name_index = 0;
                }
            } else {
                prev_source_index = 0;
                prev_source_line = 0;
                prev_source_column = 0;
                prev_name_index = 0;
            }

            const encoded = try vlq.encodeVLQSegment(allocator, fields.items);
            defer allocator.free(encoded);
            try result.appendSlice(allocator, encoded);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn duplicateStringArray(allocator: std.mem.Allocator, items: []const []const u8) ![]const []const u8 {
    const out = try allocator.alloc([]const u8, items.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            allocator.free(out[i]);
        }
        allocator.free(out);
    }
    while (i < items.len) : (i += 1) {
        out[i] = try allocator.dupe(u8, items[i]);
    }
    return out;
}

fn duplicateOptionalStringArray(allocator: std.mem.Allocator, items: []const ?[]const u8) ![]const ?[]const u8 {
    const out = try allocator.alloc(?[]const u8, items.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            if (out[i]) |value| allocator.free(value);
        }
        allocator.free(out);
    }
    while (i < items.len) : (i += 1) {
        if (items[i]) |value| {
            out[i] = try allocator.dupe(u8, value);
        } else {
            out[i] = null;
        }
    }
    return out;
}

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
        const decoded = try self.generateDecoded();
        defer {
            decoded.deinit();
            self.allocator.destroy(decoded);
        }
        return try createSourceMapFromDecoded(self.allocator, decoded);
    }

    pub fn generateDecoded(self: *SourceMapGenerator) !*DecodedSourceMap {
        return try self.buildDecodedMap();
    }

    fn buildDecodedMap(self: *SourceMapGenerator) !*DecodedSourceMap {
        const source_name = self.options.source orelse "";
        var sources_list = std.ArrayList([]const u8).empty;
        errdefer sources_list.deinit(self.allocator);
        const dup_source = try self.allocator.dupe(u8, source_name);
        try sources_list.append(self.allocator, dup_source);

        const sources = try sources_list.toOwnedSlice(self.allocator);

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

        const mappings = try self.generateDecodedMappings();
        errdefer {
            for (mappings) |line| self.allocator.free(line.segments);
            self.allocator.free(mappings);
        }

        const map = try self.allocator.create(DecodedSourceMap);
        map.* = DecodedSourceMap{
            .allocator = self.allocator,
            .file = if (self.options.file) |f| try self.allocator.dupe(u8, f) else null,
            .source_root = if (self.options.source_root) |r| try self.allocator.dupe(u8, r) else null,
            .sources = sources,
            .sources_content = sources_content,
            .names = try self.allocator.alloc([]const u8, 0),
            .mappings = mappings,
        };

        return map;
    }

    fn generateDecodedMappings(self: *SourceMapGenerator) ![]DecodedLine {
        const line_starts = try self.computeLineStartOffsets();
        defer self.allocator.free(line_starts);

        const LineBuilder = struct {
            segments: std.ArrayList(DecodedSegment),
        };

        var lines = std.ArrayList(LineBuilder).empty;
        errdefer {
            for (lines.items) |*builder| builder.segments.deinit(self.allocator);
            lines.deinit(self.allocator);
        }

        try lines.append(self.allocator, .{ .segments = std.ArrayList(DecodedSegment).empty });
        var current_segments = &lines.items[0].segments;

        var gen_line: usize = 0;
        var gen_column: usize = 0;

        const startNewLine = struct {
            fn run(
                parent: *SourceMapGenerator,
                lines_ref: *std.ArrayList(LineBuilder),
                gen_line_ref: *usize,
                current_segments_ref: **std.ArrayList(DecodedSegment),
            ) !void {
                gen_line_ref.* += 1;
                try lines_ref.append(parent.allocator, .{ .segments = std.ArrayList(DecodedSegment).empty });
                current_segments_ref.* = &lines_ref.items[lines_ref.items.len - 1].segments;
            }
        }.run;

        const recordSegment = struct {
            fn run(
                builder: *std.ArrayList(DecodedSegment),
                allocator: std.mem.Allocator,
                gen_column_value: usize,
                source_line: usize,
                source_column: usize,
            ) !void {
                try builder.append(allocator, .{
                    .generated_column = gen_column_value,
                    .source_index = 0,
                    .source_line = source_line,
                    .source_column = source_column,
                    .name_index = null,
                });
            }
        }.run;

        for (self.magic_string.segments.items) |*segment| {
            if (segment.intro) |intro| {
                for (intro) |c| {
                    if (c == '\n') {
                        try startNewLine(self, &lines, &gen_line, &current_segments);
                        gen_column = 0;
                    } else {
                        gen_column += 1;
                    }
                }
            }

            if (segment.source_offset) |source_offset| {
                if (segment.content.len > 0) {
                    const start_lc = lineColumnFromOffset(line_starts, source_offset);
                    var source_line = start_lc.line;
                    var source_column = start_lc.column;
                    var first_in_line = true;

                    for (segment.content) |c| {
                        if (c == '\n') {
                            try startNewLine(self, &lines, &gen_line, &current_segments);
                            gen_column = 0;
                            source_line += 1;
                            source_column = 0;
                            first_in_line = true;
                        } else {
                            if (first_in_line) {
                                try recordSegment(current_segments, self.allocator, gen_column, source_line, source_column);
                                first_in_line = false;
                            }
                            gen_column += 1;
                            source_column += 1;
                        }
                    }
                }
            } else {
                if (segment.original_end > segment.original_start and segment.content.len > 0) {
                    const lc = lineColumnFromOffset(line_starts, segment.original_start);
                    var first_in_line = true;

                    for (segment.content) |c| {
                        if (c == '\n') {
                            try startNewLine(self, &lines, &gen_line, &current_segments);
                            gen_column = 0;
                            first_in_line = true;
                        } else {
                            if (first_in_line) {
                                try recordSegment(current_segments, self.allocator, gen_column, lc.line, lc.column);
                                first_in_line = false;
                            }
                            gen_column += 1;
                        }
                    }
                } else {
                for (segment.content) |c| {
                    if (c == '\n') {
                            try startNewLine(self, &lines, &gen_line, &current_segments);
                            gen_column = 0;
                        } else {
                            gen_column += 1;
                        }
                    }
                }
            }

            if (segment.outro) |outro| {
                for (outro) |c| {
                    if (c == '\n') {
                        try startNewLine(self, &lines, &gen_line, &current_segments);
                        gen_column = 0;
                    } else {
                        gen_column += 1;
                    }
                }
            }
        }

        const decoded_lines = try self.allocator.alloc(DecodedLine, lines.items.len);
        errdefer {
            for (decoded_lines[0..]) |line| self.allocator.free(line.segments);
            self.allocator.free(decoded_lines);
        }

        for (lines.items, 0..) |*builder, idx| {
            decoded_lines[idx] = DecodedLine{
                .segments = try builder.segments.toOwnedSlice(self.allocator),
            };
        }
        lines.deinit(self.allocator);

        return decoded_lines;
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

fn createSourceMapFromDecoded(allocator: std.mem.Allocator, decoded: *DecodedSourceMap) !*SourceMap {
    const sources = try duplicateStringArray(allocator, decoded.sources);
    errdefer {
        for (sources) |s| allocator.free(s);
        allocator.free(sources);
    }

    const sources_content = if (decoded.sources_content) |content| blk: {
        const dup = try duplicateOptionalStringArray(allocator, content);
        break :blk dup;
    } else null;
    errdefer if (sources_content) |content| {
        for (content) |entry| {
            if (entry) |value| allocator.free(value);
        }
        allocator.free(content);
    };

    const names = try duplicateStringArray(allocator, decoded.names);
    errdefer {
        for (names) |n| allocator.free(n);
        allocator.free(names);
    }

    const mappings = try encodeDecodedMappings(allocator, decoded.mappings);
    errdefer allocator.free(mappings);

    const map = try allocator.create(SourceMap);
    map.* = SourceMap{
        .allocator = allocator,
        .version = 3,
        .file = if (decoded.file) |f| try allocator.dupe(u8, f) else null,
        .source_root = if (decoded.source_root) |r| try allocator.dupe(u8, r) else null,
        .sources = sources,
        .sources_content = sources_content,
        .names = names,
        .mappings = mappings,
    };
    return map;
}

pub fn decodedToSourceMap(allocator: std.mem.Allocator, decoded: *DecodedSourceMap) !*SourceMap {
    return try createSourceMapFromDecoded(allocator, decoded);
}

pub fn cloneDecodedMap(allocator: std.mem.Allocator, map: *DecodedSourceMap) !*DecodedSourceMap {
    const sources = try duplicateStringArray(allocator, map.sources);
    errdefer {
        for (sources) |s| allocator.free(s);
        allocator.free(sources);
    }

    const sources_content = if (map.sources_content) |content| blk: {
        const dup = try duplicateOptionalStringArray(allocator, content);
        break :blk dup;
    } else null;
    errdefer if (sources_content) |content| {
        for (content) |entry| {
            if (entry) |value| allocator.free(value);
        }
        allocator.free(content);
    };

    const names = try duplicateStringArray(allocator, map.names);
    errdefer {
        for (names) |n| allocator.free(n);
        allocator.free(names);
    }

    const mappings = try cloneDecodedLines(allocator, map.mappings);
    errdefer {
        for (mappings) |line| allocator.free(line.segments);
        allocator.free(mappings);
    }

    const clone = try allocator.create(DecodedSourceMap);
    clone.* = DecodedSourceMap{
        .allocator = allocator,
        .file = if (map.file) |f| try allocator.dupe(u8, f) else null,
        .source_root = if (map.source_root) |r| try allocator.dupe(u8, r) else null,
        .sources = sources,
        .sources_content = sources_content,
        .names = names,
        .mappings = mappings,
    };
    return clone;
}

fn cloneDecodedLines(allocator: std.mem.Allocator, lines: []const DecodedLine) ![]DecodedLine {
    const out = try allocator.alloc(DecodedLine, lines.len);
    errdefer {
        for (out[0..]) |line| allocator.free(line.segments);
        allocator.free(out);
    }

    for (lines, 0..) |line, idx| {
        const segs = try allocator.alloc(DecodedSegment, line.segments.len);
        @memcpy(segs, line.segments);
        out[idx] = DecodedLine{ .segments = segs };
    }

    return out;
}

const SourceAccumulator = struct {
    allocator: std.mem.Allocator,
    store_content: bool,
    table: std.StringHashMap(usize),
    names: std.ArrayList([]const u8),
    contents: std.ArrayList(?[]const u8),

    fn init(allocator: std.mem.Allocator, store_content: bool) SourceAccumulator {
        return .{
            .allocator = allocator,
            .store_content = store_content,
            .table = std.StringHashMap(usize).init(allocator),
            .names = std.ArrayList([]const u8).empty,
            .contents = std.ArrayList(?[]const u8).empty,
        };
    }

    fn put(self: *SourceAccumulator, name: []const u8, content: ?[]const u8) !usize {
        if (self.table.get(name)) |idx| return idx;
        const dup_name = try self.allocator.dupe(u8, name);
        const index = self.names.items.len;
        try self.names.append(self.allocator, dup_name);

        if (self.store_content) {
            if (content) |value| {
                try self.contents.append(self.allocator, try self.allocator.dupe(u8, value));
            } else {
                try self.contents.append(self.allocator, null);
            }
        }

        try self.table.put(dup_name, index);
        return index;
    }

    fn finish(self: *SourceAccumulator) !struct {
        sources: []const []const u8,
        contents: ?[]const ?[]const u8,
    } {
        const sources = try self.names.toOwnedSlice(self.allocator);
        const contents = if (self.store_content) blk: {
            const dup = try self.contents.toOwnedSlice(self.allocator);
            break :blk dup;
        } else null;
        return .{ .sources = sources, .contents = contents };
    }

    fn deinit(self: *SourceAccumulator) void {
        self.table.deinit();
        self.names.deinit(self.allocator);
        self.contents.deinit(self.allocator);
    }
};

const StringInterner = struct {
    allocator: std.mem.Allocator,
    table: std.StringHashMap(usize),
    values: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) StringInterner {
        return .{
            .allocator = allocator,
            .table = std.StringHashMap(usize).init(allocator),
            .values = std.ArrayList([]const u8).empty,
        };
    }

    fn put(self: *StringInterner, value: []const u8) !usize {
        if (self.table.get(value)) |idx| {
            return idx;
        }
        const dup = try self.allocator.dupe(u8, value);
        const index = self.values.items.len;
        try self.values.append(self.allocator, dup);
        try self.table.put(dup, index);
        return index;
    }

    fn finish(self: *StringInterner) ![]const []const u8 {
        return self.values.toOwnedSlice(self.allocator);
    }

    fn deinit(self: *StringInterner) void {
        self.table.deinit();
        self.values.deinit(self.allocator);
    }
};

const TraceResult = struct {
    source_name: []const u8,
    source_content: ?[]const u8,
    line: usize,
    column: usize,
    name: ?[]const u8,
};

fn findSegment(segments: []const DecodedSegment, column: usize) ?*const DecodedSegment {
    var low: usize = 0;
    var high: usize = segments.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const mid_column = segments[mid].generated_column;
        if (mid_column == column) {
            return &segments[mid];
        } else if (mid_column < column) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    return null;
}

fn traceThroughChain(
    maps: []const *DecodedSourceMap,
    depth: usize,
    line: usize,
    column: usize,
    current_name: ?[]const u8,
) ?TraceResult {
    const map = maps[depth];
    if (line >= map.mappings.len) return null;
    const segment_ptr = findSegment(map.mappings[line].segments, column) orelse return null;
    const segment = segment_ptr.*;

    const next_name = if (segment.name_index) |idx| map.names[idx] else current_name;
    if (segment.source_index == null) return null;

    if (depth + 1 >= maps.len) {
        const source_idx = segment.source_index.?;
        const source_name = map.sources[source_idx];
        const source_content = if (map.sources_content) |content| content[source_idx] else null;
        return TraceResult{
            .source_name = source_name,
            .source_content = source_content,
            .line = segment.source_line,
            .column = segment.source_column,
            .name = next_name,
        };
    }

    if (segment.source_index.? != 0) return null;

    return traceThroughChain(
        maps,
        depth + 1,
        segment.source_line,
        segment.source_column,
        next_name,
    );
}

pub fn mergeDecodedMaps(
    allocator: std.mem.Allocator,
    maps: []const *DecodedSourceMap,
    include_content: bool,
) !*DecodedSourceMap {
    if (maps.len == 0) return error.NoSourceMaps;
    if (maps.len == 1) {
        return try cloneDecodedMap(allocator, maps[0]);
    }

    for (maps[0 .. maps.len - 1]) |map| {
        if (map.sources.len != 1) {
            return error.InvalidTransformMap;
        }
    }

    var sources_acc = SourceAccumulator.init(allocator, include_content);
    defer sources_acc.deinit();
    var names_acc = StringInterner.init(allocator);
    defer names_acc.deinit();

    const root = maps[0];
    const final_lines = try allocator.alloc(DecodedLine, root.mappings.len);
    errdefer {
        for (final_lines[0..]) |line| allocator.free(line.segments);
        allocator.free(final_lines);
    }

    for (root.mappings, 0..) |line, line_idx| {
        var builder = std.ArrayList(DecodedSegment).empty;
        errdefer builder.deinit(allocator);

        for (line.segments) |segment| {
            if (segment.source_index == null) continue;
            const initial_name = if (segment.name_index) |idx| root.names[idx] else null;
            const traced = traceThroughChain(maps, 0, line_idx, segment.generated_column, initial_name) orelse continue;

            const source_idx = try sources_acc.put(traced.source_name, traced.source_content);
            const name_idx = if (traced.name) |name_value| try names_acc.put(name_value) else null;

            try builder.append(allocator, .{
                .generated_column = segment.generated_column,
                .source_index = source_idx,
                .source_line = traced.line,
                .source_column = traced.column,
                .name_index = name_idx,
            });
        }

        final_lines[line_idx] = DecodedLine{
            .segments = try builder.toOwnedSlice(allocator),
        };
        builder.deinit(allocator);
    }

    const sources_result = try sources_acc.finish();
    const names_result = try names_acc.finish();

    var merged_lines = final_lines;
    var used_len = merged_lines.len;
    while (used_len > 0 and merged_lines[used_len - 1].segments.len == 0) {
        used_len -= 1;
        allocator.free(merged_lines[used_len].segments);
    }
    if (used_len != merged_lines.len) {
        const trimmed_lines = try allocator.alloc(DecodedLine, used_len);
        @memcpy(trimmed_lines, merged_lines[0..used_len]);
        allocator.free(merged_lines);
        merged_lines = trimmed_lines;
    }

    const merged = try allocator.create(DecodedSourceMap);
    merged.* = DecodedSourceMap{
        .allocator = allocator,
        .file = if (root.file) |f| try allocator.dupe(u8, f) else null,
        .source_root = if (root.source_root) |r| try allocator.dupe(u8, r) else null,
        .sources = sources_result.sources,
        .sources_content = sources_result.contents,
        .names = names_result,
        .mappings = merged_lines,
    };

    return merged;
}

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
