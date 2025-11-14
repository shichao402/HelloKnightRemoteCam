#!/bin/bash

# 手机端 Android 部署脚本（向后兼容包装器）
# 此脚本调用新的模块化部署脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 解析命令行参数并传递给新的部署脚本
ARGS=""
if [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    ARGS="-y"
fi

# 使用 exec 会替换当前进程，如果失败错误信息可能不显示
# 改为直接调用，这样可以正确显示错误信息
"$SCRIPT_DIR/deploy.sh" $ARGS --debug
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo ""
    echo "部署失败，退出码: $exit_code"
    exit $exit_code
fi

