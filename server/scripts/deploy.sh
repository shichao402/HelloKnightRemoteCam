#!/bin/bash

# 完整部署脚本（Android）- 组合调用各个模块

# 不使用 set -e，而是手动检查每个步骤的退出码
# 这样可以更好地显示错误信息

# 解析命令行参数
AUTO_START=true  # 默认自动启动
BUILD_MODE="debug"

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_START=true
            shift
            ;;
        -n|--no-start)
            AUTO_START=false
            shift
            ;;
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
            echo "用法: $0 [-y|--yes] [-n|--no-start] [--release|--debug]"
            echo "  默认行为: 自动启动应用"
            echo "  -n, --no-start: 不自动启动应用"
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "开始部署 Server Android ($BUILD_MODE)"
echo "========================================"

# 0. 终止旧的adb日志收集进程
echo "步骤 0/5: 终止旧的adb日志收集进程..."
PACKAGE_NAME="com.firoyang.helloknightrcc_server"
PID_FILE="$HOME/adb_logcat_${PACKAGE_NAME}.pid"

# 方法1: 通过PID文件清理
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "终止旧的日志收集进程 (PID: $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null
        sleep 1
        # 如果进程仍在运行，强制终止
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill -9 "$OLD_PID" 2>/dev/null
        fi
    fi
    rm -f "$PID_FILE"
fi

# 方法2: 通过进程名查找并清理残留的adb logcat进程（针对该包名的日志收集）
# 查找所有包含"logcat"和包名的进程
ps aux 2>/dev/null | grep -E "[a]db logcat.*${PACKAGE_NAME}" | awk '{print $2}' | while read pid; do
    if [ -n "$pid" ]; then
        echo "发现残留的日志收集进程 (PID: $pid)，正在终止..."
        kill "$pid" 2>/dev/null
        sleep 0.5
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
    fi
done

echo "✓ 旧的日志收集进程已清理"

# 1. 终止已有进程
echo "步骤 1/5: 终止已有进程..."
if ! "$SCRIPT_DIR/kill_process.sh"; then
    echo "警告: 终止进程时出现问题，继续执行..."
fi

# 2. 构建
echo "步骤 2/5: 构建 APK..."
if ! "$SCRIPT_DIR/build.sh" --$BUILD_MODE; then
    echo "错误: 构建失败"
    exit 1
fi

# 3. 安装
echo "步骤 3/5: 安装 APK..."
if ! "$SCRIPT_DIR/install.sh" "$BUILD_MODE"; then
    echo "错误: 安装失败"
    exit 1
fi

# 4. 启动应用
if [ "$AUTO_START" = true ]; then
    echo "步骤 4/5: 启动应用..."
    if ! "$SCRIPT_DIR/start.sh"; then
        echo "错误: 启动失败"
        exit 1
    fi
else
    read -p "是否启动应用? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "步骤 4/5: 启动应用..."
        if ! "$SCRIPT_DIR/start.sh"; then
            echo "错误: 启动失败"
            exit 1
        fi
    fi
fi

# 5. 启动日志收集
echo ""
echo "步骤 5/5: 启动日志收集..."
if ! "$SCRIPT_DIR/collect_adb_logs.sh"; then
    echo "警告: 启动日志收集失败，继续执行..."
fi

echo "========================================"
echo "部署完成！"
echo "========================================"

