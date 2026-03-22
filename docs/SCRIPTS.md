# 脚本说明

本文档说明仓库内现有脚本的职责边界与常见用法。**脚本是工程事实来源之一**；遇到流程问题时，请优先检查脚本实际实现。

## 一、脚本分层

### 1. 根目录 `scripts/`

负责跨子项目的公共能力：

- 版本管理
- 构建标签创建
- Release 创建
- 更新配置生成
- 日志收集
- Gitee 相关同步辅助

当前常用脚本：

- `scripts/version.sh`
- `scripts/create_build_tags.sh`
- `scripts/create_release.sh`
- `scripts/collect_all_logs.sh`
- `scripts/generate_update_config.py`

### 2. `client/scripts/`

负责桌面客户端的构建、部署、启动与清理：

- `build.sh`
- `deploy.sh`
- `deploy_mac.sh`
- `deploy_windows.bat`
- `start.sh`
- `kill_process.sh`

### 3. `server/scripts/`

负责 Android 服务端的构建、安装、启动与日志收集：

- `build.sh`
- `deploy.sh`
- `deploy_android.sh`
- `install.sh`
- `start.sh`
- `kill_process.sh`
- `collect_adb_logs.sh`

## 二、最常用脚本

### `scripts/version.sh`

统一管理 `VERSION.yaml`：

```bash
./scripts/version.sh get
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13
./scripts/version.sh bump client patch
./scripts/version.sh sync
```

### `scripts/create_build_tags.sh`

从 `VERSION.yaml` 读取版本号，创建并推送 `build<x.y.z>` 标签，触发 `build.yml`：

```bash
./scripts/create_build_tags.sh
./scripts/create_build_tags.sh --remote
./scripts/create_build_tags.sh --no-push
```

说明：

- 标签格式示例：`build1.0.8`
- 推送后会触发 GitHub Actions 构建三个平台
- 如果标签已存在，脚本当前会提示是否覆盖

### `scripts/create_release.sh`

检查构建标签、构建状态与 artifacts，然后触发 `release.yml`：

```bash
./scripts/create_release.sh 1.0.8
```

说明：

- 传入参数是主版本号 `x.y.z`
- 依赖 `gh auth login` 或环境变量 `GITHUB_TOKEN` / `GH_TOKEN`
- 如果对应 Release 已存在，脚本当前会提示是否覆盖

### `scripts/collect_all_logs.sh`

收集客户端与服务端日志：

```bash
./scripts/collect_all_logs.sh
```

## 三、客户端脚本

### 构建

```bash
cd client
./scripts/build.sh --debug --macos
./scripts/build.sh --release --macos
bash ./scripts/build.sh --debug --windows
bash ./scripts/build.sh --release --windows
```

### 部署

```bash
cd client
./scripts/deploy.sh --debug --macos
./scripts/deploy.sh --release --macos
bash ./scripts/deploy.sh --debug --windows
bash ./scripts/deploy.sh --release --windows
```

### 兼容入口

```bash
cd client
./scripts/deploy_mac.sh
scripts\deploy_windows.bat
```

## 四、服务端脚本

### 构建

```bash
cd server
./scripts/build.sh --debug
./scripts/build.sh --release
```

### 部署

```bash
cd server
./scripts/deploy.sh --debug
./scripts/deploy.sh --release
```

### 兼容入口

```bash
cd server
./scripts/deploy_android.sh
```

## 五、构建与发布关系

当前推荐链路：

1. `./scripts/version.sh ...`
2. `./scripts/create_build_tags.sh`
3. 等待 `.github/workflows/build.yml`
4. `./scripts/create_release.sh <x.y.z>`

也就是说：

- **构建入口**在 `create_build_tags.sh`
- **正式发版入口**在 `create_release.sh`
- **版本事实来源**在 `VERSION.yaml`

## 六、与 GitHub Actions 的关系

GitHub Actions 复用仓库内脚本，而不是另起一套逻辑：

- 各平台构建工作流会调用对应的 `build.sh`
- `release.yml` 会调用 `scripts/generate_update_config.py`
- 版本信息通过 `scripts/lib/version_manager.py` 从 `VERSION.yaml` 读取

## 七、当前注意事项

- `create_build_tags.sh` / `create_release.sh` 在少数场景下仍有交互提示；使用前请确认本地标签和远端 Release 状态。
- `VERSION.yaml` 是单一数据源，不应手工维护多套版本号。
- 需要发布时，请同时参考 [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) 与 [`CI_CD_SETUP.md`](CI_CD_SETUP.md)。
