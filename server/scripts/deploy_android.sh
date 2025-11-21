#!/bin/bash

# 手机端 Android 部署脚本（向后兼容包装器）
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

# 使用 exec 会替换当前进程，如果失败错误信息可能不显示
# 改为直接调用，这样可以正确显示错误信息
"$SCRIPT_DIR/deploy.sh" $ARGS --debug
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo ""
    echo "部署失败，退出码: $exit_code"
    exit $exit_code
fi

