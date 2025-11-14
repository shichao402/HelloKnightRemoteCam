#!/bin/bash

# 完整部署脚本（Android）- 组合调用各个模块

# 不使用 set -e，而是手动检查每个步骤的退出码
# 这样可以更好地显示错误信息

# 解析命令行参数
AUTO_START=false
BUILD_MODE="debug"

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_START=true
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
            echo "用法: $0 [-y|--yes] [--release|--debug]"
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "开始部署 Server Android ($BUILD_MODE)"
echo "========================================"

# 1. 终止已有进程
echo "步骤 1/4: 终止已有进程..."
if ! "$SCRIPT_DIR/kill_process.sh"; then
    echo "警告: 终止进程时出现问题，继续执行..."
fi

# 2. 构建
echo "步骤 2/4: 构建 APK..."
if ! "$SCRIPT_DIR/build.sh" --$BUILD_MODE; then
    echo "错误: 构建失败"
    exit 1
fi

# 3. 安装
echo "步骤 3/4: 安装 APK..."
if ! "$SCRIPT_DIR/install.sh" "$BUILD_MODE"; then
    echo "错误: 安装失败"
    exit 1
fi

# 4. 启动应用
if [ "$AUTO_START" = true ]; then
    echo "步骤 4/4: 启动应用..."
    if ! "$SCRIPT_DIR/start.sh"; then
        echo "错误: 启动失败"
        exit 1
    fi
else
    read -p "是否启动应用? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "步骤 4/4: 启动应用..."
        if ! "$SCRIPT_DIR/start.sh"; then
            echo "错误: 启动失败"
            exit 1
        fi
    fi
fi

echo "========================================"
echo "部署完成！"
echo "========================================"

