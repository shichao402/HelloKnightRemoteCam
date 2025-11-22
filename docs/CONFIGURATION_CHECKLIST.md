# 双平台配置清单

## ✅ 已自动完成（无需操作）

- ✅ Gitee Go workflow 文件已创建 (`.gitee/workflows/build.yml`)
- ✅ 更新配置文件模板已创建 (`update_config_gitee.json`)
- ✅ 脚本已创建并设置执行权限
- ✅ 文档已创建

## ⚠️ 需要你手动配置的项

### 1. 添加 Gitee 远程仓库（必需）

**方式1：使用脚本（推荐）**
```bash
# 运行配置脚本，会提示输入 Gitee 仓库 URL
./scripts/setup_dual_remote.sh

# 或直接传入 Gitee URL
./scripts/setup_dual_remote.sh https://gitee.com/your-username/HelloKnightRemoteCam.git
```

**方式2：手动添加**
```bash
# 添加 Gitee 远程仓库
git remote add gitee https://gitee.com/your-username/HelloKnightRemoteCam.git

# 配置 origin 同时推送到两个平台（可选，推荐）
git remote set-url --add --push origin https://github.com/shichao402/HelloKnightRemoteCam.git
git remote set-url --add --push origin https://gitee.com/your-username/HelloKnightRemoteCam.git
```

**验证：**
```bash
git remote -v
# 应该看到 gitee 远程仓库
```

### 2. 在 Gitee 创建仓库（如果还没有）

1. 登录 Gitee
2. 创建新仓库：`HelloKnightRemoteCam`
3. 记录仓库 URL：`https://gitee.com/your-username/HelloKnightRemoteCam.git`

### 3. 配置 Gitee Go Secrets（必需）

在 Gitee 仓库设置中配置以下 Secrets：

1. **进入 Gitee 仓库设置**
   - 仓库 → 设置 → Gitee Go → 流水线变量

2. **添加以下变量：**

   | 变量名 | 说明 | 示例值 |
   |--------|------|--------|
   | `GITEE_TOKEN` | Gitee 个人访问令牌 | `ghp_xxxxxxxxxxxx` |
   | `GITEE_REPO_OWNER` | Gitee 用户名 | `your-username` |
   | `GITEE_REPO_NAME` | 仓库名称 | `HelloKnightRemoteCam` |

3. **获取 GITEE_TOKEN：**
   - Gitee → 设置 → 安全设置 → 私人令牌
   - 创建新令牌
   - 权限选择：`projects`、`pull_requests`、`issues`、`notes`、`repository`

### 4. 启用 Gitee Go（必需）

1. 进入 Gitee 仓库
2. 点击 "Gitee Go" 标签
3. 启用 Gitee Go 功能
4. 确保 workflow 文件 `.gitee/workflows/build.yml` 已提交到仓库

### 5. 安装 Git 配置（推荐）

```bash
./scripts/install_git_hooks.sh
```

这会创建 Git 别名，方便使用。

## 📋 快速检查清单

完成配置后，运行以下命令检查：

```bash
# 1. 检查远程仓库配置
git remote -v
# 应该看到 gitee 和 github 两个远程仓库

# 2. 测试推送（可选）
git commit --allow-empty -m "测试双平台推送"
git push origin main
# 检查两个平台是否都有这个提交

# 3. 检查 Gitee Go 配置
# 在 Gitee 仓库页面查看 "Gitee Go" 标签是否可用
```

## 🎯 配置完成后

配置完成后，你就可以：

```bash
# 推送代码（自动推送到两个平台）
git push origin main

# 创建 Release（自动推送到两个平台并触发 CI/CD）
./scripts/create_release.sh 1.0.0
```

## ❓ 常见问题

### Q: 我没有 Gitee 账号怎么办？
A: 需要先注册 Gitee 账号并创建仓库。

### Q: Gitee Go 在哪里启用？
A: 在 Gitee 仓库页面，点击 "Gitee Go" 标签，然后启用。

### Q: 如何知道配置是否成功？
A: 运行 `git remote -v` 应该看到 gitee 远程仓库。推送代码后检查两个平台是否都有提交。

### Q: 可以只配置 GitHub 不配置 Gitee 吗？
A: 可以。如果不配置 Gitee，脚本会自动检测并只推送到 GitHub。

## 📚 相关文档

- [快速开始指南](QUICK_START_DUAL_PLATFORM.md)
- [完整配置文档](DUAL_PLATFORM_SETUP.md)
- [Gitee Actions 设置](GITEE_ACTIONS_SETUP.md)

