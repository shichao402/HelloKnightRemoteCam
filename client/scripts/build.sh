#!/bin/bash

# 构建脚本（macOS/Linux）

set -e

# 解析命令行参数
BUILD_MODE="debug"
BUILD_TYPE="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "用法: $0 [--release|--debug] [--macos|--windows]"
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")/.."

echo "========================================"
echo "构建 Client ($BUILD_TYPE, $BUILD_MODE)"
echo "========================================"

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

# 获取依赖
echo "获取依赖..."
$FLUTTER pub get

# 清理旧的构建产物（仅删除最终文件，保留中间文件以支持增量编译）
if [ "$BUILD_TYPE" = "macos" ]; then
    # Flutter 构建输出路径使用首字母大写的模式名（Debug/Release）
    BUILD_MODE_CAPITALIZED="$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"
    APP_PATH="build/macos/Build/Products/$BUILD_MODE_CAPITALIZED/HelloKnightRCC.app"
    if [ -d "$APP_PATH" ]; then
        echo "删除旧的 app 文件以使用增量编译..."
        rm -rf "$APP_PATH"
        echo "✓ 已删除旧 app，保留中间文件"
    fi
fi

# 构建
echo "正在构建..."
if [ "$BUILD_TYPE" = "macos" ]; then
    $FLUTTER build macos --$BUILD_MODE
    # Flutter 构建输出路径使用首字母大写的模式名（Debug/Release）
    BUILD_PATH="build/macos/Build/Products/$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"
else
    $FLUTTER build windows --$BUILD_MODE
    BUILD_PATH="build/windows/x64/runner/$(echo ${BUILD_MODE:0:1} | tr '[:lower:]' '[:upper:]')${BUILD_MODE:1}"
fi

if [ "$BUILD_TYPE" = "macos" ]; then
    APP_PATH="$BUILD_PATH/HelloKnightRCC.app"
    if [ -d "$APP_PATH" ]; then
        # 移除 macOS Gatekeeper 隔离属性（允许未签名应用运行）
        echo "移除 macOS 隔离属性..."
        xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true
        xattr -d com.apple.provenance "$APP_PATH" 2>/dev/null || true
        echo "✓ 已移除隔离属性"
        echo "========================================"
        echo "构建成功！"
        echo "应用位置: $APP_PATH"
        echo "========================================"
    else
        echo "错误: 应用未找到: $APP_PATH"
        echo "构建失败，请检查错误信息"
        exit 1
    fi
else
    if [ -d "$BUILD_PATH" ]; then
        echo "========================================"
        echo "构建成功！"
        echo "应用位置: $BUILD_PATH"
        echo "========================================"
    else
        echo "错误: 构建目录未找到: $BUILD_PATH"
        echo "构建失败，请检查错误信息"
        exit 1
    fi
fi

