#!/bin/bash

# 创建 Release 脚本
# 使用方法: ./scripts/create_release.sh [version]
# 例如: ./scripts/create_release.sh 1.0.0
# 如果不提供版本号，将从 VERSION.yaml 读取

set -e

# 获取版本号
if [ $# -eq 0 ]; then
    # 优先从 VERSION.yaml 读取版本号
    if [ -f "VERSION.yaml" ]; then
        VERSION=$(./scripts/version.sh get client | sed 's/+.*//')
    elif [ -f "client/pubspec.yaml" ]; then
        VERSION=$(grep '^version:' client/pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
    elif [ -f "server/pubspec.yaml" ]; then
        VERSION=$(grep '^version:' server/pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
    else
        echo "错误: 未找到 VERSION.yaml 或 pubspec.yaml 文件"
        exit 1
    fi
else
    VERSION=$1
fi

# 验证版本号格式 (x.y.z)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: 版本号格式不正确，应为 x.y.z (例如: 1.0.0)"
    exit 1
fi

TAG="v${VERSION}"

echo "========================================"
echo "创建 Release: $TAG"
echo "========================================"

# 检查是否已存在该标签
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "警告: 标签 $TAG 已存在"
    read -p "是否删除并重新创建? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "$TAG" 2>/dev/null || true
        git push origin ":refs/tags/$TAG" 2>/dev/null || true
    else
        echo "已取消"
        exit 1
    fi
fi

# 创建标签
echo "创建标签: $TAG"
git tag -a "$TAG" -m "Release $VERSION"

# 推送标签到 GitHub
echo "推送标签到 GitHub..."
git push origin "$TAG" || echo "警告: origin 推送失败"

echo ""
echo "✅ 标签已创建并推送到 GitHub: $TAG"
echo ""

# 显示 GitHub Actions 构建信息
REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [[ "$REMOTE_URL" == *"github.com"* ]] || [[ "$REMOTE_URL" == *"github"* ]]; then
    REPO_PATH=$(echo "$REMOTE_URL" | sed 's/.*github.com[:/]\(.*\)\.git/\1/' | sed 's/.*@github.com:\(.*\)\.git/\1/')
    echo "GitHub Actions 将自动："
    echo "  1. 构建所有平台的应用"
    echo "  2. 创建 Release 并上传构建产物"
    echo "  查看构建进度: https://github.com/${REPO_PATH}/actions"
    echo ""
fi

