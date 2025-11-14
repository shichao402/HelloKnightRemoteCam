#!/bin/bash

# 主控端 macOS 部署脚本（向后兼容包装器）
# 此脚本调用新的模块化部署脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 解析命令行参数并传递给新的部署脚本
ARGS=""
if [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    ARGS="-y"
fi

exec "$SCRIPT_DIR/deploy.sh" $ARGS --debug --macos

