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

# 查找沙盒应用路径和非沙盒应用路径
CLIENT_LOG_DIR_SANDBOX="$HOME/Library/Containers/com.example.remoteCamClient/Data/Library/Logs"
CLIENT_LOG_DIR_NON_SANDBOX="$HOME/Library/Logs/HelloKnightRCC"

# 收集所有存在的日志目录
CLIENT_LOG_DIRS=()
if [ -d "$CLIENT_LOG_DIR_SANDBOX" ]; then
    CLIENT_LOG_DIRS+=("$CLIENT_LOG_DIR_SANDBOX")
    echo "✓ 找到客户端日志目录（沙盒应用）: $CLIENT_LOG_DIR_SANDBOX"
fi
if [ -d "$CLIENT_LOG_DIR_NON_SANDBOX" ]; then
    CLIENT_LOG_DIRS+=("$CLIENT_LOG_DIR_NON_SANDBOX")
    echo "✓ 找到客户端日志目录（非沙盒应用）: $CLIENT_LOG_DIR_NON_SANDBOX"
fi

if [ ${#CLIENT_LOG_DIRS[@]} -gt 0 ]; then
    # 列出所有日志文件
    echo ""
    echo "客户端日志文件列表:"
    for dir in "${CLIENT_LOG_DIRS[@]}"; do
        echo ""
        echo "--- $dir ---"
        LOG_FILES=$(ls -lha "$dir" 2>/dev/null | grep -E "client_debug_.*\.log" || true)
        if [ -n "$LOG_FILES" ]; then
            echo "$LOG_FILES"
        else
            echo "该目录下无日志文件"
        fi
    done
    
    echo ""
    echo "最新日志内容:"
    echo "========================================"
    # 从所有目录中查找最新的日志文件（按修改时间排序）
    # 使用find + stat确保按修改时间排序，而不是文件名
    LATEST_LOG=""
    for dir in "${CLIENT_LOG_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            FOUND_LOG=$(find "$dir" -name "client_debug_*.log" -type f -print0 2>/dev/null | \
                xargs -0 stat -f "%m %N" 2>/dev/null | \
                sort -rn | \
                head -1 | \
                awk '{print $2}')
            
            if [ -n "$FOUND_LOG" ]; then
                if [ -z "$LATEST_LOG" ]; then
                    LATEST_LOG="$FOUND_LOG"
                else
                    # 比较修改时间，保留最新的
                    LATEST_TIME=$(stat -f "%m" "$LATEST_LOG" 2>/dev/null || echo "0")
                    FOUND_TIME=$(stat -f "%m" "$FOUND_LOG" 2>/dev/null || echo "0")
                    if [ "$FOUND_TIME" -gt "$LATEST_TIME" ]; then
                        LATEST_LOG="$FOUND_LOG"
                    fi
                fi
            fi
        fi
    done
    
    if [ -z "$LATEST_LOG" ]; then
        # 如果find + stat失败，回退到ls -t方法，合并所有目录
        ALL_LOGS=""
        for dir in "${CLIENT_LOG_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                DIR_LOGS=$(ls -t "$dir"/client_debug_*.log 2>/dev/null)
                if [ -n "$DIR_LOGS" ]; then
                    if [ -z "$ALL_LOGS" ]; then
                        ALL_LOGS="$DIR_LOGS"
                    else
                        ALL_LOGS="$ALL_LOGS"$'\n'"$DIR_LOGS"
                    fi
                fi
            fi
        done
        if [ -n "$ALL_LOGS" ]; then
            LATEST_LOG=$(echo "$ALL_LOGS" | head -1)
        fi
    fi
    
    if [ -n "$LATEST_LOG" ]; then
        LATEST_LOG_NAME=$(basename "$LATEST_LOG")
        LATEST_LOG_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST_LOG" 2>/dev/null || echo "未知")
        LATEST_LOG_DIR=$(dirname "$LATEST_LOG")
        echo "读取最新日志文件: $LATEST_LOG_NAME"
        echo "文件路径: $LATEST_LOG"
        echo "文件修改时间: $LATEST_LOG_TIME"
        echo ""
        cat "$LATEST_LOG" 2>/dev/null || echo "无法读取日志文件"
    else
        echo "未找到日志文件"
    fi
    echo "========================================"
else
    echo "✗ 客户端日志目录不存在"
    echo "  已检查路径:"
    echo "    - $CLIENT_LOG_DIR_SANDBOX"
    echo "    - $CLIENT_LOG_DIR_NON_SANDBOX"
fi

echo ""
echo ""
echo "========================================"
echo "日志收集完成"
echo "========================================"

