#!/bin/bash

# Olend 项目代码格式化脚本
# 使用 sui move fmt 格式化所有 Move 代码

echo "正在格式化 Move 代码..."

# 格式化源代码
sui move fmt

echo "代码格式化完成！"

# 检查是否有格式化变更
if git diff --quiet; then
    echo "✅ 代码格式符合规范"
else
    echo "⚠️  发现格式化变更，请检查 git diff"
fi