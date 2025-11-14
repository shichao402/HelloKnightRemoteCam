# 构建脚本说明

## 脚本架构

项目采用模块化脚本设计，将构建流程拆分为独立的模块，便于复用和维护。

## Client 脚本（macOS/Windows）

### 模块化脚本

#### `kill_process.sh`
终止已有进程
```bash
./client/scripts/kill_process.sh
```

#### `build.sh`
构建应用
```bash
# macOS Debug 构建
./client/scripts/build.sh --debug --macos

# macOS Release 构建
./client/scripts/build.sh --release --macos

# Windows Debug 构建
./client/scripts/build.sh --debug --windows

# Windows Release 构建
./client/scripts/build.sh --release --windows
```

#### `start.sh`
启动应用
```bash
# macOS
./client/scripts/start.sh debug macos

# Windows
./client/scripts/start.sh debug windows
```

#### `deploy.sh`
完整部署流程（组合调用上述模块）
```bash
# macOS Debug 部署
./client/scripts/deploy.sh --debug --macos

# macOS Release 部署（自动启动）
./client/scripts/deploy.sh -y --release --macos

# Windows Release 部署
./client/scripts/deploy.sh --release --windows
```

### 向后兼容脚本

#### `deploy_mac.sh`
macOS 部署脚本（调用新的模块化脚本）
```bash
./client/scripts/deploy_mac.sh        # Debug 构建
./client/scripts/deploy_mac.sh -y     # Debug 构建并自动启动
```

## Server 脚本（Android）

### 模块化脚本

#### `kill_process.sh`
终止已有进程（通过 adb）
```bash
./server/scripts/kill_process.sh
```

#### `build.sh`
构建 APK
```bash
# Debug 构建
./server/scripts/build.sh --debug

# Release 构建
./server/scripts/build.sh --release
```

#### `install.sh`
安装 APK 到设备
```bash
# 安装 Debug APK
./server/scripts/install.sh debug

# 安装 Release APK
./server/scripts/install.sh release
```

#### `start.sh`
启动应用（通过 adb）
```bash
./server/scripts/start.sh
```

#### `deploy.sh`
完整部署流程（组合调用上述模块）
```bash
# Debug 部署
./server/scripts/deploy.sh --debug

# Release 部署（自动启动）
./server/scripts/deploy.sh -y --release
```

### 向后兼容脚本

#### `deploy_android.sh`
Android 部署脚本（调用新的模块化脚本）
```bash
./server/scripts/deploy_android.sh        # Debug 构建、安装
./server/scripts/deploy_android.sh -y     # Debug 构建、安装并自动启动
```

## GitHub Actions 使用

GitHub Actions 工作流直接使用模块化的构建脚本：

```yaml
# macOS 构建
- name: Build macOS app
  run: |
    cd client
    ./scripts/build.sh --release --macos

# Windows 构建
- name: Build Windows app
  run: |
    cd client
    bash scripts/build.sh --release --windows

# Android 构建
- name: Build Android APK
  run: |
    cd server
    ./scripts/build.sh --release
```

## 脚本优势

1. **模块化**：每个脚本只负责一个功能，便于维护和测试
2. **可复用**：GitHub Actions 和本地开发使用相同的构建脚本
3. **向后兼容**：保留原有脚本，通过包装器调用新脚本
4. **灵活性**：可以单独调用任意模块，也可以使用组合脚本

## 使用示例

### 仅构建（不安装、不启动）
```bash
# Client macOS
cd client && ./scripts/build.sh --release --macos

# Server Android
cd server && ./scripts/build.sh --release
```

### 完整部署流程
```bash
# Client macOS（自动启动）
cd client && ./scripts/deploy.sh -y --release --macos

# Server Android（自动启动）
cd server && ./scripts/deploy.sh -y --release
```

### 手动步骤
```bash
# 1. 终止进程
./server/scripts/kill_process.sh

# 2. 构建
./server/scripts/build.sh --release

# 3. 安装
./server/scripts/install.sh release

# 4. 启动
./server/scripts/start.sh
```

