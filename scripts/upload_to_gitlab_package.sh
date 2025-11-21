#!/bin/bash

# GitLab Package 上传脚本
# 用途：将构建产物上传到 GitLab Generic Package Registry
# 使用方法: ./scripts/upload_to_gitlab_package.sh [--client|--server] [--platform PLATFORM] [--version VERSION]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
TARGET=""
PLATFORM=""
VERSION=""
BUILD_MODE="release"

# 从环境变量读取配置（如果未设置，脚本会提示）
GITLAB_URL="${GITLAB_URL:-}"
GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --client)
            TARGET="client"
            shift
            ;;
        --server)
            TARGET="server"
            shift
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --debug)
            BUILD_MODE="debug"
            shift
            ;;
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --help|-h)
            echo "GitLab Package 上传脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --client              上传客户端构建产物"
            echo "  --server              上传服务器构建产物"
            echo "  --platform PLATFORM   平台 (android/macos/windows)"
            echo "  --version VERSION     版本号 (例如: 1.0.0+1)"
            echo "  --debug               使用debug构建"
            echo "  --release             使用release构建 (默认)"
            echo ""
            echo "环境变量:"
            echo "  GITLAB_URL            GitLab实例URL (例如: https://gitlab.com)"
            echo "  GITLAB_PROJECT_ID     GitLab项目ID或路径"
            echo "  GITLAB_TOKEN          GitLab访问令牌 (需要api权限)"
            echo ""
            echo "示例:"
            echo "  $0 --client --platform macos --version 1.0.0+1"
            echo "  $0 --server --platform android --version 1.0.0+1"
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# 检查必需参数
if [ -z "$TARGET" ]; then
    echo -e "${RED}错误: 必须指定 --client 或 --server${NC}" >&2
    exit 1
fi

if [ -z "$PLATFORM" ]; then
    echo -e "${RED}错误: 必须指定 --platform${NC}" >&2
    exit 1
fi

# 获取版本号
if [ -z "$VERSION" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    VERSION_SCRIPT="$PROJECT_ROOT/scripts/version.sh"
    
    if [ -f "$VERSION_SCRIPT" ]; then
        if [ "$TARGET" = "client" ]; then
            VERSION=$(bash "$VERSION_SCRIPT" get client)
        else
            VERSION=$(bash "$VERSION_SCRIPT" get server)
        fi
        echo -e "${BLUE}从VERSION文件读取版本号: $VERSION${NC}"
    else
        echo -e "${RED}错误: 未指定版本号且无法读取VERSION文件${NC}" >&2
        exit 1
    fi
fi

# 提取版本号部分（去掉构建号）
VERSION_NUMBER=$(echo "$VERSION" | sed 's/+.*//')
PACKAGE_VERSION="$VERSION_NUMBER"

# 检查环境变量
if [ -z "$GITLAB_URL" ]; then
    echo -e "${YELLOW}警告: GITLAB_URL 未设置，请输入 GitLab 实例 URL:${NC}"
    read -r GITLAB_URL
fi

if [ -z "$GITLAB_PROJECT_ID" ]; then
    echo -e "${YELLOW}警告: GITLAB_PROJECT_ID 未设置，请输入项目 ID 或路径:${NC}"
    read -r GITLAB_PROJECT_ID
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo -e "${YELLOW}警告: GITLAB_TOKEN 未设置，请输入访问令牌:${NC}"
    read -r GITLAB_TOKEN
fi

# 确定构建产物路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILE_PATH=""
FILE_NAME=""
PACKAGE_NAME=""

if [ "$TARGET" = "client" ]; then
    PACKAGE_NAME="helloknightrcc-client"
    
    case "$PLATFORM" in
        macos)
            BUILD_MODE_CAPITALIZED="$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"
            APP_PATH="$PROJECT_ROOT/client/build/macos/Build/Products/$BUILD_MODE_CAPITALIZED/HelloKnightRCC.app"
            
            if [ ! -d "$APP_PATH" ]; then
                echo -e "${RED}错误: 应用未找到: $APP_PATH${NC}" >&2
                echo -e "${YELLOW}提示: 请先运行构建脚本${NC}"
                exit 1
            fi
            
            # 创建临时zip文件
            TEMP_DIR=$(mktemp -d)
            ZIP_FILE="$TEMP_DIR/HelloKnightRCC-${VERSION_NUMBER}-macos.zip"
            cd "$(dirname "$APP_PATH")"
            zip -r "$ZIP_FILE" "HelloKnightRCC.app" > /dev/null
            FILE_PATH="$ZIP_FILE"
            FILE_NAME="HelloKnightRCC-${VERSION_NUMBER}-macos.zip"
            ;;
        windows)
            BUILD_MODE_CAPITALIZED="$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"
            BUILD_DIR="$PROJECT_ROOT/client/build/windows/x64/runner/$BUILD_MODE_CAPITALIZED"
            
            if [ ! -d "$BUILD_DIR" ]; then
                echo -e "${RED}错误: 构建目录未找到: $BUILD_DIR${NC}" >&2
                echo -e "${YELLOW}提示: 请先运行构建脚本${NC}"
                exit 1
            fi
            
            # 创建临时zip文件
            TEMP_DIR=$(mktemp -d)
            ZIP_FILE="$TEMP_DIR/HelloKnightRCC-${VERSION_NUMBER}-windows.zip"
            cd "$BUILD_DIR"
            zip -r "$ZIP_FILE" . > /dev/null
            FILE_PATH="$ZIP_FILE"
            FILE_NAME="HelloKnightRCC-${VERSION_NUMBER}-windows.zip"
            ;;
        *)
            echo -e "${RED}错误: 不支持的客户端平台: $PLATFORM${NC}" >&2
            echo "支持的平台: macos, windows"
            exit 1
            ;;
    esac
elif [ "$TARGET" = "server" ]; then
    PACKAGE_NAME="helloknightrcc-server"
    
    case "$PLATFORM" in
        android)
            if [ "$BUILD_MODE" = "release" ]; then
                APK_PATH="$PROJECT_ROOT/server/build/app/outputs/flutter-apk/app-release.apk"
            else
                APK_PATH="$PROJECT_ROOT/server/build/app/outputs/flutter-apk/app-debug.apk"
            fi
            
            if [ ! -f "$APK_PATH" ]; then
                echo -e "${RED}错误: APK 文件未找到: $APK_PATH${NC}" >&2
                echo -e "${YELLOW}提示: 请先运行构建脚本${NC}"
                exit 1
            fi
            
            FILE_PATH="$APK_PATH"
            FILE_NAME="HelloKnightRCC-Server-${VERSION_NUMBER}.apk"
            ;;
        *)
            echo -e "${RED}错误: 不支持的服务器平台: $PLATFORM${NC}" >&2
            echo "支持的平台: android"
            exit 1
            ;;
    esac
fi

# 检查文件是否存在
if [ ! -f "$FILE_PATH" ] && [ ! -d "$FILE_PATH" ]; then
    echo -e "${RED}错误: 文件未找到: $FILE_PATH${NC}" >&2
    exit 1
fi

# 构建上传URL
# GitLab Generic Package API格式:
# PUT /projects/:id/packages/generic/:package_name/:package_version/:file_name
UPLOAD_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${PACKAGE_VERSION}/${FILE_NAME}"

echo "========================================"
echo "上传到 GitLab Package Registry"
echo "========================================"
echo "目标: $TARGET"
echo "平台: $PLATFORM"
echo "版本: $PACKAGE_VERSION"
echo "文件: $FILE_NAME"
echo "路径: $FILE_PATH"
echo "URL: $UPLOAD_URL"
echo "========================================"

# 上传文件
if [ -f "$FILE_PATH" ]; then
    # 普通文件
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        --request PUT \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --upload-file "$FILE_PATH" \
        "$UPLOAD_URL")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo -e "${GREEN}✓ 上传成功！${NC}"
        
        # 构建下载URL
        DOWNLOAD_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${PACKAGE_VERSION}/${FILE_NAME}"
        echo -e "${GREEN}下载URL: ${DOWNLOAD_URL}${NC}"
        
        # 清理临时文件
        if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
            rm -rf "$TEMP_DIR"
        fi
        
        exit 0
    else
        echo -e "${RED}✗ 上传失败 (HTTP $HTTP_CODE)${NC}"
        echo "响应: $BODY"
        
        # 清理临时文件
        if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
            rm -rf "$TEMP_DIR"
        fi
        
        exit 1
    fi
else
    echo -e "${RED}错误: 文件路径无效${NC}" >&2
    exit 1
fi

