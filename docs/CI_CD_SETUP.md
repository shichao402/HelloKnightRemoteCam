# CI/CD 配置文档

本文档描述仓库当前的 GitHub Actions 流程。当前流程分为 **构建**、**正式发布**、**Gitee 同步** 三段，而不是一个标签完成全部事情。

## 一、工作流总览

### 1. 构建工作流：`build.yml`

触发方式：

- 推送 `build*` 标签
- 手动触发 `workflow_dispatch`

职责：

- 构建 macOS 客户端
- 构建 Windows 客户端
- 构建 Android 服务端
- 构建完成后回写 `VERSION.yaml` 中的 build number

### 2. 发布工作流：`release.yml`

触发方式：

- 手动 `workflow_dispatch`
- 通常由 `scripts/create_release.sh <x.y.z>` 触发

职责：

- 查找对应 `build<x.y.z>` 标签的成功构建
- 下载并整理 artifacts
- 生成 `file_hashes.json`
- 生成 `update_config_github.json`
- 创建正式 GitHub Release `v<x.y.z>`
- 更新固定的 `UpdateConfig` Release

### 3. Gitee 同步工作流：`sync-to-gitee.yml`

触发方式：

- GitHub Release 发布事件
- 手动触发
- 被其他 workflow 调用

职责：

- 下载 GitHub Release 资产
- 在 Gitee 创建 / 覆盖同版本 Release
- 生成并上传 `update_config_gitee.json` 到固定 `config` Release

## 二、推荐发布链路

```text
修改代码 / VERSION.yaml
    ↓
create_build_tags.sh
    ↓
push build<x.y.z>
    ↓
build.yml
    ↓
构建成功 + artifacts 可用
    ↓
create_release.sh <x.y.z>
    ↓
release.yml
    ↓
GitHub Release + UpdateConfig
    ↓
sync-to-gitee.yml（可选 / 自动）
```

## 三、构建阶段细节

### build tag 规则

构建标签格式：

```text
build<x.y.z>
```

例如：

```text
build1.0.8
```

### 构建输出

构建产物由三个复用工作流生成：

- `build-client-macos.yml`
- `build-client-windows.yml`
- `build-server-android.yml`

这些工作流会调用项目里的构建脚本，并从 `VERSION.yaml` 提取版本号。

### build number 回写

`build.yml` 结束时会递增并提交 `VERSION.yaml` 中的 build number。这是当前仓库的自动行为，发布文档应以此为前提理解版本变化。

## 四、正式发布阶段细节

### 真实版本来源

`release.yml` 会从 **build tag 对应提交里的 `VERSION.yaml`** 读取版本信息，而不是依赖 README 或手工拼接版本号。

### Release 资产

当前 GitHub Release 资产以 zip 包为主：

- macOS：zip 中包含 dmg
- Windows：zip 中包含 exe 安装程序
- Android：zip 中包含 apk

### 更新配置文件

GitHub 更新配置文件不再发布在仓库原始文件地址，而是发布在固定的 `UpdateConfig` Release：

- `update_config_github.json`
- URL 形态：`https://github.com/<owner>/<repo>/releases/download/UpdateConfig/update_config_github.json`

## 五、Gitee 同步阶段细节

Gitee 同步不是构建阶段的一部分，而是**基于已发布 GitHub Release 的后处理**：

- 读取 GitHub Release 资产
- 在 Gitee 创建对应 Release
- 更新固定 `config` Release 中的 `update_config_gitee.json`

## 六、不要再沿用的旧认知

以下说法已经不再准确：

- “推 `v*` 标签就会自动构建并发版”
- “GitHub 更新配置文件在 `raw.githubusercontent.com/.../main/update_config_github.json`”
- “版本主要从 `pubspec.yaml` 读取”

当前准确说法是：

- **构建入口**：`build*` 标签
- **发版入口**：`release.yml` / `create_release.sh`
- **版本来源**：`VERSION.yaml`
- **GitHub 更新配置位置**：`UpdateConfig` Release

## 七、相关文档

- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
- [`GITHUB_ACTIONS_SETUP.md`](GITHUB_ACTIONS_SETUP.md)
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
- [`GITEE_SYNC_SETUP.md`](GITEE_SYNC_SETUP.md)
