#!/bin/bash

# 创建 Release 脚本
# 使用方法: ./scripts/create_release.sh <version>
# 例如: ./scripts/create_release.sh 1.0.7
#
# 功能：
# 1. 检查 build 标签是否存在
# 2. 查找对应的构建流水线运行
# 3. 检查构建是否完成
# 4. 检查是否有构建结果
# 5. 触发 GitHub Actions release 工作流创建 Release

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 <version>"
    echo ""
    echo "创建 GitHub Release，重用已构建的产物"
    echo ""
    echo "参数:"
    echo "  version              版本号（如 1.0.7），必须提供"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 1.0.7              # 使用版本 1.0.7 的构建结果创建 Release"
    echo ""
    echo "说明:"
    echo "  - 脚本会检查 build{version} 标签是否存在（如 build1.0.7）"
    echo "  - 查找该标签对应的构建流水线运行"
    echo "  - 验证构建是否成功完成"
    echo "  - 验证是否有构建产物"
    echo "  - 然后触发 Release 工作流创建 Release"
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

# 检查版本号参数
if [ $# -eq 0 ]; then
    echo -e "${RED}错误: 必须提供版本号参数${NC}"
    echo ""
    show_help
    exit 1
fi

VERSION=$1

# 验证版本号格式 (x.y.z)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}错误: 版本号格式不正确，应为 x.y.z (例如: 1.0.7)${NC}"
    exit 1
fi

BUILD_TAG="build${VERSION}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}创建 Release: v${VERSION}${NC}"
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

# 如果还是没有 token，报错
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${RED}错误: 未找到 GitHub Token${NC}"
    echo "请使用以下方式之一："
    echo "  1. 安装 GitHub CLI: brew install gh && gh auth login"
    echo "  2. 设置环境变量: export GITHUB_TOKEN=your_token"
    echo "  3. 设置环境变量: export GH_TOKEN=your_token"
    exit 1
fi

echo -e "${BLUE}步骤 1: 检查构建标签是否存在...${NC}"

# 检查构建标签是否存在
if ! git rev-parse "$BUILD_TAG" >/dev/null 2>&1; then
    echo -e "${RED}错误: 构建标签 ${BUILD_TAG} 不存在${NC}"
    echo ""
    echo "请先创建构建标签："
    echo "  ./scripts/create_build_tags.sh"
    echo "或手动创建："
    echo "  git tag build${VERSION}"
    echo "  git push origin build${VERSION}"
    exit 1
fi

echo -e "${GREEN}✓ 构建标签 ${BUILD_TAG} 存在${NC}"
echo ""

# 获取标签对应的 commit SHA
TAG_COMMIT=$(git rev-parse "$BUILD_TAG")
echo -e "${BLUE}标签 ${BUILD_TAG} 对应的提交: ${TAG_COMMIT:0:7}${NC}"
echo ""

echo -e "${BLUE}步骤 2: 查找构建流水线运行...${NC}"

# 使用 GitHub API 查找构建工作流运行
# 查找总构建工作流 (build.yml)
MAIN_WORKFLOW_RUN_ID=""
MAIN_WORKFLOW_STATUS=""
MAIN_WORKFLOW_CONCLUSION=""

# 使用 GitHub API 查找
page=1
found=false
while [ $page -le 5 ] && [ "$found" = false ]; do
    RESPONSE=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO_PATH}/actions/workflows/build.yml/runs?per_page=30&page=${page}")
    
    # 解析 JSON，查找匹配的 commit SHA
    RUNS=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data.get('workflow_runs', [])
    for run in runs:
        if run.get('head_sha') == '${TAG_COMMIT}':
            print(f\"{run['id']}|{run['status']}|{run.get('conclusion', '')}\")
            sys.exit(0)
except:
    pass
" 2>/dev/null || echo "")
    
    if [[ -n "$RUNS" ]]; then
        MAIN_WORKFLOW_RUN_ID=$(echo "$RUNS" | cut -d'|' -f1)
        MAIN_WORKFLOW_STATUS=$(echo "$RUNS" | cut -d'|' -f2)
        MAIN_WORKFLOW_CONCLUSION=$(echo "$RUNS" | cut -d'|' -f3)
        found=true
    else
        page=$((page + 1))
    fi
done

if [[ -z "$MAIN_WORKFLOW_RUN_ID" ]]; then
    echo -e "${RED}错误: 未找到标签 ${BUILD_TAG} 对应的构建工作流运行${NC}"
    echo ""
    echo "请检查："
    echo "  1. 构建标签是否已推送到远程"
    echo "  2. 构建工作流是否已触发"
    echo "  3. 查看构建状态: https://github.com/${REPO_PATH}/actions"
    exit 1
fi

echo -e "${GREEN}✓ 找到构建工作流运行 ID: ${MAIN_WORKFLOW_RUN_ID}${NC}"
echo "  状态: ${MAIN_WORKFLOW_STATUS}"
echo "  结论: ${MAIN_WORKFLOW_CONCLUSION:-未完成}"
echo ""

echo -e "${BLUE}步骤 3: 检查构建状态...${NC}"

# 检查构建是否完成
if [ "$MAIN_WORKFLOW_STATUS" != "completed" ]; then
    echo -e "${YELLOW}警告: 构建工作流尚未完成（当前状态: ${MAIN_WORKFLOW_STATUS}）${NC}"
    echo ""
    echo "请等待构建完成后再创建 Release"
    echo "查看构建进度: https://github.com/${REPO_PATH}/actions/runs/${MAIN_WORKFLOW_RUN_ID}"
    exit 1
fi

# 检查构建是否成功
if [ "$MAIN_WORKFLOW_CONCLUSION" != "success" ]; then
    echo -e "${RED}错误: 构建工作流未成功完成（结论: ${MAIN_WORKFLOW_CONCLUSION}）${NC}"
    echo ""
    echo "请检查构建日志并修复问题："
    echo "  https://github.com/${REPO_PATH}/actions/runs/${MAIN_WORKFLOW_RUN_ID}"
    exit 1
fi

echo -e "${GREEN}✓ 构建工作流已完成且成功${NC}"
echo ""

echo -e "${BLUE}步骤 4: 检查子工作流构建状态...${NC}"

# 检查三个子工作流的运行状态
WORKFLOW_FILES=(
    "build-client-macos.yml|macos"
    "build-client-windows.yml|windows"
    "build-server-android.yml|android"
)

ALL_BUILDS_SUCCESS=true
WORKFLOW_RUN_IDS=()

for workflow_info in "${WORKFLOW_FILES[@]}"; do
    IFS='|' read -r workflow_file platform <<< "$workflow_info"
    
    # 查找该工作流的运行
    page=1
    found=false
    run_id=""
    status=""
    conclusion=""
    
    while [ $page -le 5 ] && [ "$found" = false ]; do
        RESPONSE=$(curl -s \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${REPO_PATH}/actions/workflows/${workflow_file}/runs?per_page=30&page=${page}")
        
        RUN_INFO=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data.get('workflow_runs', [])
    for run in runs:
        if run.get('head_sha') == '${TAG_COMMIT}':
            print(f\"{run['id']}|{run['status']}|{run.get('conclusion', '')}\")
            sys.exit(0)
except:
    pass
" 2>/dev/null || echo "")
        
        if [[ -n "$RUN_INFO" ]]; then
            run_id=$(echo "$RUN_INFO" | cut -d'|' -f1)
            status=$(echo "$RUN_INFO" | cut -d'|' -f2)
            conclusion=$(echo "$RUN_INFO" | cut -d'|' -f3)
            found=true
        else
            page=$((page + 1))
        fi
    done
    
    if [[ -z "$run_id" ]]; then
        echo -e "${RED}✗ ${platform}: 未找到构建运行${NC}"
        ALL_BUILDS_SUCCESS=false
    elif [ "$status" != "completed" ]; then
        echo -e "${YELLOW}⚠ ${platform}: 构建尚未完成（状态: ${status}）${NC}"
        ALL_BUILDS_SUCCESS=false
    elif [ "$conclusion" != "success" ]; then
        echo -e "${RED}✗ ${platform}: 构建失败（结论: ${conclusion}）${NC}"
        ALL_BUILDS_SUCCESS=false
    else
        echo -e "${GREEN}✓ ${platform}: 构建成功（运行 ID: ${run_id}）${NC}"
        WORKFLOW_RUN_IDS+=("${platform}:${run_id}")
    fi
done

echo ""

if [ "$ALL_BUILDS_SUCCESS" = false ]; then
    echo -e "${RED}错误: 部分平台构建未成功完成${NC}"
    echo ""
    echo "请检查构建日志并修复问题："
    echo "  https://github.com/${REPO_PATH}/actions"
    exit 1
fi

echo -e "${BLUE}步骤 5: 检查构建产物...${NC}"

# 检查每个平台的构建产物是否存在
# 通过检查 artifacts 来验证
ARTIFACTS_FOUND=true

for workflow_info in "${WORKFLOW_FILES[@]}"; do
    IFS='|' read -r workflow_file platform <<< "$workflow_info"
    
    # 从 WORKFLOW_RUN_IDS 中获取对应的 run_id
    run_id=""
    for run_info in "${WORKFLOW_RUN_IDS[@]}"; do
        if [[ "$run_info" == "${platform}:"* ]]; then
            run_id="${run_info#${platform}:}"
            break
        fi
    done
    
    if [[ -z "$run_id" ]]; then
        echo -e "${RED}✗ ${platform}: 未找到运行 ID${NC}"
        ARTIFACTS_FOUND=false
        continue
    fi
    
    # 检查 artifacts
    ARTIFACTS_RESPONSE=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO_PATH}/actions/runs/${run_id}/artifacts")
    
    ARTIFACTS_COUNT=$(echo "$ARTIFACTS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    artifacts = data.get('artifacts', [])
    print(len(artifacts))
except:
    print(0)
" 2>/dev/null || echo "0")
    
    if [ "$ARTIFACTS_COUNT" -eq 0 ]; then
        echo -e "${RED}✗ ${platform}: 未找到构建产物${NC}"
        ARTIFACTS_FOUND=false
    else
        echo -e "${GREEN}✓ ${platform}: 找到 ${ARTIFACTS_COUNT} 个构建产物${NC}"
    fi
done

echo ""

if [ "$ARTIFACTS_FOUND" = false ]; then
    echo -e "${RED}错误: 部分平台缺少构建产物${NC}"
    echo ""
    echo "请检查构建日志："
    echo "  https://github.com/${REPO_PATH}/actions"
    exit 1
fi

echo -e "${GREEN}✓ 所有构建产物检查通过${NC}"
echo ""

echo -e "${BLUE}步骤 6: 触发 Release 工作流...${NC}"

# 触发 GitHub Actions Release 工作流
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "使用 GitHub CLI 触发工作流..."
    WORKFLOW_RUN=$(gh workflow run "release.yml" \
        --ref main \
        --field version="$VERSION" \
        2>&1)
    
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
    
    API_URL="https://api.github.com/repos/${REPO_PATH}/actions/workflows/release.yml/dispatches"
    
    REQUEST_BODY="{\"ref\":\"main\",\"inputs\":{\"version\":\"${VERSION}\"}}"
    
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
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}完成！${NC}"
