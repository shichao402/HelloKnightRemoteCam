# Gitee 迁移指南

## 概述

本项目已配置支持 Gitee Go CI/CD，功能与 GitHub Actions 完全一致，包括：
- 自动构建所有平台应用（macOS、Windows、Android）
- 自动创建 Release
- 自动生成更新配置文件
- 自动推送更新配置到仓库

## 已创建的文件

### 1. Gitee Go Workflow 配置

**文件路径：** `.gitee/workflows/build.yml`

该文件完全模仿 GitHub Actions 的工作流程，包括：
- 构建 macOS 客户端
- 构建 Windows 客户端
- 构建 Android 服务器
- 创建 Release
- 生成更新配置文件

### 2. Gitee 更新配置文件模板

**文件路径：** `update_config_gitee.json`

该文件是 Gitee 版本的更新配置文件模板，格式与 `update_config_github.json` 完全一致。

### 3. 文档

**文件路径：** `docs/GITEE_ACTIONS_SETUP.md`

详细的 Gitee Go 配置和使用文档。

### 4. 更新的脚本

**文件路径：** `scripts/create_release.sh`

已更新支持 Gitee 和 GitHub 双平台。

## 配置步骤

### 1. 在 Gitee 创建仓库

1. 登录 Gitee
2. 创建新仓库或导入现有仓库
3. 确保仓库名称与配置一致

### 2. 配置 Gitee Go Secrets

在 Gitee 仓库设置中配置以下 Secrets：

1. **GITEE_TOKEN**
   - 获取方式：Gitee 设置 → 安全设置 → 私人令牌
   - 权限：`projects`、`pull_requests`、`issues`、`notes`、`repository`

2. **GITEE_REPO_OWNER**
   - 你的 Gitee 用户名

3. **GITEE_REPO_NAME**
   - 仓库名称（例如：`HelloKnightRemoteCam`）

### 3. 启用 Gitee Go

1. 进入仓库设置
2. 启用 "Gitee Go" 功能
3. 确保 workflow 文件 `.gitee/workflows/build.yml` 已提交到仓库

### 4. 更新远程仓库（可选）

如果需要同时推送到 GitHub 和 Gitee：

```bash
# 添加 Gitee 远程仓库
git remote add gitee https://gitee.com/YOUR_USERNAME/YOUR_REPO.git

# 推送代码到 Gitee
git push gitee main

# 推送标签到 Gitee
git push gitee v1.0.0
```

## 使用方式

### 创建 Release

使用更新后的脚本：

```bash
# 自动检测平台
./scripts/create_release.sh 1.0.0

# 明确指定 Gitee
./scripts/create_release.sh 1.0.0 --gitee

# 明确指定 GitHub
./scripts/create_release.sh 1.0.0 --github
```

### 手动创建标签

```bash
# 创建标签
git tag v1.0.0

# 推送到 Gitee
git push gitee v1.0.0

# 或推送到 GitHub
git push origin v1.0.0
```

## Gitee vs GitHub 差异

### API 端点

- **GitHub**: `https://api.github.com/`
- **Gitee**: `https://gitee.com/api/v5/`

### Release 下载链接

- **GitHub**: `https://github.com/owner/repo/releases/download/v1.0.0/file.zip`
- **Gitee**: `https://gitee.com/owner/repo/releases/download/v1.0.0/file.zip`

### Raw 文件访问

- **GitHub**: `https://raw.githubusercontent.com/owner/repo/main/file.json`
- **Gitee**: `https://gitee.com/owner/repo/raw/main/file.json`

### Workflow 文件位置

- **GitHub**: `.github/workflows/build.yml`
- **Gitee**: `.gitee/workflows/build.yml`

## 注意事项

1. **Gitee Go 兼容性**
   - Gitee Go 支持 GitHub Actions 兼容格式，但可能需要调整
   - 如果遇到兼容性问题，请参考 Gitee Go 官方文档

2. **API 限制**
   - Gitee API 有调用频率限制
   - 注意避免频繁触发构建

3. **双平台同步**
   - 可以同时使用 GitHub 和 Gitee
   - 更新配置文件会分别生成：`update_config_github.json` 和 `update_config_gitee.json`

4. **客户端配置**
   - 客户端应用需要配置更新检查 URL
   - GitHub: `https://raw.githubusercontent.com/owner/repo/main/update_config_github.json`
   - Gitee: `https://gitee.com/owner/repo/raw/main/update_config_gitee.json`

## 故障排除

### Workflow 不触发

1. 检查 `.gitee/workflows/build.yml` 文件是否存在
2. 检查 Gitee Go 是否已启用
3. 检查标签格式是否正确（`v*`）

### Release 创建失败

1. 检查 `GITEE_TOKEN` 是否正确配置
2. 检查 `GITEE_REPO_OWNER` 和 `GITEE_REPO_NAME` 是否正确
3. 检查 API 调用是否超出频率限制

### 更新配置文件未生成

1. 检查构建是否成功完成
2. 检查是否有写入仓库的权限
3. 查看 Gitee Go 日志中的错误信息

## 相关文档

- [Gitee Actions 设置文档](./GITEE_ACTIONS_SETUP.md)
- [GitHub Actions 设置文档](./GITHUB_ACTIONS_SETUP.md)
- [CI/CD 配置文档](./CI_CD_SETUP.md)
- [版本管理文档](./VERSION_MANAGEMENT.md)

