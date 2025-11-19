const std = @import("std");
const sourcemap = @import("sourcemap.zig");

/// Segment 表示字符串的一个片段
/// 采用连续内存的数组结构，Cache-friendly
pub const Segment = struct {
    /// 该 Segment 的实际内容
    content: []const u8,

    /// 如果该 Segment 来自原始字符串，记录其在原始字符串中的起始位置
    /// null 表示这是插入的新内容
    source_offset: ?usize,

    /// 该 Segment 在原始字符串中对应的范围 [start, end)
    /// 即使被 overwrite 后，这个范围信息仍然保留
    /// 这样可以支持在 overwrite 后的位置继续 appendLeft/Right
    original_start: usize,
    original_end: usize,

    /// 在此位置左侧插入的内容（用于 appendLeft）
    intro: ?[]const u8,
    /// 在此位置右侧插入的内容（用于 appendRight）
    outro: ?[]const u8,

    /// 创建一个来自原始字符串的 Segment
    pub fn fromSource(content: []const u8, offset: usize) Segment {
        return Segment{
            .content = content,
            .source_offset = offset,
            .original_start = offset,
            .original_end = offset + content.len,
            .intro = null,
            .outro = null,
        };
    }

    /// 创建一个插入内容的 Segment，但保留原始位置信息
    pub fn fromInsertWithRange(content: []const u8, original_start: usize, original_end: usize) Segment {
        return Segment{
            .content = content,
            .source_offset = null, // 插入的内容没有原始偏移
            .original_start = original_start,
            .original_end = original_end,
            .intro = null,
            .outro = null,
        };
    }

    /// 创建一个新插入的 Segment
    pub fn fromInsert(content: []const u8) Segment {
        return Segment{
            .content = content,
            .source_offset = null,
            .original_start = 0,
            .original_end = 0,
            .intro = null,
            .outro = null,
        };
    }

    /// 计算此 Segment 输出时的总长度
    pub fn length(self: *const Segment) usize {
        var len: usize = 0;
        if (self.intro) |i| len += i.len;
        len += self.content.len;
        if (self.outro) |o| len += o.len;
        return len;
    }

    /// 将 Segment 的内容写入缓冲区
    pub fn toString(self: *const Segment, writer: anytype) !void {
        if (self.intro) |i| {
            try writer.writeAll(i);
        }
        try writer.writeAll(self.content);
        if (self.outro) |o| {
            try writer.writeAll(o);
        }
    }

    /// 释放 Segment 拥有的资源
    pub fn deinit(self: *Segment, allocator: std.mem.Allocator) void {
        // content 可能是原始字符串的切片或独立分配的，需要根据 source_offset 判断
        // 但实际上我们统一在 MagicString 层面管理内存
        if (self.intro) |i| allocator.free(i);
        if (self.outro) |o| allocator.free(o);
    }
};

/// MagicString 主结构体
/// 采用 ArrayList 存储 Segments，提供 Cache-friendly 的内存布局
pub const MagicString = struct {
    allocator: std.mem.Allocator,

    /// 原始源字符串（保持不变）
    original: []const u8,

    /// Segments 数组（连续内存）
    segments: std.ArrayList(Segment),

    /// 缓存的偏移量数组（用于二分查找）
    /// 惰性计算，只在需要时生成
    cached_offsets: ?[]usize,

    /// 初始化 MagicString
    pub fn init(allocator: std.mem.Allocator, source: []const u8) !*MagicString {
        const self = try allocator.create(MagicString);
        errdefer allocator.destroy(self);

        // 复制源字符串
        const original = try allocator.dupe(u8, source);
        errdefer allocator.free(original);

        // 创建 Segments 数组
        var segments = std.ArrayList(Segment).init(allocator);
        errdefer segments.deinit();

        // 初始时整个字符串作为一个 Segment
        if (source.len > 0) {
            try segments.append(Segment.fromSource(original, 0));
        }

        self.* = MagicString{
            .allocator = allocator,
            .original = original,
            .segments = segments,
            .cached_offsets = null,
        };

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *MagicString) void {
        // 释放所有 Segment 的附加内容
        for (self.segments.items) |*segment| {
            segment.deinit(self.allocator);
        }

        // 释放缓存的 offsets
        if (self.cached_offsets) |offsets| {
            self.allocator.free(offsets);
        }

        self.segments.deinit();
        self.allocator.free(self.original);
        self.allocator.destroy(self);
    }

    /// 计算并缓存所有 Segment 的起始偏移量
    /// 返回的数组长度等于 segments.items.len
    fn getOffsets(self: *MagicString) ![]usize {
        // 如果缓存有效，直接返回
        if (self.cached_offsets) |offsets| {
            return offsets;
        }

        // 计算偏移量
        const offsets = try self.allocator.alloc(usize, self.segments.items.len);
        var offset: usize = 0;
        for (self.segments.items, 0..) |*segment, i| {
            offsets[i] = offset;
            offset += segment.length();
        }

        self.cached_offsets = offsets;
        return offsets;
    }

    /// 使缓存失效（在修改 segments 后调用）
    fn invalidateCache(self: *MagicString) void {
        if (self.cached_offsets) |offsets| {
            self.allocator.free(offsets);
            self.cached_offsets = null;
        }
    }

    /// 二分查找：找到包含指定偏移量的 Segment 索引
    fn findSegmentIndex(self: *MagicString, target_offset: usize) !usize {
        const offsets = try self.getOffsets();

        if (self.segments.items.len == 0) return error.EmptyString;

        // 计算总长度（包含所有 Segment 的实际输出长度）
        var total_len: usize = 0;
        for (self.segments.items) |*seg| {
            total_len += seg.length();
        }

        // 允许 target_offset == total_len（在末尾追加）
        if (target_offset > total_len) {
            return error.OffsetOutOfBounds;
        }

        // 特殊情况：在末尾追加，返回最后一个 Segment
        if (target_offset == total_len) {
            return self.segments.items.len - 1;
        }

        var left: usize = 0;
        var right: usize = offsets.len - 1;

        while (left < right) {
            const mid = left + (right - left + 1) / 2;
            if (offsets[mid] <= target_offset) {
                left = mid;
            } else {
                right = mid - 1;
            }
        }

        return left;
    }

    /// 返回当前字符串内容
    pub fn toString(self: *MagicString) ![]const u8 {
        // 先计算总长度
        var total_len: usize = 0;
        for (self.segments.items) |*segment| {
            total_len += segment.length();
        }

        // 分配缓冲区
        const buffer = try self.allocator.alloc(u8, total_len);
        errdefer self.allocator.free(buffer);

        // 写入内容
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        for (self.segments.items) |*segment| {
            try segment.toString(writer);
        }

        return buffer;
    }

    /// appendLeft: 在指定索引的左侧插入内容
    /// index 是相对于**原始字符串**的位置
    /// 如果该位置随后被移动（范围结束于此），插入的内容会跟随移动
    pub fn appendLeft(self: *MagicString, index: usize, content: []const u8) !void {
        if (content.len == 0) return;

        // 先尝试找到包含该原始索引的 Segment（基于 source_offset）
        var seg_idx_opt = self.findSegmentBySourceOffset(index);

        // 如果找不到（可能因为该位置被 overwrite 了），尝试基于原始位置范围查找
        if (seg_idx_opt == null) {
            seg_idx_opt = self.findSegmentByOriginalPosition(index);
        }

        if (seg_idx_opt == null) {
            // 如果还是找不到，说明 index 超出了原始字符串范围，在末尾追加
            if (self.segments.items.len > 0) {
                const last_idx = self.segments.items.len - 1;
                var segment = &self.segments.items[last_idx];
                const new_content = try self.allocator.dupe(u8, content);
                if (segment.outro) |existing_outro| {
                    const combined = try self.allocator.alloc(u8, new_content.len + existing_outro.len);
                    @memcpy(combined[0..new_content.len], new_content);
                    @memcpy(combined[new_content.len..], existing_outro);
                    self.allocator.free(existing_outro);
                    self.allocator.free(new_content);
                    segment.outro = combined;
                } else {
                    segment.outro = new_content;
                }
                self.invalidateCache();
                return;
            }
            return error.OffsetNotFound;
        }

        const seg_idx = seg_idx_opt.?;
        const segment = &self.segments.items[seg_idx];

        // 计算在该 Segment 内的相对位置（基于原始位置）
        const relative_pos = index - segment.original_start;

        // 需要分配新的内容
        const new_content = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(new_content);

        // 如果 index 正好在 Segment 开头，添加到 intro
        if (relative_pos == 0) {
            var seg = &self.segments.items[seg_idx];
            if (seg.intro) |existing_intro| {
                // 新内容在前，现有内容在后
                const combined = try self.allocator.alloc(u8, new_content.len + existing_intro.len);
                @memcpy(combined[0..new_content.len], new_content);
                @memcpy(combined[new_content.len..], existing_intro);
                self.allocator.free(existing_intro);
                self.allocator.free(new_content);
                seg.intro = combined;
            } else {
                seg.intro = new_content;
            }
        } else {
            // 需要分裂 Segment，在分裂点左侧插入
            try self.splitSegment(seg_idx, relative_pos);
            // 分裂后，新的 Segment 在 seg_idx + 1 位置
            // 将内容添加到右侧 Segment 的 intro
            var seg = &self.segments.items[seg_idx + 1];
            if (seg.intro) |existing_intro| {
                const combined = try self.allocator.alloc(u8, new_content.len + existing_intro.len);
                @memcpy(combined[0..new_content.len], new_content);
                @memcpy(combined[new_content.len..], existing_intro);
                self.allocator.free(existing_intro);
                self.allocator.free(new_content);
                seg.intro = combined;
            } else {
                seg.intro = new_content;
            }
        }

        self.invalidateCache();
    }

    /// appendRight: 在指定索引的右侧插入内容
    /// index 是相对于**原始字符串**的位置
    /// 如果该位置随后被移动（范围开始于此），插入的内容会跟随移动
    pub fn appendRight(self: *MagicString, index: usize, content: []const u8) !void {
        if (content.len == 0) return;

        // 检查是否在原始字符串末尾
        if (index >= self.original.len) {
            // 在最后一个 segment 的末尾追加
            if (self.segments.items.len > 0) {
                const last_idx = self.segments.items.len - 1;
                var segment = &self.segments.items[last_idx];
                const new_content = try self.allocator.dupe(u8, content);
                if (segment.outro) |existing_outro| {
                    const combined = try self.allocator.alloc(u8, new_content.len + existing_outro.len);
                    @memcpy(combined[0..new_content.len], new_content);
                    @memcpy(combined[new_content.len..], existing_outro);
                    self.allocator.free(existing_outro);
                    self.allocator.free(new_content);
                    segment.outro = combined;
                } else {
                    segment.outro = new_content;
                }
                self.invalidateCache();
                return;
            }
            return error.OffsetNotFound;
        }

        // 先尝试找到包含该原始索引的 Segment（基于 source_offset）
        var seg_idx_opt = self.findSegmentBySourceOffset(index);

        // 如果找不到（可能因为该位置被 overwrite 了），尝试基于原始位置范围查找
        if (seg_idx_opt == null) {
            seg_idx_opt = self.findSegmentByOriginalPosition(index);
        }

        if (seg_idx_opt == null) {
            return error.OffsetNotFound;
        }

        const seg_idx = seg_idx_opt.?;
        const segment = &self.segments.items[seg_idx];

        // 计算在该 Segment 内的相对位置（基于原始位置）
        const relative_pos = index - segment.original_start;

        const new_content = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(new_content);

        // 计算原始范围的长度
        const original_range_len = segment.original_end - segment.original_start;

        // 如果 index 正好在 Segment 原始范围的末尾，尝试添加到下一个 segment 的 intro
        if (relative_pos == original_range_len) {
            // 查找下一个 segment（如果存在）
            if (seg_idx + 1 < self.segments.items.len) {
                var next_seg = &self.segments.items[seg_idx + 1];
                if (next_seg.intro) |existing_intro| {
                    const combined = try self.allocator.alloc(u8, new_content.len + existing_intro.len);
                    @memcpy(combined[0..new_content.len], new_content);
                    @memcpy(combined[new_content.len..], existing_intro);
                    self.allocator.free(existing_intro);
                    self.allocator.free(new_content);
                    next_seg.intro = combined;
                } else {
                    next_seg.intro = new_content;
                }
                self.invalidateCache();
                return;
            }
            // 如果没有下一个 segment，添加到当前 segment 的 outro
        }

        // 如果 index 正好在 Segment 原始范围的开头，添加到 intro（注意：appendRight 应该在 intro 的末尾）
        if (relative_pos == 0) {
            var seg = &self.segments.items[seg_idx];
            if (seg.intro) |existing_intro| {
                // 现有 intro 在前，新内容在后
                const combined = try self.allocator.alloc(u8, existing_intro.len + new_content.len);
                @memcpy(combined[0..existing_intro.len], existing_intro);
                @memcpy(combined[existing_intro.len..], new_content);
                self.allocator.free(existing_intro);
                self.allocator.free(new_content);
                seg.intro = combined;
            } else {
                seg.intro = new_content;
            }
        } else {
            // 需要分裂 Segment，在分裂点右侧插入
            try self.splitSegment(seg_idx, relative_pos);
            // 将内容添加到左侧 Segment 的 outro
            var seg = &self.segments.items[seg_idx];
            if (seg.outro) |existing_outro| {
                const combined = try self.allocator.alloc(u8, new_content.len + existing_outro.len);
                @memcpy(combined[0..new_content.len], new_content);
                @memcpy(combined[new_content.len..], existing_outro);
                self.allocator.free(existing_outro);
                self.allocator.free(new_content);
                seg.outro = combined;
            } else {
                seg.outro = new_content;
            }
        }

        self.invalidateCache();
    }

    /// 分裂 Segment：在指定位置将一个 Segment 分为两个
    /// split_pos 是相对于该 Segment 内容开头的偏移
    fn splitSegment(self: *MagicString, seg_idx: usize, split_pos: usize) !void {
        const segment = &self.segments.items[seg_idx];

        if (split_pos == 0 or split_pos >= segment.content.len) {
            return; // 无需分裂
        }

        // 创建两个新的 Segment
        const left_content = segment.content[0..split_pos];
        const right_content = segment.content[split_pos..];

        // 计算分裂点的原始位置
        const split_original_pos = segment.original_start + split_pos;

        const left_seg = Segment{
            .content = left_content,
            .source_offset = segment.source_offset,
            .original_start = segment.original_start,
            .original_end = split_original_pos,
            .intro = segment.intro,
            .outro = null,
        };

        const right_seg = Segment{
            .content = right_content,
            .source_offset = if (segment.source_offset) |offset| offset + split_pos else null,
            .original_start = split_original_pos,
            .original_end = segment.original_end,
            .intro = null,
            .outro = segment.outro,
        };

        // 替换原 Segment
        self.segments.items[seg_idx] = left_seg;
        try self.segments.insert(seg_idx + 1, right_seg);

        // 注意：原 segment 的 intro/outro 已转移，无需释放
        // 只需要将原 segment 的指针置空（但实际上已被覆盖）
    }

    /// overwrite: 用新内容替换指定范围的字符
    /// start 和 end 是相对于 **原始字符串** 的索引
    pub fn overwrite(self: *MagicString, start: usize, end: usize, content: []const u8) !void {
        if (start >= end) return error.InvalidRange;

        // 找到包含 start 和 end 位置的 Segment（基于 source_offset）
        const start_seg_idx = self.findSegmentBySourceOffset(start);
        const end_seg_idx = self.findSegmentBySourceOffset(if (end > 0) end - 1 else 0);

        if (start_seg_idx == null or end_seg_idx == null) {
            return error.OffsetNotFound;
        }

        const start_idx = start_seg_idx.?;
        var end_idx = end_seg_idx.?;

        // 记录 start 位置的相对偏移（在分裂前）
        var should_split_start = false;
        var start_relative: usize = 0;
        if (self.segments.items[start_idx].source_offset) |seg_offset| {
            start_relative = start - seg_offset;
            should_split_start = start_relative > 0;
        }

        // 分裂起始 Segment（如果需要）
        if (should_split_start) {
            try self.splitSegment(start_idx, start_relative);
            end_idx += 1; // 调整 end_idx
        }

        // 计算实际起始索引
        const actual_start = if (should_split_start) start_idx + 1 else start_idx;

        // 分裂结束 Segment（如果需要）
        if (self.segments.items[end_idx].source_offset) |seg_offset| {
            const relative = end - seg_offset;
            if (relative > 0 and relative < self.segments.items[end_idx].content.len) {
                try self.splitSegment(end_idx, relative);
            }
        }

        // 保存边界的 intro/outro
        const saved_intro = self.segments.items[actual_start].intro;
        const saved_outro = self.segments.items[end_idx].outro;

        // 执行替换
        try self.doReplaceRange(actual_start, end_idx, content, saved_intro, saved_outro);
    }

    /// 根据原始字符串的偏移量找到对应的 Segment 索引
    fn findSegmentBySourceOffset(self: *const MagicString, offset: usize) ?usize {
        for (self.segments.items, 0..) |*seg, i| {
            if (seg.source_offset) |seg_offset| {
                if (offset >= seg_offset and offset < seg_offset + seg.content.len) {
                    return i;
                }
            }
        }
        return null;
    }

    /// 根据原始字符串中的位置查找对应的 Segment 索引（基于 original_start/end 范围）
    /// 这个函数可以找到被 overwrite 后的 Segment
    fn findSegmentByOriginalPosition(self: *const MagicString, position: usize) ?usize {
        for (self.segments.items, 0..) |*seg, i| {
            // 检查 position 是否在该 segment 的原始范围内
            if (position >= seg.original_start and position < seg.original_end) {
                return i;
            }
        }
        return null;
    }

    /// 执行实际的范围替换
    fn doReplaceRange(self: *MagicString, start_idx: usize, end_idx: usize, content: []const u8, intro: ?[]const u8, outro: ?[]const u8) !void {
        // 创建新 Segment
        const new_content = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(new_content);

        // 获取被替换范围的原始位置信息
        const original_start = self.segments.items[start_idx].original_start;
        const original_end = self.segments.items[end_idx].original_end;

        var new_seg = Segment.fromInsertWithRange(new_content, original_start, original_end);
        new_seg.intro = intro;
        new_seg.outro = outro;

        // 释放被替换Segments的资源
        for (start_idx..end_idx + 1) |i| {
            const seg = &self.segments.items[i];
            // 如果是插入的内容（source_offset == null），需要释放 content
            if (seg.source_offset == null) {
                self.allocator.free(seg.content);
            }
            // intro 和 outro 在边界处已经保存到 new_seg，中间的需要释放
            if (i != start_idx and seg.intro != null) {
                self.allocator.free(seg.intro.?);
            }
            if (i != end_idx and seg.outro != null) {
                self.allocator.free(seg.outro.?);
            }
        }

        // 替换
        const count = end_idx - start_idx + 1;
        try self.segments.replaceRange(start_idx, count, &[_]Segment{new_seg});

        self.invalidateCache();
    }

    /// 生成 Source Map
    ///
    /// 根据当前的编辑操作生成符合 Source Map v3 规范的映射数据
    ///
    /// 参数：
    ///   - options: Source Map 生成选项
    ///
    /// 返回：
    ///   - Source Map 对象（调用者负责释放）
    ///
    /// 使用示例：
    /// ```zig
    /// const ms = try MagicString.init(allocator, "var x = 1");
    /// try ms.overwrite(4, 5, "answer");
    /// const map = try ms.generateMap(.{
    ///     .file = "output.js",
    ///     .source = "input.js",
    /// });
    /// defer {
    ///     map.deinit();
    ///     allocator.destroy(map);
    /// }
    /// ```
    pub fn generateMap(self: *const MagicString, options: sourcemap.SourceMapOptions) !*sourcemap.SourceMap {
        var generator = sourcemap.SourceMapGenerator.init(self.allocator, self, options);
        return try generator.generate();
    }
};
