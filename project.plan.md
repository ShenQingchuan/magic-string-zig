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

## Phase 3: 复杂编辑 (Overwrite & Split)
- [ ] **Task 3.1**: 实现 `byIndex` 查找 Chunk
    - 根据字符索引快速定位对应的 Chunk
- [ ] **Task 3.2**: 实现 `split` 操作
    - 将一个 Chunk 从中间切分为两个
- [ ] **Task 3.3**: 实现 `overwrite(start, end, content)`
    - 涉及 Chunk 分裂和内容替换

## Phase 4: Source Map 功能
- [ ] **Task 4.1**: 实现 `generateMap()`

## Phase 5: JS 侧优化
- [ ] **Task 5.1**: 创建 JS Class 包装器
    - 创建 `src/MagicString.js` 封装函数式 API
    - 提供优雅的 `new MagicString(source)` 接口
    - 使用 `FinalizationRegistry` 自动内存管理
- [x] **Task 5.2**: 迁移测试到 Vitest
    - 使用 Vitest 重写测试套件
    - 提供更好的测试体验和断言
