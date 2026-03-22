#!/bin/bash
# Core Service 开发启动脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../core"

cd "$CORE_DIR" || exit 1

# 检查依赖
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

echo "Starting Core Service in dev mode..."
exec npx tsx watch src/main.ts
