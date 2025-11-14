#!/bin/bash

# 安装脚本（Android）

set -e

BUILD_MODE="${1:-debug}"

cd "$(dirname "$0")/.."

echo "========================================"
echo "安装 Server Android ($BUILD_MODE)"
echo "========================================"

# 检查 adb 是否可用
if ! command -v adb &> /dev/null; then
    echo "错误: 未找到 adb 命令"
    echo "请确保 Android SDK 已安装并添加到 PATH"
    exit 1
fi

# 确定 APK 路径
if [ "$BUILD_MODE" = "release" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
else
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

if [ ! -f "$APK_PATH" ]; then
    echo "错误: APK 文件未找到: $APK_PATH"
    echo "请先运行构建脚本"
    exit 1
fi

# 检查设备连接
echo "检查 Android 设备..."
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device$" | wc -l)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "错误: 未检测到 Android 设备"
    echo "请连接设备后重试"
    exit 1
fi

echo "检测到 $DEVICE_COUNT 个设备"

# 安装 APK
echo "正在安装 APK..."
adb install -r "$APK_PATH"

echo "========================================"
echo "安装成功！"
echo "========================================"

