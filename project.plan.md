# Magic String in Zig - Project Plan

## Phase 1: 基础架构与 TDD 环境 (Basic Structure & TDD) ✅
- [x] **Task 1.1**: 定义 `MagicString` 核心结构体 (Zig)
    - 创建 `src/magic_string.zig`
    - 实现 `init(source)`: 初始化
    - 实现 `toString()`: 返回原始内容
- [x] **Task 1.2**: N-API 函数式封装
    - 在 `src/root.zig` 中暴露函数式 API (createMagicString, toString, destroy)
    - 使用指针传递来管理 Zig 实例
- [x] **Task 1.3**: 建立 JS 测试套件
    - 创建 `playground/test.js` 测试脚本
    - 验证基础功能：初始化、toString、特殊字符处理

## Phase 2: 核心数据结构 (Segments) ✅
- [x] **Task 2.1**: 引入 Segment 数组结构（Cache-friendly 设计）
    - 定义 `Segment` 结构体 (content, source_offset, intro, outro)
    - 使用 `ArrayList<Segment>` 替代链表，实现连续内存布局
    - 实现二分查找定位 Segment（O(log n)）
    - 惰性计算偏移量缓存
- [x] **Task 2.2**: 实现基础编辑操作
    - `appendLeft(index, content)` - 在指定位置左侧插入
    - `appendRight(index, content)` - 在指定位置右侧插入
    - `splitSegment()` - Segment 分裂逻辑
    - 完整的测试覆盖（11 个测试用例全部通过）

## Phase 3: 复杂编辑 (Overwrite & Split) ✅
- [x] **Task 3.1**: 实现 `byIndex` 查找 Segment
    - 根据原始字符串偏移定位对应的 Segment
    - 使用 `findSegmentBySourceOffset` 方法
- [x] **Task 3.2**: 实现 `split` 操作
    - 将一个 Segment 从中间切分为两个
    - `splitSegment` 方法已在 Phase 2 实现
- [x] **Task 3.3**: 实现 `overwrite(start, end, content)`
    - 基于原始字符串索引的范围替换
    - 处理 Segment 分裂和内容替换
    - 正确管理内存（释放被替换的 Segment）
    - 完整的测试覆盖（7 个测试用例全部通过）

## Phase 4: Source Map 功能 ✅
- [x] **Task 4.1**: 实现 VLQ Base64 编码
    - 符合 Source Map v3 规范的 VLQ 编码/解码
    - 完整的单元测试覆盖
- [x] **Task 4.2**: 定义 SourceMap 结构和 JSON 序列化
    - `SourceMap` 结构体（version, sources, mappings 等）
    - `toJSON()` 方法生成符合规范的 JSON
- [x] **Task 4.3**: 实现 mappings 生成逻辑
    - `SourceMapGenerator` 生成器
    - 基于 Segment 数组生成 VLQ 编码的 mappings
    - 正确处理 intro/outro 和插入内容
- [x] **Task 4.4**: 暴露 `generateMap()` N-API
    - 在 `MagicString` 中添加 `generateMap` 方法
    - N-API 绑定层实现
- [x] **Task 4.5**: Source Map 测试
    - 基础 Source Map 生成测试
    - overwrite 操作的映射测试
    - appendLeft/Right 操作的映射测试
    - **对比测试**：与原版 magic-string 的 Source Map 输出完全一致
    - 完整的测试覆盖（27 个测试全部通过，包括 6 个对比测试）

## Phase 5: JS 侧优化 ⏳
- [ ] **Task 5.1**: 创建 JS Class 包装器
    - 创建 `index.ts` 封装函数式 API
    - 提供优雅的 `new MagicString(source)` 接口
    - 使用 `FinalizationRegistry` 自动内存管理
- [ ] **Task 5.2**: 迁移测试到 Vitest
    - 更新 `playground/magic-string.test.ts` 使用新的类
    - 验证所有测试通过

---

## 性能基准测试计划 (Benchmark)

### 1. Vitest Benchmark
- 基于 Tinybench，与现有测试框架集成
- 提供统计指标：mean, min, max, hz (ops/sec), p50, p75, p99
- 支持导出 JSON 并对比：`--outputJson`, `--compare`
- 运行：`pnpm vitest bench`

```typescript
import { bench } from 'vitest'

bench('Zig appendLeft', () => {
  const ms = addon.createMagicString('x'.repeat(1000))
  addon.appendLeft(ms, 0, 'prefix')
  addon.destroy(ms)
}, { time: 1000 })
```

### 2. Benchmark 结果与反思

#### 测试结果
- **创建实例**：JS 快 ~16x
- **appendLeft/Right**：JS 快 ~50x
- **toString**：JS 快 ~400x (由于缓存机制)

#### 原因分析
1. **N-API 开销**：对于 `magic-string` 这种细粒度 API（频繁的小操作），每次调用跨语言边界的开销（参数转换、上下文切换）远大于操作本身的计算量。
2. **数据传输**：字符串在 JS 和 Zig 之间传递需要复制和编码转换。
3. **V8 优化**：JS 引擎对字符串拼接和对象分配有极高的优化。

#### 架构反思
Native 模块在 Node.js 中的最佳实践并非"逐个函数移植"，而是：
- **批量处理**：将多次操作合并为一次 Native 调用。
- **计算密集**：仅在计算量（如 Parsers, Image Processing, Source Map 生成）远大于数据传输开销时使用。
- **延迟执行**：JS 端记录操作指令（Op Log），仅在 `toString()` 或 `generateMap()` 时一次性传给 Native 执行。
