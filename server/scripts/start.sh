#!/bin/bash

# 启动应用脚本（Android）

set -e

PACKAGE_NAME="com.example.remote_cam_server"
MAIN_ACTIVITY="com.example.remote_cam_server.MainActivity"

echo "启动应用: $PACKAGE_NAME"

# 检查 adb 是否可用
if ! command -v adb &> /dev/null; then
    echo "错误: 未找到 adb 命令"
    echo "请确保 Android SDK 已安装并添加到 PATH"
    exit 1
fi

# 检查设备连接
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "错误: 未检测到 Android 设备"
    exit 1
fi

# 启动应用
echo "等待1秒后启动应用..."
sleep 1
adb shell am start -n "$PACKAGE_NAME/$MAIN_ACTIVITY"

echo "✓ 应用已启动"

