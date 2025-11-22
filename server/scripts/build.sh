#!/bin/bash

# 构建脚本（Android）

set -e

# 解析命令行参数
BUILD_MODE="debug"

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
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--release|--debug]"
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")/.."

echo "========================================"
echo "构建 Server Android ($BUILD_MODE)"
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

# 同步版本号并生成版本配置（只同步服务器）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION_SCRIPT="$PROJECT_ROOT/scripts/version.sh"
PUBSPEC_FILE="pubspec.yaml"

# 注意：不再自动还原 pubspec.yaml，保留版本号同步后的状态

if [ -f "$VERSION_SCRIPT" ]; then
    echo "同步服务器版本号到 pubspec.yaml 并生成版本配置..."
    bash "$VERSION_SCRIPT" sync server
else
    echo "警告: 版本号同步脚本未找到，跳过版本号同步"
fi

# 获取依赖
echo "获取依赖..."
$FLUTTER pub get

# 构建 APK
echo "正在构建 APK..."
$FLUTTER build apk --$BUILD_MODE

if [ "$BUILD_MODE" = "release" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
else
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

if [ ! -f "$APK_PATH" ]; then
    echo "错误: APK 文件未找到"
    exit 1
fi

echo "========================================"
echo "构建成功！"
echo "APK 位置: $APK_PATH"
echo "========================================"

