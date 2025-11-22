#!/bin/bash

# 创建 Release 脚本
# 使用方法: ./scripts/create_release.sh [version] [--gitee|--github]
# 例如: ./scripts/create_release.sh 1.0.0
# 例如: ./scripts/create_release.sh 1.0.0 --gitee
# 如果不提供版本号，将从 VERSION.yaml 读取
# 如果不指定平台，将自动检测远程仓库类型

set -e

# 检测平台参数
PLATFORM=""
if [ "$1" == "--gitee" ] || [ "$1" == "--github" ]; then
    PLATFORM=$1
    shift
elif [ "$2" == "--gitee" ] || [ "$2" == "--github" ]; then
    PLATFORM=$2
fi

# 如果没有指定平台，自动检测
if [ -z "$PLATFORM" ]; then
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$REMOTE_URL" == *"gitee.com"* ]]; then
        PLATFORM="--gitee"
        echo "检测到 Gitee 仓库，使用 Gitee 平台"
    elif [[ "$REMOTE_URL" == *"github.com"* ]] || [[ "$REMOTE_URL" == *"github"* ]]; then
        PLATFORM="--github"
        echo "检测到 GitHub 仓库，使用 GitHub 平台"
    else
        PLATFORM="--github"
        echo "无法检测仓库类型，默认使用 GitHub 平台"
    fi
fi

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

# 推送标签到所有配置的远程仓库
echo "推送标签到远程仓库..."

# 推送到 origin（主平台）
git push origin "$TAG" || echo "警告: origin 推送失败"

# 自动推送到另一个平台
if git remote get-url gitee >/dev/null 2>&1; then
    echo "同时推送到 Gitee..."
    git push gitee "$TAG" 2>/dev/null || echo "Gitee 推送失败（可能未配置或已存在）"
fi

if git remote get-url github >/dev/null 2>&1; then
    echo "同时推送到 GitHub..."
    git push github "$TAG" 2>/dev/null || echo "GitHub 推送失败（可能未配置或已存在）"
fi

echo ""
echo "✅ 标签已创建并推送到所有配置的平台: $TAG"
echo ""

# 显示两个平台的构建信息
HAS_GITHUB=false
HAS_GITEE=false

if git remote get-url github >/dev/null 2>&1; then
    HAS_GITHUB=true
    GITHUB_URL=$(git remote get-url github)
    REPO_PATH=$(echo "$GITHUB_URL" | sed 's/.*github.com[:/]\(.*\)\.git/\1/' | sed 's/.*@github.com:\(.*\)\.git/\1/')
    echo "GitHub Actions 将自动："
    echo "  1. 构建所有平台的应用"
    echo "  2. 创建 Release 并上传构建产物"
    echo "  查看构建进度: https://github.com/${REPO_PATH}/actions"
    echo ""
fi

if git remote get-url gitee >/dev/null 2>&1; then
    HAS_GITEE=true
    GITEE_URL=$(git remote get-url gitee)
    REPO_PATH=$(echo "$GITEE_URL" | sed 's/.*gitee.com[:/]\(.*\)\.git/\1/' | sed 's/.*@gitee.com:\(.*\)\.git/\1/')
    echo "Gitee Go 将自动："
    echo "  1. 构建所有平台的应用"
    echo "  2. 创建 Release 并上传构建产物"
    echo "  查看构建进度: https://gitee.com/${REPO_PATH}/pipeline"
    echo ""
fi

if [ "$HAS_GITHUB" = false ] && [ "$HAS_GITEE" = false ]; then
    REMOTE_URL=$(git config --get remote.origin.url)
    if [[ "$REMOTE_URL" == *"gitee.com"* ]]; then
        REPO_PATH=$(echo "$REMOTE_URL" | sed 's/.*gitee.com[:/]\(.*\)\.git/\1/' | sed 's/.*@gitee.com:\(.*\)\.git/\1/')
        echo "Gitee Go 将自动："
        echo "  1. 构建所有平台的应用"
        echo "  2. 创建 Release 并上传构建产物"
        echo "  查看构建进度: https://gitee.com/${REPO_PATH}/pipeline"
    else
        REPO_PATH=$(echo "$REMOTE_URL" | sed 's/.*github.com[:/]\(.*\)\.git/\1/' | sed 's/.*@github.com:\(.*\)\.git/\1/')
        echo "GitHub Actions 将自动："
        echo "  1. 构建所有平台的应用"
        echo "  2. 创建 Release 并上传构建产物"
        echo "  查看构建进度: https://github.com/${REPO_PATH}/actions"
    fi
fi

