#!/bin/bash

# 终止已有进程脚本（Android）- 通过 adb 终止应用

set -e

PACKAGE_NAME="com.example.remote_cam_server"

echo "检查并终止已有进程: $PACKAGE_NAME"

# 检查 adb 是否可用
if ! command -v adb &> /dev/null; then
    echo "警告: 未找到 adb 命令，跳过进程终止"
    exit 0
fi

# 检查设备连接
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "警告: 未检测到 Android 设备，跳过进程终止"
    exit 0
fi

# 终止应用
if adb shell am force-stop "$PACKAGE_NAME" 2>/dev/null; then
    echo "✓ 已终止旧进程"
else
    echo "✓ 应用未运行"
fi

