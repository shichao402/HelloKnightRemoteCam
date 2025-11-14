#!/bin/bash

# 终止已有进程脚本（macOS/Linux）

set -e

APP_NAME="remote_cam_client"

echo "检查并终止已有进程: $APP_NAME"

if pgrep -f "$APP_NAME" > /dev/null; then
    echo "发现正在运行的应用，正在终止..."
    pkill -9 -f "$APP_NAME" 2>/dev/null || true
    sleep 2
    echo "✓ 已终止旧进程"
else
    echo "✓ 未发现运行中的进程"
fi

