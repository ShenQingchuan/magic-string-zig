#!/bin/bash

set -e

echo "=========================================="
echo "Magic String 性能基准测试对比"
echo "=========================================="
echo ""

# 确保基准测试可执行文件已构建
echo "执行 Zig 构建..."
zig build

echo ""
echo "使用 hyperfine 进行对比测试..."
echo "=========================================="
echo ""

# 检查 hyperfine 是否安装
if ! command -v hyperfine &> /dev/null; then
    echo "错误: 未找到 hyperfine，请先安装！"
    exit 1
fi

# 使用 hyperfine 对比测试
hyperfine \
    --warmup 3 \
    --runs 10 \
    "pnpm exec tsx bench/magic-string.bench.ts" \
    "zig-out/bin/bench"

echo ""
echo "基准测试完成！"

