# CI/CD 配置文档

## 概述

本项目使用 GitHub Actions 实现自动化的 CI/CD 流程，包括构建、发布和更新配置生成。

## 工作流程

### 1. 代码推送阶段

当你推送代码到 GitHub 时：

- 触发 GitHub Actions workflow (`.github/workflows/build.yml`)
- 构建 macOS、Windows 客户端和 Android 服务器
- 构建产物上传到 GitHub Actions artifacts（临时存储）

### 2. 发布阶段

当你推送版本标签（如 `v1.0.5`）时：

1. 从构建 artifacts 下载所有构建产物
2. 创建 GitHub Release，**仅上传zip文件**（不包含dmg、exe等其他格式）
3. 生成 `update_config_github.json` 配置文件（**仅包含zip包的下载链接**）
4. 将配置文件提交并推送到 GitHub 仓库的 `main` 分支

**重要说明：** 发布后，更新列表中**仅包含zip包**，其他格式的文件不会出现在更新列表中。

## 配置文件说明

### GitHub 更新配置

**文件路径:** `update_config_github.json`  
**访问 URL:** `https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json`

**下载链接格式:**
```
https://github.com/shichao402/HelloKnightRemoteCam/releases/download/v1.0.5/HelloKnightRCC_macos_1.0.5+1.zip
```

**注意：** 更新配置中**仅包含zip包的下载链接**，不包含其他格式的文件（如dmg、exe等）。

**macOS zip包结构：**
- zip包内包含dmg文件
- 用户需要解压zip得到dmg文件
- 打开dmg文件后，将应用拖动到Applications文件夹覆盖现有程序

## 客户端配置

客户端和服务端应用默认使用 GitHub 的更新检查 URL：

**默认 URL:** `https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json`

用户可以在应用设置中修改更新检查 URL。

## 发布流程

### 1. 准备发布

1. 更新版本号（在 `client/pubspec.yaml` 和 `server/pubspec.yaml` 中）
2. 提交代码更改
3. 推送到 GitHub

### 2. 创建发布标签

```bash
# 创建并推送标签
git tag v1.0.5
git push origin v1.0.5
```

### 3. 等待 CI/CD 完成

在 GitHub Actions 中查看构建和发布状态。

### 4. 验证发布

- 检查 GitHub Release 页面
- 检查 `update_config_github.json` 文件是否已更新

## 故障排除

### GitHub Actions 失败

1. 检查 GitHub Actions 日志
2. 确认构建产物是否成功生成
3. 检查版本号是否正确

### 更新配置未生成

1. 检查是否推送了版本标签（格式：`v*`）
2. 检查 CI/CD 日志中的错误信息
3. 确认有写入仓库的权限

## 注意事项

1. **版本号一致性**: 确保标签版本号与 `pubspec.yaml` 中的版本号一致（或使用标签版本号）
2. **构建产物命名**: 构建产物的文件名必须与更新配置中的文件名匹配
3. **权限要求**: CI/CD 需要写入仓库的权限（GitHub: `contents: write`）
