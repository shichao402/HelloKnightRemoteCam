#!/bin/bash

# 启动应用脚本（macOS/Linux）

set -e

BUILD_MODE="${1:-debug}"
BUILD_TYPE="${2:-macos}"

cd "$(dirname "$0")/.."

# Flutter 构建输出路径使用首字母大写的模式名（Debug/Release）
BUILD_MODE_CAPITALIZED="$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"

if [ "$BUILD_TYPE" = "macos" ]; then
    APP_PATH="build/macos/Build/Products/$BUILD_MODE_CAPITALIZED/HelloKnightRCC.app"
    if [ ! -d "$APP_PATH" ]; then
        echo "错误: 应用未找到: $APP_PATH"
        echo "请先运行构建脚本"
        exit 1
    fi
    # 确保移除隔离属性（如果存在）
    echo "检查并移除隔离属性..."
    xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    xattr -d com.apple.provenance "$APP_PATH" 2>/dev/null || true
    echo "启动应用: $APP_PATH"
    open "$APP_PATH"
else
    APP_PATH="build/windows/x64/runner/$BUILD_MODE_CAPITALIZED/remote_cam_client.exe"
    if [ ! -f "$APP_PATH" ]; then
        echo "错误: 应用未找到: $APP_PATH"
        echo "请先运行构建脚本"
        exit 1
    fi
    echo "启动应用: $APP_PATH"
    "$APP_PATH" &
fi

echo "✓ 应用已启动"

