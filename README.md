# HelloKnightRemoteCam - 远程相机控制系统

一个基于Flutter的局域网手机远程拍照/录像控制系统，支持无损录像、实时预览、文件管理和断点续传下载。

## 项目结构

```
HelloKnightRemoteCam/
├── client/          # 主控端应用（Mac/Windows）
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/         # 数据模型
│   │   ├── services/       # 核心服务
│   │   ├── screens/        # 用户界面
│   │   └── widgets/        # UI组件
│   └── scripts/            # 部署脚本
│
├── server/          # 手机端服务应用（Android）
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/         # 数据模型
│   │   ├── services/       # 核心服务
│   │   └── screens/        # 用户界面
│   └── scripts/            # 部署脚本
│
├── docs/            # 项目文档
│   ├── AUTH_ARCHITECTURE.md      # 认证架构文档
│   ├── FILE_STATE_UPDATE.md      # 文件状态更新最佳实践
│   ├── PREVIEW_SIZE_OPTIMIZATION.md  # 预览尺寸数据流优化
│   ├── PREVIEW_ROTATION.md       # 预览旋转和转置实现
│   ├── SCRIPTS.md                # 脚本使用说明
│   └── VERSION_MANAGEMENT.md     # 版本管理指南
│
├── scripts/        # 项目级脚本
│   ├── collect_all_logs.sh       # 日志收集脚本
│   ├── create_release.sh         # 发布脚本
│   └── version.sh                # 版本管理脚本
│
└── VERSION.yaml    # 版本号配置文件（YAML格式，单一数据源）
```

## 核心特性

### ✨ 功能特性
- 📸 **远程拍照** - 通过主控端远程控制手机拍照
- 🎥 **高质量录像** - 支持超高质量无损录像（ResolutionPreset.ultraHigh）
- 👁️ **实时预览** - MJPEG流实时预览相机画面，支持旋转和自适应缩放
- 📁 **文件管理** - 查看、下载、删除照片和视频
- ⚙️ **灵活设置** - 可配置录像质量、拍照质量、音频开关等
- 🔐 **版本兼容性检查** - 自动检查客户端和服务器版本兼容性
- 📝 **统一日志系统** - 独立的日志文件，便于调试和问题排查

### 🚀 技术亮点
- ⏸️ **断点续传** - 支持HTTP Range请求，下载中断后可继续
- 🔄 **双并发下载** - 最多2个文件同时下载，智能队列管理
- 💾 **进度持久化** - 下载进度保存到SQLite，应用重启后自动恢复
- 🔁 **自动重试** - 下载失败自动重试最多3次
- 🎯 **状态管理** - 录像中锁定设置，防止误操作
- 📱 **跨平台** - 主控端支持Mac/Windows，手机端支持Android
- 🔒 **认证架构** - 统一的认证中间件，支持版本检查和用户认证（预留）
- 📊 **操作日志** - 记录所有关键操作，便于追踪和审计

## 技术栈

- **Framework**: Flutter 3.0+
- **相机控制**: camera ^0.10.5
- **HTTP服务**: shelf ^1.4.1 + shelf_router ^1.1.4
- **WebSocket**: shelf_web_socket ^1.0.4 + web_socket_channel ^2.4.0
- **网络请求**: dio ^5.4.0 (客户端使用dart:io HttpClient)
- **数据持久化**: shared_preferences ^2.2.2 + sqflite ^2.3.0
- **媒体处理**: image ^4.1.3
- **文件操作**: path_provider ^2.1.1 + path ^1.8.3
- **权限管理**: permission_handler ^11.0.1
- **版本管理**: package_info_plus ^8.0.0
- **MJPEG流**: mjpeg_stream ^1.0.1 (实时预览流)
- **Android最低版本**: API 24 (Android 7.0)

## 快速开始

### 前置要求

1. 安装Flutter SDK（3.0或更高版本）
2. 配置Android SDK（用于Android构建）
3. Mac系统需要Xcode（用于macOS构建）
4. Windows系统需要Visual Studio（用于Windows构建）

### 安装依赖

```bash
# 主控端
cd client
flutter pub get

# 手机端
cd ../server
flutter pub get
```

### 部署方式

**⚠️ 重要：项目使用统一的脚本系统进行部署，请使用预置脚本，不要手动执行Flutter命令。**

#### 1. 手机端（服务端）部署

**Android设备：**

```bash
cd server

# 推荐：使用部署脚本（自动同步版本号）
./scripts/deploy.sh --debug

# 或使用向后兼容脚本
./scripts/deploy_android.sh
```

#### 2. 主控端部署

**Mac平台：**

```bash
cd client

# 推荐：使用部署脚本（自动同步版本号）
./scripts/deploy.sh --debug --macos

# 或使用向后兼容脚本
./scripts/deploy_mac.sh
```

**Windows平台：**

```bash
cd client

# 推荐：使用部署脚本（需要 Git Bash 或 WSL）
bash scripts/deploy.sh --debug --windows

# 或使用向后兼容脚本（需要 Git Bash 或 WSL）
scripts\deploy_windows.bat
```

**更多脚本使用说明请参考：[docs/SCRIPTS.md](docs/SCRIPTS.md)**

## 使用指南

### 手机端（服务端）设置

1. **启动应用** - 在Android手机上启动"远程相机服务端"
2. **授予权限** - 允许相机、麦克风、存储权限
3. **启动服务器** - 点击"启动服务器"按钮
4. **记录IP地址** - 记下显示的IP地址（例如：192.168.1.100）
5. **启用调试模式**（可选）- 在设置中启用调试模式以记录详细日志

### 主控端使用

1. **连接设备**
   - 输入手机端显示的IP地址
   - 输入端口（默认8080）
   - 点击"连接"（应用会自动连接）
   - 版本不兼容时会自动提示

2. **相机控制**
   - **拍照**：点击"拍照"按钮立即拍照
   - **录像**：点击"开始录像"开始录制，再次点击停止
   - **预览**：自动显示实时预览画面（录像时显示静态图）
   - **预览旋转**：支持方向锁定和手动旋转预览画面
   - **预览适配**：预览画面自动适配窗口大小，保持原始比例

3. **设置管理**
   - 点击右上角设置图标
   - 调整录像质量、拍照质量
   - 启用/禁用音频录制
   - **注意**：录像中无法更改设置

4. **文件管理**
   - 点击文件夹图标进入文件管理
   - **照片** / **视频**：查看所有文件
   - **下载**：点击下载按钮添加到下载队列
   - **删除**：点击删除按钮删除远程文件
   - **下载管理**：
     - 最多2个文件同时下载
     - 支持暂停/恢复下载
     - 失败自动重试

## 版本管理

项目使用统一的版本管理系统，版本号存储在根目录的 `VERSION.yaml` 文件中（YAML格式）。

### 查看版本号

```bash
# 查看所有版本号
./scripts/version.sh get

# 查看客户端版本号
./scripts/version.sh get client

# 查看服务器版本号
./scripts/version.sh get server
```

### 更新版本号

```bash
# 设置客户端版本号
./scripts/version.sh set client 1.0.3+1

# 设置服务器版本号
./scripts/version.sh set server 1.0.3+1

# 递增版本号
./scripts/version.sh bump client minor
./scripts/version.sh bump server patch
```

**注意：** 构建脚本会自动从 `VERSION.yaml` 文件同步版本号到 `pubspec.yaml`，无需手动操作。

**详细说明请参考：[docs/VERSION_MANAGEMENT.md](docs/VERSION_MANAGEMENT.md)**

## 日志系统

项目使用统一的日志服务，所有日志写入独立文件，便于调试和问题排查。

### 日志位置

- **手机端日志**：`/data/data/com.firoyang.helloknightrcc_server/files/logs/debug_*.log`
- **客户端日志**：`~/Library/Application Support/com.example.helloKnightRCC/logs/client_debug_*.log` (Mac)

### 收集日志

**使用日志收集脚本（推荐）：**

```bash
# 收集所有日志（手机端和客户端）
./scripts/collect_all_logs.sh
```

脚本会自动：
- 检测Android设备连接
- 收集手机端日志文件
- 收集客户端日志文件
- 显示日志文件位置和内容

### 启用调试模式

- **手机端**：在应用设置中启用"调试模式"
- **客户端**：在应用设置中启用"调试模式"

**注意：** 调试模式默认关闭，以提升性能。仅在需要调试时启用。

## API文档

### HTTP端点

**基础端点：**
- `GET /ping` - 健康检查
- `GET /version` - 获取服务器版本信息
- `GET /device/info` - 获取设备信息

**相机控制：**
- `POST /capture` - 拍照
- `POST /recording/start` - 开始录像
- `POST /recording/stop` - 停止录像
- `GET /camera/status` - 获取相机状态
- `GET /camera/capabilities` - 获取相机能力

**文件管理：**
- `GET /files` - 获取文件列表
- `GET /file/download?path=<path>` - 下载文件（支持Range）
- `DELETE /file/delete?path=<path>` - 删除文件
- `POST /file/star?path=<path>` - 标记/取消标记文件

**设置管理：**
- `GET /settings` - 获取当前设置
- `GET /settings/status` - 获取设置状态（是否可更改）
- `POST /settings/update` - 更新设置

**预览流：**
- `GET /preview/stream` - MJPEG预览流

**WebSocket：**
- `WS /ws` - WebSocket连接（用于实时通知）

### 认证机制

所有API请求都会经过认证中间件：
1. **版本检查** - 检查客户端版本是否满足最低要求
2. **用户认证** - 预留接口，未来可扩展用户认证

**详细说明请参考：[docs/AUTH_ARCHITECTURE.md](docs/AUTH_ARCHITECTURE.md)**

## 配置说明

### 相机质量配置

```dart
CameraSettings(
  videoQuality: 'ultra',  // ultra/high/medium/low
  photoQuality: 'ultra',  // ultra/high/medium/low
  enableAudio: true,      // 录像时录制音频
  previewFps: 10,         // 预览帧率
  previewQuality: 70,     // 预览JPEG质量 (0-100)
)
```

### 下载管理器配置

- **最大并发数**: 2
- **最大重试次数**: 3
- **重试延迟**: 指数退避（2秒 × 重试次数）
- **进度保存**: SQLite数据库

### 版本兼容性配置

在 `VERSION.yaml` 文件中配置：
- `compatibility.min_client_version`: 服务器要求的最小客户端版本
- `compatibility.min_server_version`: 客户端要求的最小服务器版本

## 调试指南

### 使用部署脚本

**所有部署操作必须使用预置脚本：**

```bash
# 手机端部署
cd server && ./scripts/deploy.sh --debug

# Mac客户端部署
cd client && ./scripts/deploy.sh --debug --macos

# Windows客户端部署
cd client && bash scripts/deploy.sh --debug --windows
```

### 收集日志

**调试时必须使用日志收集脚本：**

```bash
# 收集所有日志
./scripts/collect_all_logs.sh
```

**禁止手动操作：**
- ❌ 禁止手动使用adb命令
- ❌ 禁止手动访问日志文件路径
- ❌ 禁止使用tail命令查看日志（会错过重要信息）

### 查看日志

日志收集脚本会自动显示日志内容。也可以手动查看日志文件：

```bash
# 手机端日志（需要adb）
adb shell run-as com.firoyang.helloknightrcc_server cat /data/data/com.firoyang.helloknightrcc_server/files/logs/debug_*.log

# 客户端日志（Mac）
cat ~/Library/Application\ Support/com.example.helloKnightRCC/logs/client_debug_*.log
```

## 常见问题

### Q: 连接失败怎么办？
A: 
1. 确保主控端和手机端在同一局域网
2. 检查防火墙设置，允许8080端口
3. 确认手机端服务器已启动
4. 检查IP地址是否正确
5. 检查版本兼容性（查看版本号）

### Q: 预览画面无法显示？
A: 
1. 检查相机权限是否授予
2. 确认网络连接正常
3. 尝试重启手机端应用
4. 启用调试模式查看详细日志

### Q: 预览画面方向不正确？
A: 
1. 检查方向锁定状态（锁定/解锁按钮）
2. 如果已锁定，点击旋转按钮手动调整方向
3. 如果未锁定，预览会自动跟随设备方向
4. 预览窗口会自动适配，保持原始比例

### Q: 下载中断后如何继续？
A: 下载管理器自动支持断点续传，失败后会自动重试。也可以在下载列表中手动点击"恢复"按钮。

### Q: 录像时为什么无法更改设置？
A: 为保证录像质量和稳定性，录像过程中锁定了设置更改。请先停止录像再修改设置。

### Q: 如何提高录像质量？
A: 在设置中将录像质量调整为"超高"，但会占用更多存储空间。

### Q: 版本不兼容怎么办？
A: 
1. 检查客户端和服务器版本号
2. 查看 `VERSION.yaml` 文件中的最小版本要求
3. 更新到兼容的版本

## 项目文档

- [认证架构文档](docs/AUTH_ARCHITECTURE.md) - 认证系统设计和使用说明
- [文件状态更新最佳实践](docs/FILE_STATE_UPDATE.md) - UI更新优化指南
- [脚本使用说明](docs/SCRIPTS.md) - 部署脚本详细说明
- [版本管理指南](docs/VERSION_MANAGEMENT.md) - 版本号管理详细说明
- [预览尺寸优化](docs/PREVIEW_SIZE_OPTIMIZATION.md) - 预览尺寸数据流优化
- [预览旋转实现](docs/PREVIEW_ROTATION.md) - 预览旋转和转置实现文档

## 开发规范

### 日志使用规范

**严格禁止使用 `print()` 语句，必须使用统一的日志服务：**

- **客户端**：使用 `ClientLoggerService`
- **手机端**：使用 `LoggerService`

**详细规范请参考项目根目录的 `.cursorrules` 文件。**

### 脚本使用规范

**所有部署和调试操作必须使用预置脚本：**
- 部署：使用 `scripts/deploy.sh` 或向后兼容脚本
- 日志收集：使用 `scripts/collect_all_logs.sh`
- 版本管理：使用 `scripts/version.sh`

**禁止手动执行Flutter命令或adb命令。**

## 未来优化方向

### 可选升级：双流预览（方案A+C）
当前方案在录像时使用静态预览。如需录像时也保持实时预览，可以升级到原生双流方案：

**实现方式：**
- Android: Camera2 API 配置双输出（VideoOutput + ImageOutput）
- iOS: AVFoundation 配置双输出
- 预计工作量：7-10天

**优势：**
- 录像时保持实时预览
- 适用于需要持续监控的场景

**架构支持：**
当前架构已预留抽象接口，升级时客户端无需改动。

## 开发团队

本项目由AI助手协助完成，基于以下设计原则：
- 模块化设计，易于扩展
- 状态驱动UI，降低耦合
- 注重用户体验和错误处理
- 优先考虑稳定性和性能
- 统一的日志和版本管理系统

## 许可证

本项目仅供学习和研究使用。

## 版本历史

### v1.0.3+1 (当前版本)
- ✅ 预览旋转和转置功能
- ✅ 方向锁定和手动旋转
- ✅ 预览自适应缩放（contain逻辑）
- ✅ MJPEG流优化（使用mjpeg_stream包）
- ✅ 预览窗口可调整大小
- ✅ 预览尺寸数据流优化

### v1.0.2+1
- ✅ 版本管理系统
- ✅ 统一日志系统
- ✅ 认证架构（版本检查）
- ✅ WebSocket实时通知
- ✅ 文件星标功能
- ✅ 设备信息获取
- ✅ 模块化脚本系统

### v1.0.0
- ✅ 初始版本发布
- ✅ 基础拍照、录像功能
- ✅ 实时预览（MJPEG流）
- ✅ 文件管理（查看、下载、删除）
- ✅ 断点续传下载
- ✅ 双并发下载队列
- ✅ 设置管理与状态锁定
- ✅ 自动连接功能
- ✅ 跨平台支持（Mac/Windows/Android）

---

**享受远程相机控制的便利！** 📸🎥
