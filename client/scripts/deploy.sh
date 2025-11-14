#!/bin/bash

# 完整部署脚本（macOS/Linux）- 组合调用各个模块

set -e

# 解析命令行参数
AUTO_START=false
BUILD_MODE="debug"
BUILD_TYPE="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_START=true
            shift
            ;;
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --debug)
            BUILD_MODE="debug"
            shift
            ;;
        --macos)
            BUILD_TYPE="macos"
            shift
            ;;
        --windows)
            BUILD_TYPE="windows"
            shift
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [-y|--yes] [--release|--debug] [--macos|--windows]"
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "开始部署 Client ($BUILD_TYPE, $BUILD_MODE)"
echo "========================================"

# 1. 终止已有进程
if [ "$BUILD_TYPE" = "macos" ]; then
    "$SCRIPT_DIR/kill_process.sh"
fi

# 2. 构建
"$SCRIPT_DIR/build.sh" --$BUILD_MODE --$BUILD_TYPE

# 3. 启动应用
if [ "$AUTO_START" = true ]; then
    "$SCRIPT_DIR/start.sh" "$BUILD_MODE" "$BUILD_TYPE"
else
    read -p "是否启动应用? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/start.sh" "$BUILD_MODE" "$BUILD_TYPE"
    fi
fi

echo "========================================"
echo "部署完成！"
echo "========================================"

