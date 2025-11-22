#!/bin/bash

# 推送到双平台脚本（GitHub + Gitee）
# 使用方法: ./scripts/push_to_both.sh [branch] [--tags]
# 例如: ./scripts/push_to_both.sh main
# 例如: ./scripts/push_to_both.sh main --tags

set -e

BRANCH=${1:-main}
PUSH_TAGS=false

if [ "$2" == "--tags" ] || [ "$1" == "--tags" ]; then
    PUSH_TAGS=true
    if [ "$1" == "--tags" ]; then
        BRANCH="main"
    fi
fi

echo "========================================"
echo "推送到双平台（GitHub + Gitee）"
echo "========================================"

# 检查远程仓库配置
HAS_GITHUB=false
HAS_GITEE=false

if git remote get-url github >/dev/null 2>&1; then
    HAS_GITHUB=true
    GITHUB_URL=$(git remote get-url github)
    echo "GitHub 远程仓库: $GITHUB_URL"
fi

if git remote get-url gitee >/dev/null 2>&1; then
    HAS_GITEE=true
    GITEE_URL=$(git remote get-url gitee)
    echo "Gitee 远程仓库: $GITEE_URL"
fi

if [ "$HAS_GITHUB" = false ] && [ "$HAS_GITEE" = false ]; then
    echo "错误: 未找到 GitHub 或 Gitee 远程仓库"
    echo "请先运行: ./scripts/setup_dual_remote.sh"
    exit 1
fi

# 检测 origin 是哪个平台
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$ORIGIN_URL" == *"gitee.com"* ]]; then
    PRIMARY_REMOTE="origin"
    SECONDARY_REMOTE="github"
    PRIMARY_NAME="Gitee"
    SECONDARY_NAME="GitHub"
elif [[ "$ORIGIN_URL" == *"github.com"* ]] || [[ "$ORIGIN_URL" == *"github"* ]]; then
    PRIMARY_REMOTE="origin"
    SECONDARY_REMOTE="gitee"
    PRIMARY_NAME="GitHub"
    SECONDARY_NAME="Gitee"
else
    # 默认使用 GitHub 作为主平台
    PRIMARY_REMOTE="github"
    SECONDARY_REMOTE="gitee"
    PRIMARY_NAME="GitHub"
    SECONDARY_NAME="Gitee"
fi

echo ""
echo "推送分支: $BRANCH"
echo "主平台: $PRIMARY_NAME ($PRIMARY_REMOTE)"
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    echo "次平台: $SECONDARY_NAME ($SECONDARY_REMOTE)"
fi
echo ""

# 推送到主平台
if git remote get-url "$PRIMARY_REMOTE" >/dev/null 2>&1; then
    echo "推送到 $PRIMARY_NAME ($PRIMARY_REMOTE)..."
    if git push "$PRIMARY_REMOTE" "$BRANCH"; then
        echo "✅ $PRIMARY_NAME 推送成功"
    else
        echo "❌ $PRIMARY_NAME 推送失败"
        exit 1
    fi
else
    echo "警告: 未找到 $PRIMARY_REMOTE 远程仓库，跳过"
fi

# 推送到次平台
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    if git remote get-url "$SECONDARY_REMOTE" >/dev/null 2>&1; then
        echo ""
        echo "推送到 $SECONDARY_NAME ($SECONDARY_REMOTE)..."
        if git push "$SECONDARY_REMOTE" "$BRANCH"; then
            echo "✅ $SECONDARY_NAME 推送成功"
        else
            echo "⚠️  $SECONDARY_NAME 推送失败（继续）"
        fi
    fi
fi

# 推送标签
if [ "$PUSH_TAGS" = true ]; then
    echo ""
    echo "推送所有标签..."
    
    # 获取所有标签
    TAGS=$(git tag -l)
    
    if [ -z "$TAGS" ]; then
        echo "没有标签需要推送"
    else
        for TAG in $TAGS; do
            echo "推送标签: $TAG"
            
            # 推送到主平台
            if git remote get-url "$PRIMARY_REMOTE" >/dev/null 2>&1; then
                git push "$PRIMARY_REMOTE" "$TAG" 2>/dev/null || true
            fi
            
            # 推送到次平台
            if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
                if git remote get-url "$SECONDARY_REMOTE" >/dev/null 2>&1; then
                    git push "$SECONDARY_REMOTE" "$TAG" 2>/dev/null || true
                fi
            fi
        done
        echo "✅ 标签推送完成"
    fi
fi

echo ""
echo "========================================"
echo "推送完成！"
echo "========================================"

