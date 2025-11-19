const std = @import("std");
const napi = @import("napi");
const MagicString = @import("magic_string.zig").MagicString;
const SourceMapOptions = @import("sourcemap.zig").SourceMapOptions;

/// 全局分配器，用于创建 MagicString 实例
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

/// 创建 MagicString 实例
/// JS: const ms = createMagicString("source code")
fn createMagicString(env: napi.Env, source: napi.Value) !napi.Value {
    var buf: [4096]u8 = undefined;
    const len = try source.getValueString(.utf8, &buf);
    const source_str = buf[0..len];

    const ms = try MagicString.init(allocator, source_str);

    // 将指针转换为数值返回给 JS（使用 f64 存储）
    const ptr_value = @intFromPtr(ms);
    const ptr_as_f64: f64 = @floatFromInt(ptr_value);
    return try env.create(f64, ptr_as_f64);
}

/// 调用 toString 方法
/// JS: const result = magicStringToString(handle)
fn magicStringToString(env: napi.Env, handle: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    const result_str = try ms.toString();
    defer allocator.free(result_str);

    return try env.createString(.utf8, result_str);
}

/// 释放 MagicString 实例
/// JS: destroyMagicString(handle)
fn destroyMagicString(env: napi.Env, handle: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    ms.deinit();
    return try env.create(void, {});
}

/// appendLeft: 在指定索引左侧插入内容
/// JS: appendLeft(handle, index, content)
fn magicStringAppendLeft(env: napi.Env, handle: napi.Value, index_val: napi.Value, content_val: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    const index = try index_val.getValue(f64);
    const index_usize: usize = @intFromFloat(index);

    var buf: [4096]u8 = undefined;
    const len = try content_val.getValueString(.utf8, &buf);
    const content = buf[0..len];

    try ms.appendLeft(index_usize, content);

    return try env.create(void, {});
}

/// appendRight: 在指定索引右侧插入内容
/// JS: appendRight(handle, index, content)
fn magicStringAppendRight(env: napi.Env, handle: napi.Value, index_val: napi.Value, content_val: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    const index = try index_val.getValue(f64);
    const index_usize: usize = @intFromFloat(index);

    var buf: [4096]u8 = undefined;
    const len = try content_val.getValueString(.utf8, &buf);
    const content = buf[0..len];

    try ms.appendRight(index_usize, content);

    return try env.create(void, {});
}

/// overwrite: 用新内容替换指定范围
/// JS: overwrite(handle, start, end, content)
fn magicStringOverwrite(env: napi.Env, handle: napi.Value, start_val: napi.Value, end_val: napi.Value, content_val: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    const start = try start_val.getValue(f64);
    const start_usize: usize = @intFromFloat(start);

    const end = try end_val.getValue(f64);
    const end_usize: usize = @intFromFloat(end);

    var buf: [4096]u8 = undefined;
    const len = try content_val.getValueString(.utf8, &buf);
    const content = buf[0..len];

    try ms.overwrite(start_usize, end_usize, content);

    return try env.create(void, {});
}

/// generateMap: 生成 Source Map
/// JS: generateMap(handle)
fn magicStringGenerateMap(env: napi.Env, handle: napi.Value) !napi.Value {
    const ptr_as_f64 = try handle.getValue(f64);
    const ptr_value: usize = @intFromFloat(ptr_as_f64);
    const ms: *MagicString = @ptrFromInt(ptr_value);

    // 暂时使用默认选项
    const options = SourceMapOptions{};

    // 生成 Source Map
    const map = try ms.generateMap(options);
    defer {
        map.deinit();
        allocator.destroy(map);
    }

    // 转换为 JSON
    const json = try map.toJSON(allocator);
    defer allocator.free(json);

    // 返回 JSON 字符串
    return try env.createString(.utf8, json);
}

fn init(env: napi.Env, exports: napi.Value) !napi.Value {
    try exports.setNamedProperty("createMagicString", try env.createFunction(createMagicString, "createMagicString"));
    try exports.setNamedProperty("toString", try env.createFunction(magicStringToString, "toString"));
    try exports.setNamedProperty("appendLeft", try env.createFunction(magicStringAppendLeft, "appendLeft"));
    try exports.setNamedProperty("appendRight", try env.createFunction(magicStringAppendRight, "appendRight"));
    try exports.setNamedProperty("overwrite", try env.createFunction(magicStringOverwrite, "overwrite"));
    try exports.setNamedProperty("generateMap", try env.createFunction(magicStringGenerateMap, "generateMap"));
    try exports.setNamedProperty("destroy", try env.createFunction(destroyMagicString, "destroy"));
    return exports;
}

comptime {
    napi.registerModule(init);
}
