#!/bin/bash

# 更新配置文件上传脚本
# 用途：将更新配置文件上传到 GitLab 仓库
# 使用方法: ./scripts/upload_update_config.sh [--file CONFIG_FILE] [--commit-message MESSAGE]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
CONFIG_FILE=""
COMMIT_MESSAGE="更新更新配置文件"
BRANCH="main"
REMOTE="gitlab"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --commit-message)
            COMMIT_MESSAGE="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --help|-h)
            echo "更新配置文件上传脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --file FILE           配置文件路径 (默认: update_config.json)"
            echo "  --commit-message MSG  提交消息"
            echo "  --branch BRANCH       分支名称 (默认: main)"
            echo "  --remote REMOTE       远程仓库名称 (默认: gitlab)"
            echo ""
            echo "示例:"
            echo "  $0 --file update_config.json --commit-message '更新到版本 1.0.0'"
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

# 设置默认配置文件
if [ -z "$CONFIG_FILE" ]; then
    CONFIG_FILE="$PROJECT_ROOT/update_config.json"
fi

# 检查文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件未找到: $CONFIG_FILE${NC}" >&2
    echo "请先运行 generate_update_config.sh 生成配置文件"
    exit 1
fi

cd "$PROJECT_ROOT"

echo "========================================"
echo "上传更新配置文件到 GitLab"
echo "========================================"
echo "文件: $CONFIG_FILE"
echo "分支: $BRANCH"
echo "远程: $REMOTE"
echo "========================================"

# 检查远程仓库是否存在
if ! git remote | grep -q "^${REMOTE}$"; then
    echo -e "${RED}错误: 远程仓库 '$REMOTE' 不存在${NC}" >&2
    echo "请先添加 GitLab 远程仓库:"
    echo "  git remote add $REMOTE <gitlab_repo_url>"
    exit 1
fi

# 确保在正确的分支
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo -e "${YELLOW}当前分支: $CURRENT_BRANCH，切换到 $BRANCH${NC}"
    git checkout "$BRANCH"
fi

# 复制配置文件到仓库根目录（如果不在根目录）
if [ "$(dirname "$CONFIG_FILE")" != "$PROJECT_ROOT" ]; then
    cp "$CONFIG_FILE" "$PROJECT_ROOT/update_config.json"
    CONFIG_FILE="$PROJECT_ROOT/update_config.json"
fi

# 检查是否有更改
if git diff --quiet "$CONFIG_FILE"; then
    echo -e "${YELLOW}配置文件没有更改，跳过提交${NC}"
    exit 0
fi

# 添加文件
git add "$CONFIG_FILE"

# 提交
git commit -m "$COMMIT_MESSAGE"

# 推送
echo "正在推送到 $REMOTE/$BRANCH..."
if git push "$REMOTE" "$BRANCH"; then
    echo -e "${GREEN}✓ 上传成功！${NC}"
    
    # 显示访问URL（需要从git remote获取）
    GITLAB_URL=$(git remote get-url "$REMOTE" | sed 's/\.git$//' | sed 's/^git@/https:\/\//' | sed 's/:/\//')
    if [ -n "$GITLAB_URL" ]; then
        RAW_URL="${GITLAB_URL}/-//raw/${BRANCH}/update_config.json"
        echo -e "${GREEN}配置文件访问URL: ${RAW_URL}${NC}"
    fi
else
    echo -e "${RED}✗ 上传失败${NC}" >&2
    exit 1
fi

echo "========================================"
echo "完成！"
echo "========================================"

