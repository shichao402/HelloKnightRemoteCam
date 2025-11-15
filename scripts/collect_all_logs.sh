#!/bin/bash

# 收集所有日志的脚本

echo "========================================"
echo "收集远程相机系统日志"
echo "========================================"
echo ""

# 1. 收集手机端日志
echo "1. 收集手机端日志..."
echo "----------------------------------------"

if adb devices | grep -q "device$"; then
    echo "✓ 检测到Android设备"
    
    # 确定日志目录路径（getApplicationSupportDirectory在Android上返回/files/，不是/app_flutter/）
    LOG_DIR="/data/data/com.example.remote_cam_server/files/logs"
    
    # 如果新路径不存在，尝试旧路径（向后兼容）
    if ! adb shell run-as com.example.remote_cam_server test -d "$LOG_DIR" 2>/dev/null; then
        LOG_DIR="/data/data/com.example.remote_cam_server/app_flutter/logs"
    fi
    
    echo ""
    echo "手机端日志目录: $LOG_DIR"
    echo "手机端日志文件列表:"
    adb shell run-as com.example.remote_cam_server ls -lat "$LOG_DIR/" 2>/dev/null | head -10 || echo "无法访问日志目录"
    
    echo ""
    echo "最新日志内容:"
    echo "========================================"
    
    # 直接读取日志文件：使用find命令查找所有日志文件，然后按修改时间排序
    # 只查找.log文件，排除其他文件
    LOG_FILES=$(adb shell run-as com.example.remote_cam_server sh -c "find '$LOG_DIR' -name 'debug_*.log' -type f 2>/dev/null" 2>/dev/null | grep "\.log$" | tr '\r\n' '\n' | sort)
    
    if [ -n "$LOG_FILES" ]; then
        # 获取最新的日志文件（按文件名排序，最新的ISO8601时间戳在最后）
        LATEST_LOG=$(echo "$LOG_FILES" | tail -1 | tr -d '\r\n')
        
        if [ -n "$LATEST_LOG" ]; then
            LATEST_LOG_NAME=$(basename "$LATEST_LOG")
            echo "读取最新日志文件: $LATEST_LOG_NAME"
            echo ""
            adb shell run-as com.example.remote_cam_server cat "$LATEST_LOG" 2>/dev/null || echo "无法读取日志文件: $LATEST_LOG"
            
            # 读取其他最近的日志文件（倒数第2和第3个）
            OTHER_LOGS=$(echo "$LOG_FILES" | tail -3 | head -2)
            if [ -n "$OTHER_LOGS" ]; then
                echo ""
                echo "其他最近日志文件内容:"
                echo "$OTHER_LOGS" | while read logpath; do
                    logpath=$(echo "$logpath" | tr -d '\r\n')
                    if [ -n "$logpath" ] && [ "$logpath" != "$LATEST_LOG" ]; then
                        logname=$(basename "$logpath")
                        echo ""
                        echo "========================================"
                        echo "--- $logname ---"
                        echo "========================================"
                        adb shell run-as com.example.remote_cam_server cat "$logpath" 2>/dev/null || true
                    fi
                done
            fi
        else
            echo "未找到有效的日志文件"
        fi
    else
        echo "未找到日志文件"
        echo "尝试检查日志目录..."
        adb shell run-as com.example.remote_cam_server ls -la "$LOG_DIR/" 2>/dev/null | head -15 || echo "无法访问日志目录: $LOG_DIR"
    fi
    
    echo "========================================"
else
    echo "✗ 未检测到Android设备"
fi

echo ""
echo ""

# 2. 收集Mac客户端日志
echo "2. 收集Mac客户端日志..."
echo "----------------------------------------"

CLIENT_LOG_DIR="$HOME/Library/Logs/HelloKnightRCC"

if [ -d "$CLIENT_LOG_DIR" ]; then
    echo "✓ 找到客户端日志目录: $CLIENT_LOG_DIR"
    
    # 列出日志文件
    echo ""
    echo "客户端日志文件列表:"
    ls -lha "$CLIENT_LOG_DIR"
    
    echo ""
    echo "最新日志内容:"
    echo "========================================"
    cat "$CLIENT_LOG_DIR"/client_debug_*.log 2>/dev/null || echo "无日志文件"
    echo "========================================"
else
    echo "✗ 客户端日志目录不存在: $CLIENT_LOG_DIR"
fi

echo ""
echo ""
echo "========================================"
echo "日志收集完成"
echo "========================================"

