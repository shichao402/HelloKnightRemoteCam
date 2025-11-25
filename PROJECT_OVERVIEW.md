## HelloKnightRemoteCam 项目总览（精简版）

一个基于 **Flutter** 的局域网远程相机控制系统：手机端作为相机服务器，桌面客户端（macOS / Windows）负责连接、预览、拍照/录像与文件管理，并且配有统一版本管理、自动更新和独立日志系统。

---

## 1. 整体架构与目录

### 1.1 角色划分

- **Server（Android 手机端）**
  - 使用 Flutter 构建的 Android 应用。
  - 负责相机控制、HTTP API、WebSocket 实时通知、MJPEG 预览流输出。
- **Client（macOS / Windows 客户端）**
  - 使用 Flutter 构建的桌面应用。
  - 负责设备连接、相机控制 UI、文件管理与下载、更新检查。
- **Shared**
  - 共享模型与部分服务逻辑，保证 Client 与 Server 行为一致。
- **根目录脚本与配置**
  - `VERSION.yaml`：统一版本配置（客户端/服务端版本号、兼容性要求、更新配置地址）。
  - `scripts/`：版本管理、发布、日志收集等项目级脚本。

### 1.2 主要目录结构

```text
HelloKnightRemoteCam/
├── client/                 # 主控端（macOS / Windows）
│   ├── lib/                # Flutter 客户端代码（UI / services / models 等）
│   └── scripts/            # 客户端构建 & 部署脚本
├── server/                 # 手机端（Android Server）
│   ├── lib/                # Flutter 服务端代码
│   └── scripts/            # 服务端构建 & 部署脚本
├── shared/                 # Client & Server 共享 Dart 包（模型 / 服务 / 工具）
├── docs/                   # 专题设计文档（认证、预览、版本、CI/CD 等）
├── scripts/                # 项目级脚本（版本、发布、日志收集）
└── VERSION.yaml            # 统一版本配置（单一数据源）
```

---

## 2. 关键能力概览

- **远程控制**
  - 拍照、开始/停止录像。
  - 录像期间锁定设置，避免误操作。
- **实时预览**
  - 基于 `mjpeg_stream` 的 MJPEG 预览流。
  - 支持方向锁定、手动旋转（0/90/180/270）、窗口自适应缩放（contain 逻辑，不裁剪）。
  - 预览尺寸从 Server 通过 WebSocket / HTTP 状态统一下发，Client 统一更新。
- **文件管理与下载**
  - 浏览照片/视频，支持星标。
  - 下载支持 HTTP Range 断点续传，最多 2 个并发任务。
  - 下载进度持久化到 SQLite，应用重启后可恢复。
- **版本管理与兼容性**
  - 根目录 `VERSION.yaml` 作为唯一版本数据源（client/server 独立版本号 + 最小兼容版本）。
  - 构建脚本自动同步版本号到各自 `pubspec.yaml` 与 assets 中的 `VERSION.yaml`。
  - 连接时双向版本检查：Server 校验 Client，Client 校验 Server。
- **自动更新**
  - 基于 GitHub Releases / Gitee Releases。
  - CI/CD 自动生成 `update_config_github.json` / `update_config_gitee.json`。
  - Client 从配置 URL 读取可用版本与下载地址，提示用户更新。
- **统一日志体系**
  - Server：`LoggerService`，日志写入 `/data/data/.../logs/debug_*.log`。
  - Client：`ClientLoggerService`，日志写入用户目录下的 `client_debug_*.log`。
  - 根目录脚本 `scripts/collect_all_logs.sh` 一次性收集手机端与客户端日志。

---

## 3. 开发与部署规范（必须遵守）

> **强制：所有构建 / 部署 / 调试都必须通过脚本完成，禁止直接执行 `flutter`、`adb`、手动访问日志文件或使用 `tail`。**

### 3.1 环境准备

1. 安装 Flutter 3.x。
2. 配置 Android SDK（用于构建 Android 服务端）。
3. 在 macOS 安装 Xcode（macOS 客户端）。
4. 在 Windows 安装 Visual Studio（Windows 客户端）。

### 3.2 安装依赖

```bash
# 客户端依赖
cd client
flutter pub get

# 服务端依赖
cd ../server
flutter pub get
```

### 3.3 构建与部署（必须用脚本）

**手机端（Server / Android）：**

```bash
cd server

# 推荐：统一部署脚本（会自动同步版本号）
./scripts/deploy.sh --debug

# 向后兼容脚本
./scripts/deploy_android.sh
```

**桌面客户端（Client）：**

```bash
cd client

# macOS
./scripts/deploy.sh --debug --macos
# 或
./scripts/deploy_mac.sh

# Windows（Git Bash / WSL）
bash scripts/deploy.sh --debug --windows
# 或
scripts\deploy_windows.bat
```

更多参数与组合方式请参考 `docs/SCRIPTS.md`。

---

## 4. 使用流程（从零到跑通）

### 4.1 启动手机端

1. 在 Android 手机上安装并启动 Server 应用。
2. 授予相机、麦克风、存储权限。
3. 点击“启动服务器”，记下应用界面显示的 IP 与端口（默认 `8080`）。
4. 如需排错，在设置中开启“调试模式”（会写更详细的日志）。

### 4.2 启动客户端并连接

1. 启动桌面客户端应用。
2. 在连接界面输入：
   - 服务器 IP（如 `192.168.1.100`）
   - 端口（默认 `8080`）
3. 点击“连接”。
4. 如果版本不兼容，客户端会根据 `VERSION.yaml` 的兼容配置给出错误提示。

### 4.3 基本操作

- **相机控制**
  - 拍照：点击“拍照”按钮。
  - 录像：点击“开始录像”开始，再次点击停止。
  - 录像时禁止修改录像相关设置，保证稳定性。
- **实时预览**
  - 会自动拉取 MJPEG 预览流。
  - 可以锁定方向或手动旋转画面。
  - 预览窗口大小可调，画面自动等比缩放（不裁剪）。
- **文件管理与下载**
  - 切换到文件管理页面浏览照片/视频。
  - 支持星标、删除。
  - 下载会进入下载队列，支持暂停/继续，失败自动重试。

---

## 5. 版本管理与自动更新（关键流程）

### 5.1 版本号与兼容性

- 唯一版本数据源：根目录 `VERSION.yaml`。
  - `client.version` / `server.version`
  - `compatibility.min_client_version` / `compatibility.min_server_version`
- 管理脚本：`scripts/version.sh`

常用命令：

```bash
# 查看当前版本
./scripts/version.sh get

# 设置版本
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13

# 递增版本（语义化）
./scripts/version.sh bump client minor
./scripts/version.sh bump server patch

# 同步版本号到各自 pubspec.yaml
./scripts/version.sh sync
```

详细规则与代码集成方式参见：`docs/VERSION_MANAGEMENT.md` 与 `docs/VERSION_COPY_STRATEGY.md`。

### 5.2 CI/CD 与自动更新

- 基于 **GitHub Actions** 进行构建与发布：
  - 构建 macOS / Windows 客户端与 Android 服务端。
  - 创建 GitHub Release，仅上传 zip 包（内部包含 dmg / exe / apk）。
  - 生成 `update_config_github.json` 并推送到仓库。
- 可选：通过工作流同步 Release 至 Gitee，并生成 `update_config_gitee.json`。
- 客户端默认从 GitHub 的配置 URL 检查更新，用户可在设置中切换为 Gitee。

相关详细文档：

- `docs/CI_CD_SETUP.md`
- `docs/GITHUB_ACTIONS_SETUP.md`
- `docs/AUTO_UPDATE.md`
- `docs/GITEE_SYNC_SETUP.md`

---

## 6. 日志与调试流程（必看）

### 6.1 日志位置

- **手机端（Server）**：`/data/data/com.firoyang.helloknightrcc_server/files/logs/debug_*.log`
- **客户端（Client，macOS）**：`~/Library/Application Support/com.example.helloKnightRCC/logs/client_debug_*.log`
- （其他平台路径以具体实现为准）

### 6.2 收集所有日志（强制使用脚本）

```bash
./scripts/collect_all_logs.sh
```

脚本会自动：

- 检测 Android 设备。
- 收集手机端与客户端日志文件。
- 汇总到统一目录，便于分析。

> **禁止：**
> - 手动执行 `adb`。
> - 手动访问日志目录。
> - 使用 `tail` 跟日志（可能漏关键信息）。

### 6.3 日志使用规范（代码层）

- 禁止使用 `print()` / `debugPrint()`。
- 客户端必须使用 `ClientLoggerService`。
- 服务端必须使用 `LoggerService`。
- 所有日志需要带有有意义的 tag（如：`PREVIEW`、`DOWNLOAD`、`AUTH` 等）。

更多细节可参考根目录规则说明与现有服务实现。

---

## 7. 进阶设计文档导航

当需要深入了解具体子系统实现细节时，可查阅 `docs/` 下的专题文档：

- **认证与版本兼容**
  - `docs/AUTH_ARCHITECTURE.md`
  - `docs/VERSION_MANAGEMENT.md`
  - `docs/VERSION_COPY_STRATEGY.md`
- **预览与 UI 优化**
  - `docs/PREVIEW_ROTATION.md`              （预览旋转与转置）
  - `docs/PREVIEW_SIZE_OPTIMIZATION.md`     （预览尺寸数据流优化）
  - `docs/FILE_STATE_UPDATE.md`            （文件状态更新最佳实践）
- **更新模块与自动发布**
  - `docs/UPDATE_MODULE_ARCHITECTURE.md`
  - `docs/AUTO_UPDATE.md`
  - `docs/CI_CD_SETUP.md`
  - `docs/GITHUB_ACTIONS_SETUP.md`
  - `docs/GITEE_SYNC_SETUP.md`
- **其他辅助说明**
  - `docs/SCRIPTS.md`                  （脚本说明）
  - `docs/CURSOR_GIT_SYNC.md`         （仅与开发工具 Cursor 的 git 行为相关，可按需参考）

---

## 8. 建议阅读顺序

1. 本文档：`PROJECT_OVERVIEW.md`（整体认知与关键流程）。
2. 根目录 `README.md`（更详细的功能与 API 说明）。
3. 视需求选择性阅读 `docs/` 下的专题设计文档。

本总览文档的目标是：**让新同学在 10 分钟内搞清楚项目做什么、怎么跑起来、关键脚本和日志/版本/更新的核心流程。**


