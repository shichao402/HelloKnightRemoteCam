#!/bin/bash

# 创建构建标签脚本
# 用法: ./scripts/create_build_tags.sh [version] [--no-push]
# 示例: ./scripts/create_build_tags.sh 1.0.7          # 创建并推送标签
#       ./scripts/create_build_tags.sh                 # 从 VERSION.yaml 读取版本号并推送
#       ./scripts/create_build_tags.sh 1.0.7 --no-push # 只创建标签，不推送

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "创建构建标签并触发 GitHub Actions 构建工作流"
    echo ""
    echo "选项:"
    echo "  --no-push           只创建标签，不推送到远程（默认会自动推送）"
    echo "  --remote            基于远程分支的最新状态创建标签（默认基于本地当前状态）"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                           # 从 VERSION.yaml 读取版本号，创建标签并推送"
    echo "  $0 --no-push                 # 只创建标签，不推送"
    echo "  $0 --remote                  # 基于远程分支状态创建标签"
    echo ""
    echo "说明:"
    echo "  - 版本号始终从 VERSION.yaml 文件读取，确保版本一致性"
    echo "  - 如果无法读取版本号，脚本会中断并报错"
    echo "  - 创建的标签格式为 build{version}，例如 build1.0.7"
    echo "  - 推送标签后会触发 GitHub Actions 构建所有平台（macOS, Windows, Android）"
    echo ""
    echo "注意:"
    echo "  - 默认基于本地当前 HEAD 创建标签"
    echo "  - 使用 --remote 选项会先 fetch 远程更新，然后基于远程分支创建标签"
}

# 解析参数
PUSH_TO_REMOTE=true  # 默认推送
USE_REMOTE=false     # 默认基于本地状态

# 解析参数
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-push)
            PUSH_TO_REMOTE=false
            ;;
        --remote)
            USE_REMOTE=true
            ;;
        *)
            echo -e "${RED}错误: 未知参数 '$arg'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# 从 VERSION.yaml 读取版本号（必须）
echo -e "${BLUE}从 VERSION.yaml 读取版本号...${NC}"

VERSION=""
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

# 验证版本号是否成功读取
if [ -z "$VERSION" ]; then
    echo -e "${RED}错误: 无法从版本文件读取版本号${NC}"
    echo ""
    echo "请确保以下文件之一存在且包含有效的版本号："
    echo "  - VERSION.yaml"
    echo "  - client/pubspec.yaml"
    echo "  - server/pubspec.yaml"
    echo ""
    echo "或者确保 scripts/lib/version_manager.py 可用"
    exit 1
fi

# 验证版本号格式
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}错误: 读取到的版本号格式不正确: '${VERSION}'${NC}"
    echo "版本号应为 x.y.z 格式（如 1.0.7）"
    exit 1
fi

echo -e "${GREEN}✓ 读取到版本号: ${VERSION}${NC}"
echo ""

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

# 确定基于哪个引用创建标签
if [ "$USE_REMOTE" = true ]; then
    echo -e "${BLUE}基于远程分支状态创建标签...${NC}"
    
    # 获取当前分支名
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    # 获取远程分支名（通常是 origin/main 或 origin/master）
    REMOTE_BRANCH="origin/${CURRENT_BRANCH}"
    if ! git rev-parse --verify "$REMOTE_BRANCH" >/dev/null 2>&1; then
        # 尝试 origin/main
        if git rev-parse --verify "origin/main" >/dev/null 2>&1; then
            REMOTE_BRANCH="origin/main"
        elif git rev-parse --verify "origin/master" >/dev/null 2>&1; then
            REMOTE_BRANCH="origin/master"
        else
            echo -e "${RED}错误: 未找到远程分支，请先推送代码或指定分支${NC}"
            exit 1
        fi
    fi
    
    # 获取远程最新状态
    echo "获取远程最新状态..."
    git fetch origin "${REMOTE_BRANCH#origin/}" || git fetch origin
    
    # 使用远程分支的最新提交
    CURRENT_REF="$REMOTE_BRANCH"
    REMOTE_COMMIT=$(git rev-parse "$REMOTE_BRANCH")
    echo -e "${GREEN}基于远程分支创建标签: ${REMOTE_BRANCH}${NC}"
    echo -e "${GREEN}远程提交: ${REMOTE_COMMIT:0:7}${NC}"
else
    # 使用本地当前状态
    CURRENT_REF=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD)
    LOCAL_COMMIT=$(git rev-parse HEAD)
    echo -e "${GREEN}基于本地当前状态创建标签: $CURRENT_REF${NC}"
    echo -e "${GREEN}本地提交: ${LOCAL_COMMIT:0:7}${NC}"
fi
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
    echo -e "${YELLOW}提示: 标签已创建但未推送。手动推送:${NC}"
    echo "  git push origin ${BUILD_TAG}"
fi

echo ""
echo -e "${GREEN}完成！${NC}"
