#!/bin/bash

# 主控端 macOS 部署脚本

set -e

# 解析命令行参数
AUTO_START=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_START=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [-y|--yes]"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "开始构建主控端 macOS 应用"
echo "========================================"

cd "$(dirname "$0")/.."

# 查找Flutter
FLUTTER=""
if command -v flutter &> /dev/null; then
    FLUTTER="flutter"
elif [ -f "$HOME/development/flutter/bin/flutter" ]; then
    FLUTTER="$HOME/development/flutter/bin/flutter"
elif [ -f "$HOME/flutter/bin/flutter" ]; then
    FLUTTER="$HOME/flutter/bin/flutter"
else
    echo "错误: 未找到 Flutter"
    echo "请确保 Flutter 已安装"
    exit 1
fi

echo "使用 Flutter: $FLUTTER"

# 终止已有进程
echo "检查并终止已有进程..."
if pgrep -f "remote_cam_client" > /dev/null; then
    echo "发现正在运行的应用，正在终止..."
    pkill -9 -f "remote_cam_client" 2>/dev/null || true
    sleep 2
    echo "✓ 已终止旧进程"
else
    echo "✓ 未发现运行中的进程"
fi

# 只删除最终的 app 文件，保留中间文件以支持增量编译
APP_PATH="build/macos/Build/Products/Debug/remote_cam_client.app"
if [ -d "$APP_PATH" ]; then
    echo "删除旧的 app 文件以使用增量编译..."
    rm -rf "$APP_PATH"
    echo "✓ 已删除旧 app，保留中间文件"
fi

# 构建 macOS 应用
echo "正在构建..."
$FLUTTER build macos --debug

BUILD_PATH="build/macos/Build/Products/Debug"

if [ -d "$BUILD_PATH" ]; then
    echo "========================================"
    echo "构建成功！"
    echo "应用位置: $BUILD_PATH"
    echo "========================================"
    
    # 根据参数决定是否启动应用
    if [ "$AUTO_START" = true ]; then
        echo "自动启动应用..."
        open "$BUILD_PATH/remote_cam_client.app"
    else
        # 询问是否启动应用
        read -p "是否启动应用? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            open "$BUILD_PATH/remote_cam_client.app"
        fi
    fi
else
    echo "构建失败，请检查错误信息"
    exit 1
fi

