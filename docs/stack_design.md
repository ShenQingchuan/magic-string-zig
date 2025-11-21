# MagicString Stack 设计稿

> 目标：在 Zig 端复刻 `magic-string-stack` 的能力，支持多次 commit/rollback，并在生成 Source Map 时自动合并全部层级的映射信息。

## 结构设计

- `MagicStringStack` 将作为全新的公开类型，位于 `src/magic_string.zig` 顶层，与既有 `MagicString` 并列。
- 内部包含：
  - `allocator: std.mem.Allocator`：统一管理所有层的生命周期。
  - `layers: std.ArrayList(*MagicString)`：按栈结构存放 `MagicString` 指针，`layers.items[0]` 即当前活跃实例。
  - `options: MagicStringStackOptions`：目前仅透传 `SourceMapOptions`/未来可扩展。
- 栈顶 `MagicString` 暴露全部原方法（appendLeft/overwrite 等），Stack 仅作为管理容器。

## API 规划

| 函数 | 说明 |
| --- | --- |
| `init(allocator, source: []const u8) !*MagicStringStack` | 创建 Stack，并在 `layers` 中放入首个 `MagicString`。 |
| `deinit(self: *MagicStringStack) void` | 释放栈内所有 `MagicString` 以及数组本身。 |
| `current(self: *MagicStringStack) *MagicString` | 返回当前层，供操作函数复用。 |
| `commit(self: *MagicStringStack) !void` | 将 `current().toString()` 结果作为新 `MagicString` 的原始内容推入栈顶。 |
| `rollback(self: *MagicStringStack) !void` | 弹出栈顶并销毁之，禁止在层数为 1 时调用。 |
| `toString(self: *MagicStringStack) ![]const u8` | 直接委托给 `current()`. |
| `generateMap(self: *MagicStringStack, options) !*SourceMap` | 若层数为 1，直接返回 `current().generateMap`；否则走 Step4 的 remapping 流程。 |
| `generateDecodedMap(self: *MagicStringStack, options) !DecodedSourceMap` | 为 remapping 提供中间数据。 |

## 生命周期与内存

1. `init` 时会复制源字符串，与 `MagicString.init` 一致，确保后续 commit 之间互不影响。
2. `commit` 流程：
   - 调用 `current().toString()` 获取完整结果。
   - 用该结果创建新的 `MagicString`，记得在复制后释放临时字符串。
   - 将新实例插入 `layers` 的开头（或末尾，视实现而定），并设置为当前层。
3. `rollback` 需调用 `MagicString.deinit` 释放被弹出的实例。
4. Stack 本身的 `deinit` 负责遍历 `layers` 统一清理。

## 后续实现要点

1. **代理操作**：Zig 端不会像 JS 那样做 Proxy，但会提供 `MagicStringStack.current()` 供后续直接调用 `current().appendLeft(...)`。
2. **Source Map 合并**：Step4 里会基于 `@jridgewell/remapping` 的算法编写 Zig 版本的树状合并器；`MagicStringStack.generateMap` 将成为唯一调用方。
3. **测试策略**：
   - `tests/unit_test.zig`：增加 commit/rollback 正反用例。
   - `tests/snapshot_test.zig` 与 `tests/consistency.test.ts`：加入多层 commit 的场景，对照 JS 版 `magic-string-stack`。

这一设计确保我们能先以 `MagicStringStack` 封装生命周期，再逐步实现 remapping 与对外 API。

