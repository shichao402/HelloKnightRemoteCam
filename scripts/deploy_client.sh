#!/bin/bash
# 客户端部署脚本 - macOS/Linux 入口
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/deploy_client.py" "$@"
