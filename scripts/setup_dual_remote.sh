#!/bin/bash

# 配置双远程仓库脚本（GitHub + Gitee）
# 使用方法: ./scripts/setup_dual_remote.sh [gitee_url]
# 例如: ./scripts/setup_dual_remote.sh https://gitee.com/your-username/HelloKnightRemoteCam.git

set -e

GITEE_URL=$1

echo "========================================"
echo "配置双远程仓库（GitHub + Gitee）"
echo "========================================"

# 检查是否已存在 origin 远程仓库
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "错误: 未找到 origin 远程仓库"
    exit 1
fi

ORIGIN_URL=$(git remote get-url origin)
echo "当前 origin 远程仓库: $ORIGIN_URL"

# 检测 origin 是 GitHub 还是 Gitee
if [[ "$ORIGIN_URL" == *"gitee.com"* ]]; then
    echo "检测到 origin 是 Gitee 仓库"
    GITHUB_REMOTE="github"
    GITEE_REMOTE="origin"
    
    # 如果没有提供 Gitee URL，使用 origin
    if [ -z "$GITEE_URL" ]; then
        GITEE_URL="$ORIGIN_URL"
    fi
    
    # 需要用户提供 GitHub URL
    if [ -z "$GITEE_URL" ]; then
        echo ""
        read -p "请输入 GitHub 仓库 URL: " GITHUB_URL
        if [ -z "$GITHUB_URL" ]; then
            echo "错误: 必须提供 GitHub 仓库 URL"
            exit 1
        fi
    fi
else
    echo "检测到 origin 是 GitHub 仓库"
    GITHUB_REMOTE="origin"
    GITEE_REMOTE="gitee"
    
    # 如果没有提供 Gitee URL，需要用户输入
    if [ -z "$GITEE_URL" ]; then
        echo ""
        read -p "请输入 Gitee 仓库 URL（留空跳过）: " GITEE_URL
    fi
fi

# 配置 GitHub 远程仓库
if ! git remote get-url "$GITHUB_REMOTE" >/dev/null 2>&1; then
    if [ "$GITHUB_REMOTE" == "github" ] && [ -n "$GITHUB_URL" ]; then
        echo "添加 GitHub 远程仓库: $GITHUB_URL"
        git remote add github "$GITHUB_URL"
    fi
else
    echo "GitHub 远程仓库已存在: $(git remote get-url $GITHUB_REMOTE)"
fi

# 配置 Gitee 远程仓库
if [ -n "$GITEE_URL" ]; then
    if ! git remote get-url "$GITEE_REMOTE" >/dev/null 2>&1; then
        echo "添加 Gitee 远程仓库: $GITEE_URL"
        git remote add gitee "$GITEE_URL"
    else
        echo "Gitee 远程仓库已存在: $(git remote get-url $GITEE_REMOTE)"
        read -p "是否更新 Gitee 远程仓库 URL? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git remote set-url gitee "$GITEE_URL"
            echo "已更新 Gitee 远程仓库 URL"
        fi
    fi
fi

# 显示当前远程仓库配置
echo ""
echo "========================================"
echo "当前远程仓库配置:"
echo "========================================"
git remote -v

# 配置 origin 的多个 push URL（如果两个平台都存在）
if [ "$HAS_GITHUB" = true ] && [ "$HAS_GITEE" = true ]; then
    ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [[ "$ORIGIN_URL" == *"github.com"* ]]; then
        # origin 是 GitHub，添加 Gitee 作为额外的 push URL
        echo ""
        echo "配置 origin 同时推送到 GitHub 和 Gitee..."
        # 先设置 fetch URL
        git remote set-url origin "$ORIGIN_URL"
        # 添加多个 push URL
        git remote set-url --add --push origin "$ORIGIN_URL"
        git remote set-url --add --push origin "$GITEE_URL"
        echo "✅ 已配置 origin 同时推送到两个平台"
    elif [[ "$ORIGIN_URL" == *"gitee.com"* ]]; then
        # origin 是 Gitee，添加 GitHub 作为额外的 push URL
        echo ""
        echo "配置 origin 同时推送到 Gitee 和 GitHub..."
        # 先设置 fetch URL
        git remote set-url origin "$ORIGIN_URL"
        # 添加多个 push URL
        git remote set-url --add --push origin "$ORIGIN_URL"
        git remote set-url --add --push origin "$GITHUB_URL"
        echo "✅ 已配置 origin 同时推送到两个平台"
    fi
fi

echo ""
echo "提示：运行 './scripts/install_git_hooks.sh' 来配置 Git 别名"

echo ""
echo "========================================"
echo "配置完成！"
echo "========================================"
echo ""
echo "现在你可以："
echo "1. 使用 'git push origin <branch>' 推送到主平台"
echo "2. 使用 'git push-all <branch>' 同时推送到两个平台"
echo "3. 推送标签会自动同步到两个平台"
echo ""
echo "注意：首次推送可能需要配置认证信息"

