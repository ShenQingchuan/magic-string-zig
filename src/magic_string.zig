const std = @import("std");

/// Segment 表示字符串的一个片段
/// 采用连续内存的数组结构，Cache-friendly
pub const Segment = struct {
    /// 该 Segment 的实际内容
    content: []const u8,

    /// 如果该 Segment 来自原始字符串，记录其在原始字符串中的起始位置
    /// null 表示这是插入的新内容
    source_offset: ?usize,

    /// 在此位置左侧插入的内容（用于 appendLeft）
    intro: ?[]const u8,
    /// 在此位置右侧插入的内容（用于 appendRight）
    outro: ?[]const u8,

    /// 创建一个来自原始字符串的 Segment
    pub fn fromSource(content: []const u8, offset: usize) Segment {
        return Segment{
            .content = content,
            .source_offset = offset,
            .intro = null,
            .outro = null,
        };
    }

    /// 创建一个新插入的 Segment
    pub fn fromInsert(content: []const u8) Segment {
        return Segment{
            .content = content,
            .source_offset = null,
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
        if (target_offset >= offsets[offsets.len - 1] + self.segments.items[self.segments.items.len - 1].length()) {
            return error.OffsetOutOfBounds;
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
};
