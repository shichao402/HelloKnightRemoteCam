# 更新模块架构设计文档

本文档描述**当前已经落地**的更新模块结构，而不是早期“准备创建共享包”的设计草案。

## 一、当前结论

- `shared/` 包已经存在。
- 更新相关的模型、版本工具和部分服务已经迁移到共享层。
- `client/` 和 `server/` 各自仍保留平台相关的协调逻辑与 UI / 运行时行为。

## 二、分层结构

### 1. `shared/`：共享核心能力

当前已存在的共享能力包括：

- 更新检查模型：`update_info.dart`、`update_check_result.dart`
- 更新检查与 URL 配置服务：`update_check_service.dart`、`update_url_config_service.dart`
- 更新下载处理：`update_download_processor.dart`
- 归档处理：`archive_service.dart`
- 文件校验：`file_verification_service.dart`
- 版本解析与比较：`version_parser_service.dart`、`version_utils.dart`

### 2. `client/`：桌面端专属能力

客户端保留：

- 更新流程协调：`update_service.dart`
- 更新文件清理：`update_file_cleanup_service.dart`
- 更新设置：`update_settings_service.dart`
- 更新对话框 UI：`update_dialog.dart`

这些内容与桌面端下载目录、安装体验、交互反馈强相关，不适合全部下沉到共享层。

### 3. `server/`：服务端专属能力

服务端保留：

- 服务端更新协调逻辑：`update_service.dart`
- 更新设置：`update_settings_service.dart`

这些逻辑与 Android 端运行环境、安装与应用生命周期绑定更紧。

## 三、为什么不是“全部共享”

更新模块天然包含两类职责：

### 适合共享的部分

- 版本解析与比较
- 更新配置 JSON 解析
- 文件哈希校验
- 归档 / 解压逻辑
- 通用下载处理流程

### 不适合强行共享的部分

- 平台特定安装与启动逻辑
- UI 交互（如更新弹窗）
- 平台目录管理与权限处理
- 应用生命周期集成

因此，当前架构采用的是：

```text
共享底层能力 + 端内协调层
```

而不是“单个巨大 UpdateService 供两端共用”。

## 四、当前收益

采用 `shared/` 后，已经获得的收益包括：

- Client / Server 在更新配置解析上保持一致
- 版本比较逻辑不再双份维护
- 文件校验与归档处理可复用
- 后续修复更新协议问题时，只需在共享层改一处

## 五、仍可继续优化的方向

虽然共享包已经建立，但仍有进一步收敛空间：

- 抽离更多更新流程编排中的公共步骤
- 减少 Client / Server `update_service.dart` 中重复的错误处理分支
- 统一更新结果状态模型和日志打点规范
- 让共享层暴露更清晰的 façade，而不是零散服务组合

## 六、阅读建议

如果你要修改更新相关代码，建议按这个顺序看：

1. `shared/lib/models/` 与 `shared/lib/services/`
2. `client/lib/services/update_service.dart`
3. `server/lib/services/update_service.dart`
4. 发布侧脚本与工作流：
   - `scripts/generate_update_config.py`
   - `.github/workflows/release.yml`
   - `.github/workflows/sync-to-gitee.yml`

## 七、相关文档

- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
- [`VERSION_MANAGEMENT.md`](VERSION_MANAGEMENT.md)
- [`VERSION_COPY_STRATEGY.md`](VERSION_COPY_STRATEGY.md)
