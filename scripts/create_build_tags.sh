#!/bin/bash

# 创建构建标签脚本
# 用法: ./scripts/create_build_tags.sh [version] [--push]
# 示例: ./scripts/create_build_tags.sh 1.0.7
#       ./scripts/create_build_tags.sh 1.0.7 --push
#       ./scripts/create_build_tags.sh --push  # 从 VERSION.yaml 读取版本号

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 解析参数
PUSH_TO_REMOTE=false
VERSION=""

# 解析参数
for arg in "$@"; do
    if [ "$arg" == "--push" ]; then
        PUSH_TO_REMOTE=true
    elif [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        VERSION=$arg
    fi
done

# 如果没有提供版本号，从 VERSION.yaml 读取
if [ -z "$VERSION" ]; then
    echo -e "${BLUE}未提供版本号，从 VERSION.yaml 读取...${NC}"
    if [ -f "scripts/lib/version_manager.py" ]; then
        # 使用 version_manager.py 获取版本号（JSON 格式）
        VERSION=$(python3 scripts/lib/version_manager.py extract client --json 2>/dev/null | \
                 python3 -c "import sys, json; print(json.load(sys.stdin)['version'])" 2>/dev/null || \
                 python3 scripts/lib/version_manager.py extract client 2>/dev/null | sed 's/+.*//')
    elif [ -f "VERSION.yaml" ]; then
        # 回退到使用 version.sh（用户接口）
        VERSION=$(./scripts/version.sh get client 2>/dev/null | sed 's/+.*//' || echo "")
    elif [ -f "client/pubspec.yaml" ]; then
        VERSION=$(grep '^version:' client/pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
    elif [ -f "server/pubspec.yaml" ]; then
        VERSION=$(grep '^version:' server/pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
    fi
    
    if [ -z "$VERSION" ]; then
        echo -e "${RED}错误: 无法从 VERSION.yaml 读取版本号，请手动指定${NC}"
        echo "用法: $0 [version] [--push]"
        echo "示例: $0 1.0.7"
        echo "      $0 1.0.7 --push"
        echo "      $0 --push  # 从 VERSION.yaml 读取版本号"
        exit 1
    fi
    
    echo -e "${GREEN}读取到版本号: ${VERSION}${NC}"
    echo ""
fi

# 验证版本号格式（简单验证：应该包含点号）
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo -e "${YELLOW}警告: 版本号格式可能不正确，建议使用语义化版本号（如 1.0.7）${NC}"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 创建构建标签（格式：build1.0.7）
BUILD_TAG="build${VERSION}"

echo -e "${GREEN}准备创建构建标签: ${BUILD_TAG}${NC}"
echo ""

# 检查标签是否已存在
if git rev-parse "$BUILD_TAG" >/dev/null 2>&1; then
    echo -e "${YELLOW}警告: 标签 ${BUILD_TAG} 已存在${NC}"
    read -p "是否覆盖这个标签？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消操作"
        exit 1
    fi
    # 删除已存在的标签
    echo -e "${YELLOW}删除本地标签: ${BUILD_TAG}${NC}"
    git tag -d "$BUILD_TAG" 2>/dev/null || true
    if [ "$PUSH_TO_REMOTE" = true ]; then
        echo -e "${YELLOW}删除远程标签: ${BUILD_TAG}${NC}"
        git push origin ":refs/tags/$BUILD_TAG" 2>/dev/null || true
    fi
fi

# 获取当前分支或提交
CURRENT_REF=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD)

echo -e "${GREEN}基于当前引用创建标签: $CURRENT_REF${NC}"
echo ""

# 创建标签
echo -e "创建标签: ${GREEN}${BUILD_TAG}${NC}"
if git tag -a "$BUILD_TAG" -m "Build tag for version $VERSION" "$CURRENT_REF"; then
    echo -e "  ${GREEN}✓${NC} 标签创建成功"
else
    echo -e "  ${RED}✗${NC} 标签创建失败"
    exit 1
fi

echo ""

# 如果需要推送到远程
if [ "$PUSH_TO_REMOTE" = true ]; then
    echo -e "${GREEN}推送到远程仓库...${NC}"
    
    # 推送标签
    if git push origin "$BUILD_TAG"; then
        echo -e "${GREEN}✓${NC} 标签已成功推送到远程"
        echo ""
        echo "GitHub Actions 将自动触发构建工作流："
        echo "  - Build Client macOS"
        echo "  - Build Client Windows"
        echo "  - Build Server Android"
    else
        echo -e "${RED}✗${NC} 推送标签到远程时出错"
        exit 1
    fi
else
    echo -e "${YELLOW}提示: 标签已创建但未推送。使用 --push 参数推送到远程:${NC}"
    echo "  git push origin ${BUILD_TAG}"
    echo "或重新运行脚本:"
    echo "  $0 $VERSION --push"
fi

echo ""
echo -e "${GREEN}完成！${NC}"
