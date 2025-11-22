# 双平台快速开始指南

## 5分钟完成配置

### 步骤1：配置双远程仓库（1分钟）

```bash
# 运行配置脚本
./scripts/setup_dual_remote.sh

# 如果知道 Gitee URL，可以直接传入
./scripts/setup_dual_remote.sh https://gitee.com/your-username/HelloKnightRemoteCam.git
```

脚本会自动：
- 检测当前的 `origin` 是 GitHub 还是 Gitee
- 提示输入另一个平台的 URL
- 配置多个 push URL，实现自动双平台推送

### 步骤2：安装 Git 配置（1分钟）

```bash
./scripts/install_git_hooks.sh
```

脚本会：
- 验证双远程仓库配置
- 创建 Git 别名
- 显示配置状态

### 步骤3：测试配置（1分钟）

```bash
# 创建一个测试提交
git commit --allow-empty -m "测试双平台推送"

# 推送到 origin（会自动推送到两个平台）
git push origin main

# 检查两个平台的提交是否同步
```

### 步骤4：配置 CI/CD Secrets（2分钟）

#### GitHub Actions
在 GitHub 仓库设置中配置：
- `GITHUB_TOKEN`（自动提供）

#### Gitee Go
在 Gitee 仓库设置中配置：
- `GITEE_TOKEN` - Gitee 个人访问令牌
- `GITEE_REPO_OWNER` - 你的 Gitee 用户名
- `GITEE_REPO_NAME` - 仓库名称

## 完成！现在可以无感知使用了

### 日常操作（完全无感知）

```bash
# 推送代码（自动推送到两个平台）
git push origin main

# 推送标签（自动推送到两个平台）
git push origin v1.0.0

# 创建 Release（自动推送到两个平台并触发 CI/CD）
./scripts/create_release.sh 1.0.0
```

**所有操作都会自动同步到两个平台，无需额外步骤！**

## 验证配置

### 查看远程仓库配置

```bash
git remote -v
```

应该看到：
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
# 创建测试提交
echo "test" >> test.txt
git add test.txt
git commit -m "测试双平台推送"

# 推送到 origin（会自动推送到两个平台）
git push origin main

# 检查两个平台是否都有这个提交
```

## 故障排除

### 推送失败

如果推送到一个平台失败：

```bash
# 手动推送到单个平台
git push github main
git push gitee main
```

### 重新配置

如果配置丢失：

```bash
# 重新运行配置脚本
./scripts/setup_dual_remote.sh
./scripts/install_git_hooks.sh
```

## 更多信息

- [完整配置文档](DUAL_PLATFORM_SETUP.md)
- [Gitee Actions 设置](GITEE_ACTIONS_SETUP.md)
- [GitHub Actions 设置](GITHUB_ACTIONS_SETUP.md)

