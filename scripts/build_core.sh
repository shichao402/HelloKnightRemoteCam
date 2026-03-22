#!/bin/bash
# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

cd "$PROJECT_ROOT/core" || exit 1

echo "=== Core Service: Install Dependencies ==="
npm install

echo ""
echo "=== Core Service: Run Tests ==="
npx vitest run

echo ""
echo "=== Core Service: Build ==="
npx tsc

echo ""
echo "=== Core Service: Build Complete ==="
echo "Start with: cd core && npm run dev"
