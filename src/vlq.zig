const std = @import("std");

/// VLQ (Variable Length Quantity) Base64 编码实现
///
/// Source Map v3 规范使用 VLQ Base64 编码来压缩 mappings 数据。
/// 这是一种变长编码，可以用更少的字符表示小数字。
///
/// VLQ 编码规则：
/// 1. 使用 Base64 字符集：ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
/// 2. 每个 Base64 字符代表 6 位数据
/// 3. 第 6 位（最高位）是 continuation bit（继续位）：
///    - 1 表示后面还有更多字节
///    - 0 表示这是最后一个字节
/// 4. 第 1 位（最低位）在第一个字节中表示符号位：
///    - 0 表示正数
///    - 1 表示负数
/// 5. 数字以 least significant first（最低有效位在前）的顺序编码
///
/// 示例：
/// - 数字 0  → "A" (000000)
/// - 数字 1  → "C" (000010)
/// - 数字 -1 → "D" (000011)
/// - 数字 15 → "e" (011110)
/// - 数字 16 → "gB" (100000, 000001) - 需要两个字符
/// Base64 字符表（符合 RFC 4648）
const BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// VLQ 编码的基础值（每个字节 5 位有效数据）
const VLQ_BASE_SHIFT: u6 = 5;
const VLQ_BASE: u32 = 1 << VLQ_BASE_SHIFT; // 32

/// VLQ 继续位掩码（第 6 位）
const VLQ_CONTINUATION_BIT: u32 = VLQ_BASE; // 100000

/// VLQ 符号位掩码（第 1 位）
const VLQ_SIGN_BIT: u32 = 1;

/// 将整数编码为 VLQ Base64 字符串
///
/// 参数：
///   - allocator: 内存分配器
///   - value: 要编码的整数（可以是负数）
///
/// 返回：
///   - 编码后的字符串（调用者负责释放）
///
/// 编码步骤：
/// 1. 将值转换为绝对值，并记录符号
/// 2. 将符号位放在最低位
/// 3. 循环提取 5 位数据，设置继续位
/// 4. 将每个 5 位数据转换为 Base64 字符
pub fn encodeVLQ(allocator: std.mem.Allocator, value: i32) ![]const u8 {
    // 步骤 1：转换为无符号并处理符号位
    // 负数：将绝对值左移 1 位，然后设置符号位
    // 正数：直接左移 1 位（符号位为 0）
    var vlq: u32 = if (value < 0)
        (@as(u32, @intCast(-value)) << 1) | VLQ_SIGN_BIT
    else
        @as(u32, @intCast(value)) << 1;

    // 计算需要的字符数（最多 6 个字符可以表示 32 位整数）
    // 每个字符 5 位，32 位需要 ceil(32/5) = 7 个字符
    // 但实际上我们限制在 32 位整数范围内
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // 步骤 2：循环编码，每次处理 5 位
    while (true) {
        // 提取最低 5 位
        var digit: u32 = vlq & (VLQ_BASE - 1); // 取低 5 位：00011111

        // 右移 5 位，准备下一轮
        vlq >>= VLQ_BASE_SHIFT;

        // 如果还有剩余位，设置继续位
        if (vlq > 0) {
            digit |= VLQ_CONTINUATION_BIT; // 设置第 6 位为 1
        }

        // 转换为 Base64 字符并追加
        try result.append(BASE64_CHARS[@as(usize, @intCast(digit))]);

        // 如果没有剩余位，结束编码
        if (vlq == 0) break;
    }

    return result.toOwnedSlice();
}

/// 将多个整数批量编码为 VLQ Base64 字符串（直接连接）
///
/// 这个函数用于编码 Source Map 的一个 segment（映射段）
/// 每个 segment 包含 1, 4 或 5 个字段，字段之间直接连接（不用分隔符）
/// segment 之间的分隔由调用者负责（用逗号）
///
/// 参数：
///   - allocator: 内存分配器
///   - values: 要编码的整数数组
///
/// 返回：
///   - 编码后的字符串，各字段直接连接（调用者负责释放）
///
/// 示例：
///   encodeVLQSegment([0, 0, 0, 0]) -> "AAAA" (4个A直接连接)
pub fn encodeVLQSegment(allocator: std.mem.Allocator, values: []const i32) ![]const u8 {
    if (values.len == 0) return try allocator.dupe(u8, "");

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (values) |value| {
        // 编码当前值
        const encoded = try encodeVLQ(allocator, value);
        defer allocator.free(encoded);

        // 直接追加编码结果（不添加分隔符）
        try result.appendSlice(encoded);
    }

    return result.toOwnedSlice();
}

/// 解码单个 VLQ Base64 字符为 6 位值
///
/// 这个函数主要用于测试和验证
fn decodeBase64Char(c: u8) !u32 {
    return switch (c) {
        'A'...'Z' => c - 'A',
        'a'...'z' => c - 'a' + 26,
        '0'...'9' => c - '0' + 52,
        '+' => 62,
        '/' => 63,
        else => error.InvalidBase64Char,
    };
}

/// 解码 VLQ Base64 字符串为整数
///
/// 这个函数主要用于测试验证编码的正确性
///
/// 参数：
///   - encoded: 编码后的字符串
///
/// 返回：
///   - 解码后的整数值
pub fn decodeVLQ(encoded: []const u8) !i32 {
    var result: u32 = 0;
    var shift: u5 = 0;

    for (encoded) |c| {
        // 解码当前字符
        const digit = try decodeBase64Char(c);

        // 提取数据位（低 5 位）
        const value = digit & (VLQ_BASE - 1);

        // 将数据位放到正确的位置
        result |= value << @as(u5, @intCast(shift));

        // 检查继续位
        if ((digit & VLQ_CONTINUATION_BIT) == 0) {
            // 这是最后一个字节，处理符号位
            const is_negative = (result & VLQ_SIGN_BIT) != 0;
            result >>= 1; // 去掉符号位

            return if (is_negative)
                -@as(i32, @intCast(result))
            else
                @as(i32, @intCast(result));
        }

        shift += VLQ_BASE_SHIFT;
        if (shift >= 32) return error.ValueTooLarge;
    }

    return error.UnexpectedEnd;
}

// ============================================================================
// 单元测试
// ============================================================================

test "VLQ: 编码零" {
    const allocator = std.testing.allocator;
    const encoded = try encodeVLQ(allocator, 0);
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("A", encoded);

    // 验证解码
    const decoded = try decodeVLQ(encoded);
    try std.testing.expectEqual(@as(i32, 0), decoded);
}

test "VLQ: 编码正数" {
    const allocator = std.testing.allocator;

    // 测试 1
    {
        const encoded = try encodeVLQ(allocator, 1);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("C", encoded);
        try std.testing.expectEqual(@as(i32, 1), try decodeVLQ(encoded));
    }

    // 测试 15
    {
        const encoded = try encodeVLQ(allocator, 15);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("e", encoded);
        try std.testing.expectEqual(@as(i32, 15), try decodeVLQ(encoded));
    }

    // 测试 16（需要两个字符）
    {
        const encoded = try encodeVLQ(allocator, 16);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("gB", encoded);
        try std.testing.expectEqual(@as(i32, 16), try decodeVLQ(encoded));
    }
}

test "VLQ: 编码负数" {
    const allocator = std.testing.allocator;

    // 测试 -1
    {
        const encoded = try encodeVLQ(allocator, -1);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("D", encoded);
        try std.testing.expectEqual(@as(i32, -1), try decodeVLQ(encoded));
    }

    // 测试 -15
    {
        const encoded = try encodeVLQ(allocator, -15);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("f", encoded);
        try std.testing.expectEqual(@as(i32, -15), try decodeVLQ(encoded));
    }
}

test "VLQ: 编码大数字" {
    const allocator = std.testing.allocator;

    // 测试 1000
    {
        const encoded = try encodeVLQ(allocator, 1000);
        defer allocator.free(encoded);
        const decoded = try decodeVLQ(encoded);
        try std.testing.expectEqual(@as(i32, 1000), decoded);
    }

    // 测试 -1000
    {
        const encoded = try encodeVLQ(allocator, -1000);
        defer allocator.free(encoded);
        const decoded = try decodeVLQ(encoded);
        try std.testing.expectEqual(@as(i32, -1000), decoded);
    }
}

test "VLQ: 编码 segment" {
    const allocator = std.testing.allocator;

    // 测试空数组
    {
        const encoded = try encodeVLQSegment(allocator, &[_]i32{});
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("", encoded);
    }

    // 测试单个值
    {
        const encoded = try encodeVLQSegment(allocator, &[_]i32{0});
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("A", encoded);
    }

    // 测试多个值（典型的 4 字段 segment）
    {
        const values = [_]i32{ 0, 0, 0, 0 };
        const encoded = try encodeVLQSegment(allocator, &values);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("AAAA", encoded); // 4个A直接连接
    }

    // 测试混合正负数
    {
        const values = [_]i32{ 1, -1, 15, -15 };
        const encoded = try encodeVLQSegment(allocator, &values);
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings("CDef", encoded); // 直接连接，无逗号
    }
}
