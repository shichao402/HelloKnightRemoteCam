#!/bin/bash

# 持续收集adb logcat日志的脚本
# 根据包名获取PID，然后过滤该PID的日志

PACKAGE_NAME="com.firoyang.helloknightrcc_server"
LOG_FILE="$HOME/adb_logcat_${PACKAGE_NAME}.log"
PID_FILE="$HOME/adb_logcat_${PACKAGE_NAME}.pid"

# 清理旧的日志文件（每次启动时清理）
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
fi

# 如果已有日志收集进程在运行，先终止它
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "终止旧的日志收集进程 (PID: $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null
        sleep 1
    fi
    rm -f "$PID_FILE"
fi

# 等待应用启动并获取PID
echo "等待应用启动..."
MAX_WAIT=30
WAIT_COUNT=0
APP_PID=""

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # 尝试获取应用PID（使用多种方法以提高兼容性）
    # 方法1: pidof（Android 8.0+）
    APP_PID=$(adb shell pidof "$PACKAGE_NAME" 2>/dev/null | tr -d '\r\n')
    
    # 方法2: 如果pidof失败，使用ps + grep
    if [ -z "$APP_PID" ] || [ "$APP_PID" = "" ]; then
        APP_PID=$(adb shell ps -A 2>/dev/null | grep "$PACKAGE_NAME" | awk '{print $2}' | head -1 | tr -d '\r\n')
    fi
    
    # 方法3: 如果还是失败，尝试使用ps（不带-A，适用于旧版本）
    if [ -z "$APP_PID" ] || [ "$APP_PID" = "" ]; then
        APP_PID=$(adb shell ps 2>/dev/null | grep "$PACKAGE_NAME" | awk '{print $2}' | head -1 | tr -d '\r\n')
    fi
    
    if [ -n "$APP_PID" ] && [ "$APP_PID" != "" ]; then
        echo "找到应用进程 PID: $APP_PID"
        break
    fi
    
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ -z "$APP_PID" ] || [ "$APP_PID" = "" ]; then
    echo "错误: 无法获取应用PID，应用可能未启动"
    echo "请确保应用已启动后再运行此脚本"
    exit 1
fi

# 清空日志缓冲区
adb logcat -c

# 启动logcat并过滤PID
# 尝试使用--pid选项（Android 7.0+支持）
if adb logcat --help 2>&1 | grep -q "\-\-pid"; then
    echo "启动日志收集，使用 --pid 过滤 PID: $APP_PID"
    adb logcat --pid="$APP_PID" > "$LOG_FILE" 2>&1 &
    LOG_PID=$!
else
    # 如果不支持--pid，使用grep过滤
    # logcat格式: MM-DD HH:MM:SS.mmm PID TID TAG: message
    echo "启动日志收集，使用 grep 过滤 PID: $APP_PID"
    adb logcat | grep --line-buffered -E "^[0-9]{2}-[0-9]{2}.*[[:space:]]+${APP_PID}[[:space:]]+" > "$LOG_FILE" 2>&1 &
    LOG_PID=$!
fi

# 保存日志收集进程的PID
echo $LOG_PID > "$PID_FILE"

echo "日志收集已启动 (PID: $LOG_PID)，输出到: $LOG_FILE"
echo "应用 PID: $APP_PID"
echo ""
echo "提示: 要停止日志收集，运行: kill \$(cat $PID_FILE)"

