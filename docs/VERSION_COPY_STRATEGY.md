# VERSION.yaml 拷贝策略和版本号读取统一逻辑

## 设计原则

### 1. 单一数据源原则
所有 VERSION.yaml 的拷贝逻辑都应该在构建脚本中完成，确保本地部署和 CI/CD 流水线使用相同的逻辑。

### 2. 统一的版本号读取逻辑
**客户端和服务器端都应该使用相同的版本号读取逻辑**：

1. **优先从 VERSION.yaml 读取**（从 `assets/VERSION.yaml`）
2. **如果读不到，回退到 pubspec.yaml**（通过 `package_info_plus`）
3. **如果还是失败，使用默认版本号**

这样可以确保版本号始终与根目录的 VERSION.yaml 保持一致。

## 当前实现

### 构建脚本（单一数据源）

所有平台的构建脚本都负责拷贝 VERSION.yaml 到构建输出目录：

1. **客户端 macOS** (`client/scripts/build.sh`)
   - 拷贝到：`app bundle/Contents/Resources/VERSION.yaml`
   - 位置：构建完成后，在 app bundle 创建之后

2. **客户端 Windows** (`client/scripts/build.sh`)
   - 拷贝到：`build/windows/x64/runner/Debug/VERSION.yaml`（或 Release）
   - 位置：构建完成后，在构建输出目录创建之后

3. **服务器 Android** (`server/scripts/build.sh`)
   - 拷贝到：`server/assets/VERSION.yaml`
   - 使用：`version_manager.py copy-to-assets` 命令
   - 位置：构建之前，确保 assets 目录存在

### CI/CD 流水线

**重要**：CI/CD 流水线完全依赖构建脚本，不包含独立的拷贝逻辑。

#### 构建工作流调用方式

```yaml
# macOS
- name: Build macOS app
  run: |
    cd client
    ./scripts/build.sh --release --macos

# Windows
- name: Build Windows app
  run: |
    cd client
    bash scripts/build.sh --release --windows

# Android
- name: Build Android APK
  run: |
    cd server
    ./scripts/build.sh --release
```

#### 版本号同步

流水线在构建前会同步版本号到 pubspec.yaml：

```yaml
# 使用统一的版本管理模块提取和同步版本号
python3 scripts/lib/version_manager.py extract client --sync client/pubspec.yaml
python3 scripts/lib/version_manager.py extract server --sync server/pubspec.yaml
```

**注意**：`extract --sync` 对于 server 会自动调用 `copy_to_assets()`，但这与构建脚本中的拷贝是重复的（无害）。为了统一，建议：

1. **保持现状**：构建脚本中的拷贝逻辑是主要逻辑
2. **或者**：移除 `extract --sync` 中的自动拷贝，只保留构建脚本中的拷贝

## 修改指南

### ✅ 正确的做法

**所有 VERSION.yaml 拷贝逻辑都应该在构建脚本中**：

1. 修改 `client/scripts/build.sh` 或 `server/scripts/build.sh`
2. 确保拷贝逻辑在构建完成后执行
3. 测试本地部署和 CI/CD 流水线

### ❌ 错误的做法

**不要在以下位置添加独立的拷贝逻辑**：

1. ❌ GitHub Actions workflow 文件中
2. ❌ 独立的脚本文件（除非被构建脚本调用）
3. ❌ 其他部署脚本中

## 验证清单

修改拷贝逻辑后，确保：

- [ ] 本地部署（`./scripts/deploy.sh`）正常工作
- [ ] CI/CD 流水线构建成功
- [ ] 构建输出中包含 VERSION.yaml
- [ ] 应用可以正确读取版本信息

## 版本号读取统一逻辑

### 客户端和服务器端实现

**客户端** (`client/lib/services/version_service.dart`):
- 使用 `VersionFileProvider` 从 `assets/VERSION.yaml` 读取
- 失败时回退到 `package_info_plus`（从 `pubspec.yaml` 读取）

**服务器端** (`server/lib/services/version_service.dart`):
- 使用 `VersionFileProvider` 从 `assets/VERSION.yaml` 读取
- 失败时回退到 `package_info_plus`（从 `pubspec.yaml` 读取）

### 读取优先级

1. ✅ **assets/VERSION.yaml**（优先）
   - 从根目录的 VERSION.yaml 同步而来
   - 确保版本号与根目录保持一致

2. ⚠️ **pubspec.yaml**（回退）
   - 通过 `package_info_plus` 读取
   - 仅在 assets/VERSION.yaml 不存在时使用

3. 🔄 **默认版本号**（最后回退）
   - `1.0.0+1`
   - 仅在所有读取方式都失败时使用

### 相关服务文件

**客户端**:
- `client/lib/services/version_file_provider.dart`: 版本文件提供者
- `client/lib/services/version_parser.dart`: 版本解析器
- `client/lib/services/version_fallback_service.dart`: 回退服务

**服务器端**:
- `server/lib/services/version_file_provider.dart`: 版本文件提供者
- `server/lib/services/version_parser.dart`: 版本解析器
- `server/lib/services/version_fallback_service.dart`: 回退服务

**共享**:
- `shared/lib/services/version_parser_service.dart`: 版本解析服务（客户端和服务器端共享）

## 相关文件

- `client/scripts/build.sh`: 客户端构建脚本
- `server/scripts/build.sh`: 服务器构建脚本
- `scripts/lib/version_manager.py`: 版本管理模块（提供 `copy-to-assets` 命令）
- `.github/workflows/build-client-macos.yml`: macOS 构建工作流
- `.github/workflows/build-client-windows.yml`: Windows 构建工作流
- `.github/workflows/build-server-android.yml`: Android 构建工作流

## 历史问题

- **问题 1**：之前只在 CI/CD 流水线中拷贝 VERSION.yaml，本地部署时没有拷贝
- **问题 2**：客户端和服务器端使用不同的版本号读取逻辑
- **问题 3**：服务器端直接从 pubspec.yaml 读取，没有优先从 VERSION.yaml 读取
- **原因**：拷贝逻辑分散在多个地方，版本号读取逻辑不统一
- **解决方案**：
  1. 将所有拷贝逻辑集中到构建脚本中，确保本地和 CI/CD 使用相同的逻辑
  2. 统一客户端和服务器端的版本号读取逻辑，都优先从 VERSION.yaml 读取

