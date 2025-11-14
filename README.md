# HelloKnightRemoteCam - 远程相机控制系统

一个基于Flutter的局域网手机远程拍照/录像控制系统，支持无损录像、实时预览、文件管理和断点续传下载。

## 项目结构

```
HelloKnightRemoteCam/
├── client/          # 主控端应用（Mac/Windows/Android）
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/         # 数据模型
│   │   ├── services/       # 核心服务
│   │   └── screens/        # 用户界面
│   └── scripts/            # 部署脚本
│
└── server/          # 手机端服务应用（Android）
    ├── lib/
    │   ├── main.dart
    │   ├── models/         # 数据模型
    │   ├── services/       # 核心服务
    │   └── screens/        # 用户界面
    └── scripts/            # 部署脚本
```

## 核心特性

### ✨ 功能特性
- 📸 **远程拍照** - 通过主控端远程控制手机拍照
- 🎥 **高质量录像** - 支持超高质量无损录像（ResolutionPreset.ultraHigh）
- 👁️ **实时预览** - MJPEG流实时预览相机画面
- 📁 **文件管理** - 查看、下载、删除照片和视频
- ⚙️ **灵活设置** - 可配置录像质量、拍照质量、音频开关等

### 🚀 技术亮点
- ⏸️ **断点续传** - 支持HTTP Range请求，下载中断后可继续
- 🔄 **双并发下载** - 最多2个文件同时下载，智能队列管理
- 💾 **进度持久化** - 下载进度保存到SQLite，应用重启后自动恢复
- 🔁 **自动重试** - 下载失败自动重试最多3次
- 🎯 **状态管理** - 录像中锁定设置，防止误操作
- 📱 **跨平台** - 主控端支持Mac/Windows/Android，手机端支持Android

## 技术栈

- **Framework**: Flutter 3.0+
- **相机控制**: camera ^0.10.5
- **HTTP服务**: shelf ^1.4.1 + shelf_router ^1.1.4
- **网络请求**: dio ^5.4.0 (客户端使用dart:io HttpClient)
- **数据持久化**: shared_preferences ^2.2.2 + sqflite ^2.3.0
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

#### 1. 手机端（服务端）部署

**Android设备：**

```bash
cd server

# 方式1：使用部署脚本（推荐）
./scripts/deploy_android.sh

# 方式2：手动部署
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.remote_cam_server/.MainActivity
```

#### 2. 主控端部署

**Mac平台：**

```bash
cd client

# 方式1：使用部署脚本（推荐）
./scripts/deploy.sh --debug --macos

# 方式2：向后兼容脚本
./scripts/deploy_mac.sh

# 方式3：直接运行
flutter run -d macos
```

**Windows平台：**

```bash
cd client

# 方式1：使用部署脚本（推荐，需要 Git Bash 或 WSL）
bash scripts/deploy.sh --debug --windows

# 方式2：向后兼容脚本（需要 Git Bash 或 WSL）
scripts\deploy_windows.bat

# 方式3：直接运行
flutter run -d windows
```

**Android平台（Server）：**

```bash
cd server

# 方式1：使用部署脚本（推荐）
./scripts/deploy.sh --debug

# 方式2：向后兼容脚本
./scripts/deploy_android.sh
```

## 使用指南

### 手机端（服务端）设置

1. **启动应用** - 在Android手机上启动"远程相机服务端"
2. **授予权限** - 允许相机、麦克风、存储权限
3. **启动服务器** - 点击"启动服务器"按钮
4. **记录IP地址** - 记下显示的IP地址（例如：192.168.1.100）

### 主控端使用

1. **连接设备**
   - 输入手机端显示的IP地址
   - 输入端口（默认8080）
   - 点击"连接"（应用会自动连接）

2. **相机控制**
   - **拍照**：点击"拍照"按钮立即拍照
   - **录像**：点击"开始录像"开始录制，再次点击停止
   - **预览**：自动显示实时预览画面（录像时显示静态图）

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

## API文档

### HTTP端点

**HTTP端点：**
- `GET /ping` - 健康检查
- `POST /capture` - 拍照
- `POST /recording/start` - 开始录像
- `POST /recording/stop` - 停止录像
- `GET /files` - 获取文件列表
- `GET /file/download?path=<path>` - 下载文件（支持Range）
- `DELETE /file/delete?path=<path>` - 删除文件
- `GET /settings` - 获取当前设置
- `GET /settings/status` - 获取设置状态（是否可更改）
- `POST /settings/update` - 更新设置
- `GET /preview/stream` - MJPEG预览流

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

## 调试指南

### Mac平台调试

```bash
cd client
flutter run -d macos --debug
```

### Android手机端调试

```bash
cd server
flutter run -d <device_id> --debug

# 查看设备列表
flutter devices
```

### 查看日志

```bash
# Flutter日志
flutter logs

# Android日志
adb logcat | grep flutter
```

## 常见问题

### Q: 连接失败怎么办？
A: 
1. 确保主控端和手机端在同一局域网
2. 检查防火墙设置，允许8080端口
3. 确认手机端服务器已启动
4. 检查IP地址是否正确

### Q: 预览画面无法显示？
A: 
1. 检查相机权限是否授予
2. 确认网络连接正常
3. 尝试重启手机端应用

### Q: 下载中断后如何继续？
A: 下载管理器自动支持断点续传，失败后会自动重试。也可以在下载列表中手动点击"恢复"按钮。

### Q: 录像时为什么无法更改设置？
A: 为保证录像质量和稳定性，录像过程中锁定了设置更改。请先停止录像再修改设置。

### Q: 如何提高录像质量？
A: 在设置中将录像质量调整为"超高"，但会占用更多存储空间。

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

## 许可证

本项目仅供学习和研究使用。

## 版本历史

### v1.0.0 (2025-11-09)
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

