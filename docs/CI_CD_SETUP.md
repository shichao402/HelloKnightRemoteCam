# CI/CD 配置文档

## 概述

本项目实现了双平台独立的 CI/CD 流程：
- **GitHub Actions**: 处理 GitHub 平台的构建、发布和更新配置
- **GitLab CI/CD**: 处理 GitLab 平台的构建、发布和更新配置

两个平台的 CI/CD 流程完全独立，互不干扰。

## 工作流程

### 1. 代码推送阶段

当你推送代码到 GitHub 或 GitLab 时：

**GitHub:**
- 触发 GitHub Actions workflow (`.github/workflows/build.yml`)
- 构建 macOS、Windows 客户端和 Android 服务器
- 构建产物上传到 GitHub Actions artifacts（临时存储）

**GitLab:**
- 触发 GitLab CI/CD pipeline (`.gitlab-ci.yml`)
- 构建 macOS、Windows 客户端和 Android 服务器（需要相应的 runner）
- 构建产物上传到 GitLab CI artifacts（临时存储）

### 2. 发布阶段

当你推送版本标签（如 `v1.0.5`）时：

**GitHub:**
1. 从构建 artifacts 下载所有构建产物
2. 创建 GitHub Release，并上传构建产物
3. 生成 `update_config_github.json` 配置文件
4. 将配置文件提交并推送到 GitHub 仓库的 `main` 分支

**GitLab:**
1. 从构建 artifacts 下载所有构建产物
2. 上传构建产物到 GitLab Package Registry
3. 生成 `update_config.json` 配置文件
4. 将配置文件提交并推送到 GitLab 仓库的 `main` 分支

## 配置文件说明

### GitHub 更新配置

**文件路径:** `update_config_github.json`  
**访问 URL:** `https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json`

**下载链接格式:**
```
https://github.com/shichao402/HelloKnightRemoteCam/releases/download/v1.0.5/HelloKnightRCC_macos_1.0.5+1.zip
```

### GitLab 更新配置

**文件路径:** `update_config.json`  
**访问 URL:** `https://jihulab.com/shichao402/HelloKnightRemoteCam/-/raw/main/update_config.json`

**下载链接格式:**
```
https://jihulab.com/api/v4/projects/298216/packages/generic/helloknightrcc-client/1.0.5/HelloKnightRCC-1.0.5-macos.zip
```

## GitLab CI/CD 配置说明

### Runner 要求

GitLab CI/CD 需要以下 runner：

1. **Linux Runner** (必需)
   - 用于构建 Android 服务器
   - 使用 Docker 镜像：`cirrusci/flutter:3.24.0`

2. **macOS Runner** (可选)
   - 用于构建 macOS 客户端
   - 如果没有 macOS runner，可以设置 `allow_failure: true`

3. **Windows Runner** (可选)
   - 用于构建 Windows 客户端
   - 如果没有 Windows runner，可以设置 `allow_failure: true`

### 配置 Runner

如果没有 macOS 或 Windows runner，可以：

1. **设置 allow_failure: true**
   ```yaml
   build-client-macos:
     # ...
     allow_failure: true
   ```

2. **注释掉相应的 job**
   如果完全不需要构建某个平台，可以注释掉对应的 job

3. **配置专用 runner**
   参考 GitLab 文档配置 macOS 和 Windows runner

## 客户端配置

客户端和服务端应用需要配置更新检查 URL：

### 默认配置

- **GitLab:** `https://jihulab.com/api/v4/projects/298216/repository/files/update_config.json/raw?ref=main`
- **GitHub:** `https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json`

### 在应用中配置

用户可以在应用设置中修改更新检查 URL，选择使用 GitHub 或 GitLab 的更新源。

## 发布流程

### 1. 准备发布

1. 更新版本号（在 `client/pubspec.yaml` 和 `server/pubspec.yaml` 中）
2. 提交代码更改
3. 推送到 GitHub 和 GitLab

### 2. 创建发布标签

```bash
# 创建并推送标签
git tag v1.0.5
git push origin v1.0.5
git push gitlab v1.0.5
```

### 3. 等待 CI/CD 完成

- **GitHub:** 在 GitHub Actions 中查看构建和发布状态
- **GitLab:** 在 GitLab CI/CD Pipelines 中查看构建和发布状态

### 4. 验证发布

- **GitHub:** 检查 Release 页面和 `update_config_github.json` 文件
- **GitLab:** 检查 Package Registry 和 `update_config.json` 文件

## 故障排除

### GitHub Actions 失败

1. 检查 GitHub Actions 日志
2. 确认 secrets 配置正确
3. 检查构建产物是否成功生成

### GitLab CI/CD 失败

1. 检查 GitLab CI/CD 日志
2. 确认 runner 配置正确
3. 如果没有 macOS/Windows runner，设置 `allow_failure: true`

### 更新配置未生成

1. 检查是否推送了版本标签（格式：`v*`）
2. 检查 CI/CD 日志中的错误信息
3. 确认有写入仓库的权限

## 注意事项

1. **版本号一致性**: 确保标签版本号与 `pubspec.yaml` 中的版本号一致（或使用标签版本号）
2. **构建产物命名**: 构建产物的文件名必须与更新配置中的文件名匹配
3. **权限要求**: CI/CD 需要写入仓库的权限（GitHub: `contents: write`, GitLab: `write_repository`）
4. **Package Registry 权限**: GitLab CI/CD 需要访问 Package Registry 的权限（通过 `CI_JOB_TOKEN`）

