# 自动更新功能文档

## 概述

本项目实现了基于 GitHub Releases 的自动更新功能。系统在推送版本标签时自动构建应用，创建 GitHub Release，并生成更新配置文件。客户端可以自动检查并下载更新。

## 工作流程

1. **构建应用**：GitHub Actions 自动构建各平台应用
2. **创建 Release**：自动创建 GitHub Release 并上传构建产物
3. **生成更新配置**：自动生成包含所有平台下载URL的JSON配置文件
4. **推送配置文件**：将配置文件推送到 GitHub 仓库
5. **客户端检查更新**：客户端从固定URL获取更新信息并提示用户

## 更新配置文件

### 文件位置

**文件路径:** `update_config_github.json`  
**访问 URL:** `https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json`

### 配置格式

**重要说明：** 更新列表中**仅包含zip包**，其他格式的文件（如dmg、exe等）不会出现在更新列表中。

```json
{
  "client": {
    "version": "1.0.0+1",
    "versionNumber": "1.0.0",
    "platforms": {
      "macos": {
        "version": "1.0.0+1",
        "versionNumber": "1.0.0",
        "downloadUrl": "https://github.com/shichao402/HelloKnightRemoteCam/releases/download/v1.0.0/HelloKnightRCC_macos_1.0.0+1.zip",
        "fileName": "HelloKnightRCC_macos_1.0.0+1.zip",
        "fileType": "zip",
        "platform": "macos"
      },
      "windows": {
        "version": "1.0.0+1",
        "versionNumber": "1.0.0",
        "downloadUrl": "https://github.com/shichao402/HelloKnightRemoteCam/releases/download/v1.0.0/HelloKnightRCC_windows_1.0.0+1.zip",
        "fileName": "HelloKnightRCC_windows_1.0.0+1.zip",
        "fileType": "zip",
        "platform": "windows"
      }
    }
  },
  "server": {
    "version": "1.0.0+1",
    "versionNumber": "1.0.0",
    "platforms": {
      "android": {
        "version": "1.0.0+1",
        "versionNumber": "1.0.0",
        "downloadUrl": "https://github.com/shichao402/HelloKnightRemoteCam/releases/download/v1.0.0/helloknightrcc_server_android_1.0.0+1.zip",
        "fileName": "helloknightrcc_server_android_1.0.0+1.zip",
        "fileType": "zip",
        "platform": "android"
      }
    }
  },
  "updateCheckUrl": "https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json",
  "lastUpdated": "2025-01-21T10:00:00Z"
}
```

### 发布文件说明

**GitHub Release 中只包含zip文件：**
- macOS: `HelloKnightRCC_macos_<version>.zip`
- Windows: `HelloKnightRCC_windows_<version>.zip`
- Android: `helloknightrcc_server_android_<version>.zip`

**注意：** 虽然构建过程中可能生成其他格式的文件（如dmg、exe等），但这些文件**不会上传到Release**，也不会出现在更新列表中。更新列表和Release中**仅包含zip包**。

## 完整发布流程

### 1. 更新版本号

```bash
# 使用版本管理脚本
./scripts/version.sh bump patch  # 或 minor, major
./scripts/version.sh sync        # 同步到 pubspec.yaml
```

### 2. 提交代码

```bash
git add .
git commit -m "准备发布版本 X.X.X"
git push origin main
```

### 3. 创建并推送版本标签

```bash
git tag v1.0.0  # 替换为实际版本号
git push origin v1.0.0
```

### 4. 等待 GitHub Actions 完成

- 查看 Actions 页面：https://github.com/shichao402/HelloKnightRemoteCam/actions
- 等待所有构建完成（约 10-20 分钟）

### 5. 验证发布

- 检查 GitHub Release 页面
- 检查 `update_config_github.json` 文件是否已更新

## 客户端使用

### 默认配置

客户端和服务端应用默认使用以下更新检查 URL：

```
https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json
```

### 自定义更新源

用户可以在应用设置中修改更新检查 URL，使用自定义的更新源。

## 故障排除

### 更新检查失败

1. 检查网络连接
2. 检查更新检查 URL 是否正确
3. 检查更新配置文件是否可以访问

### 下载失败

1. 检查下载 URL 是否可访问
2. 检查 GitHub Release 是否存在
3. 检查文件是否已上传到 Release

## 相关文档

- [CI/CD 配置文档](./CI_CD_SETUP.md)
- [GitHub Actions 配置文档](./GITHUB_ACTIONS_SETUP.md)
- [版本管理文档](./VERSION_MANAGEMENT.md)
