# GitHub Actions 自动发布配置指南

## 概述

GitHub Actions workflow 已配置为在推送版本标签时自动：
1. 构建所有平台的应用（macOS、Windows、Android）
2. 创建 GitHub Release
3. 生成并推送更新配置文件到 GitHub 仓库

## 工作流程

### 触发条件

当推送版本标签（格式：`v*`，例如 `v1.0.4`）时，workflow 会自动执行：

```bash
git tag v1.0.4
git push origin v1.0.4
```

### 执行步骤

1. **构建阶段**（并行执行）
   - 构建 macOS 客户端
   - 构建 Windows 客户端
   - 构建 Android 服务器

2. **发布阶段**（所有构建完成后）
   - 创建 GitHub Release
   - 上传构建产物到 Release
   - 生成更新配置文件
   - 推送配置文件到 GitHub 仓库

## 版本号管理

版本号从 `pubspec.yaml` 文件中读取：
- 客户端版本：`client/pubspec.yaml`
- 服务器版本：`server/pubspec.yaml`

格式：`x.y.z+build`（例如：`1.0.4+1`）

如果是从标签触发，workflow 会优先使用标签中的版本号。

## 文件命名规则

### 构建产物

- macOS: `HelloKnightRCC_macos_1.0.4+1.zip`
- Windows: `HelloKnightRCC_windows_1.0.4+1.zip`
- Android: `helloknightrcc_server_android_1.0.4+1.zip`

### GitHub Release

**重要说明：** GitHub Release 中**仅上传zip文件**，其他格式的文件（如dmg、exe等）不会上传到Release。

- macOS: `HelloKnightRCC_macos_<version>.zip`
- Windows: `HelloKnightRCC_windows_<version>.zip`
- Android: `helloknightrcc_server_android_<version>.zip`

## 更新配置文件

生成的 `update_config_github.json` 包含：
- 所有平台的版本信息
- 下载 URL（指向 GitHub Releases，**仅包含zip包**）
- 更新检查 URL

**重要说明：** 更新配置文件中**仅包含zip包的下载链接**，不包含其他格式的文件。发布后，更新列表中预期只有zip包。

配置文件会自动推送到 GitHub 仓库的 `main` 分支。

## 故障排除

### 构建失败

- 检查 Flutter 版本是否匹配（当前：3.24.0）
- 检查依赖是否正确
- 查看 GitHub Actions 日志

### 配置文件推送失败

- 检查是否有写入仓库的权限
- 检查分支名称是否正确（默认：`main`）

## 手动触发（可选）

如果需要手动触发 workflow，可以：

1. 在 GitHub Actions 页面点击 "Run workflow"
2. 选择分支和版本标签
3. 点击 "Run workflow"

## 注意事项

1. **版本标签格式**：必须使用 `v*` 格式（例如：`v1.0.4`）
2. **版本号同步**：确保 `pubspec.yaml` 中的版本号已更新
3. **构建时间**：完整构建可能需要 10-20 分钟
4. **并发限制**：GitHub Actions 有并发限制，请合理安排发布频率

## 相关文档

- [自动更新功能文档](./AUTO_UPDATE.md)
- [CI/CD 配置文档](./CI_CD_SETUP.md)
- [版本管理文档](./VERSION_MANAGEMENT.md)
