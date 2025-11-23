#!/bin/bash

# Gitee 同步脚本
# 使用方法: ./scripts/sync_to_gitee.sh [version]
# 例如: ./scripts/sync_to_gitee.sh 1.0.7
# 或者: ./scripts/sync_to_gitee.sh  # 使用最新 Release
#
# 功能：
# 1. 从 GitHub Release 下载构建产物
# 2. 同步到 Gitee Release
# 3. 上传构建产物到 Gitee
# 4. 同步更新配置文件

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [version]"
    echo ""
    echo "将 GitHub Release 同步到 Gitee"
    echo ""
    echo "参数:"
    echo "  version              版本号（如 1.0.7），可选。留空则使用最新 Release"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "配置文件:"
    echo "  脚本会从 gitee_config.yaml 读取配置"
    echo "  如果文件不存在，请创建配置文件并填写实际配置"
    echo ""
    echo "示例:"
    echo "  $0 1.0.7              # 同步版本 1.0.7 的 Release"
    echo "  $0                     # 同步最新 Release"
    echo ""
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

# 读取 YAML 配置文件
load_config() {
    local config_file="gitee_config.yaml"
    
    echo -e "${BLUE}🔍 读取配置文件...${NC}"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ 配置文件不存在: ${config_file}${NC}"
        echo ""
        echo "请创建配置文件 ${config_file} 并填写实际配置"
        echo ""
        echo "配置文件格式示例:"
        echo "  gitee:"
        echo "    token: \"your_gitee_token\""
        echo "    repo_owner: \"your_username\""
        echo "    repo_name: \"your_repo_name\""
        echo "  github:"
        echo "    token: \"your_github_token\"  # 可选"
        echo "    repo_owner: \"your_username\"  # 可选"
        echo "    repo_name: \"your_repo_name\"  # 可选"
        echo ""
        exit 1
    fi
    
    # 检查是否安装了 PyYAML
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "  安装 PyYAML..."
        python3 -m pip install --user pyyaml --quiet || \
        python3 -m pip install pyyaml --quiet || {
            echo -e "${RED}❌ 无法安装 PyYAML，请手动安装: pip install pyyaml${NC}"
            exit 1
        }
    fi
    
    # 使用 Python 读取 YAML 配置
    local python_script='
import yaml
import sys
import os

try:
    with open("gitee_config.yaml", "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)
    
    # 读取 Gitee 配置
    gitee = config.get("gitee", {})
    gitee_token = gitee.get("token", "").strip()
    gitee_repo_owner = gitee.get("repo_owner", "").strip()
    gitee_repo_name = gitee.get("repo_name", "").strip()
    
    # 读取 GitHub 配置（可选）
    github = config.get("github", {})
    github_token = github.get("token", "").strip()
    github_repo_owner = github.get("repo_owner", "").strip()
    github_repo_name = github.get("repo_name", "").strip()
    
    # 检查 token 是否是占位符
    if github_token in ["your_github_token_here", ""]:
        github_token = ""
    
    # 如果 GitHub 配置未设置，使用 Gitee 的值
    if not github_repo_owner or github_repo_owner in ["your_github_username", ""]:
        github_repo_owner = gitee_repo_owner
    if not github_repo_name or github_repo_name in ["your_repo_name", ""]:
        github_repo_name = gitee_repo_name
    
    # 验证必需配置
    if not gitee_token:
        print("ERROR: gitee.token 未设置", file=sys.stderr)
        sys.exit(1)
    if not gitee_repo_owner:
        print("ERROR: gitee.repo_owner 未设置", file=sys.stderr)
        sys.exit(1)
    if not gitee_repo_name:
        print("ERROR: gitee.repo_name 未设置", file=sys.stderr)
        sys.exit(1)
    
    # 输出配置（使用特殊分隔符，避免值中包含空格或特殊字符）
    print(f"GITEE_TOKEN={gitee_token}")
    print(f"GITEE_REPO_OWNER={gitee_repo_owner}")
    print(f"GITEE_REPO_NAME={gitee_repo_name}")
    print(f"GITHUB_TOKEN={github_token}")
    print(f"GITHUB_REPO_OWNER={github_repo_owner}")
    print(f"GITHUB_REPO_NAME={github_repo_name}")
    
except FileNotFoundError:
    print("ERROR: 配置文件不存在", file=sys.stderr)
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"ERROR: YAML 解析失败: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: 读取配置失败: {e}", file=sys.stderr)
    sys.exit(1)
'
    
    # 执行 Python 脚本并读取输出
    local config_output
    config_output=$(python3 -c "$python_script" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}❌ 读取配置文件失败${NC}"
        echo "$config_output"
        exit 1
    fi
    
    # 解析配置输出
    while IFS='=' read -r key value; do
        case "$key" in
            GITEE_TOKEN)
                GITEE_TOKEN="$value"
                ;;
            GITEE_REPO_OWNER)
                GITEE_REPO_OWNER="$value"
                ;;
            GITEE_REPO_NAME)
                GITEE_REPO_NAME="$value"
                ;;
            GITHUB_TOKEN)
                GITHUB_TOKEN="$value"
                ;;
            GITHUB_REPO_OWNER)
                GITHUB_REPO_OWNER="$value"
                ;;
            GITHUB_REPO_NAME)
                GITHUB_REPO_NAME="$value"
                ;;
        esac
    done <<< "$config_output"
    
    # 清理并去除换行符、回车符和前后空格
    GITEE_TOKEN=$(printf '%s' "${GITEE_TOKEN}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    GITEE_REPO_OWNER=$(printf '%s' "${GITEE_REPO_OWNER}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    GITEE_REPO_NAME=$(printf '%s' "${GITEE_REPO_NAME}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    GITHUB_TOKEN=$(printf '%s' "${GITHUB_TOKEN}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    GITHUB_REPO_OWNER=$(printf '%s' "${GITHUB_REPO_OWNER}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    GITHUB_REPO_NAME=$(printf '%s' "${GITHUB_REPO_NAME}" | tr -d '\n\r\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    GITEE_REPO="${GITEE_REPO_OWNER}/${GITEE_REPO_NAME}"
    GITHUB_REPO="${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}"
    
    echo -e "${GREEN}✅ 配置文件读取成功${NC}"
    echo "  Gitee 仓库: ${GITEE_REPO}"
    echo "  GitHub 仓库: ${GITHUB_REPO}"
    if [ -n "$GITHUB_TOKEN" ] && [ "$GITHUB_TOKEN" != "your_github_token_here" ]; then
        echo "  GitHub Token: 已设置"
    else
        echo "  GitHub Token: 未设置（将使用公开 API）"
        GITHUB_TOKEN=""  # 确保占位符被视为未设置
    fi
    echo ""
}

# 检查配置（保持函数名兼容，实际调用 load_config）
check_env() {
    load_config
    
    # 创建临时目录
    TEMP_DIR="temp"
    mkdir -p "${TEMP_DIR}"
    echo "📁 临时目录: $(realpath ${TEMP_DIR})"
    echo ""
}

# 提取 Release 标签
extract_release_tag() {
    local input_version="$1"
    
    echo -e "${BLUE}🔍 提取 Release 标签...${NC}"
    
    if [ -n "$input_version" ] && [ "$input_version" != "" ]; then
        # 如果版本号没有 v 前缀，添加 v 前缀
        if [[ ! "$input_version" =~ ^v ]]; then
            TAG_NAME="v${input_version}"
        else
            TAG_NAME="${input_version}"
        fi
        echo -e "${GREEN}✅ 使用指定版本号: ${input_version}，转换为标签 ${TAG_NAME}${NC}"
    else
        # 从 GitHub API 获取最新 Release
        echo "📡 未提供版本号，从 GitHub API 获取最新 Release..."
        
        if [ -z "$GITHUB_TOKEN" ]; then
            echo -e "${YELLOW}⚠️  GITHUB_TOKEN 未设置，尝试使用公开 API...${NC}"
            TAG_NAME=$(curl -s \
                "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | \
                jq -r '.tag_name // empty')
        else
            TAG_NAME=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | \
                jq -r '.tag_name // empty')
        fi
        
        if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" == "null" ] || [ "$TAG_NAME" == "" ]; then
            echo -e "${RED}❌ 无法从 GitHub API 获取最新 Release 标签${NC}"
            echo "  请手动指定版本号参数，或确保仓库中至少有一个已发布的 Release"
            exit 1
        fi
        
        echo -e "${GREEN}✅ 获取到最新 Release 标签: ${TAG_NAME}${NC}"
    fi
    
    echo ""
}

# 获取 Release 信息
get_release_info() {
    echo -e "${BLUE}🔍 获取 Release 信息...${NC}"
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${YELLOW}⚠️  GITHUB_TOKEN 未设置，使用公开 API...${NC}"
        echo "  请求 URL: https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${TAG_NAME}"
        echo "  正在请求 GitHub API..."
        RELEASE_INFO=$(curl -s --max-time 30 --connect-timeout 10 \
            "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${TAG_NAME}" 2>&1)
        CURL_EXIT_CODE=$?
    else
        echo "  正在请求 GitHub API..."
        RELEASE_INFO=$(curl -s --max-time 30 --connect-timeout 10 \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${TAG_NAME}" 2>&1)
        CURL_EXIT_CODE=$?
    fi
    
    echo "  curl 退出码: ${CURL_EXIT_CODE}"
    
    # 检查 curl 是否成功
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}❌ 网络请求失败 (curl 退出码: ${CURL_EXIT_CODE})${NC}"
        echo "  请检查网络连接或 GitHub API 是否可访问"
        exit 1
    fi
    
    # 检查是否获取成功
    if ! echo "$RELEASE_INFO" | jq -e '.id' > /dev/null 2>&1; then
        echo -e "${RED}❌ 无法获取 Release 信息${NC}"
        echo "  响应: $RELEASE_INFO"
        echo "  请检查 Release 标签 ${TAG_NAME} 是否存在"
        exit 1
    fi
    
    RELEASE_NAME=$(echo "$RELEASE_INFO" | jq -r '.name // .tag_name')
    RELEASE_BODY=$(echo "$RELEASE_INFO" | jq -r '.body // ""')
    RELEASE_ID=$(echo "$RELEASE_INFO" | jq -r '.id')
    
    echo -e "${GREEN}✅ Release 信息获取成功${NC}"
    echo "  ID: ${RELEASE_ID}"
    echo "  名称: ${RELEASE_NAME}"
    echo "  标签: ${TAG_NAME}"
    echo ""
}

# 下载构建产物
download_assets() {
    # 检查是否需要跳过下载
    if [ "${SKIP_DOWNLOAD_ASSETS:-false}" = "true" ]; then
        echo -e "${GREEN}✅ 跳过下载构建产物（hash 已匹配）${NC}"
        echo ""
        echo "📋 使用已下载的 hash 文件..."
        RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
        mkdir -p "${RELEASE_ASSETS_DIR}"
        
        # 确保 hash 文件存在（应该已经在 check_hashes_before_download 中复制了）
        if [ ! -f "${RELEASE_ASSETS_DIR}/file_hashes.json" ]; then
            echo -e "${YELLOW}⚠️  Hash 文件不存在，需要重新下载${NC}"
            export SKIP_DOWNLOAD_ASSETS=false
        else
            echo "✅ Hash 文件已就绪"
            return 0
        fi
    fi
    
    echo -e "${BLUE}📥 下载构建产物文件...${NC}"
    
    RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
    
    # 清空下载目录（如果存在）
    if [ -d "${RELEASE_ASSETS_DIR}" ]; then
        echo "  清空下载目录: ${RELEASE_ASSETS_DIR}"
        rm -rf "${RELEASE_ASSETS_DIR}"/*
        rm -rf "${RELEASE_ASSETS_DIR}"/.* 2>/dev/null || true  # 删除隐藏文件，忽略错误
    fi
    
    # 创建下载目录
    mkdir -p "${RELEASE_ASSETS_DIR}"
    echo "  目标目录: $(realpath ${RELEASE_ASSETS_DIR})"
    
    # 使用 GitHub CLI 下载文件（如果可用）
    if command -v gh &> /dev/null && [ -n "$GITHUB_TOKEN" ]; then
        echo "  使用 GitHub CLI 下载文件..."
        export GH_TOKEN="$GITHUB_TOKEN"
        gh release download "${TAG_NAME}" -D "${RELEASE_ASSETS_DIR}" -R "${GITHUB_REPO}" || {
            echo -e "${YELLOW}⚠️  GitHub CLI 下载失败，尝试使用 curl...${NC}"
            download_with_curl
        }
    else
        download_with_curl
    fi
    
    echo ""
    echo "📋 已下载的文件列表:"
    ls -lh "${RELEASE_ASSETS_DIR}/" || echo "  目录为空或不存在"
    
    FILE_COUNT=$(find "${RELEASE_ASSETS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
    TOTAL_SIZE=$(du -sh "${RELEASE_ASSETS_DIR}" 2>/dev/null | cut -f1 || echo "0")
    echo ""
    echo "  文件数量: ${FILE_COUNT}"
    echo "  总大小: ${TOTAL_SIZE}"
    echo ""
    
    # 计算文件 hash
    echo ""
    echo -e "${BLUE}📋 计算文件 hash...${NC}"
    python3 scripts/calculate_file_hashes.py \
      --input-dir "${RELEASE_ASSETS_DIR}" \
      --output "${RELEASE_ASSETS_DIR}/file_hashes.json" \
      --base-name-only
    
    if [ -f "${RELEASE_ASSETS_DIR}/file_hashes.json" ]; then
        echo -e "${GREEN}✅ 文件 hash 列表已生成${NC}"
        echo "文件内容:"
        cat "${RELEASE_ASSETS_DIR}/file_hashes.json"
        echo ""
    else
        echo -e "${YELLOW}⚠️  文件 hash 列表生成失败，将使用默认方式计算 hash${NC}"
    fi
    echo ""
}

# 使用 curl 下载文件
download_with_curl() {
    echo "  使用 curl 手动下载文件..."
    
    RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
    ASSETS=$(echo "$RELEASE_INFO" | jq -r '.assets[] | "\(.browser_download_url)|\(.name)"')
    
    DOWNLOAD_SUCCESS=0
    DOWNLOAD_FAILED=0
    
    echo "$ASSETS" | while IFS='|' read -r url name; do
        if [ -n "$url" ] && [ -n "$name" ]; then
            echo "  📦 下载 ${name}..."
            
            if [ -n "$GITHUB_TOKEN" ]; then
                HTTP_CODE=$(curl -s -w "%{http_code}" -L \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -o "${RELEASE_ASSETS_DIR}/${name}" \
                    "${url}" | tail -n1)
            else
                HTTP_CODE=$(curl -s -w "%{http_code}" -L \
                    -o "${RELEASE_ASSETS_DIR}/${name}" \
                    "${url}" | tail -n1)
            fi
            
            if [ "$HTTP_CODE" = "200" ]; then
                FILE_SIZE=$(du -h "${RELEASE_ASSETS_DIR}/${name}" | cut -f1)
                echo "    ✅ ${name} 下载成功 (${FILE_SIZE})"
                DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
            else
                echo "    ❌ ${name} 下载失败 (HTTP ${HTTP_CODE})"
                DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
            fi
        fi
    done
}

# 从 build tag 提取版本信息
extract_version_from_build_tag() {
    echo -e "${BLUE}🔍 从 build tag 读取 VERSION.yaml...${NC}"
    
    # 从 Release 标签获取版本号
    VERSION=${TAG_NAME#v}  # 去掉 v 前缀（例如 v1.0.7 -> 1.0.7）
    
    # 根据版本号构建 build tag 名称（例如 1.0.7 -> build1.0.7）
    BUILD_TAG="build${VERSION}"
    
    echo "  Release Tag: ${TAG_NAME}"
    echo "  Version: ${VERSION}"
    echo "  Build Tag: ${BUILD_TAG}"
    
    # Checkout build tag 以获取 VERSION.yaml
    git fetch --tags --force 2>/dev/null || true
    
    if git rev-parse "${BUILD_TAG}" >/dev/null 2>&1; then
        echo "✅ 找到 build tag: ${BUILD_TAG}"
        git checkout "${BUILD_TAG}" -- VERSION.yaml 2>/dev/null || {
            echo -e "${YELLOW}⚠️ 无法 checkout VERSION.yaml，尝试从当前工作区读取${NC}"
            if [ ! -f "VERSION.yaml" ]; then
                echo -e "${RED}❌ 错误: 未找到 VERSION.yaml${NC}"
                exit 1
            fi
        }
    else
        echo -e "${YELLOW}⚠️ 未找到 build tag: ${BUILD_TAG}${NC}"
        echo "  尝试从当前工作区读取 VERSION.yaml"
        if [ ! -f "VERSION.yaml" ]; then
            echo -e "${YELLOW}⚠️ 未找到 VERSION.yaml，使用 Release 标签版本号: ${VERSION}${NC}"
            return
        fi
    fi
    
    # 安装 PyYAML（如果需要）
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "  安装 PyYAML..."
        python3 -m pip install --user pyyaml --quiet || \
        python3 -m pip install pyyaml --quiet || {
            echo -e "${YELLOW}⚠️ 无法安装 PyYAML，使用 Release 标签版本号${NC}"
            return
        }
    fi
    
    # 从 VERSION.yaml 读取版本信息
    if [ -f "VERSION.yaml" ]; then
        CLIENT_FULL_VERSION=$(python3 -c "import yaml; print(yaml.safe_load(open('VERSION.yaml'))['client']['version'])" 2>/dev/null || echo "")
        SERVER_FULL_VERSION=$(python3 -c "import yaml; print(yaml.safe_load(open('VERSION.yaml'))['server']['version'])" 2>/dev/null || echo "")
        
        if [ -n "$CLIENT_FULL_VERSION" ]; then
            CLIENT_VERSION_NUM=$(echo "${CLIENT_FULL_VERSION}" | sed 's/+.*//')
            VERSION="${CLIENT_VERSION_NUM}"
            
            echo ""
            echo -e "${GREEN}✅ 从 build tag (${BUILD_TAG}) 的 VERSION.yaml 提取的版本信息:${NC}"
            echo "  Client Full Version: ${CLIENT_FULL_VERSION}"
            echo "  Client Version Number: ${CLIENT_VERSION_NUM}"
            echo "  Server Full Version: ${SERVER_FULL_VERSION}"
            echo "  Release Tag: ${TAG_NAME}"
            echo "  Release Version: ${VERSION}"
        fi
    fi
    
    echo ""
}

# 创建 Gitee Release
create_gitee_release() {
    # 检查是否需要跳过创建 Release（如果 hash 匹配，Release 已存在且内容一致）
    if [ "${SKIP_UPLOAD_ASSETS:-false}" = "true" ]; then
        echo -e "${GREEN}✅ 跳过创建 Gitee Release（文件已是最新版本，Release 已存在）${NC}"
        echo ""
        return 0
    fi
    
    echo -e "${BLUE}🚀 创建 Gitee Release...${NC}"
    
    # URL 编码
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    TAG_NAME_ENCODED=$(printf '%s' "${TAG_NAME}" | jq -sRr @uri)
    
    # 验证仓库是否存在
    echo "🔍 验证 Gitee 仓库是否存在..."
    REPO_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}"
    
    REPO_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${REPO_API_URL}")
    
    REPO_CHECK_HTTP_CODE=$(echo "$REPO_CHECK" | tail -n1)
    REPO_CHECK_BODY=$(echo "$REPO_CHECK" | sed '$d')
    
    if [ "$REPO_CHECK_HTTP_CODE" != "200" ]; then
        ERROR_MSG=$(echo "$REPO_CHECK_BODY" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "$REPO_CHECK_BODY")
        echo -e "${RED}❌ Gitee 仓库不存在或无法访问 (HTTP ${REPO_CHECK_HTTP_CODE})${NC}"
        echo "  错误信息: ${ERROR_MSG}"
        exit 1
    fi
    
    REPO_DEFAULT_BRANCH=$(echo "$REPO_CHECK_BODY" | jq -r '.default_branch // "master"' 2>/dev/null || echo "master")
    echo -e "${GREEN}✅ Gitee 仓库验证通过${NC}"
    echo "  默认分支: ${REPO_DEFAULT_BRANCH}"
    
    # 获取tag对应的commit SHA
    echo ""
    echo "🔍 获取tag ${TAG_NAME} 对应的commit SHA..."
    TAG_INFO_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/tags/${TAG_NAME_ENCODED}"
    TAG_INFO=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${TAG_INFO_API_URL}")
    
    TAG_INFO_HTTP_CODE=$(echo "$TAG_INFO" | tail -n1)
    TAG_INFO_BODY=$(echo "$TAG_INFO" | sed '$d')
    
    if [ "$TAG_INFO_HTTP_CODE" = "200" ]; then
        TARGET_COMMITISH=$(echo "$TAG_INFO_BODY" | jq -r '.commit.sha // empty' 2>/dev/null || echo "")
        if [ -n "$TARGET_COMMITISH" ] && [ "$TARGET_COMMITISH" != "null" ]; then
            echo "✅ 使用tag ${TAG_NAME} 对应的commit: ${TARGET_COMMITISH:0:7}..."
        else
            TARGET_COMMITISH=""
        fi
    else
        TARGET_COMMITISH=""
    fi
    
    # 如果无法从tag获取commit，则使用默认分支的最新commit
    if [ -z "$TARGET_COMMITISH" ] || [ "$TARGET_COMMITISH" == "null" ]; then
        echo "🔍 获取默认分支 ${REPO_DEFAULT_BRANCH} 的最新 commit..."
        BRANCH_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/branches/${REPO_DEFAULT_BRANCH}"
        BRANCH_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
            -H "Authorization: token ${GITEE_TOKEN}" \
            "${BRANCH_API_URL}")
        
        BRANCH_CHECK_HTTP_CODE=$(echo "$BRANCH_CHECK" | tail -n1)
        if [ "$BRANCH_CHECK_HTTP_CODE" = "200" ]; then
            BRANCH_CHECK_BODY=$(echo "$BRANCH_CHECK" | sed '$d')
            TARGET_COMMITISH=$(echo "$BRANCH_CHECK_BODY" | jq -r '.commit.sha // empty' 2>/dev/null || echo "")
            if [ -z "$TARGET_COMMITISH" ] || [ "$TARGET_COMMITISH" == "null" ]; then
                TARGET_COMMITISH="${REPO_DEFAULT_BRANCH}"
            else
                echo "✅ 使用默认分支 ${REPO_DEFAULT_BRANCH} 的最新 commit: ${TARGET_COMMITISH:0:7}..."
            fi
        else
            TARGET_COMMITISH="${REPO_DEFAULT_BRANCH}"
        fi
    fi
    
    # 检查并删除所有匹配tag的Release（仅在需要上传时）
    if [ "${SKIP_UPLOAD_ASSETS:-false}" = "true" ]; then
        echo "✅ Release 已存在且文件一致，跳过删除操作"
    else
        echo ""
        echo "🔍 检查并删除所有匹配tag的Gitee Release..."
        DELETED_COUNT=0
    PAGE=1
    PER_PAGE=100
    
    while true; do
        RELEASES_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases?page=${PAGE}&per_page=${PER_PAGE}"
        RELEASES_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
            -H "Authorization: token ${GITEE_TOKEN}" \
            "${RELEASES_API_URL}")
        
        RELEASES_HTTP_CODE=$(echo "$RELEASES_RESPONSE" | tail -n1)
        RELEASES_BODY=$(echo "$RELEASES_RESPONSE" | sed '$d')
        
        if [ "$RELEASES_HTTP_CODE" != "200" ]; then
            echo -e "${YELLOW}⚠️ 获取Release列表失败 (HTTP ${RELEASES_HTTP_CODE})，跳过删除步骤${NC}"
            break
        fi
        
        MATCHING_RELEASES=$(echo "$RELEASES_BODY" | jq -r ".[] | select(.tag_name == \"${TAG_NAME}\") | .id" 2>/dev/null || echo "")
        
        if [ -z "$MATCHING_RELEASES" ]; then
            RELEASE_COUNT=$(echo "$RELEASES_BODY" | jq 'length' 2>/dev/null || echo "0")
            if [ "$RELEASE_COUNT" -lt "$PER_PAGE" ]; then
                break
            fi
            PAGE=$((PAGE + 1))
            continue
        fi
        
        while IFS= read -r RELEASE_ID; do
            if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
                echo "  删除 Release ID: ${RELEASE_ID} (tag: ${TAG_NAME})"
                DELETE_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}"
                
                DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
                    -H "Authorization: token ${GITEE_TOKEN}" \
                    "${DELETE_API_URL}")
                
                DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)
                
                if [ "$DELETE_HTTP_CODE" = "204" ] || [ "$DELETE_HTTP_CODE" = "200" ]; then
                    echo "  ✅ 已删除 Release (ID: ${RELEASE_ID})"
                    DELETED_COUNT=$((DELETED_COUNT + 1))
                else
                    DELETE_BODY=$(echo "$DELETE_RESPONSE" | sed '$d')
                    ERROR_MSG=$(echo "$DELETE_BODY" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "$DELETE_BODY")
                    echo "  ⚠️ 删除 Release ${RELEASE_ID} 失败 (HTTP ${DELETE_HTTP_CODE}): ${ERROR_MSG}"
                fi
            fi
        done <<< "$MATCHING_RELEASES"
        
        RELEASE_COUNT=$(echo "$RELEASES_BODY" | jq 'length' 2>/dev/null || echo "0")
        if [ "$RELEASE_COUNT" -lt "$PER_PAGE" ]; then
            break
        fi
        PAGE=$((PAGE + 1))
        done
        
        if [ "$DELETED_COUNT" -gt 0 ]; then
            echo "✅ 共删除了 ${DELETED_COUNT} 个匹配tag的Release"
            sleep 3
        else
            echo "✅ 未找到需要删除的Release，将创建新的Release"
        fi
    fi
    
    # 确保标签存在
    echo ""
    echo "🔍 检查 Gitee 标签是否存在..."
    TAG_CHECK_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/tags/${TAG_NAME_ENCODED}"
    
    TAG_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${TAG_CHECK_API_URL}")
    
    TAG_CHECK_HTTP_CODE=$(echo "$TAG_CHECK" | tail -n1)
    
    if [ "$TAG_CHECK_HTTP_CODE" != "200" ]; then
        echo "⚠️ 标签 ${TAG_NAME} 不存在，创建标签..."
        
        CREATE_TAG_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/tags"
        CREATE_TAG_BODY=$(echo "{
          \"refs\": \"${TARGET_COMMITISH}\",
          \"tag_name\": \"${TAG_NAME}\",
          \"message\": \"Release ${TAG_NAME}\"
        }" | jq -c .)
        
        CREATE_TAG_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${GITEE_TOKEN}" \
            -d "${CREATE_TAG_BODY}" \
            "${CREATE_TAG_API_URL}")
        
        CREATE_TAG_HTTP_CODE=$(echo "$CREATE_TAG_RESPONSE" | tail -n1)
        
        if [ "$CREATE_TAG_HTTP_CODE" = "200" ] || [ "$CREATE_TAG_HTTP_CODE" = "201" ]; then
            echo "✅ 标签 ${TAG_NAME} 创建成功"
        else
            CREATE_TAG_BODY_RESPONSE=$(echo "$CREATE_TAG_RESPONSE" | sed '$d')
            ERROR_MSG=$(echo "$CREATE_TAG_BODY_RESPONSE" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "$CREATE_TAG_BODY_RESPONSE")
            if echo "$ERROR_MSG" | grep -qi "已存在\|already exists\|duplicate\|标签名已存在"; then
                echo "✅ 标签已存在"
            else
                echo -e "${YELLOW}⚠️ 创建标签失败，但继续执行${NC}"
            fi
        fi
    else
        echo "✅ 标签 ${TAG_NAME} 已存在"
    fi
    
    # 创建新 Release
    echo ""
    echo "📝 创建新的 Gitee Release..."
    
    CREATE_BODY_JSON=$(echo "${RELEASE_BODY}" | jq -Rs .)
    REQUEST_BODY=$(echo "{
      \"tag_name\": \"${TAG_NAME}\",
      \"name\": \"${RELEASE_NAME}\",
      \"body\": ${CREATE_BODY_JSON},
      \"target_commitish\": \"${TARGET_COMMITISH}\",
      \"prerelease\": false
    }" | jq -c .)
    
    CREATE_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -d "${REQUEST_BODY}" \
        "${CREATE_API_URL}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        if echo "${RESPONSE_BODY}" | grep -q '"id"'; then
            RELEASE_ID=$(echo "${RESPONSE_BODY}" | jq -r '.id // empty')
            echo -e "${GREEN}✅ Gitee Release 创建成功${NC}"
            echo "  Release ID: ${RELEASE_ID}"
        else
            echo -e "${YELLOW}⚠️ 响应格式异常，但 HTTP 状态码为 ${HTTP_CODE}${NC}"
        fi
    else
        ERROR_MSG=$(echo "${RESPONSE_BODY}" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "${RESPONSE_BODY}")
        echo -e "${RED}❌ Gitee Release 创建失败 (HTTP ${HTTP_CODE})${NC}"
        echo "  错误信息: ${ERROR_MSG}"
        exit 1
    fi
    
    echo ""
}

# 提前检查两个平台的 hash 列表，决定是否需要下载和上传
check_hashes_before_download() {
    echo -e "${BLUE}🔍 提前检查两个平台的 hash 列表...${NC}"
    
    # URL 编码
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    TAG_NAME_ENCODED=$(printf '%s' "${TAG_NAME}" | jq -sRr @uri)
    
    # 初始化变量
    export SKIP_DOWNLOAD_ASSETS=false
    export SKIP_UPLOAD_ASSETS=false
    
    # 1. 检查 Gitee Release 是否存在
    echo ""
    echo "📋 步骤 1: 检查 Gitee Release..."
    RELEASE_CHECK_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${TAG_NAME_ENCODED}"
    
    RELEASE_CHECK=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${RELEASE_CHECK_API_URL}")
    
    RELEASE_CHECK_HTTP_CODE=$(echo "$RELEASE_CHECK" | tail -n1)
    RELEASE_CHECK_BODY=$(echo "$RELEASE_CHECK" | sed '$d')
    
    if [ "$RELEASE_CHECK_HTTP_CODE" != "200" ]; then
        echo "✅ Gitee Release 不存在，需要下载和上传所有文件"
        return 0
    fi
    
    RELEASE_ID=$(echo "$RELEASE_CHECK_BODY" | jq -r '.id // empty' 2>/dev/null || echo "")
    
    if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" == "null" ]; then
        echo "⚠️  无法获取 Release ID，需要下载和上传所有文件"
        return 0
    fi
    
    echo "✅ Gitee Release 已存在 (ID: ${RELEASE_ID})"
    
    # 2. 从 Gitee Release 下载 file_hashes.json
    echo ""
    echo "📋 步骤 2: 从 Gitee Release 下载 file_hashes.json..."
    ASSETS_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}/attach_files"
    
    ASSETS_RESPONSE=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${ASSETS_API_URL}")
    
    ASSETS_HTTP_CODE=$(echo "$ASSETS_RESPONSE" | tail -n1)
    ASSETS_BODY=$(echo "$ASSETS_RESPONSE" | sed '$d')
    
    if [ "$ASSETS_HTTP_CODE" != "200" ]; then
        echo "⚠️  无法获取 Gitee Release assets，需要下载和上传所有文件"
        return 0
    fi
    
    GITEE_HASH_FILE_URL=$(echo "$ASSETS_BODY" | jq -r '.[] | select(.name == "file_hashes.json") | .browser_download_url' 2>/dev/null || echo "")
    
    if [ -z "$GITEE_HASH_FILE_URL" ]; then
        echo "⚠️  Gitee Release 中没有 file_hashes.json，需要下载和上传所有文件"
        return 0
    fi
    
    GITEE_HASH_FILE="${TEMP_DIR}/gitee_file_hashes.json"
    download_result=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -L \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -o "$GITEE_HASH_FILE" \
        "$GITEE_HASH_FILE_URL")
    
    download_http_code=$(echo "$download_result" | tail -n1)
    
    if [ "$download_http_code" != "200" ] || [ ! -f "$GITEE_HASH_FILE" ]; then
        echo "⚠️  下载 Gitee file_hashes.json 失败，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    if ! jq empty "$GITEE_HASH_FILE" 2>/dev/null; then
        echo "⚠️  Gitee file_hashes.json 格式无效，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    echo "✅ 已下载 Gitee file_hashes.json"
    
    # 3. 从 GitHub Release 下载 file_hashes.json
    echo ""
    echo "📋 步骤 3: 从 GitHub Release 下载 file_hashes.json..."
    
    # 从之前获取的 RELEASE_INFO 中查找 file_hashes.json
    GITHUB_HASH_FILE_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name == "file_hashes.json") | .browser_download_url' 2>/dev/null || echo "")
    
    if [ -z "$GITHUB_HASH_FILE_URL" ]; then
        echo "⚠️  GitHub Release 中没有 file_hashes.json，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    GITHUB_HASH_FILE="${TEMP_DIR}/github_file_hashes.json"
    
    if [ -n "$GITHUB_TOKEN" ]; then
        download_result=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -L \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            -o "$GITHUB_HASH_FILE" \
            "$GITHUB_HASH_FILE_URL")
    else
        download_result=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -L \
            -o "$GITHUB_HASH_FILE" \
            "$GITHUB_HASH_FILE_URL")
    fi
    
    download_http_code=$(echo "$download_result" | tail -n1)
    
    if [ "$download_http_code" != "200" ] || [ ! -f "$GITHUB_HASH_FILE" ]; then
        echo "⚠️  下载 GitHub file_hashes.json 失败，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE" "$GITHUB_HASH_FILE"
        return 0
    fi
    
    if ! jq empty "$GITHUB_HASH_FILE" 2>/dev/null; then
        echo "⚠️  GitHub file_hashes.json 格式无效，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE" "$GITHUB_HASH_FILE"
        return 0
    fi
    
    echo "✅ 已下载 GitHub file_hashes.json"
    
    # 4. 比较两个 hash 文件
    echo ""
    echo "📋 步骤 4: 比较两个平台的 hash 文件..."
    
    # 比较两个 JSON 文件的内容（忽略顺序）
    GITHUB_HASH_CONTENT=$(jq -S -c . "$GITHUB_HASH_FILE" 2>/dev/null || echo "")
    GITEE_HASH_CONTENT=$(jq -S -c . "$GITEE_HASH_FILE" 2>/dev/null || echo "")
    
    if [ -z "$GITHUB_HASH_CONTENT" ] || [ -z "$GITEE_HASH_CONTENT" ]; then
        echo "⚠️  无法解析 hash 文件，需要下载和上传所有文件"
        rm -f "$GITEE_HASH_FILE" "$GITHUB_HASH_FILE"
        return 0
    fi
    
    if [ "$GITHUB_HASH_CONTENT" = "$GITEE_HASH_CONTENT" ]; then
        echo -e "${GREEN}✅ 两个平台的 hash 文件完全一致！${NC}"
        echo ""
        echo "📊 Hash 文件统计:"
        FILE_COUNT=$(jq 'length' "$GITHUB_HASH_FILE" 2>/dev/null || echo "0")
        echo "  文件数量: ${FILE_COUNT}"
        echo ""
        echo -e "${GREEN}✅ 跳过下载和上传构建产物（文件已是最新版本）${NC}"
        export SKIP_DOWNLOAD_ASSETS=true
        export SKIP_UPLOAD_ASSETS=true
        
        # 保存 GitHub hash 文件供后续使用（如果后续步骤需要）
        RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
        mkdir -p "${RELEASE_ASSETS_DIR}"
        cp "$GITHUB_HASH_FILE" "${RELEASE_ASSETS_DIR}/file_hashes.json"
    else
        echo -e "${YELLOW}⚠️  两个平台的 hash 文件不一致，需要下载和上传${NC}"
        echo "  将比较详细的差异..."
        
        # 显示差异（可选）
        GITHUB_FILES=$(jq -r 'keys[]' "$GITHUB_HASH_FILE" 2>/dev/null | sort || echo "")
        GITEE_FILES=$(jq -r 'keys[]' "$GITEE_HASH_FILE" 2>/dev/null | sort || echo "")
        
        if [ "$GITHUB_FILES" != "$GITEE_FILES" ]; then
            echo "  文件列表不一致"
        fi
        
        # 逐个比较文件 hash
        ALL_MATCH=true
        for file_name in $(echo "$GITHUB_FILES"); do
            github_hash=$(jq -r ".[\"${file_name}\"] // empty" "$GITHUB_HASH_FILE" 2>/dev/null || echo "")
            gitee_hash=$(jq -r ".[\"${file_name}\"] // empty" "$GITEE_HASH_FILE" 2>/dev/null || echo "")
            
            if [ -z "$github_hash" ] || [ -z "$gitee_hash" ] || [ "$github_hash" != "$gitee_hash" ]; then
                if [ "$ALL_MATCH" = true ]; then
                    echo "  不匹配的文件:"
                    ALL_MATCH=false
                fi
                echo "    - ${file_name}"
                if [ -n "$github_hash" ] && [ -n "$gitee_hash" ] && [ "$github_hash" != "$gitee_hash" ]; then
                    echo "      GitHub: ${github_hash}"
                    echo "      Gitee:  ${gitee_hash}"
                fi
            fi
        done
    fi
    
    # 清理临时文件
    rm -f "$GITEE_HASH_FILE" "$GITHUB_HASH_FILE"
    
    echo ""
}

# 检查 Gitee Release 文件 hash 并决定是否需要上传
check_gitee_release_hashes() {
    echo -e "${BLUE}🔍 检查 Gitee Release 文件 hash...${NC}"
    
    # 确保 RELEASE_ASSETS_DIR 变量已定义
    RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
    
    # URL 编码
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    TAG_NAME_ENCODED=$(printf '%s' "${TAG_NAME}" | jq -sRr @uri)
    
    # 检查 Release 是否存在
    RELEASE_CHECK_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${TAG_NAME_ENCODED}"
    
    RELEASE_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${RELEASE_CHECK_API_URL}")
    
    RELEASE_CHECK_HTTP_CODE=$(echo "$RELEASE_CHECK" | tail -n1)
    RELEASE_CHECK_BODY=$(echo "$RELEASE_CHECK" | sed '$d')
    
    if [ "$RELEASE_CHECK_HTTP_CODE" != "200" ]; then
        echo "✅ Gitee Release 不存在，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        return 0
    fi
    
    RELEASE_ID=$(echo "$RELEASE_CHECK_BODY" | jq -r '.id // empty' 2>/dev/null || echo "")
    
    if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" == "null" ]; then
        echo "⚠️  无法获取 Release ID，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        return 0
    fi
    
    echo "✅ Gitee Release 已存在 (ID: ${RELEASE_ID})"
    
    # 获取 Release 的 assets 列表，查找 file_hashes.json
    ASSETS_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}/attach_files"
    
    ASSETS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${ASSETS_API_URL}")
    
    ASSETS_HTTP_CODE=$(echo "$ASSETS_RESPONSE" | tail -n1)
    ASSETS_BODY=$(echo "$ASSETS_RESPONSE" | sed '$d')
    
    if [ "$ASSETS_HTTP_CODE" != "200" ]; then
        echo "⚠️  无法获取 Release assets，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        return 0
    fi
    
    # 查找 file_hashes.json
    HASH_FILE_URL=$(echo "$ASSETS_BODY" | jq -r '.[] | select(.name == "file_hashes.json") | .browser_download_url' 2>/dev/null || echo "")
    
    if [ -z "$HASH_FILE_URL" ]; then
        echo "⚠️  Gitee Release 中没有 file_hashes.json，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        return 0
    fi
    
    echo "📥 下载 Gitee Release 的 file_hashes.json..."
    GITEE_HASH_FILE="${TEMP_DIR}/gitee_file_hashes.json"
    
    download_result=$(curl -s -w "\n%{http_code}" -L \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -o "$GITEE_HASH_FILE" \
        "$HASH_FILE_URL")
    
    download_http_code=$(echo "$download_result" | tail -n1)
    
    if [ "$download_http_code" != "200" ] || [ ! -f "$GITEE_HASH_FILE" ]; then
        echo "⚠️  下载 file_hashes.json 失败，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    # 加载 Gitee 的 hash 文件
    if ! jq empty "$GITEE_HASH_FILE" 2>/dev/null; then
        echo "⚠️  file_hashes.json 格式无效，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    echo "✅ 已下载 Gitee file_hashes.json"
    
    # 加载本地的 hash 文件
    LOCAL_HASH_FILE="${RELEASE_ASSETS_DIR}/file_hashes.json"
    if [ ! -f "$LOCAL_HASH_FILE" ]; then
        echo "⚠️  本地 file_hashes.json 不存在，需要上传所有文件"
        export SKIP_UPLOAD_ASSETS=false
        rm -f "$GITEE_HASH_FILE"
        return 0
    fi
    
    # 比较 hash
    echo ""
    echo "📋 比较文件 hash..."
    
    # 获取需要比较的文件列表（排除 file_hashes.json 本身）
    LOCAL_FILES=()
    while IFS= read -r -d '' file; do
        file_name=$(basename "$file")
        if [ "$file_name" != "file_hashes.json" ]; then
            LOCAL_FILES+=("$file")
        fi
    done < <(find "${RELEASE_ASSETS_DIR}" -type f -print0 2>/dev/null)
    
    ALL_MATCH=true
    MISMATCH_FILES=()
    
    for local_file in "${LOCAL_FILES[@]}"; do
        local_file_name=$(basename "$local_file")
        
        # 从本地 hash 文件获取 hash
        local_hash=$(jq -r ".[\"${local_file_name}\"] // empty" "$LOCAL_HASH_FILE" 2>/dev/null || echo "")
        
        if [ -z "$local_hash" ]; then
            echo "  ⚠️  本地 hash 文件中未找到: ${local_file_name}"
            ALL_MATCH=false
            MISMATCH_FILES+=("${local_file_name} (本地 hash 不存在)")
            continue
        fi
        
        # 从 Gitee hash 文件获取 hash
        gitee_hash=$(jq -r ".[\"${local_file_name}\"] // empty" "$GITEE_HASH_FILE" 2>/dev/null || echo "")
        
        if [ -z "$gitee_hash" ]; then
            echo "  ⚠️  Gitee hash 文件中未找到: ${local_file_name}"
            ALL_MATCH=false
            MISMATCH_FILES+=("${local_file_name} (Gitee hash 不存在)")
            continue
        fi
        
        # 比较 hash
        if [ "$local_hash" = "$gitee_hash" ]; then
            echo "  ✅ ${local_file_name}: hash 匹配"
        else
            echo "  ❌ ${local_file_name}: hash 不匹配"
            echo "     本地: ${local_hash}"
            echo "     Gitee: ${gitee_hash}"
            ALL_MATCH=false
            MISMATCH_FILES+=("${local_file_name}")
        fi
    done
    
    # 清理临时文件
    rm -f "$GITEE_HASH_FILE"
    
    echo ""
    if [ "$ALL_MATCH" = true ]; then
        echo -e "${GREEN}✅ 所有文件 hash 匹配，跳过上传构建产物${NC}"
        export SKIP_UPLOAD_ASSETS=true
    else
        echo -e "${YELLOW}⚠️  文件 hash 不匹配，需要上传构建产物${NC}"
        if [ ${#MISMATCH_FILES[@]} -gt 0 ]; then
            echo "不匹配的文件:"
            for file in "${MISMATCH_FILES[@]}"; do
                echo "  - ${file}"
            done
        fi
        export SKIP_UPLOAD_ASSETS=false
    fi
    
    echo ""
}

# 上传构建产物到 Gitee Release
upload_assets_to_gitee() {
    # 检查是否需要跳过上传
    if [ "${SKIP_UPLOAD_ASSETS:-false}" = "true" ]; then
        echo -e "${GREEN}✅ 跳过上传构建产物（文件 hash 已匹配）${NC}"
        return 0
    fi
    
    echo -e "${BLUE}📤 上传构建产物到 Gitee Release...${NC}"
    
    # 获取 Release ID
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    TAG_NAME_ENCODED=$(printf '%s' "${TAG_NAME}" | jq -sRr @uri)
    
    RELEASE_INFO_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${TAG_NAME_ENCODED}"
    
    RELEASE_INFO=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "${RELEASE_INFO_API_URL}")
    
    RELEASE_INFO_HTTP_CODE=$(echo "$RELEASE_INFO" | tail -n1)
    RELEASE_INFO_BODY=$(echo "$RELEASE_INFO" | sed '$d')
    
    if [ "$RELEASE_INFO_HTTP_CODE" != "200" ] || ! echo "${RELEASE_INFO_BODY}" | grep -q '"id"'; then
        echo -e "${RED}❌ 无法获取 Gitee Release 信息 (HTTP ${RELEASE_INFO_HTTP_CODE})${NC}"
        exit 1
    fi
    
    RELEASE_ID=$(echo "${RELEASE_INFO_BODY}" | jq -r '.id // empty')
    echo "✅ 找到 Gitee Release (ID: ${RELEASE_ID})"
    
    # 检查文件数量
    RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
    FILE_COUNT=$(find "${RELEASE_ASSETS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FILE_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}⚠️ 未找到需要上传的文件${NC}"
        return
    fi
    
    echo "  找到 ${FILE_COUNT} 个文件需要上传"
    
    # 收集所有文件列表
    FILES=()
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "${RELEASE_ASSETS_DIR}" -type f -print0 2>/dev/null)
    
    TOTAL_FILES=${#FILES[@]}
    UPLOAD_SUCCESS=0
    UPLOAD_FAILED=0
    MAX_RETRIES=3
    RETRY_DELAY=5
    
    UPLOAD_API_BASE_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}/attach_files"
    
    FILE_INDEX=0
    for file in "${FILES[@]}"; do
        FILE_INDEX=$((FILE_INDEX + 1))
        
        # 添加请求间隔，避免 Gitee API 限流
        if [ $FILE_INDEX -gt 1 ]; then
            echo "   ⏸️  等待 2 秒以避免 API 限流..."
            sleep 2
        fi
        
        filename=$(basename "$file")
        filesize=$(du -h "$file" | cut -f1)
        filesize_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦 [${FILE_INDEX}/${TOTAL_FILES}] 上传 ${filename}"
        echo "   文件大小: ${filesize} (${filesize_bytes} bytes)"
        
        # 重试机制
        RETRY_COUNT=0
        UPLOAD_SUCCESS_FLAG=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            if [ $RETRY_COUNT -gt 0 ]; then
                echo "   ⏳ 重试第 ${RETRY_COUNT}/${MAX_RETRIES} 次（等待 ${RETRY_DELAY} 秒后重试）..."
                sleep $RETRY_DELAY
            fi
            
            echo "   📤 开始上传 ${filename}..."
            UPLOAD_START_TIME=$(date +%s)
            
            TEMP_RESPONSE_FILE=$(mktemp)
            TEMP_HTTP_CODE_FILE=$(mktemp)
            
            CONNECT_TIMEOUT=30
            MAX_TIMEOUT=$((filesize_bytes / 102400 + 600))
            if [ $MAX_TIMEOUT -lt 600 ]; then
                MAX_TIMEOUT=600
            fi
            if [ $MAX_TIMEOUT -gt 3600 ]; then
                MAX_TIMEOUT=3600
            fi
            
            curl --progress-bar --show-error \
                --connect-timeout ${CONNECT_TIMEOUT} \
                --max-time ${MAX_TIMEOUT} \
                --retry 2 \
                --retry-delay 3 \
                --retry-connrefused \
                -w "%{http_code}" \
                -o "${TEMP_RESPONSE_FILE}" \
                -X POST \
                -H "Authorization: token ${GITEE_TOKEN}" \
                -F "file=@${file}" \
                "${UPLOAD_API_BASE_URL}" \
                > "${TEMP_HTTP_CODE_FILE}"
            
            CURL_EXIT_CODE=$?
            
            HTTP_CODE=$(cat "${TEMP_HTTP_CODE_FILE}" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "")
            RESPONSE_BODY=$(cat "${TEMP_RESPONSE_FILE}" 2>/dev/null || echo "")
            
            rm -f "${TEMP_RESPONSE_FILE}" "${TEMP_HTTP_CODE_FILE}"
            
            UPLOAD_END_TIME=$(date +%s)
            UPLOAD_DURATION=$((UPLOAD_END_TIME - UPLOAD_START_TIME))
            
            if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
                echo "   ✅ ${filename} 上传成功（耗时: ${UPLOAD_DURATION}秒）"
                UPLOAD_SUCCESS=$((UPLOAD_SUCCESS + 1))
                UPLOAD_SUCCESS_FLAG=true
                break
            elif echo "$RESPONSE_BODY" | grep -qi "already exists\|已存在\|duplicate"; then
                echo "   ⚠️ ${filename} 已存在，跳过"
                UPLOAD_SUCCESS=$((UPLOAD_SUCCESS + 1))
                UPLOAD_SUCCESS_FLAG=true
                break
            else
                ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "HTTP ${HTTP_CODE}")
                echo "   ❌ 上传失败: ${ERROR_MSG}"
                
                if echo "$HTTP_CODE" | grep -qE "^(429|500|502|503|504)$"; then
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                elif [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ]; then
                    break
                elif [ "$HTTP_CODE" -eq 404 ]; then
                    break
                else
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                fi
            fi
        done
        
        if [ "$UPLOAD_SUCCESS_FLAG" = false ]; then
            echo "   ❌ ${filename} 上传失败（已重试 ${MAX_RETRIES} 次）"
            UPLOAD_FAILED=$((UPLOAD_FAILED + 1))
        fi
        
        echo ""
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📊 上传统计:"
    echo "  ✅ 成功: ${UPLOAD_SUCCESS}/${TOTAL_FILES}"
    echo "  ❌ 失败: ${UPLOAD_FAILED}/${TOTAL_FILES}"
    
    if [ "$UPLOAD_FAILED" -gt 0 ]; then
        if [ "$UPLOAD_FAILED" -eq "$TOTAL_FILES" ]; then
            echo -e "${RED}❌ 所有文件上传失败，终止流程${NC}"
            exit 1
        else
            echo -e "${YELLOW}⚠️ 部分文件上传失败，继续执行后续步骤${NC}"
        fi
    else
        echo -e "${GREEN}✅ 所有构建产物上传完成${NC}"
    fi
    
    echo ""
}

# 生成更新配置文件（仅生成，不检查）
generate_update_config_file() {
    echo -e "${BLUE}📝 生成更新配置文件...${NC}"
    
    # 单点数据源原则：版本信息从 build tag 的 VERSION.yaml 获取（已在 extract_version_from_build_tag() 中设置）
    if [ -z "$CLIENT_FULL_VERSION" ] || [ -z "$SERVER_FULL_VERSION" ]; then
        echo -e "${RED}❌ 版本信息未设置，请确保已调用 extract_version_from_build_tag()${NC}"
        return 1
    fi
    
    echo "  使用从 build tag 的 VERSION.yaml 提取的版本信息（单点数据源）:"
    echo "    Client Version: ${CLIENT_FULL_VERSION}"
    echo "    Server Version: ${SERVER_FULL_VERSION}"
    
    # 从构建产物目录中找到文件
    RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
    MACOS_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "HelloKnightRCC_macos_*.zip" | head -1)
    WINDOWS_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "HelloKnightRCC_windows_*.zip" | head -1)
    ANDROID_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "helloknightrcc_server_android_*.zip" | head -1)
    
    if [ -z "$MACOS_FILE" ] || [ ! -f "$MACOS_FILE" ]; then
        echo -e "${RED}❌ 未找到 macOS 构建产物文件${NC}"
        return 1
    fi
    
    if [ -z "$WINDOWS_FILE" ] || [ ! -f "$WINDOWS_FILE" ]; then
        echo -e "${RED}❌ 未找到 Windows 构建产物文件${NC}"
        return 1
    fi
    
    if [ -z "$ANDROID_FILE" ] || [ ! -f "$ANDROID_FILE" ]; then
        echo -e "${RED}❌ 未找到 Android 构建产物文件${NC}"
        return 1
    fi
    
    echo "  找到构建产物文件:"
    echo "    macOS: $MACOS_FILE"
    echo "    Windows: $WINDOWS_FILE"
    echo "    Android: $ANDROID_FILE"
    
    # 提取主版本号（用于 tag）
    CLIENT_VERSION_NUM=$(echo "${CLIENT_FULL_VERSION}" | sed 's/+.*//')
    TAG_NAME="v${CLIENT_VERSION_NUM}"
    
    # 使用统一的生成脚本生成 Gitee 配置
    CONFIG_RELEASE_TAG="config"
    
    # 设置配置文件输出路径
    CONFIG_DIR="${TEMP_DIR}/config"
    mkdir -p "${CONFIG_DIR}"
    CONFIG_GITEE_FILE="${CONFIG_DIR}/update_config_gitee.json"
    
    echo ""
    echo "📝 使用统一脚本生成 Gitee 更新配置（单点数据源：build tag 的 VERSION.yaml + 构建产物文件）..."
    
    # 检查是否存在 hash 文件
    HASH_FILE="${RELEASE_ASSETS_DIR}/file_hashes.json"
    if [ -f "$HASH_FILE" ]; then
        echo -e "${GREEN}✅ 使用已生成的 hash 文件: $HASH_FILE${NC}"
        python3 scripts/generate_update_config.py \
          --client-version "${CLIENT_FULL_VERSION}" \
          --server-version "${SERVER_FULL_VERSION}" \
          --macos-file "${MACOS_FILE}" \
          --windows-file "${WINDOWS_FILE}" \
          --android-file "${ANDROID_FILE}" \
          --tag-version "${TAG_NAME}" \
          --repo-owner "${GITEE_REPO_OWNER}" \
          --repo-name "${GITEE_REPO_NAME}" \
          --repo-type gitee \
          --file-hashes "$HASH_FILE" \
          --output "${CONFIG_GITEE_FILE}"
    else
        echo -e "${YELLOW}⚠️  Hash 文件不存在，将重新计算 hash${NC}"
        python3 scripts/generate_update_config.py \
          --client-version "${CLIENT_FULL_VERSION}" \
          --server-version "${SERVER_FULL_VERSION}" \
          --macos-file "${MACOS_FILE}" \
          --windows-file "${WINDOWS_FILE}" \
          --android-file "${ANDROID_FILE}" \
          --tag-version "${TAG_NAME}" \
          --repo-owner "${GITEE_REPO_OWNER}" \
          --repo-name "${GITEE_REPO_NAME}" \
          --repo-type gitee \
          --output "${CONFIG_GITEE_FILE}"
    fi
    
    echo "✅ 已生成 Gitee 更新配置文件"
    echo ""
}

# 检查配置是否需要上传（仅检查，不上传）
check_config_before_upload() {
    echo -e "${BLUE}🔍 检查配置是否需要上传...${NC}"
    
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    CONFIG_RELEASE_TAG="config"
    CONFIG_RELEASE_TAG_ENCODED=$(printf '%s' "${CONFIG_RELEASE_TAG}" | jq -sRr @uri)
    CONFIG_GITEE_FILE="${TEMP_DIR}/config/update_config_gitee.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_GITEE_FILE" ]; then
        echo -e "${YELLOW}⚠️  配置文件不存在，需要生成${NC}"
        export SKIP_UPLOAD_CONFIG=false
        return 0
    fi
    
    # 检查配置 Release 是否存在
    RELEASE_CHECK=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${CONFIG_RELEASE_TAG_ENCODED}")
    
    RELEASE_CHECK_HTTP_CODE=$(echo "$RELEASE_CHECK" | tail -n1)
    RELEASE_CHECK_BODY=$(echo "$RELEASE_CHECK" | sed '$d')
    
    export SKIP_UPLOAD_CONFIG=false
    
    if [ "$RELEASE_CHECK_HTTP_CODE" = "200" ]; then
        CONFIG_RELEASE_ID=$(echo "$RELEASE_CHECK_BODY" | jq -r '.id // empty' 2>/dev/null || echo "")
        
        if [ -n "$CONFIG_RELEASE_ID" ] && [ "$CONFIG_RELEASE_ID" != "null" ]; then
            # 获取配置文件的下载 URL
            ASSETS_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${CONFIG_RELEASE_ID}/attach_files"
            
            ASSETS_RESPONSE=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -X GET \
                -H "Authorization: token ${GITEE_TOKEN}" \
                "${ASSETS_API_URL}")
            
            ASSETS_HTTP_CODE=$(echo "$ASSETS_RESPONSE" | tail -n1)
            ASSETS_BODY=$(echo "$ASSETS_RESPONSE" | sed '$d')
            
            if [ "$ASSETS_HTTP_CODE" = "200" ]; then
                CONFIG_FILE_URL=$(echo "$ASSETS_BODY" | jq -r '.[] | select(.name == "update_config_gitee.json") | .browser_download_url' 2>/dev/null || echo "")
                
                if [ -n "$CONFIG_FILE_URL" ]; then
                    echo "📥 下载 Gitee 上的更新配置..."
                    GITEE_CONFIG_FILE="${TEMP_DIR}/gitee_update_config_gitee.json"
                    
                    download_result=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -L \
                        -H "Authorization: token ${GITEE_TOKEN}" \
                        -o "$GITEE_CONFIG_FILE" \
                        "$CONFIG_FILE_URL")
                    
                    download_http_code=$(echo "$download_result" | tail -n1)
                    
                    if [ "$download_http_code" = "200" ] && [ -f "$GITEE_CONFIG_FILE" ]; then
                        # 比较两个配置文件（忽略 lastUpdated 字段）
                        LOCAL_CONFIG_HASH=$(jq -S -c 'del(.lastUpdated)' "$CONFIG_GITEE_FILE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "")
                        GITEE_CONFIG_HASH=$(jq -S -c 'del(.lastUpdated)' "$GITEE_CONFIG_FILE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "")
                        
                        if [ -n "$LOCAL_CONFIG_HASH" ] && [ -n "$GITEE_CONFIG_HASH" ] && [ "$LOCAL_CONFIG_HASH" = "$GITEE_CONFIG_HASH" ]; then
                            echo -e "${GREEN}✅ 更新配置与 Gitee 上的配置一致，跳过上传${NC}"
                            export SKIP_UPLOAD_CONFIG=true
                        else
                            echo -e "${YELLOW}⚠️  更新配置与 Gitee 上的配置不一致，需要上传${NC}"
                            if [ -n "$LOCAL_CONFIG_HASH" ] && [ -n "$GITEE_CONFIG_HASH" ]; then
                                echo "  本地配置 hash: ${LOCAL_CONFIG_HASH}"
                                echo "  Gitee 配置 hash: ${GITEE_CONFIG_HASH}"
                            fi
                            export SKIP_UPLOAD_CONFIG=false
                        fi
                        
                        rm -f "$GITEE_CONFIG_FILE"
                    else
                        echo "⚠️  下载 Gitee 配置失败，需要上传"
                        export SKIP_UPLOAD_CONFIG=false
                    fi
                else
                    echo "⚠️  Gitee Release 中没有找到 update_config_gitee.json，需要上传"
                    export SKIP_UPLOAD_CONFIG=false
                fi
            else
                echo "⚠️  无法获取 Gitee Release assets，需要上传"
                export SKIP_UPLOAD_CONFIG=false
            fi
        else
            echo "⚠️  无法获取配置 Release ID，需要上传"
            export SKIP_UPLOAD_CONFIG=false
        fi
    else
        echo "✅ Gitee 配置 Release 不存在，需要上传"
        export SKIP_UPLOAD_CONFIG=false
    fi
    
    echo ""
}

# 上传更新配置到 Gitee（仅上传，不检查）
upload_update_config() {
    echo -e "${BLUE}📤 上传更新配置到 Gitee...${NC}"
    
    # 检查是否需要跳过上传
    if [ "${SKIP_UPLOAD_CONFIG:-false}" = "true" ]; then
        echo -e "${GREEN}✅ 跳过上传更新配置（配置已是最新）${NC}"
        return 0
    fi
    
    GITEE_REPO_OWNER_ENCODED=$(printf '%s' "${GITEE_REPO_OWNER}" | jq -sRr @uri)
    GITEE_REPO_NAME_ENCODED=$(printf '%s' "${GITEE_REPO_NAME}" | jq -sRr @uri)
    CONFIG_RELEASE_TAG="config"
    CONFIG_RELEASE_TAG_ENCODED=$(printf '%s' "${CONFIG_RELEASE_TAG}" | jq -sRr @uri)
    CONFIG_GITEE_FILE="${TEMP_DIR}/config/update_config_gitee.json"
    
    if [ ! -f "$CONFIG_GITEE_FILE" ]; then
        echo -e "${RED}❌ 配置文件不存在: ${CONFIG_GITEE_FILE}${NC}"
        return 1
    fi
    
    # 获取 master 分支的最新 commit SHA
    echo ""
    echo "🔍 获取 master 分支的最新 commit..."
    BRANCH_INFO=$(curl -s -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/branches/master")
    
    MASTER_COMMIT_SHA=$(echo "$BRANCH_INFO" | jq -r '.commit.sha // empty' 2>/dev/null || echo "")
    
    if [ -z "$MASTER_COMMIT_SHA" ] || [ "$MASTER_COMMIT_SHA" == "null" ]; then
        echo -e "${YELLOW}⚠️ 无法获取 master 分支的 commit SHA，使用默认分支${NC}"
        MASTER_COMMIT_SHA="master"
    else
        echo "✅ Master 分支最新 commit: ${MASTER_COMMIT_SHA:0:7}..."
    fi
    
    # 检查配置 Release 是否存在
    echo ""
    echo "🔍 检查配置 Release 是否存在..."
    RELEASE_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${CONFIG_RELEASE_TAG_ENCODED}")
    
    RELEASE_CHECK_HTTP_CODE=$(echo "$RELEASE_CHECK" | tail -n1)
    RELEASE_CHECK_BODY=$(echo "$RELEASE_CHECK" | sed '$d')
    
    if [ "$RELEASE_CHECK_HTTP_CODE" = "200" ]; then
        RELEASE_ID=$(echo "$RELEASE_CHECK_BODY" | jq -r '.id // empty' 2>/dev/null || echo "")
        if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
            echo "✅ Release ${CONFIG_RELEASE_TAG} 已存在 (ID: ${RELEASE_ID})"
            
            # 如果配置也匹配，跳过删除
            if [ "${SKIP_UPLOAD_CONFIG:-false}" = "true" ]; then
                echo "✅ 配置已是最新版本，跳过删除操作"
            else
                echo "🗑️  删除现有配置 Release..."
                
                DELETE_RELEASE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
                    -H "Authorization: token ${GITEE_TOKEN}" \
                    "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}")
                
                DELETE_RELEASE_HTTP_CODE=$(echo "$DELETE_RELEASE_RESPONSE" | tail -n1)
                
                if [ "$DELETE_RELEASE_HTTP_CODE" = "204" ] || [ "$DELETE_RELEASE_HTTP_CODE" = "200" ]; then
                    echo "✅ 已删除现有配置 Release"
                    sleep 2
                fi
            fi
        fi
    fi
    
    # 确保 tag 存在
    echo ""
    echo "🔍 确保 Tag ${CONFIG_RELEASE_TAG} 存在..."
    TAG_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: token ${GITEE_TOKEN}" \
        "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/tags/${CONFIG_RELEASE_TAG_ENCODED}")
    
    TAG_CHECK_HTTP_CODE=$(echo "$TAG_CHECK" | tail -n1)
    
    if [ "$TAG_CHECK_HTTP_CODE" != "200" ]; then
        echo "  Tag 不存在，创建 Tag..."
        CREATE_TAG_BODY=$(echo "{
          \"refs\": \"${MASTER_COMMIT_SHA}\",
          \"tag_name\": \"${CONFIG_RELEASE_TAG}\",
          \"message\": \"Tag for update config release\"
        }" | jq -c .)
        
        CREATE_TAG_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${GITEE_TOKEN}" \
            -d "${CREATE_TAG_BODY}" \
            "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/tags")
        
        CREATE_TAG_HTTP_CODE=$(echo "$CREATE_TAG_RESPONSE" | tail -n1)
        
        if [ "$CREATE_TAG_HTTP_CODE" = "200" ] || [ "$CREATE_TAG_HTTP_CODE" = "201" ]; then
            echo "✅ Tag ${CONFIG_RELEASE_TAG} 创建成功"
        fi
    else
        echo "✅ Tag ${CONFIG_RELEASE_TAG} 已存在"
    fi
    
    # 创建新 Release（仅在需要上传时）
    if [ "${SKIP_UPLOAD_CONFIG:-false}" = "true" ]; then
        echo ""
        echo "✅ 配置 Release 已存在且配置一致，跳过创建和上传"
        return 0
    fi
    
    echo ""
    echo "📝 创建配置 Release..."
    
    RELEASE_NAME="UpdateConfig"
    RELEASE_BODY="This release contains the update configuration file for the application."
    
    CREATE_RELEASE_BODY=$(echo "{
      \"tag_name\": \"${CONFIG_RELEASE_TAG}\",
      \"name\": \"${RELEASE_NAME}\",
      \"body\": \"${RELEASE_BODY}\",
      \"target_commitish\": \"${MASTER_COMMIT_SHA}\",
      \"prerelease\": false
    }" | jq -c .)
    
    CREATE_RELEASE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${GITEE_TOKEN}" \
        -d "${CREATE_RELEASE_BODY}" \
        "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases")
    
    CREATE_RELEASE_HTTP_CODE=$(echo "$CREATE_RELEASE_RESPONSE" | tail -n1)
    CREATE_RELEASE_BODY_RESPONSE=$(echo "$CREATE_RELEASE_RESPONSE" | sed '$d')
    
    if [ "$CREATE_RELEASE_HTTP_CODE" = "200" ] || [ "$CREATE_RELEASE_HTTP_CODE" = "201" ]; then
        RELEASE_ID=$(echo "$CREATE_RELEASE_BODY_RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")
        if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" == "null" ]; then
            echo -e "${RED}❌ 无法从响应中获取 Release ID${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Release 创建成功 (ID: ${RELEASE_ID})${NC}"
    else
        ERROR_MSG=$(echo "$CREATE_RELEASE_BODY_RESPONSE" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "$CREATE_RELEASE_BODY_RESPONSE")
        # 如果 Release 已存在，可能是之前的删除操作还没完成，尝试获取现有的 Release ID
        if echo "$ERROR_MSG" | grep -qi "已存在\|already exists\|duplicate"; then
            echo "⚠️  Release 已存在，尝试获取现有 Release ID..."
            RELEASE_CHECK=$(curl -s -w "\n%{http_code}" -X GET \
                -H "Authorization: token ${GITEE_TOKEN}" \
                "https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/tags/${CONFIG_RELEASE_TAG_ENCODED}")
            RELEASE_CHECK_HTTP_CODE=$(echo "$RELEASE_CHECK" | tail -n1)
            RELEASE_CHECK_BODY=$(echo "$RELEASE_CHECK" | sed '$d')
            if [ "$RELEASE_CHECK_HTTP_CODE" = "200" ]; then
                RELEASE_ID=$(echo "$RELEASE_CHECK_BODY" | jq -r '.id // empty' 2>/dev/null || echo "")
                if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
                    echo "✅ 找到现有 Release (ID: ${RELEASE_ID})"
                else
                    echo -e "${RED}❌ Release 创建失败且无法获取现有 Release ID${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}❌ Release 创建失败 (HTTP ${CREATE_RELEASE_HTTP_CODE})${NC}"
                echo "  错误信息: ${ERROR_MSG}"
                exit 1
            fi
        else
            echo -e "${RED}❌ Release 创建失败 (HTTP ${CREATE_RELEASE_HTTP_CODE})${NC}"
            echo "  错误信息: ${ERROR_MSG}"
            exit 1
        fi
    fi
    
    # 上传配置文件到 Release
    echo ""
    echo "📤 上传配置文件到 Release..."
    
    UPLOAD_API_URL="https://gitee.com/api/v5/repos/${GITEE_REPO_OWNER_ENCODED}/${GITEE_REPO_NAME_ENCODED}/releases/${RELEASE_ID}/attach_files"
    
    MAX_RETRIES=3
    RETRY_DELAY=5
    RETRY_COUNT=0
    UPLOAD_SUCCESS_FLAG=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo "  ⏳ 重试第 ${RETRY_COUNT}/${MAX_RETRIES} 次（等待 ${RETRY_DELAY} 秒后重试）..."
            sleep $RETRY_DELAY
        fi
        
        echo "  📤 开始上传..."
        
        TEMP_RESPONSE_FILE=$(mktemp)
        TEMP_HTTP_CODE_FILE=$(mktemp)
        
        curl --progress-bar --show-error \
            --connect-timeout 30 \
            --max-time 600 \
            --retry 2 \
            --retry-delay 3 \
            --retry-connrefused \
            -w "%{http_code}" \
            -o "${TEMP_RESPONSE_FILE}" \
            -X POST \
            -H "Authorization: token ${GITEE_TOKEN}" \
            -F "file=@${CONFIG_GITEE_FILE}" \
            -F "name=update_config_gitee.json" \
            "${UPLOAD_API_URL}" \
            > "${TEMP_HTTP_CODE_FILE}"
        
        UPLOAD_HTTP_CODE=$(cat "${TEMP_HTTP_CODE_FILE}" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "")
        UPLOAD_BODY_RESPONSE=$(cat "${TEMP_RESPONSE_FILE}" 2>/dev/null || echo "")
        
        rm -f "${TEMP_RESPONSE_FILE}" "${TEMP_HTTP_CODE_FILE}"
        
        if [ "$UPLOAD_HTTP_CODE" = "200" ] || [ "$UPLOAD_HTTP_CODE" = "201" ]; then
            echo -e "${GREEN}✅ 文件上传成功${NC}"
            UPLOAD_SUCCESS_FLAG=true
            break
        else
            ERROR_MSG=$(echo "$UPLOAD_BODY_RESPONSE" | jq -r '.message // .error // "未知错误"' 2>/dev/null || echo "HTTP ${UPLOAD_HTTP_CODE}")
            echo "  ❌ 上传失败: ${ERROR_MSG}"
            
            if echo "$UPLOAD_HTTP_CODE" | grep -qE "^(429|500|502|503|504)$"; then
                RETRY_COUNT=$((RETRY_COUNT + 1))
            elif [ "$UPLOAD_HTTP_CODE" -eq 401 ] || [ "$UPLOAD_HTTP_CODE" -eq 403 ]; then
                break
            elif [ "$UPLOAD_HTTP_CODE" -eq 404 ]; then
                break
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
            fi
        fi
    done
    
    if [ "$UPLOAD_SUCCESS_FLAG" = false ]; then
        echo -e "${RED}❌ 配置文件上传失败（已重试 ${MAX_RETRIES} 次）${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✅ 更新配置文件已成功同步到 Gitee Release: ${CONFIG_RELEASE_TAG}${NC}"
    echo "  访问 URL: https://gitee.com/${GITEE_REPO}/releases/download/${CONFIG_RELEASE_TAG}/update_config_gitee.json"
    echo ""
}

# 主函数
main() {
    local input_version="$1"
    
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}🚀 Gitee 同步脚本${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # ==========================================
    # 第一阶段：初始化和准备
    # ==========================================
    check_env
    extract_release_tag "$input_version"
    get_release_info
    extract_version_from_build_tag
    
    # ==========================================
    # 第二阶段：检查阶段（所有检查操作）
    # ==========================================
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}🔍 检查阶段${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 1. 检查文件 hash（构建产物）
    #    这个函数会下载 GitHub 和 Gitee 的 file_hashes.json 进行比较
    #    如果 hash 匹配，设置 SKIP_DOWNLOAD_ASSETS=true 和 SKIP_UPLOAD_ASSETS=true
    check_hashes_before_download
    
    # 2. 下载构建产物（如果需要）
    #    注意：即使 hash 匹配，也需要下载文件才能生成配置文件
    #    但如果 hash 匹配，后续不会上传这些文件
    if [ "${SKIP_DOWNLOAD_ASSETS:-false}" = "false" ]; then
        download_assets
    else
        # Hash 匹配，跳过下载，但需要确保文件已存在（用于生成配置）
        # 如果文件不存在，仍然需要下载
        RELEASE_ASSETS_DIR="${TEMP_DIR}/release-assets"
        MACOS_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "HelloKnightRCC_macos_*.zip" 2>/dev/null | head -1)
        WINDOWS_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "HelloKnightRCC_windows_*.zip" 2>/dev/null | head -1)
        ANDROID_FILE=$(find "${RELEASE_ASSETS_DIR}" -name "helloknightrcc_server_android_*.zip" 2>/dev/null | head -1)
        
        if [ -z "$MACOS_FILE" ] || [ -z "$WINDOWS_FILE" ] || [ -z "$ANDROID_FILE" ]; then
            echo -e "${YELLOW}⚠️  Hash 匹配但文件不存在，需要下载文件以生成配置${NC}"
            export SKIP_DOWNLOAD_ASSETS=false
            download_assets
        else
            echo -e "${GREEN}✅ Hash 匹配且文件已存在，跳过下载${NC}"
        fi
    fi
    
    # 3. 生成更新配置文件
    #    需要文件存在才能生成配置
    generate_update_config_file
    
    # 4. 检查配置 hash
    #    比较本地生成的配置和 Gitee 上的配置
    #    如果匹配，设置 SKIP_UPLOAD_CONFIG=true
    check_config_before_upload
    
    # ==========================================
    # 第三阶段：上传阶段（所有上传操作）
    # ==========================================
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}📤 上传阶段${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 1. 创建 Gitee Release（如果需要）
    #    如果 SKIP_UPLOAD_ASSETS=true，跳过删除和创建 Release
    create_gitee_release
    
    # 2. 上传构建产物（如果需要）
    #    如果 SKIP_UPLOAD_ASSETS=true，跳过上传
    upload_assets_to_gitee
    
    # 3. 上传更新配置（如果需要）
    #    如果 SKIP_UPLOAD_CONFIG=true，跳过上传
    upload_update_config
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ 同步完成！${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 执行主函数
main "$@"

