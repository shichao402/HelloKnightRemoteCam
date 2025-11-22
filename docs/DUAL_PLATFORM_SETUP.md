# 双平台自动推送配置指南

## 概述

本项目已配置支持自动同步推送到 GitHub 和 Gitee 两个平台，实现完全无感知的双平台操作。

## 快速开始

### 1. 一次性配置

```bash
# 配置双远程仓库（首次运行）
./scripts/setup_dual_remote.sh [gitee_url]

# 安装 Git 配置和别名
./scripts/install_git_hooks.sh
```

### 2. 日常使用（完全无感知）

配置完成后，你只需要像往常一样操作：

```bash
# 推送代码（自动推送到两个平台）
git push origin main

# 推送标签（自动推送到两个平台）
git push origin v1.0.0

# 创建 Release（自动推送到两个平台）
./scripts/create_release.sh 1.0.0
```

**所有操作都会自动同步到两个平台，无需额外步骤！**

## 工作原理

### 方法1：Git 多 Push URL（推荐）

配置 `origin` 的多个 push URL，当执行 `git push origin` 时自动推送到两个平台：

```bash
git remote set-url --add --push origin <github_url>
git remote set-url --add --push origin <gitee_url>
```

**优点：**
- 完全无感知，使用 `git push origin` 即可
- 自动推送到两个平台
- 不需要改变现有工作流程

### 方法2：Git 别名

创建便捷的 Git 别名：

```bash
# 推送到所有远程仓库
git push-all main

# 推送到 GitHub 和 Gitee
git push-both main
```

## 配置步骤详解

### 步骤1：配置双远程仓库

运行配置脚本：

```bash
./scripts/setup_dual_remote.sh
```

脚本会：
1. 检测当前的 `origin` 是 GitHub 还是 Gitee
2. 提示输入另一个平台的仓库 URL
3. 自动添加远程仓库（`github` 或 `gitee`）
4. 配置 `origin` 的多个 push URL

**示例：**

```bash
# 如果 origin 是 GitHub
$ ./scripts/setup_dual_remote.sh
当前 origin 远程仓库: https://github.com/user/repo.git
请输入 Gitee 仓库 URL: https://gitee.com/user/repo.git
添加 Gitee 远程仓库: https://gitee.com/user/repo.git
配置 origin 同时推送到 GitHub 和 Gitee...
✅ 已配置 origin 同时推送到两个平台
```

### 步骤2：安装 Git 配置

运行安装脚本：

```bash
./scripts/install_git_hooks.sh
```

脚本会：
1. 验证双远程仓库配置
2. 配置 Git 别名（`push-all`、`push-both`）
3. 显示当前配置状态

## 使用方式

### 推送代码

**方式1：使用 origin（推荐，自动双平台）**
```bash
git push origin main
# 自动推送到 GitHub 和 Gitee
```

**方式2：使用别名**
```bash
git push-all main
# 推送到所有远程仓库

git push-both main
# 推送到 GitHub 和 Gitee
```

**方式3：使用脚本**
```bash
./scripts/push_to_both.sh main
# 推送到两个平台，带详细输出
```

### 推送标签

```bash
# 方式1：使用 origin（自动双平台）
git push origin v1.0.0

# 方式2：使用脚本
./scripts/push_to_both.sh main --tags
```

### 创建 Release

```bash
# 自动推送到两个平台并触发 CI/CD
./scripts/create_release.sh 1.0.0
```

脚本会：
1. 创建标签
2. 推送到 origin（自动同步到两个平台）
3. 触发两个平台的 CI/CD 构建

## 验证配置

### 查看远程仓库

```bash
git remote -v
```

应该看到类似输出：

```
gitee    https://gitee.com/user/repo.git (fetch)
gitee    https://gitee.com/user/repo.git (push)
github   https://github.com/user/repo.git (fetch)
github   https://github.com/user/repo.git (push)
origin   https://github.com/user/repo.git (fetch)
origin   https://github.com/user/repo.git (push)
origin   https://gitee.com/user/repo.git (push)  # 多个 push URL
```

### 测试推送

```bash
# 创建一个测试提交
echo "test" >> test.txt
git add test.txt
git commit -m "测试双平台推送"

# 推送到 origin（会自动推送到两个平台）
git push origin main

# 检查两个平台的提交是否同步
```

## CI/CD 自动触发

当推送标签到两个平台时，会自动触发：

- **GitHub**: GitHub Actions 构建和发布
- **Gitee**: Gitee Go 构建和发布

两个平台会：
1. 构建所有平台的应用
2. 创建 Release
3. 生成更新配置文件
4. 推送配置文件到仓库

## 故障排除

### 推送失败

**问题：** 推送到一个平台失败

**解决：**
1. 检查网络连接
2. 检查认证信息（SSH key 或 token）
3. 检查远程仓库 URL 是否正确

**临时方案：**
```bash
# 手动推送到单个平台
git push github main
git push gitee main
```

### 配置丢失

**问题：** 多 push URL 配置丢失

**解决：**
```bash
# 重新运行配置脚本
./scripts/setup_dual_remote.sh
./scripts/install_git_hooks.sh
```

### 只推送到一个平台

**问题：** 只想推送到 GitHub 或 Gitee

**解决：**
```bash
# 推送到特定平台
git push github main
git push gitee main

# 或使用脚本
./scripts/push_to_both.sh main  # 会尝试两个平台，失败不影响
```

## 最佳实践

1. **首次配置后测试**
   ```bash
   # 创建测试提交并推送
   git commit --allow-empty -m "测试双平台推送"
   git push origin main
   ```

2. **定期检查同步状态**
   ```bash
   # 检查两个平台的提交是否一致
   git fetch github
   git fetch gitee
   git log --oneline --graph --all -10
   ```

3. **使用 Release 脚本**
   ```bash
   # 创建 Release 时使用脚本，确保标签同步
   ./scripts/create_release.sh 1.0.0
   ```

4. **保持 workflow 文件同步**
   - `.github/workflows/build.yml` (GitHub Actions)
   - `.gitee/workflows/build.yml` (Gitee Go)
   - 两个文件应该保持一致

## 注意事项

1. **认证信息**
   - 确保两个平台都已配置认证（SSH key 或 token）
   - GitHub 和 Gitee 的认证是独立的

2. **网络环境**
   - 如果某个平台访问受限，推送可能会失败
   - 失败不会影响另一个平台的推送

3. **CI/CD 配置**
   - 两个平台都需要单独配置 Secrets
   - GitHub: `GITHUB_TOKEN`
   - Gitee: `GITEE_TOKEN`, `GITEE_REPO_OWNER`, `GITEE_REPO_NAME`

4. **更新配置文件**
   - GitHub 生成: `update_config_github.json`
   - Gitee 生成: `update_config_gitee.json`
   - 两个文件格式相同，但 URL 不同

## 相关文档

- [Gitee Actions 设置文档](./GITEE_ACTIONS_SETUP.md)
- [GitHub Actions 设置文档](./GITHUB_ACTIONS_SETUP.md)
- [CI/CD 配置文档](./CI_CD_SETUP.md)
- [版本管理文档](./VERSION_MANAGEMENT.md)

