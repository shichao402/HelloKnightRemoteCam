#!/bin/bash

# 版本号管理脚本（包装器）
# 所有版本号读写逻辑统一在 version_manager.py 中实现
# 此脚本仅作为命令行接口的包装器

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_MANAGER="$SCRIPT_DIR/lib/version_manager.py"

# 检查 Python3 是否可用
if ! command -v python3 &> /dev/null; then
    echo "错误: 需要 Python3 来运行版本管理工具" >&2
    exit 1
fi

# 检查 PyYAML 是否安装
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "警告: PyYAML 未安装，正在尝试安装..." >&2
    if python3 -m pip install --user pyyaml 2>/dev/null; then
        echo "PyYAML 安装成功"
    else
        echo "错误: 无法安装 PyYAML" >&2
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

# 主逻辑：直接调用 Python 模块
case "${1:-get}" in
    get)
        python3 "$VERSION_MANAGER" get "${2:-all}"
        ;;
    set)
        if [ "$2" == "client" ] || [ "$2" == "server" ]; then
            python3 "$VERSION_MANAGER" set "$2" "$3"
        elif [ "$2" == "min-version" ]; then
            python3 "$VERSION_MANAGER" set-min-version "$3" "$4"
        else
            echo "错误: 请指定目标（client/server）" >&2
            show_help
            exit 1
        fi
        ;;
    set-min-version)
        python3 "$VERSION_MANAGER" set-min-version "$2" "$3"
        ;;
    bump)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "错误: 请指定目标（client/server）和递增类型" >&2
            show_help
            exit 1
        fi
        python3 "$VERSION_MANAGER" bump "$2" "$3"
        ;;
    sync)
        python3 "$VERSION_MANAGER" sync "${2:-all}"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "错误: 未知命令: $1" >&2
        show_help
        exit 1
        ;;
esac
