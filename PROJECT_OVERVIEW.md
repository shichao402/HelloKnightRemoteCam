# HelloKnightRemoteCam 项目总览

本文档面向开发者，帮助你在较短时间内理解项目的**角色划分、代码布局、关键流程和常用文档入口**。

如果你第一次接触本仓库，建议按下面顺序阅读：

1. `README.md`
2. `PROJECT_OVERVIEW.md`（当前文档）
3. `docs/README.md`

## 1. 系统角色

### `server/`：Android 手机端

- 负责相机控制
- 暴露 HTTP API
- 推送 WebSocket 实时通知
- 输出 MJPEG 预览流
- 提供文件列表、下载、删除等能力

### `client/`：桌面主控端

- 运行于 macOS / Windows
- 负责连接手机端、展示预览、触发拍照/录像
- 提供文件管理、下载与更新检查 UI

### `shared/`：共享能力层

当前已经落地为独立包，主要承载：

- 更新检查相关模型与服务
- 版本解析与版本比较工具
- 归档、文件校验等共用能力

这意味着“更新模块共享”已经不是设计设想，而是**当前现实结构的一部分**。

## 2. 仓库布局

```text
HelloKnightRemoteCam/
├── client/
│   ├── lib/               # 客户端 Flutter 代码
│   └── scripts/           # 客户端构建 / 部署脚本
├── server/
│   ├── lib/               # 服务端 Flutter 代码
│   └── scripts/           # 服务端构建 / 部署脚本
├── shared/
│   └── lib/               # 共享模型、服务、工具
├── docs/                  # 专题文档
├── scripts/               # 根目录脚本
├── VERSION.yaml           # 版本与更新配置的单一数据源
├── README.md              # 项目入口
└── PROJECT_OVERVIEW.md    # 开发者总览
```

## 3. 核心运行链路

### 3.1 连接与控制

1. 用户在 Android 端启动服务。
2. 桌面端输入 IP / 端口并发起连接。
3. 双方进行版本兼容检查。
4. 连接成功后，桌面端可进行：
   - 拍照
   - 开始 / 停止录像
   - 获取相机状态
   - 浏览与下载文件
   - 拉取 MJPEG 预览流

### 3.2 预览

- 预览流使用 MJPEG。
- 预览方向支持锁定与手动旋转。
- 预览区域按窗口大小自适应，优先保证不裁剪画面。

相关专题：

- [`docs/PREVIEW_ROTATION.md`](docs/PREVIEW_ROTATION.md)
- [`docs/PREVIEW_SIZE_OPTIMIZATION.md`](docs/PREVIEW_SIZE_OPTIMIZATION.md)

### 3.3 文件下载

- 支持 HTTP Range 断点续传。
- 下载任务支持失败重试。
- 下载状态在客户端持久化。

相关专题：

- [`docs/FILE_STATE_UPDATE.md`](docs/FILE_STATE_UPDATE.md)

## 4. 版本、构建与发布

### 4.1 版本来源

项目采用**单一数据源**原则：

- 版本号与更新地址统一存放在根目录 `VERSION.yaml`
- `client/pubspec.yaml` 与 `server/pubspec.yaml` 由脚本同步
- 自动更新地址也以 `VERSION.yaml` / 发布流程生成结果为准

### 4.2 构建触发方式

当前流程不是直接推 `v*` 标签构建，而是：

1. 用 `./scripts/create_build_tags.sh` 创建并推送 `build<x.y.z>` 标签
2. GitHub Actions 的 `build.yml` 被触发，构建三个平台
3. 构建成功后，流水线会自动回写 `VERSION.yaml` 中的 build number
4. 再用 `./scripts/create_release.sh <x.y.z>` 触发 `release.yml` 创建正式 GitHub Release

### 4.3 自动更新

- GitHub 更新配置文件：固定发布到 `UpdateConfig` Release
- Gitee 更新配置文件：固定发布到 `config` Release
- 客户端通过更新配置 URL 拉取版本、文件名、下载地址与哈希

相关文档：

- [`docs/VERSION_MANAGEMENT.md`](docs/VERSION_MANAGEMENT.md)
- [`docs/CI_CD_SETUP.md`](docs/CI_CD_SETUP.md)
- [`docs/AUTO_UPDATE.md`](docs/AUTO_UPDATE.md)
- [`docs/GITEE_SYNC_SETUP.md`](docs/GITEE_SYNC_SETUP.md)

## 5. 开发与调试约束

### 必须遵守

- 使用脚本完成部署与发布，不要手动拼流程。
- 版本信息以 `VERSION.yaml` 为准，不要手改多个地方。
- 出现问题先收集日志，再分析原因。

### 常用命令

```bash
# 查看版本
./scripts/version.sh get

# 触发构建
./scripts/create_build_tags.sh

# 创建 Release
./scripts/create_release.sh 1.0.8

# 收集日志
./scripts/collect_all_logs.sh
```

## 6. 项目推进与规划

`docs/plans/requirements-board.md` 是全项目唯一推进入口。当请求是泛化的（如"继续推进"、"找下一个点"、"按项目往前做"），先读该文件，选第一个非观察态的高优先级条目开工。

专题级别的 checklist 只在对应专题内有效，不作为全项目优先级来源。

## 7. 推荐阅读地图

### 规划与推进

- [`docs/plans/requirements-board.md`](docs/plans/requirements-board.md)：项目推进板（唯一推进入口）
- [`docs/plans/ARCHITECTURE_REDESIGN.md`](docs/plans/ARCHITECTURE_REDESIGN.md)：架构改造方案

### 入门入口

- `README.md`
- [`docs/README.md`](docs/README.md)

### 架构与机制

- [`docs/AUTH_ARCHITECTURE.md`](docs/AUTH_ARCHITECTURE.md)
- [`docs/UPDATE_MODULE_ARCHITECTURE.md`](docs/UPDATE_MODULE_ARCHITECTURE.md)
- [`docs/VERSION_COPY_STRATEGY.md`](docs/VERSION_COPY_STRATEGY.md)

### 工程与发布

- [`docs/SCRIPTS.md`](docs/SCRIPTS.md)
- [`docs/VERSION_MANAGEMENT.md`](docs/VERSION_MANAGEMENT.md)
- [`docs/CI_CD_SETUP.md`](docs/CI_CD_SETUP.md)
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)

### 预览与 UI 专题

- [`docs/PREVIEW_ROTATION.md`](docs/PREVIEW_ROTATION.md)
- [`docs/PREVIEW_SIZE_OPTIMIZATION.md`](docs/PREVIEW_SIZE_OPTIMIZATION.md)
- [`docs/FILE_STATE_UPDATE.md`](docs/FILE_STATE_UPDATE.md)

## 8. 这份文档的定位

- `README.md`：对外入口，强调项目是什么、怎么开始。
- `PROJECT_OVERVIEW.md`：对内总览，强调仓库如何组织、关键流程如何串起来。
- `docs/README.md`：专题文档索引，告诉你“该去哪里看细节”。
