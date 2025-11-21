# 自动更新功能文档

## 概述

本项目实现了基于 GitLab Package Registry 的自动更新功能。系统支持双推送（GitHub 和 GitLab），并将构建产物上传到 GitLab Package Registry，客户端可以自动检查并下载更新。

## 工作流程

1. **构建应用**：使用现有的构建脚本构建各平台应用
2. **上传到 GitLab Package**：使用上传脚本将构建产物上传到 GitLab
3. **生成更新配置**：生成包含所有平台下载URL的JSON配置文件
4. **上传配置文件**：将配置文件推送到 GitLab 仓库
5. **客户端检查更新**：客户端从固定URL获取更新信息并提示用户

## 脚本说明

### 1. GitLab Package 上传脚本

**路径：** `scripts/upload_to_gitlab_package.sh`

**用途：** 将构建产物上传到 GitLab Generic Package Registry

**使用方法：**

```bash
# 上传客户端 macOS 版本
./scripts/upload_to_gitlab_package.sh --client --platform macos --version 1.0.0+1

# 上传客户端 Windows 版本
./scripts/upload_to_gitlab_package.sh --client --platform windows --version 1.0.0+1

# 上传服务器 Android 版本
./scripts/upload_to_gitlab_package.sh --server --platform android --version 1.0.0+1
```

**环境变量：**

- `GITLAB_URL`: GitLab 实例 URL（例如：https://gitlab.com）
- `GITLAB_PROJECT_ID`: GitLab 项目 ID 或路径
- `GITLAB_TOKEN`: GitLab 访问令牌（需要 `api` 权限）

**参数：**

- `--client`: 上传客户端构建产物
- `--server`: 上传服务器构建产物
- `--platform PLATFORM`: 平台（macos/windows/android）
- `--version VERSION`: 版本号（可选，默认从 VERSION 文件读取）
- `--debug`: 使用 debug 构建
- `--release`: 使用 release 构建（默认）

### 2. 更新配置生成脚本

**路径：** `scripts/generate_update_config.sh`

**用途：** 生成包含所有平台下载URL的JSON更新配置文件

**使用方法：**

```bash
./scripts/generate_update_config.sh \
  --output update_config.json \
  --gitlab-url https://gitlab.com \
  --project-id 123
```

**环境变量：**

- `GITLAB_URL`: GitLab 实例 URL
- `GITLAB_PROJECT_ID`: GitLab 项目 ID 或路径

**输出格式：**

```json
{
  "client": {
    "version": "1.0.0+1",
    "versionNumber": "1.0.0",
    "platforms": {
      "macos": {
        "version": "1.0.0+1",
        "versionNumber": "1.0.0",
        "downloadUrl": "https://gitlab.com/api/v4/projects/123/packages/generic/helloknightrcc-client/1.0.0/HelloKnightRCC-1.0.0-macos.zip",
        "fileName": "HelloKnightRCC-1.0.0-macos.zip",
        "fileType": "zip",
        "platform": "macos"
      },
      "windows": {
        ...
      }
    }
  },
  "server": {
    ...
  },
  "updateCheckUrl": "https://gitlab.com/api/v4/projects/123/repository/files/update_config.json/raw?ref=main",
  "lastUpdated": "2025-01-21T10:00:00Z"
}
```

### 3. 更新配置文件上传脚本

**路径：** `scripts/upload_update_config.sh`

**用途：** 将更新配置文件上传到 GitLab 仓库

**使用方法：**

```bash
./scripts/upload_update_config.sh \
  --file update_config.json \
  --commit-message "更新到版本 1.0.0" \
  --branch main \
  --remote gitlab
```

**参数：**

- `--file FILE`: 配置文件路径（默认：update_config.json）
- `--commit-message MSG`: 提交消息
- `--branch BRANCH`: 分支名称（默认：main）
- `--remote REMOTE`: 远程仓库名称（默认：gitlab）

### 4. GitLab 推送脚本

**路径：** `scripts/push_to_gitlab.sh`

**用途：** 将代码推送到 GitLab 仓库

**使用方法：**

```bash
./scripts/push_to_gitlab.sh --remote gitlab --branch main
```

**首次使用前需要添加 GitLab 远程仓库：**

```bash
git remote add gitlab <gitlab_repo_url>
```

## 完整发布流程

### 1. 准备环境变量

```bash
export GITLAB_URL="https://gitlab.com"
export GITLAB_PROJECT_ID="your-project-id"
export GITLAB_TOKEN="your-access-token"
```

### 2. 构建应用

```bash
# 构建客户端 macOS
cd client && ./scripts/deploy.sh --release --macos --no-start

# 构建客户端 Windows
cd client && ./scripts/deploy.sh --release --windows --no-start

# 构建服务器 Android
cd server && ./scripts/deploy.sh --release --no-start
```

### 3. 上传构建产物

```bash
# 上传客户端 macOS
./scripts/upload_to_gitlab_package.sh --client --platform macos

# 上传客户端 Windows
./scripts/upload_to_gitlab_package.sh --client --platform windows

# 上传服务器 Android
./scripts/upload_to_gitlab_package.sh --server --platform android
```

### 4. 生成并上传更新配置

```bash
# 生成更新配置
./scripts/generate_update_config.sh

# 上传配置文件到 GitLab
./scripts/upload_update_config.sh --commit-message "发布版本 $(./scripts/version.sh get client)"
```

### 5. 推送到 GitLab（可选）

```bash
# 推送代码到 GitLab
./scripts/push_to_gitlab.sh
```

## 客户端配置

### 设置更新检查URL

更新检查URL需要配置在客户端应用中。可以通过以下方式设置：

1. **在代码中硬编码**（不推荐）
2. **通过环境变量**（推荐用于CI/CD）
3. **通过应用设置界面**（需要添加UI）

更新检查URL格式：
```
https://gitlab.com/api/v4/projects/{project_id}/repository/files/update_config.json/raw?ref=main
```

### 客户端使用

1. **启动时自动检查**（可选）：在应用启动时调用 `UpdateService.checkForUpdate()`
2. **手动检查**：在设置界面点击"检查更新"按钮
3. **下载更新**：如果发现新版本，用户可以选择立即下载
4. **安装更新**：
   - macOS: 下载zip文件，解压后用户手动替换应用
   - Windows: 下载zip文件，解压后用户手动替换应用
   - Android: 下载APK文件，系统会自动打开安装器

## 注意事项

1. **GitLab Token 权限**：确保访问令牌具有 `api` 权限
2. **文件大小限制**：GitLab Package Registry 可能有文件大小限制，请检查
3. **版本号格式**：版本号必须遵循语义化版本格式（x.y.z+build）
4. **平台标识**：客户端会自动识别当前平台（macos/windows/android）
5. **下载目录**：更新文件会下载到应用支持目录的 `downloads` 子目录

## 故障排除

### 上传失败

- 检查 GitLab Token 是否有效
- 检查项目 ID 是否正确
- 检查文件是否存在
- 检查网络连接

### 客户端无法检查更新

- 检查更新检查URL是否正确配置
- 检查网络连接
- 查看客户端日志文件

### 下载失败

- 检查下载URL是否可访问
- 检查文件大小是否超过限制
- 检查磁盘空间是否充足

## 相关文件

- `scripts/upload_to_gitlab_package.sh`: GitLab Package 上传脚本
- `scripts/generate_update_config.sh`: 更新配置生成脚本
- `scripts/upload_update_config.sh`: 配置文件上传脚本
- `scripts/push_to_gitlab.sh`: GitLab 推送脚本
- `client/lib/services/update_service.dart`: 客户端更新服务
- `client/lib/services/update_settings_service.dart`: 更新设置服务
- `client/lib/screens/client_settings_screen.dart`: 设置界面（包含更新检查）

