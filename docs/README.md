# 文档索引

`docs/` 目录用于存放 **专题文档、工程说明、发布与更新流程**。根目录仅保留入口文档；如果你已经进入 `docs/`，建议先看完本文档，再跳到具体专题。

## 阅读顺序

### 第一次接触项目

1. [`../README.md`](../README.md)
2. [`../PROJECT_OVERVIEW.md`](../PROJECT_OVERVIEW.md)
3. 本文档

### 准备开发或排查问题

1. [`SCRIPTS.md`](SCRIPTS.md)
2. [`VERSION_MANAGEMENT.md`](VERSION_MANAGEMENT.md)
3. [`AUTH_ARCHITECTURE.md`](AUTH_ARCHITECTURE.md)
4. 按需阅读预览 / 更新专题

### 准备发布

1. [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
2. [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
3. [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
4. [`GITEE_SYNC_SETUP.md`](GITEE_SYNC_SETUP.md)

## 文档分组

### 入口与导航

- [`../README.md`](../README.md)
  - 项目入口、快速开始、核心文档导航。
- [`../PROJECT_OVERVIEW.md`](../PROJECT_OVERVIEW.md)
  - 面向开发者的仓库总览、角色划分与关键流程。

### 开发与工程约束

- [`SCRIPTS.md`](SCRIPTS.md)
  - 根目录与子项目脚本的职责、常用命令与使用方式。
- [`VERSION_MANAGEMENT.md`](VERSION_MANAGEMENT.md)
  - `VERSION.yaml` 的管理规则、版本同步与常见命令。
- [`VERSION_COPY_STRATEGY.md`](VERSION_COPY_STRATEGY.md)
  - 版本文件在构建产物中的落位策略，以及运行时的版本读取优先级。

### 发布与更新

- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
  - 实际发布步骤清单。
- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
  - GitHub Actions 工作流分工、构建与 Release 链路。
- [`GITHUB_ACTIONS_SETUP.md`](GITHUB_ACTIONS_SETUP.md)
  - 各工作流文件的职责与触发方式速查。
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
  - 自动更新配置文件、下载地址与客户端消费方式。
- [`GITEE_SYNC_SETUP.md`](GITEE_SYNC_SETUP.md)
  - GitHub Release 同步到 Gitee 的 secrets、触发与验证方式。

### 架构设计

- [`AUTH_ARCHITECTURE.md`](AUTH_ARCHITECTURE.md)
  - 认证与版本兼容校验架构。
- [`UPDATE_MODULE_ARCHITECTURE.md`](UPDATE_MODULE_ARCHITECTURE.md)
  - 更新模块的当前架构与共享能力拆分。

### 预览与 UI 专题

- [`PREVIEW_ROTATION.md`](PREVIEW_ROTATION.md)
  - 预览方向锁定、旋转与转置逻辑。
- [`PREVIEW_SIZE_OPTIMIZATION.md`](PREVIEW_SIZE_OPTIMIZATION.md)
  - 预览尺寸的数据流优化。
- [`FILE_STATE_UPDATE.md`](FILE_STATE_UPDATE.md)
  - 文件列表局部状态更新最佳实践。

## 当前整理原则

### 目录职责

- **根目录**：仅保留入口级文档。
- **`docs/`**：存放专题与操作细节。
- **脚本与工作流**：是工程事实来源之一，文档需要和它们保持一致。

### 判断优先级

当文档与实现不一致时，优先相信：

1. `VERSION.yaml`
2. `scripts/`
3. `.github/workflows/`
4. 代码实现
5. 文档

## 已对齐的重点约束

本轮整理后，以下信息应以当前文档为准：

- 构建触发使用 `build*` 标签，而不是直接推 `v*` 标签。
- GitHub `update_config_github.json` 发布在固定的 `UpdateConfig` Release。
- Gitee `update_config_gitee.json` 发布在固定的 `config` Release。
- `shared/` 包已经存在，更新模块共享不再是“待创建”的设计设想。

## 维护建议

- 新增专题文档时，请优先把链接补进本文档。
- 根目录如再出现新的操作型文档，优先考虑收敛到 `docs/`。
- 若工程流程调整，优先更新：`README.md`、本文档、`RELEASE_CHECKLIST.md`、`CI_CD_SETUP.md`。
