#!/bin/bash

# GitLab 推送脚本
# 用途：将代码推送到 GitLab 仓库
# 使用方法: ./scripts/push_to_gitlab.sh [--remote REMOTE] [--branch BRANCH]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
REMOTE="gitlab"
BRANCH="main"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help|-h)
            echo "GitLab 推送脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --remote REMOTE       远程仓库名称 (默认: gitlab)"
            echo "  --branch BRANCH       分支名称 (默认: main)"
            echo ""
            echo "示例:"
            echo "  $0 --remote gitlab --branch main"
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数: $1${NC}" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "========================================"
echo "推送到 GitLab"
echo "========================================"
echo "远程: $REMOTE"
echo "分支: $BRANCH"
echo "========================================"

# 检查远程仓库是否存在
if ! git remote | grep -q "^${REMOTE}$"; then
    echo -e "${YELLOW}警告: 远程仓库 '$REMOTE' 不存在${NC}"
    echo "请先添加 GitLab 远程仓库:"
    echo "  git remote add $REMOTE <gitlab_repo_url>"
    exit 1
fi

# 获取当前分支
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 如果当前分支不是目标分支，询问是否切换
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo -e "${YELLOW}当前分支: $CURRENT_BRANCH${NC}"
    read -p "是否切换到分支 $BRANCH? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout "$BRANCH"
    fi
fi

# 检查是否有未提交的更改
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}警告: 有未提交的更改${NC}"
    read -p "是否继续推送? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 推送代码
echo "正在推送到 $REMOTE/$BRANCH..."
if git push "$REMOTE" "$BRANCH"; then
    echo -e "${GREEN}✓ 推送成功！${NC}"
else
    echo -e "${RED}✗ 推送失败${NC}" >&2
    exit 1
fi

# 推送所有标签
echo "正在推送标签..."
if git push "$REMOTE" --tags; then
    echo -e "${GREEN}✓ 标签推送成功！${NC}"
else
    echo -e "${YELLOW}警告: 标签推送失败或没有标签${NC}"
fi

echo "========================================"
echo "完成！"
echo "========================================"

