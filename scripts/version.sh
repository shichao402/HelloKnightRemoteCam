#!/bin/bash

# 版本号管理脚本
# 用途：管理项目版本号，不依赖外部平台（Git、CI/CD等）
# 版本号存储在根目录的 VERSION 文件中
# 客户端和服务器使用独立的版本号

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "版本号管理工具"
    echo ""
    echo "用法:"
    echo "  $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  get [client|server]          显示版本号（默认显示所有）"
    echo "  set client <version>          设置客户端版本号"
    echo "  set server <version>          设置服务器版本号"
    echo "  bump client [major|minor|patch|build]  递增客户端版本号"
    echo "  bump server [major|minor|patch|build]  递增服务器版本号"
    echo "  sync [client|server]          同步版本号到 pubspec.yaml（默认同步所有）"
    echo "  set-min-version client <version>  设置服务器要求的最小客户端版本"
    echo "  set-min-version server <version>  设置客户端要求的最小服务器版本"
    echo "  help                          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 get                        # 显示所有版本号"
    echo "  $0 get client                  # 显示客户端版本号"
    echo "  $0 set client 1.2.3+10        # 设置客户端版本号为 1.2.3+10"
    echo "  $0 bump client minor           # 客户端次版本号+1"
    echo "  $0 sync                        # 同步所有版本号到 pubspec.yaml"
    echo "  $0 sync client                 # 只同步客户端版本号"
}

# 读取VERSION文件中的配置值
read_version_config() {
    local key=$1
    if [ ! -f "$VERSION_FILE" ]; then
        echo -e "${RED}错误: VERSION 文件不存在${NC}" >&2
        exit 1
    fi
    
    # 读取配置值（忽略注释和空行）
    grep "^${key}=" "$VERSION_FILE" | head -1 | cut -d'=' -f2 | tr -d '[:space:]'
}

# 写入VERSION文件中的配置值
write_version_config() {
    local key=$1
    local value=$2
    
    if [ ! -f "$VERSION_FILE" ]; then
        echo -e "${RED}错误: VERSION 文件不存在${NC}" >&2
        exit 1
    fi
    
    # 如果配置已存在，更新它；否则追加
    if grep -q "^${key}=" "$VERSION_FILE"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$VERSION_FILE"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$VERSION_FILE"
        fi
    else
        echo "${key}=${value}" >> "$VERSION_FILE"
    fi
}

# 获取版本号
get_version() {
    local target=${1:-all}
    
    case "$target" in
        client)
            read_version_config "CLIENT_VERSION"
            ;;
        server)
            read_version_config "SERVER_VERSION"
            ;;
        all|*)
            echo -e "${BLUE}客户端版本:${NC} $(read_version_config 'CLIENT_VERSION')"
            echo -e "${BLUE}服务器版本:${NC} $(read_version_config 'SERVER_VERSION')"
            echo -e "${BLUE}最小客户端版本:${NC} $(read_version_config 'MIN_CLIENT_VERSION')"
            echo -e "${BLUE}最小服务器版本:${NC} $(read_version_config 'MIN_SERVER_VERSION')"
            ;;
    esac
}

# 验证版本号格式
validate_version() {
    local version=$1
    if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
        echo -e "${RED}错误: 版本号格式不正确${NC}" >&2
        echo "正确格式: x.y.z+build 或 x.y.z"
        echo "示例: 1.0.0+1 或 1.0.0"
        exit 1
    fi
}

# 设置版本号
set_version() {
    local target=$1
    local new_version=$2
    
    if [ -z "$target" ] || [ -z "$new_version" ]; then
        echo -e "${RED}错误: 请指定目标（client/server）和版本号${NC}" >&2
        show_help
        exit 1
    fi
    
    validate_version "$new_version"
    
    case "$target" in
        client)
            write_version_config "CLIENT_VERSION" "$new_version"
            echo -e "${GREEN}客户端版本号已设置为: $new_version${NC}"
            ;;
        server)
            write_version_config "SERVER_VERSION" "$new_version"
            echo -e "${GREEN}服务器版本号已设置为: $new_version${NC}"
            ;;
        *)
            echo -e "${RED}错误: 未知目标: $target${NC}" >&2
            echo "可用目标: client, server"
            exit 1
            ;;
    esac
}

# 设置最小版本号
set_min_version() {
    local target=$1
    local min_version=$2
    
    if [ -z "$target" ] || [ -z "$min_version" ]; then
        echo -e "${RED}错误: 请指定目标（client/server）和最小版本号${NC}" >&2
        show_help
        exit 1
    fi
    
    # 最小版本号不需要构建号
    if ! [[ $min_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误: 最小版本号格式不正确${NC}" >&2
        echo "正确格式: x.y.z（不含构建号）"
        echo "示例: 1.0.0"
        exit 1
    fi
    
    case "$target" in
        client)
            write_version_config "MIN_CLIENT_VERSION" "$min_version"
            echo -e "${GREEN}服务器要求的最小客户端版本已设置为: $min_version${NC}"
            ;;
        server)
            write_version_config "MIN_SERVER_VERSION" "$min_version"
            echo -e "${GREEN}客户端要求的最小服务器版本已设置为: $min_version${NC}"
            ;;
        *)
            echo -e "${RED}错误: 未知目标: $target${NC}" >&2
            echo "可用目标: client, server"
            exit 1
            ;;
    esac
}

# 解析版本号
parse_version() {
    local version=$1
    local version_part=$(echo "$version" | sed 's/+.*//')
    local build_part=$(echo "$version" | sed 's/.*+//')
    
    if [ "$version" == "$version_part" ]; then
        build_part="1"
    fi
    
    echo "$version_part|$build_part"
}

# 递增版本号
bump_version() {
    local target=$1
    local bump_type=$2
    
    if [ -z "$target" ] || [ -z "$bump_type" ]; then
        echo -e "${RED}错误: 请指定目标（client/server）和递增类型${NC}" >&2
        show_help
        exit 1
    fi
    
    local current_version
    case "$target" in
        client)
            current_version=$(read_version_config "CLIENT_VERSION")
            ;;
        server)
            current_version=$(read_version_config "SERVER_VERSION")
            ;;
        *)
            echo -e "${RED}错误: 未知目标: $target${NC}" >&2
            exit 1
            ;;
    esac
    
    local parsed=$(parse_version "$current_version")
    local version_part=$(echo "$parsed" | cut -d'|' -f1)
    local build_part=$(echo "$parsed" | cut -d'|' -f2)
    
    local new_version
    case "$bump_type" in
        major)
            local major=$(echo "$version_part" | cut -d'.' -f1)
            major=$((major + 1))
            new_version="${major}.0.0+${build_part}"
            ;;
        minor)
            local major=$(echo "$version_part" | cut -d'.' -f1)
            local minor=$(echo "$version_part" | cut -d'.' -f2)
            minor=$((minor + 1))
            new_version="${major}.${minor}.0+${build_part}"
            ;;
        patch)
            local major=$(echo "$version_part" | cut -d'.' -f1)
            local minor=$(echo "$version_part" | cut -d'.' -f2)
            local patch=$(echo "$version_part" | cut -d'.' -f3)
            patch=$((patch + 1))
            new_version="${major}.${minor}.${patch}+${build_part}"
            ;;
        build)
            build_part=$((build_part + 1))
            new_version="${version_part}+${build_part}"
            ;;
        *)
            echo -e "${RED}错误: 未知的递增类型: $bump_type${NC}" >&2
            echo "可用类型: major, minor, patch, build"
            exit 1
            ;;
    esac
    
    set_version "$target" "$new_version"
    echo -e "${GREEN}${target}版本号已递增: $new_version${NC}"
}

# 复制VERSION文件到服务器assets目录（用于打包到APK）
copy_version_to_assets() {
    local assets_dir="$PROJECT_ROOT/server/assets"
    
    # 确保assets目录存在
    mkdir -p "$assets_dir"
    
    # 复制VERSION文件到assets目录
    if [ -f "$VERSION_FILE" ]; then
        cp "$VERSION_FILE" "$assets_dir/VERSION"
        echo -e "${GREEN}已复制VERSION文件到 server/assets/VERSION${NC}"
    else
        echo -e "${YELLOW}警告: VERSION文件不存在，无法复制到assets${NC}"
    fi
}

# 同步版本号到 pubspec.yaml
sync_version() {
    local target=${1:-all}
    
    case "$target" in
        client)
            local version=$(read_version_config "CLIENT_VERSION")
            local version_part=$(echo "$version" | sed 's/+.*//')
            local build_part=$(echo "$version" | sed 's/.*+//')
            
            if [ "$version" == "$version_part" ]; then
                build_part="1"
            fi
            
            local full_version="${version_part}+${build_part}"
            
            if [ -f "$PROJECT_ROOT/client/pubspec.yaml" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s/^version:.*/version: $full_version/" "$PROJECT_ROOT/client/pubspec.yaml"
                else
                    sed -i "s/^version:.*/version: $full_version/" "$PROJECT_ROOT/client/pubspec.yaml"
                fi
                echo -e "${GREEN}已同步客户端版本号到 client/pubspec.yaml: $full_version${NC}"
            fi
            ;;
        server)
            local version=$(read_version_config "SERVER_VERSION")
            local version_part=$(echo "$version" | sed 's/+.*//')
            local build_part=$(echo "$version" | sed 's/.*+//')
            
            if [ "$version" == "$version_part" ]; then
                build_part="1"
            fi
            
            local full_version="${version_part}+${build_part}"
            
            if [ -f "$PROJECT_ROOT/server/pubspec.yaml" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s/^version:.*/version: $full_version/" "$PROJECT_ROOT/server/pubspec.yaml"
                else
                    sed -i "s/^version:.*/version: $full_version/" "$PROJECT_ROOT/server/pubspec.yaml"
                fi
                echo -e "${GREEN}已同步服务器版本号到 server/pubspec.yaml: $full_version${NC}"
            fi
            
            # 复制VERSION文件到assets目录（用于打包到APK）
            copy_version_to_assets
            ;;
        all|*)
            sync_version "client"
            sync_version "server"
            ;;
    esac
}

# 主逻辑
case "${1:-get}" in
    get)
        get_version "${2:-all}"
        ;;
    set)
        if [ "$2" == "client" ] || [ "$2" == "server" ]; then
            set_version "$2" "$3"
        elif [ "$2" == "min-version" ]; then
            set_min_version "$3" "$4"
        else
            echo -e "${RED}错误: 请指定目标（client/server）${NC}" >&2
            show_help
            exit 1
        fi
        ;;
    set-min-version)
        set_min_version "$2" "$3"
        ;;
    bump)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}错误: 请指定目标（client/server）和递增类型${NC}" >&2
            show_help
            exit 1
        fi
        bump_version "$2" "$3"
        ;;
    sync)
        sync_version "${2:-all}"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}错误: 未知命令: $1${NC}" >&2
        show_help
        exit 1
        ;;
esac
