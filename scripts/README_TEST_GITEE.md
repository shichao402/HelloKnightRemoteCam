# Gitee API 测试工具使用说明

## 概述

`test_gitee_api.sh` 是一个本地测试脚本，用于验证 Gitee API 调用，避免在 GitHub Actions 中反复调试。

## 使用方法

### 1. 设置环境变量

```bash
export GITEE_TOKEN="your_gitee_token"
export GITEE_REPO_OWNER="your_gitee_username"
export GITEE_REPO_NAME="your_repo_name"

# 可选：如果需要从 GitHub 获取 commit SHA
export GITHUB_TOKEN="your_github_token"
export GITHUB_REPO_OWNER="your_github_username"  # 可选，默认使用 GITEE_REPO_OWNER
export GITHUB_REPO_NAME="your_repo_name"        # 可选，默认使用 GITEE_REPO_NAME
```

### 2. 运行测试脚本

```bash
# 测试默认标签 v1.0.7
./scripts/test_gitee_api.sh

# 测试指定标签
./scripts/test_gitee_api.sh v1.0.8
```

## 测试步骤

脚本会执行以下步骤：

1. **验证 Gitee 仓库是否存在**
   - 检查仓库是否可访问
   - 显示仓库信息和默认分支

2. **从 GitHub 获取标签对应的 commit SHA**（如果设置了 GITHUB_TOKEN）
   - 尝试多种方式获取 commit SHA
   - 显示获取到的 commit SHA

3. **检查 Gitee 仓库中是否存在该 commit**
   - 如果不存在，会尝试获取默认分支的最新 commit
   - 提供解决方案建议

4. **检查 Gitee 标签是否存在**
   - 如果不存在，会尝试创建标签
   - 测试不同的 API 参数（refs 和 ref）

## 常见问题

### 问题 1: "起点不存在" (refs is missing)

**原因**: Gitee 仓库中不存在该 commit SHA

**解决方案**:
1. 确保 Gitee 仓库已同步 GitHub 的代码
2. 或者使用 Gitee 仓库中存在的 commit SHA

### 问题 2: 无法获取 commit SHA

**原因**: GitHub token 未设置或标签不存在

**解决方案**:
1. 设置 `GITHUB_TOKEN` 环境变量
2. 确保标签在 GitHub 中存在

### 问题 3: 创建标签失败

**原因**: API 参数错误或 commit 不存在

**解决方案**:
1. 检查 commit 是否存在于 Gitee 仓库
2. 使用测试脚本验证 API 调用
3. 查看错误信息，根据错误调整参数

## 示例输出

```
=== Gitee API 测试工具 ===

配置信息:
  仓库: username/repo_name
  Owner: username
  Repo Name: repo_name

测试标签: v1.0.7

步骤 1: 验证 Gitee 仓库是否存在...
  API URL: https://gitee.com/api/v5/repos/username/repo_name
  HTTP 状态码: 200
✅ Gitee 仓库验证通过
  仓库全名: username/repo_name
  默认分支: master

步骤 2: 从 GitHub 获取标签对应的 commit SHA...
  查询 GitHub 仓库: username/repo_name
✅ 标签 v1.0.7 对应的 commit SHA: 56e0fdb...

步骤 3: 检查 Gitee 仓库中是否存在该 commit...
  API URL: https://gitee.com/api/v5/repos/username/repo_name/git/commits/56e0fdb...
  HTTP 状态码: 200
✅ Commit 56e0fdb... 存在于 Gitee 仓库

步骤 4: 检查 Gitee 标签是否存在...
  标签检查 API URL: https://gitee.com/api/v5/repos/username/repo_name/tags/v1.0.7
  HTTP 状态码: 404
⚠️  标签 v1.0.7 不存在

步骤 5: 尝试创建 Gitee 标签...
  创建标签 API URL: https://gitee.com/api/v5/repos/username/repo_name/tags
  请求体 (使用 refs): {"refs":"56e0fdb...","tag_name":"v1.0.7","message":"Release v1.0.7"}
  响应 HTTP 状态码: 201
✅ 标签 v1.0.7 创建成功

=== 测试完成 ===
```

## 注意事项

1. **Token 安全**: 不要在脚本中硬编码 token，使用环境变量
2. **仓库同步**: 确保 Gitee 仓库已同步 GitHub 的代码
3. **API 限制**: Gitee API 有速率限制，不要频繁调用
4. **参数测试**: 脚本会测试不同的 API 参数，帮助找到正确的调用方式

