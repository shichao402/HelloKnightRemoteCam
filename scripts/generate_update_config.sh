#!/bin/bash

# 更新配置列表生成脚本
# 用途：生成包含所有平台下载URL的JSON更新配置文件
# 使用方法: ./scripts/generate_update_config.sh [--output OUTPUT_FILE] [--gitlab-url URL] [--project-id ID]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
OUTPUT_FILE=""
GITLAB_URL="${GITLAB_URL:-}"
GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --gitlab-url)
            GITLAB_URL="$2"
            shift 2
            ;;
        --project-id)
            GITLAB_PROJECT_ID="$2"
            shift 2
            ;;
        --help|-h)
            echo "更新配置列表生成脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --output FILE         输出文件路径 (默认: update_config.json)"
            echo "  --gitlab-url URL      GitLab实例URL"
            echo "  --project-id ID       GitLab项目ID或路径"
            echo ""
            echo "环境变量:"
            echo "  GITLAB_URL            GitLab实例URL"
            echo "  GITLAB_PROJECT_ID     GitLab项目ID或路径"
            echo ""
            echo "示例:"
            echo "  $0 --output update_config.json --gitlab-url https://gitlab.com --project-id 123"
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# 检查环境变量
if [ -z "$GITLAB_URL" ]; then
    echo -e "${YELLOW}警告: GITLAB_URL 未设置，请输入 GitLab 实例 URL:${NC}"
    read -r GITLAB_URL
fi

if [ -z "$GITLAB_PROJECT_ID" ]; then
    echo -e "${YELLOW}警告: GITLAB_PROJECT_ID 未设置，请输入项目 ID 或路径:${NC}"
    read -r GITLAB_PROJECT_ID
fi

# 设置默认输出文件
if [ -z "$OUTPUT_FILE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    OUTPUT_FILE="$PROJECT_ROOT/update_config.json"
fi

# 获取版本号
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_SCRIPT="$PROJECT_ROOT/scripts/version.sh"

if [ ! -f "$VERSION_SCRIPT" ]; then
    echo -e "${RED}错误: 版本号脚本未找到${NC}" >&2
    exit 1
fi

CLIENT_VERSION=$(bash "$VERSION_SCRIPT" get client)
SERVER_VERSION=$(bash "$VERSION_SCRIPT" get server)

CLIENT_VERSION_NUMBER=$(echo "$CLIENT_VERSION" | sed 's/+.*//')
SERVER_VERSION_NUMBER=$(echo "$SERVER_VERSION" | sed 's/+.*//')

echo "========================================"
echo "生成更新配置文件"
echo "========================================"
echo "客户端版本: $CLIENT_VERSION"
echo "服务器版本: $SERVER_VERSION"
echo "输出文件: $OUTPUT_FILE"
echo "========================================"

# 构建下载URL基础路径
BASE_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic"

# 生成JSON配置
JSON_CONFIG=$(cat <<EOF
{
  "client": {
    "version": "$CLIENT_VERSION",
    "versionNumber": "$CLIENT_VERSION_NUMBER",
    "platforms": {
      "macos": {
        "version": "$CLIENT_VERSION",
        "versionNumber": "$CLIENT_VERSION_NUMBER",
        "downloadUrl": "${BASE_URL}/helloknightrcc-client/${CLIENT_VERSION_NUMBER}/HelloKnightRCC-${CLIENT_VERSION_NUMBER}-macos.zip",
        "fileName": "HelloKnightRCC-${CLIENT_VERSION_NUMBER}-macos.zip",
        "fileType": "zip",
        "platform": "macos"
      },
      "windows": {
        "version": "$CLIENT_VERSION",
        "versionNumber": "$CLIENT_VERSION_NUMBER",
        "downloadUrl": "${BASE_URL}/helloknightrcc-client/${CLIENT_VERSION_NUMBER}/HelloKnightRCC-${CLIENT_VERSION_NUMBER}-windows.zip",
        "fileName": "HelloKnightRCC-${CLIENT_VERSION_NUMBER}-windows.zip",
        "fileType": "zip",
        "platform": "windows"
      }
    }
  },
  "server": {
    "version": "$SERVER_VERSION",
    "versionNumber": "$SERVER_VERSION_NUMBER",
    "platforms": {
      "android": {
        "version": "$SERVER_VERSION",
        "versionNumber": "$SERVER_VERSION_NUMBER",
        "downloadUrl": "${BASE_URL}/helloknightrcc-server/${SERVER_VERSION_NUMBER}/HelloKnightRCC-Server-${SERVER_VERSION_NUMBER}.apk",
        "fileName": "HelloKnightRCC-Server-${SERVER_VERSION_NUMBER}.apk",
        "fileType": "apk",
        "platform": "android"
      }
    }
  },
  "updateCheckUrl": "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/files/update_config.json/raw?ref=main",
  "lastUpdated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

# 写入文件
echo "$JSON_CONFIG" > "$OUTPUT_FILE"

echo -e "${GREEN}✓ 更新配置文件已生成: $OUTPUT_FILE${NC}"
echo ""
echo "配置文件内容预览:"
echo "$JSON_CONFIG" | python3 -m json.tool 2>/dev/null || echo "$JSON_CONFIG"

