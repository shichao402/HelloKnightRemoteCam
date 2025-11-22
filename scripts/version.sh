#!/bin/bash

# 版本号管理脚本
# 用途：管理项目版本号，不依赖外部平台（Git、CI/CD等）
# 版本号存储在根目录的 VERSION.yaml 文件中（YAML格式）
# 客户端和服务器使用独立的版本号

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION.yaml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查 Python3 是否可用
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}错误: 需要 Python3 来解析 YAML 文件${NC}" >&2
    exit 1
fi

# 检查 PyYAML 是否安装
if ! python3 -c "import yaml" 2>/dev/null; then
    echo -e "${YELLOW}警告: PyYAML 未安装，正在尝试安装...${NC}" >&2
    if python3 -m pip install --user pyyaml 2>/dev/null; then
        echo -e "${GREEN}PyYAML 安装成功${NC}"
    else
        echo -e "${RED}错误: 无法安装 PyYAML${NC}" >&2
        echo "请手动安装: pip3 install pyyaml 或 python3 -m pip install pyyaml" >&2
        exit 1
    fi
fi

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

# 使用 Python 读取 YAML 文件中的配置值
read_yaml_value() {
    local key_path=$1
    python3 <<EOF
import yaml
import sys

try:
    with open('$VERSION_FILE', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    
    # 支持嵌套路径，如 client.version 或 compatibility.min_client_version
    keys = '$key_path'.split('.')
    value = data
    for key in keys:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            sys.exit(1)
    
    if value is not None:
        print(value)
except Exception as e:
    sys.exit(1)
EOF
}

# 使用 Python 写入 YAML 文件中的配置值
write_yaml_value() {
    local key_path=$1
    local value=$2
    python3 <<EOF
import yaml
import sys

try:
    # 读取现有文件
    with open('$VERSION_FILE', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    
    # 支持嵌套路径
    keys = '$key_path'.split('.')
    current = data
    for i, key in enumerate(keys[:-1]):
        if key not in current:
            current[key] = {}
        current = current[key]
    
    # 设置值
    current[keys[-1]] = '$value'
    
    # 写回文件，保持格式
    with open('$VERSION_FILE', 'w', encoding='utf-8') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# 读取VERSION文件中的配置值（兼容旧格式和新格式）
read_version_config() {
    local key=$1
    
    # 优先使用 YAML 格式
    if [ -f "$VERSION_FILE" ]; then
        case "$key" in
            CLIENT_VERSION)
                read_yaml_value "client.version" 2>/dev/null || echo ""
                ;;
            SERVER_VERSION)
                read_yaml_value "server.version" 2>/dev/null || echo ""
                ;;
            MIN_CLIENT_VERSION)
                read_yaml_value "compatibility.min_client_version" 2>/dev/null || echo ""
                ;;
            MIN_SERVER_VERSION)
                read_yaml_value "compatibility.min_server_version" 2>/dev/null || echo ""
                ;;
            *)
                echo ""
                ;;
        esac
    else
        # 兼容旧的 VERSION 文件格式
        local old_file="$PROJECT_ROOT/VERSION"
        if [ -f "$old_file" ]; then
            grep "^${key}=" "$old_file" | head -1 | cut -d'=' -f2 | tr -d '[:space:]'
        else
            echo -e "${RED}错误: VERSION.yaml 文件不存在${NC}" >&2
            exit 1
        fi
    fi
}

# 写入VERSION文件中的配置值
write_version_config() {
    local key=$1
    local value=$2
    
    if [ ! -f "$VERSION_FILE" ]; then
        echo -e "${RED}错误: VERSION.yaml 文件不存在${NC}" >&2
        exit 1
    fi
    
    case "$key" in
        CLIENT_VERSION)
            write_yaml_value "client.version" "$value"
            ;;
        SERVER_VERSION)
            write_yaml_value "server.version" "$value"
            ;;
        MIN_CLIENT_VERSION)
            write_yaml_value "compatibility.min_client_version" "$value"
            ;;
        MIN_SERVER_VERSION)
            write_yaml_value "compatibility.min_server_version" "$value"
            ;;
        *)
            echo -e "${RED}错误: 未知的配置键: $key${NC}" >&2
            exit 1
            ;;
    esac
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
    
    # 复制VERSION.yaml文件到assets目录（保持YAML格式）
    if [ -f "$VERSION_FILE" ]; then
        cp "$VERSION_FILE" "$assets_dir/VERSION.yaml"
        echo -e "${GREEN}已复制VERSION.yaml文件到 server/assets/VERSION.yaml${NC}"
    else
        # 兼容旧格式
        local old_file="$PROJECT_ROOT/VERSION"
        if [ -f "$old_file" ]; then
            cp "$old_file" "$assets_dir/VERSION"
            echo -e "${GREEN}已复制VERSION文件（旧格式）到 server/assets/VERSION${NC}"
        else
            echo -e "${YELLOW}警告: VERSION.yaml文件不存在，无法复制到assets${NC}"
        fi
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
