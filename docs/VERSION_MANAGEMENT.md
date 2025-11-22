# 版本管理指南

## 版本号格式

项目使用语义化版本号格式：`主版本号.次版本号.修订号+构建号`

例如：`1.0.0+1`
- `1.0.0` - 版本号（主版本.次版本.修订号）
- `+1` - 构建号

## 版本号管理方式（不依赖外部平台）

**重要：** 项目版本号完全由项目自身管理，不依赖 Git、CI/CD 平台或其他外部工具。

### 版本号存储位置

版本号统一存储在项目根目录的 `VERSION.yaml` 文件中（YAML格式），作为单一数据源。

**客户端和服务器使用独立的版本号：**

```
HelloKnightRemoteCam/
  VERSION.yaml     # 版本号配置文件（YAML格式，包含客户端和服务器独立版本号）
  client/
    pubspec.yaml   # 客户端版本号（自动同步）
  server/
    pubspec.yaml   # 服务器版本号（自动同步）
    assets/
      VERSION.yaml # 服务器assets中的版本文件（用于运行时读取）
```

### VERSION.yaml 文件格式

使用 YAML 格式，更易读易写：

```yaml
# 版本号配置文件
# 客户端和服务器使用独立的版本号
# 格式: YAML

client:
  version: "1.0.7+6"  # 客户端版本号（格式: x.y.z+build）
  
server:
  version: "1.0.7+6"  # 服务器版本号（格式: x.y.z+build）

compatibility:
  # 服务器支持的最小客户端版本（格式: x.y.z，不含构建号）
  min_client_version: "1.0.6"
  
  # 客户端支持的最小服务器版本（格式: x.y.z，不含构建号）
  min_server_version: "1.0.6"
```

### 版本号管理工具

使用 `scripts/version.sh` 脚本管理版本号：

```bash
# 显示所有版本号
./scripts/version.sh get

# 显示客户端版本号
./scripts/version.sh get client

# 显示服务器版本号
./scripts/version.sh get server

# 设置客户端版本号
./scripts/version.sh set client 1.2.3+10

# 设置服务器版本号
./scripts/version.sh set server 1.2.3+10

# 递增客户端版本号
./scripts/version.sh bump client minor

# 递增服务器版本号
./scripts/version.sh bump server patch

# 设置服务器要求的最小客户端版本
./scripts/version.sh set-min-version client 1.0.0

# 设置客户端要求的最小服务器版本
./scripts/version.sh set-min-version server 1.0.0

# 同步版本号到 pubspec.yaml（同步所有）
./scripts/version.sh sync

# 只同步客户端版本号
./scripts/version.sh sync client

# 只同步服务器版本号
./scripts/version.sh sync server
```

### 自动同步机制

**构建脚本会自动同步版本号：**

- 执行 `client/scripts/build.sh` 时，会自动从 `VERSION.yaml` 文件同步**客户端**版本号到 `client/pubspec.yaml`
- 执行 `server/scripts/build.sh` 时，会自动从 `VERSION.yaml` 文件同步**服务器**版本号到 `server/pubspec.yaml`，并复制 `VERSION.yaml` 到 `server/assets/VERSION.yaml`
- 执行 `client/scripts/deploy.sh` 或 `server/scripts/deploy.sh` 时，也会自动同步对应版本号

**无需手动操作：** 只需更新 `VERSION.yaml` 文件，构建时会自动同步。

## 版本兼容性检查

### 工作原理

1. **客户端连接时：**
   - 客户端在注册设备时发送自己的版本号
   - 服务器检查客户端版本是否满足 `MIN_CLIENT_VERSION` 要求
   - 如果版本过低，服务器拒绝连接并发送 `version_incompatible` 通知

2. **服务器响应时：**
   - 服务器在连接确认消息中包含服务器版本号
   - 客户端检查服务器版本是否满足 `MIN_SERVER_VERSION` 要求
   - 如果版本过低，客户端断开连接

### 版本兼容性配置

在 `VERSION.yaml` 文件中配置：

- `compatibility.min_client_version`: 服务器要求的最小客户端版本
- `compatibility.min_server_version`: 客户端要求的最小服务器版本

**示例：**

如果服务器升级到 2.0.0，要求客户端至少是 1.5.0：

```yaml
server:
  version: "2.0.0+1"

compatibility:
  min_client_version: "1.5.0"
```

如果客户端升级到 2.0.0，要求服务器至少是 1.5.0：

```yaml
client:
  version: "2.0.0+1"

compatibility:
  min_server_version: "1.5.0"
```

### 版本检查流程

```
客户端连接
    ↓
客户端发送版本号（registerDevice）
    ↓
服务器检查客户端版本
    ├─ 版本兼容 → 允许连接
    └─ 版本不兼容 → 拒绝连接，发送 version_incompatible 通知
    ↓
服务器发送连接确认（包含服务器版本号）
    ↓
客户端检查服务器版本
    ├─ 版本兼容 → 继续使用
    └─ 版本不兼容 → 断开连接，显示错误提示
```

## 在代码中读取版本号

### 客户端（Client）

```dart
import 'package:hello_knight_rcc/services/version_service.dart';
import 'package:hello_knight_rcc/services/version_compatibility_service.dart';

final versionService = VersionService();
final versionCompatibilityService = VersionCompatibilityService();

// 获取完整版本号（格式: x.y.z+build）
final version = await versionService.getVersion();

// 获取版本号部分（不含构建号，格式: x.y.z）
final versionNumber = await versionService.getVersionNumber();

// 获取构建号
final buildNumber = await versionService.getBuildNumber();

// 检查服务器版本兼容性
final (isCompatible, reason) = await versionCompatibilityService.checkServerVersion(serverVersion);
```

### 服务端（Server）

```dart
import 'package:helloknightrcc_server/services/version_service.dart';
import 'package:helloknightrcc_server/services/version_compatibility_service.dart';

final versionService = VersionService();
final versionCompatibilityService = VersionCompatibilityService();

// 获取完整版本号（格式: x.y.z+build）
final version = await versionService.getVersion();

// 获取版本号部分（不含构建号，格式: x.y.z）
final versionNumber = await versionService.getVersionNumber();

// 检查客户端版本兼容性
final (isCompatible, reason) = await versionCompatibilityService.checkClientVersion(clientVersion);
```

版本号服务使用 `package_info_plus` 包从 `pubspec.yaml` 读取版本号，确保版本号与构建时一致。

## 版本号更新建议

### 主版本号（Major）
- 不兼容的 API 更改
- 重大功能变更
- **通常需要更新最小版本要求**

### 次版本号（Minor）
- 向后兼容的功能添加
- 新功能
- **可能需要更新最小版本要求（如果新功能需要客户端支持）**

### 修订号（Patch）
- 向后兼容的 bug 修复
- 小改进
- **通常不需要更新最小版本要求**

### 构建号（Build）
- 每次构建递增
- 用于区分同一版本的多次构建
- **不影响版本兼容性**

## 工作流程示例

### 示例 1: 客户端独立更新

```bash
# 1. 更新客户端版本号（例如：1.0.0 -> 1.1.0）
./scripts/version.sh bump client minor

# 2. 构建客户端（会自动同步版本号）
cd client && ./scripts/deploy.sh --release --macos

# 服务器版本号保持不变
```

### 示例 2: 服务器独立更新

```bash
# 1. 更新服务器版本号（例如：1.0.0 -> 1.1.0）
./scripts/version.sh bump server minor

# 2. 如果需要，更新最小客户端版本要求
./scripts/version.sh set-min-version client 1.0.0

# 3. 构建服务器（会自动同步版本号）
cd server && ./scripts/deploy.sh --release
```

### 示例 3: 不兼容更新（需要更新最小版本要求）

```bash
# 服务器升级到 2.0.0，要求客户端至少是 1.5.0

# 1. 更新服务器版本号
./scripts/version.sh set server 2.0.0+1

# 2. 更新最小客户端版本要求
./scripts/version.sh set-min-version client 1.5.0

# 3. 构建服务器
cd server && ./scripts/deploy.sh --release

# 旧版本客户端（< 1.5.0）将无法连接
```

## 版本号一致性

- **单一数据源：** `VERSION.yaml` 文件是版本号的唯一来源
- **独立管理：** 客户端和服务器版本号独立管理
- **自动同步：** 构建脚本自动同步到对应的 `pubspec.yaml`
- **代码读取：** 应用代码通过 `VersionService` 从 `pubspec.yaml` 读取（由 Flutter 的 `package_info_plus` 提供）
- **运行时读取：** Server 端从 `assets/VERSION.yaml` 读取版本兼容性配置（打包到 APK 中）

## 注意事项

1. **不要手动编辑 pubspec.yaml 中的版本号**：版本号应该通过 `VERSION.yaml` 文件和 `version.sh` 脚本管理
2. **构建前会自动同步**：执行构建脚本时，版本号会自动从 `VERSION.yaml` 文件同步到对应的 `pubspec.yaml`
3. **版本号格式**：必须遵循 `x.y.z+build` 格式
4. **版本号服务**：代码中应使用 `VersionService` 读取版本号，而不是硬编码
5. **版本兼容性**：更新版本时，注意更新最小版本要求，确保旧版本客户端/服务器无法连接（如果需要）
6. **独立更新**：客户端和服务器可以独立更新版本号，互不影响
7. **YAML 格式**：使用 YAML 格式更易读易写，所有版本配置都存储在 `VERSION.yaml` 文件中

## 与 Git 集成（可选）

虽然版本号不依赖 Git，但可以配合 Git 使用：

```bash
# 更新客户端版本号
./scripts/version.sh bump client minor

# 提交版本更新
git add VERSION.yaml client/pubspec.yaml
git commit -m "Bump client version to $(./scripts/version.sh get client)"

# 创建标签（可选）
git tag "client-v$(./scripts/version.sh get client | sed 's/+.*//')"
```

**注意：** Git 标签是可选的，版本号管理不依赖 Git。

## YAML 格式的优势

使用 YAML 格式相比旧的 key=value 格式有以下优势：

1. **更易读**：结构化的层次结构，一目了然
2. **更易写**：支持注释，格式更灵活
3. **类型安全**：YAML 解析器可以验证数据类型
4. **扩展性好**：未来可以轻松添加新的配置项
5. **工具支持**：可以使用标准的 YAML 工具和库
