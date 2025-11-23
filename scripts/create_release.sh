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
    show_help
    exit 0
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

# 获取标签对应的 commit SHA（使用^{}来获取标签指向的提交，而不是标签对象本身）
TAG_COMMIT=$(git rev-parse "$BUILD_TAG^{}" 2>/dev/null || git rev-parse "$BUILD_TAG")
echo -e "${BLUE}标签 ${BUILD_TAG} 对应的提交: ${TAG_COMMIT:0:7}${NC}"
echo ""

echo -e "${BLUE}步骤 2: 查找构建流水线运行...${NC}"
echo "  查找标签: ${BUILD_TAG}"
echo "  提交 SHA: ${TAG_COMMIT}"
echo "  仓库路径: ${REPO_PATH}"
echo ""

# 使用 GitHub API 查找构建工作流运行
# 查找总构建工作流 (build.yml)
MAIN_WORKFLOW_RUN_ID=""
MAIN_WORKFLOW_STATUS=""
MAIN_WORKFLOW_CONCLUSION=""

# 使用 GitHub API 查找
page=1
found=false
while [ $page -le 5 ] && [ "$found" = false ]; do
    API_URL="https://api.github.com/repos/${REPO_PATH}/actions/workflows/build.yml/runs?per_page=30&page=${page}"
    echo "  [调试] 查询第 ${page} 页: ${API_URL}"
    
    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$API_URL")
    
    HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
    RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')
    
    echo "  [调试] HTTP 状态码: ${HTTP_CODE}"
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo -e "${RED}  [错误] API 请求失败，HTTP 状态码: ${HTTP_CODE}${NC}"
        echo "  [调试] 响应内容:"
        echo "$RESPONSE" | head -n 20
        echo ""
        if [ $page -eq 1 ]; then
            echo -e "${RED}错误: 无法访问 GitHub API${NC}"
            exit 1
        fi
        break
    fi
    
    # 解析 JSON，查找匹配的 commit SHA
    RUNS=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    total_count = data.get('total_count', 0)
    runs = data.get('workflow_runs', [])
    print(f'[调试] 找到 {len(runs)} 个工作流运行（总计: {total_count}）', file=sys.stderr)
    for i, run in enumerate(runs):
        run_sha = run.get('head_sha', '')
        run_id = run.get('id', '')
        run_status = run.get('status', '')
        run_conclusion = run.get('conclusion', '')
        print(f'[调试] 运行 #{i+1}: ID={run_id}, SHA={run_sha[:7]}, 状态={run_status}, 结论={run_conclusion}', file=sys.stderr)
        if run_sha == '${TAG_COMMIT}':
            print(f\"{run['id']}|{run['status']}|{run.get('conclusion', '')}\")
            sys.exit(0)
except Exception as e:
    print(f'[错误] JSON 解析失败: {e}', file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
" 2>&1)
    
    MATCHED_RUN=$(echo "$RUNS" | grep -E "^[0-9]+\|" || echo "")
    DEBUG_OUTPUT=$(echo "$RUNS" | grep -E "^\[" || echo "")
    
    if [[ -n "$DEBUG_OUTPUT" ]]; then
        echo "$DEBUG_OUTPUT"
    fi
    
    if [[ -n "$MATCHED_RUN" ]]; then
        MAIN_WORKFLOW_RUN_ID=$(echo "$MATCHED_RUN" | cut -d'|' -f1)
        MAIN_WORKFLOW_STATUS=$(echo "$MATCHED_RUN" | cut -d'|' -f2)
        MAIN_WORKFLOW_CONCLUSION=$(echo "$MATCHED_RUN" | cut -d'|' -f3)
        found=true
        echo "  [调试] ✓ 找到匹配的工作流运行: ID=${MAIN_WORKFLOW_RUN_ID}"
    else
        echo "  [调试] 第 ${page} 页未找到匹配的运行，继续查找..."
        page=$((page + 1))
    fi
    echo ""
done

if [[ -z "$MAIN_WORKFLOW_RUN_ID" ]]; then
    echo -e "${RED}错误: 未找到标签 ${BUILD_TAG} 对应的构建工作流运行${NC}"
    echo ""
    echo "调试信息："
    echo "  - 查找的标签: ${BUILD_TAG}"
    echo "  - 标签对应的提交 SHA: ${TAG_COMMIT}"
    echo "  - 已搜索 ${page} 页"
    echo ""
    echo "请检查："
    echo "  1. 构建标签是否已推送到远程: git push origin ${BUILD_TAG}"
    echo "  2. 构建工作流是否已触发"
    echo "  3. 查看构建状态: https://github.com/${REPO_PATH}/actions"
    echo "  4. 确认工作流文件名称是否为 build.yml"
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
echo "  从主工作流运行中获取子工作流信息..."
echo "  主工作流运行 ID: ${MAIN_WORKFLOW_RUN_ID}"
echo ""

# 从主工作流运行中获取所有作业（jobs）
API_URL="https://api.github.com/repos/${REPO_PATH}/actions/runs/${MAIN_WORKFLOW_RUN_ID}/jobs"
echo "  [调试] 查询主工作流的作业: ${API_URL}"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL")

HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
JOBS_RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')

echo "  [调试] HTTP 状态码: ${HTTP_CODE}"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}错误: 无法获取主工作流的作业信息 (HTTP ${HTTP_CODE})${NC}"
    echo "  [调试] 响应内容:"
    echo "$JOBS_RESPONSE" | head -n 10
    exit 1
fi

# 解析作业信息，查找三个平台的构建作业
JOBS_INFO=$(echo "$JOBS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    print(f'  [调试] 找到 {len(jobs)} 个作业', file=sys.stderr)
    
    # 定义平台名称映射（使用更灵活的匹配）
    platform_keywords = {
        'macos': ['macos', 'client-macos'],
        'windows': ['windows', 'client-windows'],
        'android': ['android', 'server-android']
    }
    
    results = {}
    for job in jobs:
        job_name = job.get('name', '').lower()
        job_id = job.get('id', '')
        job_status = job.get('status', '')
        job_conclusion = job.get('conclusion', '')
        
        print(f'  [调试] 作业: {job.get(\"name\", \"\")}, ID={job_id}, 状态={job_status}, 结论={job_conclusion}', file=sys.stderr)
        
        # 查找匹配的平台
        for platform, keywords in platform_keywords.items():
            if any(keyword in job_name for keyword in keywords):
                results[platform] = f\"{job_id}|{job_status}|{job_conclusion}\"
                print(f'  [调试] 匹配到平台: {platform}', file=sys.stderr)
                break
    
    # 输出结果
    for platform in ['macos', 'windows', 'android']:
        if platform in results:
            print(f'{platform}:{results[platform]}')
        else:
            print(f'{platform}:NOT_FOUND')
            
except Exception as e:
    print(f'  [错误] JSON 解析失败: {e}', file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
" 2>&1)

ALL_BUILDS_SUCCESS=true
WORKFLOW_RUN_IDS=()

# 解析每个平台的结果
for platform in macos windows android; do
    PLATFORM_INFO=$(echo "$JOBS_INFO" | grep "^${platform}:" | cut -d: -f2-)
    
    if [[ -z "$PLATFORM_INFO" ]] || [[ "$PLATFORM_INFO" == "NOT_FOUND" ]]; then
        echo -e "${RED}✗ ${platform}: 未找到构建作业${NC}"
        ALL_BUILDS_SUCCESS=false
        continue
    fi
    
    job_id=$(echo "$PLATFORM_INFO" | cut -d'|' -f1)
    status=$(echo "$PLATFORM_INFO" | cut -d'|' -f2)
    conclusion=$(echo "$PLATFORM_INFO" | cut -d'|' -f3)
    
    echo "  [调试] ${platform}: 作业 ID=${job_id}, 状态=${status}, 结论=${conclusion}"
    
    if [ "$status" != "completed" ]; then
        echo -e "${YELLOW}⚠ ${platform}: 构建尚未完成（状态: ${status}）${NC}"
        ALL_BUILDS_SUCCESS=false
    elif [ "$conclusion" != "success" ]; then
        echo -e "${RED}✗ ${platform}: 构建失败（结论: ${conclusion}）${NC}"
        ALL_BUILDS_SUCCESS=false
    else
        echo -e "${GREEN}✓ ${platform}: 构建成功（作业 ID: ${job_id}）${NC}"
        # 注意：这里存储的是作业ID，不是运行ID，但用于获取artifacts时需要使用运行ID
        # 我们需要从作业中获取运行ID
        WORKFLOW_RUN_IDS+=("${platform}:${MAIN_WORKFLOW_RUN_ID}")
    fi
    echo ""
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
echo "  从主工作流运行中获取所有构建产物..."
echo "  主工作流运行 ID: ${MAIN_WORKFLOW_RUN_ID}"
echo ""

# 从主工作流运行中获取所有 artifacts
API_URL="https://api.github.com/repos/${REPO_PATH}/actions/runs/${MAIN_WORKFLOW_RUN_ID}/artifacts"
echo "  [调试] 查询构建产物: ${API_URL}"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL")

HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
ARTIFACTS_RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')

echo "  [调试] HTTP 状态码: ${HTTP_CODE}"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}错误: 无法获取构建产物信息 (HTTP ${HTTP_CODE})${NC}"
    echo "  [调试] 响应内容:"
    echo "$ARTIFACTS_RESPONSE" | head -n 10
    exit 1
fi

# 解析所有artifacts，按平台分类
ARTIFACTS_INFO=$(echo "$ARTIFACTS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    artifacts = data.get('artifacts', [])
    print(f'  [调试] 找到 {len(artifacts)} 个构建产物', file=sys.stderr)
    
    # 定义平台名称映射
    platform_map = {
        'macos': ['macos', 'client-macos'],
        'windows': ['windows', 'client-windows'],
        'android': ['android', 'server-android']
    }
    
    results = {platform: [] for platform in platform_map.keys()}
    
    for artifact in artifacts:
        name = artifact.get('name', '').lower()
        size = artifact.get('size_in_bytes', 0)
        print(f'  [调试] 产物: {artifact.get(\"name\", \"\")} ({size} bytes)', file=sys.stderr)
        
        # 查找匹配的平台
        for platform, keywords in platform_map.items():
            if any(keyword in name for keyword in keywords):
                results[platform].append(artifact.get('name', ''))
                break
    
    # 输出结果
    for platform in ['macos', 'windows', 'android']:
        count = len(results[platform])
        artifacts_list = ','.join(results[platform])
        print(f'{platform}:{count}:{artifacts_list}')
        
except Exception as e:
    print(f'  [错误] JSON 解析失败: {e}', file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
" 2>&1)

ARTIFACTS_FOUND=true

# 检查每个平台的artifacts
for platform in macos windows android; do
    PLATFORM_INFO=$(echo "$ARTIFACTS_INFO" | grep "^${platform}:" | cut -d: -f2-)
    
    if [[ -z "$PLATFORM_INFO" ]]; then
        echo -e "${RED}✗ ${platform}: 无法解析构建产物信息${NC}"
        ARTIFACTS_FOUND=false
        continue
    fi
    
    count=$(echo "$PLATFORM_INFO" | cut -d: -f1)
    artifacts_list=$(echo "$PLATFORM_INFO" | cut -d: -f2-)
    
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}✗ ${platform}: 未找到构建产物${NC}"
        ARTIFACTS_FOUND=false
    else
        echo -e "${GREEN}✓ ${platform}: 找到 ${count} 个构建产物${NC}"
        if [[ -n "$artifacts_list" ]]; then
            echo "    [调试] 产物名称: $artifacts_list"
        fi
    fi
    echo ""
done

echo ""

if [ "$ARTIFACTS_FOUND" = false ]; then
    echo -e "${RED}错误: 部分平台缺少构建产物${NC}"
    echo ""
    echo "调试信息："
    echo "  - 已检查的工作流运行:"
    for run_info in "${WORKFLOW_RUN_IDS[@]}"; do
        echo "    - ${run_info}"
    done
    echo ""
    echo "请检查构建日志："
    echo "  https://github.com/${REPO_PATH}/actions"
    exit 1
fi

echo -e "${GREEN}✓ 所有构建产物检查通过${NC}"
echo ""

echo -e "${BLUE}步骤 6: 触发 Release 工作流...${NC}"
echo "  版本号: ${VERSION}"
echo "  仓库路径: ${REPO_PATH}"
echo ""

# 触发 GitHub Actions Release 工作流
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "  [调试] 使用 GitHub CLI 触发工作流..."
    echo "  [调试] 命令: gh workflow run \"release.yml\" --ref main --field version=\"${VERSION}\""
    
    WORKFLOW_RUN=$(gh workflow run "release.yml" \
        --ref main \
        --field version="$VERSION" \
        2>&1)
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Release 工作流已触发${NC}"
        echo ""
        echo "查看工作流运行: https://github.com/${REPO_PATH}/actions"
        echo ""
        
        # 等待一下，然后获取 run ID
        echo "  [调试] 等待工作流启动..."
        sleep 2
        RUN_ID=$(gh run list --workflow="release.yml" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")
        if [[ -n "$RUN_ID" ]]; then
            echo "  [调试] 工作流运行 ID: $RUN_ID"
            echo "查看详情: https://github.com/${REPO_PATH}/actions/runs/${RUN_ID}"
        else
            echo "  [调试] 无法获取运行 ID，请手动查看: https://github.com/${REPO_PATH}/actions"
        fi
    else
        echo -e "${RED}错误: 触发工作流失败 (退出码: $EXIT_CODE)${NC}"
        echo "  [调试] 错误输出:"
        echo "$WORKFLOW_RUN"
        exit 1
    fi
else
    # 使用 GitHub API
    echo "  [调试] 使用 GitHub API 触发工作流..."
    
    API_URL="https://api.github.com/repos/${REPO_PATH}/actions/workflows/release.yml/dispatches"
    REQUEST_BODY="{\"ref\":\"main\",\"inputs\":{\"version\":\"${VERSION}\"}}"
    
    echo "  [调试] API URL: ${API_URL}"
    echo "  [调试] 请求体: ${REQUEST_BODY}"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$REQUEST_BODY" \
        "$API_URL")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    echo "  [调试] HTTP 状态码: ${HTTP_CODE}"
    
    if [ "$HTTP_CODE" -eq 204 ]; then
        echo -e "${GREEN}✅ Release 工作流已触发${NC}"
        echo ""
        echo "查看工作流运行: https://github.com/${REPO_PATH}/actions"
    else
        echo -e "${RED}错误: 触发工作流失败 (HTTP $HTTP_CODE)${NC}"
        echo "  [调试] 响应内容:"
        echo "$BODY"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}完成！${NC}"
