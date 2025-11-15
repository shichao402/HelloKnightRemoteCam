# 版本管理指南

## 版本号格式

项目使用语义化版本号格式：`主版本号.次版本号.修订号+构建号`

例如：`1.0.0+1`
- `1.0.0` - 版本号（主版本.次版本.修订号）
- `+1` - 构建号

版本号定义在：
- Client: `client/pubspec.yaml`
- Server: `server/pubspec.yaml`

## 创建 Release

### 方法 1: 使用脚本（推荐）

```bash
# 自动从 pubspec.yaml 读取版本号
./scripts/create_release.sh

# 或手动指定版本号
./scripts/create_release.sh 1.0.0
```

脚本会：
1. 从 `pubspec.yaml` 读取版本号（或使用提供的版本号）
2. 创建 Git 标签（格式：`v1.0.0`）
3. 推送标签到远程仓库
4. 触发 GitHub Actions 自动构建和创建 Release

### 方法 2: 手动创建标签

```bash
# 1. 更新版本号（在 pubspec.yaml 中）
# client/pubspec.yaml: version: 1.0.0+1
# server/pubspec.yaml: version: 1.0.0+1

# 2. 提交更改
git add client/pubspec.yaml server/pubspec.yaml
git commit -m "Bump version to 1.0.0"

# 3. 创建并推送标签
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0
```

## GitHub Actions 自动流程

当推送版本标签（格式：`v*`）时，GitHub Actions 会：

1. **构建所有平台**
   - Client macOS
   - Client Windows
   - Server Android

2. **提取版本号**
   - 从 `pubspec.yaml` 读取版本号和构建号
   - 生成完整的版本字符串

3. **创建 Release**
   - 使用标签名称作为 Release 版本
   - 上传所有构建产物
   - 生成 Release 说明

## Release 文件命名

构建产物会自动包含版本号：

- `HelloKnightRCC_macos_1.0.0+1.zip`
- `HelloKnightRCC_windows_1.0.0+1.zip`
- `remote_cam_server_android_1.0.0+1.apk`

## 版本号更新建议

### 主版本号（Major）
- 不兼容的 API 更改
- 重大功能变更

### 次版本号（Minor）
- 向后兼容的功能添加
- 新功能

### 修订号（Patch）
- 向后兼容的 bug 修复
- 小改进

### 构建号（Build）
- 每次构建递增
- 用于区分同一版本的多次构建

## 示例工作流

```bash
# 1. 开发新功能
git checkout -b feature/new-feature
# ... 开发代码 ...

# 2. 合并到主分支
git checkout main
git merge feature/new-feature

# 3. 更新版本号（例如：1.0.0 -> 1.1.0）
# 编辑 client/pubspec.yaml 和 server/pubspec.yaml
# version: 1.1.0+1

# 4. 提交版本更新
git add client/pubspec.yaml server/pubspec.yaml
git commit -m "Bump version to 1.1.0"

# 5. 创建 Release
./scripts/create_release.sh 1.1.0

# 6. GitHub Actions 会自动：
#    - 构建所有平台
#    - 创建 Release
#    - 上传构建产物
```

## 查看 Release

访问 GitHub 仓库的 Releases 页面：
```
https://github.com/<username>/<repo>/releases
```

## 注意事项

1. **标签格式**：必须使用 `v` 前缀（例如：`v1.0.0`）
2. **版本一致性**：确保 client 和 server 的版本号一致（或根据需要分别管理）
3. **构建号**：每次发布新版本时，建议重置构建号为 1
4. **权限**：确保 GitHub Actions 有创建 Release 的权限（在仓库设置中配置）

