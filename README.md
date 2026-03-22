# HelloKnightRemoteCam

一个基于 Flutter 的局域网远程相机控制系统：

- `server/`：运行在 Android 手机上的相机服务端，负责相机控制、HTTP API、WebSocket 通知与 MJPEG 预览流。
- `client/`：运行在 macOS / Windows 上的桌面主控端，负责连接、预览、拍照/录像、文件管理与更新检查。
- `shared/`：Client 与 Server 共用的模型、版本解析、更新检查与文件处理能力。

> **文档整理说明**：根目录只保留项目入口文档；专题文档统一收敛到 `docs/`。如需查看完整文档导航，请先阅读 [`docs/README.md`](docs/README.md)。

## 核心能力

- **远程拍照与录像**：桌面端可远程控制手机拍照、开始/停止录像。
- **实时预览**：基于 MJPEG 流，支持方向锁定、手动旋转与窗口自适应缩放。
- **文件管理**：浏览照片/视频、删除、下载，下载支持断点续传与失败重试。
- **版本兼容校验**：连接时双向校验 Client / Server 最低兼容版本。
- **自动更新**：基于 GitHub Release / Gitee Release 分发，客户端通过更新配置文件检查新版本。
- **统一日志系统**：关键操作写入独立日志，方便调试和问题排查。

## 仓库结构

```text
HelloKnightRemoteCam/
├── client/                # 桌面主控端（macOS / Windows）
├── server/                # Android 手机端服务
├── shared/                # 共享 Dart 包
├── docs/                  # 专题文档与操作说明
├── scripts/               # 根目录脚本（版本、构建标签、发布、日志等）
├── VERSION.yaml           # 版本与更新地址的单一数据源
├── PROJECT_OVERVIEW.md    # 项目总览（面向开发者）
└── README.md              # 项目入口（当前文件）
```

## 快速开始

### 环境准备

- Flutter 3.x
- Android SDK（用于 `server/`）
- Xcode（macOS 构建）
- Visual Studio（Windows 构建）

### 安装依赖

```bash
cd client && flutter pub get
cd ../server && flutter pub get
cd ../shared && flutter pub get
```

### 本地部署

> **重要**：本项目要求优先使用现有脚本，不要直接手动执行零散的构建/部署流程。

- **服务端（Android）**

```bash
cd server
./scripts/deploy.sh --debug
```

- **客户端（macOS）**

```bash
cd client
./scripts/deploy.sh --debug --macos
```

- **客户端（Windows，Git Bash / WSL）**

```bash
cd client
bash scripts/deploy.sh --debug --windows
```

更完整的脚本说明见 [`docs/SCRIPTS.md`](docs/SCRIPTS.md)。

## 版本与发布

- **版本单一数据源**：根目录 `VERSION.yaml`
- **版本管理脚本**：`./scripts/version.sh`
- **构建触发方式**：`./scripts/create_build_tags.sh`
- **Release 创建方式**：`./scripts/create_release.sh <x.y.z>`

常用命令：

```bash
# 查看版本
./scripts/version.sh get

# 更新版本
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13
./scripts/version.sh sync

# 触发构建
./scripts/create_build_tags.sh

# 构建完成后创建 Release
./scripts/create_release.sh 1.0.8
```

完整流程见：

- [`docs/VERSION_MANAGEMENT.md`](docs/VERSION_MANAGEMENT.md)
- [`docs/CI_CD_SETUP.md`](docs/CI_CD_SETUP.md)
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)

## 调试与日志

统一日志收集脚本：

```bash
./scripts/collect_all_logs.sh
```

日志与调试约束：

- 不要在代码里使用 `print()` / `debugPrint()` 代替正式日志服务。
- 不要绕过项目脚本手动拼装部署流程。
- 不要手动维护版本号的多份副本；以 `VERSION.yaml` 为准。

## 文档导航

### 先看这些

- [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md)：项目结构、职责分层、常见开发入口
- [`docs/README.md`](docs/README.md)：完整文档索引与推荐阅读顺序

### 常用专题

- [`docs/SCRIPTS.md`](docs/SCRIPTS.md)：脚本说明
- [`docs/VERSION_MANAGEMENT.md`](docs/VERSION_MANAGEMENT.md)：版本管理
- [`docs/CI_CD_SETUP.md`](docs/CI_CD_SETUP.md)：CI/CD 与 Release 流程
- [`docs/AUTO_UPDATE.md`](docs/AUTO_UPDATE.md)：自动更新机制
- [`docs/AUTH_ARCHITECTURE.md`](docs/AUTH_ARCHITECTURE.md)：认证与版本兼容校验
- [`docs/UPDATE_MODULE_ARCHITECTURE.md`](docs/UPDATE_MODULE_ARCHITECTURE.md)：更新模块架构

## 当前文档约定

- 根目录文档负责**入口和总览**。
- `docs/` 负责**专题说明与操作细节**。
- 如文档与实现冲突，**以代码、脚本和 `VERSION.yaml` 为准**，并应优先回补文档。
