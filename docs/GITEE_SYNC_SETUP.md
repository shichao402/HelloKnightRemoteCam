# Gitee Release 同步配置

## 概述

本项目使用 GitHub Actions 构建所有平台的应用，然后自动同步 Release 到 Gitee。这样既利用了 GitHub Actions 的强大构建能力，又能在 Gitee 上提供下载。

## 工作流程

1. **GitHub Actions 构建**（`.github/workflows/build.yml`）
   - 构建 macOS 客户端
   - 构建 Windows 客户端
   - 构建 Android 服务器
   - 创建 GitHub Release
   - 生成更新配置文件

2. **自动同步到 Gitee**（`.github/workflows/sync-to-gitee.yml`）
   - 当 GitHub Release 发布时自动触发
   - 下载 GitHub Release 文件
   - 创建 Gitee Release
   - 上传文件到 Gitee Release
   - 同步更新配置文件到 Gitee

## 配置步骤

### 1. 配置 GitHub Secrets

在 GitHub 仓库设置中添加以下 Secrets：

| Secret 名称 | 说明 | 如何获取 |
|------------|------|----------|
| `GITEE_TOKEN` | Gitee 个人访问令牌 | Gitee 设置 → 安全设置 → 私人令牌 |
| `GITEE_REPO_OWNER` | Gitee 用户名 | 例如：`your-username` |
| `GITEE_REPO_NAME` | 仓库名称 | 例如：`HelloKnightRemoteCam` |

### 2. 获取 Gitee Token

1. 登录 Gitee
2. 进入 设置 → 安全设置 → 私人令牌
3. 生成新令牌
4. 权限选择：`projects`、`pull_requests`、`issues`、`notes`、`repository`
5. 复制令牌并添加到 GitHub Secrets

### 3. 验证配置

创建测试 Release：

```bash
# 创建标签并推送
git tag v1.0.0-test
git push origin v1.0.0-test

# 在 GitHub 创建 Release（或使用脚本）
./scripts/create_release.sh 1.0.0-test
```

检查：
1. GitHub Actions 是否成功构建
2. GitHub Release 是否创建
3. Gitee Release 是否自动同步
4. Gitee 仓库的 `update_config_gitee.json` 是否更新

## 使用方式

### 创建 Release（完全无感知）

```bash
# 创建 Release（会自动同步到 Gitee）
./scripts/create_release.sh 1.0.0
```

流程：
1. 创建标签并推送到 GitHub
2. GitHub Actions 自动构建
3. 创建 GitHub Release
4. **自动同步到 Gitee Release**（如果配置了 Secrets）
5. 更新配置文件到 Gitee

### 手动触发同步

如果需要手动触发同步（例如修复同步失败）：

1. 在 GitHub Actions 页面
2. 找到 "Sync Release to Gitee" workflow
3. 点击 "Run workflow"
4. 选择已发布的 Release

## 更新配置文件

同步后会自动生成两个更新配置文件：

- **GitHub**: `update_config_github.json`
  - URL: `https://raw.githubusercontent.com/owner/repo/main/update_config_github.json`
  - 下载链接指向 GitHub Releases

- **Gitee**: `update_config_gitee.json`
  - URL: `https://gitee.com/owner/repo/raw/main/update_config_gitee.json`
  - 下载链接指向 Gitee Releases

## 故障排除

### 同步失败

**问题：** Gitee Release 未创建

**检查：**
1. GitHub Secrets 是否正确配置
2. GITEE_TOKEN 是否有足够权限
3. GITEE_REPO_OWNER 和 GITEE_REPO_NAME 是否正确
4. 查看 GitHub Actions 日志中的错误信息

### 文件上传失败

**问题：** Release 创建了但文件未上传

**解决：**
1. 检查 Gitee API 调用是否成功
2. 文件可能已存在（Gitee 不允许重复上传）
3. 查看 Actions 日志中的详细错误

### 配置文件未同步

**问题：** `update_config_gitee.json` 未更新

**检查：**
1. 确认 `update_config_github.json` 已生成
2. 检查 Git push 权限
3. 查看 Actions 日志

## 优势

✅ **简单可靠**
- 利用 GitHub Actions 的强大构建能力
- 自动同步，无需手动操作

✅ **GitHub 构建，Gitee 同步**
- GitHub：完整的 CI/CD 流程
- Gitee：Release 同步和下载（可选）

✅ **无感知使用**
- 创建 Release 时自动同步
- 用户无需额外操作

## 相关文档

- [GitHub Actions 配置文档](./GITHUB_ACTIONS_SETUP.md)
- [CI/CD 配置文档](./CI_CD_SETUP.md)

