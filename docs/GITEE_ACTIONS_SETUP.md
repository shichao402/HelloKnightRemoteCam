# Gitee Go 自动发布配置指南

## 概述

Gitee Go workflow 已配置为在推送版本标签时自动：
1. 构建所有平台的应用（macOS、Windows、Android）
2. 创建 Gitee Release
3. 生成并推送更新配置文件到 Gitee 仓库

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
   - 创建 Gitee Release
   - 上传构建产物到 Release
   - 生成更新配置文件
   - 推送配置文件到 Gitee 仓库

## 版本号管理

版本号从 `VERSION.yaml` 文件中读取：
- 客户端版本：`client.version`
- 服务器版本：`server.version`

格式：`x.y.z+build`（例如：`1.0.4+1`）

如果是从标签触发，workflow 会优先使用标签中的版本号。

## 文件命名规则

### 构建产物

- macOS: `HelloKnightRCC_macos_1.0.4+1.zip`
- Windows: `HelloKnightRCC_windows_1.0.4+1.zip`
- Android: `helloknightrcc_server_android_1.0.4+1.zip`

### Gitee Release

**重要说明：** Gitee Release 中**仅上传zip文件**，zip包内包含相应的安装文件。

- macOS: `HelloKnightRCC_macos_<version>.zip`（zip包内包含dmg文件）
- Windows: `HelloKnightRCC_windows_<version>.zip`（zip包内包含exe安装程序）
- Android: `helloknightrcc_server_android_<version>.zip`（zip包内包含apk文件）

**macOS 安装流程：**
1. 下载zip文件并解压
2. 得到dmg文件
3. 打开dmg文件
4. 将应用拖动到Applications文件夹覆盖现有程序

## 更新配置文件

生成的 `update_config_gitee.json` 包含：
- 所有平台的版本信息
- 下载 URL（指向 Gitee Releases，**仅包含zip包**）
- 更新检查 URL

**重要说明：** 更新配置文件中**仅包含zip包的下载链接**，不包含其他格式的文件。发布后，更新列表中预期只有zip包。

配置文件会自动推送到 Gitee 仓库的 `main` 分支。

## Gitee Go 配置

### 必需的环境变量

在 Gitee Go 中需要配置以下 Secrets：

1. **GITEE_TOKEN**: Gitee 个人访问令牌（Personal Access Token）
   - 获取方式：Gitee 设置 → 安全设置 → 私人令牌
   - 权限要求：`projects`、`pull_requests`、`issues`、`notes`、`repository`

2. **GITEE_REPO_OWNER**: Gitee 仓库所有者用户名
   - 例如：`your-username`

3. **GITEE_REPO_NAME**: Gitee 仓库名称
   - 例如：`HelloKnightRemoteCam`

### 配置步骤

1. 登录 Gitee，进入仓库设置
2. 进入 "Gitee Go" → "流水线设置"
3. 添加以下 Secrets：
   - `GITEE_TOKEN`: 你的 Gitee 个人访问令牌
   - `GITEE_REPO_OWNER`: 仓库所有者
   - `GITEE_REPO_NAME`: 仓库名称

### Workflow 文件位置

Workflow 文件位于：`.gitee/workflows/build.yml`

## 故障排除

### 构建失败

- 检查 Flutter 版本是否匹配（当前：3.24.0）
- 检查依赖是否正确
- 查看 Gitee Go 日志

### 配置文件推送失败

- 检查是否有写入仓库的权限
- 检查 GITEE_TOKEN 是否正确配置
- 检查分支名称是否正确（默认：`main`）

### Release 创建失败

- 检查 GITEE_TOKEN 是否有创建 Release 的权限
- 检查 GITEE_REPO_OWNER 和 GITEE_REPO_NAME 是否正确
- 检查标签是否已存在

## 手动触发（可选）

如果需要手动触发 workflow，可以：

1. 在 Gitee Go 页面点击 "运行流水线"
2. 选择分支和版本标签
3. 点击 "运行"

## 注意事项

1. **版本标签格式**：必须使用 `v*` 格式（例如：`v1.0.4`）
2. **版本号同步**：确保 `VERSION.yaml` 中的版本号已更新
3. **构建时间**：完整构建可能需要 10-20 分钟
4. **并发限制**：Gitee Go 有并发限制，请合理安排发布频率
5. **Gitee API 限制**：注意 Gitee API 的调用频率限制

## Gitee vs GitHub 差异

### API 差异

- Gitee API 使用 `https://gitee.com/api/v5/` 作为基础 URL
- Gitee Release 文件上传使用不同的 API 端点
- Gitee raw 文件访问使用 `/raw/` 路径

### 下载链接格式

**GitHub:**
```
https://github.com/owner/repo/releases/download/v1.0.4/file.zip
```

**Gitee:**
```
https://gitee.com/owner/repo/releases/download/v1.0.4/file.zip
```

### Raw 文件访问

**GitHub:**
```
https://raw.githubusercontent.com/owner/repo/main/file.json
```

**Gitee:**
```
https://gitee.com/owner/repo/raw/main/file.json
```

## 相关文档

- [自动更新功能文档](./AUTO_UPDATE.md)
- [CI/CD 配置文档](./CI_CD_SETUP.md)
- [版本管理文档](./VERSION_MANAGEMENT.md)
- [GitHub Actions 配置文档](./GITHUB_ACTIONS_SETUP.md)

