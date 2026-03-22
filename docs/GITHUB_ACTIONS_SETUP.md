# GitHub Actions 工作流速查

本文档是 `.github/workflows/` 下主要工作流的简明说明，适合快速确认“哪个文件负责什么”。

## 工作流清单

### `build.yml`

- **作用**：总构建入口
- **触发**：推送 `build*` 标签、手动触发
- **调用**：
  - `build-client-macos.yml`
  - `build-client-windows.yml`
  - `build-server-android.yml`
- **附加行为**：构建成功后递增并提交 `VERSION.yaml` 中的 build number

### `build-client-macos.yml`

- **作用**：构建 macOS 客户端
- **版本来源**：`VERSION.yaml`
- **产物**：macOS 客户端构建结果

### `build-client-windows.yml`

- **作用**：构建 Windows 客户端
- **版本来源**：`VERSION.yaml`
- **产物**：Windows 客户端构建结果

### `build-server-android.yml`

- **作用**：构建 Android 服务端
- **版本来源**：`VERSION.yaml`
- **产物**：Android APK / zip 构建结果

### `release.yml`

- **作用**：创建正式 GitHub Release
- **触发**：手动 `workflow_dispatch`
- **常见入口**：`./scripts/create_release.sh <x.y.z>`
- **关键动作**：
  - 查找 `build<x.y.z>` 对应的成功构建
  - 下载 artifacts
  - 生成 `file_hashes.json`
  - 生成 `update_config_github.json`
  - 创建正式 Release `v<x.y.z>`
  - 更新固定 `UpdateConfig` Release

### `sync-to-gitee.yml`

- **作用**：将 GitHub Release 同步到 Gitee
- **触发**：
  - GitHub Release `published`
  - 手动触发
  - `workflow_call`
- **关键动作**：
  - 下载 GitHub Release 资产
  - 在 Gitee 创建同版本 Release
  - 生成并上传 `update_config_gitee.json`

## 触发规则速记

### 构建

```text
push build* tag -> build.yml
```

### 正式发版

```text
manual release.yml
或
scripts/create_release.sh <x.y.z>
```

### Gitee 同步

```text
GitHub release published -> sync-to-gitee.yml
```

## 当前关键事实

- GitHub 构建不是由 `v*` 标签直接触发。
- GitHub 更新配置文件位于 `UpdateConfig` Release。
- 版本信息以 `VERSION.yaml` 为准。
- `release.yml` 会从 build tag 对应提交里的 `VERSION.yaml` 提取真实版本号。

## 建议搭配阅读

- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
