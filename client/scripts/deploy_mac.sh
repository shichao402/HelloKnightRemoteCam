#!/bin/bash

# 主控端 macOS 部署脚本（向后兼容包装器）
# 此脚本调用新的模块化部署脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 解析命令行参数并传递给新的部署脚本
# 默认会自动启动，如果需要禁用启动，传递 -n 参数
ARGS=""
if [ "$1" = "-n" ] || [ "$1" = "--no-start" ]; then
    ARGS="-n"
elif [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    # 保留 -y 参数以保持向后兼容（虽然现在是默认行为）
    ARGS="-y"
fi

exec "$SCRIPT_DIR/deploy.sh" $ARGS --debug --macos

