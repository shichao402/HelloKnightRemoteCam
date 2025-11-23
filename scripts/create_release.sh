#!/bin/bash

# 创建 Release 脚本
# 使用方法: ./scripts/create_release.sh [version]
# 例如: ./scripts/create_release.sh 1.0.7
# 如果不提供版本号，将从 VERSION.yaml 读取
#
# 功能：
# 1. 根据版本号查找对应的构建标签（小于等于该版本的最大版本）
# 2. 触发 GitHub Actions release 工作流创建 Release

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [version] [选项]"
    echo ""
    echo "创建 GitHub Release，重用已构建的产物"
    echo ""
    echo "参数:"
    echo "  version              版本号（如 1.0.7），如果不提供则使用最新的构建结果"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 使用最新的构建结果创建 Release"
    echo "  $0 1.0.7              # 使用版本 1.0.7 的构建结果创建 Release"
    echo ""
    echo "说明:"
    echo "  - 如果不指定版本号，会查找最新的 build* 标签对应的构建结果"
    echo "  - 如果指定版本号，会查找版本号 <= 指定版本的最大 build* 标签"
    echo "  - Release 工作流会自动查找对应的构建产物并创建 Release"
}

# 检查帮助参数
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
    esac
done

# 获取版本号
USE_LATEST=false
VERSION=""

if [ $# -eq 0 ]; then
    # 无参数：使用最新构建结果
    USE_LATEST=true
    echo -e "${BLUE}未指定版本号，将使用最新的构建结果${NC}"
else
    # 检查是否是版本号格式
    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        VERSION=$1
    else
        echo -e "${RED}错误: 未知参数 '$1'${NC}"
        echo ""
        show_help
        exit 1
    fi
fi

if [ "$USE_LATEST" = true ]; then
    RELEASE_TAG="latest"
    DISPLAY_VERSION="最新版本"
else
    RELEASE_TAG="v${VERSION}"
    DISPLAY_VERSION="${RELEASE_TAG}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}创建 Release: ${DISPLAY_VERSION}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}错误: 当前目录不是 Git 仓库${NC}"
    exit 1
fi

# 获取远程仓库信息
REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [[ -z "$REMOTE_URL" ]]; then
    echo -e "${RED}错误: 未找到远程仓库配置${NC}"
    exit 1
fi

# 解析仓库路径
if [[ "$REMOTE_URL" == *"github.com"* ]] || [[ "$REMOTE_URL" == *"github"* ]]; then
    REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's/.*github\.com[:/]([^/]+\/[^/]+)(\.git)?$/\1/' | sed 's/\.git$//')
else
    echo -e "${RED}错误: 不是 GitHub 仓库${NC}"
    exit 1
fi

# 检查 GitHub CLI 或 GitHub Token
GITHUB_TOKEN=""
if command -v gh &> /dev/null; then
    echo -e "${GREEN}使用 GitHub CLI (gh)${NC}"
    # 检查是否已登录
    if gh auth status &> /dev/null; then
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
    fi
fi

# 如果没有 GitHub CLI token，尝试从环境变量获取
if [[ -z "$GITHUB_TOKEN" ]]; then
    if [[ -n "$GITHUB_TOKEN" ]]; then
        GITHUB_TOKEN="$GITHUB_TOKEN"
    elif [[ -n "$GH_TOKEN" ]]; then
        GITHUB_TOKEN="$GH_TOKEN"
    fi
fi

# 如果还是没有 token，提示用户
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${YELLOW}警告: 未找到 GitHub Token${NC}"
    echo "请使用以下方式之一："
    echo "  1. 安装 GitHub CLI: brew install gh && gh auth login"
    echo "  2. 设置环境变量: export GITHUB_TOKEN=your_token"
    echo "  3. 设置环境变量: export GH_TOKEN=your_token"
    echo ""
    read -p "是否继续（将提示手动触发）? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    MANUAL_MODE=true
else
    MANUAL_MODE=false
fi

if [ "$USE_LATEST" = true ]; then
    echo -e "${BLUE}将使用最新的构建结果创建 Release${NC}"
    echo ""
else
    echo -e "${BLUE}查找版本号 <= ${VERSION} 的构建标签...${NC}"
    
    # 检查构建标签是否存在（仅提示，实际查找由工作流完成）
    BUILD_TAGS=(
        "build_client_macos_v${VERSION}"
        "build_client_windows_v${VERSION}"
        "build_server_android_v${VERSION}"
    )
    
    FOUND_TAGS=()
    for tag in "${BUILD_TAGS[@]}"; do
        if git rev-parse "$tag" >/dev/null 2>&1; then
            FOUND_TAGS+=("$tag")
        fi
    done
    
    if [ ${#FOUND_TAGS[@]} -eq 0 ]; then
        echo -e "${YELLOW}提示: 未找到精确版本 ${VERSION} 的构建标签${NC}"
        echo "Release 工作流将自动查找 <= ${VERSION} 的最大版本构建标签"
        echo ""
    fi
fi

# 触发 GitHub Actions Release 工作流
if [ "$MANUAL_MODE" = false ]; then
    echo -e "${BLUE}触发 GitHub Actions Release 工作流...${NC}"
    
    # 使用 GitHub CLI
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        echo "使用 GitHub CLI 触发工作流..."
        if [ "$USE_LATEST" = true ]; then
            # 无版本号：传递空字符串，让工作流使用最新构建
            WORKFLOW_RUN=$(gh workflow run "release.yml" \
                --ref main \
                2>&1)
        else
            WORKFLOW_RUN=$(gh workflow run "release.yml" \
                --ref main \
                --field version="$VERSION" \
                2>&1)
        fi
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Release 工作流已触发${NC}"
            echo ""
            echo "查看工作流运行: https://github.com/${REPO_PATH}/actions"
            echo ""
            
            # 等待一下，然后获取 run ID
            sleep 2
            RUN_ID=$(gh run list --workflow="release.yml" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")
            if [[ -n "$RUN_ID" ]]; then
                echo "工作流运行 ID: $RUN_ID"
                echo "查看详情: https://github.com/${REPO_PATH}/actions/runs/${RUN_ID}"
            fi
        else
            echo -e "${RED}错误: 触发工作流失败${NC}"
            echo "$WORKFLOW_RUN"
            exit 1
        fi
    else
        # 使用 GitHub API
        echo "使用 GitHub API 触发工作流..."
        
        # 使用工作流文件名（GitHub API 支持使用文件名）
        API_URL="https://api.github.com/repos/${REPO_PATH}/actions/workflows/release.yml/dispatches"
        
        # 构建请求体
        if [ "$USE_LATEST" = true ]; then
            # 无版本号：传递空字符串或省略 inputs
            REQUEST_BODY="{\"ref\":\"main\"}"
        else
            REQUEST_BODY="{\"ref\":\"main\",\"inputs\":{\"version\":\"${VERSION}\"}}"
        fi
        
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$REQUEST_BODY" \
            "$API_URL")
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | head -n-1)
        
        if [ "$HTTP_CODE" -eq 204 ]; then
            echo -e "${GREEN}✅ Release 工作流已触发${NC}"
            echo ""
            echo "查看工作流运行: https://github.com/${REPO_PATH}/actions"
        else
            echo -e "${RED}错误: 触发工作流失败 (HTTP $HTTP_CODE)${NC}"
            echo "$BODY"
            echo ""
            echo -e "${YELLOW}提示: 请检查 GitHub Token 权限或手动触发工作流${NC}"
            MANUAL_MODE=true
        fi
    fi
else
    echo -e "${YELLOW}手动触发模式${NC}"
    echo ""
    echo "请手动在 GitHub Actions 页面触发 'Create Release' 工作流："
    echo "  https://github.com/${REPO_PATH}/actions/workflows/release.yml"
    echo ""
    echo "输入参数："
    if [ "$USE_LATEST" = true ]; then
        echo "  version: （留空，使用最新构建结果）"
    else
        echo "  version: ${VERSION}"
    fi
    echo ""
fi

echo ""
echo -e "${GREEN}完成！${NC}"

