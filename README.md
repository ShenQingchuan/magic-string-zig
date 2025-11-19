# magic-string-zig

<div align="center">

**用于字符串操作和 Source Map 生成的高性能 Zig 工具库**

[![Zig Version](https://img.shields.io/badge/zig-0.15.2-blue)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

</div>

> ✨ **已完成 Zig 0.15 迁移！** 现已完全兼容 Zig 0.15.2
>
> 📌 **版本说明**：v0.2.0+ 兼容 Zig 0.15.0+，v0.1.0 兼容 Zig 0.14.0（代码在分支 `zig-0.14.x`）

## 📖 简介

> 🌱 本项目采用 Vibe Coding 编写，因此非常欢迎批评指正和改进建议！

`magic-string-zig` 是 [magic-string](https://github.com/rich-harris/magic-string) 的 Zig 实现，提供了高效的字符串操作和 Source Map 生成能力。该库专为构建工具、代码转换器和编译器设计，能够精确追踪源代码的修改位置，并生成符合 Source Map v3 规范的映射文件。

灵感来自 [magic-string](https://github.com/rich-harris/magic-string) **\[ MIT Licensed \]**，本项目采用了 CPU 缓存友好的连续内存布局 ArrayList 而非链表实现。

### 核心特性

- ⚡ **高性能**：采用 Zig 编写，零成本抽象，内存布局优化
- 🎯 **精确追踪**：支持在任意位置插入、替换内容，并准确记录原始位置
- 🗺️ **Source Map 生成**：完整支持 Source Map v3 规范，包括 VLQ 编码
- 🔄 **Zig 0.15 就绪**：已完成迁移，使用新的 `std.Io.Writer` 接口和 `std.json.fmt` API
- 🧪 **完整测试**：包含单元测试和一致性测试，确保与 JS 版本功能一致
- 📊 **基准测试**：提供性能基准测试工具

## 🚀 快速开始

### 安装

确保已安装 [Zig](https://ziglang.org/download/) 0.15.2 或更高版本。

```bash
# 克隆仓库
git clone https://github.com/shenqingchuan/magic-string-zig.git
cd magic-string-zig

# 构建项目
zig build

# 运行测试
zig build test
```

### 基本使用

#### Zig 代码中使用

```zig
const std = @import("std");
const MagicString = @import("magic_string").MagicString;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建 MagicString 实例
    var ms = try MagicString.init(allocator, "Hello, World!");
    defer ms.deinit();

    // 在位置 5 左侧插入内容
    try ms.appendLeft(5, "Beautiful ");

    // 替换指定范围
    try ms.overwrite(13, 18, "Zig!");

    // 获取结果
    const result = try ms.toString();
    defer allocator.free(result);
    
    std.debug.print("{s}\n", .{result}); // 输出: "Hello Beautiful Zig!"
}
```

## 📚 API 文档

### `MagicString`

#### `init(allocator: Allocator, source: []const u8) MagicString`

创建一个新的 `MagicString` 实例。

- `allocator`: 内存分配器
- `source`: 原始源字符串

**返回**: `MagicString` 实例

#### `deinit(self: *MagicString) void`

释放 `MagicString` 实例占用的所有内存。

#### `toString(self: *const MagicString) ![]u8`

生成最终的字符串结果。

**返回**: 分配的新字符串，调用者负责释放

#### `appendLeft(self: *MagicString, index: usize, content: []const u8) !void`

在指定索引位置的左侧插入内容。

- `index`: 插入位置（基于原始字符串的索引）
- `content`: 要插入的内容

#### `appendRight(self: *MagicString, index: usize, content: []const u8) !void`

在指定索引位置的右侧插入内容。

- `index`: 插入位置（基于原始字符串的索引）
- `content`: 要插入的内容

#### `overwrite(self: *MagicString, start: usize, end: usize, content: []const u8) !void`

用新内容替换指定范围。

- `start`: 起始位置（包含）
- `end`: 结束位置（不包含）
- `content`: 替换内容

#### `generateMap(self: *const MagicString, options: SourceMapOptions) !*SourceMap`

生成 Source Map。

- `options`: Source Map 配置选项

**返回**: `SourceMap` 实例，调用者负责调用 `deinit()` 和 `destroy()`

### `SourceMapOptions`

```zig
pub const SourceMapOptions = struct {
    file: ?[]const u8 = null,              // 生成的文件名
    source_root: ?[]const u8 = null,       // 源文件根路径
    source: ?[]const u8 = null,            // 源文件名
    include_content: bool = false,          // 是否包含源文件内容
    hires: bool = false,                    // 是否美化输出
};
```

### `SourceMap`

#### `toJSON(self: *const SourceMap, allocator: Allocator) ![]u8`

将 Source Map 转换为 JSON 字符串。

**返回**: JSON 字符串，调用者负责释放

#### `deinit(self: *SourceMap) void`

释放 Source Map 占用的内存。

## 💡 使用示例

### 示例 1: 代码转换

```zig
var ms = try MagicString.init(allocator, "const x = 1;");
defer ms.deinit();

// 添加类型注解
try ms.overwrite(5, 5, ": number");

const result = try ms.toString();
defer allocator.free(result);
// 结果: "const x: number = 1;"
```

### 示例 2: 生成 Source Map

```zig
var ms = try MagicString.init(allocator, "console.log('hello');");
defer ms.deinit();

try ms.overwrite(0, 12, "print");

const options = SourceMapOptions{
    .file = "output.js",
    .source = "input.js",
    .include_content = true,
};

const map = try ms.generateMap(options);
defer {
    map.deinit();
    allocator.destroy(map);
}

const json = try map.toJSON(allocator);
defer allocator.free(json);
// json 包含完整的 Source Map JSON
```

### 示例 3: 多次修改

```zig
var ms = try MagicString.init(allocator, "foo bar baz");
defer ms.deinit();

try ms.appendLeft(4, "qux ");   // "foo qux bar baz"
try ms.overwrite(8, 11, "quux"); // "foo qux quux baz"
try ms.appendRight(12, " quuz"); // "foo qux quux baz quuz"

const result = try ms.toString();
defer allocator.free(result);
```

## ⚡ 性能

`magic-string-zig` 针对性能进行了优化：

- **零成本抽象**：Zig 的编译期特性和零成本抽象确保运行时开销最小
- **缓存友好**：使用连续内存布局的 `ArrayList` 存储片段，提高缓存命中率
- **高效算法**：优化的片段合并和位置计算算法

运行基准测试：

```bash
zig build bench
```

## 🧪 测试

> 由于包含对 JS 版本 magic-string 的对比测试，测试采用 [Vitest](https://vitest.dev/) 运行。

项目包含完整的测试套件：

```bash
# 运行所有测试
pnpm test

# 仅运行 Zig 单元测试
zig build test

# 运行一致性测试（与上游 magic-string 对比）
pnpm run test:consistency
```

## 📁 项目结构

```
magic-string-zig/
├── src/
│   ├── magic_string.zig    # 核心 MagicString 实现
│   ├── sourcemap.zig        # Source Map 生成器
│   ├── vlq.zig              # VLQ 编码实现
│   └── root.zig             # NAPI 绑定入口
├── tests/
│   ├── unit_test.zig        # Zig 单元测试
│   ├── snapshot_test.zig    # 快照测试
│   └── consistency.test.ts  # 一致性测试
├── bench/
│   └── benchmark.zig        # 性能基准测试
└── build.zig                # 构建配置
```

## 🤝 贡献

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 开发指南

- 代码风格遵循 Zig 官方风格指南
- 所有新功能需要包含测试
- 确保所有测试通过：`zig build test`
- 提交前运行：`pnpm test`

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [magic-string](https://github.com/rich-harris/magic-string) - 原始 JavaScript 实现
- [Zig](https://ziglang.org/) - 系统编程语言

## 📮 联系方式

如有问题或建议，请通过以下方式联系：

- 提交 [Issue](https://github.com/shenqingchuan/magic-string-zig/issues)
- 开启 [Discussion](https://github.com/shenqingchuan/magic-string-zig/discussions)

---

<div align="center">

**Made with ❤️ using Zig**

[⬆ 回到顶部](#magic-string-zig)

</div>

