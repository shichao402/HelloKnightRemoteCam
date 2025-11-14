#!/bin/bash

# GitHub 仓库推送脚本
# 使用方法: ./scripts/push_to_github.sh <你的GitHub用户名> <仓库名>
# 例如: ./scripts/push_to_github.sh shichao402 HelloKnightRemoteCam

set -e

if [ $# -lt 2 ]; then
    echo "使用方法: $0 <GitHub用户名> <仓库名>"
    echo "例如: $0 shichao402 HelloKnightRemoteCam"
    exit 1
fi

GITHUB_USER=$1
REPO_NAME=$2
REPO_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "准备推送到 GitHub..."
echo "仓库URL: ${REPO_URL}"
echo ""

# 检查是否已配置远程仓库
if git remote get-url origin >/dev/null 2>&1; then
    echo "检测到已存在的远程仓库，更新URL..."
    git remote set-url origin "${REPO_URL}"
else
    echo "添加远程仓库..."
    git remote add origin "${REPO_URL}"
fi

echo "验证远程仓库配置..."
git remote -v

echo ""
echo "推送代码到 GitHub..."
git branch -M main
git push -u origin main

echo ""
echo "✅ 代码已成功推送到 GitHub!"
echo "访问: https://github.com/${GITHUB_USER}/${REPO_NAME}"


