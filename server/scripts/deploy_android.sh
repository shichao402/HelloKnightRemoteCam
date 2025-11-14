#!/bin/bash

# 手机端 Android 部署脚本

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
echo "开始构建并部署手机端 Android 应用"
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

# 检查adb是否可用
if ! command -v adb &> /dev/null; then
    echo "错误: 未找到 adb 命令"
    echo "请确保 Android SDK 已安装并添加到 PATH"
    exit 1
fi

# 构建 APK
echo "正在构建 APK..."
$FLUTTER build apk --debug

APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "错误: APK 文件未找到"
    exit 1
fi

echo "APK 构建成功: $APK_PATH"

# 检查设备连接
echo "检查 Android 设备..."
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device$" | wc -l)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "警告: 未检测到 Android 设备"
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

# 根据参数决定是否启动应用
if [ "$AUTO_START" = true ]; then
    echo "等待1秒后自动启动应用..."
    sleep 1
    adb shell am start -n com.example.remote_cam_server/.MainActivity
    echo "应用已启动"
else
    # 询问是否启动应用
    read -p "是否启动应用? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "等待1秒后启动应用..."
        sleep 1
        adb shell am start -n com.example.remote_cam_server/.MainActivity
        echo "应用已启动"
    fi
fi

