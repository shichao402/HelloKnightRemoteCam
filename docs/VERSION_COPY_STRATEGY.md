# VERSION.yaml 拷贝策略

## 设计原则

**单一数据源原则**：所有 VERSION.yaml 的拷贝逻辑都应该在构建脚本中完成，确保本地部署和 CI/CD 流水线使用相同的逻辑。

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

## 相关文件

- `client/scripts/build.sh`: 客户端构建脚本
- `server/scripts/build.sh`: 服务器构建脚本
- `scripts/lib/version_manager.py`: 版本管理模块（提供 `copy-to-assets` 命令）
- `.github/workflows/build-client-macos.yml`: macOS 构建工作流
- `.github/workflows/build-client-windows.yml`: Windows 构建工作流
- `.github/workflows/build-server-android.yml`: Android 构建工作流

## 历史问题

- **问题**：之前只在 CI/CD 流水线中拷贝 VERSION.yaml，本地部署时没有拷贝
- **原因**：拷贝逻辑分散在多个地方，没有统一管理
- **解决方案**：将所有拷贝逻辑集中到构建脚本中，确保本地和 CI/CD 使用相同的逻辑

