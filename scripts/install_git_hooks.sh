#!/bin/bash

# 配置 Git 以实现自动双平台推送
# 使用方法: ./scripts/install_git_hooks.sh

set -e

echo "========================================"
echo "配置 Git 自动双平台推送"
echo "========================================"

# 检查是否已配置双远程仓库
HAS_GITHUB=false
HAS_GITEE=false

if git remote get-url github >/dev/null 2>&1; then
    HAS_GITHUB=true
    GITHUB_URL=$(git remote get-url github)
    echo "✅ GitHub 远程仓库: $GITHUB_URL"
fi

if git remote get-url gitee >/dev/null 2>&1; then
    HAS_GITEE=true
    GITEE_URL=$(git remote get-url gitee)
    echo "✅ Gitee 远程仓库: $GITEE_URL"
fi

if [ "$HAS_GITHUB" = false ] && [ "$HAS_GITEE" = false ]; then
    echo ""
    echo "⚠️  未找到 GitHub 或 Gitee 远程仓库"
    echo "请先运行: ./scripts/setup_dual_remote.sh"
    exit 1
fi

# 配置 origin 的多个 push URL（如果两个平台都存在）
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [[ "$ORIGIN_URL" == *"github.com"* ]]; then
        # origin 是 GitHub，添加 Gitee 作为额外的 push URL
        echo ""
        echo "配置 origin 同时推送到 GitHub 和 Gitee..."
        git remote set-url --add --push origin "$GITHUB_URL"
        git remote set-url --add --push origin "$GITEE_URL"
        echo "✅ 已配置 origin 同时推送到两个平台"
    elif [[ "$ORIGIN_URL" == *"gitee.com"* ]]; then
        # origin 是 Gitee，添加 GitHub 作为额外的 push URL
        echo ""
        echo "配置 origin 同时推送到 Gitee 和 GitHub..."
        git remote set-url --add --push origin "$GITEE_URL"
        git remote set-url --add --push origin "$GITHUB_URL"
        echo "✅ 已配置 origin 同时推送到两个平台"
    fi
fi

# 创建 Git alias 用于推送到两个平台
echo ""
echo "创建 Git 别名..."

# push-all: 推送到所有配置的平台
git config --global alias.push-all '!f(){ for remote in $(git remote); do echo "推送到 $remote..."; git push "$remote" "$@" || echo "  $remote 推送失败"; done; }; f' 2>/dev/null || true

# push-both: 推送到 GitHub 和 Gitee
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    git config --global alias.push-both '!f(){ git push origin "$@" && (git push github "$@" 2>/dev/null || true) && (git push gitee "$@" 2>/dev/null || true); }; f' 2>/dev/null || true
fi

echo "✅ Git 别名创建完成"
echo ""
echo "========================================"
echo "配置完成！"
echo "========================================"
echo ""
echo "现在你可以："
echo ""
echo "1. 使用 'git push origin <branch>' 推送到主平台"
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    echo "   （如果配置了多个 push URL，会自动推送到两个平台）"
fi
echo ""
echo "2. 使用 'git push-all <branch>' 推送到所有远程仓库"
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    echo "3. 使用 'git push-both <branch>' 推送到 GitHub 和 Gitee"
fi
echo ""
echo "4. 推送标签也会自动同步到两个平台"
echo ""
echo "当前远程仓库配置："
git remote -v

