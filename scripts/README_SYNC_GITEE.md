# Gitee 同步脚本使用说明

## 概述

`sync_to_gitee.sh` 是一个本地脚本，用于将 GitHub Release 同步到 Gitee。它仿照了 GitHub Actions 工作流 `.github/workflows/sync-to-gitee.yml` 的完整流程。

## 功能

脚本会执行以下步骤：

1. **检查环境变量配置**
   - 验证必需的 Gitee 配置
   - 设置 GitHub 仓库信息（可选）

2. **提取 Release 标签**
   - 从参数获取版本号，或从 GitHub API 获取最新 Release

3. **获取 Release 信息**
   - 从 GitHub API 获取 Release 详细信息

4. **下载构建产物**
   - 使用 GitHub CLI 或 curl 下载所有构建产物文件

5. **提取版本信息**
   - 从 build tag 的 VERSION.yaml 提取版本信息

6. **创建 Gitee Release**
   - 验证 Gitee 仓库
   - 删除旧 Release（如果存在）
   - 创建标签（如果不存在）
   - 创建新的 Gitee Release

7. **上传构建产物**
   - 上传所有构建产物文件到 Gitee Release
   - 支持重试机制和进度显示

8. **同步更新配置**
   - 转换更新配置文件为 Gitee 格式
   - 创建配置 Release（UpdateConfig）
   - 上传配置文件

## 使用方法

### 1. 创建配置文件

在项目根目录创建 `gitee_config.yaml` 配置文件：

```yaml
gitee:
  # Gitee 访问令牌（必需）
  token: "your_gitee_token"
  
  # Gitee 仓库所有者（用户名或组织名，必需）
  repo_owner: "your_gitee_username"
  
  # Gitee 仓库名称（必需）
  repo_name: "your_repo_name"

github:
  # GitHub 访问令牌（可选）
  # 如果未设置，会尝试使用公开 API 下载 Release
  token: "your_github_token"
  
  # GitHub 仓库所有者（可选，默认使用 Gitee 的 repo_owner）
  repo_owner: "your_github_username"
  
  # GitHub 仓库名称（可选，默认使用 Gitee 的 repo_name）
  repo_name: "your_repo_name"
```

**注意**: `gitee_config.yaml` 已添加到 `.gitignore`，不会被提交到仓库，确保敏感信息安全。

### 2. 运行脚本

```bash
# 同步指定版本的 Release
./scripts/sync_to_gitee.sh 1.0.7

# 同步最新 Release（不提供版本号）
./scripts/sync_to_gitee.sh

# 查看帮助信息
./scripts/sync_to_gitee.sh --help
```

## 配置文件说明

### 必需配置

- **gitee.token**: Gitee 访问令牌
  - 获取方式：Gitee 设置 → 安全设置 → 私人令牌
  - 需要 `projects` 权限

- **gitee.repo_owner**: Gitee 仓库所有者（用户名或组织名）

- **gitee.repo_name**: Gitee 仓库名称

### 可选配置

- **github.token**: GitHub 访问令牌
  - 用于下载 Release 文件（如果未设置，会尝试使用公开 API）
  - 获取方式：GitHub Settings → Developer settings → Personal access tokens
  - 需要 `public_repo` 权限

- **github.repo_owner**: GitHub 仓库所有者（默认使用 Gitee 的 repo_owner）

- **github.repo_name**: GitHub 仓库名称（默认使用 Gitee 的 repo_name）

## 工作流程

### 1. 版本号处理

- 如果提供了版本号参数（如 `1.0.7`），会自动添加 `v` 前缀（`v1.0.7`）
- 如果未提供版本号，会从 GitHub API 获取最新 Release 标签

### 2. 构建产物下载

脚本会尝试两种方式下载构建产物：

1. **GitHub CLI**（如果已安装且设置了 GITHUB_TOKEN）
   ```bash
   gh release download <tag> -D release-assets
   ```

2. **curl**（备用方案）
   - 使用 GitHub API 获取所有 assets 的下载 URL
   - 逐个下载文件

### 3. 版本信息提取

脚本会尝试从 build tag（如 `build1.0.7`）的 `VERSION.yaml` 提取版本信息：

- 如果找到 build tag，会 checkout `VERSION.yaml`
- 使用 Python 解析 YAML 文件获取完整版本号
- 如果找不到，会使用 Release 标签的版本号

### 4. Gitee Release 创建

- 验证 Gitee 仓库是否存在
- 获取 tag 对应的 commit SHA（如果 tag 不存在，使用默认分支的最新 commit）
- 删除所有匹配 tag 的旧 Release
- 创建 tag（如果不存在）
- 创建新的 Release

### 5. 文件上传

- 支持大文件上传（自动计算超时时间）
- 每个文件上传前等待 2 秒（避免 API 限流）
- 支持重试机制（最多 3 次）
- 显示上传进度和统计信息

### 6. 更新配置同步

- 从下载的 `update_config_github.json` 读取配置
- 转换为 Gitee 格式（替换 URL）
- 创建固定的配置 Release（tag: `config`，名称: `UpdateConfig`）
- 上传配置文件

## 错误处理

脚本包含完善的错误处理：

- **环境变量检查**: 启动时检查必需的环境变量
- **API 错误处理**: 检查 HTTP 状态码，显示详细错误信息
- **重试机制**: 上传文件时自动重试（最多 3 次）
- **超时处理**: 根据文件大小自动计算超时时间
- **进度显示**: 实时显示上传进度和统计信息

## 注意事项

1. **网络连接**: 确保能够访问 GitHub 和 Gitee API
2. **文件大小**: 大文件上传可能需要较长时间，请耐心等待
3. **API 限流**: Gitee API 有速率限制，脚本会自动添加延迟
4. **权限要求**: Gitee Token 需要有仓库的写入权限
5. **Git 仓库**: 脚本需要在 Git 仓库中运行（用于 checkout build tag）

## 示例输出

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Gitee 同步脚本
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 检查环境变量配置...
✅ 环境变量检查通过
  Gitee 仓库: username/repo_name
  GitHub 仓库: username/repo_name

🔍 提取 Release 标签...
✅ 使用指定版本号: 1.0.7，转换为标签 v1.0.7

🔍 获取 Release 信息...
✅ Release 信息获取成功
  ID: 12345678
  名称: Release 1.0.7
  标签: v1.0.7

📥 下载构建产物文件...
  ...

✅ 同步完成！
```

## 与 GitHub Actions 工作流的区别

本地脚本与 GitHub Actions 工作流的主要区别：

1. **配置方式**: 使用本地 YAML 配置文件，而不是 GitHub Secrets
2. **GitHub Token**: 可选，如果未设置会使用公开 API
3. **错误处理**: 更详细的错误信息和进度显示
4. **交互性**: 可以在本地直接运行和调试
5. **安全性**: 配置文件已添加到 `.gitignore`，不会被提交到仓库

## 故障排查

### 问题：配置文件不存在

**解决方案**:
- 在项目根目录创建 `gitee_config.yaml` 文件
- 参考文档填写正确的配置信息

### 问题：无法获取 Release 信息

**解决方案**:
- 检查配置文件中的 GitHub Token 是否正确
- 确认 Release 标签是否存在
- 检查网络连接

### 问题：文件上传失败

**解决方案**:
- 检查配置文件中的 Gitee Token 权限
- 确认文件大小是否超过限制
- 检查网络连接和超时设置

### 问题：无法找到 VERSION.yaml

**解决方案**:
- 确认 build tag 是否存在（如 `build1.0.7`）
- 检查当前目录是否是 Git 仓库
- 运行 `git fetch --tags` 更新标签

## 相关文件

- `.github/workflows/sync-to-gitee.yml`: GitHub Actions 工作流
- `scripts/create_release.sh`: 创建 Release 脚本
- `scripts/README_TEST_GITEE.md`: Gitee API 测试说明
- `gitee_config.yaml`: 本地配置文件（已添加到 `.gitignore`）

