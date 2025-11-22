# 更新模块架构设计文档

## 概述

本文档描述了更新模块的架构设计，包括代码组织、模块化方案以及客户端和服务端的代码共享策略。

## 当前架构

### 客户端（Client）更新模块结构

```
client/lib/services/
├── update_service.dart              # 更新服务主类（协调各个子服务）
├── file_download_service.dart        # 文件下载服务（支持断点续传）
├── download_directory_service.dart   # 下载目录管理服务
├── file_verification_service.dart    # 文件验证服务（hash校验）
├── archive_service.dart              # 归档服务（zip解压）
├── update_file_cleanup_service.dart  # 更新文件清理服务
└── version_service.dart              # 版本服务

client/lib/utils/
└── version_utils.dart                # 版本号工具类（版本比较、解析）
```

### 服务端（Server）更新模块结构

```
server/lib/services/
├── update_service.dart              # 更新服务主类
├── file_download_service.dart        # 文件下载服务
└── version_service.dart              # 版本服务
```

## 代码重复问题

### 当前重复的代码

1. **版本比较逻辑** (`_compareVersions`)
   - Client: `client/lib/services/update_service.dart`
   - Server: `server/lib/services/update_service.dart`

2. **UpdateInfo 和 UpdateCheckResult 模型**
   - Client: `client/lib/services/update_service.dart`
   - Server: `server/lib/services/update_service.dart`

3. **Zip解压逻辑** (`_extractZipFile`)
   - Client: `client/lib/services/archive_service.dart`
   - Server: `server/lib/services/update_service.dart`

4. **文件hash验证逻辑**
   - Client: `client/lib/services/file_verification_service.dart`
   - Server: 可能也需要（当前未实现）

## 共享代码方案

### 方案1：创建共享包（推荐）

创建一个独立的Flutter包来存放共享代码：

```
shared/
├── pubspec.yaml
└── lib/
    ├── models/
    │   ├── update_info.dart          # UpdateInfo模型
    │   └── update_check_result.dart # UpdateCheckResult模型
    ├── utils/
    │   └── version_utils.dart        # 版本工具类
    ├── services/
    │   ├── archive_service.dart      # 归档服务（zip解压）
    │   └── file_verification_service.dart # 文件验证服务
    └── update_common.dart            # 导出所有公共API
```

**优点：**
- 代码完全共享，避免重复
- 易于维护和测试
- 符合DRY原则

**缺点：**
- 需要额外的包管理
- 需要修改pubspec.yaml添加path依赖

**实现步骤：**
1. 创建 `shared/` 目录
2. 创建 `shared/pubspec.yaml`
3. 提取共享代码到shared包
4. 在client和server的pubspec.yaml中添加path依赖：
   ```yaml
   dependencies:
     shared:
       path: ../shared
   ```

### 方案2：使用符号链接（不推荐）

创建符号链接指向共享代码。

**缺点：**
- 跨平台兼容性问题
- Git管理复杂
- 不推荐使用

### 方案3：保持现状（当前方案）

客户端和服务端各自维护代码。

**优点：**
- 简单直接
- 各自可以独立演进

**缺点：**
- 代码重复
- 维护成本高
- 容易出现不一致

## 推荐方案

**建议采用方案1：创建共享包**

### 理由

1. **代码重复度高**：版本比较、模型定义、zip解压等逻辑完全相同
2. **维护成本**：修复bug或添加功能需要在两处修改
3. **一致性保证**：共享代码确保客户端和服务端行为一致
4. **测试便利**：共享代码可以统一测试

### 实施计划

1. **第一阶段**：提取模型和工具类
   - `UpdateInfo` 和 `UpdateCheckResult` 模型
   - `VersionUtils` 工具类

2. **第二阶段**：提取服务类
   - `ArchiveService`（zip解压）
   - `FileVerificationService`（hash验证）

3. **第三阶段**：重构客户端和服务端
   - 更新import语句
   - 使用共享代码

## 当前模块化状态

### ✅ 已完成的模块化

1. **DownloadDirectoryService**：统一管理下载目录
2. **FileVerificationService**：统一处理文件验证
3. **ArchiveService**：统一处理zip解压
4. **UpdateFileCleanupService**：统一处理文件清理
5. **VersionUtils**：版本工具类

### 📋 待完成的工作

1. 创建共享包结构
2. 提取共享代码到shared包
3. 更新client和server的依赖
4. 重构server端使用共享代码

## 代码组织原则

### 单一职责原则
每个服务类只负责一个明确的功能：
- `DownloadDirectoryService`：只负责目录管理
- `FileVerificationService`：只负责文件验证
- `ArchiveService`：只负责归档操作

### 依赖注入
服务之间通过依赖注入组合，而不是直接耦合：
```dart
class UpdateService {
  final DownloadDirectoryService _downloadDirService;
  final FileVerificationService _fileVerificationService;
  // ...
}
```

### 接口抽象
关键服务提供清晰的接口，便于测试和替换。

## 总结

当前客户端代码已经实现了良好的模块化，各个服务职责清晰。下一步应该创建共享包来避免客户端和服务端的代码重复，提高代码质量和维护效率。

